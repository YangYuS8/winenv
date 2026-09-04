# Contributing to Winenv

[简体中文](./CONTRIBUTING.zh-CN.md)

Thank you for helping make Windows software management more predictable. This guide keeps changes reviewable, secure, and maintainable by a small community.

Coding agents must also follow [AGENTS.md](./AGENTS.md), including its requirement to raise material requirement or design conflicts before implementation and obtain an informed decision from the requester.

## Before opening an issue

- Search existing issues and the [documentation](https://yangyus8.top/winenv/).
- Use the structured issue form that matches the request.
- Report security vulnerabilities privately according to [SECURITY.md](./SECURITY.md).
- Include the Winenv version (`win ver`), Windows build, PowerShell version, exact command, expected result, actual result, and sanitized output for bugs.

Support questions are welcome, but a minimal reproducible example is much easier to answer than a screenshot alone.

## Project scope

Winenv coordinates WinGet, Scoop, and mise on Windows 11. Changes should preserve these boundaries:

- package discovery comes from live manager catalogs, not a manually curated universal index;
- package managers remain responsible for installation, updates, removal, pins, and holds;
- the runtime profile contains only capabilities required by Winenv itself;
- user and community profiles remain independent, composable, and non-destructive;
- trust decisions such as third-party repositories or unverifiable installers stay visible and explicit;
- existing installations are reused or adopted without pretending Winenv originally installed them.

Proposals outside these boundaries should begin as a feature request with a concrete user problem.

## Architecture

Read [RFC 0001](https://yangyus8.top/winenv/reference/architecture) before changing command routing, profile semantics, or a package manager. `win.ps1` is a thin compatibility entry point; implementation functions belong in the matching file under `src/`. Internal modules are not a public API and must not perform user actions merely because they were loaded.

Provider changes must preserve the validated registry contract. A new provider requires an issue covering its machine-level responsibility, ownership model, unavailable behavior, privileges, trust, rollback, tests, and maintenance cost. Do not introduce a provider only to duplicate a project dependency manager or expose third-party code loading.

## Development setup

Documentation-only contributions work on Windows, macOS, and Linux. Use the Node.js version recorded in `.node-version` (or a compatible newer version) and the pnpm version pinned in `package.json`. These are contributor tools, not Winenv runtime prerequisites. Fork the repository and create a focused branch:

```powershell
git clone https://github.com/<your-account>/winenv.git
cd winenv
npm install --global pnpm@11.25.0
pnpm install --frozen-lockfile
pnpm docs:dev
```

Before opening a documentation pull request, run:

```sh
pnpm test:docs
pnpm docs:build
```

For navigation, styling, or language-switching changes, also run the browser checks:

```sh
pnpm exec playwright install chromium
pnpm docs:test
```

PowerShell behavior changes additionally need Windows 11 and PowerShell 7:

```powershell
pwsh -NoProfile -File ./scripts/test.ps1
powershell.exe -NoProfile -File ./scripts/test-windows-powershell.ps1
pnpm docs:build
```

CI runs documentation and browser checks on Linux, and runtime checks on Windows when relevant files change. A documentation build validates metadata, JSON examples, locale pairs, local links, assets, and published URL/anchor compatibility. Translation-change checks remind contributors to review the Chinese counterpart; they cannot judge translation accuracy. Pure translation corrections do not require rewriting English.

Keep policy text canonical in the root files. Site community pages are introductions with links, not independently maintained copies of the full policies. The [documentation maintenance guide](https://yangyus8.top/winenv/community/documentation/) explains content structure and checks.

## Make a focused change

- Keep a pull request limited to one coherent problem.
- Preserve unrelated user and repository changes.
- Add or update tests for behavior changes and regressions.
- Keep internal functions in one responsibility module and update architecture tests when module boundaries change.
- Keep commands short for routine use while retaining compatible long forms when practical.
- Do not silently elevate privileges, weaken Windows security settings, or broaden a trust decision.
- Do not commit personal profiles, credentials, downloaded installers, generated documentation output, `VERSION`, or manual edits to `CHANGELOG.md`.

## English and Simplified Chinese

English is canonical for source strings, repository policy, and the documentation root. Simplified Chinese is a supported product language, not a best-effort appendix.

For user-facing changes:

1. write the English source message or page first;
2. update `locales/zh-CN.json` for CLI output;
3. update the matching page under `docs/src/content/docs/zh/`;
4. preserve command names, parameters, package IDs, paths, and code samples unless localization genuinely requires a change;
5. run localization and documentation checks.

Repository policy translations use a `.zh-CN.md` suffix. See the [translation guide](https://yangyus8.top/winenv/community/i18n) for terminology and review rules.

## Commits and releases

Use Conventional Commits:

```text
feat: add automatic locale selection
fix: preserve profile language during migration
docs: explain third-party bucket trust
test: cover localized table output
chore: refresh development metadata
```

Use `feat!:` or a `BREAKING CHANGE:` footer only for an intentionally incompatible change. Squash exploratory commits before merge when it improves the history.

The `main` branch is released automatically. semantic-release determines the next version, generates the changelog and tag, publishes checksummed assets, runs an installation smoke test, and then deploys GitHub Pages. Contributors should not create release commits or tags.

## Pull request checklist

- Explain the user problem and the chosen behavior.
- Link related issues.
- Describe security, compatibility, migration, and rollback implications where relevant.
- Include tests and bilingual user-facing content.
- Confirm the local checks pass.
- Be ready to revise the change during review.

Submitting a contribution means you agree to license it under the repository's [MIT License](./LICENSE) and follow the [Code of Conduct](./CODE_OF_CONDUCT.md).
