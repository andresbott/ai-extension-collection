# pi-clear-on-exit

A Pi extension that clears the visible terminal and its scrollback when an
interactive Pi process exits. The parent shell returns at the top of a clean
terminal, so there is no need to run `clear` manually.

## How it works

Pi stops its TUI and emits `session_shutdown` during a graceful exit, but may
print a session-resume hint afterward. The extension listens for a shutdown
whose reason is `quit`, then schedules the clear for Node's final `exit` event
so all normal Pi shutdown output is removed.

The clear uses standard ANSI sequences to:

1. clear the visible screen;
2. clear terminal scrollback;
3. move the cursor to the top-left corner.

It runs only when Pi is in interactive TUI mode and stdout is a TTY. It does not
run for `/reload`, `/new`, `/resume`, `/fork`, print/JSON/RPC mode, or redirected
output.

## Install

It ships with the ai-extension-collection pi package:

```sh
pi install git:github.com/andresbott/ai-extension-collection
```

To load only this extension while iterating, from the repo root:

```sh
pi -e ./plugins/pi-clear-on-exit/pi/index.ts
```

Restart Pi after installation.

## Test

From the repo root:

```sh
npm run test:pi
```

## Compatibility

The extension targets ANSI-compatible terminals, including common Linux and
macOS terminal emulators. Clearing scrollback is terminal-dependent; terminals
that do not implement ANSI `CSI 3 J` will still clear the visible screen.
