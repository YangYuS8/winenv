$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "Validating JSON and schema..."
$profilePath = Join-Path $root "profile.json"
$schemaPath = Join-Path $root "profile.schema.json"
foreach ($candidatePath in @($profilePath)) {
    $profileText = Get-Content -Raw -Path $candidatePath
    $schemaValid = $profileText | Test-Json -SchemaFile $schemaPath
    if (-not $schemaValid) {
        throw "$candidatePath does not match profile.schema.json"
    }

    $profile = $profileText | ConvertFrom-Json
    $duplicateKeys = @($profile.packages | Group-Object key | Where-Object Count -gt 1)
    $duplicatePackages = @($profile.packages | Group-Object {
        $location = if ($_.owner -eq "winget") { $_.source } elseif ($_.owner -eq "scoop") { $_.bucket } else { $_.owner }
        "$($_.owner):$location`:$($_.id)".ToLowerInvariant()
    } | Where-Object Count -gt 1)
    if ($duplicateKeys.Count -gt 0 -or $duplicatePackages.Count -gt 0) {
        throw "$candidatePath contains duplicate package ownership."
    }

    $commandOwners = @{}
    foreach ($package in @($profile.packages)) {
        foreach ($command in @($package.commands)) {
            $key = $command.ToLowerInvariant()
            if ($commandOwners.ContainsKey($key) -and $commandOwners[$key] -ne $package.owner) {
                throw "Command '$command' has multiple owners in $candidatePath."
            }
            $commandOwners[$key] = $package.owner
        }
    }
}

Write-Host "Parsing PowerShell files..."
foreach ($file in @(Get-ChildItem -Path $root -Filter "*.ps1" -File) + @(Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1" -File)) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw "PowerShell parser errors in $($file.Name): $($errors -join '; ')"
    }
}

Write-Host "Exercising command routes..."
$testLocalAppData = Join-Path ([IO.Path]::GetTempPath()) ("winenv-tests-" + [Guid]::NewGuid().ToString("N"))
$env:LOCALAPPDATA = $testLocalAppData
$env:MISE_CONFIG_DIR = Join-Path $testLocalAppData "mise"
$testUserProfilePath = Join-Path $testLocalAppData "test-user-profile.json"
$testSharedProfilePath = Join-Path $testLocalAppData "test-shared-profile.json"
$testConflictProfilePath = Join-Path $testLocalAppData "test-conflict-profile.json"
$testProviderConflictProfilePath = Join-Path $testLocalAppData "test-provider-conflict-profile.json"
New-Item -ItemType Directory -Path $testLocalAppData -Force | Out-Null
$testBinPath = Join-Path $testLocalAppData "bin"
New-Item -ItemType Directory -Path $testBinPath -Force | Out-Null
$originalProcessPath = $env:Path
$originalUpperProcessPath = $env:PATH
$pathSeparator = [string][IO.Path]::PathSeparator
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    $testFzfPath = Join-Path $testBinPath "fzf.cmd"
    @(
        "@echo off",
        'if "%~1"=="--version" (echo 0.73.0 & exit /b 0)',
        'findstr /b /c:"winget:winget/Microsoft.PowerToys"'
    ) | Set-Content -Path $testFzfPath -Encoding ASCII
} else {
    $testFzfPath = Join-Path $testBinPath "fzf"
    @(
        "#!/bin/sh",
        'if [ "$1" = "--version" ]; then echo 0.73.0; exit 0; fi',
        'while IFS= read -r line; do case "$line" in winget:winget/Microsoft.PowerToys*) printf "%s\n" "$line"; break;; esac; done'
    ) | Set-Content -Path $testFzfPath -Encoding utf8NoBOM
    & chmod "+x" $testFzfPath
}
$env:Path = "$testBinPath$pathSeparator$originalProcessPath"
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    $env:PATH = "$testBinPath$pathSeparator$originalUpperProcessPath"
}
[pscustomobject]@{
    schemaVersion = 1
    name = "test-user"
    defaultProfiles = @("personal-test")
    scoopBuckets = @("main")
    packages = @(
        [pscustomobject]@{ key = "vscode"; displayName = "Visual Studio Code"; owner = "winget"; id = "Microsoft.VisualStudioCode"; source = "winget"; profiles = @("personal-test"); commands = @("code") },
        [pscustomobject]@{ key = "ripgrep"; displayName = "ripgrep"; owner = "scoop"; id = "ripgrep"; bucket = "main"; profiles = @("personal-test"); commands = @("rg") },
        [pscustomobject]@{ key = "node"; displayName = "Node.js"; owner = "mise"; id = "node"; version = "26"; profiles = @("personal-test"); commands = @("node", "npm", "npx") }
    )
} | ConvertTo-Json -Depth 8 | Set-Content -Path $testUserProfilePath -Encoding UTF8

