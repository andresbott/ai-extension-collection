export const meta = {
  name: 'flow-run',
  description: 'Internal gitauto delivery flow; launched by /gitauto:branch-out, /gitauto:open-pr, and /gitauto:ship',
  phases: [
    { title: 'Prepare', detail: 'Branch, verify, commit, and push' },
    { title: 'Publish', detail: 'Open the pull request and wait for CI' },
    { title: 'Land', detail: 'Merge, synchronize main, and clean up' },
    { title: 'Release', detail: 'Optionally publish an explicit release tag' },
  ],
}

// One workflow owns every stage so that only the three gitauto commands are
// user-facing. `until` selects how far the flow runs:
//   branch  → branch
//   open-pr → branch, verify, commit, push, open-pr
//   ship    → the full flow through cleanup and optional tag (default)

const UNTIL = ['branch', 'open-pr', 'ship']
const until = UNTIL.includes(args?.until) ? args.until : 'ship'
const str = value => (typeof value === 'string' ? value.trim() : '')
const shellQuote = value => `'${value.replaceAll("'", `'"'"'`)}'`
const root = str(args?.root) || '$HOME/.pi/workflows/saved'
const helper = name => `bash "${root}/gitauto-${name}.sh"`
const remote = str(args?.remote) || 'origin'
const base = str(args?.base)

const withStatus = (result, empty, map = {}) => {
  if (result === null) return { status: 'incomplete', ...empty }
  return { status: map[result.state] || 'ok', ...result }
}

// ---------------------------------------------------------------- stages

const branchStage = async requestedName => {
  const command = requestedName ? `${helper('branch')} ${shellQuote(requestedName)}` : helper('branch')
  const result = await agent(
    `Operate on the current Git repository and do only the branch task below.

Requested branch name: ${JSON.stringify(requestedName || null)}
Branch helper command: ${command}

Rules:
1. Determine the current branch. If it is not main or master, run the helper without inventing or creating another branch and report unchanged.
2. If a branch name was requested, run the exact helper command above. Do not alter the supplied name.
3. If no name was requested and the current branch is main or master, inspect the uncommitted changes with read-only git commands. Choose a concise lowercase branch name such as feat/<slug>, fix/<slug>, docs/<slug>, or chore/<slug> when the changes make the purpose clear.
4. If the changes do not suggest a useful name, run the helper without an argument; it provides deterministic file-based and invented fallbacks.
5. Do not stage, commit, push, reset, or modify files. Run the helper at most once.
6. Return the real outcome through the structured output tool. Use state=failed if the helper fails, and explain the error in report.`,
    {
      label: 'create-branch',
      schema: {
        type: 'object',
        additionalProperties: false,
        required: ['state', 'branch', 'nameSource', 'report'],
        properties: {
          state: { type: 'string', enum: ['created', 'unchanged', 'failed'] },
          branch: { type: ['string', 'null'] },
          nameSource: { type: 'string', enum: ['provided', 'changes', 'invented', 'existing'] },
          report: { type: 'string' },
        },
      },
    },
  )
  return withStatus(result, {
    branch: null,
    nameSource: null,
    report: 'The branch operator did not return a result; repository state is unknown.',
  }, { failed: 'failed' })
}

const verifyStage = async () => {
  const result = await agent(
    `Operate on the current Git repository and perform only verification.

Verification helper command: ${helper('verify')}

Rules:
1. Run the exact helper command once. The helper owns discovery, ordering, and fail-fast behavior.
2. Do not stage, commit, branch, push, reset, or edit source files.
3. Report every command emitted by the helper, in order.
4. Report state=pass only when all checks pass, state=fail when one fails, and state=skip when the helper discovers none.
5. Return the real outcome through the structured output tool; do not claim commands that did not run.`,
    {
      label: 'verify-repository',
      schema: {
        type: 'object',
        additionalProperties: false,
        required: ['state', 'commands', 'report'],
        properties: {
          state: { type: 'string', enum: ['pass', 'fail', 'skip'] },
          commands: { type: 'array', items: { type: 'string' } },
          report: { type: 'string' },
        },
      },
    },
  )
  return withStatus(result, {
    state: null,
    commands: [],
    report: 'The verification operator did not return a result; verification status is unknown.',
  }, { fail: 'failed' })
}

