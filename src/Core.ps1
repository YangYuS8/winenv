# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function Update-WinenvSelf {
    $installerPath = Join-Path $WinenvRoot "install.ps1"
    if (-not (Test-Path $installerPath)) {
        throw "Self-update installer not found: $installerPath"
    }

    Write-Step "Updating Winenv"
    Write-Plan "$installerPath -ToolOnly"
    if ($DryRun) { return }
    & $installerPath -ToolOnly
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$IgnoreExitCode
    )

    Write-Plan ((@($Command) + $Arguments) -join " ")
    if ($DryRun) { return }

    & $Command @Arguments
    $exitCode = $LASTEXITCODE
    if (-not $IgnoreExitCode -and $null -ne $exitCode -and $exitCode -ne 0) {
        throw "$Command failed with exit code $exitCode"
    }
}

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($pathValue in @($env:Path, $machinePath, $userPath)) {
        foreach ($entry in @([string]$pathValue -split ";")) {
            if ([string]::IsNullOrWhiteSpace($entry)) { continue }
            $expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim())
            $key = $expanded.TrimEnd("\").ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $entries.Add($expanded)
            }
        }
    }
    $env:Path = $entries -join ";"
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsWindowsPlatform {
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Get-ExternalCommandCandidates {
    param([string]$Name)
    return @(Get-Command $Name -All -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandType -in @("Application", "ExternalScript") -and
        -not [string]::IsNullOrWhiteSpace([string]$_.Path)
    })
}

function Invoke-CommandProbe {
    param(
        [string]$Path,
        [string[]]$Arguments
    )
    try {
        $global:LASTEXITCODE = 0
        $lines = @(& $Path @Arguments 2>&1)
        $succeeded = $?
        $exitCode = if ($null -eq $LASTEXITCODE) {
            if ($succeeded) { 0 } else { 1 }
        } else {
            [int]$LASTEXITCODE
        }
        return [pscustomobject]@{
            Lines = @($lines | ForEach-Object { [string]$_ })
            ExitCode = $exitCode
            Error = ""
        }
    } catch {
        return [pscustomobject]@{
            Lines = @()
            ExitCode = 1
            Error = $_.Exception.Message
        }
    }
}

function ConvertTo-DetectedVersion {
    param([array]$Lines)
    $text = @($Lines) -join "`n"
    $match = [Regex]::Match($text, "(?<!\d)(\d+\.\d+(?:\.\d+){0,2})")
    if (-not $match.Success) { return $null }
    try { return [Version]$match.Groups[1].Value } catch { return $null }
}

function Get-ManagerProbe {
    param([ValidateSet("winget", "scoop", "mise")][string]$Name)
    $candidates = @(Get-ExternalCommandCandidates $Name)
    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{
            Name = $Name
            Status = "missing"
            Version = $null
            Path = ""
            OtherPaths = @()
            Error = ""
        }
    }

    $path = [string]$candidates[0].Path
    $result = Invoke-CommandProbe $path @("--version")
    return [pscustomobject]@{
        Name = $Name
        Status = if ($result.ExitCode -eq 0) { "available" } else { "broken" }
        Version = ConvertTo-DetectedVersion $result.Lines
        Path = $path
        OtherPaths = @($candidates | Select-Object -Skip 1 | ForEach-Object Path | Select-Object -Unique)
        Error = [string]$result.Error
    }
}

function Get-RuntimeRequirement {
    param($Package)
    if ($null -eq $Package -or -not [bool]$Package._runtime) { return $null }
    $key = [string]$Package.key
    if (-not $RuntimeRequirements.ContainsKey($key)) { return $null }
    return $RuntimeRequirements[$key]
}

function Get-RuntimeRequirementProbe {
    param($Package)
    $requirement = Get-RuntimeRequirement $Package
    if ($null -eq $requirement) { return $null }

    $allCommands = @(Get-Command $requirement.Command -All -ErrorAction SilentlyContinue)
    $candidates = @($allCommands | Where-Object {
        $_.CommandType -in @("Application", "ExternalScript") -and
        -not [string]::IsNullOrWhiteSpace([string]$_.Path)
    })
    $shadowing = @($allCommands | Where-Object {
        $_.CommandType -notin @("Application", "ExternalScript")
    } | ForEach-Object { "$($_.CommandType):$($_.Name)" } | Select-Object -Unique)

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{
            Name = $requirement.Name
            Command = $requirement.Command
            Status = "missing"
            Version = $null
            MinimumVersion = $requirement.MinimumVersion
            Path = ""
            OtherPaths = @()
            Shadowing = $shadowing
            Error = ""
        }
    }

    $path = [string]$candidates[0].Path
    $arguments = if ($requirement.Command -eq "pwsh") {
        @("-NoLogo", "-NoProfile", "-Command", '$PSVersionTable.PSVersion.ToString()')
    } else {
        @("--version")
    }
    $result = Invoke-CommandProbe $path $arguments
    $version = ConvertTo-DetectedVersion $result.Lines
    $status = if ($result.ExitCode -ne 0 -or $null -eq $version) {
        "broken"
    } elseif ($version -lt $requirement.MinimumVersion) {
        "outdated"
    } else {
        "available"
    }
    return [pscustomobject]@{
        Name = $requirement.Name
        Command = $requirement.Command
        Status = $status
        Version = $version
        MinimumVersion = $requirement.MinimumVersion
        Path = $path
        OtherPaths = @($candidates | Select-Object -Skip 1 | ForEach-Object Path | Select-Object -Unique)
        Shadowing = $shadowing
        Error = [string]$result.Error
    }
}

function Get-ResolvedManagerCommand {
    param([ValidateSet("winget", "scoop", "mise")][string]$Name)
    if ($ResolvedManagerCommands.ContainsKey($Name)) {
        return [string]$ResolvedManagerCommands[$Name]
    }
    $probe = Get-ManagerProbe $Name
    if ($probe.Status -eq "available") {
        $ResolvedManagerCommands[$Name] = $probe.Path
        return [string]$probe.Path
    }
    if ($DryRun) { return $Name }
    throw "$Name is unavailable. Run 'win check' for details."
}

function Get-OptionalManagerCommand {
    param([ValidateSet("winget", "scoop", "mise")][string]$Name)
    $probe = Get-ManagerProbe $Name
    if ($probe.Status -eq "available") { return [string]$probe.Path }
    if ($DryRun -and (Test-Command $Name)) { return $Name }
    return $null
}

function Get-TextHash {
    param([string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
}

function Get-ReferenceExtension {
    param([string]$Reference)
    try {
        $uri = [Uri]$Reference
        if ($uri.IsAbsoluteUri -and $Reference -match "^[a-zA-Z][a-zA-Z0-9+.-]*://") {
            return [IO.Path]::GetExtension($uri.AbsolutePath)
        }
    } catch {}
    return [IO.Path]::GetExtension($Reference)
}