[pscustomobject]@{
    schemaVersion = 1
    name = "shared-tools"
    defaultProfiles = @("shared-default")
    scoopBuckets = @("main")
    packages = @(
        [pscustomobject]@{ key = "code-editor"; displayName = "Visual Studio Code"; owner = "winget"; id = "Microsoft.VisualStudioCode"; source = "winget"; profiles = @("shared-default"); commands = @("code") },
        [pscustomobject]@{ key = "jq"; displayName = "jq"; owner = "scoop"; id = "jq"; bucket = "main"; profiles = @("shared-default"); commands = @("jq") }
    )
} | ConvertTo-Json -Depth 8 | Set-Content -Path $testSharedProfilePath -Encoding UTF8

[pscustomobject]@{
    schemaVersion = 1
    name = "older-node"
    defaultProfiles = @("development")
    scoopBuckets = @()
    packages = @(
        [pscustomobject]@{ key = "node"; displayName = "Node.js 24"; owner = "mise"; id = "node"; version = "24"; profiles = @("development"); commands = @("node", "npm", "npx") }
    )
} | ConvertTo-Json -Depth 8 | Set-Content -Path $testConflictProfilePath -Encoding UTF8

[pscustomobject]@{
    schemaVersion = 1
    name = "winget-ripgrep"
    defaultProfiles = @("development")
    scoopBuckets = @()
    packages = @(
        [pscustomobject]@{ key = "ripgrep-winget"; displayName = "ripgrep (WinGet)"; owner = "winget"; id = "BurntSushi.ripgrep.MSVC"; source = "winget"; profiles = @("development"); commands = @("rg"); provides = @("cli:search") }
    )
} | ConvertTo-Json -Depth 8 | Set-Content -Path $testProviderConflictProfilePath -Encoding UTF8

function global:winget {
    switch ($args[0]) {
        "search" {
            @(
                "Name                  Id                        Version Source",
                "--------------------  ------------------------  ------- ------",
                "Microsoft PowerToys   Microsoft.PowerToys       0.95.1  winget",
                "PowerToys Preview     Microsoft.PowerToys.Dev   0.96.0  msstore"
            )
        }
        "list" {
            @(
                "Name                  Id                        Version Source",
                "--------------------  ------------------------  ------- ------",
                "Microsoft PowerToys   Microsoft.PowerToys       0.95.0  winget"
            )
        }
    }
    $global:LASTEXITCODE = 0
}
function global:scoop {
    switch ($args[0]) {
        "search" {
            [pscustomobject]@{ Name = "powertoys"; Version = "0.95.1"; Source = "extras"; Binaries = "" }
        }
        "list" {
            [pscustomobject]@{ Name = "powertoys"; Version = "0.95.0"; Source = "extras"; Updated = "2026-09-03"; Info = "" }
        }
    }
    $global:LASTEXITCODE = 0
}
function global:mise {
    switch ($args[0]) {
        "registry" {
            '[{"short":"node","description":"JavaScript runtime","aliases":["nodejs"],"backends":["core:node"]}]'
        }
        "ls" {
            '{"node":[{"version":"26.8.1","requested_version":"26","installed":true,"active":true}]}'
        }
    }
    $global:LASTEXITCODE = 0
}
function global:fzf {
    begin { $rows = @() }
    process { $rows += [string]$_ }
    end {
        $global:LASTEXITCODE = 0
        $global:WinenvFzfRows = @($rows)
        $rows | Where-Object { $_ -match "^winget:winget/Microsoft\.PowerToys`t" } | Select-Object -First 1
    }
}
function global:Invoke-WebRequest {
    param(
        [string]$Uri,
        [switch]$UseBasicParsing,
        [hashtable]$Headers
    )
    $path = switch ($Uri) {
        "https://profiles.example/test.json" { $testUserProfilePath }
        "https://profiles.example/shared.json" { $testSharedProfilePath }
        "https://profiles.example/conflict.json" { $testConflictProfilePath }
        "https://profiles.example/provider-conflict.json" { $testProviderConflictProfilePath }
        default { throw "Unexpected test URL: $Uri" }
    }
    return [pscustomobject]@{ Content = Get-Content -Raw -Path $path }
}
function global:Read-Host {
    param([string]$Prompt)
    if ($Prompt -eq "Search WinGet, Scoop, and mise") { return "powertoys" }
    if ($Prompt -match "^Choose the package to keep") { return "2" }
    throw "Unexpected interactive prompt: $Prompt"
}

