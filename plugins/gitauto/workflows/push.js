export const meta = {
  name: 'push-run',
  description: 'Push the current feature branch and configure its upstream',
  phases: [{ title: 'Push', detail: 'Run the guarded feature-branch push' }],
}

phase('Push')

const remote = typeof args?.remote === 'string' && args.remote.trim() ? args.remote.trim() : 'origin'
const shellQuote = value => `'${value.replaceAll("'", `'"'"'`)}'`
const root = typeof args?.root === 'string' && args.root.trim() ? args.root.trim() : '$HOME/.pi/workflows/saved'
const command = `bash "${root}/gitauto-push.sh" ${shellQuote(`remote=${remote}`)}`

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

if (result === null) {
  return { status: 'incomplete', state: null, branch: null, remote, report: 'Push operator returned no result.' }
}

if (result.state === 'failed') return { status: 'failed', ...result }
if (result.state === 'blocked') return { status: 'blocked', ...result }
return { status: 'ok', ...result }
