$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root "win.ps1"
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $env:LOCALAPPDATA = [IO.Path]::GetTempPath()
}

Write-Host "Checking prerequisite detection..."

& {
    param($WinenvEntry)

    . $WinenvEntry version | Out-Null

    $testBinA = Join-Path ([IO.Path]::GetTempPath()) ("winenv-requirements-a-" + [Guid]::NewGuid().ToString("N"))
    $testBinB = Join-Path ([IO.Path]::GetTempPath()) ("winenv-requirements-b-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $testBinA, $testBinB -Force | Out-Null
    $originalPath = $env:Path
    $originalUpperPath = $env:PATH

    function New-TestCommand {
        param(
            [string]$Directory,
            [string]$Name,
            [string]$Output,
            [int]$ExitCode = 0
        )
        if (Test-IsWindowsPlatform) {
            $path = Join-Path $Directory "$Name.cmd"
            @("@echo off", "echo $Output", "exit /b $ExitCode") | Set-Content -Path $path -Encoding ASCII
        } else {
            $path = Join-Path $Directory $Name
            @("#!/bin/sh", "echo '$Output'", "exit $ExitCode") | Set-Content -Path $path -Encoding utf8NoBOM
            & chmod "+x" $path
        }
        return $path
    }

    try {
        $pathSeparator = [string][IO.Path]::PathSeparator
        $env:Path = "$testBinA$pathSeparator$testBinB$pathSeparator$originalPath"
        if (-not (Test-IsWindowsPlatform)) {
            $env:PATH = "$testBinA$pathSeparator$testBinB$pathSeparator$originalUpperPath"
        }

        $healthyPath = New-TestCommand $testBinA "winenv-probe-ok" "1.2.3"
        New-TestCommand $testBinB "winenv-probe-ok" "1.1.0" | Out-Null
        New-TestCommand $testBinA "winenv-probe-old" "0.9.0" | Out-Null
        New-TestCommand $testBinA "winenv-probe-broken" "failed" 7 | Out-Null

        $RuntimeRequirements["test-ok"] = [pscustomobject]@{ Name = "test ok"; Command = "winenv-probe-ok"; MinimumVersion = [Version]"1.0.0" }
        $RuntimeRequirements["test-old"] = [pscustomobject]@{ Name = "test old"; Command = "winenv-probe-old"; MinimumVersion = [Version]"1.0.0" }
        $RuntimeRequirements["test-broken"] = [pscustomobject]@{ Name = "test broken"; Command = "winenv-probe-broken"; MinimumVersion = [Version]"1.0.0" }
        $RuntimeRequirements["test-shadow"] = [pscustomobject]@{ Name = "test shadow"; Command = "winenv-probe-shadow"; MinimumVersion = [Version]"1.0.0" }

        function winenv-probe-shadow { "9.9.9" }

        $healthyPackage = [pscustomobject]@{ key = "test-ok"; displayName = "test ok"; owner = "winget"; id = "Test.Ok"; _runtime = $true }
        $oldPackage = [pscustomobject]@{ key = "test-old"; displayName = "test old"; owner = "winget"; id = "Test.Old"; _runtime = $true }
        $brokenPackage = [pscustomobject]@{ key = "test-broken"; displayName = "test broken"; owner = "winget"; id = "Test.Broken"; _runtime = $true }
        $shadowPackage = [pscustomobject]@{ key = "test-shadow"; displayName = "test shadow"; owner = "winget"; id = "Test.Shadow"; _runtime = $true }

        $healthyProbe = Get-RuntimeRequirementProbe $healthyPackage
        if ($healthyProbe.Status -ne "available" -or $healthyProbe.Version -ne [Version]"1.2.3" -or $healthyProbe.Path -ne $healthyPath -or @($healthyProbe.OtherPaths).Count -lt 1) {
            throw "A healthy external runtime command was not selected or its duplicate paths were not reported: status=$($healthyProbe.Status), version=$($healthyProbe.Version), path=$($healthyProbe.Path), expected=$healthyPath, others=$(@($healthyProbe.OtherPaths) -join '|')."
        }
        if ((Get-RuntimeRequirementProbe $oldPackage).Status -ne "outdated") {
            throw "An outdated runtime command was not rejected."
        }
        if ((Get-RuntimeRequirementProbe $brokenPackage).Status -ne "broken") {
            throw "A broken runtime command was not rejected."
        }
        $shadowProbe = Get-RuntimeRequirementProbe $shadowPackage
        if ($shadowProbe.Status -ne "missing" -or (@($shadowProbe.Shadowing) -join " ") -notmatch "Function") {
            throw "A same-name function was incorrectly accepted as an installed runtime executable."
        }

        $DryRun = $true
        $reusePlan = Resolve-RuntimeInstallPlan @($healthyPackage)
        if (@($reusePlan.Packages).Count -ne 0) {
            throw "A healthy external runtime command was not reused."
        }
        $missingPlan = Resolve-RuntimeInstallPlan @($shadowPackage)
        if (@($missingPlan.Packages).Count -ne 1) {
            throw "A missing runtime executable did not retain its declared fallback package."
        }
        $conflictMessage = ""
        try {
            Resolve-RuntimeInstallPlan @($oldPackage) | Out-Null
        } catch {
            $conflictMessage = $_.Exception.Message
        }
        if ($conflictMessage -notmatch "explicit interactive choice") {
            throw "An unattended outdated-runtime conflict did not stop safely."
        }

        $marker = if (Test-IsWindowsPlatform) { "C:\winenv-process-only" } else { "/winenv-process-only" }
        $env:Path = "$marker;$originalPath"
        Refresh-ProcessPath
        if (@($env:Path -split ";") -notcontains $marker) {
            throw "Refreshing PATH discarded a process-only entry."
        }
    } finally {
        $env:Path = $originalPath
        if (-not (Test-IsWindowsPlatform)) { $env:PATH = $originalUpperPath }
        Remove-Item -Path $testBinA, $testBinB -Recurse -Force
    }
} $entry

& {
    param($WinenvEntry)

    . $WinenvEntry version | Out-Null
    $script:WinGetProbeCount = 0
    $script:AppInstallerRegistered = $false
    $DryRun = $false

    function Test-IsWindowsPlatform { return $true }
    function Get-ManagerProbe {
        param([string]$Name)
        $script:WinGetProbeCount++
        if ($script:WinGetProbeCount -eq 1) {
            return [pscustomobject]@{ Name = $Name; Status = "missing"; Version = $null; Path = ""; OtherPaths = @(); Error = "" }
        }
        return [pscustomobject]@{ Name = $Name; Status = "available"; Version = [Version]"1.0.0"; Path = "C:\fake\winget.exe"; OtherPaths = @(); Error = "" }
    }
    function Add-AppxPackage {
        [CmdletBinding()]
        param([switch]$RegisterByFamilyName, [string]$MainPackage)
        $script:AppInstallerRegistered = $RegisterByFamilyName -and $MainPackage -eq "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"
    }

    Ensure-WinGet
    if (-not $script:AppInstallerRegistered -or $ResolvedManagerCommands["winget"] -ne "C:\fake\winget.exe") {
        throw "A missing WinGet command was not re-registered and re-probed."
    }
} $entry

& {
    param($WinenvEntry)

    . $WinenvEntry version | Out-Null
    $DryRun = $true
    function Get-ManagerProbe {
        param([string]$Name)
        return [pscustomobject]@{ Name = $Name; Status = "missing"; Version = $null; Path = ""; OtherPaths = @(); Error = "" }
    }

    $misePlan = (Ensure-Mise 6>&1 | Out-String -Width 4096)
    if ($misePlan -notmatch "Installing mise with Scoop" -or $misePlan -notmatch "scoop install mise" -or $misePlan -match "jdx\.mise") {
        throw "A missing mise command did not use Scoop as its fallback provider."
    }

    function Get-ManagerProbe {
        param([string]$Name)
        return [pscustomobject]@{ Name = $Name; Status = "available"; Version = [Version]"2026.9.1"; Path = "C:\existing\mise.exe"; OtherPaths = @(); Error = "" }
    }
    $ResolvedManagerCommands = @{}
    $miseReuse = (Ensure-Mise 6>&1 | Out-String -Width 4096)
    if ($miseReuse -match "Installing mise" -or $ResolvedManagerCommands["mise"] -ne "C:\existing\mise.exe") {
        throw "A healthy existing mise executable was not reused."
    }
} $entry

Write-Host "Prerequisite detection checks passed." -ForegroundColor Green
