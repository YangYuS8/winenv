# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function ConvertFrom-ProfileText {
    param(
        [string]$Text,
        [string]$Source
    )
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "Profile is empty: $Source"
    }
    if ([Text.Encoding]::UTF8.GetByteCount($Text) -gt 1MB) {
        throw "Profile is larger than 1 MiB: $Source"
    }
    try {
        $definition = $Text | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Profile is not valid JSON: $Source"
    }
    if ($definition -isnot [pscustomobject]) {
        throw "Profile root must be a JSON object: $Source"
    }
    if ($definition.schemaVersion -ne 1) {
        throw "Unsupported profile schema version: $($definition.schemaVersion)"
    }
    return $definition
}

function Read-ProfileFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Profile not found: $Path" }
    return (ConvertFrom-ProfileText (Get-Content -Raw -Encoding UTF8 -Path $Path) $Path)
}

function Read-UserProfileSource {
    param([string]$Source)

    if ($Source -match "^https://") {
        Write-Step "Downloading shared profile"
        $response = Invoke-WebRequest -Uri $Source -UseBasicParsing -Headers @{
            "Accept" = "application/json"
            "User-Agent" = "winenv"
        }
        $text = if ($response.Content -is [byte[]]) {
            [Text.Encoding]::UTF8.GetString($response.Content)
        } else {
            [string]$response.Content
        }
        $uri = [Uri]$Source
        $displayUri = [UriBuilder]$uri
        $displayUri.UserName = ""
        $displayUri.Password = ""
        $displayUri.Query = ""
        $displayUri.Fragment = ""
        $canonicalUri = $displayUri.Uri.AbsoluteUri
        return [pscustomobject]@{
            Text = $text
            Label = $canonicalUri
            Key = "url:$canonicalUri"
            Type = "url"
        }
    }

    if ($Source -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
        throw "Shared profiles must use HTTPS: $Source"
    }
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "User profile JSON was not found: $Source"
    }
    $resolvedPath = (Resolve-Path -LiteralPath $Source).Path
    return [pscustomobject]@{
        Text = Get-Content -Raw -Encoding UTF8 -Path $resolvedPath
        Label = $resolvedPath
        Key = "file:$resolvedPath"
        Type = "file"
    }
}

function New-WinenvConfig {
    return [pscustomobject]@{
        schemaVersion = 2
        language = "auto"
        profiles = @()
        resolutions = @()
        legacy = $false
    }
}

function Get-ProfileId {
    param(
        [string]$Name,
        [string]$SourceKey
    )
    $slug = ([regex]::Replace($Name.ToLowerInvariant(), "[^a-z0-9]+", "-")).Trim("-")
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "profile" }
    if ($slug.Length -gt 32) { $slug = $slug.Substring(0, 32).TrimEnd("-") }
    return "$slug-$((Get-TextHash $SourceKey).Substring(0, 10))"
}

function Read-WinenvConfig {
    if (-not (Test-Path $ConfigPath)) { return New-WinenvConfig }
    try {
        $stored = Get-Content -Raw -Encoding UTF8 -Path $ConfigPath | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Winenv config is not valid JSON: $ConfigPath"
    }

    if ($stored.schemaVersion -eq 2) {
        return [pscustomobject]@{
            schemaVersion = 2
            language = if ($stored.psobject.Properties.Name -contains "language") { [string]$stored.language } else { "auto" }
            profiles = @($stored.profiles)
            resolutions = @($stored.resolutions)
            legacy = $false
        }
    }

    $config = New-WinenvConfig
    $config.legacy = $true
    if ([string]$stored.userProfile -eq "@local" -and (Test-Path $LocalUserProfilePath)) {
        $profile = Read-ProfileFile $LocalUserProfilePath
        $sourceKey = "legacy:@local"
        $id = Get-ProfileId $profile.name $sourceKey
        $config.profiles = @([pscustomobject]@{
            id = $id
            name = [string]$profile.name
            source = $sourceKey
            sourceType = "legacy"
            fileName = ""
            hash = Get-TextHash (Get-Content -Raw -Encoding UTF8 -Path $LocalUserProfilePath)
            enabled = $true
            addedAt = [DateTime]::UtcNow.ToString("o")
            updatedAt = [DateTime]::UtcNow.ToString("o")
        })
    }
    return $config
}

