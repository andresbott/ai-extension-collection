// Pure helpers behind the /rename command. No dependencies; fully unit-tested.
//
// /rename "Some title"  -> parseManualTitle() returns the title verbatim
// /rename               -> buildTranscript() (libs/pi-side-call) + buildNamingPrompt()
//                          feed one side call, and cleanGeneratedName() tidies its reply.

/** Transcript budget, in characters, sent to the naming model. */
export const TRANSCRIPT_CHARS = 6000;

/** Model families for naming, most preferred first; the session model is the fallback. */
export const NAMING_MODELS: readonly RegExp[] = [/sonnet/i];

/** Upper bound on a generated session name. */
export const MAX_NAME_CHARS = 80;

const QUOTE_PAIRS: Record<string, string> = {
  '"': '"',
  "'": "'",
  "`": "`",
  "“": "”",
  "‘": "’",
};

/** Strips one matching pair of quotes wrapping the whole string, if present. */
function stripWrappingQuotes(text: string): string {
  if (text.length < 2) return text;
  const close = QUOTE_PAIRS[text[0]];
  return close !== undefined && text.endsWith(close) ? text.slice(1, -close.length) : text;
}

/**
 * Returns the title typed after /rename, or undefined when none was given (which
 * means "generate one"). The title is used verbatim; only surrounding whitespace
 * and one pair of quotes wrapping the whole argument are removed, so
 * `/rename "Fix auth bug"` and `/rename Fix auth bug` both name it `Fix auth bug`.
 */
export function parseManualTitle(args: string | undefined): string | undefined {
  const trimmed = (args ?? "").trim();
  if (!trimmed) return undefined;
  const title = stripWrappingQuotes(trimmed).trim();
  return title || undefined;
}

/** The single-turn prompt asking the model for a session name. */
export function buildNamingPrompt(transcript: string): string {
  return [
    "Write a short title for the coding session below, so it is easy to find later in a session list.",
    "Use 3 to 6 words that name the main task or topic. Use no quotes and no trailing period.",
    "Reply with the title only.",
    "",
    "<conversation>",
    transcript,
    "</conversation>",
  ].join("\n");
}

/**
 * Turns the model's reply into a session name: first non-empty line, without a
 * "Title:" label, wrapping quotes, markdown emphasis, or a trailing period, with
 * whitespace collapsed and the length capped. Returns "" when nothing is left.
 */
export function cleanGeneratedName(reply: string, maxChars: number = MAX_NAME_CHARS): string {
  const line = reply
    .split("\n")
    .map((l) => l.trim())
    .find((l) => l.length > 0);
  if (!line) return "";

  let name = line.replace(/^#+\s*/, "").replace(/^(session\s+)?(title|name)\s*:\s*/i, "");
  name = name.replace(/^\*\*(.*)\*\*$/, "$1").replace(/^_(.*)_$/, "$1");
  name = stripWrappingQuotes(name.trim()).trim();
  name = name.replace(/\.+$/, "").replace(/\s+/g, " ").trim();

  if (name.length > maxChars) name = name.slice(0, maxChars).trimEnd();
  return name;
}
