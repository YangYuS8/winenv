# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function New-PackageCandidate {
    param(
        [string]$ManagerName,
        [string]$Id,
        [string]$Name,
        [string]$Version = "",
        [string]$Source = "",
        [string]$Description = "",
        [string]$ManagedKey = "",
        [bool]$Adoptable = $true,
        [string]$RequestedVersion = ""
    )

    $normalizedSource = switch ($ManagerName) {
        "winget" { if ($Source) { $Source } else { "winget" } }
        "scoop" { if ($Source) { $Source } else { "main" } }
        "mise" { $Source }
        default { $Source }
    }
    $token = switch ($ManagerName) {
        "winget" { "winget:$normalizedSource/$Id" }
        "scoop" { "scoop:$normalizedSource/$Id" }
        "mise" { "mise:$Id" }
        default { "$ManagerName`:$Id" }
    }

    return [pscustomobject]@{
        Token = $token
        Manager = $ManagerName
        Name = if ($Name) { $Name } else { $Id }
        Id = $Id
        Version = $Version
        Source = $normalizedSource
        Description = $Description
        ManagedKey = $ManagedKey
        Adoptable = $Adoptable
        RequestedVersion = $RequestedVersion
    }
}

function ConvertTo-PackageDefinition {
    param($Candidate)
    return [pscustomobject]@{
        key = [string]$Candidate.Token
        displayName = [string]$Candidate.Name
        owner = [string]$Candidate.Manager
        id = [string]$Candidate.Id
        version = [string]$Candidate.Version
        source = if ($Candidate.Manager -eq "winget") { [string]$Candidate.Source } else { $null }
        bucket = if ($Candidate.Manager -eq "scoop") { [string]$Candidate.Source } else { $null }
        profiles = @()
        commands = @()
    }
}

function ConvertFrom-FixedWidthTable {
    param([string[]]$Lines)

    $escapeCharacter = [char]27
    $cleanLines = @($Lines | ForEach-Object {
        ([regex]::Replace([string]$_, "$escapeCharacter\[[0-9;?]*[ -/]*[@-~]", "")) -split "`r?`n"
    })
    $dividerIndex = -1
    $columns = @()
    for ($index = 0; $index -lt $cleanLines.Count; $index++) {
        $matches = @([regex]::Matches($cleanLines[$index], "-{2,}"))
        if ($matches.Count -ge 2) {
            $dividerIndex = $index
            $columns = $matches
            break
        }
    }
    if ($dividerIndex -lt 0) { return @() }

    $rows = @()
    foreach ($line in @($cleanLines | Select-Object -Skip ($dividerIndex + 1))) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $values = @()
        for ($columnIndex = 0; $columnIndex -lt $columns.Count; $columnIndex++) {
            $start = $columns[$columnIndex].Index
            if ($line.Length -le $start) {
                $values += ""
                continue
            }
            $end = if ($columnIndex + 1 -lt $columns.Count) {
                [Math]::Min($line.Length, $columns[$columnIndex + 1].Index)
            } else {
                $line.Length
            }
            $values += $line.Substring($start, [Math]::Max(0, $end - $start)).Trim()
        }
        if ($values.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($values[1])) {
            $rows += ,$values
        }
    }
    return @($rows)
}

function Invoke-CapturedCommand {
    param(
        [string]$Command,
        [string[]]$Arguments
    )
    $lines = @(& $Command @Arguments 2>&1)
    return [pscustomobject]@{ Lines = $lines; ExitCode = $LASTEXITCODE }
}

function Get-ManagedCandidates {
    param(
        $Definition,
        [string]$Query = ""
    )
    return @($Definition.packages | Where-Object {
        ($Manager -in @("all", "managed") -or $_.owner -eq $Manager) -and
        ([string]::IsNullOrWhiteSpace($Query) -or (Test-PackageMatch $_ $Query))
    } | ForEach-Object {
        $source = if ($_.owner -eq "winget") { [string]$_.source } elseif ($_.owner -eq "scoop") { [string]$_.bucket } else { "" }
        New-PackageCandidate -ManagerName $_.owner -Id $_.id -Name $_.displayName -Version $_.version -Source $source -Description $_.instructions -ManagedKey $_.key
    })
}

