# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function Enable-WinenvInPowerShell {
    $documents = [Environment]::GetFolderPath("MyDocuments")
    if ([string]::IsNullOrWhiteSpace($documents)) {
        if ($DryRun) {
            $documents = Join-Path ([IO.Path]::GetTempPath()) "WinenvDocuments"
        } else {
            throw "Windows Documents directory could not be resolved."
        }
    }
    $profilePaths = @(
        (Join-Path $documents "WindowsPowerShell\profile.ps1"),
        (Join-Path $documents "PowerShell\profile.ps1")
    )
    $startMarker = "# >>> winenv shell >>>"
    $endMarker = "# <<< winenv shell <<<"
    $escapedScriptPath = $WinenvEntryPath.Replace("'", "''")
    $stableLauncherPath = (Join-Path $StateRoot "bin\win-launch.ps1").Replace("'", "''")
    $block = @"
$startMarker
function win {
    if (Test-Path '$stableLauncherPath') {
        & '$stableLauncherPath' @args
    } else {
        & '$escapedScriptPath' @args
    }
}

if (Get-Command mise -ErrorAction SilentlyContinue) {
    (& mise activate pwsh) | Out-String | Invoke-Expression
}
$endMarker
"@

    foreach ($path in $profilePaths) {
        Write-Plan "Ensure the 'win' command and mise activation in $path"
        if ($DryRun) { continue }

        $directory = Split-Path -Parent $path
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $existing = if (Test-Path $path) { Get-Content -Raw -Encoding UTF8 -Path $path } else { "" }
        $pattern = "(?s)" + [Regex]::Escape($startMarker) + ".*?" + [Regex]::Escape($endMarker)
        if ($existing -match $pattern) {
            $updated = [Regex]::Replace($existing, $pattern, $block.TrimEnd())
        } else {
            $separator = if ([string]::IsNullOrWhiteSpace($existing)) { "" } else { "`r`n`r`n" }
            $updated = $existing.TrimEnd() + $separator + $block.TrimEnd() + "`r`n"
        }
        Set-Content -Path $path -Value $updated -Encoding UTF8
    }
}

function Test-ProfileHealth {
    param($Definition)
    Write-Step "Validating package ownership"
    Write-WinenvHost "All active profile claims resolved without ambiguity." -ForegroundColor Green

    $selectedPackages = Get-SelectedPackages $Definition

    Write-Step "Checking managers"
    Write-WinenvHost ("{0,-10} {1,-11} {2,-12} {3}" -f
        (Get-WinenvLocalizedColumnName "manager"),
        (Get-WinenvLocalizedColumnName "status"),
        (Get-WinenvLocalizedColumnName "version"),
        (Get-WinenvLocalizedColumnName "path")) -ForegroundColor DarkGray
    $managerProbes = @(@("winget", "scoop", "mise") | ForEach-Object { Get-ManagerProbe $_ })
    foreach ($probe in $managerProbes) {
        $version = if ($null -ne $probe.Version) { $probe.Version.ToString() } else { "-" }
        $path = if ($probe.Path) { $probe.Path } else { "-" }
        $color = if ($probe.Status -eq "available") { "Green" } else { "Yellow" }
        $localizedStatus = Get-WinenvLocalizedDisplayValue "status" $probe.Status
        Write-WinenvHost ("{0,-10} {1,-11} {2,-12} {3}" -f $probe.Name, $localizedStatus, $version, $path) -ForegroundColor $color
        if (@($probe.OtherPaths).Count -gt 0) {
            Write-WinenvHost ("           other paths: {0}" -f (@($probe.OtherPaths) -join " | ")) -ForegroundColor Yellow
        }
    }

    Write-Step "Checking Winenv runtime requirements"
    Write-WinenvHost ("{0,-10} {1,-18} {2,-12} {3}" -f
        (Get-WinenvLocalizedColumnName "action"),
        (Get-WinenvLocalizedColumnName "requirement"),
        (Get-WinenvLocalizedColumnName "version"),
        (ConvertTo-WinenvLocalizedText "path or fallback")) -ForegroundColor DarkGray
    foreach ($package in @($selectedPackages | Where-Object { $null -ne (Get-RuntimeRequirement $_) })) {
        $probe = Get-RuntimeRequirementProbe $package
        $version = if ($null -ne $probe.Version) { $probe.Version.ToString() } else { "-" }
        $action = switch ($probe.Status) {
            "available" { "reuse" }
            "missing" { "install" }
            default { "resolve" }
        }
        $location = if ($probe.Status -eq "missing") { "via $($package.owner)" } else { $probe.Path }
        $color = if ($probe.Status -eq "available") { "Green" } elseif ($probe.Status -eq "missing") { "DarkGray" } else { "Yellow" }
        $localizedAction = Get-WinenvLocalizedDisplayValue "action" $action
        Write-WinenvHost ("{0,-10} {1,-18} {2,-12} {3}" -f $localizedAction, $probe.Name, $version, $location) -ForegroundColor $color
        if ($probe.Status -eq "outdated") {
            Write-WinenvHost "           requires >= $($probe.MinimumVersion)" -ForegroundColor Yellow
        }
        if (@($probe.OtherPaths).Count -gt 0) {
            Write-WinenvHost ("           other paths: {0}" -f (@($probe.OtherPaths) -join " | ")) -ForegroundColor Yellow
        }
        if (@($probe.Shadowing).Count -gt 0) {
            Write-WinenvHost ("           same-name aliases/functions ignored: {0}" -f (@($probe.Shadowing) -join " | ")) -ForegroundColor Yellow
        }
    }

    Write-Step "Checking command resolution"
    foreach ($package in $selectedPackages) {
        foreach ($command in @($package.commands)) {
            $resolved = @(Get-Command $command -All -ErrorAction SilentlyContinue)
            if ($resolved.Count -eq 0) {
                $missing = Get-WinenvLocalizedDisplayValue "status" "missing"
                $owner = Get-WinenvLocalizedColumnName "owner"
                Write-WinenvHost ("{0,-12} {1} ({2}: {3})" -f $command, $missing, $owner, $package.owner) -ForegroundColor DarkGray
                continue
            }

            $paths = @($resolved | ForEach-Object {
                $location = if ($_.Path) { $_.Path } elseif ($_.Source) { $_.Source } else { $_.Name }
                "$($_.CommandType):$location"
            } | Select-Object -Unique)
            $color = if ($paths.Count -gt 1) { "Yellow" } else { "Green" }
            Write-WinenvHost ("{0,-12} {1}" -f $command, ($paths -join " | ")) -ForegroundColor $color
        }
    }

    $miseProbe = @($managerProbes | Where-Object Name -eq "mise" | Select-Object -First 1)
    if ($miseProbe.Count -gt 0 -and $miseProbe[0].Status -eq "available") {
        Write-Step "Running mise doctor"
        Invoke-Native $miseProbe[0].Path @("doctor") -IgnoreExitCode
    }
}

