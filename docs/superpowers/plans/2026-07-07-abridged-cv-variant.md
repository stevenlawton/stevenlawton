# Abridged CV Variant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce an abridged `Steven-Lawton-CV-Short.pdf` from the single `CV.md` source (drop Personal Projects, keep the 3 most recent roles) and guarantee SplatLLM normalisation runs on every local commit.

**Architecture:** A single-source approach. A new pandoc Lua filter (`abridged.lua`) trims the document for the short build; it chains before the existing `wrap-experience.lua`. Both the Makefile and the CI workflow gain an abridged build path. Normalisation moves to a versioned git pre-commit hook that calls a new `make normalize-staged` target (reusing the existing recipe), so CI needs no normalize step.

**Tech Stack:** pandoc (Lua filters, `-t html5`), wkhtmltopdf, GNU Make, bash, GitHub Actions, SplatLLM via `uvx`.

## Global Constraints

- Single source of truth: only `CV.md` is authored; the abridged CV is derived, never hand-copied.
- Normalisation MUST use the existing `NORMALIZE` make define (perl hard-break pre-conversion piped into `uvx splatllm` with every `--keep-*` flag). Never call plain `splatllm` — it would strip markdown.
- The abridged build MUST reuse `templates/template.cv.html.html` (its print CSS) — no new template, no CSS changes.
- Default number of Experience roles in the abridged CV: **3**, passed as `-M abridged_roles=3`; the filter defaults to 3 when the metadata is absent.
- The full CV output (`Steven-Lawton-CV.pdf`) and its content MUST remain unchanged.
- Abridged PDF filename: exactly `Steven-Lawton-CV-Short.pdf`.
- Commit after each task.

---

### Task 1: `abridged.lua` variant filter

**Files:**
- Create: `templates/abridged.lua`
- Test: manual shell assertions (no test framework in this repo)

**Interfaces:**
- Consumes: `CV.md` block structure — `## Summary`, `## Skills`, `## Experience` with `### role` sub-headings, `## Open Source & Personal Projects`, `## Why Me?`, `## Contact`. Reads `-M abridged_roles=<int>`.
- Produces: a filtered pandoc document with Personal Projects removed and Experience trimmed to the first N roles. Chains BEFORE `templates/wrap-experience.lua` (which then wraps the surviving roles in `<section class="experience">`).

- [ ] **Step 1: Write the failing test**

Create `/tmp/abridged-test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /home/steve/repos/stevenlawton
OUT=/tmp/short-test.html
pandoc CV.md \
  --template=templates/template.cv.html.html \
  --metadata title="Steven Lawton - CV (Short)" \
  --lua-filter=templates/abridged.lua \
  --lua-filter=templates/wrap-experience.lua \
  -M abridged_roles=3 -f markdown -t html5 -s -o "$OUT"

roles=$(grep -o 'class="experience"' "$OUT" | wc -l | tr -d ' ')
projects=$(grep -o 'class="project"' "$OUT" | wc -l | tr -d ' ')
oss=$(grep -c 'Open Source' "$OUT" || true)
have() { grep -q "id=\"$1\"" "$OUT" && echo "yes" || echo "NO"; }

echo "roles=$roles (want 3)"
echo "project-sections=$projects (want 0)"
echo "open-source-text=$oss (want 0)"
echo "summary=$(have summary) skills=$(have skills) why-me=$(have why-me) contact=$(have contact)"

[ "$roles" = "3" ] || { echo "FAIL: expected 3 roles"; exit 1; }
[ "$projects" = "0" ] || { echo "FAIL: expected 0 project sections"; exit 1; }
[ "$oss" = "0" ] || { echo "FAIL: Open Source section leaked in"; exit 1; }
for id in summary skills why-me contact; do
  grep -q "id=\"$id\"" "$OUT" || { echo "FAIL: missing #$id"; exit 1; }
done
echo "PASS"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash /tmp/abridged-test.sh`
Expected: FAIL — pandoc errors with `could not find filter templates/abridged.lua` (filter does not exist yet).

- [ ] **Step 3: Write the filter**

Create `templates/abridged.lua`:

