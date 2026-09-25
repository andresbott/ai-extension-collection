// One-off nested model call that stays out of the main conversation.
// Unit-tested in side-call.test.ts.

/** The slice of a model reply this module reads. Pi's AssistantMessage satisfies it. */
export interface SideCallReply {
  stopReason: string;
  errorMessage?: string;
  content: readonly { type: string; text?: string }[];
}

/** The slice of Pi's ModelRegistry this module uses. */
export interface SideCallRegistry<M> {
  streamSimple(
    model: M,
    context: { messages: { role: "user"; content: { type: "text"; text: string }[]; timestamp: number }[] },
    options: { cacheRetention: "none"; sessionId: string; signal?: AbortSignal },
  ): { result(): Promise<SideCallReply> };
}

/**
 * Sends prompt as a single user message to model and returns the reply's text.
 * The call writes no prompt cache and uses a fresh routing ID, so it neither
 * touches the main conversation nor warms a cache nobody reuses. Throws when the
 * request fails or the reply ends in error or abort.
 */
export async function sideCall<M>(
  registry: SideCallRegistry<M>,
  model: M,
  prompt: string,
  signal?: AbortSignal,
): Promise<string> {
  const reply = await registry
    .streamSimple(
      model,
      { messages: [{ role: "user", content: [{ type: "text", text: prompt }], timestamp: Date.now() }] },
      { cacheRetention: "none", sessionId: crypto.randomUUID(), signal },
    )
    .result();

  if (reply.stopReason === "error" || reply.stopReason === "aborted") {
    throw new Error(reply.errorMessage || reply.stopReason);
  }
  return reply.content.flatMap((part) => (part.type === "text" && part.text !== undefined ? [part.text] : [])).join("\n");
}
