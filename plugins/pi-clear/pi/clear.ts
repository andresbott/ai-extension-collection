// Pure, dependency-free logic behind the /clear command.
//
// omp's /clear "clears the conversation context in place, keeping the session".
// We reproduce that in Pi without an internal reset primitive: on the next
// model call after /clear we record how many leading messages existed, then
// hide that prefix from every subsequent model call. The session/transcript on
// disk is never touched — only what Pi sends to the model is trimmed.

export interface ClearState {
  /** How many leading messages to hide from the model; null while inactive. */
  dropCount: number | null;
  /** Set by /clear; the next applyClear captures the baseline, then clears it. */
  armed: boolean;
}

export function createClearState(): ClearState {
  return { dropCount: null, armed: false };
}

/** Arm a clear. It takes effect on the next model call (the next applyClear). */
export function requestClear(state: ClearState): void {
  state.armed = true;
}

/**
 * Return the messages the model should actually see, given the clear state.
 * The input is never mutated.
 *
 * When armed, the baseline is everything except the just-submitted turn
 * (`length - 1`), so the message the user typed after /clear survives while the
 * prior conversation is hidden. That baseline then stays fixed as the
 * conversation grows.
 */
export function applyClear<T>(state: ClearState, messages: readonly T[]): T[] {
  if (state.armed) {
    state.dropCount = Math.max(0, messages.length - 1);
    state.armed = false;
  }
  return messages.slice(state.dropCount ?? 0);
}
