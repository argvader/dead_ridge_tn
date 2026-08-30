---
name: publish-site
description: >-
  Publish the Dead Ridge, TN site: build-check, commit, and push to main (which
  triggers the GitHub Pages deploy). Use when the user says "publish site", "publish
  the site", "deploy the site", or similar.
---

# Publish the site

Commit the current site content and push it live. Pushing to `main` triggers the
`deploy-docs` GitHub Action (`mkdocs gh-deploy --force`), publishing to the
`gh-pages` branch at <https://argvader.github.io/dead_ridge_tn/>.

## Steps

1. **Build check** — abort and report if this fails; never publish a broken build:

   ```bash
   mkdocs build --strict
   ```

2. **Stage the site sources** — the docs, config, assets, and any changed prompts or
   theme/hook files:

   ```bash
   git add docs mkdocs.yml docs/assets world hooks overrides
   git add SESSION_SUMMARIZER.md WORLD_PAGE.md requirements.txt 2>/dev/null || true
   ```

3. **Show what will be published** — run `git status --short` and briefly summarize
   the staged changes to the user before pushing.

4. **Commit** with a clear message — e.g. `publish site` or, when a specific session
   was just added, `publish session <DATE>`:

   ```bash
   git commit -m "publish site"
   ```

5. **Push** to publish (this deploys the live site):

   ```bash
   git push origin main
   ```

6. Report the commit and note the deploy runs automatically; the live site updates in
   a minute or two.

> Pushing publishes publicly. Invoking this skill is the go-ahead — but always print
> the staged changes (step 3) first so the user sees what is going live.
