/**
 * render-mode — pure mode logic.
 *
 * Every decision the extension makes lives here as a pure function with no
 * imports from the Pi SDK or pi-tui, so it can be unit-tested without the
 * runtime packages installed (they do not resolve from this repo). `index.ts`
 * and `tools.ts` are thin wiring over these helpers.
 *
 * The three modes:
 *   normal   thinking hidden; tool call shown; output truncated (expand w/ ctrl+o)
 *   verbose  thinking shown;  tool call shown; full output
 *   minimal  thinking hidden; NO tool rows at all — just Pi's working spinner,
 *            then the assistant's output
 */

export type RenderMode = "normal" | "verbose" | "minimal";

/** Cycle order for the rotate shortcut. */
export const RENDER_MODES = ["normal", "verbose", "minimal"] as const satisfies readonly RenderMode[];

/**
 * Extension tools whose rows we intentionally suppress in minimal mode.
 *
 * Pi does not currently expose global tool-render middleware, so these names
 * are handled by the narrow ToolExecutionComponent compatibility patch in
 * tools.ts. Unknown tools retain their own rendering.
 */
export const KNOWN_CUSTOM_TOOL_NAMES = new Set([
	// @ff-labs/pi-fff
	"ffgrep",
	"fffind",
	"fff-multi-grep",
	// pi-web-access
	"web_search",
	"source_check",
	"fetch_content",
	"get_search_content",
	// pi-mcp-adapter
	"mcp",
	"mcpScript",
	// pi-lens
	"lens_diagnostics",
	"symbol_search",
	"effective_config",
	"project_report",
	"module_report",
	"read_symbol",
	"read_enclosing",
	"pi_lens_activate_tools",
	"ast_grep_search",
	"ast_grep_replace",
	"ast_grep_outline",
	"lsp_navigation",
	"lens_diagnostic_mark",
	// Subagent engines and dynamic workflows
	"subagent",
	"Agent",
	"SubagentWorkflow",
	"get_subagent_result",
	"steer_subagent",
	"workflow",
	"workflow_control",
]);

export function hideKnownCustomToolRow(mode: RenderMode, toolName: unknown): boolean {
	return mode === "minimal" && typeof toolName === "string" && KNOWN_CUSTOM_TOOL_NAMES.has(toolName);
}

export function isRenderMode(value: unknown): value is RenderMode {
	return typeof value === "string" && (RENDER_MODES as readonly string[]).includes(value);
}

/** Next mode in the cycle, wrapping around. */
export function nextMode(mode: RenderMode): RenderMode {
	const index = RENDER_MODES.indexOf(mode);
	return RENDER_MODES[(index + 1) % RENDER_MODES.length]!;
}

/** Whether thinking blocks should be shown in this mode. */
export function showThinking(mode: RenderMode): boolean {
	return mode === "verbose";
}

/** Human-readable one-liner for the rotate notification. */
export function describeMode(mode: RenderMode): string {
	switch (mode) {
		case "normal":
			return "normal — thinking hidden, tool output truncated";
		case "verbose":
			return "verbose — thinking shown, full tool output";
		case "minimal":
			return "minimal — spinner only, tool rows hidden";
	}
}

/** Compact footer status text (colored by the caller). */
export function statusText(mode: RenderMode): string {
	return `render: ${mode}`;
}

/** Working-loader message for a mode, or `undefined` to keep Pi's default. */
export function workingMessage(mode: RenderMode): string | undefined {
	return mode === "minimal" ? "working…" : undefined;
}

/** Collapsed-thinking label for a mode, or `undefined` to reset to default. */
export function hiddenThinkingLabel(mode: RenderMode): string | undefined {
	return showThinking(mode) ? undefined : "thinking hidden";
}

/**
 * Markdown transform for thinking blocks: blank them out unless the mode shows
 * thinking. Display-only — the real message stays in the session and context.
 */
export function transformThinking(markdown: string, messageType: string, mode: RenderMode): string {
	return messageType === "assistant-thinking" && !showThinking(mode) ? "" : markdown;
}

/** How a tool result should render in a given mode. */
export interface ResultPlan {
	/** Render nothing at all (minimal mode). */
	hide: boolean;
	/** Show a "still running" indicator instead of a result. */
	partial: boolean;
	/** Include the output body, not just the summary line. */
	showBody: boolean;
	/** Max body lines to show before truncating. */
	maxLines: number;
}

export function resultPlan(mode: RenderMode, opts: { expanded?: boolean; isPartial?: boolean }): ResultPlan {
	if (mode === "minimal") {
		return { hide: true, partial: false, showBody: false, maxLines: 0 };
	}
	if (opts.isPartial) {
		return { hide: false, partial: true, showBody: false, maxLines: 0 };
	}
	const showBody = mode === "verbose" || Boolean(opts.expanded);
	return { hide: false, partial: false, showBody, maxLines: mode === "verbose" ? 400 : 20 };
}
