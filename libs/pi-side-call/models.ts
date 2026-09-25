// Picks a model for a nested side call by family. Pure; unit-tested in models.test.ts.
//
// The caller supplies the families (the policy), for example [/sonnet/i] for a
// mid-tier call or [/haiku/i, /flash/i] for a cheap one; this module only
// supplies the search (the mechanism), so it works on any provider without
// configuration.

/** The slice of a model this module reads. Pi's Model satisfies it. */
export interface ModelRef {
  provider: string;
  id: string;
}

const newestFirst = (a: ModelRef, b: ModelRef) => b.id.localeCompare(a.id, undefined, { numeric: true });

/**
 * The model to use, or undefined when no family matches. Models from the
 * session's provider win (same subscription, auth known to work); then the
 * earliest matching family; then the newest version within it.
 */
export function pickModel<M extends ModelRef>(
  available: readonly M[],
  families: readonly RegExp[],
  sessionProvider?: string,
): M | undefined {
  const providers = sessionProvider ? [sessionProvider, undefined] : [undefined];
  for (const provider of providers) {
    const pool = provider ? available.filter((m) => m.provider === provider) : available;
    for (const family of families) {
      const match = pool.filter((m) => family.test(m.id)).sort(newestFirst)[0];
      if (match) return match;
    }
  }
  return undefined;
}
