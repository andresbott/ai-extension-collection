# Writing the README so it reads like a person wrote it

Adapted for READMEs from [humanizer](https://github.com/blader/humanizer)
(MIT), which builds on Wikipedia's
[Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing).

A model picks the wording that fits the widest range of readers and projects.
A person picks it for one reader and one project. Every pattern below is a form
of that default: a sentence that signals importance instead of adding a fact,
rhythm or formatting applied by rule, an ordinary feature dressed up as a
breakthrough, or chat leftovers. Two rules follow:

- **Every sentence adds a fact** the reader did not already have.
- **Nothing is made up.** A name, number, version, benchmark, quote, or
  comparison must come from the repo, its docs, or the user. When a sentence
  needs a detail you do not have, write a simpler sentence or list it as open
  in the final report.

## The patterns

The first five justify an edit on one sighting. A pattern marked *weak alone*
counts only when other tells share the passage.

### Staging instead of stating

1. **Not X but Y.** "It's not just a CLI, it's a workflow." State the point:
   "It runs the whole release from one command."
2. **One-line closers.** "That's the power of sense." after a section, or
   fragments like "No config. No setup." Cut the closer, or merge the
   fragments into one specific claim.
3. **Sayings that sound deep.** "At its core, search is about meaning." Replace
   it with the specific claim.
4. **A run-up before the point.** "Let's dive in", "Here's the thing", "Ever
   wondered how…?" Start with the point.
5. **Arguing with no one.** "This isn't just another tagging library." Remove
   the objection nobody raised.

### Rhythm by rule

6. **Forced triads.** "fast, simple, and reliable"; three examples every time.
   Use as many items as the facts give.
7. **Repeated openings.** Every bullet starting "Supports…". Merge or vary.
8. **Dashes as the universal connector** (*weak alone*). Use periods, commas,
   colons, or parentheses, unless the existing README uses dashes on purpose.
9. **Stacked qualifiers** (*weak alone*). "can potentially help" → "helps", or
   keep the one qualifier the facts support.
10. **Hyphenated pairs everywhere** (*weak alone*). Keep a hyphen only before a
    noun ("a self-hosted server") or where the dictionary has one.
11. **Missing subjects** (*weak alone*). "No configuration needed" → "It runs
    with the defaults" when naming the actor helps.

### Inflation

12. **Stock AI words.** delve, leverage, robust, seamless, comprehensive,
    cutting-edge, empower, unlock, elevate, streamline, landscape, testament,
    showcase. Use plain words.
13. **Inflated significance.** "a game-changer for developers", "the future of
    search". Keep the fact; end on the last concrete one.
14. **Vague connections.** "integrates with your workflow". Say what it
    connects to and how ("reads `go.mod` and writes `README.md`").
15. **-ing riders.** "…, making it ideal for…", "…, ensuring…". Keep only what
    the facts support, as its own sentence.
16. **Sales language.** "blazing fast", "powerful", "effortless", "beautiful".
    Say what it is or give the number ("indexes 10,000 files in 4 s").
17. **Borrowed authority.** "Trusted by developers worldwide", "industry
    standard". Name a real source or user and what they said, or cut it.
18. **Avoiding *is* and *has*.** "serves as", "boasts", "features". Write "is"
    and "has".

### Formatting by rule

19. **Bold as decoration.** Bold on every product name, or a bold label and
    colon on every bullet that only repeats the bullet ("**Speed:** It is
    fast"). Remove the bold; turn labeled bullets into plain ones or prose.
20. **Decorative headings.** Title Case, emojis (🚀 Quick Start), arrows,
    horizontal rules between every section, clever headings ("Your music,
    your rules"). Use sentence case and name what the section holds
    ("Install", "Add to your project").
21. **Curly quotes** (*weak alone*). Use straight quotes in Markdown.

### Leftovers from the chat and the draft

22. **Chatbot residue.** "Happy coding!", "Feel free to…", "I hope this
    helps", "Enjoy!". Remove the wrapper.
23. **Guesses about missing facts.** "It likely supports Windows as well."
    State what the repo shows, or leave it out and report it.
24. **A heading repeated in the first sentence.** "## Install" followed by
    "Installing is easy." Let the heading do the work.
25. **Writing about the document.** "This README explains…", "The table below
    lists…", "This section was added to replace…". Describe the project, not
    the page. Mention a previous version only in upgrade notes.

## When not to act

Leave a watched phrase alone inside a quote, a product or package name, or
text the author clearly chose (their tagline, their tone). In update mode, fix
the author's wording only where it shows several tells together; do not
rewrite a human-written README into your own voice. Reference text (install
steps, API examples, DEVELOPMENT.md) stays neutral and plain.

## Final check

Before writing the files, read the draft once more and search for the tells
that most often survive a rewrite: not-X-but-Y (1), closers (2), triads (6),
dashes (8), and bold labels (19). Then check that the rewrite neither added a
fact you cannot point to in the repo nor dropped one the old text had.
