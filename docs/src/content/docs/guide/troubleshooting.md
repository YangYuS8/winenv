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

## Network and proxy

If downloads time out or connections fail, read the original error first. A failed command does not necessarily mean a proxy is needed: missing packages, permissions, rate limits, and verification failures have other causes. If your connection already works, leave it alone.

Winenv does not manage proxies, switch mirrors, or retry through another route. Configure only the affected tool yourself, using its current help and official instructions:

- **WinGet:** [Microsoft's settings reference](https://learn.microsoft.com/en-us/windows/package-manager/winget/settings). Available proxy options depend on the installed version and administrative policy.
- **Scoop:** run `scoop help config` and check its [proxy setting](https://github.com/ScoopInstaller/Scoop/blob/master/libexec/scoop-config.ps1). Scoop uses Internet Options by default; Git and other download helpers may need separate attention.
- **mise:** follow the [HTTP proxy FAQ](https://mise.jdx.dev/faq.html#how-do-i-use-mise-with-http-proxies) for `http_proxy` / `https_proxy`. Plugins may behave differently.
- **Winenv bootstrap or shared-file downloads:** these use PowerShell, not a package manager. Check the help for your PowerShell version's [Invoke-WebRequest](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest) and `Invoke-RestMethod`. If the initial `irm ... | iex` download fails, Winenv has not started and cannot display its own hint.

If you use FlClash or Clash Verge, first check that the client is running and its address/port matches any explicit settings. A system proxy only affects programs that honor it; TUN routes traffic at the network layer. Turning off a tool's explicit proxy does not bypass TUN. Manage those choices in your proxy client; see the [Clash Verge guide](https://www.clashverge.dev/guide/quickstart.html).

Keep HTTPS, hash, and signature verification enabled. Remove proxy credentials and private URLs before sharing logs.

## A Profile cannot be resolved

Inspect `win ls` and `win diff`. Identical claims merge, but incompatible versions or command providers require a choice. Automation flags do not resolve such conflicts. Refresh only the intended source with `win use <file-or-URL>`; disable an unwanted layer with `win off <name-or-id>`. Disabling does not uninstall its software.

## Hash, signature, or source verification fails

Stop. Check that the file came from the intended publisher and compare its SHA-256 with an independently trusted value. Do not disable signature checks, Windows protection, or HTTPS verification to make an installer run. See [manual installers](/winenv/guide/manual-installers/) and the [security policy](https://github.com/YangYuS8/winenv/blob/main/SECURITY.md).

## Ask for help

Use a [question or bug form](https://github.com/YangYuS8/winenv/issues/new/choose). Include `win ver`, Windows build, PowerShell version, the exact command, expected and actual behavior, and sanitized text output. Remove usernames, private paths, tokens, and private Profile URLs. Vulnerabilities belong in the private security reporting channel, not a public issue.
