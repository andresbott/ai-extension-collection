import assert from "node:assert/strict";
import { test } from "node:test";

import type { ContextBreakdown } from "./breakdown.ts";
import { formatTokens, gridColumns, percentString, planCells, PLAIN, renderReport, type Style } from "./report.ts";

function breakdown(overrides: Partial<ContextBreakdown> = {}): ContextBreakdown {
  return {
    model: "Claude Opus",
    contextWindow: 200_000,
    usedTokens: 50_000,
    estimated: false,
    categories: [
      { id: "systemPrompt", label: "System prompt", tokens: 3_000 },
      { id: "systemTools", label: "System tools", tokens: 7_000 },
      { id: "extensionTools", label: "Extension tools", tokens: 0 },
      { id: "mcpTools", label: "MCP tools", tokens: 400 },
      { id: "extensionPrompts", label: "Extension prompts", tokens: 0 },
      { id: "memoryFiles", label: "Memory files", tokens: 600 },
      { id: "skills", label: "Skills", tokens: 2_000 },
      { id: "messages", label: "Messages", tokens: 37_000 },
    ],
    freeTokens: 133_616,
    autoCompactBufferTokens: 16_384,
    details: [
      { title: "MCP tools", items: [{ name: "mcp__context7", tokens: 400 }] },
      { title: "Memory files", items: [{ name: "AGENTS.md", tokens: 600 }] },
    ],
    ...overrides,
  };
}

test("formatTokens compacts like Claude Code", () => {
  assert.equal(formatTokens(842), "842");
  assert.equal(formatTokens(1_000), "1k");
  assert.equal(formatTokens(1_440), "1.4k");
  assert.equal(formatTokens(45_230), "45.2k");
  assert.equal(formatTokens(200_000), "200k");
  assert.equal(formatTokens(1_000_000), "1M");
  assert.equal(formatTokens(-5), "0");
});

test("percentString shows one decimal and flags tiny shares", () => {
  assert.equal(percentString(50_000, 200_000), "25.0%");
  assert.equal(percentString(10, 200_000), "<0.1%");
  assert.equal(percentString(0, 200_000), "0.0%");
  assert.equal(percentString(5, 0), "0%");
});

test("grid is 10 wide for standard windows, 20 past 200k", () => {
  assert.equal(gridColumns(200_000), 10);
  assert.equal(gridColumns(1_000_000), 20);
});

test("planCells fills categories, then free, then the buffer, always exactly the grid size", () => {
  const cells = planCells(breakdown(), 100);
  assert.equal(cells.length, 100);
  assert.equal(cells.filter((c) => c.glyph === "⛃").length, Math.round(37_000 / 2_000));
  assert.equal(cells.at(-1)!.glyph, "⛝");
  assert.equal(cells.filter((c) => c.glyph === "⛝").length, Math.round(16_384 / 2_000));
  // A category smaller than one cell still gets one.
  assert.equal(cells.filter((c) => c.color === "syntaxKeyword").length, 1);
});

test("planCells never overruns the grid when rounding piles up", () => {
  const full = breakdown({
    usedTokens: 200_000,
    freeTokens: 0,
    autoCompactBufferTokens: 0,
    categories: breakdown().categories.map((c) => ({ ...c, tokens: c.id === "messages" ? 190_000 : 1_500 })),
  });
  const cells = planCells(full, 100);
  assert.equal(cells.length, 100);
  assert.ok(cells.every((c) => c.glyph !== "⛶"));
});

test("renderReport puts the legend beside the grid and the lists below", () => {
  const lines = renderReport(breakdown(), PLAIN);
  assert.match(lines[0], /^(⛁|⛃|⛶|⛝)( (⛁|⛃|⛶|⛝)){9} {3}Claude Opus · 50k\/200k tokens \(25\.0%\)$/);
  const text = lines.join("\n");
  assert.match(text, /⛁ System prompt: 3k tokens \(1\.5%\)/);
  assert.match(text, /⛃ Messages: 37k tokens \(18\.5%\)/);
  assert.match(text, /⛶ Free space: 134k \(66\.8%\)/);
  assert.match(text, /⛝ Autocompact buffer: 16\.4k tokens \(8\.2%\)/);
  assert.doesNotMatch(text, /Extension tools:/, "zero categories are hidden");
  assert.match(text, /\nMCP tools\n└ mcp__context7: 400 tokens\n\nMemory files\n└ AGENTS\.md: 600 tokens$/);
});

test("renderReport marks an estimated total and colors through the style", () => {
  const tagged: Style = { fg: (color, text) => `[${color}:${text}]`, bold: (text) => `*${text}*` };
  const lines = renderReport(breakdown({ estimated: true }), tagged);
  assert.match(lines[0], /\[muted: \(25\.0%, estimated\)\]$/);
  assert.match(lines.join("\n"), /\[syntaxKeyword:⛁\] MCP tools: \*400\*/);
});
