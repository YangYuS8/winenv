$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "Checking Windows PowerShell compatibility..."
foreach ($name in @("win.ps1", "install.ps1")) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        throw "$name is not compatible with this PowerShell parser: $($errors -join '; ')"
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-legacy-tests-" + [Guid]::NewGuid().ToString("N"))
$env:LOCALAPPDATA = $testRoot
$env:MISE_CONFIG_DIR = Join-Path $testRoot "mise"

function global:winget {}
function global:scoop {}
function global:mise {}

$englishHelp = (& (Join-Path $root "win.ps1") help -Language en 6>&1 | Out-String -Width 4096)
$chineseHelp = (& (Join-Path $root "win.ps1") help -Language zh 6>&1 | Out-String -Width 4096)
if ($englishHelp -notmatch "Winenv keeps Windows software simple" -or $chineseHelp -match "Winenv keeps Windows software simple") {
    throw "Windows PowerShell did not decode the external locale resources correctly."
}
$chineseList = (& (Join-Path $root "win.ps1") list -Language zh 6>&1 | Out-String -Width 4096)
if ($chineseList -notmatch "PowerShell 7" -or $chineseList -notmatch "junegunn.fzf") {
    throw "Localized tabular output failed under Windows PowerShell."
}
& (Join-Path $root "win.ps1") off -n | Out-Null
& (Join-Path $root "win.ps1") find fzf -From managed | Out-Null
& (Join-Path $root "win.ps1") scan | Out-Null
& (Join-Path $root "win.ps1") add powershell -n | Out-Null

if (Test-Path $testRoot) {
    Remove-Item -Path $testRoot -Recurse -Force
}

Write-Host "Windows PowerShell compatibility checks passed." -ForegroundColor Green