const commitStage = async requestedMessage => {
  const command = requestedMessage ? `${helper('commit')} ${shellQuote(`message=${requestedMessage}`)}` : null
  const result = await agent(
    `Operate on the current Git repository and perform only the commit task below.

Requested commit message: ${JSON.stringify(requestedMessage || null)}
${command ? `Commit helper command: ${command}` : `No message was supplied. Commit helper: ${helper('commit')}`}

Rules:
1. First determine the current branch with a read-only Git command. On main, master, or detached HEAD, invoke the helper with a harmless one-line message so its mandatory guard reports blocked. Do not stage anything yourself.
2. If the feature-branch tree is clean, invoke the helper with a harmless one-line message so it reports unchanged.
3. If a message was supplied, run the exact helper command above without altering it.
4. If no message was supplied and the feature-branch tree is dirty, inspect the diff with read-only Git commands, compose a concise one-line message with no body or Co-Authored-By trailer, and invoke the helper once with message=<text> as its single shell-quoted argument.
5. Never run git add or git commit directly. Never branch, push, reset, or edit source files. The helper must enforce branch safety immediately before staging.
6. Return the real helper outcome through the structured output tool. Use state=failed if the helper fails, and explain the error in report.`,
    {
      label: 'commit-changes',
      schema: {
        type: 'object',
        additionalProperties: false,
        required: ['state', 'branch', 'message', 'report'],
        properties: {
          state: { type: 'string', enum: ['committed', 'unchanged', 'blocked', 'failed'] },
          branch: { type: ['string', 'null'] },
          message: { type: ['string', 'null'] },
          report: { type: 'string' },
        },
      },
    },
  )
  return withStatus(result, {
    state: null,
    branch: null,
    message: null,
    report: 'The commit operator did not return a result; repository state is unknown.',
  }, { failed: 'failed', blocked: 'blocked' })
}

const pushStage = async () => {
  const command = `${helper('push')} ${shellQuote(`remote=${remote}`)}`
  const result = await agent(`Run only this guarded push command in the current repository:
${command}

Do not run git push directly, alter branches, commit, reset, merge, or edit files. Return the helper's real outcome through the structured output tool.`, {
    label: 'push-feature-branch',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['state', 'branch', 'remote', 'report'],
      properties: {
        state: { type: 'string', enum: ['pushed', 'blocked', 'failed'] },
        branch: { type: ['string', 'null'] },
        remote: { type: 'string' },
        report: { type: 'string' },
      },
    },
  })
  return withStatus(result, { state: null, branch: null, remote, report: 'Push operator returned no result.' },
    { failed: 'failed', blocked: 'blocked' })
}

const openPrStage = async (title, body) => {
  const baseArgument = base ? ` ${shellQuote(`base=${base}`)}` : ''
  const baseInstruction = base ? `base=${JSON.stringify(base)}` : 'no base argument'
  const instruction = title && body
    ? `Run this exact guarded helper command once:\n${helper('open-pr')} ${shellQuote(`title=${title}`)} ${shellQuote(`body=${body}`)}${baseArgument}`
    : `No complete title/body was supplied. First use read-only git log and git diff commands to understand the branch against ${JSON.stringify(base || 'the default branch')}. Write a concise one-line title${title ? ` (use exactly ${JSON.stringify(title)})` : ''} and a compact body containing ## Summary and ## What, with ## Notes only when useful${body ? ` (use exactly the supplied body: ${JSON.stringify(body)})` : ''}. Then invoke ${helper('open-pr')} exactly once with separately shell-quoted title=<title>, body=<body>, and ${baseInstruction}.`
  const result = await agent(`Open or reuse the current feature branch's pull request.

${instruction}

Do not commit, push, merge, reset, branch, or edit files. Return the helper's real outcome through structured output.`, {
    label: 'open-pull-request',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['state', 'number', 'url', 'branch', 'report'],
      properties: {
        state: { type: 'string', enum: ['created', 'reused', 'already-merged', 'closed', 'blocked', 'failed'] },
        number: { type: ['number', 'null'] },
        url: { type: ['string', 'null'] },
        branch: { type: ['string', 'null'] },
        report: { type: 'string' },
      },
    },
  })
  return withStatus(result, { state: null, number: null, url: null, branch: null, report: 'PR operator returned no result.' },
    { failed: 'failed', blocked: 'blocked', closed: 'blocked' })
}

