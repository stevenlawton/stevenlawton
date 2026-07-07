# CV build + de-LLM pipeline — local mirror of .github/workflows/build-pages.yml
# Iterate locally:  make lint  →  fix words by hand  →  make normalize  →  make html  →  commit  →  push
# CI (on push to main) re-runs the build and commits the regenerated PDFs back to assets/.

.DEFAULT_GOAL := help

# --- tools (run via uvx/npx — no global installs needed) ---
SPLAT    := uvx splatllm
SLOPGATE := npx --yes slop-gate@latest
PANDOC   := pandoc
WK       := wkhtmltopdf

# Vale is fetched on demand into .tools/ (gitignored). Override the version with
#   make vale VALE_VERSION=x.y.z
VALE_VERSION ?= 3.9.5
VALE         := .tools/vale

SRCS := CV.md profile.md
OUT  := output

# SplatLLM in "normalize only" mode: remap fancy Unicode + strip invisible/watermark
# chars, but KEEP every piece of markdown (headings, bold, lists, links, ...) because
# pandoc renders it. Without these flags SplatLLM would gut the document.
SPLAT_KEEP := --keep-headings --keep-code-blocks --keep-inline-code \
              --keep-bold --keep-italics --keep-strikethrough \
              --keep-images --keep-links --keep-blockquotes \
              --keep-unordered-lists --keep-ordered-lists \
              --keep-horizontal-rules --keep-tables

# SplatLLM strips trailing whitespace, which would silently kill markdown hard-breaks
# (two trailing spaces). Pre-convert hard-breaks on NON-heading lines to a backslash
# break (which survives) so rendering is unchanged. Headings are skipped: trailing
# spaces there are inert, and a backslash would render a stray break.
define NORMALIZE
	perl -pe 's/ {2,}$$/\\/ unless /^\s*#/' $(1) | $(SPLAT) $(SPLAT_KEEP) 2>/dev/null
endef

.PHONY: help ready lint lint-all slop vale normalize check build html pdf preview all clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-11s\033[0m %s\n", $$1, $$2}'

ready: ## One-shot pre-commit: normalize → lint → render preview. Then commit & push.
	@$(MAKE) -s normalize
	@echo "── remaining word-level tells (fix by hand if you like) ──"
	@$(MAKE) -s slop
	@$(MAKE) -s html
	@echo ""
	@echo "✓ ready. Review output/index.html + the tells above, then: git commit && git push"
	@echo "  (CI rebuilds and commits the PDFs back to assets/)"

lint: slop ## Flag AI tells without changing anything (fast: slop-gate only)

lint-all: slop vale ## Run both linters (slop-gate + Vale)

slop: ## slop-gate: flag sentence/word-level AI tells (the primary de-LLM linter)
	@$(SLOPGATE) $(SRCS) || true

# Opt-in second opinion. Vale's AI ruleset targets STRUCTURAL prose tells (hedging,
# enumeration, narrative padding) — useful for prose-heavy text, light on a terse CV.
# Config + curated package set live in .vale.ini. Binary + styles are gitignored.
vale: $(VALE) ## Vale: AI-writing ruleset + prose packs (see .vale.ini)
	@$(VALE) sync >/dev/null 2>&1
	@$(VALE) $(SRCS) || true

$(VALE):
	@mkdir -p .tools
	@echo "fetching vale $(VALE_VERSION) into .tools/ ..."
	@curl -sL "https://github.com/errata-ai/vale/releases/download/v$(VALE_VERSION)/vale_$(VALE_VERSION)_Linux_64-bit.tar.gz" \
	  | tar xz -C .tools vale && chmod +x $(VALE)

check: ## Dry run: show what `normalize` WOULD change + slop tells (no writes)
	@for f in $(SRCS); do \
	  $(call NORMALIZE,$$f) | diff -u $$f - && echo "$$f: char-clean" || true; \
	done
	@$(SLOPGATE) $(SRCS) || true

normalize: ## Apply char-level fixes in place (SplatLLM, hard-breaks preserved)
	@for f in $(SRCS); do \
	  $(call NORMALIZE,$$f) > $$f.tmp && mv $$f.tmp $$f && echo "normalized $$f"; \
	done

build: html pdf ## Full local build (HTML + PDF into output/)

html: | $(OUT) ## Render HTML only (fast iteration, no PDF)
	$(PANDOC) CV.md --template=templates/template.html \
	  --metadata title="Steven Lawton - CV" -f markdown -t html5 -s -o $(OUT)/index.html
	$(PANDOC) CV.md --template=templates/template.cv.html.html \
	  --metadata title="Steven Lawton - CV" --lua-filter=templates/wrap-experience.lua \
	  -f markdown -t html5 -s -o $(OUT)/index.cv.html
	$(PANDOC) CV.md --template=templates/template.cv.html.html \
	  --metadata title="Steven Lawton - CV (Short)" \
	  --lua-filter=templates/abridged.lua --lua-filter=templates/wrap-experience.lua \
	  -M abridged_roles=3 -f markdown -t html5 -s -o $(OUT)/index.cv.short.html
	$(PANDOC) profile.md --template=templates/template.profile.html \
	  --metadata title="Steven Lawton – Profile" -f markdown -t html5 -s -o $(OUT)/profile.html
	@sed -i 's|<!-- PDF-LINK-HERE -->|<p><a href="/stevenlawton/Steven-Lawton-CV.pdf" download>📄 Download PDF version</a></p>|' $(OUT)/index.html

pdf: html ## Render PDFs (needs wkhtmltopdf)
	$(WK) --enable-local-file-access --print-media-type \
	  $(OUT)/index.cv.html $(OUT)/Steven-Lawton-CV.pdf
	$(WK) --enable-local-file-access --print-media-type \
	  $(OUT)/index.cv.short.html $(OUT)/Steven-Lawton-CV-Short.pdf
	$(WK) $(OUT)/profile.html $(OUT)/Steven-Lawton-Profile.pdf

preview: html ## Build HTML and open the CV in a browser
	@xdg-open $(OUT)/index.html >/dev/null 2>&1 || echo "open $(OUT)/index.html"

all: lint build ## Lint then build (does NOT mutate sources; run `normalize` explicitly)

$(OUT):
	@mkdir -p $(OUT)

clean: ## Remove generated HTML/PDF from output/
	rm -f $(OUT)/*.html $(OUT)/*.pdf
