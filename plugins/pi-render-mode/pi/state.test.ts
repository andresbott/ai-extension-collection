import assert from "node:assert/strict";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, test } from "node:test";

import { loadMode, saveMode, stateFilePath } from "./state.ts";

const dirs: string[] = [];
async function tempFile(name = "render-mode.json"): Promise<string> {
	const dir = await mkdtemp(join(tmpdir(), "render-mode-"));
	dirs.push(dir);
	return join(dir, name);
}

after(async () => {
	await Promise.all(dirs.map((dir) => rm(dir, { recursive: true, force: true })));
});

test("saveMode then loadMode round-trips the mode", async () => {
	const path = await tempFile();
	await saveMode("verbose", path);
	assert.equal(await loadMode(path), "verbose");
});

test("saveMode creates missing parent directories", async () => {
	const dir = await mkdtemp(join(tmpdir(), "render-mode-"));
	dirs.push(dir);
	const path = join(dir, "nested", "deeper", "render-mode.json");
	await saveMode("minimal", path);
	assert.equal(await loadMode(path), "minimal");
});

test("loadMode returns undefined when the file is missing", async () => {
	const path = await tempFile("does-not-exist.json");
	assert.equal(await loadMode(path), undefined);
});

test("loadMode returns undefined for malformed JSON", async () => {
	const path = await tempFile();
	await writeFile(path, "{ not json", "utf8");
	assert.equal(await loadMode(path), undefined);
});

test("loadMode returns undefined for a valid-JSON but invalid mode", async () => {
	const path = await tempFile();
	await writeFile(path, JSON.stringify({ mode: "loud" }), "utf8");
	assert.equal(await loadMode(path), undefined);
});

test("stateFilePath honors $PI_CODING_AGENT_DIR", () => {
	const previous = process.env.PI_CODING_AGENT_DIR;
	try {
		process.env.PI_CODING_AGENT_DIR = "/tmp/pi-agent-test";
		assert.equal(stateFilePath(), "/tmp/pi-agent-test/render-mode.json");
	} finally {
		if (previous === undefined) delete process.env.PI_CODING_AGENT_DIR;
		else process.env.PI_CODING_AGENT_DIR = previous;
	}
});

test("stateFilePath falls back to ~/.pi/agent when the env var is unset", () => {
	const previous = process.env.PI_CODING_AGENT_DIR;
	try {
		delete process.env.PI_CODING_AGENT_DIR;
		assert.ok(stateFilePath().endsWith("/.pi/agent/render-mode.json"));
	} finally {
		if (previous !== undefined) process.env.PI_CODING_AGENT_DIR = previous;
	}
});
