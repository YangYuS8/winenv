---
title: "Finding and managing software"
description: "Finding and managing software for Winenv, the Windows 11 software management layer."
sidebar:
  order: 3
---

<span id="finding-and-managing-software"></span>

Winenv does not maintain its own package index. Every search queries the WinGet, Scoop, and mise catalogs currently available on the machine and presents their results through one interface.

## Terminal software picker

```powershell
win                 # browse and filter
win powertoys       # start with a query
win vscode -From winget
```

The picker is powered by fzf:

- type to fuzzy-filter results;
- press `Tab` to select multiple entries, `Enter` to install, or `Esc` to cancel;
- press `Alt-P` to toggle the detail preview;
- use `Alt-J` and `Alt-K` to scroll the preview.

Each row includes manager, catalog source, name, ID, and version. If the same application exists in more than one catalog, each source remains a separate choice. Winenv does not silently pick one.

For copyable text output instead:

```powershell
win find powertoys
win find node -From mise
```

## Install or reuse

```powershell
win add                 # apply all active profiles
win add vscode          # install one known package
win add scoop:extras/powertoys
win add mise:node
```

Search results outside a profile include a manager-and-source token that can be passed directly to `win add`. Add software to a personal profile only when it should be reproduced on another machine.

Before installation, Winenv reads each manager's current inventory. If a matching package and version already satisfy the request, the plan reports `reuse` and leaves the installation in place.

## Default ownership policy

Use this decision order when building a durable baseline:

1. Must versions change between projects? Use mise.
2. Is it a portable, user-scoped CLI? Use Scoop.
3. Does it need an installer, service, registry entry, file association, or other Windows integration? Use WinGet.
4. If none fit, treat it as an explicit manual-installation exception.

These rules keep your own choices consistent. Search still shows every real source.

## Update

```powershell
win up
```

This updates Winenv first, then asks WinGet, Scoop, and mise to update everything they currently track—including packages outside profiles. WinGet pins, Scoop holds, and mise configuration remain authoritative within their managers.

The command shows its scope and asks for confirmation. Automation can use `win up -y`.

## Remove

```powershell
win rm                 # select from installed software
win rm powertoys       # narrow the selection
```

The manager that records the application performs the removal. Disabling a profile does not uninstall its software; see [Disabling and ownership](/winenv/guide/profiles/#disabling-and-software-ownership).

## Clean old versions

```powershell
win clean
```

This clears old Scoop versions and cache, then asks mise to prune tool versions no longer referenced by any mise configuration. Pin a required old version in global or project mise configuration before cleaning.

## Preview and confirmation

```powershell
win add node -From mise   # constrain the manager
win up -n                 # dry run
win up -y                 # confirm ordinary operations
```

Third-party sources and unverifiable installers introduce a new trust decision. `-y` never accepts that decision silently.