function Merge-PackageCandidates {
    param([array]$Candidates)
    $merged = [ordered]@{}
    foreach ($candidate in @($Candidates)) {
        if ($null -eq $candidate -or [string]::IsNullOrWhiteSpace([string]$candidate.Token)) { continue }
        $key = ([string]$candidate.Token).ToLowerInvariant()
        if (-not $merged.Contains($key)) {
            $merged[$key] = $candidate
            continue
        }
        $existing = $merged[$key]
        foreach ($property in @("Version", "Source", "Description", "ManagedKey", "RequestedVersion")) {
            if ([string]::IsNullOrWhiteSpace([string]$existing.$property) -and -not [string]::IsNullOrWhiteSpace([string]$candidate.$property)) {
                $existing.$property = $candidate.$property
            }
        }
        if (-not [bool]$candidate.Adoptable) { $existing.Adoptable = $false }
    }
    return @($merged.Values)
}

function Get-CatalogCandidates {
    param(
        $Definition,
        [string]$Query
    )
    $candidates = @(Get-ManagedCandidates $Definition $Query)
    if ($Manager -ne "managed") {
        $providers = if ($Manager -eq "all") {
            @(Get-WinenvProviderNames "Search")
        } else {
            @($Manager)
        }
        foreach ($provider in $providers) {
            $candidates += @(Invoke-WinenvProviderOperation $provider "Search" @($Query))
        }
    }
    return @(Merge-PackageCandidates $candidates | Sort-Object Manager, Name, Id)
}

function Get-InstalledCandidates {
    param(
        $Definition,
        [string]$Query = ""
    )
    $candidates = @()
    if ($Manager -in @("all", "managed", "winget")) {
        $winGetTable = @(Get-WinGetCandidates $Query -Installed)
        $candidates += @(Resolve-WinGetInstalledInventory $Definition $winGetTable $Query)
    }
    if ($Manager -in @("all", "managed", "scoop")) { $candidates += @(Get-ScoopCandidates $Query -Installed) }
    if ($Manager -in @("all", "managed", "mise")) { $candidates += @(Get-MiseCandidates $Query -Installed) }

    $managed = @(Get-ManagedCandidates $Definition $Query)
    foreach ($candidate in $candidates) {
        $match = @($managed | Where-Object {
            $_.Token -eq $candidate.Token -or
            ($_.Manager -eq $candidate.Manager -and ([string]$_.Id).Equals([string]$candidate.Id, [StringComparison]::OrdinalIgnoreCase))
        } | Select-Object -First 1)
        if ($match.Count -gt 0) { $candidate.ManagedKey = $match[0].ManagedKey }
    }
    return @(Merge-PackageCandidates $candidates | Sort-Object Manager, Name, Id)
}

function Get-InventoryStatus {
    param($Candidate)
    if (-not [string]::IsNullOrWhiteSpace([string]$Candidate.ManagedKey)) { return "managed" }
    if ([bool]$Candidate.Adoptable) { return "adoptable" }
    return "local"
}

function Show-InstalledInventory {
    param(
        $Definition,
        [string]$Query = $Target
    )

    $candidates = @(Get-InstalledCandidates $Definition $Query)
    if ($Manager -eq "managed") {
        $candidates = @($candidates | Where-Object { (Get-InventoryStatus $_) -eq "managed" })
    }
    Write-Step "Installed software inventory"
    if ($candidates.Count -eq 0) {
        Write-WinenvHost "No installed software matched '$Query'." -ForegroundColor Yellow
        return
    }

    $rows = @($candidates | ForEach-Object {
        [pscustomobject]@{
            status = Get-InventoryStatus $_
            manager = [string]$_.Manager
            source = [string]$_.Source
            name = [string]$_.Name
            id = [string]$_.Id
            version = [string]$_.Version
        }
    })
    $rows | Sort-Object status, manager, name | Format-WinenvTable -AutoSize

    $managedCount = @($rows | Where-Object status -eq "managed").Count
    $adoptableCount = @($rows | Where-Object status -eq "adoptable").Count
    $localCount = @($rows | Where-Object status -eq "local").Count
    Write-WinenvHost "managed: $managedCount | adoptable: $adoptableCount | local-only: $localCount" -ForegroundColor DarkGray
    Write-WinenvHost "'local' means Windows knows the app is installed, but WinGet could not match it to a configured source. Scan never changes software or profiles." -ForegroundColor DarkGray
}

