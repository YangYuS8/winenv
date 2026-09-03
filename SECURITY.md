# Security policy

[简体中文](./SECURITY.zh-CN.md)

## Supported versions

Winenv is pre-1.0 and ships through an automatically updated stable channel. Security fixes target the latest stable release and `main`.

| Version | Security support |
| --- | --- |
| Latest stable release | Supported |
| Older releases and source snapshots | Upgrade required |

If a fix requires an incompatible change, the advisory and release notes will include migration guidance.

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/YangYuS8/winenv/security/advisories/new). Do not disclose a suspected vulnerability in a public issue, pull request, discussion, or social post before a coordinated fix is available.

Include when possible:

- affected version or commit;
- Windows and PowerShell versions;
- attack prerequisites and realistic impact;
- minimal reproduction or proof of concept;
- relevant files, commands, and sanitized logs;
- any suggested mitigation.

Never include real credentials, access tokens, personal files, or third-party data. Use a harmless test environment.

## What to expect

The maintainer will acknowledge a complete report as time permits, validate impact, coordinate a remediation, and credit the reporter unless anonymity is requested. Response times are best-effort because the project is maintained by a small team; duplicate, non-actionable, and out-of-scope reports may be closed without a release.

Please allow time for a fix and release before public disclosure. If communication stops, request an update through the private advisory rather than opening a public issue.

## In scope

- command or argument injection in Winenv-controlled execution;
- bypass of installer hash, signature, HTTPS, or source-confirmation checks;
- unsafe profile or manifest parsing that crosses documented trust boundaries;
- unintended privilege escalation, secret exposure, or destructive file operations caused by Winenv;
- compromised release generation or update verification.

Expected upstream installer behavior, a malicious third-party profile explicitly approved by the user, missing antivirus detection, and vulnerabilities wholly inside WinGet, Scoop, mise, Windows, or a packaged application should normally be reported to the responsible upstream project.