& (Join-Path $PSScriptRoot "test-requirements.ps1")

$runtimeList = (& (Join-Path $root "win.ps1") list | Out-String -Width 4096)
if ($runtimeList -notmatch "PowerShell 7" -or $runtimeList -notmatch "junegunn.fzf" -or $runtimeList -match "Node.js") {
    throw "The default runtime profile contains personal software or is missing a runtime dependency."
}
$runtimeInstall = (& (Join-Path $root "win.ps1") install -DryRun 6>&1 | Out-String -Width 4096)
if ($runtimeInstall -notmatch "Runtime requirements" -or $runtimeInstall -notmatch "PowerShell 7" -or $runtimeInstall -notmatch "fzf" -or $runtimeInstall -match "Microsoft.VisualStudioCode") {
    throw "The default install route did not probe only Winenv runtime dependencies."
}
& (Join-Path $root "win.ps1") use
$helpText = (& (Join-Path $root "win.ps1") help 6>&1 | Out-String -Width 4096)
if ($helpText -notmatch "win \[software\]" -or $helpText -notmatch "win off" -or $helpText -notmatch "-From") {
    throw "The compact help does not describe the primary command interface."
}

Write-Host "Checking legacy profile migration..."
$primaryLocalAppData = $env:LOCALAPPDATA
$primaryMiseConfigDir = $env:MISE_CONFIG_DIR
$legacyLocalAppData = Join-Path ([IO.Path]::GetTempPath()) ("winenv-legacy-profile-" + [Guid]::NewGuid().ToString("N"))
$legacyStateRoot = Join-Path $legacyLocalAppData "Winenv"
New-Item -ItemType Directory -Path $legacyStateRoot -Force | Out-Null
Copy-Item -LiteralPath $testSharedProfilePath -Destination (Join-Path $legacyStateRoot "user-profile.json")
[pscustomobject]@{ userProfile = "@local" } | ConvertTo-Json | Set-Content -Path (Join-Path $legacyStateRoot "config.json") -Encoding UTF8
$env:LOCALAPPDATA = $legacyLocalAppData
$env:MISE_CONFIG_DIR = Join-Path $legacyLocalAppData "mise"
$legacyList = (& (Join-Path $root "win.ps1") list 6>&1 | Out-String -Width 4096)
$migratedConfig = Get-Content -Raw -Path (Join-Path $legacyStateRoot "config.json") | ConvertFrom-Json
if ($migratedConfig.schemaVersion -ne 2 -or @($migratedConfig.profiles).Count -ne 1 -or $legacyList -notmatch "shared-tools") {
    throw "The legacy single-profile state was not migrated into the profile registry."
}
$migratedSnapshot = Join-Path (Join-Path $legacyStateRoot "profiles") $migratedConfig.profiles[0].fileName
if (-not (Test-Path $migratedSnapshot) -or -not (Test-Path (Join-Path $legacyStateRoot "user-profile.json"))) {
    throw "Legacy migration did not preserve both the old file and the new independent snapshot."
}
$env:LOCALAPPDATA = $primaryLocalAppData
$env:MISE_CONFIG_DIR = $primaryMiseConfigDir
Remove-Item -Path $legacyLocalAppData -Recurse -Force

$remoteUsePlan = (& (Join-Path $root "win.ps1") use "https://profiles.example/test.json" -DryRun -Yes 6>&1 | Out-String -Width 4096)
if ($remoteUsePlan -notmatch "Profile preview" -or $remoteUsePlan -notmatch "Microsoft.VisualStudioCode" -or $remoteUsePlan -notmatch "scoop install main/ripgrep" -or $remoteUsePlan -notmatch "mise install node@26") {
    throw "The shared-profile use route did not preview and plan the complete installation."
}
& (Join-Path $root "win.ps1") profile "https://profiles.example/test.json"
& (Join-Path $root "win.ps1") profile "https://profiles.example/shared.json"

$registryPath = Join-Path (Join-Path $testLocalAppData "Winenv") "config.json"
$profilesPath = Join-Path (Join-Path $testLocalAppData "Winenv") "profiles"
$registry = Get-Content -Raw -Path $registryPath | ConvertFrom-Json
if ($registry.schemaVersion -ne 2 -or @($registry.profiles).Count -ne 2 -or @($registry.profiles | Where-Object enabled).Count -ne 2) {
    throw "Independent profiles were not registered and enabled together."
}
if (@(Get-ChildItem -Path $profilesPath -Filter "*.json" -File).Count -ne 2) {
    throw "Profiles did not receive independent snapshots."
}
$miseFragmentPath = Join-Path $env:MISE_CONFIG_DIR "conf.d\winenv.toml"
$miseFragment = Get-Content -Raw -Path $miseFragmentPath
if ($miseFragment -notmatch '"node"\s*=\s*"26"') {
    throw "Profile-managed mise tools were not written to Winenv's isolated config fragment."
}

