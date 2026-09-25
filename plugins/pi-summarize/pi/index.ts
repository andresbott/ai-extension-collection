import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { registerSummarize } from "./command.ts";
import { renderSummary } from "./render.ts";

// Pi extension entry point. Registers `/summarize`: a mid-tier model (Sonnet)
// summarizes the conversation, and the summary is shown in the chat as a
// session entry that is kept in the session file but never sent to the model.
// The logic lives in ./command.ts, ./summarize.ts, and libs/pi-side-call
// (unit-tested); this file only binds the TUI renderer.
export default function piSummarize(pi: ExtensionAPI): void {
  registerSummarize(pi, renderSummary);
}
