---
title: "Getting started"
description: "Getting started for Winenv, the Windows 11 software management layer."
sidebar:
  order: 1
---

<span id="getting-started"></span>

Winenv supports Windows 11. A fresh installation needs only regular PowerShell, a network connection, and WinGet, which Windows 11 normally provides through App Installer.

## Install in one line

Open a regular PowerShell window and run:

```powershell
irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1 | iex
```

The installer will:

1. resolve the latest stable GitHub Release;
2. download the versioned ZIP and `SHA256SUMS`, then verify SHA-256;
3. install that version under `%LOCALAPPDATA%\Winenv\versions`;
4. create the global `win` command;
5. probe the real paths and versions of PowerShell 7, fzf, and mise, reusing compatible installations;
6. install only the runtime capabilities that are still missing.

Open a new PowerShell window when it finishes:

```powershell
win check
win
```

:::tip[Existing prerequisites are reused]
If PowerShell 7 and fzf are already runnable and meet the minimum versions, Winenv uses them in place. Software originally installed with an MSI, ZIP, Scoop, or another method remains owned and updated by that method.
:::

## Language selection

English is the canonical interface language. On first run, Winenv follows the current Windows UI culture and selects Simplified Chinese for a `zh-*` culture; all other cultures use English.

```powershell
win lang             # show the effective language and its source
win lang en          # persist English
win lang zh          # persist Simplified Chinese
win lang auto        # return to system detection
```

Use `-Lang en`, `-Lang zh`, or `-Lang auto` for one invocation. The `WINENV_LANG` environment variable can set a session or automation default; an explicit `-Lang` takes precedence.

To select a language during installation:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -Lang zh
```

## When WinGet is unavailable

WinGet is the foundational installation route on Windows. If `winget.exe` cannot be found, the installer first tries to re-register the App Installer already present on Windows 11. If that fails, it stops with directions for Microsoft Store or official repair paths.

Winenv does not silently elevate privileges or install PowerShell Gallery modules to obtain WinGet.

## Import a profile during installation

Import a local file or an HTTPS URL:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -UserProfile C:\Users\me\my-winenv.json

& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -UserProfile https://example.com/my-winenv.json
```

The profile becomes an independent layer. It does not overwrite the runtime layer or another user profile. See [Composing profiles](/winenv/guide/profiles/).

## Install Winenv without applying profiles

To create the `win` command without immediately installing profile software:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -ToolOnly
```

Run `win add` later to apply the active profiles.

## Install a specific version

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/YangYuS8/winenv/main/install.ps1))) -Version 0.13.0
```

Without `-Version`, the installer always uses the latest stable release. The regular `win up` command updates Winenv before updating managed software.

## Where to go next

- New PC: [find and manage software](/winenv/guide/packages/).
- Existing PC: [scan and adopt the current installation](/winenv/guide/existing-windows/).
- Personal software baseline: create or import a [user profile](/winenv/guide/profiles/).
