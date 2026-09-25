/**
 * pi-basic-statusline — a compact, colored footer (status bar) for Pi,
 * modeled on Claude Code's status line.
 *
 * Renders a single line:
 *   <model> │  <folder> │  <branch> │ ███▎░░░ <pct>% <used>/<window> │ $<cost>
 *   └ blue ┘         └ cwd ┘      └ git ┘ └──── green/yellow/red ────┘  └ total ┘
 *
 * A custom footer REPLACES Pi's built-in one. This stays one line, ANSI-aware,
 * and dependency-free (only the Pi-provided `theme` + Node's `node:path`).
 *
 * API used (Pi ExtensionAPI, v>=0.81, verified against 0.85):
 *   pi.on("session_start", (event, ctx) => …)          — per-session setup
 *   ctx.ui.setFooter((tui, theme, footerData) => renderer)
 *   renderer.render(width) => string[]                  — one entry per footer line
 *
 * Data sources:
 *   model         ctx.model?.id
 *   folder        ctx.cwd (basename, $HOME shown as ~)
 *   git branch    footerData.getGitBranch()
 *   context usage ctx.getContextUsage() -> { contextWindow, tokens, percent }
 *   cost          Σ usage.cost.total over ctx.sessionManager.getEntries()
 *                 (assistant + toolResult messages, compaction/branch summaries) —
 *                 the same accumulation Pi's built-in footer performs. Note the
 *                 field is `usage.cost.total`, not `usage.cost`.
 */

import { basename } from "node:path";

import type { ExtensionAPI, Theme, ThemeColor } from "@earendil-works/pi-coding-agent";

// ── Look & feel (tweak here) ────────────────────────────────────────────────

/** Segment separator. Swap for " | " if you prefer the ASCII pipe. */
const SEP = " \u{2502} "; // │

/**
 * Icons. These are Nerd Font glyphs (private-use area) — install a Nerd Font
 * (https://www.nerdfonts.com) for them to render. If you see a box/tofu, swap
 * for emoji: ICON_FOLDER = "\u{1F4C1}" (📁), ICON_BRANCH = "\u{1F33F}" (🌿).
 */
const ICON_FOLDER = "\u{f07b}"; //  nf-fa-folder
const ICON_BRANCH = "\u{e0a0}"; //  nf-pl-branch

/** Theme colors (semantic names resolved by the active theme). */
const COLOR_MODEL = "mdLink"; // blue (#81a2be in the dark theme); `accent` is teal
const COLOR_ICON = "accent"; // folder/branch glyphs
const COLOR_SEP = "dim";
const COLOR_CTX_OK = "success"; // ≤70%  → green
const COLOR_CTX_WARN = "warning"; // >70%  → yellow
const COLOR_CTX_HIGH = "error"; // >90%  → red

/** Decimal places for the cost figure ($0.00). Pi's own footer uses 3. */
const COST_DECIMALS = 2;

/** Context progress-bar width, in cells. */
const BAR_WIDTH = 8;
const BAR_FULL = "\u{2588}"; // █
const BAR_EMPTY = "\u{2591}"; // ░
// Left-partial blocks for 1..7 eighths of a cell (smooth frontier).
const BAR_EIGHTHS = ["", "\u{258f}", "\u{258e}", "\u{258d}", "\u{258c}", "\u{258b}", "\u{258a}", "\u{2589}"];

// ── Formatting helpers ──────────────────────────────────────────────────────

/** Just the folder name of a path; $HOME collapses to ~. */
function formatFolder(cwd: string): string {
	const home = process.env.HOME || process.env.USERPROFILE || "";
	if (home && cwd === home) return "~";
	return basename(cwd) || cwd;
}

/** Compact token counts, matching Pi's built-in footer: 330000 -> 330k, 1.2e6 -> 1.2M. */
function formatTokens(n: number): string {
	if (n < 1_000) return String(n);
	if (n < 10_000) return (n / 1_000).toFixed(1) + "k";
	if (n < 1_000_000) return Math.round(n / 1_000) + "k";
	if (n < 10_000_000) return (n / 1_000_000).toFixed(1) + "M";
	return Math.round(n / 1_000_000) + "M";
}

/**
 * A fixed-width progress bar for `ratio` (0..1), smooth to 1/8 of a cell.
 * Returns plain (for width math) and colored (filled in `color`, track dim).
 */
