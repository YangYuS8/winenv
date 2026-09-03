$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root "win.ps1"
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    $env:LOCALAPPDATA = [IO.Path]::GetTempPath()
}

Write-Host "Checking direct Windows installers and local WinGet manifests..."

& {
    param($WinenvEntry)
    . $WinenvEntry version | Out-Null

    $quoted = ConvertTo-WindowsCommandLineArgument 'C:\Program Files\Example\'
    if ($quoted -ne '"C:\Program Files\Example\\"') {
        throw "Windows command-line quoting did not preserve a trailing backslash: $quoted"
    }
    $argumentLine = Join-WindowsCommandLineArguments @("/S", "INSTALLDIR=C:\Program Files\Example")
    if ($argumentLine -notmatch '^/S "INSTALLDIR=') {
        throw "Installer arguments were not quoted independently."
    }
} $entry

& {
    param($WinenvEntry)
    . $WinenvEntry version | Out-Null

    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-installer-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $installerPath = Join-Path $testRoot "sample.exe"
    Set-Content -LiteralPath $installerPath -Value "test installer" -Encoding ASCII
    $actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()

    try {
        $DryRun = $false
        $Yes = $true
        $script:InstallerRuns = 0
        function Get-InstallerInspection {
            param([string]$Path)
            return [pscustomobject]@{
                Path = $Path; Type = "EXE"; Size = 14; Sha256 = $actualHash
                Product = "Sample"; Version = "1.0"; SignatureStatus = "NotSigned"
                SignatureMessage = "The file is not digitally signed."; Publisher = ""
            }
        }
        function Invoke-WindowsInstallerProcess {
            param([string]$Path, [string]$Type, [string[]]$Arguments, [string]$LogPath)
            $script:InstallerRuns++
            return 0
        }

        $unsignedMessage = ""
        try { Install-LocalWindowsInstaller $installerPath } catch { $unsignedMessage = $_.Exception.Message }
        if ($unsignedMessage -notmatch "valid Authenticode signature" -or $script:InstallerRuns -ne 0) {
            throw "Unattended mode did not stop before an unpinned unsigned installer."
        }

        $Sha256 = $actualHash
        $pinnedOutput = (Install-LocalWindowsInstaller $installerPath 6>&1 | Out-String -Width 4096)
        if ($script:InstallerRuns -ne 1 -or $pinnedOutput -notmatch "Hash check: matched" -or $pinnedOutput -notmatch "completed successfully") {
            throw "A hash-pinned unsigned installer was not accepted in unattended mode."
        }

        $Sha256 = ("0" * 64)
        $mismatchMessage = ""
        try { Install-LocalWindowsInstaller $installerPath } catch { $mismatchMessage = $_.Exception.Message }
        if ($mismatchMessage -notmatch "SHA-256 mismatch" -or $script:InstallerRuns -ne 1) {
            throw "An installer hash mismatch did not stop before execution."
        }

        $Sha256 = $actualHash
        function Get-InstallerInspection {
            param([string]$Path)
            return [pscustomobject]@{
                Path = $Path; Type = "EXE"; Size = 14; Sha256 = $actualHash
                Product = "Sample"; Version = "1.0"; SignatureStatus = "HashMismatch"
                SignatureMessage = "The signature does not match the content."; Publisher = "Example"
            }
        }
        $invalidSignatureMessage = ""
        try { Install-LocalWindowsInstaller $installerPath } catch { $invalidSignatureMessage = $_.Exception.Message }
        if ($invalidSignatureMessage -notmatch "valid Authenticode signature" -or $script:InstallerRuns -ne 1) {
            throw "A hash did not preserve the interactive requirement for an invalid signature."
        }
    } finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
} $entry

& {
    param($WinenvEntry)
    . $WinenvEntry version | Out-Null

    $testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-winget-manifest-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    $manifestPath = Join-Path $testRoot "sample.yaml"
    Set-Content -LiteralPath $manifestPath -Value "PackageIdentifier: Example.Sample" -Encoding UTF8
    try {
        $DryRun = $false
        $Yes = $true
        $script:NativeCalls = @()
        function Ensure-WinGet {}
        function Get-ResolvedManagerCommand { param([string]$Name) return "C:\fake\winget.exe" }
        function Invoke-Native {
            param([string]$Command, [string[]]$Arguments, [switch]$IgnoreExitCode)
            $script:NativeCalls += ,@($Arguments)
        }
        function Test-WinGetLocalManifestEnabled { param([string]$Command) return $false }

        $disabledMessage = ""
        try { Install-WinGetManifest $manifestPath } catch { $disabledMessage = $_.Exception.Message }
        if ($disabledMessage -notmatch "settings --enable LocalManifestFiles" -or $script:NativeCalls.Count -ne 0) {
            throw "A disabled WinGet local-manifest setting did not stop before validation and installation."
        }

        function Test-WinGetLocalManifestEnabled { param([string]$Command) return $true }
        $installedOutput = (Install-WinGetManifest $manifestPath 6>&1 | Out-String -Width 4096)
        $commands = @($script:NativeCalls | ForEach-Object { $_ -join " " })
        if ($commands.Count -ne 2 -or $commands[0] -notmatch "^validate " -or $commands[1] -notmatch "^install --manifest " -or $installedOutput -notmatch "installed successfully") {
            throw "An enabled local WinGet manifest was not validated before installation."
        }
    } finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
} $entry

& {
    param($WinenvEntry)
    . $WinenvEntry version | Out-Null

    $DryRun = $true
    $plan = (Invoke-WindowsInstallerProcess "C:\Setup Files\sample.msi" "MSI" @("PROPERTY=hello world") "C:\Logs\sample.log" 6>&1 | Out-String -Width 4096)
    if ($plan -notmatch "msiexec\.exe" -or $plan -notmatch "/i" -or $plan -notmatch "/norestart" -or $plan -notmatch "/L\*V" -or $plan -notmatch '"PROPERTY=hello world"') {
        throw "The MSI execution plan did not use safe native defaults and preserve custom arguments."
    }
} $entry

& {
    param($WinenvEntry)
    . $WinenvEntry version | Out-Null

    function Invoke-CapturedCommand {
        param([string]$Command, [string[]]$Arguments)
        return [pscustomobject]@{ Lines = @('{"adminSettings":{"LocalManifestFiles":true}}'); ExitCode = 0 }
    }
    if (-not (Test-WinGetLocalManifestEnabled "C:\fake\winget.exe")) {
        throw "An enabled WinGet LocalManifestFiles setting was not detected."
    }
    function Invoke-CapturedCommand {
        param([string]$Command, [string[]]$Arguments)
        return [pscustomobject]@{ Lines = @('{"adminSettings":{"LocalManifestFiles":false}}'); ExitCode = 0 }
    }
    if (Test-WinGetLocalManifestEnabled "C:\fake\winget.exe") {
        throw "A disabled WinGet LocalManifestFiles setting was reported as enabled."
    }
} $entry

Write-Host "Windows installer checks passed." -ForegroundColor Green
