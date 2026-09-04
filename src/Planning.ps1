# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function Resolve-RuntimeInstallPlan {
    param([array]$Packages)
    $remaining = New-Object System.Collections.Generic.List[object]
    $verificationPackages = New-Object System.Collections.Generic.List[object]
    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($package in @($Packages)) {
        $requirement = Get-RuntimeRequirement $package
        if ($null -eq $requirement) {
            $remaining.Add($package)
            continue
        }

        $probe = Get-RuntimeRequirementProbe $package
        $versionText = if ($null -ne $probe.Version) { $probe.Version.ToString() } else { "-" }
        if ($probe.Status -eq "available") {
            $rows.Add([pscustomobject]@{
                Action = "reuse"
                Requirement = $probe.Name
                Version = $versionText
                Location = $probe.Path
            })
            continue
        }

        if ($probe.Status -eq "missing") {
            $rows.Add([pscustomobject]@{
                Action = "install"
                Requirement = $probe.Name
                Version = ">= $($probe.MinimumVersion)"
                Location = "via $($package.owner)"
            })
            $remaining.Add($package)
            $verificationPackages.Add($package)
            continue
        }

        $reason = if ($probe.Status -eq "outdated") {
            "version $versionText is older than the required $($probe.MinimumVersion)"
        } else {
            "the command could not be executed"
        }
        $rows.Add([pscustomobject]@{
            Action = "conflict"
            Requirement = $probe.Name
            Version = $versionText
            Location = $probe.Path
        })
        Write-Step "Runtime requirement conflict"
        Write-WinenvHost "$($probe.Name): $reason." -ForegroundColor Yellow
        Write-WinenvHost "Existing command: $($probe.Path)"
        Write-WinenvHost "Fallback package: $($package.owner)/$($package.id)"
        if ($DryRun -or $Yes) {
            throw "A broken or outdated runtime command requires an explicit interactive choice; nothing was installed."
        }
        if (-not (Confirm-Operation "Install the fallback package and verify command resolution afterwards?")) {
            throw "Runtime dependency installation was cancelled."
        }
        $remaining.Add($package)
        $verificationPackages.Add($package)
    }

    if ($rows.Count -gt 0) {
        Write-Step "Runtime requirements"
        Write-WinenvHost ("{0,-10} {1,-18} {2,-12} {3}" -f
            (Get-WinenvLocalizedColumnName "action"),
            (Get-WinenvLocalizedColumnName "requirement"),
            (Get-WinenvLocalizedColumnName "version"),
            (Get-WinenvLocalizedColumnName "location")) -ForegroundColor DarkGray
        foreach ($row in $rows) {
            $color = switch ($row.Action) {
                "reuse" { "Green" }
                "install" { "Cyan" }
                default { "Yellow" }
            }
            $localizedAction = Get-WinenvLocalizedDisplayValue "action" $row.Action
            Write-WinenvHost ("{0,-10} {1,-18} {2,-12} {3}" -f $localizedAction, $row.Requirement, $row.Version, $row.Location) -ForegroundColor $color
        }
    }

    return [pscustomobject]@{
        Packages = @($remaining | ForEach-Object { $_ })
        VerificationPackages = @($verificationPackages | ForEach-Object { $_ })
    }
}

function Assert-RuntimeRequirements {
    param([array]$Packages)
    if ($DryRun -or @($Packages).Count -eq 0) { return }

    Refresh-ProcessPath
    foreach ($package in @($Packages)) {
        $probe = Get-RuntimeRequirementProbe $package
        if ($probe.Status -ne "available") {
            $detail = if ($probe.Path) { "The effective executable is $($probe.Path)." } else { "The command is still absent from PATH." }
            throw "$($probe.Name) was installed through $($package.owner), but its requirement is still $($probe.Status). $detail Open a new PowerShell window, run 'win check', and resolve the reported PATH conflict."
        }
        $ready = Get-WinenvLocalizedDisplayValue "action" "ready"
        Write-WinenvHost ("{0,-10} {1,-18} {2,-12} {3}" -f $ready, $probe.Name, $probe.Version, $probe.Path) -ForegroundColor Green
    }
}

