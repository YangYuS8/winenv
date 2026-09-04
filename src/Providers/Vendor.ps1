# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function Test-WindowsInstallerReference {
    param([string]$Reference)
    $extension = Get-ReferenceExtension $Reference
    return $extension -in @(".exe", ".msi")
}

function Get-InstallerInspection {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path
    $versionInfo = $item.VersionInfo
    $signatureStatus = "Unavailable"
    $publisher = ""
    $signatureMessage = "Authenticode inspection is only available on Windows."
    if (Test-IsWindowsPlatform) {
        try {
            $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
            $signatureStatus = [string]$signature.Status
            $signatureMessage = [string]$signature.StatusMessage
            if ($null -ne $signature.SignerCertificate) {
                $publisher = $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
            }
        } catch {
            $signatureStatus = "Error"
            $signatureMessage = $_.Exception.Message
        }
    }
    return [pscustomobject]@{
        Path = $item.FullName
        Type = $item.Extension.TrimStart(".").ToUpperInvariant()
        Size = [long]$item.Length
        Sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        Product = if ($null -ne $versionInfo) { [string]$versionInfo.ProductName } else { "" }
        Version = if ($null -ne $versionInfo) { [string]$versionInfo.ProductVersion } else { "" }
        SignatureStatus = $signatureStatus
        SignatureMessage = $signatureMessage
        Publisher = $publisher
    }
}

function ConvertTo-WindowsCommandLineArgument {
    param([AllowEmptyString()][string]$Value)

    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq [char]92) {
            $backslashes++
            continue
        }
        if ($character -eq [char]34) {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Join-WindowsCommandLineArguments {
    param([string[]]$Arguments)
    return (@($Arguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument ([string]$_) }) -join " ")
}

function Invoke-WindowsInstallerProcess {
    param(
        [string]$Path,
        [string]$Type,
        [string[]]$Arguments,
        [string]$LogPath = ""
    )

    if ($Type -eq "MSI") {
        $command = "msiexec.exe"
        $processArguments = @("/i", $Path)
        if (@($Arguments | Where-Object { $_ -match "^/(no|prompt|force)restart$" }).Count -eq 0) {
            $processArguments += "/norestart"
        }
        if (@($Arguments | Where-Object { $_ -match "^/l" }).Count -eq 0) {
            $processArguments += @("/L*V", $LogPath)
        }
        $processArguments += @($Arguments)
        $workingDirectory = Split-Path -Parent $Path
    } else {
        $command = $Path
        $processArguments = @($Arguments)
        $workingDirectory = Split-Path -Parent $Path
    }
    $argumentLine = Join-WindowsCommandLineArguments $processArguments
    $commandLine = ConvertTo-WindowsCommandLineArgument $command
    if ($argumentLine) { $commandLine += " $argumentLine" }
    Write-Plan $commandLine
    if ($DryRun) { return 0 }
    if (-not (Test-IsWindowsPlatform)) { throw "EXE and MSI installers can only run on Windows." }

    if ($Type -eq "MSI") {
        New-Item -ItemType Directory -Path (Split-Path -Parent $LogPath) -Force | Out-Null
    }
    try {
        $processParameters = @{
            FilePath = $command
            WorkingDirectory = $workingDirectory
            Wait = $true
            PassThru = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($argumentLine)) {
            $processParameters.ArgumentList = $argumentLine
        }
        $process = Start-Process @processParameters
        $process.WaitForExit()
        return [int]$process.ExitCode
    } catch {
        throw "Unable to start the $Type installer: $($_.Exception.Message)"
    }
}

