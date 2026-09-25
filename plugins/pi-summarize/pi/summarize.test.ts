import assert from "node:assert/strict";
import { test } from "node:test";

import { buildSummaryPrompt } from "./summarize.ts";

test("buildSummaryPrompt embeds the transcript in conversation tags", () => {
  const prompt = buildSummaryPrompt("User: hi\n\nAssistant: hello");
  assert.match(prompt, /<conversation>\nUser: hi\n\nAssistant: hello\n<\/conversation>/);
});