function Write-WinenvConfig {
    param($Config)
    Write-Plan "Save profile registry to $ConfigPath"
    if ($DryRun) { return }
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    $stored = [pscustomobject]@{
        schemaVersion = 2
        language = if ($Config.psobject.Properties.Name -contains "language") { [string]$Config.language } else { "auto" }
        profiles = @($Config.profiles | ForEach-Object {
            [pscustomobject]@{
                id = [string]$_.id
                name = [string]$_.name
                source = [string]$_.source
                sourceType = [string]$_.sourceType
                fileName = [string]$_.fileName
                hash = [string]$_.hash
                enabled = [bool]$_.enabled
                addedAt = [string]$_.addedAt
                updatedAt = [string]$_.updatedAt
            }
        })
        resolutions = @($Config.resolutions | ForEach-Object {
            [pscustomobject]@{
                key = [string]$_.key
                selected = [string]$_.selected
                updatedAt = [string]$_.updatedAt
            }
        })
    }
    $stored | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Get-ProfileSnapshotPath {
    param($Entry)
    if ([string]::IsNullOrWhiteSpace([string]$Entry.fileName)) { return $LocalUserProfilePath }
    $safeName = [IO.Path]::GetFileName([string]$Entry.fileName)
    return Join-Path $ProfilesRoot $safeName
}

function Initialize-ProfileRegistry {
    $config = Read-WinenvConfig
    if (-not $config.legacy) { return }

    Write-Step "Migrating the profile registry"
    if ($DryRun) {
        Write-Plan "Preserve the existing user profile as an independent snapshot"
        return
    }

    New-Item -ItemType Directory -Path $ProfilesRoot -Force | Out-Null
    foreach ($entry in @($config.profiles)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$entry.fileName)) { continue }
        $entry.fileName = "$($entry.id).json"
        Copy-Item -LiteralPath $LocalUserProfilePath -Destination (Get-ProfileSnapshotPath $entry) -Force
    }
    $config.legacy = $false
    Write-WinenvConfig $config
}

function Copy-WinenvConfig {
    param($Config)
    return (($Config | ConvertTo-Json -Depth 20) | ConvertFrom-Json)
}

function Copy-PackageDefinition {
    param($Package)
    $properties = [ordered]@{}
    foreach ($name in @("key", "displayName", "owner", "id", "source", "bucket", "version", "profiles", "commands", "provides", "instructions")) {
        if ($Package.psobject.Properties.Name -contains $name) {
            $properties[$name] = $Package.$name
        }
    }
    return [pscustomobject]$properties
}

function Get-PackageIdentity {
    param($Package)
    $location = switch ([string]$Package.owner) {
        "winget" { if ($Package.source) { [string]$Package.source } else { "winget" } }
        "scoop" { if ($Package.bucket) { [string]$Package.bucket } else { "main" } }
        "mise" { "mise" }
        default { "vendor" }
    }
    return "$([string]$Package.owner)|$location|$([string]$Package.id)".ToLowerInvariant()
}

function Get-PackageSpecSignature {
    param($Package)
    return "$(Get-PackageIdentity $Package)|$([string]$Package.version)".ToLowerInvariant()
}

function Get-CandidateSelectionToken {
    param($Candidate)
    return "spec:$(Get-PackageSpecSignature $Candidate.Package)"
}

function New-PackageClaim {
    param(
        $Package,
        $Entry,
        $Profile,
        [switch]$Runtime
    )
    $profileId = [string]$Entry.id
    $packageProfiles = @($Package.profiles)
    $defaultSelected = @($packageProfiles | Where-Object { @($Profile.defaultProfiles) -contains $_ }).Count -gt 0
    return [pscustomobject]@{
        Package = Copy-PackageDefinition $Package
        Identity = Get-PackageIdentity $Package
        Signature = Get-PackageSpecSignature $Package
        Ref = "$profileId/$([string]$Package.key)"
        ProfileId = $profileId
        ProfileName = [string]$Entry.name
        DefaultSelected = $defaultSelected
        Groups = @($packageProfiles | ForEach-Object { "$profileId/$_" })
        Runtime = [bool]$Runtime
    }
}

