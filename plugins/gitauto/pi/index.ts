// gitauto for pi: registers /gitauto:branch-out, /gitauto:open-pr, and
// /gitauto:ship. The flows (flow.ts) are harness-free; this file binds them to
// pi: the bundled scripts, nested model calls, the tag question, and progress.
//
// Models: GITAUTO_CHEAP_MODEL writes branch names, messages, and small PR texts;
// GITAUTO_EXPERT_MODEL runs the shared pr-writer prompt for complex changes.
// Both take `provider/id` (or a bare id) and default to the session's model.
import { execFileSync, spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";

import { branchOut, ship, type Deps, type Script, type ScriptResult } from "./flow.ts";
import { WRITE_SYSTEM_PROMPT, parseTexts, stripFrontmatter } from "./protocol.ts";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const SCRIPTS = join(ROOT, "scripts");
const PR_WRITER = join(ROOT, "agents", "pr-writer.md");

// Pi has no tool-call cap, so one run may wait on CI far longer than Claude's 540s.
const RUN_BUDGET = "3600";
const EXPERT_TIMEOUT_MS = 15 * 60_000;
const EXPERT_TOOLS = "read,grep,find,ls,bash";
const DIAGNOSE_PROMPT = "In one sentence, name the most likely cause of this failure. Do not suggest or attempt a fix.";
const WIDGET = "gitauto";
const WIDGET_LINES = 8;

type Model = NonNullable<ExtensionCommandContext["model"]>;
type Flow = (deps: Deps, args: string) => Promise<string>;

const COMMANDS: [name: string, description: string, flow: Flow][] = [
  ["branch-out", "Move off main/master onto a feature branch (no-op on a feature branch)", branchOut],
  [
    "open-pr",
    "Open (or reuse) a PR and wait for green CI: branch, verify, commit, push, open PR, watch CI. Never merges.",
    (deps, args) => ship(deps, args, "pr"),
  ],
  [
    "ship",
    "Ship the current work: branch, verify, commit, push, PR, CI, squash-merge, sync, clean up, then offer a tag. Args: [branch] [tag=<semver> | no tag] [deleteRemote=true]",
    (deps, args) => ship(deps, args, "ship"),
  ],
];

export default function gitauto(pi: ExtensionAPI) {
  let busy = false;
  for (const [name, description, flow] of COMMANDS) {
    pi.registerCommand(`gitauto:${name}`, {
      description,
      handler: async (args, ctx) => {
        if (busy) {
          ctx.ui.notify("gitauto is already running", "warning");
          return;
        }
        busy = true;
        const progress = new Progress(ctx);
        let report: string;
        try {
          await ctx.waitForIdle();
          report = await flow(makeDeps(ctx, progress), args.trim());
        } catch (err) {
          report = `failed: ${err instanceof Error ? err.message : String(err)}`;
          ctx.ui.notify(`gitauto:${name} ${report}`, "error");
        } finally {
          progress.clear();
          busy = false;
        }
        // Into the session, so the user can ask the model about a failure afterwards.
        pi.sendMessage({ customType: "gitauto", content: `**/gitauto:${name}**\n\n${report}`, display: true });
      },
    });
  }
}

/** The last few progress lines, shown in a widget while a command runs. */
class Progress {
  private lines: string[] = [];
  private ctx: ExtensionCommandContext;
  constructor(ctx: ExtensionCommandContext) {
    this.ctx = ctx;
  }
  add(line: string) {
    this.lines.push(line);
    this.ctx.ui.setWidget(WIDGET, this.lines.slice(-WIDGET_LINES));
  }
  clear() {
    this.ctx.ui.setWidget(WIDGET, undefined);
  }
}

function makeDeps(ctx: ExtensionCommandContext, progress: Progress): Deps {
  return {
    script: (name, args, opts) =>
      runScript(ctx.cwd, name, args, opts, (line) => line.startsWith("ship:") && progress.add(line)),
    write: async (context, keys) => {
      const reply = await complete(ctx, resolveModel(ctx, "GITAUTO_CHEAP_MODEL"), WRITE_SYSTEM_PROMPT, context);
      return parseTexts(reply, keys);
    },
    expert: (base) => runExpert(ctx, base),
    select: async (title, options) => (ctx.hasUI ? ctx.ui.select(title, options) : undefined),
    diagnose: async (failure) => {
      try {
        const cause = await complete(ctx, resolveModel(ctx, "GITAUTO_CHEAP_MODEL"), DIAGNOSE_PROMPT, failure);
        return cause.trim() || undefined;
      } catch {
        return undefined;
      }
    },
    progress: (note) => progress.add(`gitauto: ${note}`),
  };
}

/** Run a bundled script; stdout lines stream to onLine as they arrive. */
function runScript(
  cwd: string,
  name: Script,
  args: string[],
  opts: { stdin?: string; env?: Record<string, string> } | undefined,
  onLine: (line: string) => void,
): Promise<ScriptResult> {
  return new Promise((resolve, reject) => {
    const env = { ...process.env, GITAUTO_CMD_RUN_BUDGET: process.env.GITAUTO_CMD_RUN_BUDGET ?? RUN_BUDGET, ...opts?.env };
    const child = spawn("bash", [join(SCRIPTS, name), ...args], { cwd, env });
    let out = "";
    let err = "";
    let partial = "";
    child.stdout.on("data", (chunk: Buffer) => {
      const text = chunk.toString();
      out += text;
      const lines = (partial + text).split("\n");
      partial = lines.pop() ?? "";
      lines.forEach(onLine);
    });
    child.stderr.on("data", (chunk: Buffer) => (err += chunk.toString()));
    child.on("error", reject);
    child.on("close", (code) => resolve({ code: code ?? 1, out: out || err }));
    child.stdin.end(opts?.stdin ?? "");
  });
}

/** `provider/id` or a bare id from the env var, else the session's model. */
function resolveModel(ctx: ExtensionCommandContext, envName: string): Model {
  const spec = process.env[envName]?.trim();
  if (!spec) {
    if (!ctx.model) throw new Error(`no model selected; select one or set ${envName}`);
    return ctx.model;
  }
  const slash = spec.indexOf("/");
  const model =
    slash > 0
      ? ctx.modelRegistry.find(spec.slice(0, slash), spec.slice(slash + 1))
      : ctx.modelRegistry.getAvailable().find((m) => m.id === spec);
  if (!model) throw new Error(`${envName}=${spec} is not an available model`);
  return model;
}

async function complete(ctx: ExtensionCommandContext, model: Model, systemPrompt: string, text: string) {
  const res = await ctx.modelRegistry.complete(model, {
    systemPrompt,
    messages: [{ role: "user", content: [{ type: "text", text }], timestamp: Date.now() }],
  });
  if (res.stopReason === "error" || res.stopReason === "aborted") {
    throw new Error(res.errorMessage ?? `the model call ended with ${res.stopReason}`);
  }
  return res.content.flatMap((c) => (c.type === "text" ? [c.text] : [])).join("\n");
}

/** A one-shot pi process with the shared pr-writer prompt; it saves the draft itself. */
async function runExpert(ctx: ExtensionCommandContext, base: string): Promise<boolean> {
  const model = process.env.GITAUTO_EXPERT_MODEL?.trim() || (ctx.model && `${ctx.model.provider}/${ctx.model.id}`);
  const args = [
    "--print",
    "--no-session",
    "--no-extensions",
    "--no-skills",
    "--no-prompt-templates",
    "--no-approve",
    "--tools",
    EXPERT_TOOLS,
    "--append-system-prompt",
    stripFrontmatter(readFileSync(PR_WRITER, "utf8")),
    ...(model ? ["--model", model] : []),
    `Base: ${base}. Draft command: ${join(SCRIPTS, "ship.sh")} draft`,
  ];
  const [cmd, ...pre] = piCommand();
  await new Promise<void>((resolve) => {
    const child = spawn(cmd, [...pre, ...args], { cwd: ctx.cwd, stdio: "ignore", timeout: EXPERT_TIMEOUT_MS });
    child.on("error", () => resolve());
    child.on("close", () => resolve());
  });
  return draftSaved(ctx.cwd);
}

/** The pi that is running this extension, so the expert uses the same install. */
function piCommand(): string[] {
  if (process.env.GITAUTO_PI_BIN) return [process.env.GITAUTO_PI_BIN];
  const cli = process.argv[1];
  if (cli && /^node(\.exe)?$/i.test(basename(process.execPath)) && existsSync(cli)) return [process.execPath, cli];
  return ["pi"];
}

/** ship.sh draft writes the title into <git-dir>/gitauto/. */
function draftSaved(cwd: string): boolean {
  try {
    const gitDir = execFileSync("git", ["rev-parse", "--absolute-git-dir"], { cwd, encoding: "utf8" }).trim();
    return existsSync(join(gitDir, "gitauto", "title"));
  } catch {
    return false;
  }
}
