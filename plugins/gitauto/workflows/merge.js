export const meta = {
  name: 'merge-run',
  description: 'Squash-merge an open pull request with a Conventional Commit subject',
  phases: [{ title: 'Merge', detail: 'Validate and squash-merge the pull request' }],
}

phase('Merge')

const positional = typeof args?._ === 'string' ? args._.trim() : ''
const pr = typeof args?.pr === 'string' ? args.pr.trim() : ''
const supplied = typeof args?.subject === 'string' ? args.subject.trim() : positional
const shellQuote = value => `'${value.replaceAll("'", `'"'"'`)}'`
const root = typeof args?.root === 'string' && args.root.trim() ? args.root.trim() : '$HOME/.pi/workflows/saved'
const helper = `bash "${root}/gitauto-merge.sh"`
const prArg = pr ? ` ${shellQuote(`pr=${pr}`)}` : ''
const explicit = supplied ? `${helper}${prArg} ${shellQuote(`subject=${supplied}`)}` : null
const instruction = explicit
  ? `Run this exact guarded merge helper once:\n${explicit}`
  : `Use read-only gh pr view and git log commands to identify the current branch's PR and derive a concise valid Conventional Commit subject from its title and commits. Then run ${helper}${prArg} once with a separately shell-quoted subject=<subject> argument.`

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

if (result === null) return { status: 'incomplete', state: null, number: null, branch: null, subject: null, report: 'Merge operator returned no result.' }
if (result.state === 'failed') return { status: 'failed', ...result }
if (result.state === 'blocked') return { status: 'blocked', ...result }
return { status: 'ok', ...result }
