import assert from "node:assert/strict";
import { test } from "node:test";

import {
  classifyTool,
  computeBreakdown,
  displayPath,
  estimateMessageTokens,
  parseMemoryFiles,
  parseSkills,
  replaySystemState,
  splitPromptSections,
  type BreakdownInput,
  type SystemState,
} from "./breakdown.ts";

const tag = (name: string, body: string) => `<${name}>\n${body}\n</${name}>`;

const memory = tag(
  "project_context",
  [
    "Project-specific instructions and guidelines:",
    '<project_instructions path="/repo/AGENTS.md">\nAlways bump versions.\n</project_instructions>',
    '<project_instructions path="/home/me/.pi/agent/AGENTS.md">\nBe terse.\n</project_instructions>',
  ].join("\n\n"),
);

const skills = tag(
  "skills",
  [
    "<available_skills>",
    "  <skill>\n    <name>brainstorming</name>\n    <description>Talk it through first, at length and with care.</description>\n    <location>/s/b/SKILL.md</location>\n  </skill>",
    "  <skill>\n    <name>a&amp;b</name>\n    <description>x</description>\n    <location>/s/ab/SKILL.md</location>\n  </skill>",
    "</available_skills>",
  ].join("\n"),
);

function state(overrides: Partial<SystemState> = {}): SystemState {
  return {
    content: "",
    sections: {
      preamble: "You are pi.",
      tools: tag("tools", "- read: Read files"),
      project_context: memory,
      skills,
      cwd: tag("cwd", "/repo"),
      "coding-guides": tag("coding-guides", "x".repeat(4000)),
    },
    tools: [
      { name: "read", description: "Read a file", parameters: { type: "object" } },
      { name: "mcp__context7", description: "Context7 proxy", parameters: {} },
      { name: "agent_browser", description: "Browse".repeat(100), parameters: {} },
    ],
    ...overrides,
  };
}

function input(overrides: Partial<BreakdownInput> = {}): BreakdownInput {
  return {
    model: "Claude Opus",
    contextWindow: 200_000,
    usageTokens: 50_000,
    system: state(),
    toolMeta: [
      { name: "read", sourcePath: "builtin:read" },
      { name: "mcp__context7", sourcePath: "/x/node_modules/pi-mcp-adapter/index.ts" },
      { name: "agent_browser", sourcePath: "/x/node_modules/pi-agent-browser/index.ts" },
    ],
    messageTokens: 0,
    compaction: { enabled: true, reserveTokens: 16384 },
    cwd: "/repo",
    home: "/home/me",
    ...overrides,
  };
}

const category = (b: ReturnType<typeof computeBreakdown>, id: string) => b.categories.find((c) => c.id === id)!.tokens;

test("replaySystemState folds section patches and tool changes in order", () => {
  const replayed = replaySystemState([
    { role: "system", content: "", sections: { preamble: "P", a: "<a>\n1\n</a>", b: "<b>\n2\n</b>" }, toolsAdded: [{ name: "read" }, { name: "x" }] },
    { role: "user", content: "hi" },
    { role: "system", content: "", sections: { a: "<a>\n9\n</a>", b: null }, toolsRemoved: [{ name: "x" }], toolsAdded: [{ name: "y" }] },
  ]);
  assert.deepEqual(replayed, {
    content: "",
    sections: { preamble: "P", a: "<a>\n9\n</a>" },
    tools: [{ name: "read" }, { name: "y" }],
  });
});

test("replaySystemState is undefined without a system message", () => {
  assert.equal(replaySystemState([{ role: "user", content: "hi" }]), undefined);
});

test("splitPromptSections recovers the preamble and every section", () => {
  const sections = { tools: tag("tools", "- read"), project_context: memory, skills, cwd: tag("cwd", "/repo") };
  const text = ["You are pi.", ...Object.values(sections)].join("\n\n");
  assert.deepEqual(splitPromptSections(text), { content: "You are pi.", sections });
});

test("splitPromptSections keeps an untagged prompt as content", () => {
  assert.deepEqual(splitPromptSections("Just a custom prompt."), { content: "Just a custom prompt.", sections: {} });
});

test("parseMemoryFiles and parseSkills list each item", () => {
  assert.deepEqual(
    parseMemoryFiles(memory).map((f) => f.path),
    ["/repo/AGENTS.md", "/home/me/.pi/agent/AGENTS.md"],
  );
  assert.deepEqual(
    parseSkills(skills).map((s) => s.name),
    ["brainstorming", "a&b"],
  );
  assert.ok(parseSkills(skills).every((s) => s.tokens > 0));
});

