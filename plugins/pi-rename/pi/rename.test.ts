import { test } from "node:test";
import assert from "node:assert/strict";

import { buildNamingPrompt, cleanGeneratedName, MAX_NAME_CHARS, parseManualTitle } from "./rename.ts";

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
