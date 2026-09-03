[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("list", "ls", "profile", "store", "browse", "search", "find", "info", "show", "doctor", "check", "install", "add", "update", "up", "remove", "rm", "cleanup", "clean", "migrate", "version", "self-update", "selfup")]
    [string]$Action = "list",

    [string[]]$Profiles,
    [Parameter(Position = 1)]
    [Alias("PackageKey", "Query")]
    [string]$Target,
    [ValidateSet("all", "managed", "winget", "scoop", "mise")]
    [string]$Manager = "all",
    [switch]$DryRun,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"
$ProfilePath = Join-Path $PSScriptRoot "profile.json"
$VersionPath = Join-Path $PSScriptRoot "VERSION"
$MigrationPath = Join-Path $PSScriptRoot "migrations"
$StateRoot = Join-Path $env:LOCALAPPDATA "Winenv"
$StatePath = Join-Path $StateRoot "state.json"
$ConfigPath = Join-Path $StateRoot "config.json"
$LocalUserProfilePath = Join-Path $StateRoot "user-profile.json"
$AllowedOwners = @("winget", "scoop", "mise", "vendor")
$ActionAliases = @{
    "ls" = "list"
    "browse" = "store"
    "find" = "search"
    "show" = "info"
    "check" = "doctor"
    "add" = "install"
    "up" = "update"
    "rm" = "remove"
    "clean" = "cleanup"
    "selfup" = "self-update"
}

if ($ActionAliases.ContainsKey($Action)) {
    $Action = $ActionAliases[$Action]
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
    $env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Read-ProfileFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Profile not found: $Path" }
    $definition = Get-Content -Raw -Path $Path | ConvertFrom-Json
    if ($definition.schemaVersion -ne 1) {
        throw "Unsupported profile schema version: $($definition.schemaVersion)"
    }
    return $definition
}

function Read-WinenvConfig {
    if (-not (Test-Path $ConfigPath)) { return [pscustomobject]@{ userProfile = "" } }
    $config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    return [pscustomobject]@{ userProfile = [string]$config.userProfile }
}

function Write-WinenvConfig {
    param([string]$UserProfile)
    Write-Plan "Set active user profile to '$UserProfile' in $ConfigPath"
    if ($DryRun) { return }
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    [pscustomobject]@{ userProfile = $UserProfile } |
        ConvertTo-Json |
        Set-Content -Path $ConfigPath -Encoding UTF8
}

function Resolve-ActiveUserProfilePath {
    param([string]$Selection)
    if ([string]::IsNullOrWhiteSpace($Selection)) { return $null }
    if ($Selection -eq "@local") { return $LocalUserProfilePath }
    throw "Unsupported user profile selection in $ConfigPath. Run 'win profile default' to reset it."
}

function Merge-ProfileDefinitions {
    param(
        $RuntimeProfile,
        $UserProfile
    )
    if ($null -eq $UserProfile) { return $RuntimeProfile }
    return [pscustomobject]@{
        schemaVersion = 1
        name = "$($RuntimeProfile.name) + $($UserProfile.name)"
        defaultProfiles = @(@($RuntimeProfile.defaultProfiles) + @($UserProfile.defaultProfiles) | Select-Object -Unique)
        scoopBuckets = @(@($RuntimeProfile.scoopBuckets) + @($UserProfile.scoopBuckets) | Select-Object -Unique)
        packages = @(@($RuntimeProfile.packages) + @($UserProfile.packages))
    }
}

function Read-ProfileDefinition {
    $runtimeProfile = Read-ProfileFile $ProfilePath
    $config = Read-WinenvConfig
    $userProfilePath = Resolve-ActiveUserProfilePath $config.userProfile
    if ($null -eq $userProfilePath) { return $runtimeProfile }
    return Merge-ProfileDefinitions $runtimeProfile (Read-ProfileFile $userProfilePath)
}

function Show-UserProfileStatus {
    $config = Read-WinenvConfig
    $selection = if ([string]::IsNullOrWhiteSpace($config.userProfile)) { "none (runtime only)" } else { $config.userProfile }
    Write-Host "Runtime profile: $ProfilePath"
    Write-Host "User profile:    $selection"
    if (Test-Path $LocalUserProfilePath) {
        Write-Host "Private copy:    $LocalUserProfilePath"
    }
    Write-Host "`nUse 'win profile <json-path>' to import one, or 'win profile default' to disable it." -ForegroundColor DarkGray
}

