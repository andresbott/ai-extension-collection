import assert from "node:assert/strict";
import { test } from "node:test";

import { pickModel } from "./models.ts";

const m = (provider: string, id: string) => ({ provider, id });

const MID = [/sonnet/i, /-pro$/i];

test("the earliest family wins on the session's provider", () => {
  const available = [m("copilot", "gemini-3.1-pro"), m("copilot", "claude-sonnet-5"), m("copilot", "claude-opus-5")];
  assert.deepEqual(pickModel(available, MID, "copilot"), m("copilot", "claude-sonnet-5"));
});

test("the session's provider beats an earlier family elsewhere", () => {
  const available = [m("anthropic", "claude-sonnet-5"), m("google", "gemini-3.1-pro")];
  assert.deepEqual(pickModel(available, MID, "google"), m("google", "gemini-3.1-pro"));
});

test("picks the newest version within a family", () => {
  const dashed = [m("anthropic", "claude-sonnet-4-5-20250929"), m("anthropic", "claude-sonnet-5"), m("anthropic", "claude-sonnet-4-6")];
  assert.deepEqual(pickModel(dashed, MID, "anthropic"), m("anthropic", "claude-sonnet-5"));
  const dotted = [m("copilot", "claude-sonnet-4.6"), m("copilot", "claude-sonnet-4.10")];
  assert.deepEqual(pickModel(dotted, MID, "copilot"), m("copilot", "claude-sonnet-4.10"));
});

test("falls back to any provider when the session's has no match", () => {
  const available = [m("local", "llama-70b"), m("anthropic", "claude-sonnet-5")];
  assert.deepEqual(pickModel(available, MID, "local"), m("anthropic", "claude-sonnet-5"));
});

test("without a session provider every provider is searched", () => {
  const available = [m("local", "llama-70b"), m("anthropic", "claude-sonnet-5")];
  assert.deepEqual(pickModel(available, MID), m("anthropic", "claude-sonnet-5"));
});

test("returns undefined when no family matches", () => {
  assert.equal(pickModel([m("x", "claude-opus-5")], MID, "x"), undefined);
  assert.equal(pickModel([m("x", "claude-sonnet-5")], [], "x"), undefined);
  assert.equal(pickModel([], MID, undefined), undefined);
});
