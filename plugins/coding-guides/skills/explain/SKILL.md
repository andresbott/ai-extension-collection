---
name: explain
description: Use when you want to know how a piece of code works — a path, package, feature, or question — as one numbered list of every flow a caller can start, each a short walk-through of what happens, in order, checked against the code itself.
disable-model-invocation: true
---

Explain how the code works as short walk-throughs: what happens, in the order
it happens, from what the caller does to what comes back. The reader is a
developer who knows the domain but not this code. They should come away with an
accurate picture of every flow they can start and the few design choices that
shape them. Accuracy comes first: every step must be true of the code as it is
now.

## What to explain

- A path (file, package, directory): every flow a caller can start. A question
  or topic ("how does checkout work"): the flows that answer it, from the
  trigger to the result.
- A flow is a call the caller makes for a purpose of its own: an exported
  function or method, a handler, a command, a job. Each one gets its own entry,
  including:
  - Variants of another flow: a call that runs the same steps but returns more
    detail, or does part of the work ahead of time.
  - Maintenance and admin calls the caller makes on its own: cleanup, deletion,
    rebuilds, migrations, including the ones on parts the caller constructs and
    holds (a store, a cache).
- Not flows: constructors, options, config, getters, pure helpers the flows
  use, and test kits for implementers.

## Read before writing

Trace the real path; do not write from file names, doc comments, or a quick
skim.

1. List the entry points first. Go through the exported API of the target and
   of every part the caller constructs, and keep every call that starts a flow
   by the rules above. Each one on the list gets an entry; do not drop one
   because it is short or looks secondary.
2. For each flow, find the entry point and follow the calls, in the order they
   run, into every function that does a step of the flow. Read the bodies, not
   only their comments.
3. For each step, find the code that does it. A step you cannot point to is not
   a step: drop it, or read until you can.
4. Check the order against the code. If the code checks the cache before it
   reads the database, the steps say so in that order.
5. Check every condition. A step that only happens sometimes starts with what
   triggers it ("If the store has no copy, …"), and says what is skipped
   otherwise when that matters.
6. Check every claim about data: what is kept, where, under what key, and what
   is read from whom. "Stored by the user's id" must match the key in the code.
7. When the docs and the code disagree, follow the code, and add a short note
   after the list that says where they differ.

Stop going deeper once a step is clear at the level of the parts the reader
cares about (the app, the library, the store, the database). A helper that only
does part of a step is part of that step, not a step of its own.

## Format

At most a few words before the list. Then one numbered list with an item per
flow, the main flow first, variants right after the flow they share, and
maintenance calls last:

- Each item is a label, the call's name with its purpose in a few words in
  parentheses ("Get (serve a thumbnail)"), and its steps lettered a., b., c.
  under it. Calls that belong together, such as two cleanup calls on one store,
  may share an item with a step each.
- Two to nine steps per flow, one action each. A main flow usually needs five
  or more; a variant or maintenance call often needs only two or three.
- Hard limit: at most two sentences and about 40 words per step. A step that
  needs more is either two steps or carries detail that does not belong.
- The level is the flow, not the mechanics: what happens and in what order,
  not how each step does it. "The library reads the reply as tag names" is
  enough; the separators it splits on, the marks it strips and the lengths it
  rejects are not.
- Each step names who acts: "The app calls…", "The library resizes…", "The
  store returns…". Give each part one name and keep it for the whole list.
