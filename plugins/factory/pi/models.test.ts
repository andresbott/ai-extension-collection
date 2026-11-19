import assert from "node:assert/strict";
import { test } from "node:test";

import { findModel, pickCheapModel } from "./models.ts";

const m = (provider: string, id: string) => ({ provider, id });

const copilot = [
  m("github-copilot", "claude-opus-5.5"),
  m("github-copilot", "claude-haiku-4.5"),
  m("github-copilot", "claude-sonnet-5"),
  m("github-copilot", "gpt-5-mini"),
  m("github-copilot", "gpt-5.4-mini"),
  m("github-copilot", "gemini-3.8-flash"),
];

test("prefers haiku on the session's provider", () => {
  assert.deepEqual(pickCheapModel(copilot, "github-copilot"), m("github-copilot", "claude-haiku-4.5"));
});

test("the session's provider beats a better family elsewhere", () => {
  const available = [m("anthropic", "claude-haiku-4-5"), m("openai", "gpt-5.4"), m("openai", "gpt-5.4-mini")];
  assert.deepEqual(pickCheapModel(available, "openai"), m("openai", "gpt-5.4-mini"));
});

test("picks the newest version within a family", () => {
  const available = [m("openai", "gpt-5-mini"), m("openai", "gpt-5.4-mini"), m("openai", "gpt-5.10-mini")];
  assert.deepEqual(pickCheapModel(available, "openai"), m("openai", "gpt-5.10-mini"));
});

test("falls back to other providers when the session's has no cheap model", () => {
  const available = [m("local", "big-model"), m("google", "gemini-3.8-flash")];
  assert.deepEqual(pickCheapModel(available, "local"), m("google", "gemini-3.8-flash"));
});

test("does not treat -mini variants of other names as gpt minis", () => {
  const available = [m("x", "gpt-5.4-mini-codex"), m("x", "minimax-2")];
  assert.equal(pickCheapModel(available, "x"), undefined);
});

test("returns undefined when nothing cheap is available", () => {
  assert.equal(pickCheapModel([m("x", "claude-opus-5.5")], "x"), undefined);
  assert.equal(pickCheapModel([], "x"), undefined);
  assert.equal(pickCheapModel([], undefined), undefined);
});

test("findModel resolves provider/id and bare ids", () => {
  assert.deepEqual(findModel(copilot, "github-copilot/claude-sonnet-5"), m("github-copilot", "claude-sonnet-5"));
  assert.deepEqual(findModel(copilot, "gpt-5-mini"), m("github-copilot", "gpt-5-mini"));
  assert.equal(findModel(copilot, "openai/gpt-5-mini"), undefined);
  assert.equal(findModel(copilot, "nope"), undefined);
});