function Resolve-ExistingPackagePlan {
    param([array]$Packages)
    $owners = @($Packages | ForEach-Object owner | Sort-Object -Unique)
    $installed = @()
    if ($owners -contains "winget") {
        $wingetTable = @(Get-WinGetCandidates "" -Installed)
        $wingetExport = Get-WinGetExportInventory
        if ($wingetExport.Succeeded) { $installed += @($wingetExport.Candidates) } else { $installed += $wingetTable }
    }
    if ($owners -contains "scoop") { $installed += @(Get-ScoopCandidates "" -Installed) }
    if ($owners -contains "mise") { $installed += @(Get-MiseCandidates "" -Installed) }

    $remaining = New-Object System.Collections.Generic.List[object]
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($package in @($Packages)) {
        $matches = @($installed | Where-Object {
            $_.Manager -eq $package.owner -and
            ([string]$_.Id).Equals([string]$package.id, [StringComparison]::OrdinalIgnoreCase)
        })
        $existing = @($matches | Where-Object {
            if ($package.owner -eq "mise") { return Test-MiseVersionSatisfied ([string]$package.version) $_ }
            if (-not [string]::IsNullOrWhiteSpace([string]$package.version)) {
                return ([string]$_.Version).Equals([string]$package.version, [StringComparison]::OrdinalIgnoreCase)
            }
            return $true
        } | Select-Object -First 1)
        if ($existing.Count -gt 0) {
            $rows.Add([pscustomobject]@{
                Action = "reuse"
                Manager = [string]$package.owner
                Name = [string]$package.displayName
                Version = [string]$existing[0].Version
            })
            continue
        }
        $rows.Add([pscustomobject]@{
            Action = if ($package.owner -eq "vendor") { "manual" } else { "install" }
            Manager = [string]$package.owner
            Name = [string]$package.displayName
            Version = if ($package.version) { [string]$package.version } else { "latest" }
        })
        $remaining.Add($package)
    }

    if ($rows.Count -gt 0) {
        Write-Step "Software plan"
        Write-WinenvHost ("{0,-9} {1,-8} {2,-28} {3}" -f
            (Get-WinenvLocalizedColumnName "action"),
            (Get-WinenvLocalizedColumnName "manager"),
            (Get-WinenvLocalizedColumnName "name"),
            (Get-WinenvLocalizedColumnName "version")) -ForegroundColor DarkGray
        foreach ($row in $rows) {
            $color = if ($row.Action -eq "reuse") { "Green" } elseif ($row.Action -eq "install") { "Cyan" } else { "Yellow" }
            $localizedAction = Get-WinenvLocalizedDisplayValue "action" $row.Action
            $localizedVersion = ConvertTo-WinenvLocalizedText ([string]$row.Version)
            Write-WinenvHost ("{0,-9} {1,-8} {2,-28} {3}" -f $localizedAction, $row.Manager, $row.Name, $localizedVersion) -ForegroundColor $color
        }
    }
    return @($remaining | ForEach-Object { $_ })
}

function Get-WinenvPackageLocation {
    param($Package)
    $owner = if ($Package.psobject.Properties.Name -contains "owner") { [string]$Package.owner } else { [string]$Package.Manager }
    switch ($owner) {
        "winget" {
            $source = if ($Package.psobject.Properties.Name -contains "source") { [string]$Package.source } else { [string]$Package.Source }
            if ($source) { return $source }
            return "winget"
        }
        "scoop" {
            $bucket = if ($Package.psobject.Properties.Name -contains "bucket") { [string]$Package.bucket } else { [string]$Package.Source }
            if ($bucket) { return $bucket }
            return "main"
        }
        "mise" { return "mise" }
        default { return "vendor" }
    }
}

