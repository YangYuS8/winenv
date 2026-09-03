$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root "win.ps1"
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $env:LOCALAPPDATA = [IO.Path]::GetTempPath()
}

Write-Host "Checking Scoop buckets and direct manifests..."

& {
    param($WinenvEntry)
    . $WinenvEntry version | Out-Null

    $custom = [pscustomobject]@{ name = "community"; url = "https://github.com/example/scoop-bucket.git" }
    $definition = [pscustomobject]@{
        schemaVersion = 1
        name = "bucket-test"
        defaultProfiles = @("default")
        scoopBuckets = @("main", $custom)
        packages = @()
    }
    Assert-ProfileDefinition $definition
    if (-not (($definition | ConvertTo-Json -Depth 8) | Test-Json -SchemaFile (Join-Path (Split-Path -Parent $WinenvEntry) "profile.schema.json"))) {
        throw "A mixed known/custom Scoop bucket profile did not match profile.schema.json."
    }
    $merged = @(Merge-ScoopBucketDefinitions @("main", $custom, [pscustomobject]@{ name = "community"; url = "https://github.com/example/scoop-bucket.git/" }))
    if ($merged.Count -ne 2 -or $merged[1].Name -ne "community") {
        throw "Equivalent Scoop bucket declarations were not normalized and deduplicated."
    }

    $conflictMessage = ""
    try {
        Merge-ScoopBucketDefinitions @(
            [pscustomobject]@{ name = "community"; url = "https://github.com/example/one.git" },
            [pscustomobject]@{ name = "community"; url = "https://github.com/example/two.git" }
        ) | Out-Null
    } catch { $conflictMessage = $_.Exception.Message }
    if ($conflictMessage -notmatch "conflicting sources") {
        throw "A same-name Scoop bucket source conflict was not rejected."
    }

    $insecureMessage = ""
    try {
        Assert-ProfileDefinition ([pscustomobject]@{
            schemaVersion = 1
            name = "bad-bucket"
            defaultProfiles = @("default")
            scoopBuckets = @([pscustomobject]@{ name = "unsafe"; url = "http://example.com/bucket.git" })
            packages = @()
        })
    } catch { $insecureMessage = $_.Exception.Message }
    if ($insecureMessage -notmatch "must use HTTPS") {
        throw "An insecure custom Scoop bucket URL was not rejected."
    }
} $entry

& {
    param($WinenvEntry)
    . $WinenvEntry version | Out-Null

    $DryRun = $false
    $Yes = $true
    $script:NativeCalls = @()
    function Get-ResolvedManagerCommand { param([string]$Name) return "C:\fake\scoop.ps1" }
    function Invoke-Native {
        param([string]$Command, [string[]]$Arguments, [switch]$IgnoreExitCode)
        $script:NativeCalls += ,@($Arguments)
    }
    function Get-ScoopBucketInventory {
        return @([pscustomobject]@{ Name = "community"; Source = "https://github.com/example/current.git" })
    }

    Ensure-ScoopBucket ([pscustomobject]@{ name = "community"; url = "https://github.com/example/current.git" })
    if ($script:NativeCalls.Count -ne 0) {
        throw "An existing Scoop bucket with the same source was not reused."
    }

    Ensure-ScoopBucket "extras"
    if (($script:NativeCalls[0] -join " ") -ne "bucket add extras") {
        throw "A missing known Scoop bucket was not added from Scoop's catalog."
    }
    $script:NativeCalls = @()

    $newBucket = [pscustomobject]@{ name = "new-source"; url = "https://github.com/example/new.git" }
    $trustMessage = ""
    try { Ensure-ScoopBucket $newBucket } catch { $trustMessage = $_.Exception.Message }
    if ($trustMessage -notmatch "explicit interactive trust" -or $script:NativeCalls.Count -ne 0) {
        throw "Unattended mode did not stop before trusting a new third-party bucket."
    }

    $changedBucket = [pscustomobject]@{ name = "community"; url = "https://github.com/example/changed.git" }
    $changedMessage = ""
    try { Ensure-ScoopBucket $changedBucket } catch { $changedMessage = $_.Exception.Message }
    if ($changedMessage -notmatch "explicit interactive trust" -or $script:NativeCalls.Count -ne 0) {
        throw "Unattended mode did not stop before changing a third-party bucket source."
    }

    $ApprovedScoopBucketSources[(Get-ScoopBucketApprovalKey $changedBucket)] = $true
    Ensure-ScoopBucket $changedBucket
    $commands = @($script:NativeCalls | ForEach-Object { $_ -join " " })
    if ($commands.Count -ne 2 -or $commands[0] -ne "bucket rm community" -or $commands[1] -ne "bucket add community https://github.com/example/changed.git") {
        throw "An explicitly approved Scoop bucket source change was not applied safely."
    }
} $entry

& {
    param($WinenvEntry)
    . $WinenvEntry version | Out-Null

    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-scoop-manifest-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $manifestPath = Join-Path $testRoot "sample-app.json"
    [pscustomobject]@{
        version = "1.2.3"
        description = "Test manifest"
        homepage = "https://example.com"
        url = "https://example.com/sample.zip"
        hash = "0123456789abcdef"
        bin = "sample.exe"
    } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    try {
        $DryRun = $false
        $Yes = $true
        $script:InstalledManifest = ""
        function Ensure-Scoop {}
        function Get-ResolvedManagerCommand { param([string]$Name) return "C:\fake\scoop.ps1" }
        function Invoke-Native {
            param([string]$Command, [string[]]$Arguments, [switch]$IgnoreExitCode)
            if ($Arguments[0] -eq "install") { $script:InstalledManifest = [string]$Arguments[1] }
        }

        $preview = (Install-ScoopManifest $manifestPath 6>&1 | Out-String -Width 4096)
        if ($preview -notmatch "SHA-256" -or $preview -notmatch "1\.2\.3" -or [IO.Path]::GetFileName($script:InstalledManifest) -ne "sample-app.json") {
            throw "A local Scoop manifest was not previewed and installed from a name-preserving snapshot."
        }
        if (Test-Path -LiteralPath $script:InstalledManifest) {
            throw "The temporary Scoop manifest snapshot was not cleaned up."
        }
    } finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
} $entry

Write-Host "Scoop source checks passed." -ForegroundColor Green
