// TUI rendering of a stored summary entry. Kept apart from ./command.ts because
// it needs the pi-tui runtime, which is only available inside Pi.

import { type EntryRenderer, getMarkdownTheme } from "@earendil-works/pi-coding-agent";
import { Box, Markdown, Spacer, Text } from "@earendil-works/pi-tui";

import type { SummaryData } from "./summarize.ts";

/** Draws a summary entry as a card: a label with the model, then the Markdown summary. */
export const renderSummary: EntryRenderer<SummaryData> = (entry, _options, theme) => {
  const data = entry.data;
  if (!data?.summary) return undefined;

  const box = new Box(1, 1, (text) => theme.bg("customMessageBg", text));
  const label = theme.fg("customMessageLabel", theme.bold("Session summary"));
  box.addChild(new Text(`${label} ${theme.fg("dim", data.model)}`, 0, 0));
  box.addChild(new Spacer(1));
  box.addChild(new Markdown(data.summary, 0, 0, getMarkdownTheme()));
  return box;
};
