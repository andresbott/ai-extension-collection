---
name: generate-readme
description: Create or update the README.md and DEVELOPMENT.md at the root of a repository. The README is a short, quick-glance page for users, with a header (name, one-sentence description, image), what the project lets you do, install or add-to-project steps with a happy-path example, and a one-line license footer. DEVELOPMENT.md holds everything about working on the code. Use when the user asks to write, generate, refresh, or restructure a README or DEVELOPMENT.md.
---

# Generate README

Write or update two files at the repository root, each for a different reader:

- **`README.md`** is a **quick glance** for people deciding whether to use the
  project. After a minute of reading they know what it is, what they can do
  with it, and how to start. It is not documentation: it never explains every
  package, option, or use case.
- **`DEVELOPMENT.md`** is for people who **work on** the project: the
  toolchain, running locally, tests, builds, and releases.

If the user added instructions or arguments, follow them over the defaults
below.

## 1. Research

Learn the project before writing. Read, and do not guess:

- **What it is and who uses it.** The manifest files (`go.mod`,
  `package.json`, `Cargo.toml`, `pyproject.toml`, `pom.xml`, …), the entry
  points, the existing README and docs, and the repository description
  (`gh repo view --json description,homepageUrl` when `gh` is available).
- **Its kind.** It decides the getting-started section (see step 2):
  - **Installable**: something people install and run, such as a server, CLI,
    desktop app, browser extension, editor or Claude Code plugin, or Docker
    image.
  - **Library**: something people add to their own project as a dependency.
  - **Both**: a library that also ships a CLI, for example.
  - **Neither**: a collection of configs, templates, or docs.
- **How it is delivered.** Release tooling (`.goreleaser*.yaml`, `Dockerfile`,
  `.github/workflows/*` that publish images, packages, or release assets), the
  published package name, and a docs site URL. Confirm that the install
  command works today. For a Go module, the module path in the go.mod of the
  version `@latest` resolves to must match the current one; after a rename
  without a new tag, it doesn't.
- **Images.** Logos, icons, and screenshots in the repo (`docs/`, `assets/`,
  `site/`, `screenshots/`, `.github/`) and any already shown in the README.
- **Developer workflow.** `Makefile` targets (`make help` if it exists),
  `package.json` scripts, toolchain versions (`go.mod`, `engines`,
  `.tool-versions`, `rust-toolchain.toml`), dev configs, CI checks, and the
  release process.
- **License.** `LICENSE*` files and the license field in the manifest.
- **Existing docs.** `docs/`, a docs site, `CONTRIBUTING.md`, and
  `docs/agents/`, so both files can link to them instead of repeating them.

## 2. README.md

### Budget

The README must be short:

- **About 60 lines** for an installable project, **about 120** for a library
  including its examples. Treat these as hard limits: if the draft is longer,
  cut it before writing it.
- **Every section is a short overview:** two or three sentences, or one short
  list, or one code block.
- **Examples show the happy path only:** the most common use, in the fewest
  lines that run. No error handling beyond what the language needs, no
  options, no variants, no edge cases.

Write the sections below, in this order, and leave out the ones that don't
apply.

### Header

