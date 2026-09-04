---
title: "Software outside the default catalogs"
description: "Software outside the default catalogs for Winenv, the Windows 11 software management layer."
sidebar:
  order: 6
---

<span id="software-outside-the-default-catalogs"></span>

When software is missing from all three default catalogs, prefer a publisher-maintained package source. Treat a raw EXE or MSI as an explicit, inspected handoff only when reproducible metadata is unavailable.

## Additional Scoop buckets

Add a known Scoop bucket or a trusted third-party Git repository:

```powershell
win bucket
win bucket extras
win bucket mybucket https://github.com/user/scoop-bucket.git
```

A third-party bucket can execute installation scripts and therefore creates a new trust boundary. Winenv displays the full source. Adding it for the first time, or changing the URL behind an existing name, always requires human confirmation; `-y` does not make that decision.

For cross-machine reproduction, declare it in a profile:

```json
{
  "scoopBuckets": [
    "extras",
    {
      "name": "mybucket",
      "url": "https://github.com/user/scoop-bucket.git"
    }
  ]
}
```

Declarations that reuse a name with different URLs stop as a conflict.

## Standalone Scoop manifest

If a publisher provides only a JSON manifest:

```powershell
win add C:\Users\me\Downloads\my-app.json
win add https://example.com/my-app.json
```

Winenv accepts only a local or HTTPS `.json` up to 1 MiB. Before installation it shows the origin, version, and SHA-256 of the exact snapshot. Scoop still performs and records the installation.

A standalone manifest has no stable update feed. Put it in a trusted bucket if long-term `scoop update` support matters.

## Raw EXE and MSI

```powershell
win add C:\Users\me\Downloads\setup.exe
win add C:\Users\me\Downloads\setup.msi
```

Before launch, Winenv shows file size, product version, SHA-256, Authenticode state, and publisher. An EXE uses its own interface; an MSI runs through Windows `msiexec.exe` with `/norestart` by default and writes a verbose log under `%LOCALAPPDATA%\Winenv\logs`.

Winenv does not guess non-standard `/S` or `/silent` switches. Pass arguments or a known hash explicitly:

```powershell
win add .\setup.exe -Args '/S','/norestart'
win add .\setup.msi -Args '/passive','INSTALLDIR=C:\Tools\Example'
win add .\setup.exe -Hash 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
```

`-y` automatically accepts only a valid Authenticode signature or an unsigned file that exactly matches `-Hash`. A hash mismatch always stops. Broken, untrusted, or unverifiable signatures still require review.

Winenv currently does not download raw EXE/MSI files. Raw installers are not disguised as a package manager: future update, removal, and unattended behavior remain the publisher's responsibility.

## Local WinGet manifest

For stable reproduction, prefer a WinGet manifest containing download URL, SHA-256, arguments, and version:

```powershell
win add C:\Users\me\manifests\Example.App.yaml
win add C:\Users\me\manifests\Example.App
```

Winenv lists the YAML files and hashes, then runs `winget validate` and `winget install --manifest` after confirmation. Pass the directory for a multi-file manifest.

Local manifests are an administrator-controlled WinGet feature. Enable them explicitly in an elevated PowerShell before first use:

```powershell
winget settings --enable LocalManifestFiles
```

Winenv detects the setting but does not elevate itself or change it silently.

## After installation

If the installer registers an application with Windows Installed apps, it can usually be found later with:

```powershell
win rm application-name
```

`win up` can update it only when the installed entry maps to the public WinGet catalog. Otherwise, continue using the vendor updater or a newer installer.
