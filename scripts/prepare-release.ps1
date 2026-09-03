[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$")]
    [string]$Version
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist"
$stage = Join-Path $dist "stage"
$archiveName = "winenv-$Version.zip"
$archivePath = Join-Path $dist $archiveName
$checksumPath = Join-Path $dist "SHA256SUMS"

Set-Content -Path (Join-Path $root "VERSION") -Value $Version -Encoding utf8NoBOM

if (Test-Path $dist) {
    Remove-Item -Path $dist -Recurse -Force
}
New-Item -ItemType Directory -Path $stage -Force | Out-Null

$releaseFiles = @(
    "CHANGELOG.md",
    "LICENSE",
    "README.md",
    "VERSION",
    "install.ps1",
    "profile.json",
    "profile.schema.json",
    "win.ps1"
)

foreach ($file in $releaseFiles) {
    $source = Join-Path $root $file
    if (-not (Test-Path $source)) {
        throw "Release file is missing: $file"
    }
    Copy-Item -Path $source -Destination $stage
}

Copy-Item -Path (Join-Path $root "migrations") -Destination $stage -Recurse
Copy-Item -Path (Join-Path $root "profiles") -Destination $stage -Recurse
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $archivePath -CompressionLevel Optimal

$hash = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path $checksumPath -Value "$hash  $archiveName" -Encoding utf8NoBOM
Remove-Item -Path $stage -Recurse -Force

Write-Host "Prepared $archivePath"
Write-Host "Prepared $checksumPath"
