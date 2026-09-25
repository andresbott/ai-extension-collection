// coding-guides for pi: the same standing guides and hard rules as the Claude
// Code hooks, from the same files. before_agent_start adds
// context/coding-guides.md to the system prompt every turn (Claude: the
// SessionStart hook); tool_call runs each bash command through the shared
// PreToolUse script and blocks what it blocks (Claude: the PreToolUse hook).
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
export const GUIDES = join(ROOT, "context", "coding-guides.md");
export const PRE_TOOL_USE = join(ROOT, "hooks", "coding-guides-pre-tool-use.sh");
/** Rendered by pi as <coding-guides>…</coding-guides>; unchanged text is not re-sent. */
export const SECTION = "coding-guides";

export type Block = { block: true; reason: string };

/**
 * Run the shared PreToolUse script on a shell command, fed the payload Claude
 * Code sends. Exit 2 blocks with the script's stderr as the reason (without jq
 * the script blocks git commit calls with an install hint); anything else,
 * including a missing bash, allows.
 */
export function checkCommand(command: string): Block | undefined {
  const input = JSON.stringify({ tool_name: "Bash", tool_input: { command } });
  const run = spawnSync("bash", [PRE_TOOL_USE], { input, encoding: "utf8" });
  if (run.status !== 2) return undefined;
  return { block: true, reason: run.stderr.trim() };
}

export default function codingGuides(pi: ExtensionAPI) {
  pi.on("before_agent_start", (event) => {
    // Read each turn so edits apply without /reload; the file is small.
    event.systemPromptOptions.sections[SECTION] = readFileSync(GUIDES, "utf8");
  });

  pi.on("tool_call", (event) => {
    if (event.toolName !== "bash") return undefined;
    const command = (event.input as { command?: unknown }).command;
    return typeof command === "string" ? checkCommand(command) : undefined;
  });
}
