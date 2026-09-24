export const meta = {
  name: 'cleanup-run',
  description: 'Clean up a merged feature branch without deleting its local branch',
  phases: [{ title: 'Cleanup', detail: 'Prune remote state and remove safe worktrees' }],
}

phase('Cleanup')

const branch = typeof args?.branch === 'string' ? args.branch.trim() : ''
const remote = typeof args?.remote === 'string' && args.remote.trim() ? args.remote.trim() : 'origin'
const deleteRemote = args?.deleteRemote === true || args?.deleteRemote === 'true'
const shellQuote = value => `'${value.replaceAll("'", `'"'"'`)}'`
const root = typeof args?.root === 'string' && args.root.trim() ? args.root.trim() : '$HOME/.pi/workflows/saved'
const helper = `bash "${root}/gitauto-cleanup.sh"`
const branchArg = branch ? ` ${shellQuote(`branch=${branch}`)}` : ''
const command = `${helper}${branchArg} ${shellQuote(`remote=${remote}`)} ${shellQuote(`deleteRemote=${deleteRemote}`)}`

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

if (result === null) return { status: 'incomplete', state: null, remoteBranch: 'unknown', worktree: 'unknown', localBranch: 'kept', report: 'Cleanup operator returned no result.' }
if (result.state === 'failed') return { status: 'failed', ...result }
if (result.state === 'blocked') return { status: 'blocked', ...result }
if (result.state === 'partial') return { status: 'partial', ...result }
return { status: 'ok', ...result }
