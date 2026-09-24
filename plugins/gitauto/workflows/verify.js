export const meta = {
  name: 'verify-run',
  description: 'Run requested or locally declared repository verification checks',
  phases: [{ title: 'Verify', detail: 'Run guarded checks sequentially and report their outcome' }],
}

phase('Verify')

const positional = typeof args?._ === 'string' ? args._.trim() : ''
const namedCheck = typeof args?.check === 'string' ? args.check.trim() : ''
const namedTarget = typeof args?.target === 'string' ? args.target.trim() : ''
let request = positional
if (namedCheck) request = `check=${namedCheck}`
if (namedTarget) request = `target=${namedTarget}`
const shellQuote = value => `'${value.replaceAll("'", `'"'"'`)}'`
const root = typeof args?.root === 'string' && args.root.trim() ? args.root.trim() : '$HOME/.pi/workflows/saved'
const helper = `bash "${root}/gitauto-verify.sh"`
const command = request ? `${helper} ${shellQuote(request)}` : helper

const result = await agent(
  `Operate on the current Git repository and perform only verification.

Verification helper command: ${command}
Requested check or target: ${JSON.stringify(request || null)}

Rules:
1. Run the exact helper command once. The helper owns discovery, ordering, and fail-fast behavior.
2. Do not stage, commit, branch, push, reset, or edit source files.
3. Report every command emitted by the helper, in order.
4. Report state=pass only when all checks pass, state=fail when one fails, and state=skip when the helper discovers none.
5. Return the real outcome through the structured output tool; do not claim commands that did not run.`,
  {
    label: 'verify-repository',
    schema: {
      type: 'object',
      additionalProperties: false,
      required: ['state', 'commands', 'report'],
      properties: {
        state: { type: 'string', enum: ['pass', 'fail', 'skip'] },
        commands: { type: 'array', items: { type: 'string' } },
        report: { type: 'string' },
      },
    },
  },
)

if (result === null) {
  return {
    status: 'incomplete',
    state: null,
    commands: [],
    report: 'The verification operator did not return a result; verification status is unknown.',
  }
}

return {
  status: result.state === 'fail' ? 'failed' : 'ok',
  ...result,
}