$composedList = (& (Join-Path $root "win.ps1") list 6>&1 | Out-String -Width 4096)
if ($composedList -notmatch "test-user" -or $composedList -notmatch "shared-tools" -or $composedList -notmatch "Node.js" -or $composedList -notmatch "jq") {
    throw "Multiple enabled profiles were not composed into one effective view."
}
if ([regex]::Matches($composedList, "Visual Studio Code").Count -ne 1) {
    throw "The exact Visual Studio Code duplicate was not deduplicated."
}
if ($composedList -notmatch "test-user,shared-tools") {
    throw "The deduplicated package did not retain both profile claims."
}
& (Join-Path $root "win.ps1") show code-editor -n

& (Join-Path $root "win.ps1") profile "https://profiles.example/shared.json"
$refreshedRegistry = Get-Content -Raw -Path $registryPath | ConvertFrom-Json
if (@($refreshedRegistry.profiles).Count -ne 2) {
    throw "Refreshing the same profile source created a duplicate registry entry."
}

$offShared = (& (Join-Path $root "win.ps1") off shared-tools 6>&1 | Out-String -Width 4096)
if ($offShared -notmatch "Retained:\s+1" -or $offShared -notmatch "Unclaimed:\s+1" -or $offShared -notmatch "jq" -or $offShared -notmatch "no installed software was changed") {
    throw "Disabling a shared profile did not explain retained and unclaimed packages."
}
$afterOffRegistry = Get-Content -Raw -Path $registryPath | ConvertFrom-Json
if (@($afterOffRegistry.profiles | Where-Object enabled).Count -ne 1 -or @(Get-ChildItem -Path $profilesPath -Filter "*.json" -File).Count -ne 2) {
    throw "Disabling one profile changed another profile or deleted a snapshot."
}
$afterOffList = (& (Join-Path $root "win.ps1") list 6>&1 | Out-String -Width 4096)
if ($afterOffList -notmatch "Visual Studio Code" -or $afterOffList -match "\sjq\s") {
    throw "A shared claim was not retained, or an unclaimed package remained in the effective view."
}
$savedReenablePlan = (& (Join-Path $root "win.ps1") use shared-tools -DryRun -Yes 6>&1 | Out-String -Width 4096)
if ($savedReenablePlan -notmatch "saved snapshot" -or $savedReenablePlan -notmatch "jq") {
    throw "A disabled profile could not be previewed directly from its retained snapshot."
}
$afterReenablePreviewRegistry = Get-Content -Raw -Path $registryPath | ConvertFrom-Json
if (@($afterReenablePreviewRegistry.profiles | Where-Object enabled).Count -ne 1) {
    throw "A dry-run snapshot reactivation changed the persisted registry."
}

$conflictMessage = ""
try {
    & (Join-Path $root "win.ps1") use "https://profiles.example/conflict.json" -DryRun -Yes 6>&1 | Out-String -Width 4096 | Out-Null
} catch {
    $conflictMessage = $_.Exception.Message
}
if ($conflictMessage -notmatch "explicit interactive choice") {
    throw "A version conflict was not rejected when no explicit choice could be made."
}
$afterConflictRegistry = Get-Content -Raw -Path $registryPath | ConvertFrom-Json
if (@($afterConflictRegistry.profiles).Count -ne 2 -or @($afterConflictRegistry.profiles | Where-Object { $_.source -match "conflict" }).Count -ne 0) {
    throw "A rejected conflicting profile changed the persisted registry."
}

& (Join-Path $root "win.ps1") profile "https://profiles.example/conflict.json"
$resolvedRegistry = Get-Content -Raw -Path $registryPath | ConvertFrom-Json
if (@($resolvedRegistry.profiles).Count -ne 3 -or @($resolvedRegistry.resolutions).Count -ne 1) {
    throw "An explicit conflict choice was not persisted with the new profile."
}
$resolvedList = (& (Join-Path $root "win.ps1") list 6>&1 | Out-String -Width 4096)
if ($resolvedList -match "Node.js 24" -or $resolvedList -notmatch "Node.js") {
    throw "The explicit conflict choice was not used by the effective profile."
}
$offConflict = (& (Join-Path $root "win.ps1") off older-node 6>&1 | Out-String -Width 4096)
if ($offConflict -notmatch "Retained:\s+0" -or $offConflict -notmatch "Unclaimed:\s+1") {
    throw "Disabling a losing version claim did not distinguish it from the selected version."
}

