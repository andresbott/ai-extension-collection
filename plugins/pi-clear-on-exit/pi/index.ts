import { scheduleTerminalClear } from "./terminal.ts";

interface ShutdownEvent {
  reason: "quit" | "reload" | "new" | "resume" | "fork";
}

interface ShutdownContext {
  mode: "tui" | "rpc" | "json" | "print";
}

interface PiExtensionAPI {
  on(
    event: "session_shutdown",
    handler: (event: ShutdownEvent, ctx: ShutdownContext) => void,
  ): () => void;
}

interface NodeRuntime {
  process: {
    once(event: "exit", handler: () => void): void;
    stdout: {
      isTTY?: boolean;
      write(output: string): void;
    };
  };
}

export function shouldClearTerminal(
  event: ShutdownEvent,
  ctx: ShutdownContext,
  isTTY: boolean | undefined,
): boolean {
  return event.reason === "quit" && ctx.mode === "tui" && isTTY === true;
}

/** Clear the visible terminal and scrollback after an interactive Pi process exits. */
export default function clearOnExit(pi: PiExtensionAPI): void {
  pi.on("session_shutdown", (event, ctx) => {
    // SAFETY: Pi extensions execute inside Node.js, where globalThis.process
    // provides the exit-event and stdout APIs represented by NodeRuntime.
    const { process } = globalThis as unknown as NodeRuntime;
    if (!shouldClearTerminal(event, ctx, process.stdout.isTTY)) return;

    scheduleTerminalClear(
      (handler) => process.once("exit", handler),
      (output) => process.stdout.write(output),
    );
  });
}
