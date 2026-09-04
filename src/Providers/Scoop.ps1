# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function Get-NormalizedScoopBucketUrl {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) { return "" }
    try { $uri = [Uri]$Url } catch { throw "Invalid Scoop bucket URL: $Url" }
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne "https" -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        throw "Third-party Scoop bucket URLs must use HTTPS: $Url"
    }
    if (-not [string]::IsNullOrWhiteSpace($uri.UserInfo)) {
        throw "Scoop bucket URLs must not contain credentials: $Url"
    }
    if (-not [string]::IsNullOrWhiteSpace($uri.Query) -or -not [string]::IsNullOrWhiteSpace($uri.Fragment)) {
        throw "Scoop bucket URLs must not contain a query string or fragment: $Url"
    }
    return $uri.AbsoluteUri.TrimEnd("/")
}

function ConvertTo-ScoopBucketDefinition {
    param($Bucket)

    if ($Bucket -is [string]) {
        $name = $Bucket.Trim()
        $url = ""
    } else {
        $properties = @($Bucket.psobject.Properties.Name)
        foreach ($property in $properties) {
            if ($property -notin @("name", "url")) {
                throw "Unsupported Scoop bucket property: $property"
            }
        }
        if ($properties -notcontains "name" -or $properties -notcontains "url") {
            throw "A custom Scoop bucket requires both 'name' and 'url'."
        }
        $name = ([string]$Bucket.name).Trim()
        $url = Get-NormalizedScoopBucketUrl ([string]$Bucket.url)
    }
    if ($name -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]*$") {
        throw "Invalid Scoop bucket name: '$name'"
    }
    return [pscustomobject]@{ Name = $name; Url = $url }
}

function Merge-ScoopBucketDefinitions {
    param([array]$Buckets)

    $byName = @{}
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($bucketValue in @($Buckets)) {
        $bucket = ConvertTo-ScoopBucketDefinition $bucketValue
        $key = $bucket.Name.ToLowerInvariant()
        if (-not $byName.ContainsKey($key)) {
            $byName[$key] = $bucket
            $result.Add($bucket)
            continue
        }
        $existing = $byName[$key]
        if ([string]$existing.Url -ne [string]$bucket.Url) {
            $first = if ($existing.Url) { $existing.Url } else { "Scoop's known-bucket catalog" }
            $second = if ($bucket.Url) { $bucket.Url } else { "Scoop's known-bucket catalog" }
            throw "Scoop bucket '$($bucket.Name)' has conflicting sources: $first and $second"
        }
    }
    return @($result | ForEach-Object { $_ })
}

function Get-ScoopCandidates {
    param(
        [string]$Query,
        [switch]$Installed
    )
    if (-not (Test-Command "scoop")) { return @() }

    $arguments = if ($Installed) { @("list") } else { @("search", $Query) }
    $result = Invoke-CapturedCommand "scoop" $arguments
    if ($result.ExitCode -ne 0) { return @() }
    $objectRows = @($result.Lines | Where-Object {
        $null -ne $_ -and $_ -isnot [string] -and $_.psobject.Properties.Name -contains "Name"
    })
    if ($objectRows.Count -gt 0) {
        return @($objectRows | ForEach-Object {
            $id = [string]$_.Name
            $source = if ($_.Source) { [string]$_.Source } else { "main" }
            if ([string]::IsNullOrWhiteSpace($Query) -or $id.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                New-PackageCandidate -ManagerName "scoop" -Id $id -Name $id -Version $_.Version -Source $source
            }
        })
    }

    return @(ConvertFrom-FixedWidthTable $result.Lines | ForEach-Object {
            $values = @($_)
            $id = [string]$values[0]
            $source = if ($values.Count -ge 3 -and $values[2]) { [string]$values[2] } else { "main" }
            if ([string]::IsNullOrWhiteSpace($Query) -or $id.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                New-PackageCandidate -ManagerName "scoop" -Id $id -Name $id -Version $values[1] -Source $source
            }
        })
}

