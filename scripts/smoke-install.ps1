$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$expectedVersion = (Get-Content -Raw -Path (Join-Path $root "VERSION")).Trim()

if ([string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-smoke-" + [Guid]::NewGuid().ToString("N"))
} else {
    $testRoot = Join-Path $env:RUNNER_TEMP "winenv-smoke"
}

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$smokeProfilePath = Join-Path $testRoot "smoke-user-profile.json"
@'
{
  "schemaVersion": 1,
  "name": "smoke-user",
  "defaultProfiles": ["personal"],
  "scoopBuckets": [],
  "packages": [
    {
      "key": "terminal",
      "displayName": "Windows Terminal",
      "owner": "winget",
      "id": "Microsoft.WindowsTerminal",
      "source": "winget",
      "profiles": ["personal"],
      "commands": ["wt"]
    }
  ]
}
'@ | Set-Content -Path $smokeProfilePath -Encoding UTF8

$env:LOCALAPPDATA = $testRoot
$env:MISE_CONFIG_DIR = Join-Path $testRoot "mise"
& (Join-Path $root "install.ps1") -Version $expectedVersion -UserProfile $smokeProfilePath -Language zh -ToolOnly -Force

$installedEntry = Join-Path $testRoot "Winenv\versions\$expectedVersion\win.ps1"
$launcherEntry = Join-Path $testRoot "Winenv\bin\win-launch.ps1"
$localeEntry = Join-Path $testRoot "Winenv\versions\$expectedVersion\locales\zh-CN.json"
if (-not (Test-Path $installedEntry) -or -not (Test-Path $launcherEntry) -or -not (Test-Path $localeEntry)) {
    throw "The release installer did not create the expected files."
}

$installedVersion = (& $installedEntry version | Out-String).Trim()
$launcherVersion = (& $launcherEntry version | Out-String).Trim()
if ($installedVersion -ne $expectedVersion -or $launcherVersion -ne $expectedVersion) {
    throw "Installed version mismatch. Expected $expectedVersion, got entry=$installedVersion launcher=$launcherVersion"
}

$activeProfile = (& $installedEntry list 6>&1 | Out-String -Width 4096)
if ($activeProfile -notmatch "smoke-user" -or $activeProfile -notmatch "Windows Terminal" -or $activeProfile -notmatch "junegunn.fzf" -or $activeProfile -notmatch "用户 Profile") {
    throw "The installer did not activate the requested user profile over the runtime profile."
}

Write-Host "Release installer smoke test passed for Winenv $expectedVersion." -ForegroundColor Green
