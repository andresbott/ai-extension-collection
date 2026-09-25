// End-to-end tests for the pi glue: a fake pi and ctx, a fake model, and the
// real scripts against throwaway Git fixtures with the shared fake gh.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

import gitauto from "./index.ts";

const FAKE_GH = join(dirname(dirname(fileURLToPath(import.meta.url))), "scripts", "testdata", "fake-gh");

function git(cwd: string, ...args: string[]) {
  return execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
}

/** A repo on main with one commit; with a remote, a bare origin and the fake gh on PATH. */
function fixture(withRemote: boolean) {
  const root = mkdtempSync(join(tmpdir(), "gitauto-pi-"));
  const repo = join(root, "repo");
  mkdirSync(repo);
  git(repo, "init", "-q", "-b", "main");
  git(repo, "config", "user.name", "Gitauto Test");
  git(repo, "config", "user.email", "gitauto@example.invalid");
  writeFileSync(join(repo, "README.md"), "base\n");
  git(repo, "add", "README.md");
  git(repo, "commit", "-qm", "init");
  const gh = join(root, "gh");
  if (withRemote) {
    const remote = join(root, "remote.git");
    execFileSync("git", ["init", "-q", "--bare", "-b", "main", remote]);
    git(repo, "remote", "add", "origin", remote);
    git(repo, "push", "-qu", "origin", "main");
    git(repo, "remote", "set-head", "origin", "main");
    const bin = join(root, "bin");
    mkdirSync(bin);
    mkdirSync(gh);
    copyFileSync(FAKE_GH, join(bin, "gh"));
    execFileSync("chmod", ["+x", join(bin, "gh")]);
    process.env.PATH = `${bin}:${process.env.PATH}`;
    process.env.FAKE_GH = gh;
  }
  return { repo, gh };
}

/** Load the extension into a fake pi; the fake model answers with `reply`. */
function load(cwd: string, reply: string, choice?: string, available: { provider: string; id: string }[] = []) {
  const commands = new Map<string, { handler: (args: string, ctx: unknown) => Promise<void> }>();
  const messages: string[] = [];
  const prompts: string[] = [];
  const models: string[] = [];
  const pi = {
    registerCommand: (name: string, options: { handler: (args: string, ctx: unknown) => Promise<void> }) =>
      commands.set(name, options),
    sendMessage: (m: { content: string }) => messages.push(m.content),
  };
  const ctx = {
    cwd,
    hasUI: true,
    model: { provider: "fake", id: "model" },
    ui: { notify: () => {}, setWidget: () => {}, select: async () => choice },
    waitForIdle: async () => {},
    modelRegistry: {
      getAvailable: () => available,
      complete: async (
        model: { provider: string; id: string },
        context: { messages: { content: { text: string }[] }[] },
      ) => {
        models.push(`${model.provider}/${model.id}`);
        prompts.push(context.messages[0].content[0].text);
        return { stopReason: "stop", content: [{ type: "text", text: reply }] };
      },
    },
  };
  gitauto(pi as never);
  const run = (name: string, args = "") => commands.get(name)!.handler(args, ctx);
  return { commands, messages, prompts, models, run };
}

test("registers the three gitauto commands", () => {
  const { commands } = load(tmpdir(), "");
  assert.deepEqual([...commands.keys()], ["gitauto:branch-out", "gitauto:open-pr", "gitauto:ship"]);
});

test("/gitauto:branch-out names the branch with the model and creates it", async () => {
  const { repo } = fixture(false);
  const pi = load(repo, "=== branch\nfeat/pi-e2e\nfeat/other\nfeat/third");
  await pi.run("gitauto:branch-out");
  assert.equal(git(repo, "branch", "--show-current"), "feat/pi-e2e");
  assert.match(pi.prompts[0], /^NEED_NAME on=main/);
  assert.match(pi.messages[0], /DONE state=created branch=feat\/pi-e2e from=main/);
  assert.deepEqual(pi.models, ["fake/model"], "no cheap model available: the session's model");
});

test("texts are written by a cheap available model, not the session's model", async () => {
  const { repo } = fixture(false);
  const available = [
    { provider: "fake", id: "model" },
    { provider: "fake", id: "claude-haiku-4.5" },
    { provider: "other", id: "claude-haiku-9" },
  ];
  const pi = load(repo, "=== branch\nfeat/cheap\nfeat/b\nfeat/c", undefined, available);
  await pi.run("gitauto:branch-out");
  assert.deepEqual(pi.models, ["fake/claude-haiku-4.5"]);
  assert.equal(git(repo, "branch", "--show-current"), "feat/cheap");
});

