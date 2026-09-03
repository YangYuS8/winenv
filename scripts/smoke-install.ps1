$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$expectedVersion = (Get-Content -Raw -Path (Join-Path $root "VERSION")).Trim()

if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-smoke-" + [Guid]::NewGuid().ToString("N"))
} else {
    $testRoot = Join-Path $env:RUNNER_TEMP "winenv-smoke"
}

$env:LOCALAPPDATA = $testRoot
& (Join-Path $root "install.ps1") -Version $expectedVersion -UserProfile yangyus8 -ToolOnly -Force

$installedEntry = Join-Path $testRoot "Winenv\versions\$expectedVersion\win.ps1"
$launcherEntry = Join-Path $testRoot "Winenv\bin\win-launch.ps1"
$installedUserProfile = Join-Path $testRoot "Winenv\versions\$expectedVersion\profiles\yangyus8.json"
if (-not (Test-Path $installedEntry) -or -not (Test-Path $launcherEntry) -or -not (Test-Path $installedUserProfile)) {
    throw "The release installer did not create the expected files."
}

$installedVersion = (& $installedEntry version | Out-String).Trim()
$launcherVersion = (& $launcherEntry version | Out-String).Trim()
if ($installedVersion -ne $expectedVersion -or $launcherVersion -ne $expectedVersion) {
    throw "Installed version mismatch. Expected $expectedVersion, got entry=$installedVersion launcher=$launcherVersion"
}

$activeProfile = (& $installedEntry list 6>&1 | Out-String -Width 4096)
if ($activeProfile -notmatch "winenv-runtime \+ yangyus8" -or $activeProfile -notmatch "Tencent QQ" -or $activeProfile -notmatch "junegunn.fzf") {
    throw "The installer did not activate the requested user profile over the runtime profile."
}

Write-Host "Release installer smoke test passed for Winenv $expectedVersion." -ForegroundColor Green
