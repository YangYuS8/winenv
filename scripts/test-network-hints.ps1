$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$previousLocalAppData = $env:LOCALAPPDATA
$previousExitCode = $global:LASTEXITCODE
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-network-hints-" + [Guid]::NewGuid().ToString("N"))
$networkTest = @{}

Write-Host "Checking manual network guidance without real network requests..."

function Assert-FailureHint {
    param([scriptblock]$Run, [string]$Message, [bool]$ExpectedHint = $true)
    $networkTest.Failure = $null
    $output = (& { try { & $Run } catch { $networkTest.Failure = $_.Exception } } 6>&1 | Out-String)
    if ($null -eq $networkTest.Failure -or $networkTest.Failure.Message -ne $Message) {
        throw "Expected '$Message'; received '$($networkTest.Failure)'."
    }
    $matches = [regex]::Matches($output, 'https://yangyus8.top/winenv/(zh/)?guide/troubleshooting/#network-and-proxy')
    $expectedCount = if ($ExpectedHint) { 1 } else { 0 }
    if ($matches.Count -ne $expectedCount) { throw "Unexpected network hint count: $output" }
    return $output
}

try {
    $env:LOCALAPPDATA = $testRoot
    . (Join-Path $root "win.ps1") version -Language en | Out-Null

    function winget { "original manager output"; $global:LASTEXITCODE = $networkTest.NativeExitCode }
    function scoop.ps1 { winget }
    function mise { winget }
    function local-installer { winget }

    foreach ($language in @("en", "zh")) {
        Initialize-WinenvLocalization $language
        $networkTest.NativeExitCode = 7
        foreach ($command in @("winget", "scoop.ps1", "mise")) {
            $output = Assert-FailureHint { Invoke-Native $command @("install", "example") } "$command failed with exit code 7"
            $expected = if ($language -eq "zh") { '/winenv/zh/guide/'; } else { "If this is a network error" }
            if ($output -notmatch [regex]::Escape($expected) -or $output -notmatch "original manager output") {
                throw "Manager output or localized guidance is missing: $output"
            }
        }
    }
    Initialize-WinenvLocalization en
    Assert-FailureHint { Invoke-Native local-installer @("/S") } "local-installer failed with exit code 7" $false | Out-Null
    $ignored = (Invoke-Native winget @("list") -IgnoreExitCode 6>&1 | Out-String)
    $networkTest.NativeExitCode = 0
    $success = (Invoke-Native winget @("install", "example") 6>&1 | Out-String)
    $DryRun = $true
    $preview = (Invoke-Native winget @("install", "example") 6>&1 | Out-String)
    $DryRun = $false
    if (($ignored + $success + $preview) -match 'troubleshooting/#network-and-proxy') {
        throw "A successful, ignored, or dry-run command displayed network guidance."
    }

    $networkTest.WebCalls = 0
    function Invoke-WebRequest { $networkTest.WebCalls++; throw "original download failure" }
    function Invoke-RestMethod { $networkTest.WebCalls++; throw "original download failure" }
    function Get-ManagerProbe { [pscustomobject]@{ Status = "missing" } }
    function Get-ExecutionPolicy { "RemoteSigned" }
    function Test-IsWindowsPlatform { $false }

    Assert-FailureHint { Read-UserProfileSource "https://example.invalid/profile.json" } "original download failure" | Out-Null
    Assert-FailureHint { Install-ScoopManifest "https://example.invalid/app.json" } "original download failure" | Out-Null
    Assert-FailureHint { Ensure-Scoop } "original download failure" | Out-Null
    if ($networkTest.WebCalls -ne 3) { throw "Failed requests must not be retried." }
    Assert-FailureHint { Read-UserProfileSource "http://example.invalid/profile.json" } "Shared profiles must use HTTPS: http://example.invalid/profile.json" $false | Out-Null
    function Invoke-WebRequest { [pscustomobject]@{ Content = '{"schemaVersion":1}' } }
    $download = (Read-UserProfileSource "https://example.invalid/profile.json" 6>&1 | Out-String)
    if ($download -match 'troubleshooting/#network-and-proxy') { throw "A successful download displayed a failure hint." }

    # Exercise the standalone bootstrap in isolated state. No script is downloaded or executed.
    foreach ($language in @("en", "zh")) {
        $output = Assert-FailureHint { & (Join-Path $root "install.ps1") -ToolOnly -Language $language } "original download failure"
        $expected = if ($language -eq "zh") { '/winenv/zh/guide/' } else { "configure PowerShell's proxy yourself" }
        if ($output -notmatch [regex]::Escape($expected)) { throw "The bootstrap hint used the wrong language." }
    }
    function Invoke-RestMethod {
        [pscustomobject]@{
            tag_name = "v1.2.3"
            assets = @(
                [pscustomobject]@{ name = "winenv-1.2.3.zip"; browser_download_url = "https://example.invalid/package" },
                [pscustomobject]@{ name = "SHA256SUMS"; browser_download_url = "https://example.invalid/checksum" }
            )
        }
    }
    function Invoke-WebRequest {
        param($Uri, $OutFile, [switch]$UseBasicParsing)
        $networkTest.DownloadRoot = Split-Path -Parent $OutFile
        $networkTest.WebCalls++
        if (($networkTest.DownloadPhase -eq "zip") -or ($networkTest.DownloadPhase -eq "checksum" -and $Uri.EndsWith("checksum"))) {
            throw "original download failure"
        }
        $content = if ($Uri.EndsWith("checksum")) { ('0' * 64) + '  winenv-1.2.3.zip' } else { "harmless test fixture" }
        Set-Content -LiteralPath $OutFile -Value $content -Encoding ASCII
    }
    foreach ($phase in @("zip", "checksum", "hash")) {
        $networkTest.DownloadPhase = $phase
        $networkTest.WebCalls = 0
        $message = if ($phase -eq "hash") { "Checksum mismatch for winenv-1.2.3.zip." } else { "original download failure" }
        Assert-FailureHint { & (Join-Path $root "install.ps1") -ToolOnly -Language en } $message ($phase -ne "hash") | Out-Null
        $expectedCalls = if ($phase -eq "zip") { 1 } else { 2 }
        if ($networkTest.WebCalls -ne $expectedCalls -or (Test-Path -LiteralPath $networkTest.DownloadRoot)) {
            throw "Bootstrap requests were retried or temporary downloads were not cleaned up."
        }
    }
    if (Test-Path -LiteralPath $testRoot) { throw "Failure guidance unexpectedly created persistent user state." }
} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    $global:LASTEXITCODE = $previousExitCode
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
