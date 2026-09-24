export const meta = {
  name: 'tag-run',
  description: 'Recommend or explicitly publish a validated SemVer release tag',
  phases: [{ title: 'Tag', detail: 'Validate release state and invoke make tag only when authorized' }],
}

phase('Tag')

const positional = typeof args?._ === 'string' ? args._.trim() : ''
const version = typeof args?.version === 'string' ? args.version.trim() : positional
const subject = typeof args?.subject === 'string' ? args.subject.trim() : ''
const remote = typeof args?.remote === 'string' && args.remote.trim() ? args.remote.trim() : 'origin'
const worktree = typeof args?.worktree === 'string' && args.worktree.trim() ? args.worktree.trim() : '.'
const shellQuote = value => `'${value.replaceAll("'", `'"'"'`)}'`
const root = typeof args?.root === 'string' && args.root.trim() ? args.root.trim() : '$HOME/.pi/workflows/saved'
const helper = `bash "${root}/gitauto-tag.sh"`
const versionArg = version ? ` ${shellQuote(`version=${version}`)}` : ''
const subjectArg = subject ? ` ${shellQuote(`subject=${subject}`)}` : ''
const command = `${helper}${versionArg}${subjectArg} ${shellQuote(`remote=${remote}`)} ${shellQuote(`worktree=${worktree}`)}`

const result = await agent(`Run this exact guarded release helper once:\n${command}\n\nAn explicit version authorizes the repository's make tag target, which may publish. With no version, only return a recommendation. Do not invent a version beyond the helper's result, and do not run git tag or git push directly.`, {
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

if (result === null) return { status: 'incomplete', state: null, version: null, latest: null, report: 'Tag operator returned no result.' }
if (result.state === 'failed') return { status: 'failed', ...result }
if (result.state === 'blocked') return { status: 'blocked', ...result }
return { status: 'ok', ...result }
