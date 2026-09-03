# Adopting an existing Windows installation

You do not need to reinstall Windows or let Winenv reinstall the software already on the machine.

## Start with a read-only scan

```powershell
win scan
win scan powertoys       # filter by keyword
win scan -From winget    # filter by manager
```

Scanning does not install, update, remove, or write to a profile. Results use three states:

| State | Meaning |
| --- | --- |
| `managed` | Claimed by an active Winenv profile |
| `adoptable` | The installation maps to a current WinGet source, Scoop bucket, or mise tool and can be reproduced elsewhere |
| `local` | Windows knows it is installed, but no configured catalog can map it reliably—for example, some OEM tools and manually installed applications |

`winget list` can report applications installed both by WinGet and by other methods. A `winget` source in the scan means the current catalog can reproduce the app; it does not claim WinGet originally installed it.

## Adopt selected software

```powershell
win adopt
win adopt powertoys
win adopt -From scoop
win adopt -n             # select and preview without writing
```

`adopt` accepts only `adoptable` entries and merges the selection into:

```text
%LOCALAPPDATA%\Winenv\profiles\adopted.json
```

Nothing is reinstalled, updated, or removed. Repeating the command merges new selections. mise keeps the currently declared version, and Scoop records the HTTPS origin of a custom bucket when it can resolve one.

Winenv cannot reliably infer every command exposed by an installed package, so generated entries leave `commands` empty. Before sharing a durable profile, copy the JSON, improve its name, groups, and command declarations, then import it with `win use <file>`.

## Software that cannot be mapped

`local` entries are not forced into a supposedly reproducible manifest:

- if Windows records the application under Installed apps, `win rm` can usually find and remove it;
- if a future WinGet catalog entry matches, WinGet can then take responsibility for updates;
- otherwise, continue using the vendor updater or a newer installer.

This lets Winenv control what it can describe faithfully without inventing update and uninstall rules for unknown software.

## Disable the generated profile

```powershell
win off adopted
```

The software and snapshot remain. Only this layer's claims are disabled. A later `win adopt` warns before re-enabling the complete retained snapshot.
