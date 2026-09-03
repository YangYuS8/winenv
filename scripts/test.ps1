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
    $duplicatePackages = @($profile.packages | Group-Object { "$($_.owner):$($_.id)".ToLowerInvariant() } | Where-Object Count -gt 1)
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
$testUserProfilePath = Join-Path $testLocalAppData "test-user-profile.json"
New-Item -ItemType Directory -Path $testLocalAppData -Force | Out-Null
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
    if ($Uri -ne "https://profiles.example/test.json") {
        throw "Unexpected test URL: $Uri"
    }
    return [pscustomobject]@{ Content = Get-Content -Raw -Path $testUserProfilePath }
}

$runtimeList = (& (Join-Path $root "win.ps1") list | Out-String -Width 4096)
if ($runtimeList -notmatch "PowerShell 7" -or $runtimeList -notmatch "junegunn.fzf" -or $runtimeList -match "Node.js") {
    throw "The default runtime profile contains personal software or is missing a runtime dependency."
}
$runtimeInstall = (& (Join-Path $root "win.ps1") install -DryRun 6>&1 | Out-String -Width 4096)
if ($runtimeInstall -notmatch "Microsoft.PowerShell" -or $runtimeInstall -notmatch "junegunn.fzf" -or $runtimeInstall -match "Microsoft.VisualStudioCode") {
    throw "The default install route is not limited to Winenv runtime dependencies."
}
& (Join-Path $root "win.ps1") use
$remoteUsePlan = (& (Join-Path $root "win.ps1") use "https://profiles.example/test.json" -DryRun -Yes 6>&1 | Out-String -Width 4096)
if ($remoteUsePlan -notmatch "Profile preview" -or $remoteUsePlan -notmatch "Microsoft.VisualStudioCode" -or $remoteUsePlan -notmatch "scoop install main/ripgrep" -or $remoteUsePlan -notmatch "mise use --global node@26") {
    throw "The shared-profile use route did not preview and plan the complete installation."
}
& (Join-Path $root "win.ps1") profile "https://profiles.example/test.json"
$personalList = (& (Join-Path $root "win.ps1") list 6>&1 | Out-String -Width 4096)
if ($personalList -notmatch "test-user" -or $personalList -notmatch "Visual Studio Code" -or $personalList -notmatch "Node.js") {
    throw "The selected user profile was not layered over the runtime profile."
}
& (Join-Path $root "win.ps1") store powertoys -DryRun
if (@($global:WinenvFzfRows | Where-Object { $_ -match "^scoop:extras/powertoys`t" }).Count -ne 1) {
    throw "The live store did not keep the Scoop alternative separate from WinGet."
}
& (Join-Path $root "win.ps1") info vscode -DryRun
& (Join-Path $root "win.ps1") info "winget:winget/Microsoft.PowerToys" -DryRun
$managedSearch = (& (Join-Path $root "win.ps1") search ripgrep -Manager managed | Out-String -Width 4096)
if ($managedSearch -notmatch "ripgrep" -or $managedSearch -notmatch "win add ripgrep") {
    throw "The baseline search did not preserve its configured install command."
}
$liveSearch = (& (Join-Path $root "win.ps1") search powertoys | Out-String -Width 4096)
if ($liveSearch -notmatch "Microsoft\.PowerToys" -or $liveSearch -notmatch "powertoys" -or $liveSearch -notmatch "winget" -or $liveSearch -notmatch "scoop") {
    throw "The unified search did not return both live manager results."
}
$miseSearch = (& (Join-Path $root "win.ps1") search node -Manager mise | Out-String -Width 4096)
if ($miseSearch -notmatch "core:node" -or $miseSearch -notmatch "win add node") {
    throw "The mise result did not merge live registry data with the baseline override."
}
& (Join-Path $root "win.ps1") doctor
$reportedVersion = & (Join-Path $root "win.ps1") version
if ([string]::IsNullOrWhiteSpace([string]$reportedVersion)) {
    throw "The version command returned no version."
}
& (Join-Path $root "win.ps1") install -DryRun
& (Join-Path $root "win.ps1") install vscode -DryRun
& (Join-Path $root "win.ps1") install "scoop:extras/powertoys" -DryRun
& (Join-Path $root "win.ps1") install powertoys -DryRun
$updatePlan = (& (Join-Path $root "win.ps1") update -DryRun 6>&1 | Out-String -Width 4096)
if ($updatePlan -notmatch "winget upgrade --all" -or $updatePlan -notmatch "scoop update \*" -or $updatePlan -notmatch "mise up") {
    throw "The update route did not delegate the full inventory to each package manager."
}
& (Join-Path $root "win.ps1") remove vscode -DryRun
& (Join-Path $root "win.ps1") remove powertoys -DryRun
& (Join-Path $root "win.ps1") cleanup -DryRun
& (Join-Path $root "win.ps1") unuse
$resetList = (& (Join-Path $root "win.ps1") list | Out-String -Width 4096)
if ($resetList -match "Visual Studio Code") {
    throw "Disabling the user profile did not restore the runtime-only profile."
}
if (Test-Path $testLocalAppData) {
    Remove-Item -Path $testLocalAppData -Recurse -Force
}

Write-Host "All checks passed." -ForegroundColor Green
