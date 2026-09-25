# pi-startup-splash

A polished startup splash for Pi.

## What it does

- presents a responsive startup-only panel above the editor
- renders a large `PI` wordmark and the active model, working directory, and version
- shows compact cards for:
  - Context
  - Skills
  - Prompts
  - Extensions
- uses effective runtime data where available:
  - context and skills from system-prompt options
  - prompts from `pi.getCommands()`
  - extensions from Pi settings, command/tool provenance, and extension directories
- switches to a single-column layout on narrow terminals

Colors use Pi's semantic theme colors, so the splash follows the active theme.

## Hide Pi's default startup listing

Set Pi's supported `quietStartup` preference:

```json
{
  "quietStartup": true
}
```

Set it in the active Pi settings file, normally `~/.pi/agent/settings.json`.

`quietStartup` suppresses Pi's built-in header and loaded-resource listing. The extension renders independently as a custom widget, so the splash remains visible. Resource diagnostics still appear when Pi has something important to report.

The splash removes itself when the first prompt begins, keeping the working interface uncluttered. It returns for a new session or reload.

## Install

It ships with the ai-extension-collection pi package:

```sh
pi install git:github.com/andresbott/ai-extension-collection
```

Then restart Pi. A running session can reload the extension with `/reload`, but changing `quietStartup` is best verified with a restart.

To load only this extension while iterating, from the repo root:

```sh
pi -e ./plugins/pi-startup-splash/pi/index.ts
```

## Tests

From the repo root:

```sh
npm run test:pi
```
