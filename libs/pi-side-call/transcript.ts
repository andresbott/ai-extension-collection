// Flattens a Pi session branch into a plain-text transcript for a side call.
// Pure; unit-tested in transcript.test.ts.

/** The slice of a Pi session entry that the transcript builder reads. */
export interface EntryLike {
  type: string;
  message?: { role?: string; content?: unknown };
}

function textOf(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter(
      (part): part is { type: "text"; text: string } =>
        !!part && typeof part === "object" && part.type === "text" && typeof part.text === "string",
    )
    .map((part) => part.text)
    .join("\n");
}

/**
 * Flattens the user and assistant text of a session branch into a plain
 * transcript. Tool calls, tool results, and other entries are skipped. When the
 * transcript exceeds maxChars it keeps the start (where the goal usually is) and
 * the end (where the conversation is now), dropping the middle.
 */
export function buildTranscript(entries: readonly EntryLike[], maxChars: number): string {
  const sections: string[] = [];
  for (const entry of entries) {
    const role = entry.type === "message" ? entry.message?.role : undefined;
    if (role !== "user" && role !== "assistant") continue;
    const text = textOf(entry.message?.content).trim();
    if (text) sections.push(`${role === "user" ? "User" : "Assistant"}: ${text}`);
  }

  const transcript = sections.join("\n\n");
  if (transcript.length <= maxChars) return transcript;

  const marker = "\n\n[…]\n\n";
  const half = Math.max(0, Math.floor((maxChars - marker.length) / 2));
  return transcript.slice(0, half) + marker + transcript.slice(transcript.length - half);
}