function Get-ScoopKnownBucketNames {
    if (-not (Test-Command "scoop")) { return @("main") }
    $result = Invoke-CapturedCommand "scoop" @("bucket", "known")
    if ($result.ExitCode -ne 0) { return @("main") }
    $names = @($result.Lines | Where-Object {
        $_ -isnot [string] -and @($_.psobject.Properties.Name) -contains "Name"
    } | ForEach-Object { [string]$_.Name })
    if ($names.Count -eq 0) {
        $names = @(ConvertFrom-FixedWidthTable @($result.Lines | ForEach-Object { [string]$_ }) | ForEach-Object { [string]$_[0] })
    }
    return @(@("main") + $names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function Get-AdoptedScoopBuckets {
    param([array]$Candidates)
    $names = @($Candidates | Where-Object Manager -eq "scoop" | ForEach-Object Source | Where-Object { $_ } | Select-Object -Unique)
    if ($names.Count -eq 0) { return @() }

    $knownNames = @(Get-ScoopKnownBucketNames)
    $enabled = @()
    if (Test-Command "scoop") {
        try { $enabled = @(Get-ScoopBucketInventory "scoop") } catch { $enabled = @() }
    }
    $buckets = @()
    foreach ($name in $names) {
        if (@($knownNames | Where-Object { $_.Equals([string]$name, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
            $buckets += [string]$name
            continue
        }
        $match = @($enabled | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
        if ($match.Count -gt 0 -and ([string]$match[0].Source) -match "^https://") {
            $buckets += ,[pscustomobject]@{ name = [string]$name; url = (Get-NormalizedScoopBucketUrl ([string]$match[0].Source)) }
        } else {
            Write-WinenvHost "Could not resolve the source URL for Scoop bucket '$name'; it will be kept by name." -ForegroundColor Yellow
            $buckets += [string]$name
        }
    }
    return @($buckets)
}

function ConvertTo-StoredScoopBuckets {
    param([array]$Buckets)
    return @(Merge-ScoopBucketDefinitions $Buckets | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace([string]$_.Url)) {
            [string]$_.Name
        } else {
            [pscustomobject]@{ name = [string]$_.Name; url = [string]$_.Url }
        }
    })
}

function Ensure-Scoop {
    $probe = Get-ManagerProbe "scoop"
    if ($probe.Status -eq "available") {
        $ResolvedManagerCommands["scoop"] = $probe.Path
        return
    }
    if ($probe.Status -eq "broken") {
        throw "Scoop exists at $($probe.Path), but 'scoop --version' failed. Fix or remove that installation before continuing."
    }

    Write-Step "Preparing the official Scoop installer"
    $installerUri = "https://get.scoop.sh"
    if ($DryRun) {
        Write-Plan "Download and review $installerUri, then execute after confirmation"
        return
    }

    if ($PSVersionTable.PSVersion -lt [Version]"5.1") {
        throw "Scoop requires PowerShell 5.1 or newer."
    }
    if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
        throw "Scoop requires PowerShell FullLanguage mode; the current mode is $($ExecutionContext.SessionState.LanguageMode)."
    }
    $executionPolicy = Get-ExecutionPolicy
    if ($executionPolicy -notin @("RemoteSigned", "Unrestricted", "Bypass")) {
        throw "Scoop requires an executable script policy. Review it, then run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser"
    }
    if (Test-IsWindowsPlatform) {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw "Scoop's normal installer is for a non-admin PowerShell window. Close this elevated window and run Winenv again normally."
        }
    }

    $installerText = Invoke-RestMethod -Uri $installerUri
    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$installerText)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "")
    } finally {
        $sha256.Dispose()
    }

    Write-WinenvHost "Source: $installerUri"
    Write-WinenvHost "SHA-256: $hash"
    if (-not (Confirm-Operation "Execute this Scoop installer for the current user?")) {
        throw "Scoop installation was cancelled."
    }

    Invoke-Expression ([string]$installerText)
    Refresh-ProcessPath
    $probe = Get-ManagerProbe "scoop"
    if ($probe.Status -ne "available") {
        throw "Scoop was installed but is not visible in this process. Open a new PowerShell window and run the command again."
    }
    $ResolvedManagerCommands["scoop"] = $probe.Path
}

function Get-ScoopBucketInventory {
    param([string]$Command = (Get-ResolvedManagerCommand "scoop"))

    $result = Invoke-CapturedCommand $Command @("bucket", "list")
    if ($result.ExitCode -eq 2) { return @() }
    if ($null -ne $result.ExitCode -and $result.ExitCode -ne 0) {
        throw "Unable to read the enabled Scoop buckets."
    }

    $objectRows = @($result.Lines | Where-Object {
        $_ -isnot [string] -and @($_.psobject.Properties.Name) -contains "Name"
    })
    if ($objectRows.Count -gt 0) {
        return @($objectRows | ForEach-Object {
            [pscustomobject]@{
                Name = [string]$_.Name
                Source = if (@($_.psobject.Properties.Name) -contains "Source") { [string]$_.Source } else { "" }
            }
        })
    }

    return @(ConvertFrom-FixedWidthTable @($result.Lines | ForEach-Object { [string]$_ }) | ForEach-Object {
        [pscustomobject]@{ Name = [string]$_[0]; Source = [string]$_[1] }
    })
}