const waitCiStage = async pr => {
  const command = pr ? `${helper('wait-ci')} ${shellQuote(`pr=${pr}`)}` : helper('wait-ci')
  const result = await agent(`Run this exact CI-wait helper command once:\n${command}\n\nDo not create, update, or merge a pull request. Do not modify Git state or files. Return the helper's real terminal state through structured output.`, {
    label: 'wait-for-ci',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['state', 'number', 'report'],
      properties: {
        state: { type: 'string', enum: ['green', 'failed', 'none', 'pending', 'blocked'] },
        number: { type: ['number', 'null'] },
        report: { type: 'string' },
      },
    },
  })
  return withStatus(result, { state: null, number: null, report: 'CI operator returned no result.' },
    { failed: 'failed', blocked: 'blocked', pending: 'blocked' })
}

const mergeStage = async (pr, subject) => {
  const prArg = pr ? ` ${shellQuote(`pr=${pr}`)}` : ''
  const instruction = subject
    ? `Run this exact guarded merge helper once:\n${helper('merge')}${prArg} ${shellQuote(`subject=${subject}`)}`
    : `Use read-only gh pr view and git log commands to identify the current branch's PR and derive a concise valid Conventional Commit subject from its title and commits. Then run ${helper('merge')}${prArg} once with a separately shell-quoted subject=<subject> argument.`
  const result = await agent(`${instruction}\n\nDo not wait for CI, delete branches, synchronize main, remove worktrees, tag, push, commit, or edit files. Return the helper's real outcome.`, {
    label: 'merge-pull-request',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['state', 'number', 'branch', 'subject', 'report'],
      properties: {
        state: { type: 'string', enum: ['merged', 'already-merged', 'blocked', 'failed'] },
        number: { type: ['number', 'null'] },
        branch: { type: ['string', 'null'] },
        subject: { type: ['string', 'null'] },
        report: { type: 'string' },
      },
    },
  })
  return withStatus(result, { state: null, number: null, branch: null, subject: null, report: 'Merge operator returned no result.' },
    { failed: 'failed', blocked: 'blocked' })
}

const syncMainStage = async () => {
  const mainArg = base ? ` ${shellQuote(`main=${base}`)}` : ''
  const command = `${helper('sync-main')} ${shellQuote(`remote=${remote}`)}${mainArg}`
  const result = await agent(`Run this exact default-branch synchronization helper once:\n${command}\n\nDo not merge a PR, push, remove worktrees, delete branches, tag, commit, or edit files. Return its real outcome.`, {
    label: 'sync-default-branch',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['state', 'branch', 'sha', 'worktree', 'report'],
      properties: {
        state: { type: 'string', enum: ['synced', 'blocked', 'failed'] },
        branch: { type: ['string', 'null'] },
        sha: { type: ['string', 'null'] },
        worktree: { type: ['string', 'null'] },
        report: { type: 'string' },
      },
    },
  })
  return withStatus(result, { state: null, branch: null, sha: null, worktree: null, report: 'Sync operator returned no result.' },
    { failed: 'failed', blocked: 'blocked' })
}

const cleanupStage = async (branch, deleteRemote) => {
  const branchArg = branch ? ` ${shellQuote(`branch=${branch}`)}` : ''
  const command = `${helper('cleanup')}${branchArg} ${shellQuote(`remote=${remote}`)} ${shellQuote(`deleteRemote=${deleteRemote}`)}`
  const result = await agent(`Run this exact guarded cleanup helper once:\n${command}\n\nDo not delete any local branch, force-remove a worktree, merge, tag, commit, or edit files. Return every helper sub-outcome accurately.`, {
    label: 'cleanup-feature-branch',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['state', 'remoteBranch', 'worktree', 'localBranch', 'report'],
      properties: {
        state: { type: 'string', enum: ['clean', 'partial', 'blocked', 'failed'] },
        remoteBranch: { type: 'string' },
        worktree: { type: 'string' },
        localBranch: { type: 'string', enum: ['kept'] },
        report: { type: 'string' },
      },
    },
  })
  return withStatus(result, { state: null, remoteBranch: 'unknown', worktree: 'unknown', localBranch: 'kept', report: 'Cleanup operator returned no result.' },
    { failed: 'failed', blocked: 'blocked', partial: 'partial' })
}

