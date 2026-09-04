# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function Get-WinGetCandidates {
    param(
        [string]$Query,
        [switch]$Installed
    )
    if (-not (Test-Command "winget")) { return @() }

    $arguments = if ($Installed) {
        @("list", "--accept-source-agreements", "--disable-interactivity")
    } else {
        @("search", "--query", $Query, "--count", "50", "--accept-source-agreements", "--disable-interactivity")
    }
    if ($Installed -and -not [string]::IsNullOrWhiteSpace($Query)) {
        $arguments = @("list", "--query", $Query, "--accept-source-agreements", "--disable-interactivity")
    }

    $result = Invoke-CapturedCommand "winget" $arguments
    if ($result.ExitCode -ne 0) { return @() }
    return @(ConvertFrom-FixedWidthTable $result.Lines | ForEach-Object {
        $values = @($_)
        $source = if ($values.Count -ge 4) { [string]$values[-1] } else { "" }
        $sourceMatched = -not [string]::IsNullOrWhiteSpace($source)
        if (-not $Installed -and -not $sourceMatched) {
            $source = "winget"
            $sourceMatched = $true
        }
        if ($Installed -and -not $sourceMatched) { $source = "windows" }
        New-PackageCandidate -ManagerName "winget" -Id $values[1] -Name $values[0] -Version $values[2] -Source $source -Adoptable:$sourceMatched
    })
}

function Get-WinGetExportInventory {
    if (-not (Test-Command "winget")) {
        return [pscustomobject]@{ Succeeded = $false; Candidates = @() }
    }

    $exportPath = Join-Path ([IO.Path]::GetTempPath()) ("winenv-winget-export-" + [Guid]::NewGuid().ToString("N") + ".json")
    try {
        $result = Invoke-CapturedCommand "winget" @(
            "export", "--output", $exportPath, "--include-versions", "--accept-source-agreements", "--disable-interactivity"
        )
        if (-not (Test-Path -LiteralPath $exportPath -PathType Leaf)) {
            return [pscustomobject]@{ Succeeded = $false; Candidates = @() }
        }
        try {
            $export = Get-Content -Raw -Encoding UTF8 -LiteralPath $exportPath | ConvertFrom-Json -ErrorAction Stop
        } catch {
            return [pscustomobject]@{ Succeeded = $false; Candidates = @() }
        }
        $candidates = @($export.Sources | ForEach-Object {
            $sourceName = if ($_.SourceDetails -and $_.SourceDetails.Name) { [string]$_.SourceDetails.Name } else { "winget" }
            foreach ($package in @($_.Packages)) {
                $version = if (@($package.psobject.Properties.Name) -contains "Version") { [string]$package.Version } else { "" }
                New-PackageCandidate -ManagerName "winget" -Id ([string]$package.PackageIdentifier) -Name ([string]$package.PackageIdentifier) -Version $version -Source $sourceName
            }
        })
        return [pscustomobject]@{ Succeeded = $true; Candidates = $candidates }
    } finally {
        if (Test-Path -LiteralPath $exportPath) { Remove-Item -LiteralPath $exportPath -Force }
    }
}

