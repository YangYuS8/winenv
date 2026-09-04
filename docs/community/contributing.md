# Contributing

Winenv welcomes code, tests, documentation, translations, issue triage, and carefully designed profile examples. The full repository policy lives in [`CONTRIBUTING.md`](https://github.com/YangYuS8/winenv/blob/main/CONTRIBUTING.md).

## Before contributing

1. Search existing issues and documentation.
2. Use the matching issue form for a bug, feature, documentation problem, or question.
3. Keep security vulnerabilities private through [GitHub's advisory form](https://github.com/YangYuS8/winenv/security/advisories/new).
4. For a material design change, agree on the user problem and boundaries before investing in implementation.

## Local validation

Use Windows 11, PowerShell 7, and Node.js 20 or newer:

```powershell
npm ci
pwsh -NoProfile -File ./scripts/test.ps1
powershell.exe -NoProfile -File ./scripts/test-windows-powershell.ps1
npm run docs:build
```

The tests cover profile composition, manager routing, existing-PC adoption, installer trust rules, localization, and compatibility with Windows PowerShell. The production docs build validates both locales.

Architecture and provider changes must follow [RFC 0001](/reference/architecture). Keep `win.ps1` as a thin compatibility entry point and place implementation functions in the matching internal module.

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
- [Governance](./governance)
- [Translation guide](./i18n)
