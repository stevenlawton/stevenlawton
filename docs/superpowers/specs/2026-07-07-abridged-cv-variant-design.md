# Abridged CV variant + local normalize guarantee

**Date:** 2026-07-07
**Status:** Approved (design)

## Goal

Produce a second, abridged CV from the single `CV.md` source, alongside the existing
full CV, and guarantee character-normalisation (SplatLLM) runs on every local commit so
CI does not need to.

## Requirements

### Abridged CV content
The abridged version is a strict subset of the full CV:

- **Keep:** header block (from template), `## Summary`, `## Skills`, `## Experience`
  (trimmed), `## Why Me?`, `## Contact`.
- **Trim:** under `## Experience`, keep only the first **3** `### role` sub-sections
  (Experience is reverse-chronological, so this is the ~most recent 2 years). Configurable.
- **Drop:** the entire `## Open Source & Personal Projects` section, including its trailing
  Transferability footer and blockquote.

### Normalize guarantee
- SplatLLM normalize must run on `CV.md` / `profile.md` on **every local commit**.
- CI does **not** run normalize (no workflow change for normalize).

## Approach

**Single source of truth (`CV.md`) + a variant Lua filter.** No duplicated content, no
drift. Mirrors the existing `wrap-experience.lua` pattern.

## Components

### 1. `templates/abridged.lua` (new)
A pandoc Lua filter that transforms the document for the abridged build. Runs **before**
`wrap-experience.lua` in the filter chain.

Behaviour:
- Reads the number of Experience roles to keep from `doc.meta.abridged_roles`
  (default **3** when the metadata is absent).
- Walks top-level blocks:
  - At a level-2 `Header`: determine the section. If it is `Open Source & Personal
    Projects`, enter "dropping" mode (skip all blocks until the next level-2 header). All
    other level-2 sections are emitted; track whether we are inside `Experience`.
  - Inside a dropped section: skip every block.
  - Inside `Experience`, at a level-3 `Header`: increment a role counter; emit the role
    heading only while `count <= keep`, otherwise mark the role as skipped.
  - Inside `Experience`, in a skipped (excess) role: skip its content blocks.
  - Otherwise: emit the block unchanged.

Because `## Why Me?` and `## Contact` follow the Projects section, hitting their level-2
headers turns "dropping" off, so they are retained.

### 2. Outputs & naming
- Full CV: `Steven-Lawton-CV.pdf` — unchanged.
- Abridged CV: `Steven-Lawton-CV-Short.pdf`.
- Abridged print HTML intermediate: `output/index.cv.short.html`.
- Reuses the existing print template `templates/template.cv.html.html` (same CSS, so all
  page-break handling is inherited — no new template, no CSS changes).
- The landing page `output/index.html` gains a **second** download link for the short PDF
  next to the existing full-PDF link.

### 3. Local normalize guarantee
- `.githooks/pre-commit` (new, versioned): finds staged `CV.md` / `profile.md`
  (`git diff --cached --name-only --diff-filter=ACM`), runs `make -s normalize-staged`,
  which normalises those files in place and re-stages them.
- `Makefile` new target `normalize-staged`: reuses the existing `NORMALIZE` define
  (perl hard-break pre-conversion → `uvx splatllm` with all `--keep-*` flags), scoped to
  the staged source files only — it must not sweep up unrelated unstaged edits.
- `Makefile` new target `hooks`: `git config core.hooksPath .githooks` (one-time enable
  per clone). Run once during setup so the hook is live.

Caveat: a hook is bypassable with `git commit --no-verify` and requires `make hooks` to
have run on the clone. Acceptable for a single-machine workflow.

### 4. Makefile wiring (abridged build)
- Add abridged HTML + PDF targets producing `index.cv.short.html` and
  `Steven-Lawton-CV-Short.pdf` via:
  `pandoc CV.md --template=templates/template.cv.html.html --lua-filter=templates/abridged.lua --lua-filter=templates/wrap-experience.lua -M abridged_roles=3 ... -o output/index.cv.short.html`
  then `wkhtmltopdf --enable-local-file-access --print-media-type ...`.
- Fold abridged targets into `html`, `pdf`, and `build`.
- Local `normalize` / `ready` / `lint` flow unchanged.

### 5. Workflow wiring (`.github/workflows/build-pages.yml`)
- Add pandoc step for the abridged print HTML (mirrors the existing
  `index.cv.html` step, plus `abridged.lua` and `-M abridged_roles=3`).
- Add wkhtmltopdf step producing `output/Steven-Lawton-CV-Short.pdf`.
- Extend the landing-page download-link `sed` to also emit the short-PDF link.
- `commit-pdfs` job: also copy + `git add` + commit `assets/Steven-Lawton-CV-Short.pdf`.
- Extend trigger `paths:` to include the files the build now depends on:
  `templates/template.cv.html.html`, `templates/wrap-experience.lua`,
  `templates/abridged.lua`, and `profile.md`.
- No normalize step in CI (per the local-hook decision).

## Verification
1. `make hooks`, then a test commit touching `CV.md` shows the pre-commit hook normalising
   and re-staging it.
2. Local build of the abridged PDF; rasterise and confirm:
   - exactly 3 Experience roles present,
   - no `Open Source & Personal Projects` section (and no Transferability footer),
   - `Summary`, `Skills`, `Why Me?`, `Contact` all present,
   - no role split across a page boundary.
3. Full CV PDF is byte-for-behaviour unchanged (same content as before this work).

## Out of scope
- Rewriting/shortening the Summary specifically for the abridged version (it reuses the
  full Summary).
- Per-role include tagging (Approach B) — revisit only if a specific older role ever needs
  to appear in the short version.
- A separate web page for the abridged CV (only a PDF + a landing-page link).
