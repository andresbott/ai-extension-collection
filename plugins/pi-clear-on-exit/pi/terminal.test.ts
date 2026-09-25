import assert from "node:assert/strict";
import { test } from "node:test";

import { CLEAR_TERMINAL_SEQUENCE, scheduleTerminalClear } from "./terminal.ts";

test("writes the ANSI clear sequence only when the registered exit handler runs", () => {
  let exitHandler: (() => void) | undefined;
  const writes: string[] = [];

  scheduleTerminalClear(
    (handler) => {
      exitHandler = handler;
    },
    (output) => writes.push(output),
  );

  assert.deepEqual(writes, []);
  const handler = exitHandler;
  assert.ok(handler);

  handler();

  assert.deepEqual(writes, [CLEAR_TERMINAL_SEQUENCE]);
  assert.equal(CLEAR_TERMINAL_SEQUENCE, "\u001b[2J\u001b[3J\u001b[H");
});
