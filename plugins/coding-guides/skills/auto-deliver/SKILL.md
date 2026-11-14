---
name: auto-deliver
description: Use when handing the rest of the current feature to the agent and you only want to be asked about really critical issues.
disable-model-invocation: true
---

Continue the implementation on the current branch until the feature is complete.

- If a question comes up, invoke a named agent or create a new specialized agent to answer it.
- Only stop to ask me about really critical issues.
- Choose the approach with the best long-term maintainability.

## Keep my words as the reference

1. **Restate first.** Before building, list every item I asked for, quoted
   word for word, each with a "Read as:" line. Name any word or phrase that
   could mean two things, with both meanings.
2. **Do not guess at forks.** If two readings would lead to different results
   and the code or conversation does not settle it, that is a critical issue:
   ask me. If you cannot wait for me, mark the item "Needs you:" with both
   readings, build the unambiguous parts, and leave the fork open.
3. **Briefs carry both.** Every subagent prompt quotes my words under "The
   user asked:" and your reading separately under "My reading:". Tell it to
   report anything that contradicts your reading instead of working around it.
4. **Check against my words.** When you think the feature is done, launch a
   fresh subagent with only my original words and the result (the diff, plus
   output or screenshots where they show it). It checks each item, clause by
   clause, and reports what does not match. Do not give it your reading or the
   implementers' reports. Fix the mismatches, or list them as open.
5. **Report what I can check.** The final note opens with "Check these": the
   assumptions you made and any "Needs you:" items. Then, for each item I
   asked for, say what changed and where, in terms I can verify without
   reading the code.
