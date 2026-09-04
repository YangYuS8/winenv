---
title: "Contributing"
description: "Contributing for Winenv, the Windows 11 software management layer."
sidebar:
  order: 1
---

<span id="contributing"></span>

Winenv welcomes code, tests, documentation, translations, issue triage, and carefully designed profile examples. The full repository policy lives in [`CONTRIBUTING.md`](https://github.com/YangYuS8/winenv/blob/main/CONTRIBUTING.md).

## Before contributing

1. Search existing issues and documentation.
2. Use the matching issue form for a bug, feature, documentation problem, or question.
3. Keep security vulnerabilities private through [GitHub's advisory form](https://github.com/YangYuS8/winenv/security/advisories/new).
4. For a material design change, agree on the user problem and boundaries before investing in implementation.

## Local validation

Documentation-only contributions work on Windows, macOS, and Linux. Install the toolchain pinned in `.node-version` and `package.json` using the [repository setup guide](https://github.com/YangYuS8/winenv/blob/main/CONTRIBUTING.md#development-setup), then run:

```powershell
pnpm install --frozen-lockfile
pnpm test:docs
pnpm docs:build
```

Runtime changes additionally need the PowerShell checks described in the repository guide. Documentation changes do not require installing Winenv or preparing a Windows PC. See [Maintaining documentation](/winenv/community/documentation/) for link, translation, and browser checks.

Architecture and provider changes must follow [RFC 0001](/winenv/reference/architecture/). Keep `win.ps1` as a thin compatibility entry point and place implementation functions in the matching internal module.

## Pull request expectations

- One coherent problem per pull request
- Tests for changed behavior
- English and Simplified Chinese updated together for user-facing changes
- Explicit security, compatibility, and migration implications
- Conventional Commit title
- No personal profiles, credentials, downloaded installers, generated site output, manual `VERSION`, or manual `CHANGELOG.md` changes

Reviews evaluate correctness, user experience, trust boundaries, backward compatibility, maintenance cost, tests, and translation completeness—not merely whether the code runs.

## Project policies

- [Code of Conduct](https://github.com/YangYuS8/winenv/blob/main/CODE_OF_CONDUCT.md)
- [Security policy](https://github.com/YangYuS8/winenv/blob/main/SECURITY.md)
- [Support policy](https://github.com/YangYuS8/winenv/blob/main/SUPPORT.md)
- [Governance](/winenv/community/governance/)
- [Translation guide](/winenv/community/i18n/)
