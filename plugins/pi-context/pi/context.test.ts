import { test } from "node:test";
import assert from "node:assert/strict";

import { formatContext } from "./context.ts";

test("reports unavailable when usage is undefined", () => {
  assert.equal(formatContext(undefined), "Context usage unavailable");
});

test("appends the model name when provided", () => {
  assert.equal(
    formatContext(undefined, "kimi-k3"),
    "Context usage unavailable (kimi-k3)",
  );
});

test("reports 'not yet estimated' when tokens are null", () => {
  assert.equal(
    formatContext({ tokens: null, contextWindow: 200000 }),
    "Context: not yet estimated, window 200,000 tokens",
  );
});

test("shows used / window / percent / free for a normal reading", () => {
  assert.equal(
    formatContext({ tokens: 50000, contextWindow: 200000 }),
    "Context: 50,000 / 200,000 tokens (25%), 150,000 free",
  );
});

test("includes the model name in a normal reading", () => {
  assert.equal(
    formatContext({ tokens: 50000, contextWindow: 200000 }, "kimi-k3"),
    "Context: 50,000 / 200,000 tokens (25%), 150,000 free (kimi-k3)",
  );
});

test("omits percent and never goes negative on a zero window", () => {
  assert.equal(
    formatContext({ tokens: 100, contextWindow: 0 }),
    "Context: 100 / 0 tokens, 0 free",
  );
});