function Install-LocalWindowsInstaller {
    param([string]$Reference)

    if ($Reference -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
        throw "Direct EXE/MSI installation accepts local files only. Download the installer first so its signature and hash can be reviewed."
    }
    if (-not (Test-Path -LiteralPath $Reference -PathType Leaf)) {
        throw "Windows installer was not found: $Reference"
    }
    $path = (Resolve-Path -LiteralPath $Reference).Path
    $inspection = Get-InstallerInspection $path
    if ($inspection.Type -notin @("EXE", "MSI")) { throw "Unsupported Windows installer type: $($inspection.Type)" }

    $expectedHashVerified = $false
    if (-not [string]::IsNullOrWhiteSpace($Sha256)) {
        $normalizedExpectedHash = $Sha256.Trim().ToLowerInvariant()
        if ($normalizedExpectedHash -notmatch "^[a-f0-9]{64}$") { throw "-Hash must be a 64-character SHA-256 value." }
        if ($normalizedExpectedHash -ne $inspection.Sha256) {
            throw "Installer SHA-256 mismatch. Expected $normalizedExpectedHash but found $($inspection.Sha256)."
        }
        $expectedHashVerified = $true
    }

    Write-Step "Windows installer preview"
    $sizeLabel = if ($inspection.Size -ge 1MB) {
        "$([Math]::Round($inspection.Size / 1MB, 2)) MiB"
    } elseif ($inspection.Size -ge 1KB) {
        "$([Math]::Round($inspection.Size / 1KB, 2)) KiB"
    } else {
        "$($inspection.Size) bytes"
    }
    Write-WinenvHost "File:       $($inspection.Path)"
    Write-WinenvHost "Type:       $($inspection.Type)"
    Write-WinenvHost "Size:       $sizeLabel"
    if ($inspection.Product) { Write-WinenvHost "Product:    $($inspection.Product)" }
    if ($inspection.Version) { Write-WinenvHost "Version:    $($inspection.Version)" }
    Write-WinenvHost "SHA-256:    $($inspection.Sha256)"
    if ($expectedHashVerified) { Write-WinenvHost "Hash check: matched -Hash" -ForegroundColor Green }
    Write-WinenvHost "Signature:  $($inspection.SignatureStatus)"
    if ($inspection.Publisher) { Write-WinenvHost "Publisher:  $($inspection.Publisher)" }
    if ($inspection.SignatureStatus -ne "Valid") {
        Write-WinenvHost $inspection.SignatureMessage -ForegroundColor Yellow
    }
    if ($HasInstallerArguments) {
        Write-WinenvHost "Arguments:  $(Join-WindowsCommandLineArguments $InstallerArguments)"
    }

    $safeForUnattended = $inspection.SignatureStatus -eq "Valid" -or ($inspection.SignatureStatus -eq "NotSigned" -and $expectedHashVerified)
    if ($Yes -and -not $DryRun -and -not $safeForUnattended) {
        throw "This installer is not covered by a valid Authenticode signature or a pinned hash for an unsigned file. Run interactively to review it, or provide a trusted -Hash value."
    }
    if (-not (Confirm-Operation "Run this $($inspection.Type) installer?")) {
        Write-WinenvHost "Installer launch cancelled."
        return
    }

    $logPath = if ($inspection.Type -eq "MSI") {
        Join-Path $InstallerLogRoot ("msi-{0}-{1}.log" -f (Get-Date -Format "yyyyMMdd-HHmmssfff"), $inspection.Sha256.Substring(0, 12))
    } else { "" }
    $effectiveInstallerArguments = if ($HasInstallerArguments) { @($InstallerArguments) } else { @() }
    $exitCode = Invoke-WindowsInstallerProcess $path $inspection.Type $effectiveInstallerArguments $logPath
    if ($DryRun) { return }
    if ($exitCode -notin @(0, 1641, 3010)) {
        $logHint = if ($logPath) { " MSI log: $logPath" } else { "" }
        throw "$($inspection.Type) installer exited with code $exitCode.$logHint"
    }
    if ($exitCode -in @(1641, 3010)) {
        Write-WinenvHost "Installation completed and Windows reports that a restart is required." -ForegroundColor Yellow
    } else {
        Write-WinenvHost "Installer completed successfully." -ForegroundColor Green
    }
    if ($logPath) { Write-WinenvHost "MSI log: $logPath" }
    Write-WinenvHost "If the installer registered the app with Windows, it will appear in 'win rm'." -ForegroundColor DarkGray
}

function Invoke-VendorProviderInstall {
    param($Package, $Context)
    Write-WinenvHost "Manual vendor-managed package: $($Package.displayName)" -ForegroundColor Yellow
    if ($Package.instructions) { Write-WinenvHost $Package.instructions }
}

function Invoke-VendorProviderRemove {
    param($Package, $Context)
    throw "Vendor-managed packages must be removed according to their recorded instructions."
}
