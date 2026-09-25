import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import { pickModel } from "../../../libs/pi-side-call/models.ts";
import { sideCall } from "../../../libs/pi-side-call/side-call.ts";
import { buildTranscript } from "../../../libs/pi-side-call/transcript.ts";
import { buildNamingPrompt, cleanGeneratedName, NAMING_MODELS, parseManualTitle, TRANSCRIPT_CHARS } from "./rename.ts";

// Pi extension entry point. Registers `/rename`, Claude Code's /rename for Pi:
//   /rename "Some title"  -> names the session with that title, verbatim;
//   /rename               -> asks a mid-tier model (Sonnet) for a short title.
// Naming only ever happens when the user runs the command; nothing is automatic.
// Pi's built-in /name only sets a typed name, so this adds the generated case.
// The pure logic lives in ./rename.ts and libs/pi-side-call (unit-tested); this
// file is the wiring.
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

      const transcript = buildTranscript(ctx.sessionManager.getBranch(), TRANSCRIPT_CHARS);
      if (!transcript) {
        ctx.ui.notify('Nothing to name yet; use /rename "title" to set one by hand', "warning");
        return;
      }

      const model = pickModel(ctx.modelRegistry.getAvailable(), NAMING_MODELS, ctx.model?.provider) ?? ctx.model;
      if (!model || !ctx.modelRegistry.hasConfiguredAuth(model)) {
        ctx.ui.notify('No usable model to generate a name; use /rename "title" instead', "warning");
        return;
      }

      ctx.ui.notify(`Generating a session name with ${model.id}…`, "info");

      let text;
      try {
        text = await sideCall(ctx.modelRegistry, model, buildNamingPrompt(transcript), ctx.signal);
      } catch (error) {
        ctx.ui.notify(`Could not generate a session name: ${error instanceof Error ? error.message : error}`, "error");
        return;
      }

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
