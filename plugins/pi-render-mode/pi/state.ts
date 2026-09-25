/**
 * render-mode — global persistence of the selected mode.
 *
 * The chosen mode is stored in `<agentDir>/render-mode.json` where `agentDir`
 * is `$PI_CODING_AGENT_DIR` (Pi's overridable home) or `~/.pi/agent`. It is
 * read on session start and written on each rotation, so the mode survives
 * restarts and is shared across sessions. Only node builtins are used here so
 * this module is testable without the Pi SDK installed.
 */

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";

import { isRenderMode, type RenderMode } from "./modes.ts";

/** Absolute path of the state file, honoring `$PI_CODING_AGENT_DIR`. */
export function stateFilePath(): string {
	const dir = process.env.PI_CODING_AGENT_DIR?.trim() || join(homedir(), ".pi", "agent");
	return join(dir, "render-mode.json");
}

/** Load the persisted mode, or `undefined` if missing/unreadable/invalid. */
export async function loadMode(path: string = stateFilePath()): Promise<RenderMode | undefined> {
	try {
		const parsed = JSON.parse(await readFile(path, "utf8")) as { mode?: unknown };
		return isRenderMode(parsed?.mode) ? parsed.mode : undefined;
	} catch {
		return undefined;
	}
}

/** Persist the mode, creating the parent directory if needed. */
export async function saveMode(mode: RenderMode, path: string = stateFilePath()): Promise<void> {
	await mkdir(dirname(path), { recursive: true });
	await writeFile(path, `${JSON.stringify({ mode }, null, 2)}\n`, "utf8");
}