function Get-ResolutionSelection {
    param(
        $Config,
        [string]$Key,
        [array]$CandidateGroups
    )
    $runtimeGroup = @($CandidateGroups | Where-Object { @($_.Claims | Where-Object Runtime).Count -gt 0 } | Select-Object -First 1)
    if ($runtimeGroup.Count -gt 0) { return $runtimeGroup[0] }

    $resolution = @($Config.resolutions | Where-Object { $_.key -eq $Key } | Select-Object -First 1)
    if ($resolution.Count -eq 0) { return $null }
    $selected = [string]$resolution[0].selected
    $matches = @($CandidateGroups | Where-Object {
        (Get-CandidateSelectionToken $_) -eq $selected -or @($_.Claims.Ref) -contains $selected
    } | Select-Object -First 1)
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function Merge-PackageClaims {
    param([array]$Claims)
    $package = Copy-PackageDefinition $Claims[0].Package
    $package.profiles = @($Claims.Package.profiles | Select-Object -Unique)
    $package.commands = @($Claims.Package.commands | Where-Object { $_ } | Select-Object -Unique)
    if (@($Claims.Package.provides).Count -gt 0) {
        if ($package.psobject.Properties.Name -notcontains "provides") {
            $package | Add-Member -NotePropertyName provides -NotePropertyValue @()
        }
        $package.provides = @($Claims.Package.provides | Where-Object { $_ } | Select-Object -Unique)
    }
    $package | Add-Member -NotePropertyName _identity -NotePropertyValue ([string]$Claims[0].Identity)
    $package | Add-Member -NotePropertyName _refs -NotePropertyValue @($Claims.Ref | Select-Object -Unique)
    $package | Add-Member -NotePropertyName _claims -NotePropertyValue @($Claims.ProfileName | Select-Object -Unique)
    $package | Add-Member -NotePropertyName _defaultSelected -NotePropertyValue (@($Claims | Where-Object DefaultSelected).Count -gt 0)
    $package | Add-Member -NotePropertyName _profileGroups -NotePropertyValue @($Claims.Groups | Select-Object -Unique)
    $package | Add-Member -NotePropertyName _runtime -NotePropertyValue (@($Claims | Where-Object Runtime).Count -gt 0)
    return $package
}

function Resolve-ProfileDefinitions {
    param(
        $Config,
        [hashtable]$Overrides = @{}
    )
    $claims = @()
    $profileNames = @("winenv-runtime")
    $scoopBuckets = @()
    $defaultProfiles = @()

    $runtimeProfile = Read-ProfileFile $ProfilePath
    Assert-ProfileDefinition $runtimeProfile
    $runtimeEntry = [pscustomobject]@{ id = "runtime"; name = $runtimeProfile.name }
    $claims += @($runtimeProfile.packages | ForEach-Object { New-PackageClaim $_ $runtimeEntry $runtimeProfile -Runtime })
    $scoopBuckets += @($runtimeProfile.scoopBuckets)
    $defaultProfiles += @($runtimeProfile.defaultProfiles | ForEach-Object { "runtime/$_" })

    foreach ($entry in @($Config.profiles | Where-Object enabled)) {
        $profile = if ($Overrides.ContainsKey([string]$entry.id)) {
            $Overrides[[string]$entry.id]
        } else {
            Read-ProfileFile (Get-ProfileSnapshotPath $entry)
        }
        Assert-ProfileDefinition $profile
        $profileNames += [string]$entry.name
        $claims += @($profile.packages | ForEach-Object { New-PackageClaim $_ $entry $profile })
        $scoopBuckets += @($profile.scoopBuckets)
        $defaultProfiles += @($profile.defaultProfiles | ForEach-Object { "$($entry.id)/$_" })
    }

    $conflicts = @()
    $packages = @()
    foreach ($identityGroup in @($claims | Group-Object Identity)) {
        $signatureGroups = @($identityGroup.Group | Group-Object Signature | ForEach-Object {
            [pscustomobject]@{ Claims = @($_.Group); Package = $_.Group[0].Package }
        })
        $selectedGroup = if ($signatureGroups.Count -eq 1) {
            $signatureGroups[0]
        } else {
            Get-ResolutionSelection $Config "package:$($identityGroup.Name)" $signatureGroups
        }
        if ($null -eq $selectedGroup) {
            $conflicts += [pscustomobject]@{
                Key = "package:$($identityGroup.Name)"
                Label = "Different versions or options for $($identityGroup.Group[0].Package.displayName)"
                Candidates = $signatureGroups
            }
            continue
        }
        $packages += Merge-PackageClaims $selectedGroup.Claims
    }

    $losingIdentities = @{}
    $capabilities = @()
    foreach ($package in $packages) {
        foreach ($command in @($package.commands)) {
            if ($command) { $capabilities += [pscustomobject]@{ Token = "cmd:$([string]$command)".ToLowerInvariant(); Package = $package } }
        }
        foreach ($provided in @($package.provides)) {
            if ($provided) { $capabilities += [pscustomobject]@{ Token = ([string]$provided).ToLowerInvariant(); Package = $package } }
        }
    }
    foreach ($capabilityGroup in @($capabilities | Group-Object Token)) {
        $candidatePackages = @($capabilityGroup.Group.Package |
            Where-Object { -not $losingIdentities.ContainsKey($_._identity) } |
            Sort-Object _identity -Unique)
        if ($candidatePackages.Count -lt 2) { continue }
        $candidateGroups = @($candidatePackages | ForEach-Object {
            $candidate = $_
            [pscustomobject]@{
                Claims = @($candidate._refs | ForEach-Object {
                    $ref = $_
                    [pscustomobject]@{ Ref = $ref; Runtime = [bool]$candidate._runtime }
                })
                Package = $candidate
            }
        })
        $selectedGroup = Get-ResolutionSelection $Config "capability:$($capabilityGroup.Name)" $candidateGroups
        if ($null -eq $selectedGroup) {
            $conflicts += [pscustomobject]@{
                Key = "capability:$($capabilityGroup.Name)"
                Label = "Multiple packages provide $($capabilityGroup.Name)"
                Candidates = $candidateGroups
            }
            continue
        }
        foreach ($candidate in $candidatePackages) {
            if ($candidate._identity -ne $selectedGroup.Package._identity) {
                $losingIdentities[$candidate._identity] = $true
            }
        }
    }

    $effectivePackages = @($packages | Where-Object { -not $losingIdentities.ContainsKey($_._identity) })
    return [pscustomobject]@{
        Definition = [pscustomobject]@{
            schemaVersion = 1
            name = ($profileNames -join " + ")
            defaultProfiles = @($defaultProfiles | Select-Object -Unique)
            scoopBuckets = @(Merge-ScoopBucketDefinitions $scoopBuckets)
            packages = $effectivePackages
        }
        Conflicts = @($conflicts)
    }
}

function Set-ConflictResolution {
    param(
        $Config,
        [string]$Key,
        [string]$Selected
    )
    $Config.resolutions = @($Config.resolutions | Where-Object { $_.key -ne $Key }) + @([pscustomobject]@{
        key = $Key
        selected = $Selected
        updatedAt = [DateTime]::UtcNow.ToString("o")
    })
}

function Resolve-ProfileConflicts {
    param(
        $Config,
        $Result,
        [hashtable]$Overrides = @{}
    )
    while (@($Result.Conflicts).Count -gt 0) {
        $conflict = @($Result.Conflicts)[0]
        Write-Step "Profile conflict"
        Write-WinenvHost $conflict.Label -ForegroundColor Yellow
        $candidates = @($conflict.Candidates)
        for ($index = 0; $index -lt $candidates.Count; $index++) {
            $candidate = $candidates[$index]
            $claims = @($candidate.Claims | ForEach-Object { ($_.Ref -split "/", 2)[0] } | Select-Object -Unique) -join ", "
            $version = if ($candidate.Package.version) { " @$($candidate.Package.version)" } else { "" }
            Write-WinenvHost ("  [{0}] {1}: {2}/{3}{4}" -f ($index + 1), $claims, $candidate.Package.owner, $candidate.Package.id, $version)
        }
        if ($DryRun -or $Yes) {
            throw "Profile conflicts require an explicit interactive choice; no profile was changed."
        }
        $answer = Read-WinenvHost "Choose the package to keep [1-$($candidates.Count)]"
        $selectedIndex = 0
        if (-not [int]::TryParse($answer, [ref]$selectedIndex) -or $selectedIndex -lt 1 -or $selectedIndex -gt $candidates.Count) {
            throw "Profile activation cancelled because no valid conflict choice was made."
        }
        $selectedToken = Get-CandidateSelectionToken $candidates[$selectedIndex - 1]
        Set-ConflictResolution $Config $conflict.Key $selectedToken
        $Result = Resolve-ProfileDefinitions $Config $Overrides
    }
    return $Result
}

function Read-ProfileDefinition {
    Initialize-ProfileRegistry
    $config = Read-WinenvConfig
    $result = Resolve-ProfileDefinitions $config
    if (@($result.Conflicts).Count -gt 0) {
        $labels = @($result.Conflicts.Label) -join "; "
        throw "Unresolved profile conflicts: $labels. Re-import the affected profile with 'win use'."
    }
    return $result.Definition
}

function Show-UserProfileStatus {
    Initialize-ProfileRegistry
    $config = Read-WinenvConfig
    Write-WinenvHost "Runtime profile: $ProfilePath"
    $entries = @($config.profiles)
    if ($entries.Count -eq 0) {
        Write-WinenvHost "User profiles:   none (runtime only)"
    } else {
        Write-WinenvHost "`nUser profiles"
        $entries |
            Select-Object @{Name = "status"; Expression = { if ($_.enabled) { "on" } else { "off" } }}, id, name,
                @{Name = "type"; Expression = { $_.sourceType }},
                @{Name = "source"; Expression = { ([string]$_.source) -replace "^(url|file):", "" }} |
            Format-WinenvTable -AutoSize
    }
    Write-WinenvHost "`nUse 'win use <file-or-https-url>' to add or refresh one; use 'win off <name-or-id>' to disable it." -ForegroundColor DarkGray
}

function Set-UserProfile {
    param([switch]$Apply)

    if ([string]::IsNullOrWhiteSpace($Target)) {
        Show-UserProfileStatus
        return
    }
    if ($Target -in @("default", "none", "off")) {
        Disable-UserProfile -AllowAliasTarget
        return
    }

    Initialize-ProfileRegistry
    $config = Read-WinenvConfig
    $savedEntry = $null
    $looksLikeUri = $Target -match "^[a-zA-Z][a-zA-Z0-9+.-]*://"
    if (-not $looksLikeUri -and -not (Test-Path -LiteralPath $Target -PathType Leaf)) {
        $savedMatches = @($config.profiles | Where-Object { $_.id -eq $Target -or $_.name -eq $Target })
        if ($savedMatches.Count -gt 1) {
            throw "More than one saved profile is named '$Target'. Use an ID: $(@($savedMatches.id) -join ', ')"
        }
        if ($savedMatches.Count -eq 1) { $savedEntry = $savedMatches[0] }
    }
    $source = if ($null -ne $savedEntry) {
        $savedPath = Get-ProfileSnapshotPath $savedEntry
        [pscustomobject]@{
            Text = Get-Content -Raw -Encoding UTF8 -Path $savedPath
            Label = "saved snapshot $($savedEntry.id)"
            Key = [string]$savedEntry.source
            Type = [string]$savedEntry.sourceType
        }
    } else {
        Read-UserProfileSource $Target
    }
    $userProfile = ConvertFrom-ProfileText $source.Text $source.Label
    Assert-ProfileDefinition $userProfile

    $nextConfig = Copy-WinenvConfig $config
    $existing = if ($null -ne $savedEntry) {
        @($nextConfig.profiles | Where-Object { $_.id -eq $savedEntry.id } | Select-Object -First 1)
    } else {
        @($nextConfig.profiles | Where-Object { $_.source -eq $source.Key } | Select-Object -First 1)
    }
    $now = [DateTime]::UtcNow.ToString("o")
    if ($existing.Count -gt 0) {
        $entry = $existing[0]
        $entry.name = [string]$userProfile.name
        $entry.sourceType = [string]$source.Type
        $entry.hash = Get-TextHash $source.Text
        $entry.enabled = $true
        $entry.updatedAt = $now
    } else {
        $id = Get-ProfileId ([string]$userProfile.name) ([string]$source.Key)
        $entry = [pscustomobject]@{
            id = $id
            name = [string]$userProfile.name
            source = [string]$source.Key
            sourceType = [string]$source.Type
            fileName = "$id.json"
            hash = Get-TextHash $source.Text
            enabled = $true
            addedAt = $now
            updatedAt = $now
        }
        $nextConfig.profiles = @($nextConfig.profiles) + @($entry)
    }

    $overrides = @{ ([string]$entry.id) = $userProfile }
    $resolved = Resolve-ProfileDefinitions $nextConfig $overrides
    $resolved = Resolve-ProfileConflicts $nextConfig $resolved $overrides
    $definition = $resolved.Definition
    $selectedPackages = @(Get-DefaultPackages $definition)
    $customBuckets = @($definition.scoopBuckets | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Url) })

    if ($Apply) {
        Write-Step "Profile preview"
        Write-WinenvHost "Name:    $($userProfile.name)"
        Write-WinenvHost "ID:      $($entry.id)"
        Write-WinenvHost "Source:  $($source.Label)"
        Write-WinenvHost "Active:  $(@($nextConfig.profiles | Where-Object enabled).Count) user profile(s)"
        Write-WinenvHost "Install: $($selectedPackages.Count) package(s) selected by all active defaults"
        $selectedPackages |
            Select-Object displayName, owner, id, @{Name = "claims"; Expression = { @($_._claims) -join "," }} |
            Sort-Object owner, displayName |
            Format-WinenvTable -AutoSize
        if ($customBuckets.Count -gt 0) {
            Write-WinenvHost "`nThird-party Scoop buckets" -ForegroundColor Yellow
            $customBuckets | Select-Object Name, Url | Format-WinenvTable -AutoSize
            Write-WinenvHost "Their manifests can execute installation scripts. Only continue if you trust these publishers." -ForegroundColor Yellow
        }
        $confirmationPrompt = if ($customBuckets.Count -gt 0) {
            "Trust the listed bucket sources, save this profile snapshot, and install the packages shown above?"
        } else {
            "Save this profile snapshot and install the packages shown above?"
        }
        if (-not (Confirm-Operation $confirmationPrompt)) {
            Write-WinenvHost "Profile activation cancelled."
            return
        }
        Assert-UnattendedScoopBucketTrust $customBuckets
        if (-not $DryRun -and -not $Yes) {
            foreach ($bucket in $customBuckets) {
                $ApprovedScoopBucketSources[(Get-ScoopBucketApprovalKey $bucket)] = $true
            }
        }
    }

    $snapshotPath = Get-ProfileSnapshotPath $entry
    Write-Plan "Save an independent snapshot to $snapshotPath"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $ProfilesRoot -Force | Out-Null
        Set-Content -Path $snapshotPath -Value $source.Text -Encoding UTF8
    }
    Write-WinenvConfig $nextConfig
    Sync-WinenvMiseConfig $definition

    if (-not $Apply) {
        Write-WinenvHost "Profile '$($userProfile.name)' is active. Run 'win add' to install all active defaults." -ForegroundColor Green
        return
    }

    Install-Packages $definition $selectedPackages -ProfileManagedMise
    Invoke-Migrations
    Write-WinenvHost "`nProfile '$($userProfile.name)' is active and installed." -ForegroundColor Green
}

