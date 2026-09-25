import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { applyClear, createClearState, requestClear } from "./clear.ts";

// Pi extension entry point. Registers `/clear`, which mirrors omp's built-in
// /clear: it hides the prior conversation from the model while leaving the
// session/transcript on disk untouched.
//
// Pi has no in-place context-reset primitive on the public extension API, so we
// implement it with the two sanctioned hooks:
//   - registerCommand("clear") arms a clear,
//   - on("context") trims the model-bound message list before every model call.
// All the trimming logic lives in ./clear.ts (pure + unit-tested).
export default function piClear(pi: ExtensionAPI): void {
  const state = createClearState();

  pi.registerCommand("clear", {
    description: "Clear the conversation context in place, keeping the session",
    handler: async (_args, ctx) => {
      requestClear(state);
      ctx.ui.notify(
        "Context cleared — prior messages hidden from the model; session kept.",
        "info",
      );
    },
  });

  pi.on("context", (event) => {
    const trimmed = applyClear(state, event.messages);
    if (trimmed.length !== event.messages.length) {
      return { messages: trimmed };
    }
    return undefined;
  });
}
