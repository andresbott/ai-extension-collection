export const CLEAR_TERMINAL_SEQUENCE = "\u001b[2J\u001b[3J\u001b[H";

type RegisterExitHandler = (handler: () => void) => void;
type WriteOutput = (output: string) => unknown;

/**
 * Schedule a terminal clear for the final process exit phase.
 *
 * Pi emits session_shutdown before printing its optional resume hint. Waiting
 * for Node's exit event ensures that hint and all other normal shutdown output
 * are cleared too.
 */
export function scheduleTerminalClear(
  registerExitHandler: RegisterExitHandler,
  writeOutput: WriteOutput,
): void {
  registerExitHandler(() => {
    writeOutput(CLEAR_TERMINAL_SEQUENCE);
  });
}
