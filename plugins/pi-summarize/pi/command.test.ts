import assert from "node:assert/strict";
import { test } from "node:test";

import { registerSummarize } from "./command.ts";

// A minimal stand-in for the slice of Pi's ExtensionAPI the extension uses.
// sendMessage is recorded so a test can prove the summary never reaches the model.
function makeFakePi() {
  const commands = new Map();
  const renderers = new Map();
  const handlers = new Map();
  const entries: { customType: string; data: any }[] = [];
  const sent: unknown[] = [];
  const pi = {
    registerCommand: (name: string, opts: unknown) => commands.set(name, opts),
    registerEntryRenderer: (type: string, renderer: unknown) => renderers.set(type, renderer),
    appendEntry: (customType: string, data: unknown) => entries.push({ customType, data }),
    sendMessage: (message: unknown) => sent.push(message),
    on: (event: string, handler: unknown) => handlers.set(event, handler),
  };
  return { pi, commands, renderers, handlers, entries, sent };
}

const conversation = [
  { type: "message", message: { role: "user", content: "add a /summarize command to pi" } },
  { type: "message", message: { role: "assistant", content: [{ type: "text", text: "Done." }] } },
];

const SUMMARY = "## Goal\nAdd /summarize.\n\n## Next steps\nShip it.";

function makeCtx({
  entries = conversation as unknown[],
  reply = undefined as unknown,
  auth = true,
  model = { provider: "p", id: "m" } as unknown,
  available = [] as unknown[],
  fail = undefined as string | undefined,
  mode = "tui",
} = {}) {
  const notes: { message: string; level: string }[] = [];
  const calls: { model: unknown; context: any; options: any }[] = [];
  const ctx = {
    mode,
    model,
    signal: undefined,
    sessionManager: { getBranch: () => entries },
    modelRegistry: {
      getAvailable: () => available,
      hasConfiguredAuth: () => auth,
      streamSimple: (m: unknown, context: unknown, options: unknown) => {
        calls.push({ model: m, context, options });
        return {
          result: async () => {
            if (fail) throw new Error(fail);
            return reply ?? { stopReason: "stop", content: [{ type: "text", text: `\n${SUMMARY}\n\n` }] };
          },
        };
      },
    },
    ui: { notify: (message: string, level: string) => notes.push({ message, level }) },
  };
  return { ctx, notes, calls };
}

const render = () => undefined;

function setup() {
  const fake = makeFakePi();
  registerSummarize(fake.pi as any, render);
  return { ...fake, run: (ctx: unknown) => fake.commands.get("summarize").handler("", ctx) };
}

test("registers /summarize and the renderer for its entries, with no automatic hooks", () => {
  const { commands, renderers, handlers } = setup();
  assert.equal(typeof commands.get("summarize").handler, "function");
  assert.equal(renderers.size, 1);
  const [[type, renderer]] = [...renderers];
  assert.equal(renderer, render);
  assert.equal(type, "session-summary");
  assert.equal(handlers.size, 0, "no event handlers, so summarizing never runs on its own");
});

test("summarizes with the newest Sonnet, preferring the session's provider", async () => {
  const { run, entries } = setup();
  const copilotSonnet = { provider: "github-copilot", id: "claude-sonnet-4.6" };
  const available = [{ provider: "anthropic", id: "claude-sonnet-5" }, copilotSonnet];
  const { ctx, calls, notes } = makeCtx({ model: { provider: "github-copilot", id: "claude-opus-5" }, available });

  await run(ctx);

  assert.equal(calls.length, 1);
  assert.equal(calls[0].model, copilotSonnet);
  assert.equal(calls[0].options.cacheRetention, "none");
  assert.match(calls[0].context.messages[0].content[0].text, /User: add a \/summarize command to pi\n\nAssistant: Done\./);
  assert.ok(notes.some((n) => n.message.includes("claude-sonnet-4.6")), "tells the user which model summarizes");
  assert.equal(entries.length, 1);
  assert.equal(entries[0].data.model, "github-copilot/claude-sonnet-4.6");
});

test("stores the trimmed summary as a session entry that is never sent to the model", async () => {
  const { run, entries, sent } = setup();
  const { ctx } = makeCtx();

  await run(ctx);

  assert.equal(entries.length, 1);
  assert.equal(entries[0].customType, "session-summary");
  assert.equal(entries[0].data.summary, SUMMARY);
  assert.equal(typeof entries[0].data.timestamp, "number");
  assert.deepEqual(sent, [], "nothing goes into the model's context");
});

test("falls back to the session model when no Sonnet is available", async () => {
  const { run, entries } = setup();
  const { ctx, calls } = makeCtx({ available: [{ provider: "p", id: "gpt-5.4-mini" }] });

  await run(ctx);

  assert.equal(calls[0].model, ctx.model);
  assert.equal(entries[0].data.model, "p/m");
});

test("in the TUI the entry is the output; elsewhere the summary is also notified", async () => {
  {
    const { run } = setup();
    const { ctx, notes } = makeCtx({ mode: "tui" });
    await run(ctx);
    assert.ok(!notes.some((n) => n.message.includes(SUMMARY)));
  }
  {
    const { run } = setup();
    const { ctx, notes } = makeCtx({ mode: "rpc" });
    await run(ctx);
    assert.ok(notes.some((n) => n.message.includes(SUMMARY) && n.level === "info"));
  }
});

test("an empty session warns and calls nothing", async () => {
  const { run, entries } = setup();
  const { ctx, calls, notes } = makeCtx({ entries: [] });

  await run(ctx);

  assert.equal(calls.length, 0);
  assert.deepEqual(entries, []);
  assert.equal(notes.at(-1)?.level, "warning");
});

test("no usable model warns and calls nothing", async () => {
  // null, not undefined: undefined would fall back to makeCtx's default model.
  for (const opts of [{ model: null }, { auth: false }]) {
    const { run, entries } = setup();
    const { ctx, calls, notes } = makeCtx(opts);

    await run(ctx);

    assert.equal(calls.length, 0);
    assert.deepEqual(entries, []);
    assert.equal(notes.at(-1)?.level, "warning");
  }
});

test("a failed model call reports an error and stores nothing", async () => {
  const cases = [
    { fail: "network down" },
    { reply: { stopReason: "error", errorMessage: "rate limited", content: [] } },
    { reply: { stopReason: "aborted", content: [] } },
  ];
  for (const opts of cases) {
    const { run, entries } = setup();
    const { ctx, notes } = makeCtx(opts);

    await run(ctx);

    assert.deepEqual(entries, []);
    assert.equal(notes.at(-1)?.level, "error");
  }
});

test("an empty model reply warns and stores nothing", async () => {
  const { run, entries } = setup();
  const { ctx, notes } = makeCtx({ reply: { stopReason: "stop", content: [{ type: "text", text: " \n " }] } });

  await run(ctx);

  assert.deepEqual(entries, []);
  assert.equal(notes.at(-1)?.level, "warning");
});
