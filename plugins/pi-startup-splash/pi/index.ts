// @ts-ignore -- Pi provides its SDK module when loading the installed extension.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

import { defaultSplashData, discoverStartupData } from "./discovery.ts";
import { renderSplash, type PlainTheme } from "./splash.ts";

const WIDGET_ID = "startup-splash";

export default function startupSplash(pi: ExtensionAPI): void {
  let refreshRender: (() => void) | undefined;
  let refreshToken = 0;
  let currentData = defaultSplashData(".", "model pending");

  async function refresh(ctx: ExtensionContext): Promise<void> {
    const token = ++refreshToken;
    const modelLabel = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "model pending";
    const data = await discoverStartupData({
      cwd: ctx.cwd,
      projectTrusted: ctx.isProjectTrusted(),
      modelLabel,
      commands: pi.getCommands() as any,
      tools: typeof pi.getAllTools === "function" ? (pi.getAllTools() as any) : [],
    }).catch(() => defaultSplashData(ctx.cwd, modelLabel));

    if (token !== refreshToken) return;
    currentData = data;
    refreshRender?.();
  }

  pi.on("session_start", async (_event: unknown, ctx: ExtensionContext) => {
    if (ctx.mode !== "tui") return;

    ctx.ui.setWidget(
      WIDGET_ID,
      (tui: { requestRender(): void }, theme: PlainTheme) => {
        refreshRender = () => tui.requestRender();
        return {
          render(width: number): string[] {
            return renderSplash(currentData, width, theme);
          },
          invalidate() {},
          dispose() {
            refreshRender = undefined;
          },
        };
      },
      { placement: "aboveEditor" },
    );

    await refresh(ctx);
  });

  pi.on("before_agent_start", (_event: unknown, ctx: ExtensionContext) => {
    refreshToken += 1;
    refreshRender = undefined;
    ctx.ui.setWidget(WIDGET_ID, undefined);
  });

  pi.on("session_shutdown", (_event: unknown, ctx: ExtensionContext) => {
    refreshToken += 1;
    refreshRender = undefined;
    ctx.ui.setWidget(WIDGET_ID, undefined);
  });
}
