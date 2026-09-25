// Pure formatter behind the /context command — mirrors omp's /context
// ("show estimated context usage"). Turns Pi's ContextUsage into a one-line
// summary. No dependencies; fully unit-tested.

export interface ContextUsageLike {
  /** Estimated context tokens in use, or null when not yet known. */
  tokens: number | null;
  /** The active model's context window, in tokens. */
  contextWindow: number;
}

const group = (n: number): string =>
  Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");

export function formatContext(
  usage: ContextUsageLike | undefined,
  modelName?: string,
): string {
  const suffix = modelName ? ` (${modelName})` : "";
  if (!usage) return `Context usage unavailable${suffix}`;

  const window = usage.contextWindow;
  if (usage.tokens == null) {
    return `Context: not yet estimated, window ${group(window)} tokens${suffix}`;
  }

  const used = usage.tokens;
  const free = Math.max(0, window - used);
  const percent = window > 0 ? ` (${Math.round((used / window) * 100)}%)` : "";
  return `Context: ${group(used)} / ${group(window)} tokens${percent}, ${group(free)} free${suffix}`;
}
