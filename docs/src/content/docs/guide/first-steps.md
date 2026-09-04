---
title: Your first session
description: Learn Winenv on your existing Windows PC with read-only checks before an optional installation.
sidebar:
  order: 2
---

This short walkthrough assumes you have [installed Winenv](/winenv/guide/getting-started/). You do not need a clean Windows installation or a shared Profile.

## 1. Check what is available

Open a new, regular PowerShell window:

```powershell
win ver
win check
```

The first command prints your Winenv version. The second reports manager availability and command conflicts. A missing optional manager does not mean you must reinstall Windows. Follow [troubleshooting](/winenv/guide/troubleshooting/) if a required command cannot run.

## 2. Inspect without changing anything

```powershell
win scan
win diff
```

`scan` inventories the PC. `diff` compares active declarations with installed state. With no user Profile, it checks the built-in runtime layer; it does not turn every installed application into a declaration. Neither command installs or removes software.

## 3. Search and choose a source

```powershell
win find ripgrep
```

Results retain their manager and source. Do not choose a result solely because its name looks familiar. For this example, if Scoop's main catalog offers ripgrep, inspect its exact token:

```powershell
win show scoop:main/ripgrep
win add scoop:main/ripgrep -n
```

The dry run previews the plan, including manager setup when applicable. If that source is unavailable, stop and inspect the manager instead of substituting an unrelated package.

## 4. Optionally apply the plan

Only if you want ripgrep and accept the displayed source:

```powershell
win add scoop:main/ripgrep
```

Read any prerequisite or trust prompts. This step changes the PC; the preceding inspection steps did not. An existing compatible installation may be reused. Installing one package is not the same as importing a shared Profile.

You now know the daily cycle: inspect, search, select a source, preview, and apply. Continue with [software management](/winenv/guide/packages/) or [Profile concepts](/winenv/concepts/profiles-and-ownership/).
