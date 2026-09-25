import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  buildContextItems,
  buildExtensionItems,
  buildPromptItems,
  buildSkillItems,
  labelExtensionSource,
  labelPackageSource,
  scanExtensionDir,
  shortPath,
} from "./discovery.ts";

test("shortPath prefers cwd-relative and home-relative labels", () => {
  assert.equal(shortPath("/repo/AGENTS.md", "/repo", "/home/me"), "AGENTS.md");
  assert.equal(shortPath("/home/me/.pi/agent/AGENTS.md", "/repo", "/home/me"), "~/.pi/agent/AGENTS.md");
});

test("package labels are compact for npm and local sources", () => {
  assert.equal(labelPackageSource("npm:@scope/pkg@1.2.3"), "@scope/pkg");
  assert.equal(labelPackageSource("./extensions/startup-splash"), "startup-splash");
  assert.equal(labelPackageSource("git:github.com/user/pi-stuff@v1"), "pi-stuff");
});

test("extension labels prefer package names from node_modules paths", () => {
  assert.equal(
    labelExtensionSource("/tmp/x/node_modules/@scope/pkg/extensions/index.ts"),
    "@scope/pkg",
  );
  assert.equal(labelExtensionSource("/tmp/x/extensions/render-mode/index.ts"), "render-mode");
});

test("buildContextItems, buildSkillItems, and buildPromptItems dedupe values", () => {
  const options = {
    cwd: "/repo",
    contextFiles: [{ path: "/repo/AGENTS.md" }, { path: "/repo/AGENTS.md" }],
    skills: [{ name: "effective-go" }, { name: "effective-go" }, { name: "council-mode" }],
  };
  assert.deepEqual(buildContextItems(options), ["AGENTS.md"]);
  assert.deepEqual(buildSkillItems(options), ["effective-go", "council-mode"]);
  assert.deepEqual(
    buildPromptItems([
      { name: "review", source: "prompt", sourceInfo: { path: "/x/review.md", source: "prompt", scope: "user", origin: "top-level" } },
      { name: "review", source: "prompt", sourceInfo: { path: "/x/review.md", source: "prompt", scope: "user", origin: "top-level" } },
      { name: "ext", source: "extension", sourceInfo: { path: "/x/ext.ts", source: "extension", scope: "user", origin: "top-level" } },
    ]),
    ["/review"],
  );
});

test("scanExtensionDir detects file and directory style extensions", () => {
  const dir = mkdtempSync(join(tmpdir(), "startup-splash-ext-"));
  writeFileSync(join(dir, "foo.ts"), "export default 1");
  mkdirSync(join(dir, "bar"));
  writeFileSync(join(dir, "bar", "index.ts"), "export default 2");
  assert.deepEqual(scanExtensionDir(dir), ["bar", "foo"]);
});

test("buildExtensionItems merges package, command, tool, and scanned dir hints", () => {
  const agentDir = mkdtempSync(join(tmpdir(), "startup-splash-agent-"));
  mkdirSync(join(agentDir, "extensions"));
  mkdirSync(join(agentDir, "extensions", "local-ext"));
  writeFileSync(join(agentDir, "extensions", "local-ext", "index.ts"), "export default 1");

  const items = buildExtensionItems({
    cwd: "/repo",
    agentDir,
    projectTrusted: false,
    settings: {
      packages: ["npm:pi-lens", "./extensions/startup-splash"],
      extensions: ["./extensions/render-mode/index.ts"],
    },
    commands: [
      {
        name: "hello",
        source: "extension",
        sourceInfo: {
          path: "/tmp/node_modules/pi-context/index.ts",
          source: "extension",
          scope: "user",
          origin: "package",
        },
      },
    ],
    tools: [
      {
        name: "search",
        sourceInfo: {
          path: "/tmp/node_modules/pi-fff/index.ts",
          source: "extension",
          scope: "user",
          origin: "package",
        },
      },
    ],
  });

  assert.deepEqual(items, [
    "pi-context",
    "pi-fff",
    "pi-lens",
    "startup-splash",
    "render-mode",
    "local-ext",
  ]);
});
