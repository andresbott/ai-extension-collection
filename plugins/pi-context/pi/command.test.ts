import assert from "node:assert/strict";
import { test } from "node:test";

import { CONTEXT_ENTRY, registerContext } from "./command.ts";

// A minimal stand-in for the slice of Pi's ExtensionAPI the extension uses.
// sendMessage is recorded so a test can prove the breakdown never reaches the model.
function makeFakePi({ settings = {} as unknown, active = ["read", "ffgrep"] } = {}) {
  const commands = new Map();
  const renderers = new Map();
  const entries: { customType: string; data: any }[] = [];
  const sent: unknown[] = [];
  const pi = {
    registerCommand: (name: string, opts: unknown) => commands.set(name, opts),
    registerEntryRenderer: (type: string, renderer: unknown) => renderers.set(type, renderer),
    appendEntry: (customType: string, data: unknown) => entries.push({ customType, data }),
    sendMessage: (message: unknown) => sent.push(message),
    getSettings: () => settings,
    getActiveTools: () => active,
    getAllTools: () => [
      { name: "read", description: "Read a file", parameters: {}, sourceInfo: { path: "builtin:read" } },
      { name: "ffgrep", description: "Grep", parameters: {}, sourceInfo: { path: "/n/pi-fff/index.ts" } },
      { name: "unused", description: "Not active", parameters: {}, sourceInfo: { path: "/n/x/index.ts" } },
    ],
  };
  return { pi, commands, renderers, entries, sent };
}

const systemMessage = {
  role: "system",
  content: "",
  sections: {
    preamble: "You are pi.",
    "coding-guides": "<coding-guides>\nguides\n</coding-guides>",
  },
  toolsAdded: [
    { name: "read", description: "Read a file", parameters: {} },
    { name: "mcp__docs__search", description: "Search docs", parameters: {} },
  ],
};

function makeCtx({
  mode = "tui",
  usage = { tokens: 40_000, contextWindow: 200_000, percent: 20 } as unknown,
  model = { provider: "anthropic", id: "claude-opus", name: "Claude Opus", contextWindow: 200_000 } as unknown,
  messages = [systemMessage, { role: "user", content: "hi" }] as unknown[],
  systemPrompt = "You are pi.\n\n<cwd>\n/repo\n</cwd>",
} = {}) {
  const notes: { message: string; level: string }[] = [];
  const ctx = {
    mode,
    model,
    cwd: "/repo",
    getContextUsage: () => usage,
    getSystemPrompt: () => systemPrompt,
    sessionManager: { buildSessionProjection: () => ({ messages }) },
    ui: { notify: (message: string, level: string) => notes.push({ message, level }) },
  };
  return { ctx, notes };
}

async function run(fake: ReturnType<typeof makeFakePi>, ctx: unknown) {
  registerContext(fake.pi as any, (() => undefined) as any);
  await fake.commands.get("context").handler("", ctx);
}

test("registers /context and its entry renderer", () => {
  const fake = makeFakePi();
  const renderer = () => undefined;
  registerContext(fake.pi as any, renderer as any);
  assert.equal(typeof fake.commands.get("context").handler, "function");
  assert.equal(fake.renderers.get(CONTEXT_ENTRY), renderer);
});

test("in the TUI it stores the breakdown as an entry, never as a model message", async () => {
  const fake = makeFakePi();
  const { ctx, notes } = makeCtx();
  await run(fake, ctx);

  assert.equal(fake.sent.length, 0);
  assert.equal(notes.length, 0);
  assert.equal(fake.entries.length, 1);
  const { customType, data } = fake.entries[0];
  assert.equal(customType, CONTEXT_ENTRY);
  assert.equal(data.model, "Claude Opus");
  assert.equal(data.usedTokens, 40_000);
  assert.equal(data.autoCompactBufferTokens, 16384);
  // Sections and tools come from the transcript's system message, not the base prompt.
  assert.deepEqual(
    data.details.map((g: any) => g.title),
    ["MCP tools", "Extension prompts"],
  );
});

test("before the first request it falls back to the base prompt and the active tools", async () => {
  const fake = makeFakePi();
  const { ctx } = makeCtx({ messages: [], usage: { tokens: 0, contextWindow: 200_000, percent: 0 } });
  await run(fake, ctx);

  const data = fake.entries[0].data;
  const tools = data.details.find((g: any) => g.title === "Extension tools").items.map((i: any) => i.name);
  assert.deepEqual(tools, ["ffgrep"]);
  assert.ok(data.categories.find((c: any) => c.id === "systemTools").tokens > 0);
});

test("other modes get the plain-text panel as a notification", async () => {
  const fake = makeFakePi();
  const { ctx, notes } = makeCtx({ mode: "rpc" });
  await run(fake, ctx);

  assert.equal(fake.entries.length, 0);
  assert.equal(notes.length, 1);
  assert.match(notes[0].message, /^Context Usage\n\n/);
  assert.match(notes[0].message, /Claude Opus · 40k\/200k tokens \(20\.0%\)/);
  assert.match(notes[0].message, /\nMCP tools\n└ mcp__docs__search: \d+ tokens/);
});

test("respects compaction settings, including per-model overrides", async () => {
  const off = makeFakePi({ settings: { compaction: { enabled: false } } });
  await run(off, makeCtx().ctx);
  assert.equal(off.entries[0].data.autoCompactBufferTokens, 0);

  const override = makeFakePi({
    settings: { compaction: { reserveTokens: 30_000, modelOverrides: { "anthropic/claude-opus": { reserveTokens: 50_000 } } } },
  });
  await run(override, makeCtx().ctx);
  assert.equal(override.entries[0].data.autoCompactBufferTokens, 50_000);
});

test("warns when there is no model to measure against", async () => {
  const fake = makeFakePi();
  const { ctx, notes } = makeCtx({ usage: null, model: null });
  await run(fake, ctx);
  assert.equal(fake.entries.length, 0);
  assert.equal(notes[0].level, "warning");
  assert.match(notes[0].message, /unavailable/);
});