test("classifyTool tells built-in, extension, and MCP tools apart", () => {
  assert.equal(classifyTool("read", { name: "read", sourcePath: "builtin:read" }), "system");
  assert.equal(classifyTool("read"), "system");
  assert.equal(classifyTool("mcp__docs__search", { name: "mcp__docs__search", sourcePath: "builtin:mcp" }), "mcp");
  assert.equal(classifyTool("mcp"), "mcp");
  assert.equal(classifyTool("search", { name: "search", sourcePath: "/n/pi-mcp-adapter/index.ts" }), "mcp");
  assert.equal(classifyTool("lookup", { name: "lookup", namespace: "mcp__docs" }), "mcp");
  assert.equal(classifyTool("ffgrep", { name: "ffgrep", sourcePath: "/n/pi-fff/index.ts" }), "extension");
  assert.equal(classifyTool("unknown_tool"), "extension");
});

test("estimateMessageTokens mirrors pi's chars/4 heuristic", () => {
  assert.equal(estimateMessageTokens({ role: "user", content: "12345678" }), 2);
  assert.equal(estimateMessageTokens({ role: "user", content: [{ type: "image" }] }), 1200);
  assert.equal(
    estimateMessageTokens({ role: "assistant", content: [{ type: "text", text: "abcd" }, { type: "toolCall", name: "ab", arguments: {} }] }),
    2,
  );
  assert.equal(estimateMessageTokens({ role: "system", content: "x".repeat(400) }), 0);
});

test("displayPath prefers cwd-relative, then ~", () => {
  assert.equal(displayPath("/repo/AGENTS.md", "/repo", "/home/me"), "AGENTS.md");
  assert.equal(displayPath("/home/me/.pi/AGENTS.md", "/repo", "/home/me"), "~/.pi/AGENTS.md");
  assert.equal(displayPath("/etc/AGENTS.md", "/repo", "/home/me"), "/etc/AGENTS.md");
});

test("computeBreakdown sorts sections and tools into Claude Code's categories", () => {
  const b = computeBreakdown(input());
  assert.ok(category(b, "systemPrompt") > 0);
  assert.ok(category(b, "systemTools") > 0);
  assert.ok(category(b, "mcpTools") > 0);
  assert.ok(category(b, "extensionTools") > category(b, "mcpTools"));
  assert.equal(category(b, "extensionPrompts"), Math.ceil(tag("coding-guides", "x".repeat(4000)).length / 4));
  assert.equal(category(b, "memoryFiles"), Math.ceil(memory.length / 4));
  assert.equal(category(b, "skills"), Math.ceil(skills.length / 4));
  assert.deepEqual(
    b.categories.map((c) => c.id),
    ["systemPrompt", "systemTools", "extensionTools", "mcpTools", "extensionPrompts", "memoryFiles", "skills", "messages"],
  );
});

test("computeBreakdown anchors the total on pi's usage and gives messages the rest", () => {
  const b = computeBreakdown(input({ usageTokens: 50_000 }));
  const nonMessage = b.categories.filter((c) => c.id !== "messages").reduce((s, c) => s + c.tokens, 0);
  assert.equal(b.usedTokens, 50_000);
  assert.equal(category(b, "messages"), 50_000 - nonMessage);
  assert.equal(b.estimated, false);
  assert.equal(b.autoCompactBufferTokens, 16384);
  assert.equal(b.freeTokens, 200_000 - 50_000 - 16384);
});

test("computeBreakdown estimates messages when pi has no usage number", () => {
  const b = computeBreakdown(input({ usageTokens: null, messageTokens: 1234 }));
  const nonMessage = b.categories.filter((c) => c.id !== "messages").reduce((s, c) => s + c.tokens, 0);
  assert.equal(category(b, "messages"), 1234);
  assert.equal(b.usedTokens, nonMessage + 1234);
  assert.equal(b.estimated, true);
});

test("computeBreakdown never reports negative messages or free space", () => {
  const b = computeBreakdown(input({ usageTokens: 10, contextWindow: 1000 }));
  assert.equal(category(b, "messages"), 0);
  assert.equal(b.freeTokens, 0);
  assert.equal(b.autoCompactBufferTokens, 0);
});

test("computeBreakdown drops the buffer when compaction is off", () => {
  const b = computeBreakdown(input({ compaction: { enabled: false, reserveTokens: 16384 } }));
  assert.equal(b.autoCompactBufferTokens, 0);
  assert.equal(b.freeTokens, 150_000);
});

test("computeBreakdown lists items per group, largest first (memory files in prompt order), empty groups omitted", () => {
  const b = computeBreakdown(input());
  assert.deepEqual(
    b.details.map((g) => g.title),
    ["MCP tools", "Extension tools", "Extension prompts", "Memory files", "Skills"],
  );
  const group = (title: string) => b.details.find((g) => g.title === title)!.items;
  assert.deepEqual(group("MCP tools").map((i) => i.name), ["mcp__context7"]);
  assert.deepEqual(group("Extension prompts").map((i) => i.name), ["coding-guides"]);
  assert.deepEqual(group("Memory files").map((i) => i.name), ["AGENTS.md", "~/.pi/agent/AGENTS.md"]);
  assert.deepEqual(group("Skills").map((i) => i.name), ["brainstorming", "a&b"]);

  const bare = computeBreakdown(input({ system: state({ sections: { preamble: "P" }, tools: [] }) }));
  assert.deepEqual(bare.details, []);
});