function Set-UserProfile {
    if ([string]::IsNullOrWhiteSpace($Target)) {
        Show-UserProfileStatus
        return
    }
    if ($Target -in @("default", "none", "off")) {
        Write-WinenvConfig ""
        Write-Host "User profile disabled; Winenv will use only its runtime profile." -ForegroundColor Green
        return
    }

    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) {
        throw "User profile JSON was not found: $Target"
    }
    $candidatePath = (Resolve-Path -LiteralPath $Target).Path
    $selection = "@local"

    $runtimeProfile = Read-ProfileFile $ProfilePath
    $userProfile = Read-ProfileFile $candidatePath
    $merged = Merge-ProfileDefinitions $runtimeProfile $userProfile
    Assert-ProfileDefinition $merged

    if ($selection -eq "@local") {
        Write-Plan "Copy $candidatePath to $LocalUserProfilePath"
        if (-not $DryRun) {
            New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
            if ([IO.Path]::GetFullPath($candidatePath) -ine [IO.Path]::GetFullPath($LocalUserProfilePath)) {
                Copy-Item -LiteralPath $candidatePath -Destination $LocalUserProfilePath -Force
            }
        }
    }
    Write-WinenvConfig $selection
    Write-Host "User profile '$($userProfile.name)' is active. Run 'win add' to apply it." -ForegroundColor Green
}

function Get-SelectedProfiles {
    param($Definition)
    if ($Profiles -and $Profiles.Count -gt 0) {
        return @($Profiles)
    }
    return @($Definition.defaultProfiles)
}