function Get-AdoptedPackageKey {
    param($Candidate)
    $identity = "$([string]$Candidate.Manager)|$([string]$Candidate.Source)|$([string]$Candidate.Id)".ToLowerInvariant()
    $slug = ([regex]::Replace("$($Candidate.Manager)-$($Candidate.Id)".ToLowerInvariant(), "[^a-z0-9]+", "-")).Trim("-")
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "package" }
    if ($slug.Length -gt 48) { $slug = $slug.Substring(0, 48).TrimEnd("-") }
    return "$slug-$((Get-TextHash $identity).Substring(0, 8))"
}

function ConvertTo-AdoptedPackage {
    param($Candidate)
    $properties = [ordered]@{
        key = Get-AdoptedPackageKey $Candidate
        displayName = [string]$Candidate.Name
        owner = [string]$Candidate.Manager
        id = [string]$Candidate.Id
    }
    switch ([string]$Candidate.Manager) {
        "winget" { $properties.source = [string]$Candidate.Source }
        "scoop" { $properties.bucket = [string]$Candidate.Source }
        "mise" {
            $version = if (-not [string]::IsNullOrWhiteSpace([string]$Candidate.RequestedVersion)) {
                [string]$Candidate.RequestedVersion
            } else {
                [string]$Candidate.Version
            }
            if (-not [string]::IsNullOrWhiteSpace($version)) { $properties.version = $version }
        }
    }
    $properties.profiles = @($AdoptedProfileName)
    $properties.commands = @()
    return [pscustomobject]$properties
}

