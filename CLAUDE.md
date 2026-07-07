# stevenlawton — CV & Profile

GitHub profile repo. Source of truth is Markdown; pandoc renders HTML + PDF, GitHub
Actions deploys to Pages and commits the regenerated PDFs back.

## Sources

- `CV.md` — full CV (rendered to web HTML, print HTML, and PDF)
- `profile.md` — short profile summary
- `README.md` — the GitHub profile landing page
- `templates/` — pandoc templates + `wrap-experience.lua` filter
- `output/` — generated HTML/PDF (build artifacts)
- `assets/` — PDFs committed back by CI

## Build pipeline

`.github/workflows/build-pages.yml` runs on push to `main` (when `CV.md`, the workflow,
or `templates/template.html` change): pandoc → HTML, wkhtmltopdf → PDF, deploy to the
`gh-pages` branch, and a `commit-pdfs` job commits the PDFs into `assets/`.

The `Makefile` mirrors this locally so you can iterate before pushing. Run `make help`.

## De-LLM tooling

The CV is AI-assisted, so two cleanup layers strip the machine-writing "tells". Both run
through `uvx`/`npx` — nothing is installed globally.

### Character level — `make normalize` (SplatLLM)
Remaps fancy Unicode (em/en-dash → `-`, curly quotes → straight) and removes invisible /
watermark characters. **Deterministic and idempotent — safe to commit.**

- Runs with every `--keep-*` flag so it ONLY normalizes characters and never strips
  markdown. Plain `splatllm` (defaults) would delete bold/links/inline-code — do not use.
- SplatLLM strips trailing whitespace, which would kill markdown hard-breaks (two trailing
  spaces, used in the Skills section). The Makefile pre-converts hard-breaks on non-heading
  lines to backslash breaks so the rendered HTML is unchanged. Verified: same 7 `<br>`,
  identical HTML structure (only heading anchor-id slugs shift, which nothing links to).

### Sentence / word level — `make lint` (slop-gate)
Flags AI-favoured vocabulary and phrasing (`robust`, `seamless`, `streamline`, `harness`,
`crucial`, contrastive "not just X, but Y", em-dash, ...). **Flags only — never rewrites.**
Word-level tells need human judgement; fix them by hand, then re-run. Structural tells
(rule-of-three, uniform rhythm) aren't caught by any linter — they need a human/LLM eye.

slop-gate is the primary de-LLM linter — its AI-vocabulary wordlist is the right lens for
this CV (the tells here are lexical: `robust`, `seamless`, `streamline`, ...).

### Optional second opinion — `make vale` (Vale, opt-in)
`.vale.ini` runs the **signs-of-ai-writing** ruleset (structural tells: hedging,
enumeration, narrative padding) plus `write-good` + `proselint`. The binary is fetched into
`.tools/` and styles sync into `.vale/styles` (both gitignored). Findings so far: Vale's AI
rules barely fire on this CV because it's terse bullet-points, not flowing prose — so Vale
is a supplement, not a replacement for slop-gate. `Microsoft`/`alex`/`Readability` are synced
but off by default (Microsoft alone = 270+ house-style nags that bury the AI signal); enable
them by editing `BasedOnStyles` in `.vale.ini`. `make lint-all` runs both linters.

## Typical loop

```
edit CV.md
make ready       # normalize chars → list remaining word tells → render preview
                 # (optionally hand-fix the flagged words, re-run make ready)
git commit && git push   # CI rebuilds + commits the PDFs back to assets/
```

`make ready` is the one-shot pre-commit command: it runs `normalize` (mutates the sources —
that's intended, commit it), then `slop` (word tells are advisory, fix by hand), then `html`.
Because normalize runs first, the slop-gate output is just the lexical tells (em-dash noise
already gone).

Individual targets if you want finer control: `make lint` (slop-gate only), `make lint-all`
(+ Vale), `make normalize`, `make html` / `make build`, `make check` (no-write dry run).
