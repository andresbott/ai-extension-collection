import assert from "node:assert/strict";
import { test } from "node:test";

import {
	describeMode,
	hiddenThinkingLabel,
	hideKnownCustomToolRow,
	isRenderMode,
	KNOWN_CUSTOM_TOOL_NAMES,
	nextMode,
	RENDER_MODES,
	resultPlan,
	showThinking,
	statusText,
	transformThinking,
	workingMessage,
} from "./modes.ts";

test("nextMode cycles normal → verbose → minimal → normal", () => {
	assert.equal(nextMode("normal"), "verbose");
	assert.equal(nextMode("verbose"), "minimal");
	assert.equal(nextMode("minimal"), "normal");
});

test("RENDER_MODES starts at normal (the default)", () => {
	assert.equal(RENDER_MODES[0], "normal");
});

test("isRenderMode accepts valid modes and rejects everything else", () => {
	for (const mode of RENDER_MODES) assert.ok(isRenderMode(mode));
	assert.equal(isRenderMode("loud"), false);
	assert.equal(isRenderMode(undefined), false);
	assert.equal(isRenderMode(3), false);
});

test("showThinking is true only in verbose", () => {
	assert.equal(showThinking("verbose"), true);
	assert.equal(showThinking("normal"), false);
	assert.equal(showThinking("minimal"), false);
});

test("describeMode and statusText produce a non-empty string per mode", () => {
	for (const mode of RENDER_MODES) {
		assert.ok(describeMode(mode).length > 0);
		assert.equal(statusText(mode), `render: ${mode}`);
	}
});

test("known custom tool rows are hidden only in minimal mode", () => {
	assert.ok(KNOWN_CUSTOM_TOOL_NAMES.size > 0);
	for (const toolName of KNOWN_CUSTOM_TOOL_NAMES) {
		assert.equal(hideKnownCustomToolRow("minimal", toolName), true);
		assert.equal(hideKnownCustomToolRow("normal", toolName), false);
		assert.equal(hideKnownCustomToolRow("verbose", toolName), false);
	}
	assert.equal(hideKnownCustomToolRow("minimal", "unknown_future_tool"), false);
	assert.equal(hideKnownCustomToolRow("minimal", undefined), false);
});

test("workingMessage is set only in minimal", () => {
	assert.equal(workingMessage("minimal"), "working…");
	assert.equal(workingMessage("normal"), undefined);
	assert.equal(workingMessage("verbose"), undefined);
});

test("hiddenThinkingLabel resets in verbose, set otherwise", () => {
	assert.equal(hiddenThinkingLabel("verbose"), undefined);
	assert.equal(typeof hiddenThinkingLabel("normal"), "string");
	assert.equal(typeof hiddenThinkingLabel("minimal"), "string");
});

test("transformThinking blanks thinking unless verbose, passes other content through", () => {
	assert.equal(transformThinking("secret plan", "assistant-thinking", "normal"), "");
	assert.equal(transformThinking("secret plan", "assistant-thinking", "minimal"), "");
	assert.equal(transformThinking("secret plan", "assistant-thinking", "verbose"), "secret plan");
	// Non-thinking content is always untouched, even when thinking is hidden.
	assert.equal(transformThinking("hello", "assistant", "normal"), "hello");
	assert.equal(transformThinking("hello", "user", "minimal"), "hello");
});

test("resultPlan: minimal hides everything", () => {
	const plan = resultPlan("minimal", { expanded: true, isPartial: false });
	assert.equal(plan.hide, true);
	assert.equal(plan.showBody, false);
});

test("resultPlan: partial results show a partial indicator (except minimal)", () => {
	assert.deepEqual(resultPlan("normal", { isPartial: true }), {
		hide: false,
		partial: true,
		showBody: false,
		maxLines: 0,
	});
	// minimal wins over partial — still hidden.
	assert.equal(resultPlan("minimal", { isPartial: true }).hide, true);
});

test("resultPlan: normal shows body only when expanded, verbose always shows a bigger body", () => {
	const normalCollapsed = resultPlan("normal", { expanded: false, isPartial: false });
	assert.equal(normalCollapsed.showBody, false);

	const normalExpanded = resultPlan("normal", { expanded: true, isPartial: false });
	assert.equal(normalExpanded.showBody, true);
	assert.equal(normalExpanded.maxLines, 20);

	const verbose = resultPlan("verbose", { expanded: false, isPartial: false });
	assert.equal(verbose.showBody, true);
	assert.ok(verbose.maxLines > normalExpanded.maxLines);
});
