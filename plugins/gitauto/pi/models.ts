// Which model gitauto's cheap nested calls use. Pure; unit-tested in models.test.ts.
//
// Short prose (branch names, commit messages, small PR texts) goes to a cheap
// model instead of the session's model; complex PR texts (the pr-writer expert)
// stay on the session's model. Claude Code runs the commands on haiku; this picks
// the pi equivalent from whatever models the user can reach, so it works on any
// provider without configuration. The search itself lives in libs/pi-side-call.

import { type ModelRef, pickModel } from "../../../libs/pi-side-call/models.ts";

export type { ModelRef };

/**
 * Cheap model families, most preferred first, matched against model ids. Haiku
 * mirrors the Claude Code command; the rest cover providers without it.
 */
const CHEAP_MODEL_PATTERNS: readonly RegExp[] = [/haiku/i, /^gpt-[\d.]+-mini$/i, /flash/i];

/**
 * The cheap model to use, or undefined when none is available. Models from the
 * session's provider win (same subscription, auth known to work); then the
 * earliest matching family; then the newest version within it.
 */
export function pickCheapModel<M extends ModelRef>(available: readonly M[], sessionProvider?: string): M | undefined {
  return pickModel(available, CHEAP_MODEL_PATTERNS, sessionProvider);
}

/**
 * Resolves a `provider/id` or bare-id override against the available models;
 * undefined when it names no available model.
 */
export function findModel<M extends ModelRef>(available: readonly M[], spec: string): M | undefined {
  const slash = spec.indexOf("/");
  if (slash > 0) {
    const provider = spec.slice(0, slash);
    const id = spec.slice(slash + 1);
    return available.find((m) => m.provider === provider && m.id === id);
  }
  return available.find((m) => m.id === spec);
}