function Adopt-InstalledPackages {
    param(
        $Definition,
        [string]$Query = $Target
    )

    if ($Manager -eq "managed") {
        Write-WinenvHost "Already managed packages do not need adoption. Use 'win scan -From managed' to review them." -ForegroundColor DarkGray
        return
    }

    $inventory = @(Get-InstalledCandidates $Definition $Query)
    $adoptable = @($inventory | Where-Object {
        [bool]$_.Adoptable -and [string]::IsNullOrWhiteSpace([string]$_.ManagedKey)
    })
    $localCount = @($inventory | Where-Object { -not [bool]$_.Adoptable }).Count
    if ($adoptable.Count -eq 0) {
        Write-WinenvHost "No unclaimed reproducible packages matched '$Query'." -ForegroundColor Yellow
        if ($localCount -gt 0) {
            Write-WinenvHost "$localCount local-only app(s) were left untouched because no configured source can reproduce them." -ForegroundColor DarkGray
        }
        return
    }

    $selected = @(Select-PackageCandidates $adoptable "Adopt installed > " -Multi)
    if ($selected.Count -eq 0) { Write-WinenvHost "No packages selected."; return }
    $newPackages = @($selected | ForEach-Object { ConvertTo-AdoptedPackage $_ })

    Initialize-ProfileRegistry
    $config = Read-WinenvConfig
    $existingEntry = @($config.profiles | Where-Object { $_.source -eq $AdoptedProfileSource } | Select-Object -First 1)
    $existingProfile = $null
    if ($existingEntry.Count -gt 0) {
        $existingPath = Get-ProfileSnapshotPath $existingEntry[0]
        if (Test-Path -LiteralPath $existingPath) { $existingProfile = Read-ProfileFile $existingPath }
    }

    $packagesByIdentity = [ordered]@{}
    foreach ($package in @($existingProfile.packages) + $newPackages) {
        if ($null -eq $package) { continue }
        $packagesByIdentity[(Get-PackageIdentity $package)] = $package
    }
    $existingBuckets = if ($null -ne $existingProfile) { @($existingProfile.scoopBuckets) } else { @() }
    $adoptedProfile = [pscustomobject]@{
        schemaVersion = 1
        name = $AdoptedProfileName
        defaultProfiles = @($AdoptedProfileName)
        scoopBuckets = @(ConvertTo-StoredScoopBuckets @($existingBuckets + @(Get-AdoptedScoopBuckets $selected)))
        packages = @($packagesByIdentity.Values)
    }
    Assert-ProfileDefinition $adoptedProfile

    Write-Step "Adopt installed software"
    $newPackages | Select-Object displayName, owner, id, version | Format-WinenvTable -AutoSize
    $previousCount = if ($null -ne $existingProfile) { @($existingProfile.packages).Count } else { 0 }
    Write-WinenvHost "Selected: $($newPackages.Count) | previous claims kept: $previousCount | resulting claims: $(@($adoptedProfile.packages).Count)" -ForegroundColor DarkGray
    if ($existingEntry.Count -gt 0 -and -not [bool]$existingEntry[0].enabled) {
        Write-WinenvHost "The retained '$AdoptedProfileName' snapshot is currently disabled; saving will re-enable all of its claims." -ForegroundColor Yellow
    }
    Write-WinenvHost "This records the selected packages in a local profile. It does not reinstall, upgrade, or uninstall anything." -ForegroundColor DarkGray
    if (-not (Confirm-Operation "Save and enable the resulting local '$AdoptedProfileName' profile?")) {
        Write-WinenvHost "Adoption cancelled."
        return
    }

    $nextConfig = Copy-WinenvConfig $config
    $now = [DateTime]::UtcNow.ToString("o")
    if ($existingEntry.Count -gt 0) {
        $entry = @($nextConfig.profiles | Where-Object id -eq $existingEntry[0].id)[0]
        $entry.enabled = $true
        $entry.hash = Get-TextHash ($adoptedProfile | ConvertTo-Json -Depth 10)
        $entry.updatedAt = $now
    } else {
        $entry = [pscustomobject]@{
            id = $AdoptedProfileId
            name = $AdoptedProfileName
            source = $AdoptedProfileSource
            sourceType = "generated"
            fileName = "$AdoptedProfileId.json"
            hash = Get-TextHash ($adoptedProfile | ConvertTo-Json -Depth 10)
            enabled = $true
            addedAt = $now
            updatedAt = $now
        }
        $nextConfig.profiles = @($nextConfig.profiles) + @($entry)
    }

    $overrides = @{ ([string]$entry.id) = $adoptedProfile }
    $resolved = Resolve-ProfileDefinitions $nextConfig $overrides
    $resolved = Resolve-ProfileConflicts $nextConfig $resolved $overrides
    $snapshotPath = Get-ProfileSnapshotPath $entry
    Write-Plan "Save the local adoption profile to $snapshotPath"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $ProfilesRoot -Force | Out-Null
        $adoptedProfile | ConvertTo-Json -Depth 10 | Set-Content -Path $snapshotPath -Encoding UTF8
    }
    Write-WinenvConfig $nextConfig
    Sync-WinenvMiseConfig $resolved.Definition
    if ($DryRun) {
        Write-WinenvHost "The selected packages would be added to the local '$AdoptedProfileName' profile; installed software would not change."
    } else {
        Write-WinenvHost "Selected packages are now claimed by the local '$AdoptedProfileName' profile; installed software was not changed." -ForegroundColor Green
    }
}

function Resolve-PackageReference {
    param(
        $Definition,
        [string]$Reference
    )
    $managed = @($Definition.packages | Where-Object {
        if ($_.key -eq $Reference) { return $true }
        if ($_.psobject.Properties.Name -notcontains "_refs") { return $false }
        foreach ($ref in @($_._refs)) {
            if ($ref -eq $Reference) { return $true }
            if (-not $Reference.Contains("/") -and $ref.EndsWith("/$Reference", [StringComparison]::OrdinalIgnoreCase)) { return $true }
        }
        return $false
    })
    if ($managed.Count -eq 1) { return $managed[0] }
    if ($managed.Count -gt 1) {
        $qualified = @($managed | ForEach-Object { @($_._refs) } | Where-Object { $_.EndsWith("/$Reference", [StringComparison]::OrdinalIgnoreCase) }) -join ", "
        throw "Package reference '$Reference' is ambiguous. Use one of: $qualified"
    }
    if ($Reference -notmatch "^(winget|scoop|mise):(.+)$") { return $null }

    $managerName = $Matches[1]
    $identity = $Matches[2]
    $source = ""
    $id = $identity
    if ($managerName -in @("winget", "scoop") -and $identity.Contains("/")) {
        $source, $id = $identity.Split("/", 2)
    }
    $candidate = New-PackageCandidate -ManagerName $managerName -Id $id -Name $id -Source $source
    return ConvertTo-PackageDefinition $candidate
}

