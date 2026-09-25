import { test } from "node:test";
import assert from "node:assert/strict";

import { applyClear, createClearState, requestClear } from "./clear.ts";

test("inactive state passes every message through unchanged", () => {
  const state = createClearState();
  assert.deepEqual(applyClear(state, ["a", "b", "c"]), ["a", "b", "c"]);
  assert.equal(state.dropCount, null);
});

test("clear hides everything before the just-submitted turn", () => {
  const state = createClearState();
  requestClear(state);
  // first model call after /clear: three old messages + the new user turn
  assert.deepEqual(applyClear(state, ["a", "b", "c", "u"]), ["u"]);
  assert.equal(state.dropCount, 3);
  assert.equal(state.armed, false);
});

test("the same prefix stays hidden as the conversation grows", () => {
  const state = createClearState();
  requestClear(state);
  applyClear(state, ["a", "b", "c", "u"]); // captures dropCount = 3
  assert.deepEqual(
    applyClear(state, ["a", "b", "c", "u", "assistant", "u2"]),
    ["u", "assistant", "u2"],
  );
});

test("re-clearing re-captures the baseline at the new point", () => {
  const state = createClearState();
  requestClear(state);
  applyClear(state, ["a", "b", "u"]); // dropCount = 2
  requestClear(state);
  assert.deepEqual(applyClear(state, ["a", "b", "u", "assistant", "u2"]), ["u2"]);
  assert.equal(state.dropCount, 4);
});

test("clearing with a single pending message keeps that message", () => {
  const state = createClearState();
  requestClear(state);
  assert.deepEqual(applyClear(state, ["u"]), ["u"]);
  assert.equal(state.dropCount, 0);
});

test("clearing with no messages is a no-op", () => {
  const state = createClearState();
  requestClear(state);
  assert.deepEqual(applyClear(state, []), []);
  assert.equal(state.dropCount, 0);
});

test("applyClear never mutates its input array", () => {
  const state = createClearState();
  requestClear(state);
  const input = ["a", "b", "u"];
  applyClear(state, input);
  assert.deepEqual(input, ["a", "b", "u"]);
});
