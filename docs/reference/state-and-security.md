# State, storage, and security

Winenv stores declarative state in its own directories. It does not store software accounts, passwords, or login tokens.

## Local files

```text
%LOCALAPPDATA%\Winenv\state.json
%LOCALAPPDATA%\Winenv\config.json
%LOCALAPPDATA%\Winenv\profiles\*.json
%LOCALAPPDATA%\Winenv\logs\*.log
%USERPROFILE%\.config\mise\conf.d\winenv.toml
```

| Path | Contents |
| --- | --- |
| `state.json` | One-time migrations already executed |
| `config.json` | Language preference, profile registry, and local conflict choices |
| `profiles/*.json` | Stable snapshots of local, remote, and generated profiles |
| `logs/*.log` | Verbose MSI installation logs |
| `winenv.toml` | Isolated mise fragment generated from effective claims |

The legacy single `user-profile.json` is migrated to an independent snapshot on first run. The original file is retained.

## Who owns software

Profiles declare requirements; actual ownership remains with:

- WinGet for installer-based and Windows-integrated apps;
- Scoop for bucket or standalone-manifest installations;
- mise for versioned development tools;
- the publisher for manual software outside the catalogs.

Disabling a profile therefore does not uninstall software. Updates and removal continue to respect each manager's pins, holds, version configuration, and security rules.

## Network sources

- The installer downloads versioned GitHub Release assets and verifies the repository-published SHA-256.
- Remote profiles and Scoop manifests require HTTPS; profile refreshes require another explicit `win use`.
- Third-party Scoop buckets show their full Git URL and require a separate confirmation.
- Winenv never executes a raw EXE/MSI directly from a URL; save and inspect the file first.

HTTPS and a hash establish transport and content identity; they are not an endorsement of the publisher. Evaluate the maintainer before using a community profile, bucket, or installer.

## Privilege boundary

Winenv does not silently:

- elevate to administrator;
- change PowerShell execution policy;
- enable WinGet's local-manifest security setting;
- replace the URL behind a same-name third-party bucket;
- accept a broken or unverifiable installer signature.

When system privileges are necessary, Windows or the upstream installer asks explicitly through its own mechanism.

## Deliberate non-goals

- Removing built-in Windows components
- Changing Defender, BitLocker, or Windows Update policy
- Installing drivers automatically
- Guessing unattended, update, or uninstall arguments for arbitrary EXEs
- Storing login tokens or private application data
- Bypassing manager-level retention, pin, hold, or cleanup policies