function Search-PackageCatalogs {
    param($Definition)
    if ([string]::IsNullOrWhiteSpace($Target)) {
        Open-PackageStore $Definition
        return
    }

    Write-Step "Live package catalogs"
    $candidates = @(Get-CatalogCandidates $Definition $Target)
    if ($candidates.Count -eq 0) {
        Write-WinenvHost "No matching packages were found in the available catalogs." -ForegroundColor Yellow
        return
    }
    $candidates | Select-Object Manager, Source, Name, Id, Version,
        @{Name = "Baseline"; Expression = { $_.ManagedKey }},
        @{Name = "Install"; Expression = {
            if ($_.ManagedKey) { "win add $($_.ManagedKey)" } else { "win add $($_.Token)" }
        }} |
        Format-WinenvTable -AutoSize
    Write-WinenvHost "Results with the same name stay separate by manager; Winenv never guesses between them." -ForegroundColor DarkGray
}

function Show-PackageInfo {
    param($Definition)
    if ([string]::IsNullOrWhiteSpace($Target)) {
        throw "show requires a profile key or manager token. Example: win show winget:winget/Microsoft.PowerToys"
    }

    $package = Resolve-PackageReference $Definition $Target
    if ($null -eq $package) { throw "Unknown package reference: $Target" }

    Write-WinenvHost $package.displayName -ForegroundColor Cyan
    Write-WinenvHost ("Reference: {0}" -f $Target)
    if ([bool]$package._runtime) {
        Write-WinenvHost ("Fallback:  {0}" -f $package.owner)
    } else {
        Write-WinenvHost ("Manager:   {0}" -f $package.owner)
    }
    Write-WinenvHost ("Package:   {0}" -f $package.id)
    if (@($package.profiles).Count -gt 0) {
        Write-WinenvHost ("Profiles:  {0}" -f (@($package.profiles) -join ", "))
    }
    if (@($package.commands).Count -gt 0) {
        Write-WinenvHost ("Commands:  {0}" -f (@($package.commands) -join ", "))
    }
    if ($package.instructions) { Write-WinenvHost "`n$($package.instructions)" }

    Write-WinenvHost "`nPackage details" -ForegroundColor DarkCyan
    switch ($package.owner) {
        "winget" {
            $managerProbe = Get-ManagerProbe "winget"
            if ($managerProbe.Status -eq "available") {
                $source = if ($package.source) { [string]$package.source } else { "winget" }
                if ($source -eq "windows") {
                    Invoke-Native $managerProbe.Path @("list", "--id", [string]$package.id, "--exact", "--accept-source-agreements", "--disable-interactivity") -IgnoreExitCode
                } else {
                    Invoke-Native $managerProbe.Path @("show", "--id", [string]$package.id, "--exact", "--source", $source, "--accept-source-agreements", "--disable-interactivity") -IgnoreExitCode
                }
            } else { Write-WinenvHost "WinGet is unavailable." }
        }
        "scoop" {
            $managerProbe = Get-ManagerProbe "scoop"
            if ($managerProbe.Status -eq "available") {
                $qualifiedId = if ($package.bucket) { "$($package.bucket)/$($package.id)" } else { [string]$package.id }
                Invoke-Native $managerProbe.Path @("info", $qualifiedId) -IgnoreExitCode
            } else { Write-WinenvHost "Scoop is unavailable." }
        }
        "mise" {
            $managerProbe = Get-ManagerProbe "mise"
            if ($managerProbe.Status -eq "available") { Invoke-Native $managerProbe.Path @("registry", [string]$package.id) -IgnoreExitCode }
            else { Write-WinenvHost "mise is unavailable." }
        }
        "vendor" { Write-WinenvHost "This package is managed by its vendor installer." }
    }
}