function Test-ScoopBucketSourceMatch {
    param(
        [string]$Actual,
        [string]$Expected
    )
    if ([string]::IsNullOrWhiteSpace($Actual)) { return $false }
    try {
        $actualUri = [Uri]$Actual
        $actualValue = $actualUri.AbsoluteUri.TrimEnd("/")
    } catch {
        $actualValue = $Actual.Trim().TrimEnd("/")
    }
    return $actualValue.Equals($Expected, [StringComparison]::OrdinalIgnoreCase)
}

function Get-ScoopBucketApprovalKey {
    param($Bucket)
    return "$($Bucket.Name.ToLowerInvariant())|$($Bucket.Url)"
}

function Ensure-ScoopGit {
    if (@(Get-ExternalCommandCandidates "git").Count -gt 0) { return }
    Write-Step "Installing Git for Scoop buckets"
    Invoke-Native (Get-ResolvedManagerCommand "scoop") @("install", "git")
    if ($DryRun) { return }
    Refresh-ProcessPath
    if (@(Get-ExternalCommandCandidates "git").Count -eq 0) {
        throw "Git was installed with Scoop but is not visible in this process. Open a new PowerShell window and run the command again."
    }
}

function Ensure-ScoopBucket {
    param($BucketValue)

    $bucket = ConvertTo-ScoopBucketDefinition $BucketValue
    $arguments = @("bucket", "add", $bucket.Name)
    if ($bucket.Url) { $arguments += $bucket.Url }
    if ($DryRun) {
        if ($bucket.Url) {
            Write-WinenvHost "Third-party Scoop bucket: $($bucket.Name)" -ForegroundColor Yellow
            Write-WinenvHost "Source: $($bucket.Url)"
            Write-WinenvHost "Its manifests may execute installation scripts. Review and trust the publisher before adding it." -ForegroundColor Yellow
        }
        Ensure-ScoopGit
        Invoke-Native (Get-ResolvedManagerCommand "scoop") $arguments
        return
    }

    $inventory = @(Get-ScoopBucketInventory)
    $matches = @($inventory | Where-Object { $_.Name -eq $bucket.Name })
    if (-not $bucket.Url) {
        if ($matches.Count -eq 0) {
            Ensure-ScoopGit
            Invoke-Native (Get-ResolvedManagerCommand "scoop") $arguments
        }
        return
    }

    if ($matches.Count -gt 0 -and (Test-ScoopBucketSourceMatch $matches[0].Source $bucket.Url)) { return }

    $approvalKey = Get-ScoopBucketApprovalKey $bucket
    if (-not $ApprovedScoopBucketSources.ContainsKey($approvalKey)) {
        Write-Step "Trust a third-party Scoop bucket"
        Write-WinenvHost "Name:   $($bucket.Name)"
        Write-WinenvHost "Source: $($bucket.Url)"
        if ($matches.Count -gt 0) { Write-WinenvHost "Current source: $($matches[0].Source)" }
        Write-WinenvHost "Scoop manifests can execute installation scripts. Only continue if you trust this publisher." -ForegroundColor Yellow
        if ($Yes) {
            throw "A new or changed third-party Scoop bucket requires explicit interactive trust; nothing was changed."
        }
        if (-not (Confirm-Operation "Trust this bucket source?")) {
            throw "Scoop bucket trust was not granted; nothing was changed."
        }
        $ApprovedScoopBucketSources[$approvalKey] = $true
    }

    Ensure-ScoopGit
    if ($matches.Count -gt 0) {
        Invoke-Native (Get-ResolvedManagerCommand "scoop") @("bucket", "rm", $bucket.Name)
    }
    Invoke-Native (Get-ResolvedManagerCommand "scoop") $arguments
}

