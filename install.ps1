[CmdletBinding()]
param(
    [string]$Version,
    [string]$UserProfile,
    [switch]$ToolOnly,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Repository = "YangYuS8/winenv"
$InstallRoot = Join-Path $env:LOCALAPPDATA "Winenv"
$VersionsRoot = Join-Path $InstallRoot "versions"
$BinRoot = Join-Path $InstallRoot "bin"
$CurrentPath = Join-Path $InstallRoot "current.txt"
$ApiHeaders = @{
    "Accept" = "application/vnd.github+json"
    "User-Agent" = "winenv-installer"
    "X-GitHub-Api-Version" = "2022-11-28"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Get-WinenvRelease {
    if ([string]::IsNullOrWhiteSpace($Version)) {
        $uri = "https://api.github.com/repos/$Repository/releases/latest"
    } else {
        $tag = if ($Version.StartsWith("v")) { $Version } else { "v$Version" }
        $uri = "https://api.github.com/repos/$Repository/releases/tags/$tag"
    }
    return Invoke-RestMethod -Uri $uri -Headers $ApiHeaders
}

function Add-UserPathEntry {
    param([string]$Path)
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @($userPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $userMatches = @($entries | Where-Object { $_.TrimEnd("\") -ieq $Path.TrimEnd("\") })
    if ($userMatches.Count -eq 0) {
        $updated = (@($entries) + $Path) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $updated, "User")
    }
    $processMatches = @($env:Path -split ";" | Where-Object { $_.TrimEnd("\") -ieq $Path.TrimEnd("\") })
    if ($processMatches.Count -eq 0) {
        $env:Path = "$Path;$env:Path"
    }
}

function Install-WinenvLauncher {
    New-Item -ItemType Directory -Path $BinRoot -Force | Out-Null
    $launcherPath = Join-Path $BinRoot "win-launch.ps1"
    $cmdPath = Join-Path $BinRoot "win.cmd"

    $launcher = @'
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$version = (Get-Content -Raw -Path (Join-Path $root "current.txt")).Trim()
$entry = Join-Path (Join-Path (Join-Path $root "versions") $version) "win.ps1"
if (-not (Test-Path $entry)) {
    throw "Winenv $version is incomplete. Re-run the installer."
}
& $entry @args
'@

    $cmd = @'
@echo off
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  pwsh -NoLogo -NoProfile -File "%~dp0win-launch.ps1" %*
) else (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0win-launch.ps1" %*
)
'@

    Set-Content -Path $launcherPath -Value $launcher -Encoding UTF8
    Set-Content -Path $cmdPath -Value $cmd -Encoding ASCII
    Add-UserPathEntry $BinRoot
}

$release = Get-WinenvRelease
$tag = [string]$release.tag_name
$resolvedVersion = $tag.TrimStart("v")
$zipName = "winenv-$resolvedVersion.zip"
$zipAsset = @($release.assets | Where-Object { $_.name -eq $zipName })
$checksumAsset = @($release.assets | Where-Object { $_.name -eq "SHA256SUMS" })

if ($zipAsset.Count -ne 1 -or $checksumAsset.Count -ne 1) {
    throw "Release $tag does not contain $zipName and SHA256SUMS."
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-" + [Guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot $zipName
$checksumPath = Join-Path $tempRoot "SHA256SUMS"
$stagingPath = Join-Path $tempRoot "expanded"
$targetPath = Join-Path $VersionsRoot $resolvedVersion

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Write-Host "Downloading Winenv $resolvedVersion..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipAsset[0].browser_download_url -OutFile $zipPath -UseBasicParsing
    Invoke-WebRequest -Uri $checksumAsset[0].browser_download_url -OutFile $checksumPath -UseBasicParsing

    $escapedName = [Regex]::Escape($zipName)
    $checksumText = Get-Content -Raw -Path $checksumPath
    $match = [Regex]::Match($checksumText, "(?im)^([a-f0-9]{64})\s+\*?$escapedName\s*$")
    if (-not $match.Success) {
        throw "No checksum was published for $zipName."
    }

    $expectedHash = $match.Groups[1].Value.ToUpperInvariant()
    $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
        throw "Checksum mismatch for $zipName."
    }

    if ((Test-Path $targetPath) -and -not $Force) {
        Write-Host "Winenv $resolvedVersion is already downloaded."
    } else {
        Expand-Archive -Path $zipPath -DestinationPath $stagingPath -Force
        New-Item -ItemType Directory -Path $VersionsRoot -Force | Out-Null
        if (Test-Path $targetPath) {
            Remove-Item -Path $targetPath -Recurse -Force
        }
        Move-Item -Path $stagingPath -Destination $targetPath
    }

    Set-Content -Path $CurrentPath -Value $resolvedVersion -Encoding ASCII
    Install-WinenvLauncher
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force
    }
}

Write-Host "Winenv $resolvedVersion installed." -ForegroundColor Green
Write-Host "Command: win"

if (-not [string]::IsNullOrWhiteSpace($UserProfile)) {
    & (Join-Path $targetPath "win.ps1") profile $UserProfile
}

if (-not $ToolOnly) {
    Write-Host "`nApplying the active Winenv profiles..." -ForegroundColor Cyan
    & (Join-Path $targetPath "win.ps1") install
}
