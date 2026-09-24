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
version. Pull requests enforce this policy through
`.github/workflows/version-bump.yml`.
