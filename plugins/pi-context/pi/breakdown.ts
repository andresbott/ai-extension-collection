// Pure core of /context: turns what the model currently sees (system prompt
// sections, tool declarations, messages) into a Claude-Code-style breakdown by
// category, plus per-item lists. No pi imports; fully unit-tested.
//
// Token counts are estimates (chars / 4, the same heuristic pi uses). The total
// comes from pi's own usage number when it has one, so only the split between
// categories is estimated; "Messages" absorbs the difference.

/** A tool as declared to the model. Only the name is relied on; the rest is only stringified. */
export interface ToolDecl {
  name: string;
  description?: unknown;
  parameters?: unknown;
}

/** Where a tool came from, from pi.getAllTools(). Used to tell built-in, extension, and MCP tools apart. */
export interface ToolMeta {
  name: string;
  sourcePath?: string;
  namespace?: string;
}

/** The system prompt and tools the model has: unsectioned text, named sections, and tool declarations. */
export interface SystemState {
  content: string;
  sections: Record<string, string>;
  tools: ToolDecl[];
}

export type CategoryId =
  | "systemPrompt"
  | "systemTools"
  | "extensionTools"
  | "mcpTools"
  | "extensionPrompts"
  | "memoryFiles"
  | "skills"
  | "messages";

export interface Category {
  id: CategoryId;
  label: string;
  tokens: number;
}

export interface DetailItem {
  name: string;
  tokens: number;
}

export interface DetailGroup {
  title: string;
  items: DetailItem[];
}

/** Plain data, stored as the session entry the renderer draws. */
export interface ContextBreakdown {
  model: string;
  contextWindow: number;
  usedTokens: number;
  /** True when pi had no usage number and the total is an estimate too. */
  estimated: boolean;
  categories: Category[];
  freeTokens: number;
  autoCompactBufferTokens: number;
  details: DetailGroup[];
}

export interface BreakdownInput {
  model: string;
  contextWindow: number;
  /** pi's context usage (ctx.getContextUsage().tokens); null when unknown, e.g. right after compaction. */
  usageTokens: number | null;
  system: SystemState;
  toolMeta?: readonly ToolMeta[];
  /** Estimated tokens of the conversation messages; used only when usageTokens is null. */
  messageTokens: number;
  compaction: { enabled: boolean; reserveTokens: number };
  cwd?: string;
  home?: string;
}

/** Sections pi itself writes into the system prompt (see buildSystemPromptSections). */
const SYSTEM_SECTIONS = new Set(["preamble", "tools", "rules", "docs", "addendum", "cwd"]);
const MEMORY_SECTION = "project_context";
const SKILLS_SECTION = "skills";

/**
 * pi's built-in tools, used only when a tool has no source metadata (getAllTools
 * normally says `builtin:<name>`). Anything not listed falls to "extension".
 */
const BUILTIN_TOOLS = new Set(["read", "bash", "edit", "write", "grep", "find", "ls", "powershell"]);

export function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

/** Text of a system message's content: a string, or text blocks. */
function contentText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  const texts: string[] = [];
  for (const block of content) {
    if (isRecord(block) && block.type === "text" && typeof block.text === "string") texts.push(block.text);
  }
  return texts.join("\n");
}

/**
 * Replays the transcript's system messages (pi stores the prompt as named
 * sections and tool changes as toolsAdded/toolsRemoved) into the state the
 * model had at its last request. Undefined when no system message exists yet.
 */
export function replaySystemState(messages: readonly unknown[]): SystemState | undefined {
  let seen = false;
  const content: string[] = [];
  const sections = new Map<string, string>();
  const tools = new Map<string, ToolDecl>();
  for (const message of messages) {
    if (!isRecord(message) || message.role !== "system") continue;
    seen = true;
    const text = contentText(message.content);
    if (text.length > 0) content.push(text);
    for (const [name, value] of Object.entries(isRecord(message.sections) ? message.sections : {})) {
      if (value === null) sections.delete(name);
      else if (typeof value === "string") sections.set(name, value);
    }
    for (const tool of Array.isArray(message.toolsRemoved) ? message.toolsRemoved : []) {
      if (isRecord(tool) && typeof tool.name === "string") tools.delete(tool.name);
    }
    for (const tool of Array.isArray(message.toolsAdded) ? message.toolsAdded : []) {
      if (isRecord(tool) && typeof tool.name === "string") tools.set(tool.name, { ...tool, name: tool.name });
    }
  }
  if (!seen) return undefined;
  return { content: content.join("\n\n"), sections: Object.fromEntries(sections), tools: [...tools.values()] };
}

