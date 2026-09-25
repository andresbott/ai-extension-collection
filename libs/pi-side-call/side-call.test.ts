import assert from "node:assert/strict";
import { test } from "node:test";

import { sideCall } from "./side-call.ts";

// A stand-in for Pi's ModelRegistry.streamSimple: records each call and answers
// with the given reply (or rejects with the given error).
function makeRegistry(reply: unknown, fail?: Error) {
  const calls: { model: unknown; context: any; options: any }[] = [];
  const registry = {
    streamSimple: (model: unknown, context: unknown, options: unknown) => {
      calls.push({ model, context, options });
      return { result: async () => (fail ? Promise.reject(fail) : reply) };
    },
  };
  return { registry, calls };
}

const ok = (...parts: unknown[]) => ({ stopReason: "stop", content: parts });

test("sends the prompt as one user message to the given model and returns its text", async () => {
  const { registry, calls } = makeRegistry(
    ok({ type: "thinking", thinking: "hmm" }, { type: "text", text: "line 1" }, { type: "text", text: "line 2" }),
  );
  const model = { provider: "anthropic", id: "claude-sonnet-5" };

  const text = await sideCall(registry, model, "Summarize this.");

  assert.equal(text, "line 1\nline 2");
  assert.equal(calls.length, 1);
  assert.equal(calls[0].model, model);
  const messages = calls[0].context.messages;
  assert.equal(messages.length, 1);
  assert.equal(messages[0].role, "user");
  assert.deepEqual(messages[0].content, [{ type: "text", text: "Summarize this." }]);
});

test("stays off the main conversation: no cache writes, a fresh session id per call, the caller's signal", async () => {
  const { registry, calls } = makeRegistry(ok({ type: "text", text: "x" }));
  const signal = new AbortController().signal;

  await sideCall(registry, {}, "a", signal);
  await sideCall(registry, {}, "b");

  assert.equal(calls[0].options.cacheRetention, "none");
  assert.equal(calls[0].options.signal, signal);
  assert.equal(typeof calls[0].options.sessionId, "string");
  assert.ok(calls[0].options.sessionId.length > 0);
  assert.notEqual(calls[0].options.sessionId, calls[1].options.sessionId);
});

test("throws the provider's error message when the call ends in error", async () => {
  const { registry } = makeRegistry({ stopReason: "error", errorMessage: "rate limited", content: [] });
  await assert.rejects(sideCall(registry, {}, "p"), { message: "rate limited" });
});

test("throws the stop reason when an error or abort carries no message", async () => {
  for (const stopReason of ["error", "aborted"]) {
    const { registry } = makeRegistry({ stopReason, content: [] });
    await assert.rejects(sideCall(registry, {}, "p"), { message: stopReason });
  }
});

test("passes a failed request through", async () => {
  const { registry } = makeRegistry(undefined, new Error("network down"));
  await assert.rejects(sideCall(registry, {}, "p"), { message: "network down" });
});
