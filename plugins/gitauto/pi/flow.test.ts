import assert from "node:assert/strict";
import { test } from "node:test";

import { MAX_RESUMES, branchOut, ship, type Deps, type Script } from "./flow.ts";
import type { Texts } from "./protocol.ts";

interface Call {
  name: Script;
  args: string[];
  stdin?: string;
  env?: Record<string, string>;
}

/** Fake deps: scripted script outputs, keyed by the first argument (or "*"). */
function fake(outputs: Record<string, string[]>, opts: { texts?: Texts; expert?: boolean; choice?: string } = {}) {
  const calls: Call[] = [];
  const written: string[][] = [];
  const asked: { title: string; options: string[] }[] = [];
  const experts: string[] = [];
  const deps: Deps = {
    script: async (name, args, o) => {
      calls.push({ name, args, stdin: o?.stdin, env: o?.env });
      const queue = outputs[args[0]] ?? outputs["*"];
      const out = queue.length > 1 ? queue.shift()! : queue[0];
      return { code: 0, out };
    },
    write: async (_context, keys) => {
      written.push(keys);
      return opts.texts ?? {};
    },
    expert: async (base) => {
      experts.push(base);
      return opts.expert ?? true;
    },
    select: async (title, options) => {
      asked.push({ title, options });
      return opts.choice;
    },
    diagnose: async () => "Most likely a failing test.",
    progress: () => {},
  };
  return { deps, calls, written, asked, experts };
}

test("branch-out returns a DONE line without the model", async () => {
  const f = fake({ "*": ["DONE state=unchanged branch=feat/x"] });
  const report = await branchOut(f.deps, "");
  assert.match(report, /DONE state=unchanged branch=feat\/x/);
  assert.equal(f.written.length, 0);
  assert.deepEqual(f.calls[0].args, [""]);
});

test("branch-out asks the model for names, then creates one", async () => {
  const f = fake(
    {
      "": ["NEED_NAME on=main\n M a.txt\n--- write\nbranch: 3 distinct names"],
      "--create": ["DONE state=created branch=feat/a from=main"],
    },
    { texts: { branch: ["feat/a", "feat/b", "feat/c"] } },
  );
  const report = await branchOut(f.deps, "");
  assert.deepEqual(f.written, [["branch"]]);
  assert.deepEqual(f.calls[1].args, ["--create", "feat/a", "feat/b", "feat/c"]);
  assert.match(report, /DONE state=created/);
});

const cheapPrepare = [
  "SHIP branch=main protected=yes base=main pr=none need=pr writer=cheap",
  "args: no tag",
  "--- write",
  "branch: names",
  "title: prose",
  "subject: cc",
  "body: md",
  "--- status",
].join("\n");

