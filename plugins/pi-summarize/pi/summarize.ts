// Pure helpers behind the /summarize command. No dependencies; unit-tested.
//
// /summarize -> buildTranscript() (libs/pi-side-call) + buildSummaryPrompt() feed
//               one side call; the reply is stored as a SUMMARY_ENTRY session
//               entry, shown in the chat but never sent to the model.

/** Custom entry type of a stored summary; its renderer is registered under it. */
export const SUMMARY_ENTRY = "session-summary";

/** Transcript budget, in characters (about 25k tokens), sent to the summary model. */
export const TRANSCRIPT_CHARS = 100_000;

/** Model families for summaries, most preferred first; the session model is the fallback. */
export const SUMMARY_MODELS: readonly RegExp[] = [/sonnet/i];

/** Data stored in a summary entry. */
export interface SummaryData {
  summary: string;
  /** `provider/id` of the model that wrote it. */
  model: string;
  timestamp: number;
}

/** The single-turn prompt asking the model for a session summary. */
export function buildSummaryPrompt(transcript: string): string {
  return [
    "Summarize the coding session below so it can be picked up again later.",
    "Use Markdown with these headings, skipping any that would be empty:",
    "Goal, Key decisions, Progress, Open questions, Next steps.",
    "Be concise: short bullets, concrete names (files, commands, errors), no filler.",
    "Reply with the summary only.",
    "",
    "<conversation>",
    transcript,
    "</conversation>",
  ].join("\n");
}
