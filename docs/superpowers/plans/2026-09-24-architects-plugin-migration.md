# Architects Plugin Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the reconciled five-agent `architects` plugin in this Claude Code marketplace without modifying either origin repository.

**Architecture:** The destination is a Claude Code plugin, so its manifest and agent frontmatter follow the existing private marketplace implementation. The agent instruction bodies are common to both origins and will be copied unchanged; Pi-only frontmatter differences will not be introduced into the Claude plugin.

**Tech Stack:** Claude Code plugin manifests, Markdown agent definitions with YAML frontmatter, JSON marketplace manifest.

**Spec:** `docs/superpowers/specs/2026-09-24-architects-plugin-migration.md`

## Global Constraints

- Both origin repositories are strictly read-only.
- Preserve all shared agent instruction bodies exactly.
- Use Claude-compatible frontmatter from `odo-ai-marketplace`.
- Publish plugin version `0.3.0`.
- Do not change any existing plugin.
- Do not commit unless Andrés explicitly requests it.

## Review Focus

- Origin drift: verify each migrated instruction body still matches both source implementations.
- Harness metadata: ensure Pi-specific lowercase tool declarations do not replace Claude-compatible declarations.
- Completeness: require exactly Pike, Natalia, Tony, Evans, and Margaret.
- Registration: ensure the marketplace entry points to `./plugins/architects` exactly once.
- Versioning: retain plugin `0.3.0` and the current marketplace patch bump without adding an unnecessary second bump to the same uncommitted change set.

---

### Task 1: Add the architects plugin

**Files:**
- Create: `plugins/architects/.claude-plugin/plugin.json`
- Create: `plugins/architects/agents/pike-go.md`
- Create: `plugins/architects/agents/natalia-frontend.md`
- Create: `plugins/architects/agents/tony-openapi.md`
- Create: `plugins/architects/agents/evans-layering.md`
- Create: `plugins/architects/agents/margaret-setup.md`

**Interfaces:**
- Consumes: the two read-only architect implementations named in the specification.
- Produces: a self-contained Claude Code plugin auto-discovered through its `agents/` directory.

- [ ] **Step 1: Create the plugin manifest**

Write `plugins/architects/.claude-plugin/plugin.json` with the source identity and version:

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "architects",
  "description": "A small team of subagents with distinct personalities: Pike (Go architecture), Natalia (TypeScript / Vue 3 / TanStack Query / PrimeVue architecture), Tony (OpenAPI / REST API design & spec), Evans (layering & dependency-direction review), and Margaret (setup & tech-stack checklist validation). The architects review and design (and implement when asked); Evans and Margaret are read-only — Evans audits layer boundaries and dependency direction, Margaret audits a project against a setup checklist.",
  "version": "0.3.0",
  "author": {
    "name": "Andres Bott",
    "email": "contact@andresbott.com"
  }
}
```

- [ ] **Step 2: Create the five Claude agent definitions**

Copy the five files from the read-only Claude marketplace source into
`plugins/architects/agents/` using their existing filenames. This preserves the
shared bodies and the Claude-specific metadata (`model: opus` for Pike, Natalia,
Tony, and Evans; `model: sonnet` plus `tools: Read, Grep, Glob, Bash` for
Margaret).

- [ ] **Step 3: Verify the migrated bodies against both origins**

For each filename, compare content after the closing frontmatter delimiter. The
command must produce no output:

```bash
for file in pike-go.md natalia-frontend.md tony-openapi.md evans-layering.md margaret-setup.md; do
  diff -u \
    <(awk 'BEGIN { n=0 } /^---$/ { n++; next } n >= 2' "/home/bott/.datos/edit/programacion-privado/odo-ai-marketplace/plugins/architects/agents/$file") \
    <(awk 'BEGIN { n=0 } /^---$/ { n++; next } n >= 2' "plugins/architects/agents/$file")
  diff -u \
    <(awk 'BEGIN { n=0 } /^---$/ { n++; next } n >= 2' "/home/bott/.datos/edit/programacion/andresbott/pi-code-config/agents/$file") \
    <(awk 'BEGIN { n=0 } /^---$/ { n++; next } n >= 2' "plugins/architects/agents/$file")
done
```

Expected: exit status `0` and no diff output.

- [ ] **Step 4: Validate plugin completeness and manifest JSON**

Run:

```bash
jq -e '.name == "architects" and .version == "0.3.0"' plugins/architects/.claude-plugin/plugin.json
find plugins/architects/agents -maxdepth 1 -type f -name '*.md' -printf '%f\n' | sort
```

Expected: `jq` prints `true`; the file list contains exactly
`evans-layering.md`, `margaret-setup.md`, `natalia-frontend.md`, `pike-go.md`, and
`tony-openapi.md`.

### Task 2: Publish the plugin in the collection

**Files:**
- Modify: `.claude-plugin/marketplace.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: the plugin created by Task 1 at `./plugins/architects`.
- Produces: marketplace discovery and user-facing documentation for the plugin.

- [ ] **Step 1: Register the plugin**

Add this object to the marketplace `plugins` array:

```json
{
  "name": "architects",
  "source": "./plugins/architects",
  "description": "Specialist architecture agents for Go, Vue and TypeScript, OpenAPI, dependency layering, and project setup validation."
}
```

Keep the marketplace version at the already-bumped `0.1.2`, because all current
working-tree changes are intended for one change set based on `0.1.1`.

- [ ] **Step 2: Document the available plugin**

Add this bullet under `README.md` → `Available plugins`:

```markdown
- **`architects`** — provides specialist agents for Go, Vue and TypeScript,
  OpenAPI, dependency layering, and project setup validation.
```

- [ ] **Step 3: Validate registration**

Run:

```bash
jq -e '
  .version == "0.1.2" and
  ([.plugins[] | select(.name == "architects")] | length) == 1 and
  any(.plugins[]; .name == "architects" and .source == "./plugins/architects")
' .claude-plugin/marketplace.json
```

Expected: `true`.

### Task 3: Verify the complete migration

**Files:**
- Verify only; no additional files.

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: evidence that the plugin is complete, registered, source-faithful, and repository-clean apart from expected working-tree changes.

- [ ] **Step 1: Confirm both origins remain unchanged**

Run `git status --short` in each origin repository and record the pre-existing
state. Confirm migration introduced no new changes; do not clean, reset, stage,
or otherwise modify either repository.

- [ ] **Step 2: Run repository checks**

Run:

```bash
git diff --check
jq empty .claude-plugin/marketplace.json
jq empty plugins/architects/.claude-plugin/plugin.json
```

Expected: all commands exit `0` with no errors.

- [ ] **Step 3: Inspect the final target diff**

Run:

```bash
git status --short
git diff -- README.md .claude-plugin/marketplace.json
git diff --no-index /dev/null plugins/architects/.claude-plugin/plugin.json || test $? -eq 1
```

Expected: only intended target-repository changes are present; `.pi/` remains
untracked and untouched; no origin path appears as modified.
