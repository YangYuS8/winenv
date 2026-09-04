---
title: "Documentation and release automation"
description: "Documentation and release automation for Winenv, the Windows 11 software management layer."
sidebar:
  order: 4
---

<span id="documentation-and-release-automation"></span>

Winenv derives versions, release notes, assets, and the documentation site from commit history. Routine maintenance does not require editing version numbers, copying changelogs, or uploading site files.

## Release pipeline

After a push or merge to `main`:

1. the Release workflow validates profiles, PowerShell syntax, behavior, localization, and documentation;
2. semantic-release analyzes Conventional Commits;
3. a feature or fix updates `VERSION` and the root `CHANGELOG.md` automatically;
4. the workflow creates the version commit, Git tag, GitHub Release, ZIP, and SHA-256 asset;
5. a smoke test downloads and installs the newly published release;
6. Release records its final commit SHA, including any generated release commit; after it succeeds, Pages retrieves that record and builds exactly that revision.

Pages waits for Release so that the generated version and release notes appear in the same site deployment. It does not fetch a newer, unrelated `main` commit while deploying an earlier run. Non-release commits such as `docs:` still pass documentation validation and update the site, but skip native runtime tests when only recognized documentation paths changed. Unknown paths and workflow changes keep the full runtime checks.

## Commit types

```text
fix: repair installer path             # patch release
feat: add a capability                 # minor release
feat!: change an incompatible schema   # major release
docs: clarify profile behavior         # no release; deploy docs
chore: update maintenance config       # no release
```

Describe the change accurately and do not edit `VERSION` by hand. See the [contribution guide](/winenv/community/contributing/) for the complete workflow.

## Changelog synchronization

The root `CHANGELOG.md` is the single source. `pnpm docs:build` first runs `scripts/sync-docs-changelog.mjs`, which creates both English and Chinese documentation wrappers around the same release history before Astro Starlight builds the site.

Generated `docs/src/content/docs/changelog.md` and `docs/src/content/docs/zh/changelog.md` files are ignored by Git to avoid checked-in copies that require manual synchronization.

## Local preview

Use the Node.js version in `.node-version` (or a compatible newer version) and pnpm pinned by `packageManager`. The cross-platform [development setup](https://github.com/YangYuS8/winenv/blob/main/CONTRIBUTING.md#development-setup) covers bootstrapping:

```powershell
pnpm install --frozen-lockfile
pnpm docs:dev
```

Before submitting documentation changes:

```powershell
pnpm docs:build
pnpm docs:preview
```

Content lives under `docs/src/content/docs/`. Site configuration is `docs/astro.config.mjs`; the small browser preference script is `docs/public/locale.js`. Starlight supplies navigation, translated UI, Pagefind search, and the default layout. See [documentation maintenance](/winenv/community/documentation/) for content and browser checks.

## Manually redeploy the site

Normally no action is required. If GitHub Pages has a transient failure, rerun it while the Release source artifact is available (retained for seven days), or manually dispatch Pages on `main`. A manual dispatch builds the exact selected commit at dispatch time, not a moving branch tip, and does not depend on locally generated files.