/**
 * Splits a rendered system prompt back into its sections. pi joins an untagged
 * preamble and `<name>\n…\n</name>` sections with blank lines; this walks back
 * from the end, matching each closing tag to its opening one. Used before the
 * first request, when the transcript has no system message yet.
 */
export function splitPromptSections(text: string): { content: string; sections: Record<string, string> } {
  const found: [string, string][] = [];
  let end = text.length;
  while (end > 0) {
    const close = /<\/([a-z][a-z0-9_-]*)>$/.exec(text.slice(0, end));
    if (!close) break;
    const open = `<${close[1]}>\n`;
    let start = text.lastIndexOf(open, close.index);
    while (start > 0 && text.slice(start - 2, start) !== "\n\n") start = text.lastIndexOf(open, start - 1);
    if (start < 0) break;
    found.unshift([close[1], text.slice(start, end)]);
    end = Math.max(0, start - 2);
  }
  return { content: text.slice(0, end), sections: Object.fromEntries(found) };
}

const IMAGE_CHARS = 4800;

function contentChars(content: unknown): number {
  if (typeof content === "string") return content.length;
  if (!Array.isArray(content)) return 0;
  let chars = 0;
  for (const block of content) {
    if (!isRecord(block)) continue;
    if (block.type === "text" && typeof block.text === "string") chars += block.text.length;
    else if (block.type === "image") chars += IMAGE_CHARS;
  }
  return chars;
}

/** Estimates one conversation message, mirroring pi's estimateTokens(). System messages count as 0 here. */
export function estimateMessageTokens(message: unknown): number {
  if (!isRecord(message)) return 0;
  let chars = 0;
  switch (message.role) {
    case "user":
    case "custom":
    case "toolResult":
      chars = contentChars(message.content);
      break;
    case "assistant":
      for (const block of Array.isArray(message.content) ? message.content : []) {
        if (!isRecord(block)) continue;
        if (block.type === "text") chars += String(block.text ?? "").length;
        else if (block.type === "thinking") chars += String(block.thinking ?? "").length;
        else if (block.type === "toolCall") chars += String(block.name ?? "").length + JSON.stringify(block.arguments ?? {}).length;
      }
      break;
    case "bashExecution":
      chars = String(message.command ?? "").length + String(message.output ?? "").length;
      break;
    case "branchSummary":
    case "compactionSummary":
      chars = String(message.summary ?? "").length;
      break;
    default:
      // System messages are counted as prompt and tools; unknown roles carry nothing pi sends.
      return 0;
  }
  return Math.ceil(chars / 4);
}

export type ToolKind = "system" | "extension" | "mcp";

const MCP_WORD = /(^|[^a-z0-9])mcp([^a-z0-9]|$)/i;

/** Built-in pi tool, extension tool, or MCP tool (by name, namespace, or source path). */
export function classifyTool(name: string, meta?: ToolMeta): ToolKind {
  if (name === "mcp" || name.startsWith("mcp__")) return "mcp";
  if (meta?.namespace?.startsWith("mcp")) return "mcp";
  const path = meta?.sourcePath ?? "";
  if (MCP_WORD.test(path)) return "mcp";
  if (path.startsWith("builtin:")) return "system";
  if (!meta && BUILTIN_TOOLS.has(name)) return "system";
  return "extension";
}

export function toolTokens(tool: ToolDecl): number {
  return estimateTokens(
    JSON.stringify({ name: tool.name, description: tool.description, parameters: tool.parameters }) ?? "",
  );
}

/** Context files in a rendered project_context section, by path. */
export function parseMemoryFiles(section: string): { path: string; tokens: number }[] {
  const files: { path: string; tokens: number }[] = [];
  for (const match of section.matchAll(/<project_instructions path="([^"]*)">\n[\s\S]*?\n<\/project_instructions>/g)) {
    files.push({ path: match[1], tokens: estimateTokens(match[0]) });
  }
  return files;
}

