import { test } from "node:test";
import assert from "node:assert/strict";

import {
  buildNamingPrompt,
  buildTranscript,
  cleanGeneratedName,
  MAX_NAME_CHARS,
  parseManualTitle,
} from "./rename.ts";

const msg = (role, content) => ({ type: "message", message: { role, content } });

test("parseManualTitle: no argument means generate", () => {
  assert.equal(parseManualTitle(""), undefined);
  assert.equal(parseManualTitle("   "), undefined);
  assert.equal(parseManualTitle(undefined), undefined);
  assert.equal(parseManualTitle('""'), undefined);
});

test("parseManualTitle: a quoted title is taken verbatim without its quotes", () => {
  assert.equal(parseManualTitle('"some title"'), "some title");
  assert.equal(parseManualTitle("'some title'"), "some title");
  assert.equal(parseManualTitle("“some title”"), "some title");
  assert.equal(parseManualTitle('  "Fix: auth.  Bug!"  '), "Fix: auth.  Bug!");
});

test("parseManualTitle: an unquoted title is taken verbatim", () => {
  assert.equal(parseManualTitle("some title"), "some title");
  assert.equal(parseManualTitle("v1.2 release — notes."), "v1.2 release — notes.");
});

test("parseManualTitle: inner or unbalanced quotes are kept", () => {
  assert.equal(parseManualTitle('the "real" fix'), 'the "real" fix');
  assert.equal(parseManualTitle('"half quoted'), '"half quoted');
  assert.equal(parseManualTitle(`"mixed'`), `"mixed'`);
});

test("buildTranscript keeps user and assistant text only", () => {
  const entries = [
    msg("user", "add a /rename command"),
    msg("assistant", [
      { type: "thinking", thinking: "hmm" },
      { type: "text", text: "Sure." },
      { type: "toolCall", name: "read", arguments: {} },
    ]),
    msg("toolResult", [{ type: "text", text: "file contents" }]),
    { type: "model_change" },
    msg("assistant", [{ type: "toolCall", name: "bash", arguments: {} }]),
  ];
  assert.equal(buildTranscript(entries), "User: add a /rename command\n\nAssistant: Sure.");
});

test("buildTranscript returns an empty string for an empty session", () => {
  assert.equal(buildTranscript([]), "");
  assert.equal(buildTranscript([{ type: "model_change" }]), "");
});

test("buildTranscript keeps the start and the end when too long", () => {
  const entries = [msg("user", "GOAL " + "a".repeat(500)), msg("assistant", "b".repeat(500) + " NOW")];
  const out = buildTranscript(entries, 200);
  assert.ok(out.length <= 200, `length ${out.length} within budget`);
  assert.ok(out.startsWith("User: GOAL"));
  assert.ok(out.endsWith("NOW"));
  assert.match(out, /\[…\]/);
});

test("buildNamingPrompt embeds the transcript", () => {
  const prompt = buildNamingPrompt("User: hi");
  assert.match(prompt, /<conversation>\nUser: hi\n<\/conversation>/);
  assert.match(prompt, /title only/i);
});

test("cleanGeneratedName tidies common model replies", () => {
  assert.equal(cleanGeneratedName("Add LLM Rename Command"), "Add LLM Rename Command");
  assert.equal(cleanGeneratedName('"Add LLM Rename Command"'), "Add LLM Rename Command");
  assert.equal(cleanGeneratedName("Title: Add rename command."), "Add rename command");
  assert.equal(cleanGeneratedName("**Session title**"), "Session title");
  assert.equal(cleanGeneratedName("\n\n  Fix   auth\tbug  \nExplanation: ..."), "Fix auth bug");
  assert.equal(cleanGeneratedName("# Heading title"), "Heading title");
});

test("cleanGeneratedName returns empty for blank replies and caps length", () => {
  assert.equal(cleanGeneratedName(""), "");
  assert.equal(cleanGeneratedName('   \n ""  '), "");
  assert.equal(cleanGeneratedName("x".repeat(200)).length, MAX_NAME_CHARS);
});
