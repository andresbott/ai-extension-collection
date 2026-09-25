// Keeps the pi agent twins (pi/agents/) in step with the Claude Code agents
// (agents/): same files, same names, same section structure, and frontmatter
// that pi-subagents can actually run.
import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const PI_DIR = dirname(fileURLToPath(import.meta.url));
const PLUGIN_DIR = dirname(PI_DIR);
const REPO_ROOT = dirname(dirname(PLUGIN_DIR));
const CLAUDE_AGENTS = join(PLUGIN_DIR, "agents");
const PI_AGENTS = join(PI_DIR, "agents");

// pi's builtin tool names; Claude's (Read, Glob, ...) are unknown to pi and
// fail pi-subagents' strict tool allowlist before the first turn.
const PI_TOOLS = new Set(["read", "grep", "find", "ls", "bash", "edit", "write"]);
// Claude Code model aliases that do not resolve in pi's model registry.
const CLAUDE_MODEL_ALIASES = new Set(["opus", "sonnet", "haiku"]);
// pi-subagents caps advertised descriptions at 512 UTF-8 bytes.
const MAX_ADVERTISED_DESCRIPTION_BYTES = 512;

type Agent = { frontmatter: Record<string, string>; body: string };

function agentFiles(dir: string): string[] {
  return readdirSync(dir).filter((name) => name.endsWith(".md")).sort();
}

/** Parse the flat `key: value` frontmatter these agent files use. */
function parseAgent(path: string): Agent {
  const text = readFileSync(path, "utf8");
  const match = /^---\n([\s\S]*?)\n---\n([\s\S]*)$/.exec(text);
  if (!match) throw new Error(`${path}: missing frontmatter`);
  const frontmatter: Record<string, string> = {};
  for (const line of match[1].split("\n")) {
    const colon = line.indexOf(":");
    assert.ok(colon > 0, `${path}: unparsable frontmatter line '${line}'`);
    frontmatter[line.slice(0, colon).trim()] = line.slice(colon + 1).trim();
  }
  return { frontmatter, body: match[2] };
}

/** Markdown headings outside fenced code blocks. */
function headings(body: string): string[] {
  let fenced = false;
  const found: string[] = [];
  for (const line of body.split("\n")) {
    if (line.startsWith("```")) fenced = !fenced;
    else if (!fenced && /^#{1,6} /.test(line)) found.push(line);
  }
  return found;
}

const files = agentFiles(CLAUDE_AGENTS);

test("every Claude agent has a pi twin and vice versa", () => {
  assert.ok(files.length > 0, "no Claude agents found");
  assert.deepEqual(agentFiles(PI_AGENTS), files);
});

for (const file of files) {
  const claude = parseAgent(join(CLAUDE_AGENTS, file));
  const pi = parseAgent(join(PI_AGENTS, file));

  test(`${file}: twins share name and section structure`, () => {
    assert.equal(pi.frontmatter.name, claude.frontmatter.name);
    assert.deepEqual(headings(pi.body), headings(claude.body));
  });

  test(`${file}: pi frontmatter runs under pi-subagents`, () => {
    const model = pi.frontmatter.model;
    assert.ok(model === undefined || !CLAUDE_MODEL_ALIASES.has(model), `Claude model alias '${model}'`);
    if (pi.frontmatter.tools !== undefined) {
      for (const tool of pi.frontmatter.tools.split(",").map((entry) => entry.trim())) {
        assert.ok(PI_TOOLS.has(tool), `unknown pi tool '${tool}'`);
      }
    }
    assert.equal(pi.frontmatter.advertise, "true");
    const description = pi.frontmatter.description ?? "";
    assert.ok(description.length > 0, "missing description");
    assert.ok(
      new TextEncoder().encode(description).length <= MAX_ADVERTISED_DESCRIPTION_BYTES,
      `description exceeds ${MAX_ADVERTISED_DESCRIPTION_BYTES} bytes`,
    );
  });
}

test("the pi package exposes the pi agents to pi-subagents", () => {
  const pkg = JSON.parse(readFileSync(join(REPO_ROOT, "package.json"), "utf8"));
  const agentsDir = `./${PI_AGENTS.slice(REPO_ROOT.length + 1)}`;
  assert.ok(pkg.pi?.subagents?.agents?.includes(agentsDir), `package.json pi.subagents.agents lacks ${agentsDir}`);
});