$providerConflictMessage = ""
try {
    & (Join-Path $root "win.ps1") use "https://profiles.example/provider-conflict.json" -DryRun -Yes 6>&1 | Out-String -Width 4096 | Out-Null
} catch {
    $providerConflictMessage = $_.Exception.Message
}
if ($providerConflictMessage -notmatch "explicit interactive choice") {
    throw "Competing managers for the same command were not treated as an explicit profile conflict."
}
$afterProviderConflictRegistry = Get-Content -Raw -Path $registryPath | ConvertFrom-Json
if (@($afterProviderConflictRegistry.profiles | Where-Object { $_.source -match "provider-conflict" }).Count -ne 0) {
    throw "A rejected provider conflict changed the persisted registry."
}
& (Join-Path $root "win.ps1") -n
$storeSelection = (& (Join-Path $root "win.ps1") powertoys -n 6>&1 | Out-String -Width 4096)
if ($storeSelection -notmatch "Microsoft\.PowerToys" -or $storeSelection -notmatch "winget") {
    throw "The live store did not return the package selected by the external fzf executable."
}
& (Join-Path $root "win.ps1") show vscode -n
& (Join-Path $root "win.ps1") show "winget:winget/Microsoft.PowerToys" -n
$managedSearch = (& (Join-Path $root "win.ps1") find ripgrep -From managed | Out-String -Width 4096)
if ($managedSearch -notmatch "ripgrep" -or $managedSearch -notmatch "win add ripgrep") {
    throw "The baseline search did not preserve its configured install command."
}
$liveSearch = (& (Join-Path $root "win.ps1") search powertoys | Out-String -Width 4096)
if ($liveSearch -notmatch "Microsoft\.PowerToys" -or $liveSearch -notmatch "powertoys" -or $liveSearch -notmatch "winget" -or $liveSearch -notmatch "scoop") {
    throw "The unified search did not return both live manager results."
}
$miseSearch = (& (Join-Path $root "win.ps1") find node -From mise | Out-String -Width 4096)
if ($miseSearch -notmatch "core:node" -or $miseSearch -notmatch "win add node") {
    throw "The mise result did not merge live registry data with the baseline override."
}
$checkText = (& (Join-Path $root "win.ps1") check 6>&1 | Out-String -Width 4096)
if ($checkText -notmatch "same-name aliases/functions ignored: Function:fzf") {
    throw "The environment check did not report an ignored command shadow."
}
$reportedVersion = & (Join-Path $root "win.ps1") ver
if ([string]::IsNullOrWhiteSpace([string]$reportedVersion)) {
    throw "The version command returned no version."
}
& (Join-Path $root "win.ps1") add -n
$temporaryGroupPlan = (& (Join-Path $root "win.ps1") add -P personal-test -n 6>&1 | Out-String -Width 4096)
if ($temporaryGroupPlan -notmatch "mise use --global node@26") {
    throw "A temporary profile-group install unexpectedly changed Winenv's persistent mise declarations."
}
& (Join-Path $root "win.ps1") add vscode -n
& (Join-Path $root "win.ps1") add "scoop:extras/powertoys" -n
& (Join-Path $root "win.ps1") add powertoys -n
$updatePlan = (& (Join-Path $root "win.ps1") up -n 6>&1 | Out-String -Width 4096)
if ($updatePlan -notmatch "winget(?:\.exe)?\s+upgrade --all" -or $updatePlan -notmatch "scoop update \*" -or $updatePlan -notmatch "mise up") {
    throw "The update route did not delegate the full inventory to each package manager."
}
& (Join-Path $root "win.ps1") rm vscode -n
& (Join-Path $root "win.ps1") rm powertoys -n
& (Join-Path $root "win.ps1") clean -n
& (Join-Path $root "win.ps1") off
$resetList = (& (Join-Path $root "win.ps1") list | Out-String -Width 4096)
if ($resetList -match "Visual Studio Code") {
    throw "Disabling the user profile did not restore the runtime-only profile."
}
$resetMiseFragment = Get-Content -Raw -Path $miseFragmentPath
if ($resetMiseFragment -match '"node"\s*=') {
    throw "Disabling the final claiming profile did not update Winenv's mise fragment."
}
if (Test-Path $testLocalAppData) {
    $env:Path = $originalProcessPath
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        $env:PATH = $originalUpperProcessPath
    }
    Remove-Item -Path $testLocalAppData -Recurse -Force
}

Write-Host "All checks passed." -ForegroundColor Green
