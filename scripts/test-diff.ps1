$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root "win.ps1"
$previousLocalAppData = $env:LOCALAPPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-diff-" + [Guid]::NewGuid().ToString("N"))

try {
    $env:LOCALAPPDATA = $testRoot
    New-Item -ItemType Directory -Path (Join-Path $testRoot "Winenv") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $testRoot "Winenv\config.json") -Value '{"sentinel":"unchanged"}' -Encoding UTF8
    . $entry version -Language en | Out-Null

    $wingetPackage = [pscustomobject]@{ key = "code"; displayName = "Code"; owner = "winget"; id = "Microsoft.VisualStudioCode"; source = "winget"; version = ""; _defaultSelected = $true; _runtime = $false; profiles = @("desktop"); commands = @("code") }
    $scoopPackage = [pscustomobject]@{ key = "rg"; displayName = "ripgrep"; owner = "scoop"; id = "ripgrep"; bucket = "main"; version = ""; _defaultSelected = $true; _runtime = $false; profiles = @("development"); commands = @("rg") }
    $misePackage = [pscustomobject]@{ key = "node"; displayName = "Node.js"; owner = "mise"; id = "node"; version = "26"; _defaultSelected = $true; _runtime = $false; profiles = @("development"); commands = @("node") }

    $script:scoopInventoryCalled = $false
    function Get-ManagerProbe {
        param([string]$Name)
        [pscustomobject]@{ Status = if ($Name -eq "scoop") { "broken" } else { "available" } }
    }
    function Get-WinGetCandidates { param([string]$Query, [switch]$Installed) @() }
    function Get-WinGetExportInventory {
        [pscustomobject]@{
            Succeeded = $true
            Candidates = @(New-PackageCandidate -ManagerName "winget" -Id "Microsoft.VisualStudioCode" -Name "Code" -Version "1.2.3" -Source "winget")
        }
    }
    function Get-ScoopCandidates { $script:scoopInventoryCalled = $true; throw "Scoop inventory should have been skipped." }
    function Get-MiseCandidates { throw "simulated inventory failure" }

    $collected = Get-WinenvInstalledInventorySnapshot @($wingetPackage, $scoopPackage, $misePackage)
    if (@($collected.Candidates).Count -ne 1 -or $collected.ProviderStatus.winget -ne "available") {
        throw "The diff inventory snapshot did not retain the available WinGet inventory."
    }
    if ($script:scoopInventoryCalled -or $collected.ProviderStatus.scoop -ne "broken") {
        throw "The diff inventory snapshot did not preserve a broken manager without querying it."
    }
    if ($collected.ProviderStatus.mise -ne "inventory-error") {
        throw "The diff inventory snapshot did not isolate an inventory read failure."
    }

    $runtimePackage = [pscustomobject]@{ key = "powershell"; displayName = "PowerShell 7"; owner = "winget"; id = "Microsoft.PowerShell"; source = "winget"; version = ""; _defaultSelected = $true; _runtime = $true; profiles = @("runtime"); commands = @("pwsh") }
    $sourcePackage = [pscustomobject]@{ key = "source-app"; displayName = "Source app"; owner = "winget"; id = "Contoso.SourceApp"; source = "winget"; version = ""; _defaultSelected = $true; _runtime = $false; profiles = @("desktop"); commands = @() }
    $unknownPackage = [pscustomobject]@{ key = "unknown-version"; displayName = "Unknown version"; owner = "scoop"; id = "unknown-version"; bucket = "main"; version = "2.0.0"; _defaultSelected = $true; _runtime = $false; profiles = @("development"); commands = @() }
    $vendorPackage = [pscustomobject]@{ key = "vendor-app"; displayName = "Vendor app"; owner = "vendor"; id = "Contoso.VendorApp"; version = ""; _defaultSelected = $true; _runtime = $false; profiles = @("desktop"); commands = @() }

    $snapshot = [pscustomobject]@{
        ProviderStatus = @{ winget = "available"; scoop = "available"; mise = "available" }
        Candidates = @(
            (New-PackageCandidate -ManagerName "winget" -Id "Microsoft.VisualStudioCode" -Name "Code" -Version "1.2.3" -Source "winget"),
            (New-PackageCandidate -ManagerName "mise" -Id "node" -Name "Node.js" -Version "25.4.0" -Source "mise" -RequestedVersion "25"),
            (New-PackageCandidate -ManagerName "winget" -Id "Contoso.SourceApp" -Name "Source app" -Version "4.0.0" -Source "msstore"),
            (New-PackageCandidate -ManagerName "scoop" -Id "unknown-version" -Name "Unknown version" -Version "" -Source "main")
        )
    }
    function Get-RuntimeRequirementProbe {
        param($Package)
        [pscustomobject]@{ Name = "PowerShell 7"; Status = "available"; Version = [Version]"7.5.2"; MinimumVersion = [Version]"7.4.0"; Path = "C:\Program Files\PowerShell\7\pwsh.exe" }
    }

    $packages = @($runtimePackage, $wingetPackage, $scoopPackage, $misePackage, $sourcePackage, $unknownPackage, $vendorPackage)
    $rows = @(Compare-WinenvPackageState $packages $snapshot)
    $expectedStatuses = @{
        "PowerShell 7" = "satisfied"
        "Code" = "satisfied"
        "ripgrep" = "missing"
        "Node.js" = "version-drift"
        "Source app" = "source-drift"
        "Unknown version" = "unverifiable"
        "Vendor app" = "unverifiable"
    }
    foreach ($name in $expectedStatuses.Keys) {
        $row = @($rows | Where-Object Name -eq $name)
        if ($row.Count -ne 1 -or $row[0].Status -ne $expectedStatuses[$name]) {
            throw "The diff model did not classify '$name' as '$($expectedStatuses[$name])'."
        }
    }
    $sourceRow = @($rows | Where-Object Name -eq "Source app")[0]
    if ($sourceRow.Desired -ne "winget @ present" -or $sourceRow.Actual -ne "msstore @ 4.0.0") {
        throw "The diff model did not show both sides of a package source drift."
    }

    $unavailable = Compare-WinenvPackageState @($scoopPackage) ([pscustomobject]@{ ProviderStatus = @{ scoop = "missing" }; Candidates = @() })
    if (@($unavailable).Count -ne 1 -or $unavailable.Status -ne "manager-unavailable" -or $unavailable.Actual -ne "missing") {
        throw "The diff model did not classify an unavailable package manager."
    }

    $definition = [pscustomobject]@{ defaultProfiles = @("runtime", "desktop", "development"); packages = $packages }
    $script:comparisonSnapshot = $snapshot
    function Get-WinenvInstalledInventorySnapshot { param([array]$Packages) return $script:comparisonSnapshot }
    $Manager = "all"
    $Profiles = $null
    $filtered = @(Get-WinenvProfileDiff $definition "node")
    if ($filtered.Count -ne 1 -or $filtered[0].Name -ne "Node.js") {
        throw "The diff route did not respect its optional package query."
    }
    $Manager = "scoop"
    $filtered = @(Get-WinenvProfileDiff $definition "")
    if ($filtered.Count -ne 2 -or @($filtered | Where-Object Manager -ne "scoop").Count -ne 0) {
        throw "The diff route did not respect -From manager filtering."
    }
    $Manager = "all"

    $script:mutations = 0
    function Write-WinenvConfig { $script:mutations++ }
    function Sync-WinenvMiseConfig { $script:mutations++ }
    function Invoke-WinenvProviderOperation { $script:mutations++ }
    function Invoke-Native { $script:mutations++ }
    $configPath = Join-Path $testRoot "Winenv\config.json"
    $beforeConfig = Get-Content -Raw -LiteralPath $configPath

    $english = (Show-WinenvProfileDiff $definition "" 6>&1 | Out-String -Width 4096)
    if ($english -notmatch "Profile difference" -or $english -notmatch "version-drift" -or $english -notmatch "source-drift" -or $english -notmatch "Extra installed software is not treated as drift") {
        throw "The English diff output omitted statuses or its non-pruning boundary."
    }
    Initialize-WinenvLocalization "zh"
    $chinese = (Show-WinenvProfileDiff $definition "" 6>&1 | Out-String -Width 4096)
    if ($chinese -notmatch "Profile .+" -or $chinese -notmatch "版本偏差" -or $chinese -notmatch "来源偏差" -or $chinese -notmatch "winget @ 存在" -or $chinese -notmatch "额外安装的软件不视为偏差" -or $chinese -match "Profile difference") {
        throw "The Simplified Chinese diff output is incomplete."
    }
    if ($script:mutations -ne 0 -or (Get-Content -Raw -LiteralPath $configPath) -ne $beforeConfig) {
        throw "The read-only diff route invoked a mutation or changed persisted state."
    }
} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host "Profile diff checks passed." -ForegroundColor Green