```lua
-- Abridged CV variant filter. Chains BEFORE wrap-experience.lua.
-- Derives the short CV from the single CV.md source by:
--   * dropping the entire "Open Source & Personal Projects" section
--   * keeping only the first N roles under "Experience"
--     (N from -M abridged_roles, default 3)
-- Every other block passes through unchanged, so Summary, Skills, the
-- trimmed Experience, Why Me? and Contact are all retained.
local DROP_SECTIONS = { ["Open Source & Personal Projects"] = true }

return {
  {
    Pandoc = function(doc)
      local keep = 3
      if doc.meta.abridged_roles then
        keep = tonumber(pandoc.utils.stringify(doc.meta.abridged_roles)) or keep
      end

      local out = {}
      local dropping = false       -- inside a dropped level-2 section
      local in_experience = false  -- inside the Experience section
      local role_count = 0
      local skip_role = false      -- dropping an excess role's content

      for _, el in ipairs(doc.blocks) do
        if el.t == "Header" and el.level == 2 then
          local title = pandoc.utils.stringify(el.content)
          dropping = DROP_SECTIONS[title] == true
          in_experience = (title == "Experience")
          role_count = 0
          skip_role = false
          if not dropping then table.insert(out, el) end
        elseif dropping then
          -- skip everything until the next level-2 header
        elseif in_experience and el.t == "Header" and el.level == 3 then
          role_count = role_count + 1
          skip_role = role_count > keep
          if not skip_role then table.insert(out, el) end
        elseif in_experience and skip_role then
          -- skip content blocks of excess roles
        else
          table.insert(out, el)
        end
      end

      return pandoc.Pandoc(out, doc.meta)
    end
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash /tmp/abridged-test.sh`
Expected: `PASS` with `roles=3`, `project-sections=0`, `open-source-text=0`, and all four sections `yes`.

- [ ] **Step 5: Commit**

```bash
git add templates/abridged.lua
git commit -m "Add abridged.lua filter for the short CV variant"
```

---

### Task 2: Makefile abridged build targets

**Files:**
- Modify: `Makefile` (the `html` and `pdf` targets)

**Interfaces:**
- Consumes: `templates/abridged.lua` (Task 1), `templates/template.cv.html.html`, `templates/wrap-experience.lua`.
- Produces: `output/index.cv.short.html` and `output/Steven-Lawton-CV-Short.pdf` on `make build`.

- [ ] **Step 1: Add the abridged HTML render to the `html` target**

In `Makefile`, the `html` target currently renders `index.html`, `index.cv.html`, and `profile.html`. Add a fourth pandoc invocation immediately after the `index.cv.html` one (before the `profile.md` line):

```make
	$(PANDOC) CV.md --template=templates/template.cv.html.html \
	  --metadata title="Steven Lawton - CV (Short)" \
	  --lua-filter=templates/abridged.lua --lua-filter=templates/wrap-experience.lua \
	  -M abridged_roles=3 -f markdown -t html5 -s -o $(OUT)/index.cv.short.html
```

- [ ] **Step 2: Add the abridged PDF render to the `pdf` target**

In the `pdf` target, add a second wkhtmltopdf line after the existing `index.cv.html → Steven-Lawton-CV.pdf` line:

```make
	$(WK) --enable-local-file-access --print-media-type \
	  $(OUT)/index.cv.short.html $(OUT)/Steven-Lawton-CV-Short.pdf
```

- [ ] **Step 3: Build and verify outputs exist**

Run:
```bash
cd /home/steve/repos/stevenlawton && make build
ls -1 output/Steven-Lawton-CV.pdf output/Steven-Lawton-CV-Short.pdf output/index.cv.short.html
```
Expected: all three paths listed, no error.

- [ ] **Step 4: Verify the short PDF content by rasterising**

Run:
```bash
SP=/tmp/short-verify
rm -rf "$SP" && mkdir -p "$SP"
pdftoppm -png -r 80 output/Steven-Lawton-CV-Short.pdf "$SP/p"
echo "pages: $(pdfinfo output/Steven-Lawton-CV-Short.pdf | awk '/Pages/{print $2}')"
ls "$SP"/*.png
```
Expected: a small page count (1–3). Open the PNGs and confirm: Summary, Skills, exactly 3 Experience roles, Why Me?, Contact; NO "Open Source & Personal Projects" section.

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "Add abridged CV build targets to Makefile"
```

---

### Task 3: Second download link on the landing page

**Files:**
- Modify: `Makefile` (the `sed` line at the end of the `html` target)

**Interfaces:**
- Consumes: the `<!-- PDF-LINK-HERE -->` marker already present in `templates/template.html`.
- Produces: `output/index.html` containing download links for BOTH the full and short PDFs.

- [ ] **Step 1: Replace the single-link `sed` with a two-link version**

The current last line of the `html` target is:

```make
	@sed -i 's|<!-- PDF-LINK-HERE -->|<p><a href="/stevenlawton/Steven-Lawton-CV.pdf" download>📄 Download PDF version</a></p>|' $(OUT)/index.html
