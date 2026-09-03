# Command reference

For daily work, remember `win`. Long action names remain compatible with older scripts, while this reference favors the short forms.

## Software

| Command | Purpose |
| --- | --- |
| `win [software]` | Open the interactive picker, optionally with an initial query |
| `win find <software>` | Print search results from the three managers |
| `win show <software>` | Show source, ownership, and package details |
| `win add [software]` | Apply active profiles or install a package/file |
| `win up` | Update Winenv and software recorded by each manager |
| `win rm [software]` | Select or search installed software for removal |
| `win clean` | Clear Scoop cache and unreferenced old tool versions |

## Profiles and the current PC

| Command | Purpose |
| --- | --- |
| `win scan [software]` | Read-only inventory of the current machine |
| `win adopt [software]` | Add selected reproducible software to the local `adopted` profile |
| `win use <file-or-URL>` | Import, refresh, and install an independent profile |
| `win use` | List registered profiles |
| `win off [profile]` | Disable one declaration layer without uninstalling |
| `win ls` | Show profiles, effective packages, and claims |

## Sources, language, and diagnostics

| Command | Purpose |
| --- | --- |
| `win bucket` | List Scoop buckets |
| `win bucket <name> [HTTPS URL]` | Add a known or third-party bucket |
| `win lang [en\|zh\|auto]` | Show or persist the interface language |
| `win check` | Inspect managers, runtime capabilities, and command conflicts |
| `win ver` | Print the Winenv version |
| `win help` | Show terminal help |

## Common parameters

| Short form | Long form | Purpose |
| --- | --- | --- |
| `-From` | `-Manager` | Limit to `managed`, `winget`, `scoop`, or `mise` |
| `-P` | `-Profiles` | Temporarily select profile groups |
| `-Lang` | `-Language` | Select `en`, `zh`, or `auto` for this invocation |
| `-n` | `-DryRun` | Produce a plan without changing the system |
| `-y` | `-Yes` | Confirm ordinary operations automatically |
| `-Hash` | `-Sha256` | Verify a local installer SHA-256 |
| `-Args` | `-InstallerArguments` | Pass known arguments to an EXE/MSI |

## Source token examples

```powershell
win add winget:winget/Microsoft.VisualStudioCode
win add scoop:extras/powertoys
win add mise:node
```

Copying the token from `win` or `win find` is safest because it includes the actual manager and catalog source.

## Compatible long action names

| Short command | Long action |
| --- | --- |
| `ls` | `list` |
| `off` | `unuse` |
| `find` | `search` |
| `show` | `info` |
| `check` | `doctor` |
| `add` | `install` |
| `up` | `update` |
| `rm` | `remove` |
| `clean` | `cleanup` |
| `lang` | `language` |
| `ver` | `version` |

Calling `win` without an action opens the interactive store.
