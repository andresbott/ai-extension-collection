# pi-statusline

A compact, colored **custom footer / status bar** for the [Pi coding agent](https://pi.dev),
modeled on Claude Code's status line. Pi-only — omp ships its own native status bar
(configured in `~/.omp/agent/config.yml`), and Claude Code uses a `statusLine` command
instead.

It renders one line:

```
<model> │  <folder> │  <branch> │ ███▎░░░ <pct>% <used>/<window> │ $<cost>
```

- **model** — in blue (`theme.fg("mdLink", …)`)
- **folder** — folder icon + the cwd's basename (`$HOME` shows as `~`)
- **branch** — git-branch icon + branch name (omitted outside a repo)
- **context** — a progress bar (smooth to ⅛ of a cell) + `pct% used/window`, all
  colored by fullness: green ≤70%, yellow >70%, red >90%
- **cost** — running session total in USD

> **Nerd Font required for the icons.** The folder/branch glyphs are Nerd Font
> code points. Install a [Nerd Font](https://www.nerdfonts.com); if you see a box
> (tofu), swap the `ICON_FOLDER` / `ICON_BRANCH` constants at the top of
> [`pi/index.ts`](./pi/index.ts) for emoji (a commented alternative is right there).

## Install

It ships with the ai-extension-collection pi package:

```sh
pi install git:github.com/andresbott/ai-extension-collection
```

To load only this extension while iterating, from the repo root:

```sh
pi -e ./plugins/pi-statusline/pi/index.ts
```

After installing, reload a running Pi with `/reload` (or restart) to load it.

## Notes & caveats

- **It replaces the built-in footer.** A custom footer takes over the whole footer
  surface, so other extensions' `setStatus()` chips are not drawn while it's active.
- **Colors adapt to the theme.** Segment colors use semantic theme names (`mdLink`,
  `success`/`warning`/`error`, `accent`, `dim`), so they track whatever theme is active.
  When the terminal is too narrow for a color-safe fit, the line degrades to plain
  truncated text (colors are dropped rather than corrupted).

## Tweaking

Everything is in [`pi/index.ts`](./pi/index.ts). The **look & feel constants** at the top
(`SEP`, `ICON_FOLDER`, `ICON_BRANCH`, the `COLOR_*` names, `COST_DECIMALS`, `BAR_WIDTH`)
cover the common changes without touching `render()`. To add/reorder segments, edit the
`seg` array inside `render()`; the context bar is built by `makeBar()`.

Available data:

- `ctx.model?.id` — active model id
- `ctx.cwd` — working directory
- `footerData.getGitBranch()` — current branch (or `null`)
- `ctx.getContextUsage()` — `{ contextWindow, tokens, percent }`
- **cost** — summed from `ctx.sessionManager.getEntries()` over assistant/toolResult
  messages and compaction/branch summaries. Note the field is **`usage.cost.total`**
  (a breakdown object), not a plain `usage.cost` — this mirrors exactly how Pi's own
  built-in footer accumulates cost. Providers on a subscription (e.g. GitHub Copilot)
  report `0`, so the figure sits at `$0.00` for them.

For color, apply the `theme` argument to each segment via `theme.fg(<ThemeColor>, text)`.