function unescapeXml(text: string): string {
  return text
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

/** Skills listed in a rendered skills section, by name. */
export function parseSkills(section: string): DetailItem[] {
  const skills: DetailItem[] = [];
  for (const match of section.matchAll(/<skill>\s*<name>([\s\S]*?)<\/name>[\s\S]*?<\/skill>/g)) {
    skills.push({ name: unescapeXml(match[1].trim()), tokens: estimateTokens(match[0]) });
  }
  return skills;
}

/** A path relative to cwd when inside it, else with the home directory shortened to ~. */
export function displayPath(path: string, cwd?: string, home?: string): string {
  if (cwd && path.startsWith(`${cwd}/`)) return path.slice(cwd.length + 1);
  if (home && path.startsWith(`${home}/`)) return `~/${path.slice(home.length + 1)}`;
  return path;
}

const byTokens = (a: DetailItem, b: DetailItem) => b.tokens - a.tokens || a.name.localeCompare(b.name);

export function computeBreakdown(input: BreakdownInput): ContextBreakdown {
  const { system, contextWindow } = input;
  const meta = new Map((input.toolMeta ?? []).map((tool) => [tool.name, tool]));

  let systemPrompt = system.content ? estimateTokens(system.content) : 0;
  let memoryFiles = 0;
  let skills = 0;
  const extensionPrompts: DetailItem[] = [];
  const memoryItems: DetailItem[] = [];
  const skillItems: DetailItem[] = [];
  for (const [name, text] of Object.entries(system.sections)) {
    const tokens = estimateTokens(text);
    if (SYSTEM_SECTIONS.has(name)) systemPrompt += tokens;
    else if (name === MEMORY_SECTION) {
      memoryFiles += tokens;
      for (const file of parseMemoryFiles(text)) {
        memoryItems.push({ name: displayPath(file.path, input.cwd, input.home), tokens: file.tokens });
      }
    } else if (name === SKILLS_SECTION) {
      skills += tokens;
      skillItems.push(...parseSkills(text));
    } else extensionPrompts.push({ name, tokens });
  }

  const toolItems: Record<ToolKind, DetailItem[]> = { system: [], extension: [], mcp: [] };
  for (const tool of system.tools) {
    toolItems[classifyTool(tool.name, meta.get(tool.name))].push({ name: tool.name, tokens: toolTokens(tool) });
  }
  const sum = (items: DetailItem[]) => items.reduce((total, item) => total + item.tokens, 0);

  const categories: Category[] = [
    { id: "systemPrompt", label: "System prompt", tokens: systemPrompt },
    { id: "systemTools", label: "System tools", tokens: sum(toolItems.system) },
    { id: "extensionTools", label: "Extension tools", tokens: sum(toolItems.extension) },
    { id: "mcpTools", label: "MCP tools", tokens: sum(toolItems.mcp) },
    { id: "extensionPrompts", label: "Extension prompts", tokens: sum(extensionPrompts) },
    { id: "memoryFiles", label: "Memory files", tokens: memoryFiles },
    { id: "skills", label: "Skills", tokens: skills },
  ];
  const nonMessage = categories.reduce((total, category) => total + category.tokens, 0);

  let usedTokens: number;
  let messages: number;
  if (input.usageTokens != null) {
    usedTokens = Math.max(input.usageTokens, nonMessage);
    messages = usedTokens - nonMessage;
  } else {
    messages = input.messageTokens;
    usedTokens = nonMessage + messages;
  }
  categories.push({ id: "messages", label: "Messages", tokens: messages });

  const window = Math.max(0, contextWindow);
  const reserve = input.compaction.enabled ? Math.min(input.compaction.reserveTokens, window) : 0;
  const autoCompactBufferTokens = Math.max(0, Math.min(reserve, window - usedTokens));
  const freeTokens = Math.max(0, window - usedTokens - autoCompactBufferTokens);

  const details: DetailGroup[] = [
    { title: "MCP tools", items: toolItems.mcp.sort(byTokens) },
    { title: "Extension tools", items: toolItems.extension.sort(byTokens) },
    { title: "Extension prompts", items: extensionPrompts.sort(byTokens) },
    // Memory files keep prompt order, the order the model reads them in.
    { title: "Memory files", items: memoryItems },
    { title: "Skills", items: skillItems.sort(byTokens) },
  ].filter((group) => group.items.length > 0);

  return {
    model: input.model,
    contextWindow: window,
    usedTokens,
    estimated: input.usageTokens == null,
    categories,
    freeTokens,
    autoCompactBufferTokens,
    details,
  };
}