test("ship passes each written text as its flag and the body on stdin", async () => {
  const texts = { branch: ["feat/a", "feat/b"], title: "Add it", subject: "feat: add it", body: "## Summary\nWhy." };
  const f = fake({ prepare: [cheapPrepare], run: ["ship: [1] verify ...\nSHIPPED pr=#7 tag=declined log=/x"] }, { texts });
  const report = await ship(f.deps, "no tag", "ship");
  assert.deepEqual(f.calls[0].args, ["prepare", "no tag"]);
  assert.deepEqual(f.written, [["branch", "title", "subject", "body"]]);
  assert.deepEqual(f.calls[1].args, [
    "run",
    "--no-tag",
    "--branch",
    "feat/a",
    "feat/b",
    "--title",
    "Add it",
    "--subject",
    "feat: add it",
    "--body-stdin",
  ]);
  assert.equal(f.calls[1].stdin, "## Summary\nWhy.");
  assert.match(report, /SHIPPED pr=#7/);
  assert.doesNotMatch(report, /ship: \[1\]/);
});

test("a DONE from prepare ends the flow", async () => {
  const f = fake({ prepare: ["DONE state=nothing branch=main report=nothing to ship"] });
  assert.match(await ship(f.deps, "", "ship"), /DONE state=nothing/);
  assert.equal(f.calls.length, 1);
});

test("WAITING resumes with only the resume flags, at most MAX_RESUMES times", async () => {
  const waiting = "WAITING stage=wait-ci pr=#7 report=CI still running log=/x";
  const f = fake(
    { prepare: ["SHIP branch=feat/x protected=no base=main pr=open#7_x need=none writer=cheap"], run: [waiting] },
    {},
  );
  const report = await ship(f.deps, "tag=v1.0.0 deleteRemote=true", "ship");
  const runs = f.calls.filter((c) => c.args[0] === "run");
  assert.equal(runs.length, 1 + MAX_RESUMES);
  for (const r of runs) assert.deepEqual(r.args, ["run", "--tag", "v1.0.0", "--delete-remote"]);
  assert.match(report, /WAITING/);
});

test("a resumed run that finishes stops the loop", async () => {
  const f = fake({
    prepare: ["SHIP branch=feat/x protected=no base=main pr=none need=none writer=cheap"],
    run: ["WAITING stage=wait-ci pr=#7 log=/x", "SHIPPED pr=#7 tag=none log=/x"],
  });
  const report = await ship(f.deps, "", "ship");
  assert.equal(f.calls.filter((c) => c.args[0] === "run").length, 2);
  assert.match(report, /SHIPPED/);
});

const tagAsk = "SHIPPED pr=#7 url=u tag=ask tag_recommended=v1.1.0 tag_options=v1.1.0,v1.0.1 latest=v1.0.0 log=/x";
const nonePrepare = "SHIP branch=feat/x protected=no base=main pr=none need=none writer=cheap";

test("tag=ask tags only an explicitly chosen version", async () => {
  const f = fake(
    { prepare: [nonePrepare], run: [tagAsk], tag: ["TAGGED version=v1.1.0 latest=v1.0.0 log=/y"] },
    { choice: "v1.1.0 (suggested)" },
  );
  const report = await ship(f.deps, "", "ship");
  assert.deepEqual(f.asked[0].options, ["No tag", "v1.1.0 (suggested)", "v1.0.1"]);
  assert.deepEqual(f.calls.at(-1)?.args, ["tag", "v1.1.0"]);
  assert.match(report, /TAGGED version=v1.1.0/);
});

test("tag=ask with No tag or no answer creates no tag", async () => {
  for (const choice of ["No tag", undefined]) {
    const f = fake({ prepare: [nonePrepare], run: [tagAsk] }, { choice });
    const report = await ship(f.deps, "", "ship");
    assert.ok(!f.calls.some((c) => c.args[0] === "tag"));
    assert.match(report, /No tag created\./);
  }
});

test("the expert writer saves a draft; the model then writes only branch names", async () => {
  const f = fake(
    {
      prepare: ["SHIP branch=main protected=yes base=main pr=none need=pr writer=expert\n--- write\nbranch: names"],
      run: ["SHIPPED pr=#7 tag=none log=/x"],
    },
    { texts: { branch: ["feat/big"] }, expert: true },
  );
  await ship(f.deps, "", "ship");
  assert.deepEqual(f.experts, ["main"]);
  assert.deepEqual(f.written, [["branch"]]);
  assert.deepEqual(f.calls.at(-1)?.args, ["run", "--branch", "feat/big"]);
});

test("without an expert draft, prepare re-runs with the cheap writer's context", async () => {
  const f = fake(
    {
      prepare: ["SHIP branch=feat/x protected=no base=main pr=none need=pr writer=expert", cheapPrepare],
      run: ["SHIPPED pr=#7 tag=none log=/x"],
    },
    { texts: { title: "T", subject: "feat: t", body: "B" }, expert: false },
  );
  await ship(f.deps, "", "ship").then((report) => assert.match(report, /expert writer saved no draft/));
  assert.equal(f.calls[1].args[0], "prepare");
  assert.equal(f.calls[1].env?.GITAUTO_CMD_COMPLEX_LINES, "1000000000");
  assert.deepEqual(f.written, [["branch", "title", "subject", "body"]]);
});

test("a failure block is reported with a one-sentence cause", async () => {
  const f = fake({
    prepare: [nonePrepare],
    run: ["ship: [1] verify -> fail\n--- failure: verify (last 60 lines)\nboom\nSTOPPED stage=verify state=fail log=/x"],
  });
  const report = await ship(f.deps, "", "ship");
  assert.match(report, /STOPPED stage=verify state=fail log=\/x\n--- failure: verify \(last 60 lines\)\nboom\n/);
  assert.match(report, /Most likely a failing test\./);
});

test("open-pr prepares --for pr, runs open-pr without tag flags, and hints at ship", async () => {
  const f = fake({
    prepare: ["SHIP branch=feat/x protected=no base=main pr=none need=none writer=cheap"],
    "open-pr": ["READY pr=#7 url=u ci=green log=/x"],
  });
  const report = await ship(f.deps, "no tag", "pr");
  assert.deepEqual(f.calls[0].args, ["prepare", "--for", "pr", "no tag"]);
  assert.deepEqual(f.calls[1].args, ["open-pr"]);
  assert.match(report, /READY pr=#7/);
  assert.match(report, /Run `\/gitauto:ship` to merge\./);
});