function Test-WinenvPackageVersionSatisfied {
    param(
        $Package,
        $Candidate
    )
    $requested = [string]$Package.version
    if ([string]::IsNullOrWhiteSpace($requested)) { return $true }
    if ([string]$Package.owner -eq "mise") { return Test-MiseVersionSatisfied $requested $Candidate }
    return ([string]$Candidate.Version).Equals($requested, [StringComparison]::OrdinalIgnoreCase)
}

function Test-WinenvCandidateVersionKnown {
    param($Candidate)
    $version = ([string]$Candidate.Version).Trim()
    return -not [string]::IsNullOrWhiteSpace($version) -and $version -notin @("unknown", "-", "n/a")
}

function Get-WinenvInstalledInventorySnapshot {
    param([array]$Packages)

    $candidates = New-Object System.Collections.Generic.List[object]
    $providerStatus = @{}
    $owners = @($Packages | Where-Object { -not [bool]$_._runtime -and $_.owner -in @("winget", "scoop", "mise") } | ForEach-Object owner | Sort-Object -Unique)
    foreach ($owner in $owners) {
        $probe = Get-ManagerProbe $owner
        $providerStatus[$owner] = [string]$probe.Status
        if ($probe.Status -ne "available") { continue }

        try {
            $inventory = switch ($owner) {
                "winget" {
                    $tableCandidates = @(Get-WinGetCandidates "" -Installed)
                    $export = Get-WinGetExportInventory
                    if ($export.Succeeded) { @($export.Candidates) } else { $tableCandidates }
                }
                "scoop" { @(Get-ScoopCandidates "" -Installed) }
                "mise" { @(Get-MiseCandidates "" -Installed) }
            }
            foreach ($candidate in @($inventory)) {
                if ($null -ne $candidate) { $candidates.Add($candidate) }
            }
        } catch {
            $providerStatus[$owner] = "inventory-error"
        }
    }

    return [pscustomobject]@{
        Candidates = @($candidates | ForEach-Object { $_ })
        ProviderStatus = $providerStatus
    }
}

function Get-WinenvDesiredPackageText {
    param($Package)
    $version = if ([string]::IsNullOrWhiteSpace([string]$Package.version)) { "present" } else { [string]$Package.version }
    if ([string]$Package.owner -in @("winget", "scoop")) {
        return "$(Get-WinenvPackageLocation $Package) @ $version"
    }
    return $version
}

function Get-WinenvActualPackageText {
    param(
        $Package,
        $Candidate
    )
    $version = if (Test-WinenvCandidateVersionKnown $Candidate) { [string]$Candidate.Version } else { "unknown" }
    if ([string]$Package.owner -in @("winget", "scoop")) {
        return "$(Get-WinenvPackageLocation $Candidate) @ $version"
    }
    return $version
}

