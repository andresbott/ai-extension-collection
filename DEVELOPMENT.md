# Development

## Add a plugin

1. Create `plugins/<plugin-name>/`.
2. Add `plugins/<plugin-name>/.claude-plugin/plugin.json` with the plugin's name,
   description, and semantic version.
3. Put its components in conventional directories such as `agents/`,
   `commands/`, `hooks/`, or `skills/`.
4. Register it in `.claude-plugin/marketplace.json`:

   ```json
   {
     "name": "my-plugin",
     "source": "./plugins/my-plugin",
     "description": "What the plugin provides"
   }
   ```

5. Increase the marketplace version and the changed plugin's version in the
   same commit.

## Add a pi adapter

A plugin can also work in pi. Keep both harnesses on one core:

- Shared behaviour (scripts, prompts, sounds, context files) stays in the
  plugin's own directories and never mentions a harness.
- Claude Code files keep their conventional places (`.claude-plugin/`,
  `commands/`, `agents/`, `hooks/`, `skills/`).
- The pi adapter goes in `plugins/<plugin-name>/pi/index.ts`. It stays thin and
  only binds the shared core to pi. Name its commands like Claude's
  (`<plugin>:<command>`).
- List the adapter in the root `package.json` under `pi.extensions`.
- Put its tests next to it as `pi/*.test.ts`. Node runs them directly
  (`npm run test:pi`).

Load an adapter directly while iterating:

```sh
pi -e ./plugins/<plugin-name>/pi/index.ts
```

or the whole package with `pi -e .`. Use `/reload` after editing.

## Develop locally

Load a plugin directly while iterating:

```sh
claude --plugin-dir ./plugins/<plugin-name>
```

Use `/reload-plugins` after editing plugin files. To test the marketplace install
path instead, run:

```text
/plugin marketplace add .
/plugin install <plugin-name>@ai-extension-collection
```

A marketplace install uses Claude Code's plugin cache. Refresh the marketplace
and reload plugins after changing an installed plugin:

```text
/plugin marketplace update ai-extension-collection
/reload-plugins
```

## Version policy

Every commit must increase the version in `.claude-plugin/marketplace.json`.
Commits that change a plugin must also increase that plugin's own manifest
version. Commits that change a pi adapter (`plugins/*/pi/`) or the root
`package.json` must also increase the root `package.json` version. Pull requests
enforce this policy through `.github/workflows/version-bump.yml`.
