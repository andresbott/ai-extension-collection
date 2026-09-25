// The gitauto flows for pi, harness-free: every side effect comes in through
// Deps, so the flows can be tested with fakes. The scripts decide; this code only
// runs them, asks a model for the texts they list, and asks the user about tags.
import {
  NO_TAG,
  failureBlock,
  firstLine,
  lastLine,
  parseFields,
  parseShipArgs,
  tagQuestion,
  writeKeys,
  type Texts,
} from "./protocol.ts";

export type Script = "ship.sh" | "branch-out.sh";

export interface ScriptResult {
  code: number;
  out: string;
}

export interface Deps {
  /** Run a gitauto script in the repository. */
  script(name: Script, args: string[], opts?: { stdin?: string; env?: Record<string, string> }): Promise<ScriptResult>;
  /** Cheap model: write the texts `keys` asks for, from a script's output. */
  write(context: string, keys: string[]): Promise<Texts>;
  /** Expert model (the pr-writer prompt): save a PR draft; true when one was saved. */
  expert(base: string): Promise<boolean>;
  /** Ask the user to pick one option; undefined when there is no answer. */
  select(title: string, options: string[]): Promise<string | undefined>;
  /** Cheap model: one sentence naming the most likely cause of a failure. */
  diagnose(failure: string): Promise<string | undefined>;
  /** Show a progress note. */
  progress(note: string): void;
}

/** CI re-runs after a WAITING, as in the Claude command. */
export const MAX_RESUMES = 5;

// Raising the thresholds past any change makes prepare show the cheap writer's context.
const CHEAP_CONTEXT_ENV = {
  GITAUTO_CMD_COMPLEX_FILES: "1000000000",
  GITAUTO_CMD_COMPLEX_LINES: "1000000000",
  GITAUTO_CMD_COMPLEX_DIRS: "1000000000",
};

const code = (text: string) => ["```text", text, "```"].join("\n");

export async function branchOut(deps: Deps, args: string): Promise<string> {
  const pre = await deps.script("branch-out.sh", [args]);
  if (!pre.out.startsWith("NEED_NAME")) return code(lastLine(pre.out));
  deps.progress("naming the branch");
  const { branch = [] } = await deps.write(pre.out, writeKeys(pre.out));
  const res = await deps.script("branch-out.sh", ["--create", ...branch]);
  return code(lastLine(res.out));
}

export async function ship(deps: Deps, args: string, until: "ship" | "pr"): Promise<string> {
  const prepareArgs = until === "pr" ? ["prepare", "--for", "pr", args] : ["prepare", args];
  let pre = await deps.script("ship.sh", prepareArgs);
  if (!pre.out.startsWith("SHIP")) return code(firstLine(pre.out));
  const fields = parseFields(firstLine(pre.out));
  const notes: string[] = [];

  if (fields.need === "pr" && fields.writer === "expert") {
    deps.progress("writing the PR description (expert model)");
    if (!(await deps.expert(fields.base))) {
      notes.push("The expert writer saved no draft, so the cheap writer wrote the PR text.");
      deps.progress("the expert saved no draft; using the cheap writer");
      pre = await deps.script("ship.sh", prepareArgs, { env: CHEAP_CONTEXT_ENV });
      if (!pre.out.startsWith("SHIP")) return code(firstLine(pre.out));
    }
  }

  const keys = writeKeys(pre.out);
  if (keys.length > 0) deps.progress(`writing: ${keys.join(", ")}`);
  const texts = keys.length > 0 ? await deps.write(pre.out, keys) : {};

  const resume = until === "ship" ? resumeFlags(args) : [];
  const cmd = until === "pr" ? "open-pr" : "run";
  let res = await deps.script("ship.sh", [cmd, ...resume, ...textFlags(texts)], { stdin: texts.body });
  for (let i = 0; i < MAX_RESUMES && lastLine(res.out).startsWith("WAITING"); i++) {
    deps.progress("CI still running; resuming");
    res = await deps.script("ship.sh", [cmd, ...resume]);
  }

  const final = lastLine(res.out);
  const report = [final];
  const failure = failureBlock(res.out);
  if (failure) report.push(failure);
  if (until === "pr" && final.startsWith("READY")) notes.push("Run `/gitauto:ship` to merge.");
  if (until === "ship" && /(?:^|\s)tag=ask(?:\s|$)/.test(final)) {
    const tagged = await askTag(deps, final);
    if (tagged) report.push(tagged);
    else notes.push(`${NO_TAG} created.`);
  }
  if (failure) {
    const cause = await deps.diagnose(failure);
    if (cause) notes.push(cause);
  }
  return [code(report.join("\n")), ...notes].join("\n\n");
}

/** The `run` flags from the command args. Only these survive a resume. */
function resumeFlags(args: string): string[] {
  const opts = parseShipArgs(args);
  const flags: string[] = [];
  if (opts.tag) flags.push("--tag", opts.tag);
  else if (opts.noTag) flags.push("--no-tag");
  if (opts.deleteRemote) flags.push("--delete-remote");
  return flags;
}

/** One flag per written text; the body goes on stdin. */
function textFlags(texts: Texts): string[] {
  const flags: string[] = [];
  if (texts.branch?.length) flags.push("--branch", ...texts.branch);
  if (texts.title) flags.push("--title", texts.title);
  if (texts.subject) flags.push("--subject", texts.subject);
  if (texts.message) flags.push("--message", texts.message);
  if (texts.body) flags.push("--body-stdin");
  return flags;
}

/** Ask once; tag only an explicitly chosen version. Returns the tag line, if any. */
async function askTag(deps: Deps, final: string): Promise<string | undefined> {
  const q = tagQuestion(parseFields(final));
  const version = q.versionOf(await deps.select(q.title, q.options));
  if (!version) return undefined;
  const tagged = await deps.script("ship.sh", ["tag", version]);
  return lastLine(tagged.out);
}
