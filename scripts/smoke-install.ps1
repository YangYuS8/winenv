$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$expectedVersion = (Get-Content -Raw -Path (Join-Path $root "VERSION")).Trim()

if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-smoke-" + [Guid]::NewGuid().ToString("N"))
} else {
    $testRoot = Join-Path $env:RUNNER_TEMP "winenv-smoke"
}

$env:LOCALAPPDATA = $testRoot
& (Join-Path $root "install.ps1") -Version $expectedVersion -ToolOnly -Force

$installedEntry = Join-Path $testRoot "Winenv\versions\$expectedVersion\win.ps1"
$launcherEntry = Join-Path $testRoot "Winenv\bin\win-launch.ps1"
if (-not (Test-Path $installedEntry) -or -not (Test-Path $launcherEntry)) {
    throw "The release installer did not create the expected files."
}

$installedVersion = (& $installedEntry version | Out-String).Trim()
$launcherVersion = (& $launcherEntry version | Out-String).Trim()
if ($installedVersion -ne $expectedVersion -or $launcherVersion -ne $expectedVersion) {
    throw "Installed version mismatch. Expected $expectedVersion, got entry=$installedVersion launcher=$launcherVersion"
}

Write-Host "Release installer smoke test passed for Winenv $expectedVersion." -ForegroundColor Green
