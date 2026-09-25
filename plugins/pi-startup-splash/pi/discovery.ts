// @ts-ignore -- Node built-ins are provided by Pi's runtime.
import { existsSync, readdirSync } from "node:fs";
// @ts-ignore -- Node built-ins are provided by Pi's runtime.
import { homedir } from "node:os";
// @ts-ignore -- Node built-ins are provided by Pi's runtime.
import { basename, extname, join, relative, resolve, sep } from "node:path";

declare const process: { env: Record<string, string | undefined> };

export type SplashScope = "user" | "project" | "temporary";

export interface SplashItem {
  label: string;
  scope?: SplashScope;
  active?: boolean;
}

export interface SectionData {
  title: "Context" | "Skills" | "Prompts" | "Extensions";
  items: string[];
  count: number;
}

export interface SplashData {
  version?: string;
  cwdLabel: string;
  modelLabel: string;
  projectTrusted: boolean;
  sections: {
    context: SectionData;
    skills: SectionData;
    prompts: SectionData;
    extensions: SectionData;
  };
}

export interface CommandLike {
  name: string;
  source: "extension" | "prompt" | "skill";
  sourceInfo: {
    path: string;
    source: string;
    scope: SplashScope;
    origin: "package" | "top-level";
    baseDir?: string;
  };
}

export interface ToolLike {
  name: string;
  sourceInfo: {
    path: string;
    source: string;
    scope: SplashScope;
    origin: "package" | "top-level";
    baseDir?: string;
  };
}

export interface SkillLike {
  name: string;
  sourceInfo?: {
    path: string;
    scope?: SplashScope;
    baseDir?: string;
  };
}

export interface SystemPromptOptionsLike {
  cwd: string;
  contextFiles?: Array<{ path: string; content?: string }>;
  skills?: SkillLike[];
}

export interface SettingsLike {
  packages?: Array<string | { source: string }>;
  extensions?: string[];
}

export interface ExtensionDiscoveryInput {
  cwd: string;
  agentDir: string;
  projectTrusted: boolean;
  commands: CommandLike[];
  tools: ToolLike[];
  settings: SettingsLike;
  globalSettings?: SettingsLike;
  projectSettings?: SettingsLike;
}

export function defaultSplashData(cwd: string, modelLabel: string): SplashData {
  return {
    cwdLabel: shortPath(cwd, cwd),
    modelLabel: modelLabel || "model pending",
    projectTrusted: true,
    sections: {
      context: { title: "Context", items: [], count: 0 },
      skills: { title: "Skills", items: [], count: 0 },
      prompts: { title: "Prompts", items: [], count: 0 },
      extensions: { title: "Extensions", items: [], count: 0 },
    },
  };
}

export function shortPath(targetPath: string, cwd: string, home = homedir()): string {
  if (!targetPath) return "";
  const normalizedCwd = resolve(cwd);
  const normalizedTarget = resolve(targetPath);
  if (normalizedTarget === normalizedCwd) return basename(normalizedTarget) || normalizedTarget;
  if (normalizedTarget.startsWith(normalizedCwd + sep)) {
    const rel = relative(normalizedCwd, normalizedTarget);
    return rel || basename(normalizedTarget) || normalizedTarget;
  }
  if (home) {
    const normalizedHome = resolve(home);
    if (normalizedTarget === normalizedHome) return "~";
    if (normalizedTarget.startsWith(normalizedHome + sep)) {
      return `~/${relative(normalizedHome, normalizedTarget)}`;
    }
  }
  return normalizedTarget;
}

export function compactList(items: readonly string[], maxItems: number): string[] {
  if (items.length <= maxItems) return [...items];
  const shown = items.slice(0, Math.max(0, maxItems - 1));
  shown.push(`+${items.length - shown.length} more`);
  return shown;
}

export function summarizeCount(count: number, noun: string): string {
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}

export function labelPackageSource(source: string): string {
  if (source.startsWith("npm:")) {
    return stripPackageVersion(source.slice(4));
  }
  const trimmedRef = source.replace(/@[^^/\\]+$/, "");
  if (trimmedRef.startsWith("git:")) {
    return trimRepoBasename(trimmedRef.slice(4));
  }
  if (/^(https?:|ssh:|git:)/.test(trimmedRef)) {
    return trimRepoBasename(trimmedRef);
  }
  return trimLocalLabel(trimmedRef);
}

