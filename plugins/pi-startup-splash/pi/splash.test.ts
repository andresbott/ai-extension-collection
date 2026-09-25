import assert from "node:assert/strict";
import { test } from "node:test";

import type { SplashData } from "./discovery.ts";
import { drawBox, renderSplash, wrapText } from "./splash.ts";

function makeData(): SplashData {
  return {
    version: "1.2.3",
    cwdLabel: "pi-code-config",
    modelLabel: "anthropic/claude-sonnet-4",
    projectTrusted: true,
    sections: {
      context: { title: "Context", items: ["AGENTS.md", "~/.pi/agent/AGENTS.md"], count: 2 },
      skills: { title: "Skills", items: ["effective-go", "council-mode", "+1 more"], count: 3 },
      prompts: { title: "Prompts", items: ["/review", "/plan", "/deploy"], count: 3 },
      extensions: { title: "Extensions", items: ["startup-splash", "statusline", "render-mode", "pi-context"], count: 4 },
    },
  };
}

function assertFits(lines: string[], width: number): void {
  for (const line of lines) {
    assert.ok(line.length <= width, `line exceeded width ${width}: ${line}`);
  }
}

test("drawBox creates a bounded bordered box", () => {
  const lines = drawBox("Context", ["2 files · AGENTS.md"], 24);
  assert.equal(lines.length, 3);
  assert.equal(lines[0][0], "╭");
  assert.equal(lines[2][0], "╰");
  assertFits(lines, 24);
});

test("wrapText wraps long content without losing words", () => {
  const lines = wrapText("alpha beta gamma delta", 10);
  assert.deepEqual(lines, ["alpha beta", "gamma", "delta"]);
});

test("renderSplash uses a two-column layout on wide terminals", () => {
  const lines = renderSplash(makeData(), 110);
  assertFits(lines, 110);
  assert.ok(lines.some((line) => line.includes("Context")));
  assert.ok(lines.every((line) => !line.includes("Tips")));
  assert.ok(lines.some((line) => line.includes("██████╗ ██╗")));
});

test("renderSplash collapses to one column on narrow terminals", () => {
  const lines = renderSplash(makeData(), 64);
  assertFits(lines, 64);
  const contextLine = lines.findIndex((line) => line.includes("Context"));
  const promptsLine = lines.findIndex((line) => line.includes("Prompts"));
  assert.ok(contextLine > 0);
  assert.ok(promptsLine > contextLine);
});

test("renderSplash handles very narrow widths gracefully", () => {
  const lines = renderSplash(makeData(), 44);
  assertFits(lines, 44);
  assert.ok(lines.some((line) => line.includes("██████╗ ██╗")));
});

test("theming keeps borders uniformly dim while accenting content", () => {
  const theme = {
    fg: (color: string, text: string) => `<${color}>${text}</${color}>`,
    bold: (text: string) => `<b>${text}</b>`,
  };
  const output = renderSplash(makeData(), 110, theme).join("\n");

  assert.match(output, /<dim>╭<\/dim>/);
  assert.match(output, /<b><accent> Context <\/accent><\/b>/);
  assert.doesNotMatch(output, /<accent>[╭╮╰╯│─]/);
  assert.doesNotMatch(output, /<(?:mdLink|success)>[╭╮╰╯│─]/);
});
