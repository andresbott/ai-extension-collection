import { test } from "node:test";
import assert from "node:assert/strict";

import piRename from "./index.ts";

// A minimal stand-in for the slice of Pi's ExtensionAPI the extension uses.
function makeFakePi() {
  const commands = new Map();
  const names = [];
  const handlers = new Map();
  const pi = {
    registerCommand: (name, opts) => commands.set(name, opts),
    setSessionName: (name) => names.push(name),
    on: (event, handler) => handlers.set(event, handler),
  };
  return { pi, commands, names, handlers };
}

const conversation = [
  { type: "message", message: { role: "user", content: "add a /rename command to pi" } },
  { type: "message", message: { role: "assistant", content: [{ type: "text", text: "Done." }] } },
];

function makeCtx({ entries = conversation, reply, auth = true, model = { name: "m" }, fail } = {}) {
  const notes = [];
  const calls = [];
  const ctx = {
    model,
    signal: undefined,
    sessionManager: { getBranch: () => entries },
    modelRegistry: {
      hasConfiguredAuth: () => auth,
      streamSimple: (m, context, options) => {
        calls.push({ model: m, context, options });
        return {
          result: async () => {
            if (fail) throw new Error(fail);
            return reply ?? { stopReason: "stop", content: [{ type: "text", text: '"Add Rename Command"' }] };
          },
        };
      },
    },
    ui: { notify: (message, level) => notes.push({ message, level }) },
  };
  return { ctx, notes, calls };
}

test("registers only a /rename command, no automatic hooks", () => {
  const { pi, commands, handlers } = makeFakePi();
  piRename(pi);
  assert.ok(commands.has("rename"), "rename command registered");
  assert.equal(typeof commands.get("rename").handler, "function");
  assert.equal(handlers.size, 0, "no event handlers, so naming never runs on its own");
});

test('/rename "title" sets the title verbatim without calling a model', async () => {
  const { pi, commands, names } = makeFakePi();
  piRename(pi);
  const { ctx, calls, notes } = makeCtx();

  await commands.get("rename").handler('"My exact Title."', ctx);

  assert.deepEqual(names, ["My exact Title."]);
  assert.equal(calls.length, 0, "no model call for a typed title");
  assert.match(notes.at(-1).message, /Session named: My exact Title\./);
});

test("bare /rename asks the current model and applies the cleaned name", async () => {
  const { pi, commands, names } = makeFakePi();
  piRename(pi);
  const { ctx, calls, notes } = makeCtx();

  await commands.get("rename").handler("", ctx);

  assert.deepEqual(names, ["Add Rename Command"]);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].model, ctx.model);
  assert.equal(calls[0].options.cacheRetention, "none");
  assert.equal(typeof calls[0].options.sessionId, "string");
  const prompt = calls[0].context.messages[0].content[0].text;
  assert.match(prompt, /User: add a \/rename command to pi/);
  assert.match(notes.at(-1).message, /Session named: Add Rename Command/);
});

test("bare /rename on an empty session warns and names nothing", async () => {
  const { pi, commands, names } = makeFakePi();
  piRename(pi);
  const { ctx, calls, notes } = makeCtx({ entries: [] });

  await commands.get("rename").handler("", ctx);

  assert.deepEqual(names, []);
  assert.equal(calls.length, 0);
  assert.equal(notes.at(-1).level, "warning");
});

test("bare /rename without a usable model warns and names nothing", async () => {
  // null, not undefined: undefined would fall back to makeCtx's default model.
  for (const opts of [{ model: null }, { auth: false }]) {
    const { pi, commands, names } = makeFakePi();
    piRename(pi);
    const { ctx, calls, notes } = makeCtx(opts);

    await commands.get("rename").handler("", ctx);

    assert.deepEqual(names, []);
    assert.equal(calls.length, 0);
    assert.equal(notes.at(-1).level, "warning");
  }
});

test("a failed model call reports an error and keeps the old name", async () => {
  const cases = [
    { fail: "network down" },
    { reply: { stopReason: "error", errorMessage: "rate limited", content: [] } },
    { reply: { stopReason: "aborted", content: [] } },
  ];
  for (const opts of cases) {
    const { pi, commands, names } = makeFakePi();
    piRename(pi);
    const { ctx, notes } = makeCtx(opts);

    await commands.get("rename").handler("", ctx);

    assert.deepEqual(names, []);
    assert.equal(notes.at(-1).level, "error");
  }
});

test("an empty model reply warns and names nothing", async () => {
  const { pi, commands, names } = makeFakePi();
  piRename(pi);
  const { ctx, notes } = makeCtx({ reply: { stopReason: "stop", content: [{ type: "text", text: "  " }] } });

  await commands.get("rename").handler("", ctx);

  assert.deepEqual(names, []);
  assert.equal(notes.at(-1).level, "warning");
});