function Resolve-WinGetInstalledInventory {
    param(
        $Definition,
        [array]$TableCandidates,
        [string]$Query = ""
    )

    $exportResult = Get-WinGetExportInventory
    if (-not $exportResult.Succeeded) { return @($TableCandidates) }
    $managed = @(Get-ManagedCandidates $Definition $Query | Where-Object Manager -eq "winget")
    $resolved = @($exportResult.Candidates | ForEach-Object {
        $exported = $_
        $tableMatch = @($TableCandidates | Where-Object {
            if ($_.Manager -ne "winget") { return $false }
            $tableId = [string]$_.Id
            if ($tableId.Equals([string]$exported.Id, [StringComparison]::OrdinalIgnoreCase)) { return $true }
            $prefix = [regex]::Replace($tableId, "(?:\u2026|\.\.\.)$", "")
            return $prefix.Length -ge 4 -and ([string]$exported.Id).StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($tableMatch.Count -eq 1) {
            $exported.Name = [string]$tableMatch[0].Name
            if ([string]::IsNullOrWhiteSpace([string]$exported.Version)) { $exported.Version = [string]$tableMatch[0].Version }
        }
        $managedMatch = @($managed | Where-Object {
            ([string]$_.Id).Equals([string]$exported.Id, [StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1)
        if ($managedMatch.Count -gt 0) { $exported.ManagedKey = [string]$managedMatch[0].ManagedKey }
        if ([string]::IsNullOrWhiteSpace($Query) -or
            ([string]$exported.Name).IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            ([string]$exported.Id).IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $exported
        }
    })
    $local = @($TableCandidates | Where-Object { $_.Manager -eq "winget" -and -not [bool]$_.Adoptable })
    return @($resolved + $local)
}

function Ensure-WinGet {
    $probe = Get-ManagerProbe "winget"
    if ($probe.Status -eq "available") {
        $ResolvedManagerCommands["winget"] = $probe.Path
        return
    }
    if ($probe.Status -eq "broken") {
        throw "WinGet exists at $($probe.Path), but 'winget --version' failed. Repair App Installer, then run 'win check'."
    }

    Write-Step "Preparing WinGet"
    $registerCommand = "Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe"
    if ($DryRun) {
        Write-Plan $registerCommand
        Write-Plan "If registration fails, repair App Installer with Microsoft.WinGet.Client or install it from Microsoft Store"
        return
    }
    if (-not (Test-IsWindowsPlatform)) {
        throw "WinGet is required and is only available on Windows 10 1809 or later."
    }
    if (-not (Get-Command "Add-AppxPackage" -ErrorAction SilentlyContinue)) {
        throw "WinGet is missing and App Installer could not be registered because Add-AppxPackage is unavailable. Install App Installer from Microsoft Store."
    }

    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe" -ErrorAction Stop
    } catch {
        throw "WinGet is missing and App Installer registration failed. Install App Installer from Microsoft Store, or run: Install-Module Microsoft.WinGet.Client -Force -Repository PSGallery; Repair-WinGetPackageManager -AllUsers"
    }
    Refresh-ProcessPath
    $probe = Get-ManagerProbe "winget"
    if ($probe.Status -ne "available") {
        throw "App Installer was registered, but WinGet is still unavailable. Open a new PowerShell window and run 'win check'. If it remains missing, repair App Installer with Microsoft.WinGet.Client."
    }
    $ResolvedManagerCommands["winget"] = $probe.Path
}

function Test-WinGetManifestReference {
    param([string]$Reference)
    if (Test-Path -LiteralPath $Reference -PathType Container) {
        return @(Get-ChildItem -LiteralPath $Reference -File -Recurse | Where-Object { $_.Extension -in @(".yaml", ".yml") }).Count -gt 0
    }
    return (Get-ReferenceExtension $Reference) -in @(".yaml", ".yml")
}

function Get-WinGetManifestFiles {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        return @(Get-ChildItem -LiteralPath $Path -File -Recurse | Where-Object { $_.Extension -in @(".yaml", ".yml") } | Sort-Object FullName)
    }
    return @(Get-Item -LiteralPath $Path)
}

function Test-WinGetLocalManifestEnabled {
    param([string]$Command)
    $result = Invoke-CapturedCommand $Command @("settings", "export")
    if ($result.ExitCode -ne 0) { return $false }
    try {
        $settings = (@($result.Lines | ForEach-Object { [string]$_ }) -join "`n") | ConvertFrom-Json -ErrorAction Stop
        $value = $settings.adminSettings.LocalManifestFiles
        return $value -eq $true -or [string]$value -match "^(true|enabled)$"
    } catch {
        return $false
    }
}

function Install-WinGetManifest {
    param([string]$Reference)

    if ($Reference -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
        throw "WinGet local manifests must be a local YAML file or directory. Clone or download the manifest first."
    }
    if (-not (Test-Path -LiteralPath $Reference)) { throw "WinGet manifest was not found: $Reference" }
    $path = (Resolve-Path -LiteralPath $Reference).Path
    $files = @(Get-WinGetManifestFiles $path)
    if ($files.Count -eq 0 -or @($files | Where-Object { $_.Extension -notin @(".yaml", ".yml") }).Count -gt 0) {
        throw "A WinGet manifest must be a YAML file or a directory containing YAML manifests."
    }

    Write-Step "Local WinGet manifest preview"
    Write-WinenvHost "Path: $path"
    $files | ForEach-Object {
        [pscustomobject]@{
            File = $_.Name
            Size = $_.Length
            Sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    } | Format-WinenvTable -AutoSize
    Write-WinenvHost "WinGet manifests select and run installers. Only continue if you trust these local files and their installer URLs." -ForegroundColor Yellow
    if (-not (Confirm-Operation "Validate and install this local WinGet manifest?")) {
        Write-WinenvHost "Manifest installation cancelled."
        return
    }

    Ensure-WinGet
    $wingetCommand = Get-ResolvedManagerCommand "winget"
    if (-not $DryRun -and -not (Test-WinGetLocalManifestEnabled $wingetCommand)) {
        throw "WinGet local manifests are disabled. Run this once from an administrator PowerShell, then retry: winget settings --enable LocalManifestFiles"
    }
    Invoke-Native $wingetCommand @("validate", $path)
    Invoke-Native $wingetCommand @(
        "install", "--manifest", $path, "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"
    )
    if (-not $DryRun) { Write-WinenvHost "Local WinGet manifest installed successfully." -ForegroundColor Green }
}

function Install-WinGetPackage {
    param($Package)
    $source = if ($Package.source) { [string]$Package.source } else { "winget" }
    Invoke-Native (Get-ResolvedManagerCommand "winget") @(
        "install", "--id", [string]$Package.id, "--exact", "--source", $source,
        "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"
    )
}

function Invoke-WinGetProviderInstall {
    param($Package, $Context)
    Install-WinGetPackage $Package
}

function Invoke-WinGetProviderRemove {
    param($Package, $Context)
    Ensure-WinGet
    Invoke-Native (Get-ResolvedManagerCommand "winget") @(
        "uninstall", "--id", [string]$Package.id, "--exact", "--disable-interactivity"
    )
}