```

Replace it with (note the delimiter changes from `|` to `#` so the `·` separator and link text are unambiguous):

```make
	@sed -i 's#<!-- PDF-LINK-HERE -->#<p><a href="/stevenlawton/Steven-Lawton-CV.pdf" download>📄 Full CV (PDF)</a> · <a href="/stevenlawton/Steven-Lawton-CV-Short.pdf" download>📄 Short CV (PDF)</a></p>#' $(OUT)/index.html
```

- [ ] **Step 2: Build and verify both links present**

Run:
```bash
cd /home/steve/repos/stevenlawton && make html
grep -o 'Steven-Lawton-CV\(-Short\)\?\.pdf' output/index.html | sort -u
```
Expected: two lines — `Steven-Lawton-CV-Short.pdf` and `Steven-Lawton-CV.pdf`. Confirm the `<!-- PDF-LINK-HERE -->` marker is gone: `grep -c 'PDF-LINK-HERE' output/index.html` prints `0`.

- [ ] **Step 3: Commit**

```bash
git add Makefile
git commit -m "Add short-CV download link to the landing page"
```

---

### Task 4: Local normalize guarantee (make targets + pre-commit hook)

**Files:**
- Modify: `Makefile` (add `normalize-staged` and `hooks` targets; add both to `.PHONY`)
- Create: `.githooks/pre-commit`

**Interfaces:**
- Consumes: the existing `NORMALIZE` make define and `SPLAT`/`SPLAT_KEEP` variables.
- Produces: `make normalize-staged` (normalises + re-stages staged `CV.md`/`profile.md`), `make hooks` (enables `core.hooksPath`), and a hook that calls `make -s normalize-staged`.

- [ ] **Step 1: Add the two Makefile targets**

Add these targets to `Makefile` (place near the existing `normalize` target). The recipe reuses the `NORMALIZE` define so there is one source of truth for the recipe:

```make
normalize-staged: ## Normalize + re-stage any STAGED CV/profile sources (used by the pre-commit hook)
	@files=$$(git diff --cached --name-only --diff-filter=ACM | grep -E '^(CV|profile)\.md$$' || true); \
	for f in $$files; do \
	  $(call NORMALIZE,$$f) > $$f.tmp && mv $$f.tmp $$f && git add "$$f" && echo "normalized+staged $$f"; \
	done

hooks: ## Enable the repo's git hooks (run once per clone)
	@git config core.hooksPath .githooks && echo "hooks enabled (core.hooksPath=.githooks)"
```

Add `normalize-staged` and `hooks` to the `.PHONY` line (currently:
`.PHONY: help ready lint lint-all slop vale normalize check build html pdf preview all clean`) so it reads:
`.PHONY: help ready lint lint-all slop vale normalize normalize-staged hooks check build html pdf preview all clean`

- [ ] **Step 2: Create the pre-commit hook**

Create `.githooks/pre-commit`:

```bash
#!/usr/bin/env bash
# Guarantee SplatLLM normalisation runs on every commit touching the CV sources.
# Normalises staged CV.md / profile.md in place and re-stages them, so the
# committed content is always normalised. Reuses `make normalize-staged`.
set -euo pipefail
exec make -s normalize-staged
```

- [ ] **Step 3: Make the hook executable**

Run:
```bash
cd /home/steve/repos/stevenlawton && chmod +x .githooks/pre-commit
```

- [ ] **Step 4: Enable hooks and functionally test `normalize-staged`**

Run (this stages a temporary curly-quote edit, confirms it gets normalised, then discards it):
```bash
cd /home/steve/repos/stevenlawton
make hooks
git config core.hooksPath   # expect: .githooks

# functional test: inject a curly apostrophe, stage, normalize-staged, verify
cp CV.md /tmp/CV.md.bak
printf '\nProbe: don\xe2\x80\x99t ship this.\n' >> CV.md
git add CV.md
make -s normalize-staged
grep -c $'\xe2\x80\x99' CV.md   # expect: 0 (curly apostrophe remapped to straight)
git grep --cached -c "Probe: don't ship this." -- CV.md   # expect: 1 (straight quote, staged)

# cleanup: restore original CV.md and unstage
cp /tmp/CV.md.bak CV.md && git add CV.md && rm /tmp/CV.md.bak
```
Expected: `core.hooksPath` prints `.githooks`; curly-apostrophe count `0`; staged straight-quote count `1`; working tree restored.

