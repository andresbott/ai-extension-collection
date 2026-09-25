/**
 * render-mode — built-in tool rendering overrides.
 *
 * Re-registers the seven built-in tools (read, bash, edit, write, find, grep,
 * ls) with the SAME name so our renderers replace Pi's, while execution is
 * delegated back to the originals (the `built-in-tool-renderer.ts` pattern).
 *
 * Each tool uses `renderShell: "self"` so it owns its outer frame. That is what
 * lets minimal mode render *nothing*: an empty `Container` has zero height, so
 * with the default boxed shell gone there is no padded, empty row per tool —
 * the whole tool row disappears, leaving only Pi's working spinner.
 *
 * Known third-party tools cannot be re-registered safely because Pi exposes
 * their metadata but not their executors. For those tools, this module applies
 * a narrow compatibility patch to Pi's exported ToolExecutionComponent and
 * suppresses only explicitly allowlisted names while minimal mode is active.
 *
 * This module imports pi-tui and the SDK as VALUES, so it is exercised live
 * rather than in unit tests (those packages do not resolve from this repo).
 * All mode-dependent decisions come from the pure helpers in `./modes.ts`.
 */

import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import {
	ToolExecutionComponent,
	createBashTool,
	createEditTool,
	createFindTool,
	createGrepTool,
	createLsTool,
	createReadTool,
	createWriteTool,
} from "@earendil-works/pi-coding-agent";
import { Container, Text } from "@earendil-works/pi-tui";
import { homedir } from "node:os";

import { hideKnownCustomToolRow, resultPlan, type RenderMode } from "./modes.ts";

const TOOL_ROW_PATCH = Symbol.for("pi-render-mode:known-custom-tool-rows");
const ACTIVE_MODE = Symbol.for("pi-render-mode:active-mode");

type RenderGlobals = typeof globalThis & { [ACTIVE_MODE]?: RenderMode };

type ToolExecutionInstance = {
	toolName?: unknown;
};

/** Keep the prototype patch's mode current across extension reloads. */
export function setToolRenderMode(mode: RenderMode): void {
	(globalThis as RenderGlobals)[ACTIVE_MODE] = mode;
}

/**
 * Hide rows for known third-party tools without replacing their executors.
 * This uses Pi's exported ToolExecutionComponent because ExtensionAPI exposes
 * tool metadata, but not the executable definitions needed for safe wrappers.
 */
function patchKnownCustomToolRows(): void {
	const prototype = ToolExecutionComponent.prototype as typeof ToolExecutionComponent.prototype & {
		[TOOL_ROW_PATCH]?: boolean;
	};
	if (prototype[TOOL_ROW_PATCH]) return;

	const originalRender = prototype.render;
	prototype.render = function patchedRender(this: ToolExecutionInstance, width: number): string[] {
		const mode = (globalThis as RenderGlobals)[ACTIVE_MODE] ?? "normal";
		if (hideKnownCustomToolRow(mode, this.toolName)) return [];
		return originalRender.call(this, width);
	};
	prototype[TOOL_ROW_PATCH] = true;
}

function shortenPath(value: unknown): string {
	const path = typeof value === "string" ? value : "";
	const home = homedir();
	return path && path.startsWith(home) ? `~${path.slice(home.length)}` : path;
}

function firstText(result: { content?: Array<{ type: string; text?: string }> }): string {
	const part = result?.content?.find((candidate) => candidate.type === "text");
	return part && part.type === "text" && typeof part.text === "string" ? part.text : "";
}

/** An empty component — a zero-height row (used for minimal mode). */
const emptyRow = (): Container => new Container();

function createAll(cwd: string) {
	return {
		read: createReadTool(cwd),
		bash: createBashTool(cwd),
		edit: createEditTool(cwd),
		write: createWriteTool(cwd),
		find: createFindTool(cwd),
		grep: createGrepTool(cwd),
		ls: createLsTool(cwd),
	};
}

type BuiltInName = keyof ReturnType<typeof createAll>;

interface ToolSpec {
	name: BuiltInName;
	/** Compact, colored one-line rendering of the tool call. */
	call: (args: Record<string, unknown>, theme: Theme) => string;
}

