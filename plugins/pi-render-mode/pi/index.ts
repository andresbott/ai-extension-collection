/**
 * render-mode — rotate Pi's rendering between three modes with one keypress.
 *
 *   normal   (default) thinking hidden, tool output truncated
 *   verbose            thinking shown, full tool output
 *   minimal            just Pi's working spinner (no tool rows), then the output
 *
 * Rotate with ctrl+r (see ROTATE_KEY). The choice is persisted globally and
 * restored on session start. The footer shows the active mode.
 *
 * Pieces:
 *   - a markdown transformer blanks thinking blocks unless the mode shows them
 *     (display-only; the real message stays in context);
 *   - the built-in tools are re-registered with mode-aware renderers (tools.ts);
 *   - in minimal mode a "working…" loader message stands in for tool rows.
 *
 * All decisions live in ./modes.ts (pure, unit-tested); this file is wiring.
 */

import type { ExtensionAPI, ExtensionContext, MarkdownTransformContext } from "@earendil-works/pi-coding-agent";

import {
	describeMode,
	hiddenThinkingLabel,
	nextMode,
	type RenderMode,
	statusText,
	transformThinking,
	workingMessage,
} from "./modes.ts";
import { loadMode, saveMode } from "./state.ts";
import { registerToolOverrides, setToolRenderMode } from "./tools.ts";

/** Key that rotates the mode. Pi's built-in session-rename binding is disabled in keybindings.json. */
const ROTATE_KEY = "ctrl+r";

const STATUS_ID = "render-mode";

type UiContext = Pick<ExtensionContext, "ui">;

export default function renderMode(pi: ExtensionAPI): void {
	let mode: RenderMode = "normal";

	const apply = (ctx: UiContext): void => {
		setToolRenderMode(mode);
		ctx.ui.setStatus(STATUS_ID, ctx.ui.theme.fg("dim", statusText(mode)));
		ctx.ui.setWorkingMessage(workingMessage(mode));
		ctx.ui.setHiddenThinkingLabel(hiddenThinkingLabel(mode));
	};

	pi.on("session_start", async (_event: unknown, ctx: ExtensionContext) => {
		const saved = await loadMode();
		if (saved) mode = saved;
		apply(ctx);
	});

	pi.registerShortcut(ROTATE_KEY, {
		description: "Rotate render mode: normal → verbose → minimal",
		handler: async (ctx: ExtensionContext) => {
			mode = nextMode(mode);
			await saveMode(mode).catch(() => {});
			apply(ctx);
			ctx.ui.notify(`Render mode: ${describeMode(mode)}`, "info");
		},
	});

	pi.registerMarkdownTransformer((markdown: string, { messageType }: MarkdownTransformContext) =>
		transformThinking(markdown, messageType, mode),
	);

	registerToolOverrides(pi, () => mode);
}