- [ ] **Step 5: Commit**

```bash
git add Makefile .githooks/pre-commit
git commit -m "Add pre-commit hook guaranteeing local SplatLLM normalize"
```

---

### Task 5: CI workflow — abridged build, commit, and trigger paths

**Files:**
- Modify: `.github/workflows/build-pages.yml`

**Interfaces:**
- Consumes: `templates/abridged.lua`, `templates/wrap-experience.lua`, `templates/template.cv.html.html`.
- Produces: `output/Steven-Lawton-CV-Short.pdf` built and deployed; `assets/Steven-Lawton-CV-Short.pdf` committed back; the landing page carries both download links.

- [ ] **Step 1: Add the abridged HTML pandoc step**

In the `build` job, immediately after the `Convert Markdown to HTML - CV(pdf version)` step (which outputs `output/index.cv.html`), add:

```yaml
      - name: Convert Markdown to HTML - CV(short)
        run: |
          pandoc CV.md \
            --template=templates/template.cv.html.html \
            --metadata title="Steven Lawton - CV (Short)" \
            --lua-filter=templates/abridged.lua \
            --lua-filter=templates/wrap-experience.lua \
            -M abridged_roles=3 \
            -f markdown -t html5 -s -o output/index.cv.short.html
```

- [ ] **Step 2: Add the abridged PDF wkhtmltopdf step**

Immediately after the `Convert HTML to PDF - CV` step, add:

```yaml
      - name: Convert HTML to PDF - CV(short)
        run: |
          wkhtmltopdf \
          --enable-local-file-access \
          --print-media-type \
          output/index.cv.short.html \
          output/Steven-Lawton-CV-Short.pdf
```

- [ ] **Step 3: Update the landing-page link step to emit both links**

Replace the body of the `Insert download link at marker` step with (delimiter `#`, matching Task 3):

```yaml
      - name: Insert download link at marker
        run: |
          sed -i 's#<!-- PDF-LINK-HERE -->#<p><a href="/stevenlawton/Steven-Lawton-CV.pdf" download>📄 Full CV (PDF)</a> · <a href="/stevenlawton/Steven-Lawton-CV-Short.pdf" download>📄 Short CV (PDF)</a></p>#' output/index.html
```

- [ ] **Step 4: Commit the short PDF in the `commit-pdfs` job**

In the `commit-pdfs` job, update the `Copy PDF to assets/` step to also copy the short PDF:

```yaml
      - name: Copy PDF to assets/
        run: |
          mkdir -p assets
          cp output/Steven-Lawton-CV.pdf assets/Steven-Lawton-CV.pdf
          cp output/Steven-Lawton-CV-Short.pdf assets/Steven-Lawton-CV-Short.pdf
          cp output/Steven-Lawton-Profile.pdf assets/Steven-Lawton-Profile.pdf
```

And update the `Commit PDF` step to stage the short PDF too — add this line alongside the existing `git add -f` lines (before the `if ! git diff --cached --quiet` check):

```yaml
          git add -f assets/Steven-Lawton-CV-Short.pdf
```

- [ ] **Step 5: Widen the trigger `paths:`**

Replace the `paths:` block under `on: push:` with:

```yaml
    paths:
      - CV.md
      - profile.md
      - .github/workflows/build-pages.yml
      - templates/template.html
      - templates/template.cv.html.html
      - templates/wrap-experience.lua
      - templates/abridged.lua
```

- [ ] **Step 6: Validate YAML and command parity**

Run:
```bash
cd /home/steve/repos/stevenlawton
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-pages.yml')); print('yaml ok')"
```
Expected: `yaml ok`. (The pandoc + wkhtmltopdf commands are identical to the Makefile ones already verified in Tasks 2–3, so no further local run is needed; the full CI run happens on push.)

- [ ] **Step 7: Commit**

```bash
git add .github/workflows/build-pages.yml
git commit -m "CI: build, commit, and link the abridged CV PDF"
```

---

## Post-implementation

- Open a PR from `cv-abridged-variant` to `main` (or fast-forward per the user's preference). On merge to `main`, the workflow builds and commits `assets/Steven-Lawton-CV-Short.pdf` and deploys both PDFs to Pages.
- After merge, verify the live short PDF at
  `https://stevenlawton.github.io/stevenlawton/Steven-Lawton-CV-Short.pdf`.