function makeBar(
	ratio: number,
	theme: Theme,
	color: ThemeColor,
): { plain: string; colored: string } {
	const clamped = Math.max(0, Math.min(1, ratio));
	const eighths = Math.round(clamped * BAR_WIDTH * 8);
	const full = Math.floor(eighths / 8);
	const rem = eighths % 8;
	let filled = BAR_FULL.repeat(full);
	if (rem > 0) filled += BAR_EIGHTHS[rem];
	const empty = BAR_EMPTY.repeat(Math.max(0, BAR_WIDTH - full - (rem > 0 ? 1 : 0)));
	return {
		plain: filled + empty,
		colored: theme.fg(color, filled) + theme.fg(COLOR_SEP, empty),
	};
}

/**
 * Total cost carried on a usage record. Pi stores it as `usage.cost.total`;
 * we also accept a plain number defensively in case that ever changes.
 */
function usageCostTotal(usage: unknown): number {
	const cost = (usage as { cost?: unknown } | null | undefined)?.cost;
	if (typeof cost === "number") return cost;
	if (cost && typeof (cost as { total?: unknown }).total === "number") {
		return (cost as { total: number }).total;
	}
	return 0;
}

interface CostEntry {
	type: string;
	message?: {
		role?: string;
		usage?: unknown;
	};
	usage?: unknown;
}

/** Sum session cost the same way Pi's built-in footer does. */
function sessionCost(entries: readonly { type: string }[]): number {
	let total = 0;
	for (const entry of entries as readonly CostEntry[]) {
		if (entry.type === "message") {
			const msg = entry.message;
			if (msg?.role === "assistant" || (msg?.role === "toolResult" && msg.usage)) {
				total += usageCostTotal(msg.usage);
			}
		} else if (entry.type === "branch_summary" || entry.type === "compaction") {
			if (entry.usage) total += usageCostTotal(entry.usage);
		}
	}
	return total;
}

/** Truncate a plain (ANSI-free) string to a terminal width, with an ellipsis. */
function truncate(s: string, width: number): string {
	if (width <= 0) return "";
	if (s.length <= width) return s;
	if (width === 1) return "…";
	return s.slice(0, width - 1) + "…";
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		// Only take over the footer in the interactive TUI.
		if (ctx.mode !== "tui") return;

		ctx.ui.setFooter((tui, theme, footerData) => {
			// Re-render when the git branch changes (context/cost update on the
			// TUI's normal repaint cycle).
			const unsubBranch = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose() {
					unsubBranch();
				},

				invalidate() {},

				render(width: number): string[] {
					// Each segment carries both a plain form (for width math /
					// tight-terminal fallback) and a colored form (what we draw).
					const seg: { plain: string; colored: string }[] = [];

					// model — blue
					const model = ctx.model?.id || "no-model";
					seg.push({ plain: model, colored: theme.fg(COLOR_MODEL, model) });

					// folder — icon + basename
					const folder = formatFolder(ctx.cwd);
					seg.push({
						plain: `${ICON_FOLDER} ${folder}`,
						colored: `${theme.fg(COLOR_ICON, ICON_FOLDER)} ${folder}`,
					});

					// git branch — icon + name (only inside a repo)
					const branch = footerData.getGitBranch();
					if (branch) {
						seg.push({
							plain: `${ICON_BRANCH} ${branch}`,
							colored: `${theme.fg(COLOR_ICON, ICON_BRANCH)} ${branch}`,
						});
					}

					// context — progress bar + "<pct>% <used>/<window>", colored by fullness
					const usage = ctx.getContextUsage();
					const window = usage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
					if (window > 0) {
						const tokens = usage?.tokens ?? null;
						const pct = usage?.percent ?? null;
						const usedStr = tokens === null ? "?" : formatTokens(tokens);
						const pctStr = pct === null ? "?" : pct.toFixed(0);
						const p = pct ?? 0;
						const color =
							p > 90 ? COLOR_CTX_HIGH : p > 70 ? COLOR_CTX_WARN : COLOR_CTX_OK;
						const bar = makeBar(p / 100, theme, color);
						const tail = `${pctStr}% ${usedStr}/${formatTokens(window)}`;
						seg.push({
							plain: `${bar.plain} ${tail}`,
							colored: `${bar.colored} ${theme.fg(color, tail)}`,
						});
					}

					// cost — session total
					const cost = sessionCost(ctx.sessionManager.getEntries());
					const costStr = `$${cost.toFixed(COST_DECIMALS)}`;
					seg.push({ plain: costStr, colored: costStr });

					if (width <= 0) return [""];

					const plainLine = seg.map((s) => s.plain).join(SEP);
					const contentWidth = width - 1;
					if (plainLine.length <= contentWidth) {
						return [` ${seg.map((s) => s.colored).join(theme.fg(COLOR_SEP, SEP))}`];
					}
					// Too narrow for color-safe truncation: degrade to plain text.
					return [` ${truncate(plainLine, contentWidth)}`];
				},
			};
		});
	});
}