function Get-SelectedPackages {
    param($Definition)
    $selectedProfiles = Get-SelectedProfiles $Definition
    return @($Definition.packages | Where-Object {
        $packageProfiles = @($_.profiles)
        @($packageProfiles | Where-Object { $selectedProfiles -contains $_ }).Count -gt 0
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
        (@($Package.profiles) -join " ")
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
    $managed = @($Definition.packages | Where-Object { $_.key -eq $Reference })
    if ($managed.Count -eq 1) { return $managed[0] }
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
        throw "info requires a profile key or manager token. Example: win info winget:winget/Microsoft.PowerToys"
    }

    $package = Resolve-PackageReference $Definition $Target
    if ($null -eq $package) { throw "Unknown package reference: $Target" }

    Write-Host $package.displayName -ForegroundColor Cyan
    Write-Host ("Reference: {0}" -f $Target)
    Write-Host ("Manager:   {0}" -f $package.owner)
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
            if (Test-Command "winget") {
                $source = if ($package.source) { [string]$package.source } else { "winget" }
                Invoke-Native "winget" @("show", "--id", [string]$package.id, "--exact", "--source", $source, "--accept-source-agreements", "--disable-interactivity") -IgnoreExitCode
            } else { Write-Host "WinGet is unavailable." }
        }
        "scoop" {
            if (Test-Command "scoop") {
                $qualifiedId = if ($package.bucket) { "$($package.bucket)/$($package.id)" } else { [string]$package.id }
                Invoke-Native "scoop" @("info", $qualifiedId) -IgnoreExitCode
            } else { Write-Host "Scoop is unavailable." }
        }
        "mise" {
            if (Test-Command "mise") { Invoke-Native "mise" @("registry", [string]$package.id) -IgnoreExitCode }
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
    if (-not (Test-Command "fzf")) {
        $Candidates | Select-Object Manager, Source, Name, Id, Version, ManagedKey | Format-Table -AutoSize
        throw "Interactive selection requires fzf. Install the baseline package with 'win add fzf'."
    }

    $rows = @($Candidates | ForEach-Object {
        @([string]$_.Token, [string]$_.Manager, [string]$_.Source, [string]$_.Name, [string]$_.Id, [string]$_.Version, [string]$_.ManagedKey) -join "`t"
    })
    $previewCommand = "pwsh -NoLogo -NoProfile -File `"$PSCommandPath`" info {1}"
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

    $selectedRows = @($rows | & fzf @fzfArguments)
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
        if ($DryRun) { throw "store requires a search query in dry-run mode. Example: win store powertoys -DryRun" }
        $Query = Read-Host "Search WinGet, Scoop, and mise"
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

    foreach ($package in @($Definition.packages)) {
        if ($AllowedOwners -notcontains $package.owner) {
            $errors.Add("$($package.key): unsupported owner '$($package.owner)'")
        }

        if ($seenKeys.ContainsKey($package.key)) {
            $errors.Add("Duplicate package key: $($package.key)")
        } else {
            $seenKeys[$package.key] = $true
        }

        $identity = "$($package.owner):$($package.id)".ToLowerInvariant()
        if ($seenPackages.ContainsKey($identity)) {
            $errors.Add("Duplicate managed package: $identity")
        } else {
            $seenPackages[$identity] = $true
        }

        foreach ($command in @($package.commands)) {
            $normalizedCommand = $command.ToLowerInvariant()
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

function Ensure-WinGet {
    if (-not (Test-Command "winget")) {
        throw "WinGet is required. Update or install App Installer from Microsoft Store, then run this command again."
    }
}

function Ensure-Mise {
    if (Test-Command "mise") { return }

    Write-Step "Installing mise with WinGet"
    Invoke-Native "winget" @(
        "install", "--id", "jdx.mise", "--exact", "--source", "winget",
        "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"
    )
    if ($DryRun) { return }

    Refresh-ProcessPath
    if (-not (Test-Command "mise")) {
        throw "mise was installed but is not visible in this process. Open a new PowerShell window and run the command again."
    }
}

function Ensure-Scoop {
    if (Test-Command "scoop") { return }

    Write-Step "Preparing the official Scoop installer"
    $installerUri = "https://get.scoop.sh"
    if ($DryRun) {
        Write-Plan "Download and review $installerUri, then execute after confirmation"
        return
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
    if (-not (Test-Command "scoop")) {
        throw "Scoop was installed but is not visible in this process. Open a new PowerShell window and run the command again."
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
    Invoke-Native "winget" @(
        "install", "--id", [string]$Package.id, "--exact", "--source", $source,
        "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"
    )
}

function Install-ScoopPackage {
    param($Package)
    $qualifiedId = if ($Package.bucket) { "$($Package.bucket)/$($Package.id)" } else { [string]$Package.id }
    Invoke-Native "scoop" @("install", $qualifiedId)
}

function Install-MisePackage {
    param($Package)
    $version = if ($Package.version) { [string]$Package.version } else { "latest" }
    Invoke-Native "mise" @("use", "--global", "$($Package.id)@$version")
}

function Install-Packages {
    param(
        $Definition,
        [array]$Packages
    )
    $packages = @($Packages)
    $owners = @($packages | ForEach-Object { $_.owner } | Sort-Object -Unique)

    Ensure-WinGet
    if ($owners -contains "scoop") { Ensure-Scoop }
    if ($owners -contains "mise") { Ensure-Mise }

    if (($owners -contains "scoop") -and (Test-Command "scoop")) {
        foreach ($bucket in @($Definition.scoopBuckets)) {
            if ($bucket -ne "main") {
                Invoke-Native "scoop" @("bucket", "add", [string]$bucket) -IgnoreExitCode
            }
        }
    }

    foreach ($package in $packages) {
        Write-Step "Installing $($package.displayName) with $($package.owner)"
        switch ($package.owner) {
            "winget" { Install-WinGetPackage $package }
            "scoop" { Install-ScoopPackage $package }
            "mise" { Install-MisePackage $package }
            "vendor" {
                Write-Host "Manual vendor-managed package: $($package.displayName)" -ForegroundColor Yellow
                if ($package.instructions) { Write-Host $package.instructions }
            }
        }
    }

    Enable-WinenvInPowerShell
}

function Install-SelectedPackages {
    param($Definition)
    if ([string]::IsNullOrWhiteSpace($Target)) {
        Install-Packages $Definition @(Get-SelectedPackages $Definition)
        return
    }

    $package = Resolve-PackageReference $Definition $Target
    if ($null -ne $package) {
        Install-Packages $Definition @($package)
        return
    }

    $candidates = @(Get-CatalogCandidates $Definition $Target)
    if ($candidates.Count -eq 0) {
        throw "No package matched '$Target'. Try 'win search $Target' or use a manager token."
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
    $selectedProfiles = Get-SelectedProfiles $Definition
    Write-Host "Profile: $($Definition.name)"
    $config = Read-WinenvConfig
    $userProfile = if ([string]::IsNullOrWhiteSpace($config.userProfile)) { "none" } else { $config.userProfile }
    Write-Host "User profile: $userProfile"
    Write-Host "Selected profiles: $($selectedProfiles -join ', ')"
    Get-SelectedPackages $Definition |
        Select-Object key, displayName, owner, id, @{Name = "profiles"; Expression = { $_.profiles -join "," }} |
        Sort-Object owner, key |
        Format-Table -AutoSize
}

function Test-ProfileHealth {
    param($Definition)
    Write-Step "Validating package ownership"
    Assert-ProfileDefinition $Definition
    Write-Host "Manifest ownership is consistent." -ForegroundColor Green

    $selectedPackages = Get-SelectedPackages $Definition
    $requiredOwners = @($selectedPackages | ForEach-Object { $_.owner } | Sort-Object -Unique)

    Write-Step "Checking managers"
    foreach ($owner in $requiredOwners) {
        if ($owner -eq "vendor") { continue }
        $available = Test-Command $owner
        $status = if ($available) { "available" } else { "missing" }
        $color = if ($available) { "Green" } else { "Yellow" }
        Write-Host ("{0,-10} {1}" -f $owner, $status) -ForegroundColor $color
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
                if ($_.Path) { $_.Path } elseif ($_.Source) { $_.Source } else { $_.Name }
            } | Select-Object -Unique)
            $color = if ($paths.Count -gt 1) { "Yellow" } else { "Green" }
            Write-Host ("{0,-12} {1}" -f $command, ($paths -join " | ")) -ForegroundColor $color
        }
    }
}

function Update-All {
    param($Definition)
    Update-WinenvSelf
    Ensure-WinGet

    Write-Step "Update scope"
    Write-Host "WinGet: every installed package with an available update"
    if (Test-Command "scoop") { Write-Host "Scoop:  Scoop itself, bucket indexes, and every installed app" }
    else { Write-Host "Scoop:  skipped (not installed)" -ForegroundColor DarkGray }
    if (Test-Command "mise") { Write-Host "mise:   every active tool from the mise configuration" }
    else { Write-Host "mise:   skipped (not installed)" -ForegroundColor DarkGray }

    if (-not (Confirm-Operation "Update everything tracked by the installed package managers?")) {
        Write-Host "Update cancelled."
        return
    }

    Write-Step "Updating all WinGet packages"
    Invoke-Native "winget" @("source", "update")
    Invoke-Native "winget" @(
        "upgrade", "--all", "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"
    ) -IgnoreExitCode

    if (Test-Command "scoop") {
        Write-Step "Updating all Scoop packages"
        Invoke-Native "scoop" @("update")
        Invoke-Native "scoop" @("update", "*") -IgnoreExitCode
    }

    if (Test-Command "mise") {
        Write-Step "Updating all active mise tools"
        $previousAge = $env:MISE_MINIMUM_RELEASE_AGE
        try {
            $env:MISE_MINIMUM_RELEASE_AGE = "0"
            Invoke-Native "mise" @("up")
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
                Invoke-Native "winget" @("uninstall", "--id", [string]$package.id, "--exact", "--disable-interactivity")
            }
            "scoop" {
                if (-not (Test-Command "scoop")) { throw "Scoop is unavailable." }
                Invoke-Native "scoop" @("uninstall", [string]$package.id)
            }
            "mise" {
                if (-not (Test-Command "mise")) { throw "mise is unavailable." }
                Invoke-Native "mise" @("unuse", "--global", [string]$package.id)
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

    if (Test-Command "scoop") {
        Write-Step "Cleaning old Scoop versions"
        Invoke-Native "scoop" @("cleanup", "*")
        Invoke-Native "scoop" @("cache", "rm", "*")
    }
    if (Test-Command "mise") {
        Write-Step "Pruning unused mise versions"
        Invoke-Native "mise" @("prune")
    }
}

if ($Action -eq "profile") {
    Set-UserProfile
    return
}

$definition = Read-ProfileDefinition
Assert-ProfileDefinition $definition

switch ($Action) {
    "list" { Show-Profile $definition }
    "store" { Open-PackageStore $definition }
    "search" { Search-PackageCatalogs $definition }
    "info" { Show-PackageInfo $definition }
    "doctor" { Test-ProfileHealth $definition }
    "install" {
        Install-SelectedPackages $definition
        Invoke-Migrations
        Write-Host "`nInstall completed. Open a new PowerShell window and run 'win doctor'." -ForegroundColor Green
    }
    "update" { Update-All $definition }
    "version" { Show-WinenvVersion }
    "self-update" { Update-WinenvSelf }
    "remove" { Remove-Package $definition }
    "cleanup" { Invoke-Cleanup }
    "migrate" { Invoke-Migrations }
}
