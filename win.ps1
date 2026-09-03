[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Action = "",

    [Alias("P")]
    [string[]]$Profiles,
    [Parameter(Position = 1)]
    [Alias("PackageKey", "Query")]
    [string]$Target,
    [Parameter(Position = 2)]
    [Alias("Url")]
    [string]$Location,
    [Alias("Args")]
    [string[]]$InstallerArguments,
    [Alias("Hash")]
    [string]$Sha256,
    [Alias("From")]
    [ValidateSet("all", "managed", "winget", "scoop", "mise")]
    [string]$Manager = "all",
    [Alias("n")]
    [switch]$DryRun,
    [Alias("y")]
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$HasInstallerArguments = $PSBoundParameters.ContainsKey("InstallerArguments")
$ProfilePath = Join-Path $PSScriptRoot "profile.json"
$VersionPath = Join-Path $PSScriptRoot "VERSION"
$MigrationPath = Join-Path $PSScriptRoot "migrations"
$StateRoot = Join-Path $env:LOCALAPPDATA "Winenv"
$StatePath = Join-Path $StateRoot "state.json"
$ConfigPath = Join-Path $StateRoot "config.json"
$LocalUserProfilePath = Join-Path $StateRoot "user-profile.json"
$ProfilesRoot = Join-Path $StateRoot "profiles"
$InstallerLogRoot = Join-Path $StateRoot "logs"
$AllowedOwners = @("winget", "scoop", "mise", "vendor")
$ResolvedManagerCommands = @{}
$ApprovedScoopBucketSources = @{}
$RuntimeRequirements = @{
    "powershell" = [pscustomobject]@{
        Name = "PowerShell 7"
        Command = "pwsh"
        MinimumVersion = [Version]"7.4.0"
    }
    "fzf" = [pscustomobject]@{
        Name = "fzf"
        Command = "fzf"
        MinimumVersion = [Version]"0.35.0"
    }
}
$ActionAliases = @{
    "ls" = "list"
    "off" = "unuse"
    "browse" = "store"
    "find" = "search"
    "show" = "info"
    "check" = "doctor"
    "add" = "install"
    "up" = "update"
    "rm" = "remove"
    "clean" = "cleanup"
    "ver" = "version"
    "self" = "self-update"
    "selfup" = "self-update"
}
$CanonicalActions = @(
    "help", "list", "use", "unuse", "profile", "store", "search", "info", "doctor",
    "install", "update", "remove", "cleanup", "migrate", "version", "self-update", "bucket"
)

if ([string]::IsNullOrWhiteSpace($Action)) {
    $Action = "store"
} elseif ($ActionAliases.ContainsKey($Action)) {
    $Action = $ActionAliases[$Action]
} elseif ($CanonicalActions -notcontains $Action) {
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        throw "Use quotes around a multi-word search, for example: win 'Visual Studio Code'"
    }
    $Target = $Action
    $Action = "store"
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Plan {
    param([string]$Message)
    if ($DryRun) {
        Write-Host "[dry-run] $Message" -ForegroundColor DarkYellow
    } else {
        Write-Host $Message -ForegroundColor DarkGray
    }
}

function Show-WinenvVersion {
    if (Test-Path $VersionPath) {
        Write-Output ((Get-Content -Raw -Path $VersionPath).Trim())
    } else {
        Write-Output "development"
    }
}

function Show-WinenvHelp {
    Write-Host @"
Winenv keeps Windows software simple.

  win [software]       Search, select, and install
  win add [software]   Apply the profile, or install one known package
  win add <setup.exe|setup.msi>
                       Inspect and run a local Windows installer
  win add <manifest.yaml|folder>
                       Install from a local WinGet manifest
  win add <file.json>  Install a local or HTTPS Scoop manifest
  win bucket           List enabled Scoop buckets
  win bucket <name> [https-url]
                       Add a known or third-party Scoop bucket
  win rm [software]    Select and remove installed software
  win up               Update Winenv and all managed software
  win use <file|url>   Add, refresh, and install a profile
  win off [profile]    Disable one profile without uninstalling
  win ls               Show profiles and effective packages
  win find <software>  Print search results without opening the picker
  win show <software>  Show package ownership and details
  win check            Check managers and command conflicts
  win clean            Remove unused package versions
  win ver              Print the Winenv version
  win help             Show this help

Useful shortcuts: -From winget|scoop|mise, -n (dry run), -y (confirm),
                  -Hash <sha256>, -Args <installer-arguments>.
"@
}

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

function Update-WinenvSelf {
    $installerPath = Join-Path $PSScriptRoot "install.ps1"
    if (-not (Test-Path $installerPath)) {
        throw "Self-update installer not found: $installerPath"
    }

    Write-Step "Updating Winenv"
    Write-Plan "$installerPath -ToolOnly"
    if ($DryRun) { return }
    & $installerPath -ToolOnly
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    Write-Plan ((@($Command) + $Arguments) -join " ")
    if ($DryRun) { return }

    & $Command @Arguments
    $exitCode = $LASTEXITCODE
    if (-not $IgnoreExitCode -and $null -ne $exitCode -and $exitCode -ne 0) {
        throw "$Command failed with exit code $exitCode"
    }
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($pathValue in @($env:Path, $machinePath, $userPath)) {
        foreach ($entry in @([string]$pathValue -split ";")) {
            if ([string]::IsNullOrWhiteSpace($entry)) { continue }
            $expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim())
            $key = $expanded.TrimEnd("\").ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $entries.Add($expanded)
            }
        }
    }
    $env:Path = $entries -join ";"
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsWindowsPlatform {
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Get-ExternalCommandCandidates {
    param([string]$Name)
    return @(Get-Command $Name -All -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandType -in @("Application", "ExternalScript") -and
        -not [string]::IsNullOrWhiteSpace([string]$_.Path)
    })
}

function Invoke-CommandProbe {
    param(
        [string]$Path,
        [string[]]$Arguments
    )
    try {
        $global:LASTEXITCODE = 0
        $lines = @(& $Path @Arguments 2>&1)
        $succeeded = $?
        $exitCode = if ($null -eq $LASTEXITCODE) {
            if ($succeeded) { 0 } else { 1 }
        } else {
            [int]$LASTEXITCODE
        }
        return [pscustomobject]@{
            Lines = @($lines | ForEach-Object { [string]$_ })
            ExitCode = $exitCode
            Error = ""
        }
    } catch {
        return [pscustomobject]@{
            Lines = @()
            ExitCode = 1
            Error = $_.Exception.Message
        }
    }
}

function ConvertTo-DetectedVersion {
    param([array]$Lines)
    $text = @($Lines) -join "`n"
    $match = [Regex]::Match($text, "(?<!\d)(\d+\.\d+(?:\.\d+){0,2})")
    if (-not $match.Success) { return $null }
    try { return [Version]$match.Groups[1].Value } catch { return $null }
}

function Get-ManagerProbe {
    param([ValidateSet("winget", "scoop", "mise")][string]$Name)
    $candidates = @(Get-ExternalCommandCandidates $Name)
    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{
            Name = $Name
            Status = "missing"
            Version = $null
            Path = ""
            OtherPaths = @()
            Error = ""
        }
    }

    $path = [string]$candidates[0].Path
    $result = Invoke-CommandProbe $path @("--version")
    return [pscustomobject]@{
        Name = $Name
        Status = if ($result.ExitCode -eq 0) { "available" } else { "broken" }
        Version = ConvertTo-DetectedVersion $result.Lines
        Path = $path
        OtherPaths = @($candidates | Select-Object -Skip 1 | ForEach-Object Path | Select-Object -Unique)
        Error = [string]$result.Error
    }
}