function Disable-UserProfile {
    param([switch]$AllowAliasTarget)

    Initialize-ProfileRegistry
    $config = Read-WinenvConfig
    $enabled = @($config.profiles | Where-Object enabled)
    if ($enabled.Count -eq 0) {
        $runtimeOnly = Resolve-ProfileDefinitions $config
        Sync-WinenvMiseConfig $runtimeOnly.Definition
        Write-WinenvHost "No user profile is active; the runtime profile is unchanged."
        return
    }

    $requested = if ($AllowAliasTarget) { "" } else { [string]$Target }
    if ([string]::IsNullOrWhiteSpace($requested)) {
        if ($enabled.Count -eq 1) {
            $entry = $enabled[0]
        } else {
            if ($Yes -or $DryRun) {
                throw "More than one profile is active. Specify one: win off <name-or-id>"
            }
            Write-WinenvHost "Active profiles"
            $enabled | Select-Object id, name, source | Format-WinenvTable -AutoSize
            $requested = Read-WinenvHost "Profile name or ID to disable"
        }
    }
    if ($null -eq $entry) {
        $matches = @($enabled | Where-Object { $_.id -eq $requested -or $_.name -eq $requested -or $_.source -eq $requested })
        if ($matches.Count -eq 0) { throw "No active profile matched '$requested'. Run 'win use' to list profiles." }
        if ($matches.Count -gt 1) {
            $ids = @($matches.id) -join ", "
            throw "More than one active profile is named '$requested'. Use an ID: $ids"
        }
        $entry = $matches[0]
    }

    $before = Resolve-ProfileDefinitions $config
    if (@($before.Conflicts).Count -gt 0) { throw "Active profile conflicts must be resolved with 'win use' before disabling a profile." }
    $nextConfig = Copy-WinenvConfig $config
    $nextEntry = @($nextConfig.profiles | Where-Object id -eq $entry.id)[0]
    $nextEntry.enabled = $false
    $nextEntry.updatedAt = [DateTime]::UtcNow.ToString("o")
    $after = Resolve-ProfileDefinitions $nextConfig
    $after = Resolve-ProfileConflicts $nextConfig $after

    $profile = Read-ProfileFile (Get-ProfileSnapshotPath $entry)
    $afterSignatures = @{}
    foreach ($package in @($after.Definition.packages)) { $afterSignatures[(Get-PackageSpecSignature $package)] = $true }
    $retained = @()
    $unclaimed = @()
    foreach ($package in @($profile.packages)) {
        if ($afterSignatures.ContainsKey((Get-PackageSpecSignature $package))) { $retained += $package } else { $unclaimed += $package }
    }

    Write-Step "Disable profile"
    Write-WinenvHost "Name:       $($entry.name)"
    Write-WinenvHost "Retained:   $(@($retained).Count) package claim(s) still referenced by another active profile"
    Write-WinenvHost "Unclaimed:  $(@($unclaimed).Count) package specification(s) no longer referenced"
    if (@($unclaimed).Count -gt 0) {
        $unclaimed | Select-Object displayName, owner, id | Format-WinenvTable -AutoSize
    }

    Write-WinenvConfig $nextConfig
    Sync-WinenvMiseConfig $after.Definition
    if ($DryRun) {
        Write-WinenvHost "Profile '$($entry.name)' would be disabled; no installed software would be changed, and its snapshot would be kept."
    } else {
        Write-WinenvHost "Profile '$($entry.name)' disabled; no installed software was changed, and its snapshot was kept." -ForegroundColor Green
    }
}

