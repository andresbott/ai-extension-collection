import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { formatContext } from "./context.ts";

// Pi extension entry point. Registers `/context`, mirroring omp's built-in
// /context: a read-only readout of context-window usage. Pi exposes the numbers
// directly via ctx.getContextUsage(), so this is a thin display wrapper — the
// formatting lives in ./context.ts (pure + unit-tested).
export default function piContext(pi: ExtensionAPI): void {
  pi.registerCommand("context", {
    description: "Show estimated context-window usage (used / free / %)",
    handler: async (_args, ctx) => {
      ctx.ui.notify(formatContext(ctx.getContextUsage(), ctx.model?.name), "info");
    },
  });
}
