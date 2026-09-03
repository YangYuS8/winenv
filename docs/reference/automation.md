# Documentation and release automation

Winenv derives versions, release notes, assets, and the documentation site from commit history. Routine maintenance does not require editing version numbers, copying changelogs, or uploading site files.

## Release pipeline

After a push or merge to `main`:

1. the Release workflow validates profiles, PowerShell syntax, behavior, localization, and documentation;
2. semantic-release analyzes Conventional Commits;
3. a feature or fix updates `VERSION` and the root `CHANGELOG.md` automatically;
4. the workflow creates the version commit, Git tag, GitHub Release, ZIP, and SHA-256 asset;
5. a smoke test downloads and installs the newly published release;
6. after Release succeeds, the Pages workflow builds and deploys the latest `main` documentation.

Pages waits for Release so that the generated version and release notes appear in the same site deployment. Non-release commits such as `docs:` still pass release validation and update the documentation site.

## Commit types

```text
fix: repair installer path             # patch release
feat: add a capability                 # minor release
feat!: change an incompatible schema   # major release
docs: clarify profile behavior         # no release; deploy docs
chore: update maintenance config       # no release
```

Describe the change accurately and do not edit `VERSION` by hand. See the [contribution guide](/community/contributing) for the complete workflow.

## Changelog synchronization

The root `CHANGELOG.md` is the single source. `npm run docs:build` first runs `scripts/sync-docs-changelog.mjs`, which creates both English and Chinese documentation wrappers around the same release history before VitePress builds the site.

Generated `docs/changelog.md` and `docs/zh/changelog.md` files are ignored by Git to avoid checked-in copies that require manual synchronization.

## Local preview

Node.js 20 or newer is required:

```powershell
npm ci
npm run docs:dev
```

Before submitting documentation changes:

```powershell
npm run docs:build
npm run docs:preview
```

Content lives under `docs/`; site configuration and language routing live under `docs/.vitepress/`.

## Manually redeploy the site

Normally no action is required. If GitHub Pages has a transient failure, manually run the Pages workflow from the Actions tab. It still builds from the latest `main` and does not depend on locally generated files.
