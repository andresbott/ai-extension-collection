---
name: explain
description: Use when you want to know how a piece of code works — a path, package, feature, or question — as a short numbered picture of the flows that matter, each a few steps of what happens, in order, checked against the code itself. Groups similar calls (like CRUD) into one point and skips setup.
disable-model-invocation: true
---

Explain how the code works as short walk-throughs: what happens, in the order
it happens, from what the caller does to what comes back. Short is the goal:
the reader should see the shape of the code at a glance, not read a manual. The reader is a
developer who knows the domain but not this code. They should come away with an
accurate picture of every flow they can start and the few design choices that
shape them. Accuracy comes first: every step must be true of the code as it is
now.

## What to explain

- The goal is a picture of what the code does, not a catalogue of its API. A
  path (file, package, directory): the few flows that make up its job. A
  question or topic ("how does checkout work"): the flows that answer it, from
  the trigger to the result.
- A flow is a call the caller makes for a purpose of its own: an exported
  function or method, a handler, a command, a job. Pick the ones that tell the
  reader what the code is for, and summarize the rest:
  - Calls that do the same kind of job on different inputs, and
    create/read/update/delete-style groups, become one point ("CRUD on
    bookmarks: create, edit, list and delete go straight to the store"). Say
    what the group is and what it has in common; do not walk through each call.
  - Variants of a flow (same steps, different input or more detail) are one
    line inside the flow they vary, saying only what differs.
  - Maintenance and admin calls (cleanup, deletion, rebuilds, migrations) get
    one short point at the end, and only when they change what the reader
    needs to know.
- Left out entirely: setup and initialization (constructors, options, config,
  wiring), getters, pure helpers the flows use, and test kits for implementers.
  A call with nothing worth saying beyond its name is left out too.

## Read before writing

Trace the real path; do not write from file names, doc comments, or a quick
skim.

1. List the entry points first. Go through the exported API of the target and
   of every part the caller constructs, sort each call by the rules above into
   a main flow, a variant, part of a group, maintenance, or left out, and plan
   the points from that. Read all of them, so nothing is missed, but write
   only the points the picture needs.
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

The answer must be scannable in under a minute. Aim for the whole answer to fit
on one screen (about 40 lines); more than that means too many items, too many
steps, or too much detail per step.

Open with a one- or two-line map: the families of flows and which one is the
main path ("Two kinds of content, text and media; every media search ends in the
same lookup"). Then one numbered list:

- One item per family, not per call. Calls that run the same steps and differ
  only in what they start from or what they return share an item: the shared
  steps are written once, and each call gets one line saying what differs
  ("SearchImage starts from a picture", "SearchText embeds a description
  instead"). Give a call its own item only when its steps really differ.
- Order: the main flow first, its variants in the same item, maintenance calls
  last, sharing one item when they do the same job on different parts.
- Each item is a label (the main call's name with its purpose in a few words in
  parentheses, "Index (store a text document)") and its steps lettered a., b.,
  c. under it.
- Two to five steps per flow, one action each. Variant lines and maintenance
  calls take one or two steps.
- Hard limit: one sentence and about 25 words per step. A step that needs more
  is either two steps or carries detail that does not belong.
- A skip-if-unchanged check is a clause in the first step ("…, unless the
  text is unchanged"), never a step of its own, and is not repeated per flow.
- Steps are what the caller can observe or depend on: what goes in, what is
  stored or looked up, what comes back. Internal mechanics (over-fetching,
  score cut-offs, tie-breaks, how the chunker packs text, the model's role
  labels) stay out unless the caller sets them.
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

1. Every main flow from the list in "Read before writing" has a point; the
   other calls are folded into a group, a variant line or a maintenance point,
   or left out on purpose. No point exists only to list setup or a single
   plain getter/setter.
2. No step is over one sentence or about 25 words, and the whole answer is
   about one screen. If not, merge calls into shared items and cut internal
   mechanics and default values.
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
