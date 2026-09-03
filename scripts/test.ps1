$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "Validating JSON and schema..."
$profilePath = Join-Path $root "profile.json"
$schemaPath = Join-Path $root "profile.schema.json"
$profileText = Get-Content -Raw -Path $profilePath
$schemaValid = $profileText | Test-Json -SchemaFile $schemaPath
if (-not $schemaValid) {
    throw "profile.json does not match profile.schema.json"
}

$profile = $profileText | ConvertFrom-Json
$duplicateKeys = @($profile.packages | Group-Object key | Where-Object Count -gt 1)
$duplicatePackages = @($profile.packages | Group-Object { "$($_.owner):$($_.id)".ToLowerInvariant() } | Where-Object Count -gt 1)
if ($duplicateKeys.Count -gt 0 -or $duplicatePackages.Count -gt 0) {
    throw "The profile contains duplicate package ownership."
}

$commandOwners = @{}
foreach ($package in @($profile.packages)) {
    foreach ($command in @($package.commands)) {
        $key = $command.ToLowerInvariant()
        if ($commandOwners.ContainsKey($key) -and $commandOwners[$key] -ne $package.owner) {
            throw "Command '$command' has multiple owners."
        }
        $commandOwners[$key] = $package.owner
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
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $env:LOCALAPPDATA = Join-Path ([IO.Path]::GetTempPath()) "winenv-tests"
}

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

& (Join-Path $root "win.ps1") list
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
if ($updatePlan -notmatch "winget upgrade --all" -or $updatePlan -notmatch "scoop update \*" -or $updatePlan -notmatch "mise up --no-prune") {
    throw "The update route did not delegate the full inventory to each package manager."
}
& (Join-Path $root "win.ps1") remove vscode -DryRun
& (Join-Path $root "win.ps1") remove powertoys -DryRun
& (Join-Path $root "win.ps1") cleanup -DryRun

Write-Host "All checks passed." -ForegroundColor Green
