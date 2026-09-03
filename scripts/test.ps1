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

function global:winget {}
function global:scoop {}
function global:mise {}
function global:fzf {
    begin { $rows = @() }
    process { $rows += [string]$_ }
    end {
        $global:LASTEXITCODE = 0
        $rows | Where-Object { $_ -match "^vscode`t" } | Select-Object -First 1
    }
}

& (Join-Path $root "win.ps1") list
& (Join-Path $root "win.ps1") store -DryRun
& (Join-Path $root "win.ps1") info vscode -DryRun
$managedSearch = (& (Join-Path $root "win.ps1") search ripgrep -Manager managed | Out-String)
if ($managedSearch -notmatch "ripgrep" -or $managedSearch -notmatch "win add ripgrep") {
    throw "Managed package search did not return an installable result."
}
& (Join-Path $root "win.ps1") search ripgrep -DryRun
& (Join-Path $root "win.ps1") doctor
$reportedVersion = & (Join-Path $root "win.ps1") version
if ([string]::IsNullOrWhiteSpace([string]$reportedVersion)) {
    throw "The version command returned no version."
}
& (Join-Path $root "win.ps1") install -DryRun
& (Join-Path $root "win.ps1") install vscode -DryRun
$unknownInstallWasRejected = $false
try {
    & (Join-Path $root "win.ps1") install package-that-is-not-managed -DryRun
} catch {
    $unknownInstallWasRejected = $true
}
if (-not $unknownInstallWasRejected) {
    throw "An unknown package key unexpectedly reached the installer."
}
& (Join-Path $root "win.ps1") update -DryRun
& (Join-Path $root "win.ps1") remove vscode -DryRun
& (Join-Path $root "win.ps1") cleanup -DryRun

Write-Host "All checks passed." -ForegroundColor Green