function Compare-WinenvPackageState {
    param(
        [array]$Packages,
        $Snapshot
    )

    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($package in @($Packages | Sort-Object owner, displayName, id)) {
        $requirement = Get-RuntimeRequirement $package
        if ($null -ne $requirement) {
            $probe = Get-RuntimeRequirementProbe $package
            $status = switch ([string]$probe.Status) {
                "available" { "satisfied" }
                "missing" { "missing" }
                "outdated" { "version-drift" }
                default { "unverifiable" }
            }
            $rows.Add([pscustomobject]@{
                Status = $status
                Manager = [string]$package.owner
                Name = [string]$probe.Name
                Desired = ">= $($probe.MinimumVersion)"
                Actual = if ($null -ne $probe.Version) { [string]$probe.Version } elseif ($probe.Status -eq "missing") { "-" } else { [string]$probe.Status }
            })
            continue
        }

        if ([string]$package.owner -eq "vendor") {
            $rows.Add([pscustomobject]@{
                Status = "unverifiable"
                Manager = "vendor"
                Name = [string]$package.displayName
                Desired = "present"
                Actual = "manual inspection"
            })
            continue
        }

        $providerStatus = if ($Snapshot.ProviderStatus.ContainsKey([string]$package.owner)) { [string]$Snapshot.ProviderStatus[[string]$package.owner] } else { "missing" }
        if ($providerStatus -ne "available") {
            $rows.Add([pscustomobject]@{
                Status = "manager-unavailable"
                Manager = [string]$package.owner
                Name = [string]$package.displayName
                Desired = Get-WinenvDesiredPackageText $package
                Actual = $providerStatus
            })
            continue
        }

        $desiredIdentity = Get-PackageIdentity $package
        $exact = @($Snapshot.Candidates | Where-Object {
            $_.Manager -eq $package.owner -and (Get-PackageIdentity (ConvertTo-PackageDefinition $_)) -eq $desiredIdentity
        } | Select-Object -First 1)
        if ($exact.Count -gt 0) {
            $candidate = $exact[0]
            $hasRequestedVersion = -not [string]::IsNullOrWhiteSpace([string]$package.version)
            $status = if (Test-WinenvPackageVersionSatisfied $package $candidate) {
                "satisfied"
            } elseif ($hasRequestedVersion -and -not (Test-WinenvCandidateVersionKnown $candidate)) {
                "unverifiable"
            } else {
                "version-drift"
            }
            $rows.Add([pscustomobject]@{
                Status = $status
                Manager = [string]$package.owner
                Name = [string]$package.displayName
                Desired = Get-WinenvDesiredPackageText $package
                Actual = Get-WinenvActualPackageText $package $candidate
            })
            continue
        }

        $differentSource = @($Snapshot.Candidates | Where-Object {
            $_.Manager -eq $package.owner -and ([string]$_.Id).Equals([string]$package.id, [StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
        if ($differentSource.Count -gt 0) {
            $rows.Add([pscustomobject]@{
                Status = "source-drift"
                Manager = [string]$package.owner
                Name = [string]$package.displayName
                Desired = Get-WinenvDesiredPackageText $package
                Actual = Get-WinenvActualPackageText $package $differentSource[0]
            })
            continue
        }

        $rows.Add([pscustomobject]@{
            Status = "missing"
            Manager = [string]$package.owner
            Name = [string]$package.displayName
            Desired = Get-WinenvDesiredPackageText $package
            Actual = "-"
        })
    }
    return @($rows | ForEach-Object { $_ })
}

function Get-WinenvProfileDiff {
    param(
        $Definition,
        [string]$Query = ""
    )
    $packages = @(Get-SelectedPackages $Definition | Where-Object {
        ($Manager -in @("all", "managed") -or $_.owner -eq $Manager) -and
        ([string]::IsNullOrWhiteSpace($Query) -or (Test-PackageMatch $_ $Query))
    })
    if ($packages.Count -eq 0) { return @() }
    $snapshot = Get-WinenvInstalledInventorySnapshot $packages
    return @(Compare-WinenvPackageState $packages $snapshot)
}

function ConvertTo-WinenvLocalizedDiffValue {
    param([string]$Value)
    $parts = @($Value -split " @ ", 2)
    if ($parts.Count -eq 2) {
        $detail = Get-WinenvLocalizedDisplayValue "status" $parts[1]
        $detail = ConvertTo-WinenvLocalizedText ([string]$detail)
        return "$($parts[0]) @ $detail"
    }
    $localized = Get-WinenvLocalizedDisplayValue "status" $Value
    return ConvertTo-WinenvLocalizedText ([string]$localized)
}

function Show-WinenvProfileDiff {
    param(
        $Definition,
        [string]$Query = ""
    )
    $rows = @(Get-WinenvProfileDiff $Definition $Query)
    if ($rows.Count -eq 0) {
        if ([string]::IsNullOrWhiteSpace($Query)) {
            Write-WinenvHost "No profile declarations are selected."
        } else {
            Write-WinenvHost "No profile declarations matched '$Query'."
        }
        return
    }

    Write-Step "Profile difference"
    $displayRows = @($rows | ForEach-Object {
        [pscustomobject]@{
            status = $_.Status
            manager = $_.Manager
            name = $_.Name
            desired = ConvertTo-WinenvLocalizedDiffValue ([string]$_.Desired)
            actual = ConvertTo-WinenvLocalizedDiffValue ([string]$_.Actual)
        }
    })
    $displayRows | Format-WinenvTable -Property status, manager, name, desired, actual -AutoSize

    $satisfied = @($rows | Where-Object Status -eq "satisfied").Count
    $unverifiable = @($rows | Where-Object Status -eq "unverifiable").Count
    $attention = $rows.Count - $satisfied - $unverifiable
    Write-WinenvHost "Satisfied: $satisfied | Attention: $attention | Unverifiable: $unverifiable"
    if ($attention -eq 0) {
        Write-WinenvHost "All automatically verifiable profile declarations are satisfied." -ForegroundColor Green
    } else {
        Write-WinenvHost "Review missing, drifted, or unavailable declarations above." -ForegroundColor Yellow
    }
    Write-WinenvHost "Extra installed software is not treated as drift. Run 'win scan' to review it." -ForegroundColor DarkGray
}

function Install-Packages {
    param(
        $Definition,
        [array]$Packages,
        [switch]$ProfileManagedMise
    )
    $runtimePlan = Resolve-RuntimeInstallPlan @($Packages)
    $packages = @(Resolve-ExistingPackagePlan @($runtimePlan.Packages))
    $owners = @($packages | ForEach-Object { $_.owner } | Sort-Object -Unique)

    Ensure-WinGet
    if ($owners -contains "scoop") { Ensure-Scoop }
    if ($owners -contains "mise") { Ensure-Mise }

    if ($owners -contains "scoop") {
        foreach ($bucket in @($Definition.scoopBuckets)) {
            Ensure-ScoopBucket $bucket
        }
    }

    foreach ($package in $packages) {
        Write-Step "Installing $($package.displayName) with $($package.owner)"
        $context = [pscustomobject]@{
            Definition = $Definition
            ProfileManagedMise = [bool]$ProfileManagedMise
        }
        Invoke-WinenvProviderOperation ([string]$package.owner) "Install" @($package, $context)
    }

    Assert-RuntimeRequirements @($runtimePlan.VerificationPackages)
    Enable-WinenvInPowerShell
}

function Install-SelectedPackages {
    param($Definition)
    if ([string]::IsNullOrWhiteSpace($Target)) {
        if ($HasInstallerArguments -or -not [string]::IsNullOrWhiteSpace($Sha256)) {
            throw "-Args and -Hash can only be used with a direct EXE or MSI installer."
        }
        Sync-WinenvMiseConfig $Definition
        Install-Packages $Definition @(Get-SelectedPackages $Definition) -ProfileManagedMise:(!$Profiles -or $Profiles.Count -eq 0)
        return
    }

    if (Test-WindowsInstallerReference $Target) {
        Install-LocalWindowsInstaller $Target
        return
    }

    if ($HasInstallerArguments -or -not [string]::IsNullOrWhiteSpace($Sha256)) {
        throw "-Args and -Hash can only be used with a direct EXE or MSI installer."
    }

    if (Test-WinGetManifestReference $Target) {
        Install-WinGetManifest $Target
        return
    }

    if (Test-ScoopManifestReference $Target) {
        Install-ScoopManifest $Target
        return
    }

    $package = Resolve-PackageReference $Definition $Target
    if ($null -ne $package) {
        Install-Packages $Definition @($package)
        return
    }

    $candidates = @(Get-CatalogCandidates $Definition $Target)
    if ($candidates.Count -eq 0) {
        throw "No package matched '$Target'. Try 'win find $Target' or use a manager token."
    }
    $selected = @(Select-PackageCandidates $candidates "Install > " -Multi)
    if ($selected.Count -eq 0) {
        Write-WinenvHost "No packages selected."
        return
    }
    $packages = @($selected | ForEach-Object { ConvertTo-PackageDefinition $_ })
    Install-Packages $Definition $packages
}
