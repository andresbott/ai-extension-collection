export const meta = {
  name: 'commit-run',
  description: 'Create exactly one guarded feature-branch commit containing all changes',
  phases: [{ title: 'Commit', detail: 'Choose a message and invoke the guarded commit helper' }],
}

phase('Commit')

const positionalMessage = typeof args?._ === 'string' ? args._.trim() : ''
const namedMessage = typeof args?.message === 'string' ? args.message.trim() : ''
const requestedMessage = namedMessage || positionalMessage
const shellQuote = value => `'${value.replaceAll("'", `'"'"'`)}'`
const root = typeof args?.root === 'string' && args.root.trim() ? args.root.trim() : '$HOME/.pi/workflows/saved'
const helper = `bash "${root}/gitauto-commit.sh"`
const requestedCommand = requestedMessage
  ? `${helper} ${shellQuote(`message=${requestedMessage}`)}`
  : null

const result = await agent(
  `Operate on the current Git repository and perform only the commit task below.

Requested commit message: ${JSON.stringify(requestedMessage || null)}
${requestedCommand ? `Commit helper command: ${requestedCommand}` : 'No message was supplied.'}

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

if (result === null) {
  return {
    status: 'incomplete',
    state: null,
    branch: null,
    message: null,
    report: 'The commit operator did not return a result; repository state is unknown.',
  }
}

return {
  status: result.state === 'failed' ? 'failed' : 'ok',
  ...result,
}
