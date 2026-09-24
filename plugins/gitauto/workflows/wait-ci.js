export const meta = {
  name: 'wait-ci-run',
  description: 'Wait for pull request checks and classify their terminal state',
  phases: [{ title: 'Wait for CI', detail: 'Watch checks without merging' }],
}

phase('Wait for CI')

const positional = typeof args?._ === 'string' ? args._.trim() : ''
const named = typeof args?.pr === 'string' ? args.pr.trim() : ''
const pr = named || positional
const root = typeof args?.root === 'string' && args.root.trim() ? args.root.trim() : '$HOME/.pi/workflows/saved'
const helper = `bash "${root}/gitauto-wait-ci.sh"`
const command = pr ? `${helper} 'pr=${pr.replaceAll("'", `'"'"'`)}'` : helper

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

if (result === null) return { status: 'incomplete', state: null, number: null, report: 'CI operator returned no result.' }
if (result.state === 'failed') return { status: 'failed', ...result }
if (result.state === 'blocked' || result.state === 'pending') return { status: 'blocked', ...result }
return { status: 'ok', ...result }