function Update-All {
    param($Definition)
    Update-WinenvSelf
    Ensure-WinGet
    $wingetCommand = Get-ResolvedManagerCommand "winget"
    Sync-WinenvMiseConfig $Definition
    $scoopCommand = Get-OptionalManagerCommand "scoop"
    $miseCommand = Get-OptionalManagerCommand "mise"

    Write-Step "Update scope"
    Write-WinenvHost "WinGet: every installed package with an available update"
    if ($null -ne $scoopCommand) { Write-WinenvHost "Scoop:  Scoop itself, bucket indexes, and every installed app" }
    else { Write-WinenvHost "Scoop:  skipped (not installed)" -ForegroundColor DarkGray }
    if ($null -ne $miseCommand) { Write-WinenvHost "mise:   every active tool from the mise configuration" }
    else { Write-WinenvHost "mise:   skipped (not installed)" -ForegroundColor DarkGray }

    if (-not (Confirm-Operation "Update everything tracked by the installed package managers?")) {
        Write-WinenvHost "Update cancelled."
        return
    }

    Write-Step "Updating all WinGet packages"
    Invoke-Native $wingetCommand @("source", "update")
    Invoke-Native $wingetCommand @(
        "upgrade", "--all", "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"
    ) -IgnoreExitCode

    if ($null -ne $scoopCommand) {
        Write-Step "Updating all Scoop packages"
        Invoke-Native $scoopCommand @("update")
        Invoke-Native $scoopCommand @("update", "*") -IgnoreExitCode
    }

    if ($null -ne $miseCommand) {
        Write-Step "Updating all active mise tools"
        $previousAge = $env:MISE_MINIMUM_RELEASE_AGE
        try {
            $env:MISE_MINIMUM_RELEASE_AGE = "0"
            Invoke-Native $miseCommand @("up")
        } finally {
            $env:MISE_MINIMUM_RELEASE_AGE = $previousAge
        }
    }

    Invoke-Migrations
}

function Remove-Package {
    param($Definition)

    $direct = if ([string]::IsNullOrWhiteSpace($Target)) { $null } else { Resolve-PackageReference $Definition $Target }
    if ($null -ne $direct) {
        $packages = @($direct)
    } else {
        $query = if ($Target) { $Target } else { "" }
        $candidates = @(Get-InstalledCandidates $Definition $query)
        if ($Manager -eq "managed") {
            $candidates = @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.ManagedKey) })
        }
        if ($candidates.Count -eq 0) {
            throw "No installed package matched '$query'."
        }
        $selected = @(Select-PackageCandidates $candidates "Remove > " -Multi)
        if ($selected.Count -eq 0) { Write-WinenvHost "No packages selected."; return }
        $packages = @($selected | ForEach-Object { ConvertTo-PackageDefinition $_ })
    }

    Write-Step "Packages selected for removal"
    $packages | Select-Object owner, displayName, id | Format-WinenvTable -AutoSize
    if (-not (Confirm-Operation "Remove these packages using their displayed managers?")) {
        Write-WinenvHost "Removal cancelled."
        return
    }

    foreach ($package in $packages) {
        Write-Step "Removing $($package.displayName) with $($package.owner)"
        Invoke-WinenvProviderOperation ([string]$package.owner) "Remove" @($package, $null)
    }
}

function Invoke-Cleanup {
    if (-not (Confirm-Operation "Remove old Scoop and unused mise versions?")) {
        Write-WinenvHost "Cleanup cancelled."
        return
    }

    $scoopCommand = Get-OptionalManagerCommand "scoop"
    if ($null -ne $scoopCommand) {
        Write-Step "Cleaning old Scoop versions"
        Invoke-Native $scoopCommand @("cleanup", "*")
        Invoke-Native $scoopCommand @("cache", "rm", "*")
    }
    $miseCommand = Get-OptionalManagerCommand "mise"
    if ($null -ne $miseCommand) {
        Write-Step "Pruning unused mise versions"
        Invoke-Native $miseCommand @("prune")
    }
}
