export const meta = {
  name: 'sync-main-run',
  description: 'Synchronize the primary worktree default branch by fast-forward only',
  phases: [{ title: 'Sync main', detail: 'Fast-forward the primary worktree safely' }],
}

phase('Sync main')

const remote = typeof args?.remote === 'string' && args.remote.trim() ? args.remote.trim() : 'origin'
const main = typeof args?.main === 'string' ? args.main.trim() : ''
const shellQuote = value => `'${value.replaceAll("'", `'"'"'`)}'`
const root = typeof args?.root === 'string' && args.root.trim() ? args.root.trim() : '$HOME/.pi/workflows/saved'
const helper = `bash "${root}/gitauto-sync-main.sh"`
const mainArg = main ? ` ${shellQuote(`main=${main}`)}` : ''
const command = `${helper} ${shellQuote(`remote=${remote}`)}${mainArg}`

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

if (result === null) return { status: 'incomplete', state: null, branch: null, sha: null, worktree: null, report: 'Sync operator returned no result.' }
if (result.state === 'failed') return { status: 'failed', ...result }
if (result.state === 'blocked') return { status: 'blocked', ...result }
return { status: 'ok', ...result }
