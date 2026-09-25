import { test } from "node:test";
import assert from "node:assert/strict";

import piContext from "./index.ts";

function makeFakePi() {
  const commands = new Map();
  const pi = { registerCommand: (name, opts) => commands.set(name, opts) };
  return { pi, commands };
}

test("registers a /context command", () => {
  const { pi, commands } = makeFakePi();
  piContext(pi);
  assert.ok(commands.has("context"), "context command registered");
  assert.equal(typeof commands.get("context").handler, "function");
});

test("/context reports usage from getContextUsage via notify", async () => {
  const { pi, commands } = makeFakePi();
  piContext(pi);
  const notes = [];
  const ctx = {
    getContextUsage: () => ({ tokens: 50000, contextWindow: 200000, percent: 25 }),
    model: { name: "kimi-k3" },
    ui: { notify: (m) => notes.push(m) },
  };

  await commands.get("context").handler("", ctx);

  assert.equal(notes.length, 1);
  assert.match(
    notes[0],
    /50,000 \/ 200,000 tokens \(25%\), 150,000 free \(kimi-k3\)/,
  );
});
