[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("list", "ls", "search", "find", "doctor", "check", "install", "add", "update", "up", "remove", "rm", "cleanup", "clean", "migrate", "version", "self-update", "selfup")]
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
$AllowedOwners = @("winget", "scoop", "mise", "vendor")
$ActionAliases = @{
    "ls" = "list"
    "find" = "search"
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

function Read-ProfileDefinition {
    if (-not (Test-Path $ProfilePath)) {
        throw "Profile not found: $ProfilePath"
    }

    $definition = Get-Content -Raw -Path $ProfilePath | ConvertFrom-Json
    if ($definition.schemaVersion -ne 1) {
        throw "Unsupported profile schema version: $($definition.schemaVersion)"
    }
    return $definition
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

function Get-PackagesToInstall {
    param($Definition)
    if ([string]::IsNullOrWhiteSpace($Target)) {
        return @(Get-SelectedPackages $Definition)
    }

    $packages = @($Definition.packages | Where-Object { $_.key -eq $Target })
    if ($packages.Count -ne 1) {
        throw "Package '$Target' is not in the managed profile. Run 'win search $Target' to inspect available packages."
    }
    return $packages
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

function Search-PackageCatalogs {
    param($Definition)
    if ([string]::IsNullOrWhiteSpace($Target)) {
        throw "search requires a query. Example: win search ripgrep"
    }

    Write-Step "Managed profile"
    $managedMatches = @($Definition.packages | Where-Object {
        (Test-PackageMatch $_ $Target) -and
        ($Manager -in @("all", "managed") -or $_.owner -eq $Manager)
    })
    if ($managedMatches.Count -gt 0) {
        $managedMatches |
            Select-Object key, displayName, owner, id, @{Name = "install"; Expression = { "win add $($_.key)" }} |
            Sort-Object owner, key |
            Format-Table -AutoSize
    } else {
        Write-Host "No matching package is currently managed by Winenv." -ForegroundColor DarkGray
    }

    if ($Manager -eq "managed") { return }

    if ($Manager -in @("all", "winget")) {
        Write-Step "WinGet catalog"
        if (Test-Command "winget") {
            Invoke-Native "winget" @(
                "search", "--query", $Target, "--count", "20",
                "--accept-source-agreements", "--disable-interactivity"
            ) -IgnoreExitCode
        } else {
            Write-Host "WinGet is unavailable; this catalog was skipped." -ForegroundColor Yellow
        }
    }

    if ($Manager -in @("all", "scoop")) {
        Write-Step "Scoop catalog"
        if (Test-Command "scoop") {
            Invoke-Native "scoop" @("search", $Target) -IgnoreExitCode
        } else {
            Write-Host "Scoop is not installed; this catalog was skipped." -ForegroundColor DarkGray
        }
    }

    if ($Manager -in @("all", "mise")) {
        Write-Step "mise registry"
        if (-not (Test-Command "mise")) {
            Write-Host "mise is not installed; this registry was skipped." -ForegroundColor DarkGray
        } elseif ($DryRun) {
            Write-Plan "mise registry --json | filter '$Target'"
        } else {
            $registryText = (& mise registry --json | Out-String)
            if ($LASTEXITCODE -ne 0) {
                Write-Host "mise registry search failed." -ForegroundColor Yellow
            } else {
                $registry = @($registryText | ConvertFrom-Json)
                $miseMatches = @($registry | Where-Object {
                    $searchable = @(
                        [string]$_.short,
                        [string]$_.description,
                        (@($_.aliases) -join " "),
                        (@($_.backends) -join " ")
                    ) -join " "
                    $searchable.IndexOf($Target, [StringComparison]::OrdinalIgnoreCase) -ge 0
                } | Select-Object -First 20)

                if ($miseMatches.Count -gt 0) {
                    $miseMatches |
                        Select-Object @{Name = "tool"; Expression = { $_.short }},
                            @{Name = "backend"; Expression = { @($_.backends)[0] }}, description |
                        Format-Table -AutoSize
                } else {
                    Write-Host "No matching tool was found in the mise registry." -ForegroundColor DarkGray
                }
            }
        }
    }

    Write-Host "`nUse -Manager managed|winget|scoop|mise to narrow the next search." -ForegroundColor DarkGray
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

function Install-SelectedPackages {
    param($Definition)
    $packages = Get-PackagesToInstall $Definition
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
    $selectedPackages = Get-SelectedPackages $Definition
    $wingetPackages = @($selectedPackages | Where-Object { $_.owner -eq "winget" })
    $scoopPackages = @($selectedPackages | Where-Object { $_.owner -eq "scoop" })
    $misePackages = @($selectedPackages | Where-Object { $_.owner -eq "mise" })

    Write-Step "Refreshing WinGet sources"
    Invoke-Native "winget" @("source", "update")

    Write-Step "Managed update plan"
    $selectedPackages |
        Select-Object key, displayName, owner, id |
        Sort-Object owner, key |
        Format-Table -AutoSize

    if (-not (Confirm-Operation "Continue with updates for these managed packages?")) {
        Write-Host "Update cancelled."
        return
    }

    Write-Step "Updating WinGet packages"
    foreach ($package in $wingetPackages) {
        $source = if ($package.source) { [string]$package.source } else { "winget" }
        Invoke-Native "winget" @(
            "upgrade", "--id", [string]$package.id, "--exact", "--source", $source,
            "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"
        ) -IgnoreExitCode
    }

    if ((Test-Command "scoop") -and $scoopPackages.Count -gt 0) {
        Write-Step "Updating Scoop packages"
        Invoke-Native "scoop" @("update")
        foreach ($package in $scoopPackages) {
            Invoke-Native "scoop" @("update", [string]$package.id) -IgnoreExitCode
        }
    }

    if ((Test-Command "mise") -and $misePackages.Count -gt 0) {
        Write-Step "Updating mise tools"
        $previousAge = $env:MISE_MINIMUM_RELEASE_AGE
        try {
            $env:MISE_MINIMUM_RELEASE_AGE = "0"
            $miseArguments = @("up") + @($misePackages | ForEach-Object { [string]$_.id })
            Invoke-Native "mise" $miseArguments
        } finally {
            $env:MISE_MINIMUM_RELEASE_AGE = $previousAge
        }
    }

    Invoke-Migrations
}

function Remove-ManagedPackage {
    param($Definition)
    if ([string]::IsNullOrWhiteSpace($Target)) {
        throw "remove requires a package key. Use 'list' to see keys."
    }

    $package = @($Definition.packages | Where-Object { $_.key -eq $Target })
    if ($package.Count -ne 1) {
        throw "Unknown or ambiguous package key: $Target"
    }
    $package = $package[0]

    Write-Step "Removing $($package.displayName) with its owner: $($package.owner)"
    if (-not (Confirm-Operation "Remove $($package.displayName)?")) {
        Write-Host "Removal cancelled."
        return
    }

    switch ($package.owner) {
        "winget" { Invoke-Native "winget" @("uninstall", "--id", [string]$package.id, "--exact", "--disable-interactivity") }
        "scoop" { Invoke-Native "scoop" @("uninstall", [string]$package.id) }
        "mise" { Invoke-Native "mise" @("unuse", "--global", [string]$package.id) }
        "vendor" { throw "Vendor-managed packages must be removed according to their recorded instructions." }
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

$definition = Read-ProfileDefinition
Assert-ProfileDefinition $definition

switch ($Action) {
    "list" { Show-Profile $definition }
    "search" { Search-PackageCatalogs $definition }
    "doctor" { Test-ProfileHealth $definition }
    "install" {
        Install-SelectedPackages $definition
        Invoke-Migrations
        Write-Host "`nInstall completed. Open a new PowerShell window and run 'win doctor'." -ForegroundColor Green
    }
    "update" { Update-All $definition }
    "version" { Show-WinenvVersion }
    "self-update" { Update-WinenvSelf }
    "remove" { Remove-ManagedPackage $definition }
    "cleanup" { Invoke-Cleanup }
    "migrate" { Invoke-Migrations }
}
