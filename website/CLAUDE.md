# website/CLAUDE.md

A Docusaurus 3 site that republishes the chapter READMEs (plus `CONVENTIONS.md`) as browsable docs,
deployed to GitHub Pages by `deploy-docs.yml`. **Never hand-edit files under `website/docs/`** — they
are generated. The source of truth is always a chapter's `README.md` (or `CONVENTIONS.md`); edit that,
then regenerate:

```bash
cd website
npm run sync     # scripts/sync-docs.sh -> node scripts/sync-docs.js: copies chapter READMEs into website/docs/NN-slug/
npm start         # local preview at http://localhost:3000
npm run build     # production build (also runs sync via `prebuild`)
```

`website/docs/` is gitignored — it's regenerated output, never committed. `sync` runs automatically
before `start`/`build` (npm `pre*` hooks) and again in CI before the Pages build, so don't trust a
locally-present `website/docs/` without re-running `sync` first.

A chapter can also carry a standalone `.html` asset (e.g. an animated diagram) alongside its
`README.md` — `scripts/sync-docs.js` copies any top-level `*.html` file in a chapter folder into
`website/static/diagrams/<route>/` (also gitignored, regenerated the same way as `docs/`) and
rewrites the README's relative `(file.html)` link to `/kubernetes-ai-infrastructure/diagrams/<route>/file.html`
so it's served live by the site. The chapter folder's copy of the `.html` file is the source of
truth and the only one committed to git.
