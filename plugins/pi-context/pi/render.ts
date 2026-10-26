// TUI rendering of a stored /context entry. Kept apart from ./command.ts because
// it needs the pi-tui runtime, which is only available inside Pi.

import type { EntryRenderer } from "@earendil-works/pi-coding-agent";
import { Box, Spacer, Text } from "@earendil-works/pi-tui";

import type { ContextBreakdown } from "./breakdown.ts";
import { renderReport } from "./report.ts";

/** Draws a breakdown as a card: title, the grid with its legend, then the per-item lists. */
export const renderContext: EntryRenderer<ContextBreakdown> = (entry, _options, theme) => {
  const data = entry.data;
  if (!data || !Array.isArray(data.categories) || !Array.isArray(data.details)) return undefined;

  const box = new Box(1, 1, (text) => theme.bg("customMessageBg", text));
  box.addChild(new Text(theme.fg("accent", theme.bold("Context Usage")), 0, 0));
  box.addChild(new Spacer(1));
  box.addChild(new Text(renderReport(data, theme).join("\n"), 0, 0));
  return box;
};
