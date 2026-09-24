export const meta = {
  name: 'ship-run',
  description: 'Ship current work through verification, pull request, merge, synchronization, cleanup, and optional tagging',
  phases: [
    { title: 'Prepare', detail: 'Branch, verify, commit, and push' },
    { title: 'Publish', detail: 'Open the pull request and wait for CI' },
    { title: 'Land', detail: 'Merge, synchronize main, and clean up' },
    { title: 'Release', detail: 'Optionally publish an explicit release tag' },
  ],
}

const stages = []
const root = typeof args?.root === 'string' ? args.root : ''
const failed = result => !result || ['failed', 'blocked', 'incomplete', 'stopped'].includes(result.status)
const run = async (id, name, input, required = true) => {
  let result
  try {
    result = await workflow(name, { ...input, root })
  } catch (error) {
    result = { status: 'incomplete', state: null, report: error instanceof Error ? error.message : String(error) }
  }
  stages.push({ id, required, result })
  return result
}

phase('Prepare')
const branch = await run('branch', 'gitauto:branch-run', { name: args?.branch || '' })
if (failed(branch)) return { status: branch ? 'stopped' : 'incomplete', stoppedAt: 'branch', stages, report: branch?.report || 'branch returned no result' }

const verify = await run('verify', 'gitauto:verify-run', {})
if (failed(verify)) return { status: verify ? 'stopped' : 'incomplete', stoppedAt: 'verify', stages, report: verify?.report || 'verify returned no result' }

const commit = await run('commit', 'gitauto:commit-run', { message: args?.message || '' })
if (failed(commit)) return { status: commit ? 'stopped' : 'incomplete', stoppedAt: 'commit', stages, report: commit?.report || 'commit returned no result' }

const push = await run('push', 'gitauto:push-run', { remote: args?.remote || 'origin' })
if (failed(push)) return { status: push ? 'stopped' : 'incomplete', stoppedAt: 'push', stages, report: push?.report || 'push returned no result' }

phase('Publish')
const pullRequest = await run('open-pr', 'gitauto:open-pr-run', {
  title: args?.title || '',
  body: args?.body || '',
  base: args?.base || '',
})
if (failed(pullRequest)) return { status: pullRequest ? 'stopped' : 'incomplete', stoppedAt: 'open-pr', stages, report: pullRequest?.report || 'open-pr returned no result' }

let merge
if (pullRequest.state === 'already-merged') {
  merge = { status: 'ok', state: 'already-merged', number: pullRequest.number, subject: null, report: 'merge already completed before this run' }
  stages.push({ id: 'merge', required: true, result: merge })
} else {
  const waitCi = await run('wait-ci', 'gitauto:wait-ci-run', { pr: String(pullRequest.number || '') })
  if (failed(waitCi)) return { status: waitCi ? 'stopped' : 'incomplete', stoppedAt: 'wait-ci', stages, report: waitCi?.report || 'wait-ci returned no result' }

  phase('Land')
  merge = await run('merge', 'gitauto:merge-run', {
    pr: String(pullRequest.number || ''),
    subject: args?.subject || args?.message || '',
  })
  if (failed(merge)) return { status: merge ? 'stopped' : 'incomplete', stoppedAt: 'merge', stages, report: merge?.report || 'merge returned no result' }
}

phase('Land')
const syncMain = await run('sync-main', 'gitauto:sync-main-run', {
  remote: args?.remote || 'origin',
  main: args?.base || '',
})
if (failed(syncMain)) return { status: syncMain ? 'stopped' : 'incomplete', stoppedAt: 'sync-main', stages, report: syncMain?.report || 'sync-main returned no result' }

await run('cleanup', 'gitauto:cleanup-run', {
  branch: branch.branch || push.branch || '',
  remote: args?.remote || 'origin',
  deleteRemote: args?.deleteRemote === true || args?.deleteRemote === 'true',
})
if (args?.tag) {
  phase('Release')
  await run('tag', 'gitauto:tag-run', {
    version: String(args.tag),
    subject: merge.subject || args?.subject || args?.message || '',
    remote: args?.remote || 'origin',
    worktree: syncMain.worktree || '',
  }, false)
}

return {
  status: stages.some(stage => ['cleanup', 'tag'].includes(stage.id) && (failed(stage.result) || stage.result.status === 'partial')) ? 'partial' : 'ok',
  stoppedAt: null,
  stages,
  report: (await agent(`Summarize this gitauto ship stage ledger in under 120 words. Preserve failures, warnings, PR numbers, merge state, cleanup state, and tag state exactly; invent nothing:\n${JSON.stringify(stages)}`, {
    label: 'summarize-ship',
  })) || 'Ship flow completed; see stage ledger.',
}
