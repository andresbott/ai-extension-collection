import type { EntryRenderer, ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { pickModel } from "../../../libs/pi-side-call/models.ts";
import { sideCall } from "../../../libs/pi-side-call/side-call.ts";
import { buildTranscript } from "../../../libs/pi-side-call/transcript.ts";
import { buildSummaryPrompt, SUMMARY_ENTRY, SUMMARY_MODELS, type SummaryData, TRANSCRIPT_CHARS } from "./summarize.ts";

/**
 * Registers `/summarize` and the renderer for the entries it stores. The
 * renderer is injected because it needs the TUI runtime (see ./render.ts),
 * which unit tests cannot load.
 *
 * Summarizing only happens when the user runs the command. The summary is a
 * custom session entry: shown in the chat and kept in the session file, but
 * never part of the model's context.
 */
export function registerSummarize(pi: ExtensionAPI, renderSummary: EntryRenderer<SummaryData>): void {
  pi.registerEntryRenderer<SummaryData>(SUMMARY_ENTRY, renderSummary);

  pi.registerCommand("summarize", {
    description: "Summarize the conversation into the chat (kept in the session, not sent to the model)",
    handler: async (_args, ctx) => {
      const transcript = buildTranscript(ctx.sessionManager.getBranch(), TRANSCRIPT_CHARS);
      if (!transcript) {
        ctx.ui.notify("Nothing to summarize yet", "warning");
        return;
      }

      const model = pickModel(ctx.modelRegistry.getAvailable(), SUMMARY_MODELS, ctx.model?.provider) ?? ctx.model;
      if (!model || !ctx.modelRegistry.hasConfiguredAuth(model)) {
        ctx.ui.notify("No usable model to summarize the session", "warning");
        return;
      }

      ctx.ui.notify(`Summarizing the session with ${model.id}…`, "info");

      let text;
      try {
        text = await sideCall(ctx.modelRegistry, model, buildSummaryPrompt(transcript), ctx.signal);
      } catch (error) {
        ctx.ui.notify(`Could not summarize the session: ${error instanceof Error ? error.message : error}`, "error");
        return;
      }

      const summary = text.trim();
      if (!summary) {
        ctx.ui.notify("The model returned an empty summary", "warning");
        return;
      }

      pi.appendEntry<SummaryData>(SUMMARY_ENTRY, {
        summary,
        model: `${model.provider}/${model.id}`,
        timestamp: Date.now(),
      });
      // Entry renderers only run in the TUI; other UIs get the text directly.
      if (ctx.mode !== "tui") ctx.ui.notify(summary, "info");
    },
  });
}
