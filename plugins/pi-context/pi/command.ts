import { homedir } from "node:os";

import type { EntryRenderer, ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";

import {
  computeBreakdown,
  type ContextBreakdown,
  estimateMessageTokens,
  replaySystemState,
  splitPromptSections,
  type SystemState,
  type ToolMeta,
} from "./breakdown.ts";
import { PLAIN, renderReport } from "./report.ts";

export const CONTEXT_ENTRY = "context-usage";

/** pi's default compaction reserve (settings `compaction.reserveTokens`). */
const DEFAULT_RESERVE_TOKENS = 16384;

interface CompactionSettingsLike {
  enabled?: boolean;
  reserveTokens?: number;
  modelOverrides?: Record<string, { reserveTokens?: number } | undefined>;
}

/**
 * Registers `/context` and the renderer for the entries it stores. The renderer
 * is injected because it needs the TUI runtime (see ./render.ts), which unit
 * tests cannot load.
 *
 * In the TUI the breakdown is a custom session entry: drawn in the chat, kept
 * in the session file, and never part of the model's context. Other modes get
 * the plain-text panel as a notification.
 */
export function registerContext(pi: ExtensionAPI, renderContext: EntryRenderer<ContextBreakdown>): void {
  pi.registerEntryRenderer<ContextBreakdown>(CONTEXT_ENTRY, renderContext);

  pi.registerCommand("context", {
    description: "Show context usage by category: system prompt, tools, memory files, skills, messages",
    handler: async (_args, ctx) => {
      const breakdown = collectBreakdown(pi, ctx);
      if (!breakdown) {
        ctx.ui.notify("Context usage is unavailable: no model is selected", "warning");
        return;
      }
      if (ctx.mode === "tui") pi.appendEntry<ContextBreakdown>(CONTEXT_ENTRY, breakdown);
      else ctx.ui.notify(["Context Usage", "", ...renderReport(breakdown, PLAIN)].join("\n"), "info");
    },
  });
}

/** Reads what the model sees from pi and builds the breakdown; undefined without a context window. */
export function collectBreakdown(pi: ExtensionAPI, ctx: ExtensionCommandContext): ContextBreakdown | undefined {
  const usage = ctx.getContextUsage();
  const contextWindow = usage?.contextWindow ?? ctx.model?.contextWindow ?? 0;
  if (!(contextWindow > 0)) return undefined;

  let messages: readonly unknown[] = [];
  try {
    messages = ctx.sessionManager.buildSessionProjection().messages;
  } catch {
    // An unreadable projection only costs the message estimate and the transcript state.
  }

  const allTools = pi.getAllTools();
  const toolMeta: ToolMeta[] = allTools.map((tool) => ({
    name: tool.name,
    sourcePath: tool.sourceInfo?.path,
    namespace: tool.namespace?.name,
  }));

  // The transcript holds the exact sections and tools of the last request, including
  // sections extensions add per run. Before the first request, fall back to the base prompt.
  const active = new Set(pi.getActiveTools());
  const system: SystemState = replaySystemState(messages) ?? {
    ...splitPromptSections(ctx.getSystemPrompt()),
    tools: allTools.flatMap((tool) =>
      active.has(tool.name) ? [{ name: tool.name, description: tool.description, parameters: tool.parameters }] : [],
    ),
  };

  const compaction = (pi.getSettings() as { compaction?: CompactionSettingsLike }).compaction;
  const modelKey = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined;
  const override = modelKey ? compaction?.modelOverrides?.[modelKey]?.reserveTokens : undefined;

  return computeBreakdown({
    model: ctx.model?.name ?? ctx.model?.id ?? "no model",
    contextWindow,
    usageTokens: usage?.tokens ?? null,
    system,
    toolMeta,
    messageTokens: messages.reduce<number>((total, message) => total + estimateMessageTokens(message), 0),
    compaction: {
      enabled: compaction?.enabled ?? true,
      reserveTokens: override ?? compaction?.reserveTokens ?? DEFAULT_RESERVE_TOKENS,
    },
    cwd: ctx.cwd,
    home: homedir(),
  });
}