const SPECS: ToolSpec[] = [
	{
		name: "read",
		call: (args, theme) => {
			let text = theme.fg("toolTitle", theme.bold("read ")) + theme.fg("accent", shortenPath(args.path ?? ""));
			if (args.offset || args.limit) {
				const parts: string[] = [];
				if (args.offset) parts.push(`offset=${args.offset}`);
				if (args.limit) parts.push(`limit=${args.limit}`);
				text += theme.fg("dim", ` (${parts.join(", ")})`);
			}
			return text;
		},
	},
	{
		name: "bash",
		call: (args, theme) => {
			const command = String(args.command ?? "");
			const shown = command.length > 80 ? `${command.slice(0, 77)}…` : command;
			let text = theme.fg("toolTitle", theme.bold("$ ")) + theme.fg("accent", shown);
			if (args.timeout) text += theme.fg("dim", ` (timeout ${args.timeout}s)`);
			return text;
		},
	},
	{
		name: "edit",
		call: (args, theme) => theme.fg("toolTitle", theme.bold("edit ")) + theme.fg("accent", shortenPath(args.path ?? "")),
	},
	{
		name: "write",
		call: (args, theme) => {
			const lines = args.content ? String(args.content).split("\n").length : 0;
			let text = theme.fg("toolTitle", theme.bold("write ")) + theme.fg("accent", shortenPath(args.path ?? ""));
			if (lines) text += theme.fg("dim", ` (${lines} lines)`);
			return text;
		},
	},
	{
		name: "find",
		call: (args, theme) =>
			theme.fg("toolTitle", theme.bold("find ")) +
			theme.fg("accent", String(args.pattern ?? "")) +
			theme.fg("dim", ` in ${shortenPath(args.path ?? ".")}`),
	},
	{
		name: "grep",
		call: (args, theme) =>
			theme.fg("toolTitle", theme.bold("grep ")) +
			theme.fg("accent", `/${args.pattern ?? ""}/`) +
			theme.fg("dim", ` in ${shortenPath(args.path ?? ".")}`),
	},
	{
		name: "ls",
		call: (args, theme) => theme.fg("toolTitle", theme.bold("ls ")) + theme.fg("accent", shortenPath(args.path ?? ".")),
	},
];

/**
 * Register the built-in tool overrides. `getMode` is read at render time, so
 * the display updates on the next render whenever the mode changes.
 */
export function registerToolOverrides(pi: ExtensionAPI, getMode: () => RenderMode): void {
	patchKnownCustomToolRows();

	// Built-in tool instances are cached per cwd; execution is delegated to them.
	const byCwd = new Map<string, ReturnType<typeof createAll>>();
	const builtIns = (cwd: string) => {
		let tools = byCwd.get(cwd);
		if (!tools) {
			tools = createAll(cwd);
			byCwd.set(cwd, tools);
		}
		return tools;
	};

	// A seed instance provides each tool's parameters/description at registration.
	const seed = builtIns(process.cwd());

	for (const spec of SPECS) {
		const base = seed[spec.name];
		pi.registerTool({
			name: spec.name,
			label: spec.name,
			description: base.description,
			parameters: base.parameters,
			renderShell: "self",

			async execute(toolCallId, params, signal, onUpdate, ctx) {
				return builtIns(ctx.cwd)[spec.name].execute(toolCallId, params, signal, onUpdate);
			},

			renderCall(args, theme, _context) {
				if (getMode() === "minimal") return emptyRow();
				return new Text(spec.call(args as Record<string, unknown>, theme), 0, 0);
			},

			renderResult(result, { expanded, isPartial }, theme, _context) {
				const plan = resultPlan(getMode(), { expanded, isPartial });
				if (plan.hide) return emptyRow();
				if (plan.partial) return new Text(theme.fg("warning", "…"), 0, 0);

				const body = firstText(result).replace(/\s+$/g, "");
				const lines = body ? body.split("\n") : [];
				const summary = theme.fg("muted", `→ ${lines.length} line${lines.length === 1 ? "" : "s"}`);
				if (!plan.showBody || lines.length === 0) {
					return new Text(summary, 0, 0);
				}

				const shown = lines
					.slice(0, plan.maxLines)
					.map((line) => theme.fg("toolOutput", line))
					.join("\n");
				let text = `${summary}\n${shown}`;
				if (lines.length > plan.maxLines) {
					text += `\n${theme.fg("muted", `… ${lines.length - plan.maxLines} more`)}`;
				}
				return new Text(text, 0, 0);
			},
		});
	}
}
