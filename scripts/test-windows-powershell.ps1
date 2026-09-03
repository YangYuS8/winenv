$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "Checking Windows PowerShell compatibility..."
$tokens = $null
$errors = $null
[Management.Automation.Language.Parser]::ParseFile((Join-Path $root "win.ps1"), [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) {
    throw "win.ps1 is not compatible with this PowerShell parser: $($errors -join '; ')"
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-legacy-tests-" + [Guid]::NewGuid().ToString("N"))
$env:LOCALAPPDATA = $testRoot
$env:MISE_CONFIG_DIR = Join-Path $testRoot "mise"

function global:winget {}
function global:scoop {}
function global:mise {}

& (Join-Path $root "win.ps1") list | Out-Null
& (Join-Path $root "win.ps1") help | Out-Null
& (Join-Path $root "win.ps1") off -n | Out-Null
& (Join-Path $root "win.ps1") find fzf -From managed | Out-Null
& (Join-Path $root "win.ps1") add powershell -n | Out-Null

if (Test-Path $testRoot) {
    Remove-Item -Path $testRoot -Recurse -Force
}

Write-Host "Windows PowerShell compatibility checks passed." -ForegroundColor Green
