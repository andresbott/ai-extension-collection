import assert from "node:assert/strict";
import { test } from "node:test";

import { buildTranscript } from "./transcript.ts";

const msg = (role: string, content: unknown) => ({ type: "message", message: { role, content } });

test("keeps user and assistant text only", () => {
  const entries = [
    msg("user", "add a /rename command"),
    msg("assistant", [
      { type: "thinking", thinking: "hmm" },
      { type: "text", text: "Sure." },
      { type: "toolCall", name: "read", arguments: {} },
    ]),
    msg("toolResult", [{ type: "text", text: "file contents" }]),
    { type: "model_change" },
    { type: "custom", customType: "session-summary", data: { summary: "old summary" } },
    msg("assistant", [{ type: "toolCall", name: "bash", arguments: {} }]),
  ];
  assert.equal(buildTranscript(entries, 1000), "User: add a /rename command\n\nAssistant: Sure.");
});

test("returns an empty string for an empty session", () => {
  assert.equal(buildTranscript([], 1000), "");
  assert.equal(buildTranscript([{ type: "model_change" }], 1000), "");
});

test("keeps the start and the end when over budget", () => {
  const entries = [msg("user", "GOAL " + "a".repeat(500)), msg("assistant", "b".repeat(500) + " NOW")];
  const out = buildTranscript(entries, 200);
  assert.ok(out.length <= 200, `length ${out.length} within budget`);
  assert.ok(out.startsWith("User: GOAL"));
  assert.ok(out.endsWith("NOW"));
  assert.match(out, /\[…\]/);
});

test("leaves a transcript exactly at budget untouched", () => {
  const entries = [msg("user", "hi"), msg("assistant", "hello")];
  // "User: hi" (8) + "\n\n" (2) + "Assistant: hello" (16) = 26 characters.
  assert.equal(buildTranscript(entries, 26), "User: hi\n\nAssistant: hello");
});
