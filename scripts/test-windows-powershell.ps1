$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "Checking Windows PowerShell compatibility..."
$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile((Join-Path $root "win.ps1"), [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    throw "win.ps1 is not compatible with this PowerShell parser: $($errors -join '; ')"
}

if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $env:LOCALAPPDATA = Join-Path ([IO.Path]::GetTempPath()) "winenv-legacy-tests"
}

function global:winget {}
function global:scoop {}
function global:mise {}

& (Join-Path $root "win.ps1") list | Out-Null
& (Join-Path $root "win.ps1") search ripgrep -Manager managed | Out-Null
& (Join-Path $root "win.ps1") install vscode -DryRun | Out-Null

Write-Host "Windows PowerShell compatibility checks passed." -ForegroundColor Green