function Get-SelectedProfiles {
    param($Definition)
    if ($Profiles -and $Profiles.Count -gt 0) {
        return @($Profiles)
    }
    return @($Definition.defaultProfiles)
}

function Get-DefaultPackages {
    param($Definition)
    return @($Definition.packages | Where-Object {
        if ($_.psobject.Properties.Name -contains "_defaultSelected") { return [bool]$_._defaultSelected }
        $packageProfiles = @($_.profiles)
        @($packageProfiles | Where-Object { @($Definition.defaultProfiles) -contains $_ }).Count -gt 0
    })
}

function Get-SelectedPackages {
    param($Definition)
    if (-not $Profiles -or $Profiles.Count -eq 0) {
        return @(Get-DefaultPackages $Definition)
    }
    $selectors = @($Profiles)
    return @($Definition.packages | Where-Object {
        $groups = if ($_.psobject.Properties.Name -contains "_profileGroups") { @($_._profileGroups) } else { @($_.profiles) }
        foreach ($selector in $selectors) {
            if ($groups -contains $selector) { return $true }
            if (-not $selector.Contains("/") -and @($groups | Where-Object { $_ -eq $selector -or $_.EndsWith("/$selector", [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                return $true
            }
        }
        return $false
    })
}

function Test-PackageMatch {
    param(
        $Package,
        [string]$Query
    )
    $searchable = @(
        [string]$Package.key,
        [string]$Package.displayName,
        [string]$Package.id,
        (@($Package.commands) -join " "),
        (@($Package.profiles) -join " "),
        (@($Package._refs) -join " "),
        (@($Package._claims) -join " ")
    ) -join " "
    return $searchable.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Assert-ProfileDefinition {
    param($Definition)
    $errors = New-Object System.Collections.Generic.List[string]
    $seenKeys = @{}
    $seenPackages = @{}
    $commandOwners = @{}

    $definitionProperties = @("`$schema", "schemaVersion", "name", "defaultProfiles", "scoopBuckets", "packages")
    $packageProperties = @("key", "displayName", "owner", "id", "source", "bucket", "version", "profiles", "commands", "provides", "instructions")
    $definitionPropertyNames = @($Definition.psobject.Properties.Name)
    $requiredDefinitionProperties = @("schemaVersion", "name", "defaultProfiles", "scoopBuckets", "packages")

    if ($Definition.schemaVersion -ne 1) { $errors.Add("schemaVersion must be 1") }
    if ([string]::IsNullOrWhiteSpace([string]$Definition.name)) { $errors.Add("name is required") }
    foreach ($property in $requiredDefinitionProperties) {
        if ($definitionPropertyNames -notcontains $property) { $errors.Add("Missing profile property: $property") }
    }
    foreach ($property in $definitionPropertyNames) {
        if ($definitionProperties -notcontains $property) { $errors.Add("Unsupported profile property: $property") }
    }
    foreach ($collectionName in @("defaultProfiles")) {
        $items = @($Definition.$collectionName)
        if (@($items | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
            $errors.Add("$collectionName contains an empty value")
        }
        if (@($items | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
            $errors.Add("$collectionName contains duplicate values")
        }
    }

    $seenBuckets = @{}
    foreach ($bucketValue in @($Definition.scoopBuckets)) {
        try {
            $bucket = ConvertTo-ScoopBucketDefinition $bucketValue
            $bucketKey = $bucket.Name.ToLowerInvariant()
            if ($seenBuckets.ContainsKey($bucketKey)) {
                $existing = $seenBuckets[$bucketKey]
                if ([string]$existing.Url -eq [string]$bucket.Url) {
                    $errors.Add("scoopBuckets contains duplicate bucket '$($bucket.Name)'")
                } else {
                    $errors.Add("scoopBuckets gives bucket '$($bucket.Name)' more than one source")
                }
            } else {
                $seenBuckets[$bucketKey] = $bucket
            }
        } catch {
            $errors.Add($_.Exception.Message)
        }
    }

    foreach ($package in @($Definition.packages)) {
        $key = [string]$package.key
        $owner = [string]$package.owner
        $id = [string]$package.id
        $packagePropertyNames = @($package.psobject.Properties.Name)
        foreach ($property in @("key", "displayName", "owner", "id", "profiles", "commands")) {
            if ($packagePropertyNames -notcontains $property) { $errors.Add("$key`: missing package property '$property'") }
        }
        foreach ($property in $packagePropertyNames) {
            if ($packageProperties -notcontains $property) { $errors.Add("$key`: unsupported package property '$property'") }
        }
        if ($key -notmatch "^[a-z0-9][a-z0-9-]*$") { $errors.Add("Invalid package key: '$key'") }
        if ([string]::IsNullOrWhiteSpace([string]$package.displayName)) { $errors.Add("$key`: displayName is required") }
        if ([string]::IsNullOrWhiteSpace($id)) { $errors.Add("$key`: id is required") }
        if ($AllowedOwners -notcontains $owner) {
            $errors.Add("$key`: unsupported owner '$owner'")
        }
        $packageProfiles = @($package.profiles)
        if ($packageProfiles.Count -eq 0 -or @($packageProfiles | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
            $errors.Add("$key`: at least one non-empty profile is required")
        }
        if (@($packageProfiles | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
            $errors.Add("$key`: profiles contains duplicate values")
        }
        $commands = @($package.commands)
        if (@($commands | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
            $errors.Add("$key`: commands contains an empty value")
        }
        if (@($commands | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
            $errors.Add("$key`: commands contains duplicate values")
        }
        $providedCapabilities = if ($packagePropertyNames -contains "provides") { @($package.provides) } else { @() }
        if (@($providedCapabilities | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -gt 0) {
            $errors.Add("$key`: provides contains an empty value")
        }
        if (@($providedCapabilities | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
            $errors.Add("$key`: provides contains duplicate values")
        }

        if (-not [string]::IsNullOrWhiteSpace($key)) {
            if ($seenKeys.ContainsKey($key)) {
                $errors.Add("Duplicate package key: $key")
            } else {
                $seenKeys[$key] = $true
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($owner) -and -not [string]::IsNullOrWhiteSpace($id)) {
            $identity = Get-PackageIdentity $package
            if ($seenPackages.ContainsKey($identity)) {
                $errors.Add("Duplicate managed package: $identity")
            } else {
                $seenPackages[$identity] = $true
            }
        }

        foreach ($command in $commands) {
            $normalizedCommand = ([string]$command).ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($normalizedCommand)) { continue }
            if ($commandOwners.ContainsKey($normalizedCommand) -and $commandOwners[$normalizedCommand] -ne $package.owner) {
                $errors.Add("Command '$command' has multiple owners: $($commandOwners[$normalizedCommand]) and $($package.owner)")
            } else {
                $commandOwners[$normalizedCommand] = $package.owner
            }
        }
    }

    if ($errors.Count -gt 0) {
        throw "Invalid profile:`n - $($errors -join "`n - ")"
    }
}

function Show-Profile {
    param($Definition)
    Show-UserProfileStatus
    Write-WinenvHost "`nEffective packages"
    Get-SelectedPackages $Definition |
        Sort-Object owner, key |
        Select-Object key, displayName,
            @{Name = "provider"; Expression = { if ([bool]$_._runtime) { "$($_.owner) (fallback)" } else { $_.owner } }}, id,
            @{Name = "claims"; Expression = { if ($_.psobject.Properties.Name -contains "_claims") { @($_._claims) -join "," } else { "runtime" } }} |
        Format-WinenvTable -AutoSize
}