- Present tense, active voice, plain words.
- Say each thing once. If a step lists something as an input, don't also
  name it earlier in the same sentence ("calls Get on an image with two
  inputs: the image, …" says the image twice).
- When a step names several items (keys, fields, inputs), put the list last,
  after a colon, as short bare nouns: "looks it up in the store, with these
  keys: image id, preset and checksum". Do not weave the list into a phrase
  ("the store keyed by the image's id, the preset and its checksum").
- The first step is the trigger (what the caller does, with what). The last
  step is the result (what comes back, or what has changed).
- When a flow repeats steps of another, refer back in a few words ("runs the
  same steps as Get") instead of repeating them, and spell out only what
  differs.
- No explanations of what a standard mechanism is for. The reader is a
  developer: "using the store with the checksum as the key" is enough, and
  "so the same image is never resized twice" is noise. Add a reason only when
  it is specific to this code and the reader could not infer it, and keep it
  to a short clause. When in doubt, leave it out.
- When a rule is easier to see than to describe, give a tiny example in
  parentheses or quotes: a 4000×3000 photo at the "small" preset becomes
  320×240.
- Describe what the code does by default. Options, flags and settings stay out,
  by name and by effect, unless the reader passes them on the call being
  explained.
- No constants and no exact numbers (limits, thresholds, sizes, formulas)
  unless the reader passes the value in or the step makes no sense without it.
  "Only the start of the text" beats "the first 2048 bytes".

No closing summary, no recap, no offer of more detail. The only lines allowed
after the list are:

- The docs-versus-code note, only about what a flow does (its steps, their
  order, the data it keeps). A difference in error handling or another left-out
  topic is not a note.
- A short note on a flow the reader would expect but that does not exist,
  saying in one or two sentences what does that job instead.

## Names and code

- No code blocks, signatures, types, file paths, or line numbers.
- Use a code name only when the reader touches it: the call they make (`Get`)
  or the thing they must provide (a `Source`). Describe everything else by
  what it does: "an in-memory list of recent thumbnails", not `lruCache`.
  Config fields, option functions, constants and implementation types are
  never touched in a flow: describe them or leave them out.
- Use the domain's words (images, presets, originals) the way the code uses
  them.

## What to leave out

Inside a flow, unless the user asks or it changes what the flow does: error
handling and validation, retries, locking and concurrency guards, logging and
metrics, eviction and cleanup, and the alternatives behind an interface. This
is about steps, not entry points: a cleanup or delete call the caller makes on
its own is a flow, and it gets an entry.

## Check before answering

Write the draft, then go through it once and fix every hit:

1. Every entry point from the list in "Read before writing" has an entry.
2. No step is over two sentences or about 40 words.
3. No code name the reader does not call or provide, and no option, constant
   or exact number the reader does not pass in.
4. Nothing from "What to leave out" inside a step or in a note.
5. Nothing after the list but the two allowed notes.

## Example

For "explain the thumbnails package", a library that serves resized images:

> 1. Get (serve a thumbnail)
>    a. The app calls Get with three inputs: an image id, the checksum it
>       stored at upload, and a size preset.
>    b. The library looks the thumbnail up in the store, with these keys:
>       image id, preset and checksum. If the store has it, the library
>       returns it.
>    c. Otherwise the library reads the original from the app's `Source`.
>    d. The library resizes the original to fit the preset's box, keeping its
>       aspect ratio (a 4000×3000 photo at "small" becomes 320×240).
>    e. The library encodes the result in the preset's format and writes it
>       to the store.
>    f. The library returns the encoded thumbnail.
> 2. GetURL (a link instead of the bytes)
>    a. The app calls GetURL with the same inputs as Get.
>    b. It runs the same steps as Get, without reading the thumbnail back.
>    c. It returns a signed link to the thumbnail in the store.
> 3. Upload (accept a new original)
>    a. The app calls Upload with an image id and the original's bytes.
>    b. The library rotates the image upright when the camera recorded a
>       rotation, and computes its checksum.
>    c. The library renders every preset from the upright image, as Get does
>       on a miss, and writes each one to the store.
>    d. The library returns the checksum, which the app keeps with the image.
> 4. Store maintenance (the app calls these on the store)
>    a. Purge deletes every thumbnail of one image, for when the image is
>       deleted.
>    b. Expire deletes the thumbnails not read since a given time, across all
>       images.
>
> There is no call to change a preset: the next Get at a new size renders a
> new thumbnail, and Expire removes the old ones.

Instead of a tour of the files ("`thumbs.go` defines `Service`, which wraps a
`renderer`; `renderer.fit` calls `scale`…"), each step says what happens and
who does it.