function stripPackageVersion(spec: string): string {
  const slashIndex = spec.indexOf("/");
  const lastAt = spec.lastIndexOf("@");
  if (lastAt > 0 && lastAt > slashIndex) return spec.slice(0, lastAt);
  return spec;
}

function trimRepoBasename(source: string): string {
  const noRef = source.replace(/@[^^/\\]+$/, "");
  const last = noRef.split(/[/:]/).filter(Boolean).pop() || noRef;
  return last.replace(/\.git$/, "");
}

function trimLocalLabel(source: string): string {
  const clean = source.replace(/[\\/]+$/, "");
  const base = basename(clean) || clean;
  const ext = extname(base);
  return ext ? base.slice(0, -ext.length) : base;
}

export function labelExtensionSource(path: string, baseDir?: string): string {
  const base = baseDir || path;
  const nodeModulesMatch = base.match(/[\\/]node_modules[\\/](@[^\\/]+[\\/][^\\/]+|[^\\/]+)/);
  if (nodeModulesMatch) return nodeModulesMatch[1].replace(/[\\/]/g, "/");
  const trimmed = trimLocalLabel(base);
  if (trimmed !== "index") return trimmed;

  const normalized = path.replace(/\\/g, "/");
  const parent = normalized.split("/").slice(-2, -1)[0];
  return parent ? trimLocalLabel(parent) : trimmed;
}

export function buildContextItems(options: SystemPromptOptionsLike | undefined): string[] {
  if (!options) return [];
  const items = (options.contextFiles || [])
    .map((file) => shortPath(file.path, options.cwd))
    .filter(Boolean);
  return [...new Set(items)];
}

export function buildSkillItems(options: SystemPromptOptionsLike | undefined): string[] {
  if (!options) return [];
  const items = (options.skills || []).map((skill) => skill.name).filter(Boolean);
  return [...new Set(items)];
}

export function buildPromptItems(commands: readonly CommandLike[]): string[] {
  const items = commands
    .filter((command) => command.source === "prompt")
    .map((command) => `/${command.name}`);
  return [...new Set(items)];
}

export function buildExtensionItems(input: ExtensionDiscoveryInput): string[] {
  const items = new Map<string, { label: string; priority: number }>();
  const add = (label: string | undefined, priority = 50) => {
    if (!label) return;
    const key = label.toLowerCase();
    const current = items.get(key);
    if (!current || priority < current.priority) items.set(key, { label, priority });
  };

  for (const entry of input.settings.packages || []) {
    add(labelPackageSource(typeof entry === "string" ? entry : entry.source), 10);
  }
  for (const entry of input.globalSettings?.packages || []) {
    add(labelPackageSource(typeof entry === "string" ? entry : entry.source), 20);
  }
  for (const entry of input.projectSettings?.packages || []) {
    add(labelPackageSource(typeof entry === "string" ? entry : entry.source), 20);
  }

  for (const path of input.settings.extensions || []) add(labelExtensionSource(path), 20);
  for (const path of input.globalSettings?.extensions || []) add(labelExtensionSource(path), 25);
  for (const path of input.projectSettings?.extensions || []) add(labelExtensionSource(path), 25);

  for (const command of input.commands) {
    if (command.source !== "extension") continue;
    add(labelExtensionSource(command.sourceInfo.path, command.sourceInfo.baseDir), 5);
  }
  for (const tool of input.tools) {
    const source = tool.sourceInfo.source;
    if (source === "builtin" || source === "sdk") continue;
    add(labelExtensionSource(tool.sourceInfo.path, tool.sourceInfo.baseDir), 5);
  }

  for (const name of scanExtensionDir(join(input.agentDir, "extensions"))) add(name, 30);
  if (input.projectTrusted) {
    for (const name of scanExtensionDir(join(input.cwd, ".pi", "extensions"))) add(name, 30);
  }

  return [...items.values()]
    .sort((a, b) => a.priority - b.priority || a.label.localeCompare(b.label))
    .map((entry) => entry.label);
}