const tagStage = async (version, subject, worktree) => {
  const subjectArg = subject ? ` ${shellQuote(`subject=${subject}`)}` : ''
  const command = `${helper('tag')} ${shellQuote(`version=${version}`)}${subjectArg} ${shellQuote(`remote=${remote}`)} ${shellQuote(`worktree=${worktree || '.'}`)}`
  const result = await agent(`Run this exact guarded release helper once:\n${command}\n\nThe explicit version authorizes the repository's make tag target, which may publish. Do not invent a version beyond the helper's result, and do not run git tag or git push directly.`, {
    label: 'release-tag',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['state', 'version', 'latest', 'report'],
      properties: {
        state: { type: 'string', enum: ['tagged', 'recommended', 'blocked', 'failed'] },
        version: { type: ['string', 'null'] },
        latest: { type: ['string', 'null'] },
        report: { type: 'string' },
      },
    },
  })
  return withStatus(result, { state: null, version: null, latest: null, report: 'Tag operator returned no result.' },
    { failed: 'failed', blocked: 'blocked' })
}

// ---------------------------------------------------------------- flow

const stages = []
const failed = result => !result || ['failed', 'blocked', 'incomplete', 'stopped'].includes(result.status)
const record = (id, result, required = true) => {
  stages.push({ id, required, result })
  return result
}
const stop = (id, result) => ({
  status: result ? 'stopped' : 'incomplete',
  until,
  stoppedAt: id,
  stages,
  report: result?.report || `${id} returned no result`,
})
const done = report => ({ status: 'ok', until, stoppedAt: null, stages, report })

phase('Prepare')
const branch = record('branch', await branchStage(str(args?.branch) || str(args?._)))
if (failed(branch)) return stop('branch', branch)
if (until === 'branch') return done(branch.report)

const verify = record('verify', await verifyStage())
if (failed(verify)) return stop('verify', verify)

const commit = record('commit', await commitStage(str(args?.message)))
if (failed(commit)) return stop('commit', commit)

const push = record('push', await pushStage())
if (failed(push)) return stop('push', push)

phase('Publish')
const pullRequest = record('open-pr', await openPrStage(str(args?.title), str(args?.body)))
if (failed(pullRequest)) return stop('open-pr', pullRequest)
if (until === 'open-pr') return done(pullRequest.report)

let merge
if (pullRequest.state === 'already-merged') {
  merge = record('merge', { status: 'ok', state: 'already-merged', number: pullRequest.number, subject: null, report: 'merge already completed before this run' })
} else {
  const waitCi = record('wait-ci', await waitCiStage(String(pullRequest.number || '')))
  if (failed(waitCi)) return stop('wait-ci', waitCi)

  phase('Land')
  merge = record('merge', await mergeStage(String(pullRequest.number || ''), str(args?.subject) || str(args?.message)))
  if (failed(merge)) return stop('merge', merge)
}

phase('Land')
const syncMain = record('sync-main', await syncMainStage())
if (failed(syncMain)) return stop('sync-main', syncMain)

record('cleanup', await cleanupStage(
  branch.branch || push.branch || '',
  args?.deleteRemote === true || args?.deleteRemote === 'true',
))

// Tagging runs only for an explicit version. `tag: false` (the user declined a
// tag) and an absent tag both skip the stage; the ledger records a declined tag
// so the launching command knows not to offer one.
const tag = typeof args?.tag === 'string' ? args.tag.trim() : ''
if (args?.tag === false) {
  record('tag', { status: 'ok', state: 'declined', version: null, latest: null, report: 'tag declined by user; not offered' }, false)
} else if (tag) {
  phase('Release')
  record('tag', await tagStage(tag, merge.subject || str(args?.subject) || str(args?.message), syncMain.worktree || ''), false)
}

return {
  status: stages.some(stage => ['cleanup', 'tag'].includes(stage.id) && (failed(stage.result) || stage.result.status === 'partial')) ? 'partial' : 'ok',
  until,
  stoppedAt: null,
  stages,
  report: (await agent(`Summarize this gitauto ship stage ledger in under 120 words. Preserve failures, warnings, PR numbers, merge state, cleanup state, and tag state exactly; invent nothing. Do not suggest or ask about creating a release tag:\n${JSON.stringify(stages)}`, {
    label: 'summarize-ship',
  })) || 'Ship flow completed; see stage ledger.',
}