function Get-RuntimeRequirement {
    param($Package)
    if ($null -eq $Package -or -not [bool]$Package._runtime) { return $null }
    $key = [string]$Package.key
    if (-not $RuntimeRequirements.ContainsKey($key)) { return $null }
    return $RuntimeRequirements[$key]
}

function Get-RuntimeRequirementProbe {
    param($Package)
    $requirement = Get-RuntimeRequirement $Package
    if ($null -eq $requirement) { return $null }

    $allCommands = @(Get-Command $requirement.Command -All -ErrorAction SilentlyContinue)
    $candidates = @($allCommands | Where-Object {
        $_.CommandType -in @("Application", "ExternalScript") -and
        -not [string]::IsNullOrWhiteSpace([string]$_.Path)
    })
    $shadowing = @($allCommands | Where-Object {
        $_.CommandType -notin @("Application", "ExternalScript")
    } | ForEach-Object { "$($_.CommandType):$($_.Name)" } | Select-Object -Unique)

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{
            Name = $requirement.Name
            Command = $requirement.Command
            Status = "missing"
            Version = $null
            MinimumVersion = $requirement.MinimumVersion
            Path = ""
            OtherPaths = @()
            Shadowing = $shadowing
            Error = ""
        }
    }

    $path = [string]$candidates[0].Path
    $arguments = if ($requirement.Command -eq "pwsh") {
        @("-NoLogo", "-NoProfile", "-Command", '$PSVersionTable.PSVersion.ToString()')
    } else {
        @("--version")
    }
    $result = Invoke-CommandProbe $path $arguments
    $version = ConvertTo-DetectedVersion $result.Lines
    $status = if ($result.ExitCode -ne 0 -or $null -eq $version) {
        "broken"
    } elseif ($version -lt $requirement.MinimumVersion) {
        "outdated"
    } else {
        "available"
    }
    return [pscustomobject]@{
        Name = $requirement.Name
        Command = $requirement.Command
        Status = $status
        Version = $version
        MinimumVersion = $requirement.MinimumVersion
        Path = $path
        OtherPaths = @($candidates | Select-Object -Skip 1 | ForEach-Object Path | Select-Object -Unique)
        Shadowing = $shadowing
        Error = [string]$result.Error
    }
}

function Get-ResolvedManagerCommand {
    param([ValidateSet("winget", "scoop", "mise")][string]$Name)
    if ($ResolvedManagerCommands.ContainsKey($Name)) {
        return [string]$ResolvedManagerCommands[$Name]
    }
    $probe = Get-ManagerProbe $Name
    if ($probe.Status -eq "available") {
        $ResolvedManagerCommands[$Name] = $probe.Path
        return [string]$probe.Path
    }
    if ($DryRun) { return $Name }
    throw "$Name is unavailable. Run 'win check' for details."
}

function Get-OptionalManagerCommand {
    param([ValidateSet("winget", "scoop", "mise")][string]$Name)
    $probe = Get-ManagerProbe $Name
    if ($probe.Status -eq "available") { return [string]$probe.Path }
    if ($DryRun -and (Test-Command $Name)) { return $Name }
    return $null
}

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
    return (ConvertFrom-ProfileText (Get-Content -Raw -Path $Path) $Path)
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
        Text = Get-Content -Raw -Path $resolvedPath
        Label = $resolvedPath
        Key = "file:$resolvedPath"
        Type = "file"
    }
}

