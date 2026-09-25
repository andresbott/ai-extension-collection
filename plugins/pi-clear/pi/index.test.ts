import { test } from "node:test";
import assert from "node:assert/strict";

import piClear from "./index.ts";

// A minimal stand-in for the slice of Pi's ExtensionAPI the extension uses.
function makeFakePi() {
  const commands = new Map();
  const handlers = new Map();
  const pi = {
    registerCommand: (name, opts) => commands.set(name, opts),
    on: (event, handler) => handlers.set(event, handler),
  };
  return { pi, commands, handlers };
}

test("registers a /clear command and a context handler", () => {
  const { pi, commands, handlers } = makeFakePi();
  piClear(pi);
  assert.ok(commands.has("clear"), "clear command registered");
  assert.equal(typeof commands.get("clear").handler, "function");
  assert.ok(handlers.has("context"), "context handler registered");
});

test("context handler is a no-op until /clear is invoked", () => {
  const { pi, handlers } = makeFakePi();
  piClear(pi);
  const onContext = handlers.get("context");
  assert.equal(onContext({ type: "context", messages: ["a", "b"] }), undefined);
});

test("after /clear the context handler hides the prior conversation", async () => {
  const { pi, commands, handlers } = makeFakePi();
  piClear(pi);
  const notes = [];
  const ctx = { ui: { notify: (m) => notes.push(m) } };

  await commands.get("clear").handler("", ctx);
  const result = handlers.get("context")({
    type: "context",
    messages: ["a", "b", "c", "u"],
  });

  assert.deepEqual(result, { messages: ["u"] });
  assert.equal(notes.length, 1, "user notified once");
});
