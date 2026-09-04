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
    [Alias("Lang")]
    [ValidateSet("auto", "en", "zh", "en-US", "zh-CN")]
    [string]$Language,
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
$AdoptedProfileSource = "generated:installed"
$AdoptedProfileId = "adopted"
$AdoptedProfileName = "adopted"
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
    "apps" = "scan"
    "lang" = "language"
}
$CanonicalActions = @(
    "help", "list", "use", "unuse", "profile", "store", "search", "info", "doctor",
    "install", "update", "remove", "cleanup", "migrate", "version", "self-update", "bucket",
    "scan", "adopt", "diff", "language"
)

$WinenvRoot = $PSScriptRoot
$WinenvEntryPath = $PSCommandPath
$WinenvProviderRegistry = [ordered]@{}
$WinenvModulePaths = @(
    "src/Localization.ps1",
    "src/Core.ps1",
    "src/Providers/Provider.Contract.ps1",
    "src/Profiles.ps1",
    "src/Providers/WinGet.ps1",
    "src/Providers/Scoop.ps1",
    "src/Providers/Mise.ps1",
    "src/Providers/Vendor.ps1",
    "src/Inventory.ps1",
    "src/Planning.ps1",
    "src/State.ps1",
    "src/Commands.ps1"
)

$localizationModulePath = Join-Path $WinenvRoot $WinenvModulePaths[0]
if (-not (Test-Path -LiteralPath $localizationModulePath)) {
    throw "Winenv internal module is missing: $($WinenvModulePaths[0])"
}
. $localizationModulePath
Initialize-WinenvLocalization $Language

foreach ($relativeModulePath in @($WinenvModulePaths | Select-Object -Skip 1)) {
    $modulePath = Join-Path $WinenvRoot $relativeModulePath
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw (ConvertTo-WinenvLocalizedText "Winenv internal module is missing: $relativeModulePath")
    }
    . $modulePath
}

try {
    Initialize-WinenvProviders
} catch {
    $localizedMessage = ConvertTo-WinenvLocalizedText ([string]$_.Exception.Message)
    if ($localizedMessage -eq [string]$_.Exception.Message) { throw }
    throw $localizedMessage
}

if ([string]::IsNullOrWhiteSpace($Action)) {
    $Action = "store"
} elseif ($ActionAliases.ContainsKey($Action)) {
    $Action = $ActionAliases[$Action]
} elseif ($CanonicalActions -notcontains $Action) {
    if (-not [string]::IsNullOrWhiteSpace($Target)) {
        throw (ConvertTo-WinenvLocalizedText "Use quotes around a multi-word search, for example: win 'Visual Studio Code'")
    }
    $Target = $Action
    $Action = "store"
}

try {
    if ($Action -eq "language") {
        Set-WinenvLanguage
        return
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
        "diff" { Show-WinenvProfileDiff $definition $Target }
        "scan" { Show-InstalledInventory $definition }
        "adopt" { Adopt-InstalledPackages $definition }
        "store" { Open-PackageStore $definition }
        "search" { Search-PackageCatalogs $definition }
        "info" { Show-PackageInfo $definition }
        "doctor" { Test-ProfileHealth $definition }
        "install" {
            Install-SelectedPackages $definition
            Invoke-Migrations
            Write-WinenvHost "`nInstall completed. Open a new PowerShell window and run 'win check'." -ForegroundColor Green
        }
        "update" { Update-All $definition }
        "remove" { Remove-Package $definition }
        "cleanup" { Invoke-Cleanup }
        "migrate" { Invoke-Migrations }
    }
} catch {
    $localizedMessage = ConvertTo-WinenvLocalizedText ([string]$_.Exception.Message)
    if ($localizedMessage -eq [string]$_.Exception.Message) { throw }
    throw $localizedMessage
}