function Get-TextHash {
    param([string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function New-WinenvConfig {
    return [pscustomobject]@{
        schemaVersion = 2
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
        $stored = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Winenv config is not valid JSON: $ConfigPath"
    }

    if ($stored.schemaVersion -eq 2) {
        return [pscustomobject]@{
            schemaVersion = 2
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
            hash = Get-TextHash (Get-Content -Raw -Path $LocalUserProfilePath)
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
        Write-Host $conflict.Label -ForegroundColor Yellow
        $candidates = @($conflict.Candidates)
        for ($index = 0; $index -lt $candidates.Count; $index++) {
            $candidate = $candidates[$index]
            $claims = @($candidate.Claims | ForEach-Object { ($_.Ref -split "/", 2)[0] } | Select-Object -Unique) -join ", "
            $version = if ($candidate.Package.version) { " @$($candidate.Package.version)" } else { "" }
            Write-Host ("  [{0}] {1}: {2}/{3}{4}" -f ($index + 1), $claims, $candidate.Package.owner, $candidate.Package.id, $version)
        }
        if ($DryRun -or $Yes) {
            throw "Profile conflicts require an explicit interactive choice; no profile was changed."
        }
        $answer = Read-Host "Choose the package to keep [1-$($candidates.Count)]"
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
    Write-Host "Runtime profile: $ProfilePath"
    $entries = @($config.profiles)
    if ($entries.Count -eq 0) {
        Write-Host "User profiles:   none (runtime only)"
    } else {
        Write-Host "`nUser profiles"
        $entries |
            Select-Object @{Name = "status"; Expression = { if ($_.enabled) { "on" } else { "off" } }}, id, name,
                @{Name = "type"; Expression = { $_.sourceType }},
                @{Name = "source"; Expression = { ([string]$_.source) -replace "^(url|file):", "" }} |
            Format-Table -AutoSize
    }
    Write-Host "`nUse 'win use <file-or-https-url>' to add or refresh one; use 'win off <name-or-id>' to disable it." -ForegroundColor DarkGray
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
            Text = Get-Content -Raw -Path $savedPath
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
        Write-Host "Name:    $($userProfile.name)"
        Write-Host "ID:      $($entry.id)"
        Write-Host "Source:  $($source.Label)"
        Write-Host "Active:  $(@($nextConfig.profiles | Where-Object enabled).Count) user profile(s)"
        Write-Host "Install: $($selectedPackages.Count) package(s) selected by all active defaults"
        $selectedPackages |
            Select-Object displayName, owner, id, @{Name = "claims"; Expression = { @($_._claims) -join "," }} |
            Sort-Object owner, displayName |
            Format-Table -AutoSize
        if ($customBuckets.Count -gt 0) {
            Write-Host "`nThird-party Scoop buckets" -ForegroundColor Yellow
            $customBuckets | Select-Object Name, Url | Format-Table -AutoSize
            Write-Host "Their manifests can execute installation scripts. Only continue if you trust these publishers." -ForegroundColor Yellow
        }
        $confirmationPrompt = if ($customBuckets.Count -gt 0) {
            "Trust the listed bucket sources, save this profile snapshot, and install the packages shown above?"
        } else {
            "Save this profile snapshot and install the packages shown above?"
        }
        if (-not (Confirm-Operation $confirmationPrompt)) {
            Write-Host "Profile activation cancelled."
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
        Write-Host "Profile '$($userProfile.name)' is active. Run 'win add' to install all active defaults." -ForegroundColor Green
        return
    }

    Install-Packages $definition $selectedPackages -ProfileManagedMise
    Invoke-Migrations
    Write-Host "`nProfile '$($userProfile.name)' is active and installed." -ForegroundColor Green
}

function Disable-UserProfile {
    param([switch]$AllowAliasTarget)

    Initialize-ProfileRegistry
    $config = Read-WinenvConfig
    $enabled = @($config.profiles | Where-Object enabled)
    if ($enabled.Count -eq 0) {
        $runtimeOnly = Resolve-ProfileDefinitions $config
        Sync-WinenvMiseConfig $runtimeOnly.Definition
        Write-Host "No user profile is active; the runtime profile is unchanged."
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
            Write-Host "Active profiles"
            $enabled | Select-Object id, name, source | Format-Table -AutoSize
            $requested = Read-Host "Profile name or ID to disable"
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
    Write-Host "Name:       $($entry.name)"
    Write-Host "Retained:   $(@($retained).Count) package claim(s) still referenced by another active profile"
    Write-Host "Unclaimed:  $(@($unclaimed).Count) package specification(s) no longer referenced"
    if (@($unclaimed).Count -gt 0) {
        $unclaimed | Select-Object displayName, owner, id | Format-Table -AutoSize
    }

    Write-WinenvConfig $nextConfig
    Sync-WinenvMiseConfig $after.Definition
    if ($DryRun) {
        Write-Host "Profile '$($entry.name)' would be disabled; no installed software would be changed, and its snapshot would be kept."
    } else {
        Write-Host "Profile '$($entry.name)' disabled; no installed software was changed, and its snapshot was kept." -ForegroundColor Green
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

function New-PackageCandidate {
    param(
        [string]$ManagerName,
        [string]$Id,
        [string]$Name,
        [string]$Version = "",
        [string]$Source = "",
        [string]$Description = "",
        [string]$ManagedKey = ""
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

function Get-WinGetCandidates {
    param(
        [string]$Query,
        [switch]$Installed
    )
    if (-not (Test-Command "winget")) { return @() }

    $arguments = if ($Installed) {
        @("list", "--accept-source-agreements", "--disable-interactivity")
    } else {
        @("search", "--query", $Query, "--count", "50", "--accept-source-agreements", "--disable-interactivity")
    }
    if ($Installed -and -not [string]::IsNullOrWhiteSpace($Query)) {
        $arguments = @("list", "--query", $Query, "--accept-source-agreements", "--disable-interactivity")
    }

    $result = Invoke-CapturedCommand "winget" $arguments
    if ($result.ExitCode -ne 0) { return @() }
    return @(ConvertFrom-FixedWidthTable $result.Lines | ForEach-Object {
        $values = @($_)
        $source = if ($values.Count -ge 4) { [string]$values[-1] } else { "winget" }
        if ([string]::IsNullOrWhiteSpace($source)) { $source = "winget" }
        New-PackageCandidate -ManagerName "winget" -Id $values[1] -Name $values[0] -Version $values[2] -Source $source
    })
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

function Get-MiseCandidates {
    param(
        [string]$Query,
        [switch]$Installed
    )
    if (-not (Test-Command "mise")) { return @() }

    if ($Installed) {
        $result = Invoke-CapturedCommand "mise" @("ls", "--json")
        if ($result.ExitCode -ne 0) { return @() }
        $inventory = (($result.Lines -join "`n") | ConvertFrom-Json)
        return @($inventory.psobject.Properties | ForEach-Object {
            $id = [string]$_.Name
            $active = @($_.Value | Where-Object { $_.active } | Select-Object -First 1)
            if ($active.Count -eq 0) { $active = @($_.Value | Select-Object -First 1) }
            if (($active.Count -gt 0) -and ([string]::IsNullOrWhiteSpace($Query) -or $id.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
                New-PackageCandidate -ManagerName "mise" -Id $id -Name $id -Version $active[0].version -Source "mise"
            }
        })
    }

    $result = Invoke-CapturedCommand "mise" @("registry", "--json")
    if ($result.ExitCode -ne 0) { return @() }
    $registry = @((($result.Lines -join "`n") | ConvertFrom-Json))
    return @($registry | Where-Object {
        $searchable = @([string]$_.short, [string]$_.description, (@($_.aliases) -join " "), (@($_.backends) -join " ")) -join " "
        $searchable.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0
    } | Select-Object -First 50 | ForEach-Object {
        New-PackageCandidate -ManagerName "mise" -Id $_.short -Name $_.short -Source (@($_.backends)[0]) -Description $_.description
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
        foreach ($property in @("Version", "Source", "Description", "ManagedKey")) {
            if ([string]::IsNullOrWhiteSpace([string]$existing.$property) -and -not [string]::IsNullOrWhiteSpace([string]$candidate.$property)) {
                $existing.$property = $candidate.$property
            }
        }
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
        if ($Manager -in @("all", "winget")) { $candidates += @(Get-WinGetCandidates $Query) }
        if ($Manager -in @("all", "scoop")) { $candidates += @(Get-ScoopCandidates $Query) }
        if ($Manager -in @("all", "mise")) { $candidates += @(Get-MiseCandidates $Query) }
    }
    return @(Merge-PackageCandidates $candidates | Sort-Object Manager, Name, Id)
}

function Get-InstalledCandidates {
    param(
        $Definition,
        [string]$Query = ""
    )
    $candidates = @()
    if ($Manager -in @("all", "managed", "winget")) { $candidates += @(Get-WinGetCandidates $Query -Installed) }
    if ($Manager -in @("all", "managed", "scoop")) { $candidates += @(Get-ScoopCandidates $Query -Installed) }
    if ($Manager -in @("all", "managed", "mise")) { $candidates += @(Get-MiseCandidates $Query -Installed) }

    $managed = @(Get-ManagedCandidates $Definition $Query)
    foreach ($candidate in $candidates) {
        $match = @($managed | Where-Object { $_.Token -eq $candidate.Token } | Select-Object -First 1)
        if ($match.Count -gt 0) { $candidate.ManagedKey = $match[0].ManagedKey }
    }
    return @(Merge-PackageCandidates $candidates | Sort-Object Manager, Name, Id)
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
        Write-Host "No matching packages were found in the available catalogs." -ForegroundColor Yellow
        return
    }
    $candidates | Select-Object Manager, Source, Name, Id, Version,
        @{Name = "Baseline"; Expression = { $_.ManagedKey }},
        @{Name = "Install"; Expression = {
            if ($_.ManagedKey) { "win add $($_.ManagedKey)" } else { "win add $($_.Token)" }
        }} |
        Format-Table -AutoSize
    Write-Host "Results with the same name stay separate by manager; Winenv never guesses between them." -ForegroundColor DarkGray
}

function Show-PackageInfo {
    param($Definition)
    if ([string]::IsNullOrWhiteSpace($Target)) {
        throw "show requires a profile key or manager token. Example: win show winget:winget/Microsoft.PowerToys"
    }

    $package = Resolve-PackageReference $Definition $Target
    if ($null -eq $package) { throw "Unknown package reference: $Target" }

    Write-Host $package.displayName -ForegroundColor Cyan
    Write-Host ("Reference: {0}" -f $Target)
    if ([bool]$package._runtime) {
        Write-Host ("Fallback:  {0}" -f $package.owner)
    } else {
        Write-Host ("Manager:   {0}" -f $package.owner)
    }
    Write-Host ("Package:   {0}" -f $package.id)
    if (@($package.profiles).Count -gt 0) {
        Write-Host ("Profiles:  {0}" -f (@($package.profiles) -join ", "))
    }
    if (@($package.commands).Count -gt 0) {
        Write-Host ("Commands:  {0}" -f (@($package.commands) -join ", "))
    }
    if ($package.instructions) { Write-Host "`n$($package.instructions)" }

    Write-Host "`nPackage details" -ForegroundColor DarkCyan
    switch ($package.owner) {
        "winget" {
            $managerProbe = Get-ManagerProbe "winget"
            if ($managerProbe.Status -eq "available") {
                $source = if ($package.source) { [string]$package.source } else { "winget" }
                Invoke-Native $managerProbe.Path @("show", "--id", [string]$package.id, "--exact", "--source", $source, "--accept-source-agreements", "--disable-interactivity") -IgnoreExitCode
            } else { Write-Host "WinGet is unavailable." }
        }
        "scoop" {
            $managerProbe = Get-ManagerProbe "scoop"
            if ($managerProbe.Status -eq "available") {
                $qualifiedId = if ($package.bucket) { "$($package.bucket)/$($package.id)" } else { [string]$package.id }
                Invoke-Native $managerProbe.Path @("info", $qualifiedId) -IgnoreExitCode
            } else { Write-Host "Scoop is unavailable." }
        }
        "mise" {
            $managerProbe = Get-ManagerProbe "mise"
            if ($managerProbe.Status -eq "available") { Invoke-Native $managerProbe.Path @("registry", [string]$package.id) -IgnoreExitCode }
            else { Write-Host "mise is unavailable." }
        }
        "vendor" { Write-Host "This package is managed by its vendor installer." }
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
        $Candidates | Select-Object Manager, Source, Name, Id, Version, ManagedKey | Format-Table -AutoSize
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
    $previewCommand = "`"$previewHost`" -NoLogo -NoProfile -File `"$PSCommandPath`" show {1}"
    $fzfArguments = @(
        "--delimiter", "`t", "--with-nth", "2,3,4,5,6,7",
        "--header", "Manager | Source | Name | ID | Version | Baseline   (Alt-P: details, Esc: cancel)",
        "--preview", $previewCommand, "--preview-label", "Alt-P: details | Alt-J/K: scroll",
        "--preview-window", "down:60%:wrap",
        "--bind", "alt-p:toggle-preview,alt-d:preview-half-page-down,alt-u:preview-half-page-up,alt-k:preview-up,alt-j:preview-down",
        "--color", "pointer:green,marker:green,prompt:cyan", "--border", "rounded",
        "--height", "95%", "--layout", "reverse", "--prompt", $Prompt
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
        $Query = Read-Host "Search WinGet, Scoop, and mise"
        if ([string]::IsNullOrWhiteSpace($Query)) {
            Write-Host "No search entered."
            return
        }
    }
    $candidates = @(Get-CatalogCandidates $Definition $Query)
    if ($candidates.Count -eq 0) {
        Write-Host "No matching packages were found in the available catalogs." -ForegroundColor Yellow
        return
    }

    $selected = @(Select-PackageCandidates $candidates "Winenv Store > " -Multi)
    if ($selected.Count -eq 0) { Write-Host "No packages selected."; return }
    $packages = @($selected | ForEach-Object { ConvertTo-PackageDefinition $_ })

    Write-Step "Installing selected packages"
    $selected | Select-Object Manager, Source, Name, Id, Version | Format-Table -AutoSize
    Install-Packages $Definition $packages
    Invoke-Migrations
    Write-Host "`nSelected packages installed." -ForegroundColor Green
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

function Confirm-Operation {
    param([string]$Prompt)
    if ($Yes -or $DryRun) { return $true }
    $answer = Read-Host "$Prompt [y/N]"
    return $answer -match "^(y|yes)$"
}

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
        Write-Host "$($probe.Name): $reason." -ForegroundColor Yellow
        Write-Host "Existing command: $($probe.Path)"
        Write-Host "Fallback package: $($package.owner)/$($package.id)"
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
        Write-Host ("{0,-10} {1,-18} {2,-12} {3}" -f "action", "requirement", "version", "location") -ForegroundColor DarkGray
        foreach ($row in $rows) {
            $color = switch ($row.Action) {
                "reuse" { "Green" }
                "install" { "Cyan" }
                default { "Yellow" }
            }
            Write-Host ("{0,-10} {1,-18} {2,-12} {3}" -f $row.Action, $row.Requirement, $row.Version, $row.Location) -ForegroundColor $color
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
        Write-Host ("ready     {0,-18} {1,-12} {2}" -f $probe.Name, $probe.Version, $probe.Path) -ForegroundColor Green
    }
}

function Ensure-WinGet {
    $probe = Get-ManagerProbe "winget"
    if ($probe.Status -eq "available") {
        $ResolvedManagerCommands["winget"] = $probe.Path
        return
    }
    if ($probe.Status -eq "broken") {
        throw "WinGet exists at $($probe.Path), but 'winget --version' failed. Repair App Installer, then run 'win check'."
    }

    Write-Step "Preparing WinGet"
    $registerCommand = "Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"
    if ($DryRun) {
        Write-Plan $registerCommand
        Write-Plan "If registration fails, repair App Installer with Microsoft.WinGet.Client or install it from Microsoft Store"
        return
    }
    if (-not (Test-IsWindowsPlatform)) {
        throw "WinGet is required and is only available on Windows 10 1809 or later."
    }
    if (-not (Get-Command "Add-AppxPackage" -ErrorAction SilentlyContinue)) {
        throw "WinGet is missing and App Installer could not be registered because Add-AppxPackage is unavailable. Install App Installer from Microsoft Store."
    }

    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe" -ErrorAction Stop
    } catch {
        throw "WinGet is missing and App Installer registration failed. Install App Installer from Microsoft Store, or run: Install-Module Microsoft.WinGet.Client -Force -Repository PSGallery; Repair-WinGetPackageManager -AllUsers"
    }
    Refresh-ProcessPath
    $probe = Get-ManagerProbe "winget"
    if ($probe.Status -ne "available") {
        throw "App Installer was registered, but WinGet is still unavailable. Open a new PowerShell window and run 'win check'. If it remains missing, repair App Installer with Microsoft.WinGet.Client."
    }
    $ResolvedManagerCommands["winget"] = $probe.Path
}

function Ensure-Mise {
    $probe = Get-ManagerProbe "mise"
    if ($probe.Status -eq "available") {
        $ResolvedManagerCommands["mise"] = $probe.Path
        return
    }
    if ($probe.Status -eq "broken") {
        throw "mise exists at $($probe.Path), but 'mise --version' failed. Fix or remove that installation before continuing."
    }

    Ensure-Scoop
    Write-Step "Installing mise with Scoop"
    Invoke-Native (Get-ResolvedManagerCommand "scoop") @("install", "mise")
    if ($DryRun) { return }

    Refresh-ProcessPath
    $probe = Get-ManagerProbe "mise"
    if ($probe.Status -ne "available") {
        throw "mise was installed but is not visible in this process. Open a new PowerShell window and run the command again."
    }
    $ResolvedManagerCommands["mise"] = $probe.Path
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

    Write-Host "Source: $installerUri"
    Write-Host "SHA-256: $hash"
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
            Write-Host "Third-party Scoop bucket: $($bucket.Name)" -ForegroundColor Yellow
            Write-Host "Source: $($bucket.Url)"
            Write-Host "Its manifests may execute installation scripts. Review and trust the publisher before adding it." -ForegroundColor Yellow
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
        Write-Host "Name:   $($bucket.Name)"
        Write-Host "Source: $($bucket.Url)"
        if ($matches.Count -gt 0) { Write-Host "Current source: $($matches[0].Source)" }
        Write-Host "Scoop manifests can execute installation scripts. Only continue if you trust this publisher." -ForegroundColor Yellow
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
            Write-Host "Scoop is not installed. Add a bucket with: win bucket <name> [https-url]" -ForegroundColor Yellow
            return
        }
        $inventory = @(Get-ScoopBucketInventory $scoopCommand)
        Write-Step "Enabled Scoop buckets"
        if ($inventory.Count -eq 0) {
            Write-Host "No Scoop buckets are enabled. Add the default source with: win bucket main"
        } else {
            $inventory | Format-Table Name, Source -AutoSize
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
    if (-not $DryRun) { Write-Host "Scoop bucket '$($bucket.Name)' is ready." -ForegroundColor Green }
}

function Get-ReferenceExtension {
    param([string]$Reference)
    try {
        $uri = [Uri]$Reference
        if ($uri.IsAbsoluteUri -and $Reference -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
            return [IO.Path]::GetExtension($uri.AbsolutePath)
        }
    } catch {}
    return [IO.Path]::GetExtension($Reference)
}

function Test-WindowsInstallerReference {
    param([string]$Reference)
    $extension = Get-ReferenceExtension $Reference
    return $extension -in @(".exe", ".msi")
}

function Test-WinGetManifestReference {
    param([string]$Reference)
    if (Test-Path -LiteralPath $Reference -PathType Container) {
        return @(Get-ChildItem -LiteralPath $Reference -File -Recurse | Where-Object { $_.Extension -in @(".yaml", ".yml") }).Count -gt 0
    }
    return (Get-ReferenceExtension $Reference) -in @(".yaml", ".yml")
}

function Get-InstallerInspection {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path
    $versionInfo = $item.VersionInfo
    $signatureStatus = "Unavailable"
    $publisher = ""
    $signatureMessage = "Authenticode inspection is only available on Windows."
    if (Test-IsWindowsPlatform) {
        try {
            $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
            $signatureStatus = [string]$signature.Status
            $signatureMessage = [string]$signature.StatusMessage
            if ($null -ne $signature.SignerCertificate) {
                $publisher = $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
            }
        } catch {
            $signatureStatus = "Error"
            $signatureMessage = $_.Exception.Message
        }
    }
    return [pscustomobject]@{
        Path = $item.FullName
        Type = $item.Extension.TrimStart(".").ToUpperInvariant()
        Size = [long]$item.Length
        Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        Product = if ($null -ne $versionInfo) { [string]$versionInfo.ProductName } else { "" }
        Version = if ($null -ne $versionInfo) { [string]$versionInfo.ProductVersion } else { "" }
        SignatureStatus = $signatureStatus
        SignatureMessage = $signatureMessage
        Publisher = $publisher
    }
}

function ConvertTo-WindowsCommandLineArgument {
    param([AllowEmptyString()][string]$Value)

    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $backslashes++
            continue
        }
        if ($character -eq [char]34) {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Join-WindowsCommandLineArguments {
    param([string[]]$Arguments)
    return (@($Arguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument ([string]$_) }) -join " ")
}

function Invoke-WindowsInstallerProcess {
    param(
        [string]$Path,
        [string]$Type,
        [string[]]$Arguments,
        [string]$LogPath = ""
    )

    if ($Type -eq "MSI") {
        $command = "msiexec.exe"
        $processArguments = @("/i", $Path)
        if (@($Arguments | Where-Object { $_ -match "^/(no|prompt|force)restart$" }).Count -eq 0) {
            $processArguments += "/norestart"
        }
        if (@($Arguments | Where-Object { $_ -match "^/l" }).Count -eq 0) {
            $processArguments += @("/L*V", $LogPath)
        }
        $processArguments += @($Arguments)
        $workingDirectory = Split-Path -Parent $Path
    } else {
        $command = $Path
        $processArguments = @($Arguments)
        $workingDirectory = Split-Path -Parent $Path
    }
    $argumentLine = Join-WindowsCommandLineArguments $processArguments
    $commandLine = ConvertTo-WindowsCommandLineArgument $command
    if ($argumentLine) { $commandLine += " $argumentLine" }
    Write-Plan $commandLine
    if ($DryRun) { return 0 }
    if (-not (Test-IsWindowsPlatform)) { throw "EXE and MSI installers can only run on Windows." }

    if ($Type -eq "MSI") {
        New-Item -ItemType Directory -Path (Split-Path -Parent $LogPath) -Force | Out-Null
    }
    try {
        $processParameters = @{
            FilePath = $command
            WorkingDirectory = $workingDirectory
            Wait = $true
            PassThru = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($argumentLine)) {
            $processParameters.ArgumentList = $argumentLine
        }
        $process = Start-Process @processParameters
        $process.WaitForExit()
        return [int]$process.ExitCode
    } catch {
        throw "Unable to start the $Type installer: $($_.Exception.Message)"
    }
}

function Install-LocalWindowsInstaller {
    param([string]$Reference)

    if ($Reference -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
        throw "Direct EXE/MSI installation accepts local files only. Download the installer first so its signature and hash can be reviewed."
    }
    if (-not (Test-Path -LiteralPath $Reference -PathType Leaf)) {
        throw "Windows installer was not found: $Reference"
    }
    $path = (Resolve-Path -LiteralPath $Reference).Path
    $inspection = Get-InstallerInspection $path
    if ($inspection.Type -notin @("EXE", "MSI")) { throw "Unsupported Windows installer type: $($inspection.Type)" }

    $expectedHashVerified = $false
    if (-not [string]::IsNullOrWhiteSpace($Sha256)) {
        $normalizedExpectedHash = $Sha256.Trim().ToLowerInvariant()
        if ($normalizedExpectedHash -notmatch "^[a-f0-9]{64}$") { throw "-Hash must be a 64-character SHA-256 value." }
        if ($normalizedExpectedHash -ne $inspection.Sha256) {
            throw "Installer SHA-256 mismatch. Expected $normalizedExpectedHash but found $($inspection.Sha256)."
        }
        $expectedHashVerified = $true
    }

    Write-Step "Windows installer preview"
    $sizeLabel = if ($inspection.Size -ge 1MB) {
        "$([Math]::Round($inspection.Size / 1MB, 2)) MiB"
    } elseif ($inspection.Size -ge 1KB) {
        "$([Math]::Round($inspection.Size / 1KB, 2)) KiB"
    } else {
        "$($inspection.Size) bytes"
    }
    Write-Host "File:       $($inspection.Path)"
    Write-Host "Type:       $($inspection.Type)"
    Write-Host "Size:       $sizeLabel"
    if ($inspection.Product) { Write-Host "Product:    $($inspection.Product)" }
    if ($inspection.Version) { Write-Host "Version:    $($inspection.Version)" }
    Write-Host "SHA-256:    $($inspection.Sha256)"
    if ($expectedHashVerified) { Write-Host "Hash check: matched -Hash" -ForegroundColor Green }
    Write-Host "Signature:  $($inspection.SignatureStatus)"
    if ($inspection.Publisher) { Write-Host "Publisher:  $($inspection.Publisher)" }
    if ($inspection.SignatureStatus -ne "Valid") {
        Write-Host $inspection.SignatureMessage -ForegroundColor Yellow
    }
    if ($HasInstallerArguments) {
        Write-Host "Arguments:  $(Join-WindowsCommandLineArguments $InstallerArguments)"
    }

    $safeForUnattended = $inspection.SignatureStatus -eq "Valid" -or ($inspection.SignatureStatus -eq "NotSigned" -and $expectedHashVerified)
    if ($Yes -and -not $DryRun -and -not $safeForUnattended) {
        throw "This installer is not covered by a valid Authenticode signature or a pinned hash for an unsigned file. Run interactively to review it, or provide a trusted -Hash value."
    }
    if (-not (Confirm-Operation "Run this $($inspection.Type) installer?")) {
        Write-Host "Installer launch cancelled."
        return
    }

    $logPath = if ($inspection.Type -eq "MSI") {
        Join-Path $InstallerLogRoot ("msi-{0}-{1}.log" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), $inspection.Sha256.Substring(0, 12))
    } else { "" }
    $effectiveInstallerArguments = if ($HasInstallerArguments) { @($InstallerArguments) } else { @() }
    $exitCode = Invoke-WindowsInstallerProcess $path $inspection.Type $effectiveInstallerArguments $logPath
    if ($DryRun) { return }
    if ($exitCode -notin @(0, 1641, 3010)) {
        $logHint = if ($logPath) { " MSI log: $logPath" } else { "" }
        throw "$($inspection.Type) installer exited with code $exitCode.$logHint"
    }
    if ($exitCode -in @(1641, 3010)) {
        Write-Host "Installation completed and Windows reports that a restart is required." -ForegroundColor Yellow
    } else {
        Write-Host "Installer completed successfully." -ForegroundColor Green
    }
    if ($logPath) { Write-Host "MSI log: $logPath" }
    Write-Host "If the installer registered the app with Windows, it will appear in 'win rm'." -ForegroundColor DarkGray
}

function Get-WinGetManifestFiles {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        return @(Get-ChildItem -LiteralPath $Path -File -Recurse | Where-Object { $_.Extension -in @(".yaml", ".yml") } | Sort-Object FullName)
    }
    return @(Get-Item -LiteralPath $Path)
}

function Test-WinGetLocalManifestEnabled {
    param([string]$Command)
    $result = Invoke-CapturedCommand $Command @("settings", "export")
    if ($result.ExitCode -ne 0) { return $false }
    try {
        $settings = (@($result.Lines | ForEach-Object { [string]$_ }) -join "`n") | ConvertFrom-Json -ErrorAction Stop
        $value = $settings.adminSettings.LocalManifestFiles
        return $value -eq $true -or [string]$value -match "^(true|enabled)$"
    } catch {
        return $false
    }
}

function Install-WinGetManifest {
    param([string]$Reference)

    if ($Reference -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
        throw "WinGet local manifests must be a local YAML file or directory. Clone or download the manifest first."
    }
    if (-not (Test-Path -LiteralPath $Reference)) { throw "WinGet manifest was not found: $Reference" }
    $path = (Resolve-Path -LiteralPath $Reference).Path
    $files = @(Get-WinGetManifestFiles $path)
    if ($files.Count -eq 0 -or @($files | Where-Object { $_.Extension -notin @(".yaml", ".yml") }).Count -gt 0) {
        throw "A WinGet manifest must be a YAML file or a directory containing YAML manifests."
    }

    Write-Step "Local WinGet manifest preview"
    Write-Host "Path: $path"
    $files | ForEach-Object {
        [pscustomobject]@{
            File = $_.Name
            Size = $_.Length
            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } | Format-Table -AutoSize
    Write-Host "WinGet manifests select and run installers. Only continue if you trust these local files and their installer URLs." -ForegroundColor Yellow
    if (-not (Confirm-Operation "Validate and install this local WinGet manifest?")) {
        Write-Host "Manifest installation cancelled."
        return
    }

    Ensure-WinGet
    $wingetCommand = Get-ResolvedManagerCommand "winget"
    if (-not $DryRun -and -not (Test-WinGetLocalManifestEnabled $wingetCommand)) {
        throw "WinGet local manifests are disabled. Run this once from an administrator PowerShell, then retry: winget settings --enable LocalManifestFiles"
    }
    Invoke-Native $wingetCommand @("validate", $path)
    Invoke-Native $wingetCommand @(
        "install", "--manifest", $path, "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"
    )
    if (-not $DryRun) { Write-Host "Local WinGet manifest installed successfully." -ForegroundColor Green }
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

        try { $manifest = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json -ErrorAction Stop } catch {
            throw "Scoop manifest is not valid JSON: $sourceLabel"
        }
        if ($manifest -isnot [pscustomobject]) { throw "Scoop manifest root must be a JSON object: $sourceLabel" }
        $manifestProperties = @($manifest.psobject.Properties.Name)
        if ($manifestProperties -contains "schemaVersion" -and $manifestProperties -contains "packages") {
            throw "This is a Winenv profile, not a Scoop manifest. Import it with 'win use'."
        }

        Write-Step "Scoop manifest preview"
        Write-Host "Source:      $sourceLabel"
        Write-Host "Manifest:    $([IO.Path]::GetFileName($snapshotPath))"
        if ($manifestProperties -contains "version") { Write-Host "Version:     $($manifest.version)" }
        if ($manifestProperties -contains "homepage") { Write-Host "Homepage:    $($manifest.homepage)" }
        if ($manifestProperties -contains "description") { Write-Host "Description: $($manifest.description)" }
        Write-Host "SHA-256:     $((Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash.ToLowerInvariant())"
        Write-Host "Scoop manifests can execute installation scripts. Review the source and hash before continuing." -ForegroundColor Yellow
        if (-not (Confirm-Operation "Install this Scoop manifest?")) {
            Write-Host "Manifest installation cancelled."
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
    $escapedScriptPath = $PSCommandPath.Replace("'", "''")
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
        $existing = if (Test-Path $path) { Get-Content -Raw -Path $path } else { "" }
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

function Install-WinGetPackage {
    param($Package)
    $source = if ($Package.source) { [string]$Package.source } else { "winget" }
    Invoke-Native (Get-ResolvedManagerCommand "winget") @(
        "install", "--id", [string]$Package.id, "--exact", "--source", $source,
        "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"
    )
}

function Install-ScoopPackage {
    param($Package)
    $qualifiedId = if ($Package.bucket) { "$($Package.bucket)/$($Package.id)" } else { [string]$Package.id }
    Invoke-Native (Get-ResolvedManagerCommand "scoop") @("install", $qualifiedId)
}

function Install-MisePackage {
    param(
        $Package,
        [switch]$ProfileManaged
    )
    $version = if ($Package.version) { [string]$Package.version } else { "latest" }
    if ($ProfileManaged) {
        Invoke-Native (Get-ResolvedManagerCommand "mise") @("install", "$($Package.id)@$version")
    } else {
        Invoke-Native (Get-ResolvedManagerCommand "mise") @("use", "--global", "$($Package.id)@$version")
    }
}

function Get-WinenvMiseConfigPath {
    $configRoot = if (-not [string]::IsNullOrWhiteSpace($env:MISE_CONFIG_DIR)) {
        $env:MISE_CONFIG_DIR
    } else {
        $userRoot = [Environment]::GetFolderPath("UserProfile")
        if ([string]::IsNullOrWhiteSpace($userRoot)) { throw "Windows user profile directory could not be resolved." }
        Join-Path $userRoot ".config\mise"
    }
    return Join-Path $configRoot "conf.d\winenv.toml"
}

function ConvertTo-TomlString {
    param([string]$Value)
    return '"' + $Value.Replace('\', '\\').Replace('"', '\"') + '"'
}

function Sync-WinenvMiseConfig {
    param($Definition)
    $path = Get-WinenvMiseConfigPath
    $tools = @(Get-DefaultPackages $Definition | Where-Object owner -eq "mise" | Sort-Object id)
    $lines = @(
        "# Generated by Winenv. Edit profiles, not this file.",
        "[tools]"
    )
    foreach ($package in $tools) {
        $version = if ($package.version) { [string]$package.version } else { "latest" }
        $lines += "$(ConvertTo-TomlString ([string]$package.id)) = $(ConvertTo-TomlString $version)"
    }
    Write-Plan "Sync Winenv's mise declarations to $path"
    if ($DryRun) { return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    Set-Content -Path $path -Value ($lines -join "`r`n") -Encoding UTF8
}

function Install-Packages {
    param(
        $Definition,
        [array]$Packages,
        [switch]$ProfileManagedMise
    )
    $runtimePlan = Resolve-RuntimeInstallPlan @($Packages)
    $packages = @($runtimePlan.Packages)
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
        switch ($package.owner) {
            "winget" { Install-WinGetPackage $package }
            "scoop" { Install-ScoopPackage $package }
            "mise" { Install-MisePackage $package -ProfileManaged:$ProfileManagedMise }
            "vendor" {
                Write-Host "Manual vendor-managed package: $($package.displayName)" -ForegroundColor Yellow
                if ($package.instructions) { Write-Host $package.instructions }
            }
        }
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
        Write-Host "No packages selected."
        return
    }
    $packages = @($selected | ForEach-Object { ConvertTo-PackageDefinition $_ })
    Install-Packages $Definition $packages
}

function Read-State {
    if (-not (Test-Path $StatePath)) {
        return @{ appliedMigrations = @() }
    }
    $state = Get-Content -Raw -Path $StatePath | ConvertFrom-Json
    return @{ appliedMigrations = @($state.appliedMigrations) }
}

function Write-State {
    param($State)
    if ($DryRun) { return }
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $StatePath -Encoding UTF8
}

function Invoke-Migrations {
    Write-Step "Running pending migrations"
    if (-not (Test-Path $MigrationPath)) { return }

    $state = Read-State
    $applied = @($state.appliedMigrations)
    $migrations = @(Get-ChildItem -Path $MigrationPath -Filter "*.ps1" -File | Sort-Object Name)

    foreach ($migration in $migrations) {
        if ($applied -contains $migration.Name) { continue }
        Write-Plan "Run migration $($migration.Name)"
        if ($DryRun) { continue }

        & $migration.FullName
        $applied += $migration.Name
        $state.appliedMigrations = @($applied)
        Write-State $state
    }
}

function Show-Profile {
    param($Definition)
    Show-UserProfileStatus
    Write-Host "`nEffective packages"
    Get-SelectedPackages $Definition |
        Sort-Object owner, key |
        Select-Object key, displayName,
            @{Name = "provider"; Expression = { if ([bool]$_._runtime) { "$($_.owner) (fallback)" } else { $_.owner } }}, id,
            @{Name = "claims"; Expression = { if ($_.psobject.Properties.Name -contains "_claims") { @($_._claims) -join "," } else { "runtime" } }} |
        Format-Table -AutoSize
}

function Test-ProfileHealth {
    param($Definition)
    Write-Step "Validating package ownership"
    Write-Host "All active profile claims resolved without ambiguity." -ForegroundColor Green

    $selectedPackages = Get-SelectedPackages $Definition

    Write-Step "Checking managers"
    Write-Host ("{0,-10} {1,-11} {2,-12} {3}" -f "manager", "status", "version", "path") -ForegroundColor DarkGray
    $managerProbes = @(@("winget", "scoop", "mise") | ForEach-Object { Get-ManagerProbe $_ })
    foreach ($probe in $managerProbes) {
        $version = if ($null -ne $probe.Version) { $probe.Version.ToString() } else { "-" }
        $path = if ($probe.Path) { $probe.Path } else { "-" }
        $color = if ($probe.Status -eq "available") { "Green" } else { "Yellow" }
        Write-Host ("{0,-10} {1,-11} {2,-12} {3}" -f $probe.Name, $probe.Status, $version, $path) -ForegroundColor $color
        if (@($probe.OtherPaths).Count -gt 0) {
            Write-Host ("           other paths: {0}" -f (@($probe.OtherPaths) -join " | ")) -ForegroundColor Yellow
        }
    }

    Write-Step "Checking Winenv runtime requirements"
    Write-Host ("{0,-10} {1,-18} {2,-12} {3}" -f "action", "requirement", "version", "path or fallback") -ForegroundColor DarkGray
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
        Write-Host ("{0,-10} {1,-18} {2,-12} {3}" -f $action, $probe.Name, $version, $location) -ForegroundColor $color
        if ($probe.Status -eq "outdated") {
            Write-Host "           requires >= $($probe.MinimumVersion)" -ForegroundColor Yellow
        }
        if (@($probe.OtherPaths).Count -gt 0) {
            Write-Host ("           other paths: {0}" -f (@($probe.OtherPaths) -join " | ")) -ForegroundColor Yellow
        }
        if (@($probe.Shadowing).Count -gt 0) {
            Write-Host ("           same-name aliases/functions ignored: {0}" -f (@($probe.Shadowing) -join " | ")) -ForegroundColor Yellow
        }
    }

    Write-Step "Checking command resolution"
    foreach ($package in $selectedPackages) {
        foreach ($command in @($package.commands)) {
            $resolved = @(Get-Command $command -All -ErrorAction SilentlyContinue)
            if ($resolved.Count -eq 0) {
                Write-Host ("{0,-12} missing (owner: {1})" -f $command, $package.owner) -ForegroundColor DarkGray
                continue
            }

            $paths = @($resolved | ForEach-Object {
                $location = if ($_.Path) { $_.Path } elseif ($_.Source) { $_.Source } else { $_.Name }
                "$($_.CommandType):$location"
            } | Select-Object -Unique)
            $color = if ($paths.Count -gt 1) { "Yellow" } else { "Green" }
            Write-Host ("{0,-12} {1}" -f $command, ($paths -join " | ")) -ForegroundColor $color
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
    Write-Host "WinGet: every installed package with an available update"
    if ($null -ne $scoopCommand) { Write-Host "Scoop:  Scoop itself, bucket indexes, and every installed app" }
    else { Write-Host "Scoop:  skipped (not installed)" -ForegroundColor DarkGray }
    if ($null -ne $miseCommand) { Write-Host "mise:   every active tool from the mise configuration" }
    else { Write-Host "mise:   skipped (not installed)" -ForegroundColor DarkGray }

    if (-not (Confirm-Operation "Update everything tracked by the installed package managers?")) {
        Write-Host "Update cancelled."
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
        if ($selected.Count -eq 0) { Write-Host "No packages selected."; return }
        $packages = @($selected | ForEach-Object { ConvertTo-PackageDefinition $_ })
    }

    Write-Step "Packages selected for removal"
    $packages | Select-Object owner, displayName, id | Format-Table -AutoSize
    if (-not (Confirm-Operation "Remove these packages using their displayed managers?")) {
        Write-Host "Removal cancelled."
        return
    }

    foreach ($package in $packages) {
        Write-Step "Removing $($package.displayName) with $($package.owner)"
        switch ($package.owner) {
            "winget" {
                Ensure-WinGet
                Invoke-Native (Get-ResolvedManagerCommand "winget") @("uninstall", "--id", [string]$package.id, "--exact", "--disable-interactivity")
            }
            "scoop" {
                $managerCommand = Get-OptionalManagerCommand "scoop"
                if ($null -eq $managerCommand) { throw "Scoop is unavailable." }
                Invoke-Native $managerCommand @("uninstall", [string]$package.id)
            }
            "mise" {
                $managerCommand = Get-OptionalManagerCommand "mise"
                if ($null -eq $managerCommand) { throw "mise is unavailable." }
                Invoke-Native $managerCommand @("unuse", "--global", [string]$package.id)
            }
            "vendor" { throw "Vendor-managed packages must be removed according to their recorded instructions." }
        }
    }
}

function Invoke-Cleanup {
    if (-not (Confirm-Operation "Remove old Scoop and unused mise versions?")) {
        Write-Host "Cleanup cancelled."
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

if ($Action -in @("profile", "use")) {
    Set-UserProfile -Apply:($Action -eq "use")
    return
}

if ($Action -eq "unuse") {
    Disable-UserProfile
    return
}

if ($Action -eq "help") {
    Show-WinenvHelp
    return
}

if ($Action -eq "version") {
    Show-WinenvVersion
    return
}

if ($Action -eq "self-update") {
    Update-WinenvSelf
    return
}

if ($Action -eq "bucket") {
    Invoke-ScoopBucketCommand
    return
}

$definition = Read-ProfileDefinition

switch ($Action) {
    "list" { Show-Profile $definition }
    "store" { Open-PackageStore $definition }
    "search" { Search-PackageCatalogs $definition }
    "info" { Show-PackageInfo $definition }
    "doctor" { Test-ProfileHealth $definition }
    "install" {
        Install-SelectedPackages $definition
        Invoke-Migrations
        Write-Host "`nInstall completed. Open a new PowerShell window and run 'win check'." -ForegroundColor Green
    }
    "update" { Update-All $definition }
    "remove" { Remove-Package $definition }
    "cleanup" { Invoke-Cleanup }
    "migrate" { Invoke-Migrations }
}
