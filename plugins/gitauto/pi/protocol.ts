// Parsers for the gitauto script protocol: the status lines, the `--- write`
// block, and the free-form command arguments. Pure functions, no pi imports.

/** `key=value` pairs of a status line; a value runs until the next ` key=`. */
export function parseFields(line: string): Record<string, string> {
  const fields: Record<string, string> = {};
  for (const m of line.matchAll(/(?:^|\s)([a-z_]+)=(.*?)(?=\s[a-z_]+=|$)/g)) {
    fields[m[1]] = m[2];
  }
  return fields;
}

export function firstLine(out: string): string {
  return out.split("\n").find((l) => l.trim() !== "")?.trim() ?? "";
}

export function lastLine(out: string): string {
  return out.split("\n").filter((l) => l.trim() !== "").at(-1)?.trim() ?? "";
}

/** The `--- failure` block a failed run prints just before its final line. */
export function failureBlock(out: string): string | undefined {
  const lines = out.replace(/\n+$/, "").split("\n");
  const start = lines.findIndex((l) => l.startsWith("--- failure"));
  if (start < 0) return undefined;
  return lines.slice(start, -1).join("\n");
}

/** Keys of the `--- write` block, in order: the texts the model must write. */
export function writeKeys(out: string): string[] {
  const keys: string[] = [];
  let inside = false;
  for (const line of out.split("\n")) {
    if (line.startsWith("--- ")) {
      inside = line === "--- write";
      continue;
    }
    const m = inside ? /^([a-z-]+): /.exec(line) : null;
    if (m) keys.push(m[1]);
  }
  return keys;
}

export interface Texts {
  branch?: string[];
  title?: string;
  subject?: string;
  message?: string;
  body?: string;
}

export const WRITE_SYSTEM_PROMPT = `You write the text a git automation script needs. The input is the script's output.
Its \`--- write\` block lists each text to write as \`<key>: <rule>\`. Follow each rule exactly, using the rest of the output as context.

Reply with one section per listed key, in the listed order. Each section starts with a line \`=== <key>\`, followed by the text on the next lines. For \`branch\`, put one name per line. Output nothing else: no preamble, no code fences, no commentary.`;

const unquote = (s: string) => s.trim().replace(/^[`'"]+|[`'"]+$/g, "").trim();

/** Parse the model's `=== key` sections into the texts `keys` asked for. */
export function parseTexts(reply: string, keys: string[]): Texts {
  const sections = new Map<string, string>();
  let key: string | undefined;
  let buf: string[] = [];
  const flush = () => key && sections.set(key, buf.join("\n").trim());
  for (const line of reply.replace(/^```\w*\n|\n```\s*$/g, "").split("\n")) {
    const m = /^===\s*([a-z-]+)\s*$/.exec(line.trim());
    if (m) {
      flush();
      key = m[1];
      buf = [];
    } else buf.push(line);
  }
  flush();

  const texts: Texts = {};
  for (const want of keys) {
    const k = want === "subject-from-title" ? "subject" : want;
    const value = sections.get(k) ?? "";
    if (!value) throw new Error(`the model did not write a ${k}`);
    if (k === "branch") {
      texts.branch = value.split("\n").map((l) => unquote(l.replace(/^\s*(?:[-*]|\d+\.)\s+/, ""))).filter(Boolean);
    } else if (k === "body") {
      texts.body = value;
    } else if (k === "title" || k === "subject" || k === "message") {
      texts[k] = unquote(firstLine(value));
    }
  }
  return texts;
}

export interface ShipOptions {
  tag?: string;
  noTag: boolean;
  deleteRemote: boolean;
}

/** `tag=<v>`, a declined tag in any common wording, and `deleteRemote=true`. */
export function parseShipArgs(args: string): ShipOptions {
  const tag = /(?:^|\s)tag=(\S+)/.exec(args)?.[1];
  return {
    tag,
    noTag: !tag && /\b(?:no|dont|don't|do not|skip|without)[\s_-]*(?:a\s+)?tag\b/i.test(args),
    deleteRemote: /\bdeleteRemote=true\b/i.test(args) || /\bdelete[\s_-]*(?:the\s+)?remote\b/i.test(args),
  };
}

export const NO_TAG = "No tag";

/** The release-tag question for a `tag=ask` line: "No tag" first, suggestion marked. */
export function tagQuestion(fields: Record<string, string>) {
  const versions = (fields.tag_options ?? "").split(",").filter(Boolean);
  const label = (v: string) => (v === fields.tag_recommended ? `${v} (suggested)` : v);
  return {
    title: `PR ${fields.pr ?? ""} is merged. Create a release tag? (latest: ${fields.latest || "none"})`,
    options: [NO_TAG, ...versions.map(label)],
    versionOf: (choice: string | undefined) => versions.find((v) => choice === label(v)),
  };
}

/** The Markdown body of a file with optional YAML frontmatter. */
export function stripFrontmatter(md: string): string {
  return md.replace(/^---\n[\s\S]*?\n---\n/, "").trim();
}
