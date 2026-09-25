import assert from "node:assert/strict";
import { test } from "node:test";

import {
  NO_TAG,
  failureBlock,
  lastLine,
  parseFields,
  parseShipArgs,
  parseTexts,
  stripFrontmatter,
  tagQuestion,
  writeKeys,
} from "./protocol.ts";

test("parseFields keeps spaces inside a value until the next key", () => {
  const f = parseFields("STOPPED stage=wait-ci state=failed report=CI still running; re-run log=/tmp/x");
  assert.equal(f.stage, "wait-ci");
  assert.equal(f.report, "CI still running; re-run");
  assert.equal(f.log, "/tmp/x");
});

test("parseFields reads the SHIP line", () => {
  const f = parseFields("SHIP branch=main protected=yes base=main pr=open#7_fix:_x need=pr writer=expert");
  assert.deepEqual([f.protected, f.base, f.pr, f.need, f.writer], ["yes", "main", "open#7_fix:_x", "pr", "expert"]);
});

test("writeKeys lists only the keys of the --- write block", () => {
  const out = [
    "SHIP branch=main need=pr",
    "--- write",
    "branch: 3 distinct names",
    "title: one line",
    "--- status",
    "body: not a rule",
  ].join("\n");
  assert.deepEqual(writeKeys(out), ["branch", "title"]);
  assert.deepEqual(writeKeys("SHIP need=none"), []);
});

test("failureBlock is everything from --- failure up to the final line", () => {
  const out = "ship: [1] verify -> fail\n--- failure: verify\nboom\nSTOPPED stage=verify\n";
  assert.equal(failureBlock(out), "--- failure: verify\nboom");
  assert.equal(lastLine(out), "STOPPED stage=verify");
  assert.equal(failureBlock("SHIPPED pr=#1"), undefined);
});

test("parseTexts reads === sections, one-line texts, and branch lists", () => {
  const reply = [
    "=== branch",
    "- feat/a",
    "`feat/b`",
    "3. feat/c",
    "=== title",
    "'Add a thing'",
    "=== subject-from-title",
    "",
    "=== subject",
    "feat(x): add a thing",
    "=== body",
    "## Summary",
    "Why.",
    "",
    "## What",
    "- it",
  ].join("\n");
  const t = parseTexts(reply, ["branch", "title", "subject", "body"]);
  assert.deepEqual(t.branch, ["feat/a", "feat/b", "feat/c"]);
  assert.equal(t.title, "Add a thing");
  assert.equal(t.subject, "feat(x): add a thing");
  assert.equal(t.body, "## Summary\nWhy.\n\n## What\n- it");
});

test("parseTexts maps subject-from-title to subject and tolerates code fences", () => {
  const t = parseTexts("```\n=== subject\nfix: reshape it\n```", ["subject-from-title"]);
  assert.equal(t.subject, "fix: reshape it");
});

test("parseTexts fails when a requested text is missing", () => {
  assert.throws(() => parseTexts("=== title\nX", ["title", "message"]), /did not write a message/);
});

test("parseShipArgs reads tag, declined tag, and delete-remote wordings", () => {
  assert.deepEqual(parseShipArgs("feat/x tag=v1.2.0"), { tag: "v1.2.0", noTag: false, deleteRemote: false });
  assert.equal(parseShipArgs("no tag").noTag, true);
  assert.equal(parseShipArgs("dont tag please").noTag, true);
  assert.equal(parseShipArgs("skip-tag").noTag, true);
  assert.equal(parseShipArgs("feat/tagging").noTag, false);
  assert.equal(parseShipArgs("deleteRemote=true").deleteRemote, true);
  assert.equal(parseShipArgs("and delete the remote").deleteRemote, true);
  assert.deepEqual(parseShipArgs(""), { tag: undefined, noTag: false, deleteRemote: false });
});

test("tagQuestion puts No tag first, marks the suggestion, and maps back", () => {
  const q = tagQuestion({ pr: "#7", latest: "v1.0.0", tag_recommended: "v1.1.0", tag_options: "v1.1.0,v1.0.1,v2.0.0" });
  assert.equal(q.title, "PR #7 is merged. Create a release tag? (latest: v1.0.0)");
  assert.deepEqual(q.options, [NO_TAG, "v1.1.0 (suggested)", "v1.0.1", "v2.0.0"]);
  assert.equal(q.versionOf("v1.1.0 (suggested)"), "v1.1.0");
  assert.equal(q.versionOf("v2.0.0"), "v2.0.0");
  assert.equal(q.versionOf(NO_TAG), undefined);
  assert.equal(q.versionOf(undefined), undefined);
  assert.match(tagQuestion({ pr: "#1" }).title, /latest: none/);
});

test("stripFrontmatter returns the Markdown body", () => {
  assert.equal(stripFrontmatter("---\nname: x\n---\n\nBody text\n"), "Body text");
  assert.equal(stripFrontmatter("No frontmatter"), "No frontmatter");
});