function Assert-UnattendedScoopBucketTrust {
    param([array]$Buckets)

    $customBuckets = @($Buckets | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Url) })
    if ($customBuckets.Count -eq 0 -or $DryRun -or -not $Yes) { return }
    $scoopCommand = Get-OptionalManagerCommand "scoop"
    if ($null -eq $scoopCommand) {
        throw "A third-party Scoop bucket requires explicit interactive trust before this profile can be saved; run the command again without -y."
    }
    $inventory = @(Get-ScoopBucketInventory $scoopCommand)
    foreach ($bucket in $customBuckets) {
        $matches = @($inventory | Where-Object { $_.Name -eq $bucket.Name })
        if ($matches.Count -eq 0 -or -not (Test-ScoopBucketSourceMatch $matches[0].Source $bucket.Url)) {
            throw "Scoop bucket '$($bucket.Name)' is new or has a different source and requires explicit interactive trust; run the command again without -y."
        }
    }
}

function Invoke-ScoopBucketCommand {
    if ([string]::IsNullOrWhiteSpace($Target)) {
        $scoopCommand = Get-OptionalManagerCommand "scoop"
        if ($null -eq $scoopCommand) {
            Write-WinenvHost "Scoop is not installed. Add a bucket with: win bucket <name> [https-url]" -ForegroundColor Yellow
            return
        }
        $inventory = @(Get-ScoopBucketInventory $scoopCommand)
        Write-Step "Enabled Scoop buckets"
        if ($inventory.Count -eq 0) {
            Write-WinenvHost "No Scoop buckets are enabled. Add the default source with: win bucket main"
        } else {
            $inventory | Format-WinenvTable Name, Source -AutoSize
        }
        return
    }

    $bucketValue = if ([string]::IsNullOrWhiteSpace($Location)) {
        [string]$Target
    } else {
        [pscustomobject]@{ name = [string]$Target; url = [string]$Location }
    }
    $bucket = ConvertTo-ScoopBucketDefinition $bucketValue
    Assert-UnattendedScoopBucketTrust @($bucket)
    Ensure-Scoop
    Ensure-ScoopBucket $bucket
    if (-not $DryRun) { Write-WinenvHost "Scoop bucket '$($bucket.Name)' is ready." -ForegroundColor Green }
}

