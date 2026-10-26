// Renders a ContextBreakdown as the Claude-Code-style /context panel: a grid of
// cells (one glyph per slice of the window, colored by category) with a legend
// beside it, then the per-item lists. Pure: colors go through a Style, so the
// TUI passes pi's theme and other modes pass PLAIN.
//
// The grid and legend are ported from oh-my-pi's
// packages/tui/src/status-line/context-usage.ts
// (MIT License, Copyright (c) 2025 Mario Zechner, (c) 2025-2026 Can Bölük,
// (c) 2026 Stencil Labs, Inc.; full notice in ../THIRD_PARTY_NOTICES.md).

import type { CategoryId, ContextBreakdown } from "./breakdown.ts";

export interface Style {
  fg(color: string, text: string): string;
  bold(text: string): string;
}

export const PLAIN: Style = { fg: (_color, text) => text, bold: (text) => text };

const CELL_FILLED = "⛁";
const CELL_MESSAGES = "⛃";
const CELL_FREE = "⛶";
const CELL_BUFFER = "⛝";
const GRID_ROWS = 10;
const GUTTER = "   ";

/** Theme color per category; distinct hues in pi's default themes. */
const COLORS: Record<CategoryId, string> = {
  systemPrompt: "muted",
  systemTools: "warning",
  extensionTools: "error",
  mcpTools: "syntaxKeyword",
  extensionPrompts: "accent",
  memoryFiles: "syntaxString",
  skills: "success",
  messages: "userMessageText",
};

const glyphFor = (id: CategoryId) => (id === "messages" ? CELL_MESSAGES : CELL_FILLED);

/** Claude Code draws 10×10 for standard windows and widens to 20 columns past 200k. */
export function gridColumns(contextWindow: number): number {
  return contextWindow > 200_000 ? 20 : 10;
}

/** Compact token count: 842, 1.4k, 45.2k, 200k, 1M. */
export function formatTokens(n: number): string {
  const value = Math.max(0, Math.round(n));
  if (value < 1000) return String(value);
  if (value < 1_000_000) {
    const k = value / 1000;
    return `${k < 100 ? k.toFixed(1).replace(/\.0$/, "") : Math.round(k)}k`;
  }
  return `${(value / 1_000_000).toFixed(1).replace(/\.0$/, "")}M`;
}

export function percentString(part: number, whole: number): string {
  if (whole <= 0) return "0%";
  const pct = (part / whole) * 100;
  if (pct > 0 && pct < 0.05) return "<0.1%";
  return `${pct.toFixed(1)}%`;
}

interface Cell {
  glyph: string;
  color: string;
}

/** One cell per window slice: categories in order, then free space, then the autocompact buffer at the end. */
export function planCells(breakdown: ContextBreakdown, total: number): Cell[] {
  const window = breakdown.contextWindow;
  const free = (): Cell => ({ glyph: CELL_FREE, color: "dim" });
  if (window <= 0) return Array.from({ length: total }, free);

  const perCell = window / total;
  const cellsFor = (tokens: number) => (tokens <= 0 ? 0 : Math.max(1, Math.round(tokens / perCell)));

  const counts = breakdown.categories.map((category) => ({ category, count: cellsFor(category.tokens) }));
  let buffer = cellsFor(breakdown.autoCompactBufferTokens);
  let used = counts.reduce((sum, c) => sum + c.count, 0);

  // Rounding up small categories can overrun the grid: trim the largest first so small ones stay visible.
  const usable = total - buffer;
  if (used > usable) {
    let overflow = used - usable;
    for (const entry of [...counts].sort((a, b) => b.count - a.count)) {
      while (overflow > 0 && entry.count > 1) {
        entry.count -= 1;
        overflow -= 1;
      }
    }
    used = counts.reduce((sum, c) => sum + c.count, 0);
    if (used + buffer > total) buffer = Math.max(0, total - used);
  }

  const cells: Cell[] = [];
  for (const { category, count } of counts) {
    for (let i = 0; i < count; i++) cells.push({ glyph: glyphFor(category.id), color: COLORS[category.id] });
  }
  const freeCount = Math.max(0, total - cells.length - buffer);
  for (let i = 0; i < freeCount; i++) cells.push(free());
  for (let i = 0; i < buffer; i++) cells.push({ glyph: CELL_BUFFER, color: "dim" });
  while (cells.length < total) cells.push(free());
  return cells.slice(0, total);
}

function legendLines(breakdown: ContextBreakdown, style: Style): string[] {
  const { contextWindow: window, usedTokens } = breakdown;
  const pct = percentString(usedTokens, window);
  const lines = [
    style.bold(breakdown.model) +
      style.fg("dim", " · ") +
      style.bold(formatTokens(usedTokens)) +
      style.fg("dim", `/${formatTokens(window)} tokens`) +
      style.fg("muted", ` (${pct}${breakdown.estimated ? ", estimated" : ""})`),
    "",
    style.fg("muted", "Estimated usage by category"),
  ];
  for (const category of breakdown.categories) {
    if (category.tokens <= 0 && category.id !== "messages") continue;
    lines.push(
      `${style.fg(COLORS[category.id], glyphFor(category.id))} ${category.label}: ` +
        `${style.bold(formatTokens(category.tokens))} ` +
        style.fg("dim", `tokens (${percentString(category.tokens, window)})`),
    );
  }
  lines.push(
    `${style.fg("dim", CELL_FREE)} Free space: ${style.bold(formatTokens(breakdown.freeTokens))} ` +
      style.fg("dim", `(${percentString(breakdown.freeTokens, window)})`),
  );
  if (breakdown.autoCompactBufferTokens > 0) {
    lines.push(
      `${style.fg("dim", CELL_BUFFER)} Autocompact buffer: ${style.bold(formatTokens(breakdown.autoCompactBufferTokens))} ` +
        style.fg("dim", `tokens (${percentString(breakdown.autoCompactBufferTokens, window)})`),
    );
  }
  return lines;
}

/** The whole panel: grid beside the legend, then one block per non-empty detail group. */
export function renderReport(breakdown: ContextBreakdown, style: Style): string[] {
  const columns = gridColumns(breakdown.contextWindow);
  const cells = planCells(breakdown, columns * GRID_ROWS);
  const legend = legendLines(breakdown, style);
  const blank = " ".repeat(columns * 2 - 1);

  const lines: string[] = [];
  for (let row = 0; row < Math.max(GRID_ROWS, legend.length); row++) {
    const grid =
      row < GRID_ROWS
        ? cells
            .slice(row * columns, (row + 1) * columns)
            .map((cell) => style.fg(cell.color, cell.glyph))
            .join(" ")
        : blank;
    const text = legend[row] ?? "";
    lines.push(text ? `${grid}${GUTTER}${text}` : grid.trimEnd());
  }

  for (const group of breakdown.details) {
    lines.push("", style.bold(group.title));
    for (const item of group.items) {
      lines.push(`${style.fg("dim", "└")} ${item.name}: ${style.fg("dim", `${formatTokens(item.tokens)} tokens`)}`);
    }
  }
  return lines;
}
