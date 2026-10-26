import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { registerContext } from "./command.ts";
import { renderContext } from "./render.ts";

// Pi extension entry point. Registers `/context`: a Claude-Code-style breakdown
// of context-window usage (grid, legend, per-item lists), shown in the chat as
// a session entry that is never sent to the model. The logic lives in
// ./command.ts, ./breakdown.ts, and ./report.ts (unit-tested); this file only
// binds the TUI renderer.
export default function piContext(pi: ExtensionAPI): void {
  registerContext(pi, renderContext);
}