function Test-ScoopManifestReference {
    param([string]$Reference)

    if (Test-Path -LiteralPath $Reference -PathType Leaf) {
        return [IO.Path]::GetExtension($Reference).Equals(".json", [StringComparison]::OrdinalIgnoreCase)
    }
    if ($Reference -notmatch "^[a-zA-Z][a-zA-Z0-9+.-]*://" -and [IO.Path]::GetExtension($Reference).Equals(".json", [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    try { $uri = [Uri]$Reference } catch { return $false }
    return $uri.IsAbsoluteUri -and [IO.Path]::GetExtension($uri.AbsolutePath).Equals(".json", [StringComparison]::OrdinalIgnoreCase)
}

function Get-SafeUriDisplay {
    param([Uri]$Uri)
    $builder = [UriBuilder]$Uri
    $builder.UserName = ""
    $builder.Password = ""
    $builder.Query = ""
    $builder.Fragment = ""
    return $builder.Uri.AbsoluteUri
}

function Install-ScoopManifest {
    param([string]$Reference)

    $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-manifest-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    try {
        $isLocalFile = Test-Path -LiteralPath $Reference -PathType Leaf
        $isUri = $false
        if (-not $isLocalFile) {
            try {
                $uri = [Uri]$Reference
                $isUri = $uri.IsAbsoluteUri
            } catch { $isUri = $false }
        }

        if ($isUri) {
            if ($uri.Scheme -ne "https" -or [string]::IsNullOrWhiteSpace($uri.Host)) { throw "Remote Scoop manifests must use HTTPS: $Reference" }
            if (-not [string]::IsNullOrWhiteSpace($uri.UserInfo)) { throw "Scoop manifest URLs must not contain credentials." }
            if (-not [IO.Path]::GetExtension($uri.AbsolutePath).Equals(".json", [StringComparison]::OrdinalIgnoreCase)) {
                throw "A Scoop manifest URL must end in .json."
            }
            Write-Step "Downloading Scoop manifest"
            $response = Invoke-WebRequest -Uri $Reference -UseBasicParsing -Headers @{
                "Accept" = "application/json"
                "User-Agent" = "winenv"
            }
            $finalUri = $null
            if ($null -ne $response.BaseResponse) {
                if ($null -ne $response.BaseResponse.RequestMessage) {
                    $finalUri = $response.BaseResponse.RequestMessage.RequestUri
                } elseif ($null -ne $response.BaseResponse.ResponseUri) {
                    $finalUri = $response.BaseResponse.ResponseUri
                }
            }
            if ($null -ne $finalUri -and $finalUri.Scheme -ne "https") {
                throw "The Scoop manifest download redirected away from HTTPS: $(Get-SafeUriDisplay $finalUri)"
            }
            $text = if ($response.Content -is [byte[]]) {
                [Text.Encoding]::UTF8.GetString($response.Content)
            } else {
                [string]$response.Content
            }
            if ([Text.Encoding]::UTF8.GetByteCount($text) -gt 1MB) {
                throw "Scoop manifest is larger than 1 MiB."
            }
            $fileName = [Uri]::UnescapeDataString([IO.Path]::GetFileName($uri.AbsolutePath))
            foreach ($invalidCharacter in [IO.Path]::GetInvalidFileNameChars()) {
                $fileName = $fileName.Replace([string]$invalidCharacter, "_")
            }
            $snapshotPath = Join-Path $temporaryRoot $fileName
            [IO.File]::WriteAllText($snapshotPath, $text, (New-Object Text.UTF8Encoding($false)))
            $sourceLabel = Get-SafeUriDisplay $uri
        } else {
            if (-not $isLocalFile) { throw "Scoop manifest was not found: $Reference" }
            if (-not [IO.Path]::GetExtension($Reference).Equals(".json", [StringComparison]::OrdinalIgnoreCase)) {
                throw "A Scoop manifest file must end in .json."
            }
            $sourcePath = (Resolve-Path -LiteralPath $Reference).Path
            if ((Get-Item -LiteralPath $sourcePath).Length -gt 1MB) { throw "Scoop manifest is larger than 1 MiB." }
            $snapshotPath = Join-Path $temporaryRoot ([IO.Path]::GetFileName($sourcePath))
            Copy-Item -LiteralPath $sourcePath -Destination $snapshotPath
            $sourceLabel = $sourcePath
        }

        try { $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $snapshotPath | ConvertFrom-Json -ErrorAction Stop } catch {
            throw "Scoop manifest is not valid JSON: $sourceLabel"
        }
        if ($manifest -isnot [pscustomobject]) { throw "Scoop manifest root must be a JSON object: $sourceLabel" }
        $manifestProperties = @($manifest.psobject.Properties.Name)
        if ($manifestProperties -contains "schemaVersion" -and $manifestProperties -contains "packages") {
            throw "This is a Winenv profile, not a Scoop manifest. Import it with 'win use'."
        }

        Write-Step "Scoop manifest preview"
        Write-WinenvHost "Source:      $sourceLabel"
        Write-WinenvHost "Manifest:    $([IO.Path]::GetFileName($snapshotPath))"
        if ($manifestProperties -contains "version") { Write-WinenvHost "Version:     $($manifest.version)" }
        if ($manifestProperties -contains "homepage") { Write-WinenvHost "Homepage:    $($manifest.homepage)" }
        if ($manifestProperties -contains "description") { Write-WinenvHost "Description: $($manifest.description)" }
        Write-WinenvHost "SHA-256:     $((Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash.ToLowerInvariant())"
        Write-WinenvHost "Scoop manifests can execute installation scripts. Review the source and hash before continuing." -ForegroundColor Yellow
        if (-not (Confirm-Operation "Install this Scoop manifest?")) {
            Write-WinenvHost "Manifest installation cancelled."
            return
        }

        Ensure-Scoop
        Invoke-Native (Get-ResolvedManagerCommand "scoop") @("install", $snapshotPath)
    } finally {
        if (Test-Path -LiteralPath $temporaryRoot) {
            Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
        }
    }
}

function Invoke-ScoopProviderInstall {
    param($Package, $Context)
    $qualifiedId = if ($Package.bucket) { "$($Package.bucket)/$($Package.id)" } else { [string]$Package.id }
    Invoke-Native (Get-ResolvedManagerCommand "scoop") @("install", $qualifiedId)
}

function Invoke-ScoopProviderRemove {
    param($Package, $Context)
    $managerCommand = Get-OptionalManagerCommand "scoop"
    if ($null -eq $managerCommand) { throw "Scoop is unavailable." }
    Invoke-Native $managerCommand @("uninstall", [string]$Package.id)
}
