export const meta = {
  name: 'open-pr-run',
  description: 'Create or reuse a pull request for the current feature branch',
  phases: [{ title: 'Open PR', detail: 'Resolve PR state and create one when absent' }],
}

phase('Open PR')

const title = typeof args?.title === 'string' ? args.title.trim() : ''
const body = typeof args?.body === 'string' ? args.body.trim() : ''
const base = typeof args?.base === 'string' ? args.base.trim() : ''
const shellQuote = value => `'${value.replaceAll("'", `'"'"'`)}'`
const root = typeof args?.root === 'string' && args.root.trim() ? args.root.trim() : '$HOME/.pi/workflows/saved'
const helper = `bash "${root}/gitauto-open-pr.sh"`
const baseArgument = base ? ` ${shellQuote(`base=${base}`)}` : ''
const baseInstruction = base ? `base=${JSON.stringify(base)}` : 'no base argument'
const explicit = title && body
  ? `${helper} ${shellQuote(`title=${title}`)} ${shellQuote(`body=${body}`)}${baseArgument}`
  : null
const instruction = explicit
  ? `Run this exact guarded helper command once:\n${explicit}`
  : `No complete title/body was supplied. First use read-only git log and git diff commands to understand the branch against ${JSON.stringify(base || 'the default branch')}. Write a concise one-line title and a compact body containing ## Summary and ## What, with ## Notes only when useful. Then invoke ${helper} exactly once with separately shell-quoted title=<title>, body=<body>, and ${baseInstruction}.`

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

if (result === null) return { status: 'incomplete', state: null, number: null, url: null, branch: null, report: 'PR operator returned no result.' }
if (result.state === 'failed') return { status: 'failed', ...result }
if (result.state === 'blocked' || result.state === 'closed') return { status: 'blocked', ...result }
return { status: 'ok', ...result }
