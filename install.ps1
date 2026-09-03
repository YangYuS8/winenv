[CmdletBinding()]
param(
    [string]$Version,
    [string]$UserProfile,
    [Alias("Lang")]
    [ValidateSet("auto", "en", "zh", "en-US", "zh-CN")]
    [string]$Language,
    [switch]$ToolOnly,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Repository = "YangYuS8/winenv"
$InstallRoot = Join-Path $env:LOCALAPPDATA "Winenv"
$VersionsRoot = Join-Path $InstallRoot "versions"
$BinRoot = Join-Path $InstallRoot "bin"
$CurrentPath = Join-Path $InstallRoot "current.txt"
$ConfigPath = Join-Path $InstallRoot "config.json"
$ApiHeaders = @{
    "Accept" = "application/vnd.github+json"
    "User-Agent" = "winenv-installer"
    "X-GitHub-Api-Version" = "2022-11-28"
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function ConvertTo-InstallerLanguage {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    if ($Value -match "^(?i:zh|zh-cn|zh-hans)") { return "zh-CN" }
    if ($Value -match "^(?i:en|en-us)") { return "en-US" }
    if ($Value -match "^(?i:auto)$") { return "auto" }
    return ""
}

function Resolve-InstallerLanguage {
    $requested = ConvertTo-InstallerLanguage $Language
    if ($requested -and $requested -ne "auto") { return $requested }
    $environmentLanguage = ConvertTo-InstallerLanguage $env:WINENV_LANG
    if ($requested -ne "auto" -and $environmentLanguage -and $environmentLanguage -ne "auto") { return $environmentLanguage }
    if ($requested -ne "auto" -and (Test-Path -LiteralPath $ConfigPath)) {
        try {
            $stored = Get-Content -Raw -Encoding UTF8 -LiteralPath $ConfigPath | ConvertFrom-Json -ErrorAction Stop
            $configuredLanguage = ConvertTo-InstallerLanguage ([string]$stored.language)
            if ($configuredLanguage -and $configuredLanguage -ne "auto") { return $configuredLanguage }
        } catch {}
    }
    if ([Globalization.CultureInfo]::CurrentUICulture.Name -match "^(?i:zh)(-|$)") { return "zh-CN" }
    return "en-US"
}

$InstallerLanguage = Resolve-InstallerLanguage

$InstallerMessages = @'
{
  "Incomplete": { "en-US": "Winenv {0} is incomplete. Re-run the installer.", "zh-CN": "Winenv {0} \u4e0d\u5b8c\u6574\u3002\u8bf7\u91cd\u65b0\u8fd0\u884c\u5b89\u88c5\u5668\u3002" },
  "MissingAssets": { "en-US": "Release {0} does not contain {1} and SHA256SUMS.", "zh-CN": "Release {0} \u4e0d\u5305\u542b {1} \u548c SHA256SUMS\u3002" },
  "Downloading": { "en-US": "Downloading Winenv {0}...", "zh-CN": "\u6b63\u5728\u4e0b\u8f7d Winenv {0}\u2026\u2026" },
  "MissingChecksum": { "en-US": "No checksum was published for {0}.", "zh-CN": "\u6ca1\u6709\u4e3a {0} \u53d1\u5e03\u6821\u9a8c\u548c\u3002" },
  "ChecksumMismatch": { "en-US": "Checksum mismatch for {0}.", "zh-CN": "{0} \u7684\u6821\u9a8c\u548c\u4e0d\u5339\u914d\u3002" },
  "AlreadyDownloaded": { "en-US": "Winenv {0} is already downloaded.", "zh-CN": "Winenv {0} \u5df2\u4e0b\u8f7d\u3002" },
  "Installed": { "en-US": "Winenv {0} installed.", "zh-CN": "Winenv {0} \u5df2\u5b89\u88c5\u3002" },
  "Command": { "en-US": "Command: win", "zh-CN": "\u547d\u4ee4\uff1awin" },
  "ApplyingProfiles": { "en-US": "\nApplying the active Winenv profiles...", "zh-CN": "\n\u6b63\u5728\u5e94\u7528\u5df2\u542f\u7528\u7684 Winenv Profile\u2026\u2026" },
  "ExistingSystem": { "en-US": "\nAlready have software installed? Run 'win scan', then use 'win adopt' to select what should become reproducible.", "zh-CN": "\n\u7535\u8111\u4e0a\u5df2\u7ecf\u5b89\u88c5\u4e86\u8f6f\u4ef6\uff1f\u5148\u8fd0\u884c\u2018win scan\u2019\uff0c\u518d\u7528\u2018win adopt\u2019\u9009\u62e9\u8981\u7eb3\u5165\u53ef\u590d\u73b0\u914d\u7f6e\u7684\u8f6f\u4ef6\u3002" }
}
'@ | ConvertFrom-Json

function Get-InstallerText {
    param([string]$Key, [object[]]$Arguments = @())
    $messageProperty = $InstallerMessages.psobject.Properties[$Key]
    if ($null -eq $messageProperty) { return $Key }
    $message = $messageProperty.Value
    $template = [string]$message.psobject.Properties[$InstallerLanguage].Value
    return [string]::Format([Globalization.CultureInfo]::InvariantCulture, $template, $Arguments)
}

function Write-InstallerHost {
    param([string]$Message, [ConsoleColor]$ForegroundColor)
    if ($PSBoundParameters.ContainsKey("ForegroundColor")) {
        Microsoft.PowerShell.Utility\Write-Host $Message -ForegroundColor $ForegroundColor
    } else {
        Microsoft.PowerShell.Utility\Write-Host $Message
    }
}

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
    $requestedLanguage = [string]$env:WINENV_LANG
    if ([string]::IsNullOrWhiteSpace($requestedLanguage) -and (Test-Path (Join-Path $root "config.json"))) {
        try { $requestedLanguage = [string](Get-Content -Raw -Encoding UTF8 -Path (Join-Path $root "config.json") | ConvertFrom-Json).language } catch {}
    }
    $locale = if ($requestedLanguage -match "^(?i:zh)") {
        "zh-CN"
    } elseif ($requestedLanguage -match "^(?i:en)") {
        "en-US"
    } elseif ([Globalization.CultureInfo]::CurrentUICulture.Name -match "^(?i:zh)(-|$)") {
        "zh-CN"
    } else {
        "en-US"
    }
    $messages = '{"en-US":"Winenv {0} is incomplete. Re-run the installer.","zh-CN":"Winenv {0} \u4e0d\u5b8c\u6574\u3002\u8bf7\u91cd\u65b0\u8fd0\u884c\u5b89\u88c5\u5668\u3002"}' | ConvertFrom-Json
    throw [string]::Format([string]$messages.psobject.Properties[$locale].Value, $version)
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
    throw (Get-InstallerText MissingAssets -Arguments @($tag, $zipName))
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-" + [Guid]::NewGuid().ToString("N"))
$zipPath = Join-Path $tempRoot $zipName
$checksumPath = Join-Path $tempRoot "SHA256SUMS"
$stagingPath = Join-Path $tempRoot "expanded"
$targetPath = Join-Path $VersionsRoot $resolvedVersion

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Write-InstallerHost (Get-InstallerText Downloading -Arguments @($resolvedVersion)) -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipAsset[0].browser_download_url -OutFile $zipPath -UseBasicParsing
    Invoke-WebRequest -Uri $checksumAsset[0].browser_download_url -OutFile $checksumPath -UseBasicParsing

    $escapedName = [Regex]::Escape($zipName)
    $checksumText = Get-Content -Raw -Path $checksumPath
    $match = [Regex]::Match($checksumText, "(?im)^([a-f0-9]{64})\s+\*?$escapedName\s*$")
    if (-not $match.Success) {
        throw (Get-InstallerText MissingChecksum -Arguments @($zipName))
    }

    $expectedHash = $match.Groups[1].Value.ToUpperInvariant()
    $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -ne $expectedHash) {
        throw (Get-InstallerText ChecksumMismatch -Arguments @($zipName))
    }

    if ((Test-Path $targetPath) -and -not $Force) {
        Write-InstallerHost (Get-InstallerText AlreadyDownloaded -Arguments @($resolvedVersion))
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

Write-InstallerHost (Get-InstallerText Installed -Arguments @($resolvedVersion)) -ForegroundColor Green
Write-InstallerHost (Get-InstallerText Command)

if (-not [string]::IsNullOrWhiteSpace($Language)) {
    & (Join-Path $targetPath "win.ps1") lang $Language
}

if (-not [string]::IsNullOrWhiteSpace($UserProfile)) {
    & (Join-Path $targetPath "win.ps1") profile $UserProfile
}

if (-not $ToolOnly) {
    Write-InstallerHost (Get-InstallerText ApplyingProfiles) -ForegroundColor Cyan
    & (Join-Path $targetPath "win.ps1") install
}

Write-InstallerHost (Get-InstallerText ExistingSystem) -ForegroundColor Cyan
