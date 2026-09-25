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
function load(cwd: string, reply: string, choice?: string) {
  const commands = new Map<string, { handler: (args: string, ctx: unknown) => Promise<void> }>();
  const messages: string[] = [];
  const prompts: string[] = [];
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
      complete: async (_model: unknown, context: { messages: { content: { text: string }[] }[] }) => {
        prompts.push(context.messages[0].content[0].text);
        return { stopReason: "stop", content: [{ type: "text", text: reply }] };
      },
    },
  };
  gitauto(pi as never);
  const run = (name: string, args = "") => commands.get(name)!.handler(args, ctx);
  return { commands, messages, prompts, run };
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
