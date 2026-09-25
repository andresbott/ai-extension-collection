import { randomUUID } from "node:crypto";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { buildNamingPrompt, buildTranscript, cleanGeneratedName, parseManualTitle } from "./rename.ts";

// Pi extension entry point. Registers `/rename`, Claude Code's /rename for Pi:
//   /rename "Some title"  -> names the session with that title, verbatim;
//   /rename               -> asks the current model for a short title and uses it.
// Naming only ever happens when the user runs the command; nothing is automatic.
// Pi's built-in /name only sets a typed name, so this adds the generated case.
// The pure logic lives in ./rename.ts (unit-tested); this file is the wiring.
export default function piRename(pi: ExtensionAPI): void {
  pi.registerCommand("rename", {
    description: 'Name the session: /rename "title" uses it verbatim, bare /rename generates one',
    handler: async (args, ctx) => {
      const manual = parseManualTitle(args);
      if (manual) {
        pi.setSessionName(manual);
        ctx.ui.notify(`Session named: ${manual}`, "info");
        return;
      }

      const transcript = buildTranscript(ctx.sessionManager.getBranch());
      if (!transcript) {
        ctx.ui.notify('Nothing to name yet; use /rename "title" to set one by hand', "warning");
        return;
      }

      const model = ctx.model;
      if (!model || !ctx.modelRegistry.hasConfiguredAuth(model)) {
        ctx.ui.notify('No usable model to generate a name; use /rename "title" instead', "warning");
        return;
      }

      ctx.ui.notify("Generating a session name…", "info");

      let reply;
      try {
        // One-off side call: no prompt-cache writes and a fresh routing ID, so it
        // neither touches the main conversation nor warms a cache nobody reuses.
        reply = await ctx.modelRegistry
          .streamSimple(
            model,
            {
              messages: [
                {
                  role: "user",
                  content: [{ type: "text", text: buildNamingPrompt(transcript) }],
                  timestamp: Date.now(),
                },
              ],
            },
            { cacheRetention: "none", sessionId: randomUUID(), signal: ctx.signal },
          )
          .result();
      } catch (error) {
        ctx.ui.notify(`Could not generate a session name: ${String(error)}`, "error");
        return;
      }

      if (reply.stopReason === "error" || reply.stopReason === "aborted") {
        ctx.ui.notify(
          `Could not generate a session name: ${reply.errorMessage || reply.stopReason}`,
          "error",
        );
        return;
      }

      const text = reply.content
        .filter((part): part is { type: "text"; text: string } => part.type === "text")
        .map((part) => part.text)
        .join("\n");
      const name = cleanGeneratedName(text);
      if (!name) {
        ctx.ui.notify('The model returned no usable name; use /rename "title" instead', "warning");
        return;
      }

      pi.setSessionName(name);
      ctx.ui.notify(`Session named: ${name}`, "info");
    },
  });
}
