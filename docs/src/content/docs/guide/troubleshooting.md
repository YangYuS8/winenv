---
title: Troubleshooting
description: Diagnose command resolution, missing managers, profile conflicts, and installer verification without weakening Windows security.
sidebar:
  order: 7
---

Start with read-only diagnostics in a regular PowerShell window:

```powershell
win ver
win check
```

## The win command is missing

Open a new PowerShell window after installation. Check command resolution and whether your shell loads its profile:

```powershell
Get-Command win -All
$PROFILE
```

A shell started with `-NoProfile` does not load the integration installed in your PowerShell profile. If setup stopped early, inspect the original installer error before retrying the official installation command. Do not erase your PowerShell profile or reinstall Windows as a troubleshooting shortcut.

## A manager is unavailable

`win check` distinguishes missing tools, old versions, and conflicting paths. `manager-unavailable` in `win diff` means Winenv could not inspect that manager; it is not proof that its packages are missing.

If WinGet is absent, follow the [App Installer guidance](/winenv/guide/getting-started/#when-winget-is-unavailable). Scoop and mise have different responsibilities and are not replacements for a broken WinGet installation.

## A Profile cannot be resolved

Inspect `win ls` and `win diff`. Identical claims merge, but incompatible versions or command providers require a choice. Automation flags do not resolve such conflicts. Refresh only the intended source with `win use <file-or-URL>`; disable an unwanted layer with `win off <name-or-id>`. Disabling does not uninstall its software.

## Hash, signature, or source verification fails

Stop. Check that the file came from the intended publisher and compare its SHA-256 with an independently trusted value. Do not disable signature checks, Windows protection, or HTTPS verification to make an installer run. See [manual installers](/winenv/guide/manual-installers/) and the [security policy](https://github.com/YangYuS8/winenv/blob/main/SECURITY.md).

## Ask for help

Use a [question or bug form](https://github.com/YangYuS8/winenv/issues/new/choose). Include `win ver`, Windows build, PowerShell version, the exact command, expected and actual behavior, and sanitized text output. Remove usernames, private paths, tokens, and private Profile URLs. Vulnerabilities belong in the private security reporting channel, not a public issue.
