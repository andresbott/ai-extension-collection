export const meta = {
  name: 'branch-run',
  description: 'Leave main or master by creating a safely named feature branch',
  phases: [{ title: 'Branch', detail: 'Choose and create a feature branch when needed' }],
}

phase('Branch')

const positionalName = typeof args?._ === 'string' ? args._.trim() : ''
const namedName = typeof args?.name === 'string' ? args.name.trim() : ''
const requestedName = namedName || positionalName
const shellQuote = value => `'${value.replaceAll("'", `'"'"'`)}'`
const root = typeof args?.root === 'string' && args.root.trim() ? args.root.trim() : '$HOME/.pi/workflows/saved'
const helper = `bash "${root}/gitauto-branch.sh"`
const requestedCommand = requestedName ? `${helper} ${shellQuote(requestedName)}` : helper

const result = await agent(
  `Operate on the current Git repository and do only the branch task below.

Requested branch name: ${JSON.stringify(requestedName || null)}
Branch helper command: ${requestedCommand}

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

if (result === null) {
  return {
    status: 'incomplete',
    branch: null,
    nameSource: null,
    report: 'The branch operator did not return a result; repository state is unknown.',
  }
}

return {
  status: result.state === 'failed' ? 'failed' : 'ok',
  ...result,
}