1. **Name** as the title: `# Name`.
2. **One sentence** saying what it is and what it does, for someone who has
   never heard of it ("Aether is a self-hosted music server that streams your
   library over an OpenSubsonic-compatible API."). Add a second sentence only
   when it carries a fact a user picks the project for ("Single binary, no
   dependencies.").
3. **Something to look at.** One of these, in order of preference:
   - a screenshot or a short demo of the project in use,
   - a logo or icon,
   - for a library with nothing visual, a few badges that carry real
     information: package docs (pkg.go.dev, docs.rs) once the page exists,
     the latest release (GitHub releases, not bare tags), the CI status, and
     the license.

   Use only images that exist in the repo or are already published. Never
   invent a path or link a placeholder. If nothing suitable exists, leave it
   out and suggest one in the final report.

   With a logo, a centered HTML block in the style of
   [lightcraft](https://github.com/storytold/lightcraft) is fine: logo, name,
   tagline, then a screenshot. Otherwise use plain Markdown, as in
   [aether](https://github.com/andresbott/aether): title, sentence, image.
4. **Optional, one line each:** a status note (`> **Pre-release:** …`) when the
   project is not stable, and a link to the docs site when there is one.

### Features

What a user **can do** with the project: three to six bullets, one line each.
Each bullet is a task or outcome the user wants, written from their side, so
a reader can tell in seconds whether the project solves their problem.

- Start from user intent: "find…", "tag…", "stream…", "save…". Ask "why would
  someone reach for this?", not "what is in the repo?".
- No package names, type names, internal architecture, or implementation
  details. Name a technology only when users pick the project for it ("Runs
  the models in process: no server, no API key").
- One bullet per capability. Do not list every variant of the same
  capability.

Bad (an inventory of the code):

> - `search/` package with a `Searcher` type over the `Embedder` port
> - Providers: yzma (llama.cpp), onnx (SigLIP 2, DINOv2), phash
> - Vector stores: MemStore, sqlite-vec, pgvector

Good (what you can do with it):

> - Search documents by meaning, in several languages
> - Find similar images and videos, or near-duplicates without a model
> - Suggest tags for a text from the tags you already use
> - Run everything locally: no server and no API key

### Install / Quick start (installable projects)

The shortest path from nothing to the project running:

- One command for the easiest channel that really exists: a package manager,
  `docker run`, a download from the releases page, `go install`, or a
  marketplace or extension store.
- The one step that makes it useful ("Open <http://localhost:8075> and sign in
  as `admin`").
- One line linking to other channels or the full installation docs, if any.

### Add to your project (libraries)

- The command that adds the dependency (`go get <module>@latest`,
  `npm install <pkg>`, `cargo add <crate>`, `pip install <pkg>`), using the
  published name.
- System requirements, if any, in one or two lines ("Needs a C compiler and
  ffmpeg 5.1+ on PATH.").
- **One** happy-path example of the main use case. Add a second or third
  only for a capability from the Features list that is just as central, each
  under its own short `###` heading, as in
  [go-taglib](https://github.com/andresbott/go-taglib). Never one example per
  package or per option.
- One line linking to the API reference (pkg.go.dev, docs.rs, typedoc) or the
  docs for everything else.

Comment each step of an example with a short line saying what it does for the
user, so a reader can follow it without knowing the API: `// open the SQLite
database that stores the vectors`, `// load the embedding model (downloaded on
first use)`, `// index a document`, `// search by meaning, best match first`.
One comment per step (a step is one to three lines), not per line, and never a
comment that only repeats the code (`// call New`).

Every function, type, and option in an example must exist under that name and
signature. Compile them: for Go, put the snippets in a scratch module outside
the repo with a `replace` directive pointing at the repo and run `go vet`; for
other languages, use the equivalent (`tsc --noEmit`, `cargo check`, a Python
import).

A project that is both gets both sections, the most common use first. A
project that is neither gets a short **Usage** section instead: what to copy
or run, in a few lines.

### Development

Always exactly this:

```markdown
## Development

See [DEVELOPMENT.md](DEVELOPMENT.md).
```

### License footer

One sentence at the end, with no heading or under a `## License` heading:
"Licensed under the [MIT License](LICENSE)." Name the license from the
`LICENSE` file or the manifest. If there is no license, leave the footer out
and mention it in the final report; never assume one.

### Never in the README

- **Reference material:** a list or table of all packages, modules, or
  commands; architecture diagrams; every option or setting; per-feature
  deep dives; limitations, scores, or benchmarks in detail; upgrade and
  migration guides; FAQs; changelogs. Link to the docs that hold them.
- **Developer material:** building from source, running tests or linters,
  make targets, dev setup, the repository layout, releasing. All of that goes
  in `DEVELOPMENT.md`.
- **Filler:** a table of contents, a "this README covers…" intro, a
  "Contributing" section beyond the development link, contributor lists.

## 3. DEVELOPMENT.md

Title it `# Developing <Name>`. Use these sections, in this order, and leave
out the ones that don't apply:

1. **Overview.** Two or three sentences on where each part of the repository
   lives (`server/`, `webui/`, `cmd/`) and where the internal or agent docs
   are (`docs/agents/`, `CONTRIBUTING.md`). A file tree, if the project has
   one, may follow.
2. **Prerequisites.** Toolchains with their versions, taken from the
   manifests and CI, and system packages. Name a command that checks for them
   if the project has one.
3. **Common tasks.** The make targets or package scripts people use every day
   (help, test, lint, the full check, build), in one code block with a short
   comment per line. Say which one is the full check to run before opening a
   PR.
4. **Run locally.** For an application, the run command, the dev config it
   uses, ports, how the frontend and backend run separately or together, and
   how to get sample data. For a library, how to run its example, playground,
   or demo, if it has one.
5. **Build.** How to produce the binary, package, or image locally, and where
   the output goes. A library with nothing to build skips it.
6. **Release.** How a release happens (for example, a tag pushed with
   `make tag version=…` triggers CI), the checks to run first, and what CI
   publishes.

Every command must exist: a target in the `Makefile`, a script in
`package.json`, a file in the repo. Do not document a command you have not
found. Link to deeper docs (`docs/agents/releasing.md`, a sub-project's
README) instead of copying them.

## 4. Creating vs updating

- **Neither file exists:** write both from the research.
- **A README exists:** rewrite it to the budget and structure above. Keep its
  facts, images, badges, and the best example; do not keep its length.
  - Content for users that is too detailed for the README (package tables,
    per-feature explanations, limitations, upgrade guides, FAQs) is not
    deleted: if the project has a docs site or `docs/` for users, move it
    there; otherwise move it to `docs/<topic>.md` files (for example
    `docs/usage.md`, `docs/upgrading.md`). Link those pages from the README
    in one line, near the section they extend.
  - Developer content (build, tests, layout, make targets, evaluation tooling)
    moves to `DEVELOPMENT.md`. A demo that runs from a clone keeps one line in
    the README that links to its `DEVELOPMENT.md` section.
- **`DEVELOPMENT.md` exists:** check every command against the repo, fix
  what drifted, and add what is missing. Keep its structure if it works.
- If the repository uses another name for the developer file
  (`CONTRIBUTING.md`, `docs/development.md`) and holds the same content,
  ask the user whether to keep it or move it into `DEVELOPMENT.md` before
  changing anything.

## 5. Style

Write like a person explaining the project to a colleague in a minute, not
like generated documentation.

- Short sentences, plain words, active voice. Say each thing once.
- No marketing or filler: no "powerful", "seamless", "blazing fast",
  "comprehensive", "robust", "leverages", no "it's worth noting". A claim
  needs a number or it goes.
- Plain bullets. Do not open every bullet with a bold label.
- No paragraph that restates the heading or the previous section.
- Commands in fenced code blocks with a language tag (`sh`, `go`, …), so they
  can be copied as-is.
- Relative links for files in the repo (`[LICENSE](LICENSE)`), full URLs for
  everything else.

Before writing, reread the draft and cut every sentence a first-time reader
would not miss.

## 6. Report

Do not commit. When both files are written, report in a few lines:

- whether each file was created or updated, the README's length in lines, and
  any `docs/` pages created for moved content,
- the kind you decided the project is (installable, library, both, or
  neither),
- anything you could not verify or left out, such as a missing image, an
  unknown license, or an install command that does not work yet, with a
  suggestion for each.