test("a complex change runs the expert on the session's model; simple texts stay cheap", async () => {
  const { repo } = fixture(true);
  writeFileSync(join(repo, "README.md"), "base\nchange\n");
  // A fake `pi` that records its arguments and saves no draft, so the cheap writer takes over.
  const bin = mkdtempSync(join(tmpdir(), "gitauto-fake-pi-"));
  const fakePi = join(bin, "pi");
  const argsFile = join(bin, "args");
  writeFileSync(fakePi, `#!/usr/bin/env bash\nprintf '%s\\n' "$@" > "${argsFile}"\n`);
  execFileSync("chmod", ["+x", fakePi]);
  const reply = ["=== branch", "feat/pi-expert", "=== title", "Add a change", "=== subject", "feat: add a change", "=== body", "## Summary", "Why."].join("\n");
  const available = [
    { provider: "fake", id: "model" },
    { provider: "fake", id: "claude-haiku-4.5" },
  ];
  const pi = load(repo, reply, undefined, available);
  process.env.GITAUTO_PI_BIN = fakePi;
  process.env.GITAUTO_CMD_COMPLEX_LINES = "0"; // rate every change complex
  try {
    await pi.run("gitauto:ship", "no tag");
  } finally {
    delete process.env.GITAUTO_PI_BIN;
    delete process.env.GITAUTO_CMD_COMPLEX_LINES;
  }
  const expertArgs = readFileSync(argsFile, "utf8").split("\n");
  assert.equal(expertArgs[expertArgs.indexOf("--model") + 1], "fake/model", "expert on the session's model");
  assert.deepEqual(pi.models, ["fake/claude-haiku-4.5"], "the fallback texts on the cheap model");
  assert.match(pi.messages[0], /SHIPPED pr=#7 /);
  assert.match(pi.messages[0], /The expert writer saved no draft/);
});

test("GITAUTO_CHEAP_MODEL overrides the cheap pick", async () => {
  const { repo } = fixture(false);
  const available = [
    { provider: "fake", id: "claude-haiku-4.5" },
    { provider: "fake", id: "big" },
  ];
  const pi = load(repo, "=== branch\nfeat/override\nfeat/b\nfeat/c", undefined, available);
  process.env.GITAUTO_CHEAP_MODEL = "fake/big";
  try {
    await pi.run("gitauto:branch-out");
  } finally {
    delete process.env.GITAUTO_CHEAP_MODEL;
  }
  assert.deepEqual(pi.models, ["fake/big"]);
});

test("/gitauto:ship ships a small change end to end with the cheap writer", async () => {
  const { repo, gh } = fixture(true);
  writeFileSync(join(repo, "README.md"), "base\nchange\n");
  const reply = [
    "=== branch",
    "feat/pi-ship",
    "=== title",
    "Add a change",
    "=== subject",
    "feat(readme): add a change",
    "=== body",
    "## Summary",
    "Because it's needed.",
  ].join("\n");
  const pi = load(repo, reply);
  await pi.run("gitauto:ship", "no tag");
  assert.match(pi.messages[0], /SHIPPED pr=#7 .* tag=declined /);
  assert.equal(git(repo, "branch", "--show-current"), "main");
  assert.equal(git(repo, "log", "-1", "--format=%s", "feat/pi-ship"), "feat(readme): add a change");
  assert.equal(readFileSync(join(gh, "title"), "utf8"), "Add a change");
  assert.match(readFileSync(join(gh, "body"), "utf8"), /Because it's needed\./);
  assert.match(readFileSync(join(gh, "merge"), "utf8"), /--subject feat\(readme\): add a change \(#7\)/);
});

test("a model reply without a requested text stops before any mutation", async () => {
  const { repo } = fixture(true);
  writeFileSync(join(repo, "README.md"), "base\nchange\n");
  const pi = load(repo, "=== branch\nfeat/half");
  await pi.run("gitauto:ship");
  assert.match(pi.messages[0], /failed: the model did not write a title/);
  assert.equal(git(repo, "branch", "--show-current"), "main");
});