function Select-PackageCandidates {
    param(
        [array]$Candidates,
        [string]$Prompt,
        [switch]$Multi
    )
    $runtimeMarker = [pscustomobject]@{ key = "fzf"; _runtime = $true }
    $fzfProbe = Get-RuntimeRequirementProbe $runtimeMarker
    if ($fzfProbe.Status -ne "available") {
        $Candidates | Select-Object Manager, Source, Name, Id, Version, ManagedKey | Format-WinenvTable -AutoSize
        throw "Interactive selection requires fzf $($fzfProbe.MinimumVersion) or newer. Run 'win add fzf', then 'win check'."
    }

    $rows = @($Candidates | ForEach-Object {
        @([string]$_.Token, [string]$_.Manager, [string]$_.Source, [string]$_.Name, [string]$_.Id, [string]$_.Version, [string]$_.ManagedKey) -join "`t"
    })
    $pwshMarker = [pscustomobject]@{ key = "powershell"; _runtime = $true }
    $pwshProbe = Get-RuntimeRequirementProbe $pwshMarker
    $previewHost = if ($pwshProbe.Status -eq "available") {
        $pwshProbe.Path
    } elseif (Test-IsWindowsPlatform) {
        Join-Path $PSHOME "powershell.exe"
    } else {
        "pwsh"
    }
    $previewCommand = "`"$previewHost`" -NoLogo -NoProfile -File `"$WinenvEntryPath`" show {1} -Language $Script:WinenvLanguage"
    $fzfArguments = @(
        "--delimiter", "`t", "--with-nth", "2,3,4,5,6,7",
        "--header", (ConvertTo-WinenvLocalizedText "Manager | Source | Name | ID | Version | Baseline   (Alt-P: details, Esc: cancel)"),
        "--preview", $previewCommand, "--preview-label", (ConvertTo-WinenvLocalizedText "Alt-P: details | Alt-J/K: scroll"),
        "--preview-window", "down:60%:wrap",
        "--bind", "alt-p:toggle-preview,alt-d:preview-half-page-down,alt-u:preview-half-page-up,alt-k:preview-up,alt-j:preview-down",
        "--color", "pointer:green,marker:green,prompt:cyan", "--border", "rounded",
        "--height", "95%", "--layout", "reverse", "--prompt", (ConvertTo-WinenvLocalizedText $Prompt)
    )
    if ($Multi) { $fzfArguments = @("--multi") + $fzfArguments }

    $selectedRows = @($rows | & $fzfProbe.Path @fzfArguments)
    $fzfExitCode = $LASTEXITCODE
    if ($fzfExitCode -in @(1, 130) -or $selectedRows.Count -eq 0) { return @() }
    if ($null -ne $fzfExitCode -and $fzfExitCode -ne 0) { throw "fzf failed with exit code $fzfExitCode" }
    $tokens = @($selectedRows | ForEach-Object { ([string]$_ -split "`t", 2)[0] } | Select-Object -Unique)
    return @($Candidates | Where-Object { $tokens -contains $_.Token })
}

function Open-PackageStore {
    param(
        $Definition,
        [string]$Query = $Target
    )
    if ([string]::IsNullOrWhiteSpace($Query) -and $Manager -ne "managed") {
        $Query = Read-WinenvHost "Search WinGet, Scoop, and mise"
        if ([string]::IsNullOrWhiteSpace($Query)) {
            Write-WinenvHost "No search entered."
            return
        }
    }
    $candidates = @(Get-CatalogCandidates $Definition $Query)
    if ($candidates.Count -eq 0) {
        Write-WinenvHost "No matching packages were found in the available catalogs." -ForegroundColor Yellow
        return
    }

    $selected = @(Select-PackageCandidates $candidates "Winenv Store > " -Multi)
    if ($selected.Count -eq 0) { Write-WinenvHost "No packages selected."; return }
    $packages = @($selected | ForEach-Object { ConvertTo-PackageDefinition $_ })

    Write-Step "Installing selected packages"
    $selected | Select-Object Manager, Source, Name, Id, Version | Format-WinenvTable -AutoSize
    Install-Packages $Definition $packages
    Invoke-Migrations
    Write-WinenvHost "`nSelected packages installed." -ForegroundColor Green
}
