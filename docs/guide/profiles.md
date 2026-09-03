# Composing profiles

A profile declares what the machine should provide; it is not another package database. WinGet, Scoop, and mise still perform installation, updates, and removal.

## Built-in runtime layer

The repository's `profile.json` contains only capabilities required to run Winenv:

- PowerShell 7 for stable execution and detail previews;
- fzf for interactive search, selection, and removal.

These declarations do not seize ownership. Compatible installations already present on the machine are reused and keep their original update path.

The maintainer's personal software is not included in the repository or releases.

## Use personal or community profiles

User profiles follow the same schema as `profile.json`. Keep one locally or share it through GitHub, a Gist, or another site:

```powershell
win use C:\Users\me\my-winenv.json
win use https://raw.githubusercontent.com/user/dotfiles/main/winenv.json
```

`win use` validates the file, saves an independent snapshot, shows the plan produced by all active profiles, and asks for confirmation. It never overwrites another profile.

Importing the same source again refreshes only its snapshot. Remote profiles require HTTPS and never update silently during `win up`; run the original `win use <url>` again when you want upstream changes.

## Minimal example

```json
{
  "$schema": "https://raw.githubusercontent.com/YangYuS8/winenv/main/profile.schema.json",
  "schemaVersion": 1,
  "name": "my-tools",
  "defaultProfiles": ["desktop", "development"],
  "scoopBuckets": ["extras"],
  "packages": [
    {
      "key": "vscode",
      "displayName": "Visual Studio Code",
      "owner": "winget",
      "id": "Microsoft.VisualStudioCode",
      "source": "winget",
      "profiles": ["development"],
      "commands": ["code"]
    },
    {
      "key": "node",
      "displayName": "Node.js",
      "owner": "mise",
      "id": "node",
      "version": "lts",
      "profiles": ["development"],
      "commands": ["node", "npm"]
    }
  ]
}
```

See [`profile.schema.json`](https://github.com/YangYuS8/winenv/blob/main/profile.schema.json) for the complete constraints.

## Merge and conflict rules

Winenv composes all active layers before it installs anything:

- identical manager, source, package ID, and version claims install once while retaining every profile reference;
- different versions of one package, or different packages claiming one command, require an explicit local choice;
- `-y` and `-n` stop on an unresolved conflict rather than treating import order as priority;
- the runtime layer always remains, so a community profile cannot remove Winenv's PowerShell and fzf requirements.

Local conflict decisions live in `%LOCALAPPDATA%\Winenv\config.json`; they are never written back into someone else's profile.

## Inspect and re-enable

```powershell
win use                 # list registered profiles
win ls                  # show profiles, packages, and claims
win use shared-tools    # re-enable a retained local snapshot
```

Only a file or HTTPS URL refreshes a snapshot. If names collide, use the ID shown by `win ls`.

## Disabling and software ownership

```powershell
win off shared-tools
win off shared-tools-e06532a770
```

Disabling removes only that profile's claims and recalculates references:

- packages still claimed elsewhere remain referenced;
- packages with no remaining claim become `unclaimed`;
- installed software and the profile snapshot are retained.

The actual manager continues to own the software. Remove an unwanted package explicitly with `win rm <software>`. `win clean` does not treat unclaimed packages as garbage.

## mise configuration boundary

Active profile tools generate an isolated fragment:

```text
%USERPROFILE%\.config\mise\conf.d\winenv.toml
```

Winenv does not edit your global `config.toml`. Disabling a profile recalculates only this fragment, leaving project and personal global configuration independent.

Apply selected groups temporarily with:

```powershell
win add -P base,desktop,development
```

`-P` is short for `-Profiles`. It selects groups from the current runtime and user layers without changing which profiles are active.