export function scanExtensionDir(dir: string): string[] {
  if (!existsSync(dir)) return [];
  const names: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isFile() && [".ts", ".js", ".mjs", ".cjs"].includes(extname(entry.name))) {
      names.push(trimLocalLabel(entry.name));
      continue;
    }
    if (!entry.isDirectory()) continue;
    const indexTs = join(dir, entry.name, "index.ts");
    const indexJs = join(dir, entry.name, "index.js");
    if (existsSync(indexTs) || existsSync(indexJs)) names.push(entry.name);
  }
  return [...new Set(names)].sort((a, b) => a.localeCompare(b));
}

export async function discoverStartupData(input: {
  cwd: string;
  projectTrusted: boolean;
  modelLabel?: string;
  commands: CommandLike[];
  tools?: ToolLike[];
  systemPromptOptions?: SystemPromptOptionsLike;
}): Promise<SplashData> {
  const { cwd, projectTrusted, commands } = input;
  const agentDir = resolveAgentDir();
  const snapshot = defaultSplashData(cwd, input.modelLabel || "model pending");
  snapshot.projectTrusted = projectTrusted;

  const runtime = await loadRuntimeData({
    cwd,
    agentDir,
    projectTrusted,
    systemPromptOptions: input.systemPromptOptions,
  });

  const extensions = buildExtensionItems({
    cwd,
    agentDir,
    projectTrusted,
    commands,
    tools: input.tools || [],
    settings: runtime.settings,
    globalSettings: runtime.globalSettings,
    projectSettings: runtime.projectSettings,
  });

  snapshot.version = runtime.version;
  snapshot.cwdLabel = shortPath(cwd, cwd);
  snapshot.sections.context = {
    title: "Context",
    items: buildContextItems(runtime.systemPromptOptions),
    count: buildContextItems(runtime.systemPromptOptions).length,
  };
  snapshot.sections.skills = {
    title: "Skills",
    items: buildSkillItems(runtime.systemPromptOptions),
    count: buildSkillItems(runtime.systemPromptOptions).length,
  };
  snapshot.sections.prompts = {
    title: "Prompts",
    items: buildPromptItems(commands),
    count: buildPromptItems(commands).length,
  };
  snapshot.sections.extensions = {
    title: "Extensions",
    items: extensions,
    count: extensions.length,
  };

  return snapshot;
}

function resolveAgentDir(): string {
  return process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
}

async function loadRuntimeData(input: {
  cwd: string;
  agentDir: string;
  projectTrusted: boolean;
  systemPromptOptions?: SystemPromptOptionsLike;
}): Promise<{
  version?: string;
  settings: SettingsLike;
  globalSettings?: SettingsLike;
  projectSettings?: SettingsLike;
  systemPromptOptions?: SystemPromptOptionsLike;
}> {
  // @ts-ignore -- Pi provides its SDK module when loading the installed extension.
  const mod = await import("@earendil-works/pi-coding-agent");
  const settingsManager = mod.SettingsManager.create(input.cwd, input.agentDir, {
    projectTrusted: input.projectTrusted,
  });

  let systemPromptOptions = input.systemPromptOptions;
  if (!systemPromptOptions) {
    const loader = new mod.DefaultResourceLoader({
      cwd: input.cwd,
      agentDir: input.agentDir,
      settingsManager,
      noExtensions: true,
      noPromptTemplates: true,
      noThemes: true,
    });
    await loader.reload();
    systemPromptOptions = {
      cwd: input.cwd,
      contextFiles: loader.getAgentsFiles().agentsFiles,
      skills: loader.getSkills().skills,
    };
  }

  return {
    version: mod.VERSION,
    settings: {
      packages: settingsManager.getPackages(),
      extensions: settingsManager.getExtensionPaths(),
    },
    globalSettings: {
      packages: settingsManager.getGlobalSettings().packages,
      extensions: settingsManager.getGlobalSettings().extensions,
    },
    projectSettings: input.projectTrusted
      ? {
          packages: settingsManager.getProjectSettings().packages,
          extensions: settingsManager.getProjectSettings().extensions,
        }
      : undefined,
    systemPromptOptions,
  };
}
