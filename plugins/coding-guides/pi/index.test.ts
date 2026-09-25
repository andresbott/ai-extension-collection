// Tests for the coding-guides pi glue: a fake pi collects the handlers, and
// the real shared script decides tool calls.
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { test } from "node:test";

import codingGuides, { GUIDES, SECTION } from "./index.ts";

// The shared script fails open without jq, and its newline checks need GNU grep -P.
const HAS_JQ = spawnSync("jq", ["--version"]).status === 0;
const HAS_GREP_P = spawnSync("grep", ["-Pq", ""], { input: "\n" }).status === 0;

type Handler = (event: any) => any;

function load() {
  const handlers = new Map<string, Handler>();
  codingGuides({ on: (name: string, handler: Handler) => handlers.set(name, handler) } as any);
  return handlers;
}

function toolCall(toolName: string, input: Record<string, unknown>) {
  return load().get("tool_call")!({ type: "tool_call", toolCallId: "t1", toolName, input });
}

test("registers the prompt and tool-call handlers", () => {
  const handlers = load();
  assert.ok(handlers.has("before_agent_start"));
  assert.ok(handlers.has("tool_call"));
});

test("adds the shared guides as a system-prompt section", () => {
  const event = { systemPromptOptions: { sections: { other: "keep" } as Record<string, string> } };
  load().get("before_agent_start")!(event);
  assert.equal(event.systemPromptOptions.sections[SECTION], readFileSync(GUIDES, "utf8"));
  assert.equal(event.systemPromptOptions.sections.other, "keep");
});

test("blocks a multi-paragraph commit with the script's reason", { skip: !HAS_JQ && "jq not installed" }, () => {
  const result = toolCall("bash", { command: 'git commit -m "feat: x" -m "the body"' });
  assert.equal(result?.block, true);
  assert.match(result.reason, /BLOCKED by coding-guides: multiple -m flags/);
  assert.match(result.reason, /git commit -m "<type>: one-line summary"/);
});

test("blocks a newline inside -m", { skip: !(HAS_JQ && HAS_GREP_P) && "jq or grep -P unavailable" }, () => {
  const result = toolCall("bash", { command: 'git commit -m "feat: x\n\n- bullet"' });
  assert.equal(result?.block, true);
  assert.match(result.reason, /spans multiple lines/);
});

test("allows a single-line commit and other commands", () => {
  assert.equal(toolCall("bash", { command: 'git add -A && git commit -m "fix: bug"' }), undefined);
  assert.equal(toolCall("bash", { command: "ls -la" }), undefined);
});

test("ignores tools other than bash", () => {
  assert.equal(toolCall("write", { path: "x", content: 'git commit -m "a" -m "b"' }), undefined);
});
