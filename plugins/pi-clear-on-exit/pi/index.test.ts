import assert from "node:assert/strict";
import { test } from "node:test";

import clearOnExit, { shouldClearTerminal } from "./index.ts";

function makeFakePi() {
  const handlers = new Map<string, (...args: any[]) => unknown>();
  const pi = {
    registerCommand: () => undefined,
    on: (event: string, handler: (...args: any[]) => unknown) => {
      handlers.set(event, handler);
      return () => undefined;
    },
  };
  return { pi, handlers };
}

test("registers a session shutdown handler", () => {
  const { pi, handlers } = makeFakePi();

  clearOnExit(pi);

  assert.equal(typeof handlers.get("session_shutdown"), "function");
});

test("clears only for interactive TTY quits", () => {
  assert.equal(
    shouldClearTerminal({ reason: "quit" }, { mode: "tui" }, true),
    true,
  );
  assert.equal(
    shouldClearTerminal({ reason: "reload" }, { mode: "tui" }, true),
    false,
  );
  assert.equal(
    shouldClearTerminal({ reason: "quit" }, { mode: "print" }, true),
    false,
  );
  assert.equal(
    shouldClearTerminal({ reason: "quit" }, { mode: "tui" }, false),
    false,
  );
});
