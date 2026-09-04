# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function ConvertTo-WinenvLanguage {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    switch -Regex ($Value.Trim()) {
        "^(?i:auto)$" { return "auto" }
        "^(?i:zh|zh-cn|zh-hans)" { return "zh-CN" }
        "^(?i:en|en-us)" { return "en-US" }
        default { return "" }
    }
}

function Get-WinenvStoredLanguage {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return "" }
    try {
        $storedConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath $ConfigPath | ConvertFrom-Json -ErrorAction Stop
        return (ConvertTo-WinenvLanguage ([string]$storedConfig.language))
    } catch {
        return ""
    }
}

function Resolve-WinenvLanguage {
    param([string]$RequestedLanguage)

    $requested = ConvertTo-WinenvLanguage $RequestedLanguage
    if ($requested -and $requested -ne "auto") {
        return [pscustomobject]@{ Language = $requested; Source = "parameter" }
    }

    $environmentLanguage = ConvertTo-WinenvLanguage $env:WINENV_LANG
    if ($requested -ne "auto" -and $environmentLanguage -and $environmentLanguage -ne "auto") {
        return [pscustomobject]@{ Language = $environmentLanguage; Source = "environment" }
    }

    $storedLanguage = Get-WinenvStoredLanguage
    if ($requested -ne "auto" -and $storedLanguage -and $storedLanguage -ne "auto") {
        return [pscustomobject]@{ Language = $storedLanguage; Source = "config" }
    }

    $uiCulture = [Globalization.CultureInfo]::CurrentUICulture.Name
    $detected = if ($uiCulture -match "^(?i:zh)(-|$)") { "zh-CN" } else { "en-US" }
    return [pscustomobject]@{ Language = $detected; Source = "system" }
}

function Initialize-WinenvLocalization {
    param([string]$RequestedLanguage)

    $resolved = Resolve-WinenvLanguage $RequestedLanguage
    $Script:WinenvLanguage = [string]$resolved.Language
    $Script:WinenvLanguageSource = [string]$resolved.Source
    $Script:WinenvLocalization = $null
    if ($Script:WinenvLanguage -eq "zh-CN") {
        $resourcePath = Join-Path (Join-Path $WinenvRoot "locales") "zh-CN.json"
        if (Test-Path -LiteralPath $resourcePath) {
            try {
                $Script:WinenvLocalization = Get-Content -Raw -Encoding UTF8 -LiteralPath $resourcePath | ConvertFrom-Json -ErrorAction Stop
            } catch {
                $Script:WinenvLanguage = "en-US"
                $Script:WinenvLanguageSource = "fallback"
            }
        } else {
            $Script:WinenvLanguage = "en-US"
            $Script:WinenvLanguageSource = "fallback"
        }
    }
}

function ConvertTo-WinenvLocalizedText {
    param([AllowEmptyString()][string]$Text)
    if ($Script:WinenvLanguage -ne "zh-CN" -or $null -eq $Script:WinenvLocalization) { return $Text }

    $exactProperty = $Script:WinenvLocalization.exact.psobject.Properties[$Text]
    if ($null -ne $exactProperty) { return [string]$exactProperty.Value }

    $localized = $Text
    foreach ($rule in @($Script:WinenvLocalization.patterns)) {
        $localized = [regex]::Replace($localized, [string]$rule.pattern, [string]$rule.replacement)
    }
    foreach ($rule in @($Script:WinenvLocalization.replacements)) {
        $localized = $localized.Replace([string]$rule.source, [string]$rule.target)
    }
    return $localized
}

function Write-WinenvHost {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [AllowNull()][object[]]$Object,
        [object]$Separator = " ",
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor,
        [switch]$NoNewline
    )
    process {
        $text = ConvertTo-WinenvLocalizedText ((@($Object) | ForEach-Object { [string]$_ }) -join [string]$Separator)
        $parameters = @{}
        if ($PSBoundParameters.ContainsKey("ForegroundColor")) { $parameters.ForegroundColor = $ForegroundColor }
        if ($PSBoundParameters.ContainsKey("BackgroundColor")) { $parameters.BackgroundColor = $BackgroundColor }
        if ($NoNewline) { $parameters.NoNewline = $true }
        Microsoft.PowerShell.Utility\Write-Host $text @parameters
    }
}

function Read-WinenvHost {
    param([string]$Prompt)
    return & "Read-Host" (ConvertTo-WinenvLocalizedText $Prompt)
}

function Get-WinenvLocalizedColumnName {
    param([string]$Name)
    if ($Script:WinenvLanguage -ne "zh-CN") { return $Name }
    $property = $Script:WinenvLocalization.columnNames.psobject.Properties[$Name]
    if ($null -ne $property) { return [string]$property.Value }
    return $Name
}

function Get-WinenvLocalizedDisplayValue {
    param([string]$PropertyName, $Value)
    if ($Script:WinenvLanguage -ne "zh-CN" -or $PropertyName -notin @("status", "action")) { return $Value }
    $key = ([string]$Value).ToLowerInvariant()
    $property = $Script:WinenvLocalization.displayValues.psobject.Properties[$key]
    if ($null -ne $property) { return [string]$property.Value }
    return $Value
}

function Format-WinenvTable {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]$InputObject,
        [Parameter(Position = 0)][object[]]$Property,
        [switch]$AutoSize
    )
    begin { $items = New-Object System.Collections.Generic.List[object] }
    process { if ($null -ne $InputObject) { $items.Add($InputObject) } }
    end {
        if ($items.Count -eq 0) { return }
        $properties = if ($null -ne $Property -and $Property.Count -gt 0) {
            @($Property)
        } else {
            @($items[0].psobject.Properties | Select-Object -ExpandProperty Name)
        }
        if ($Script:WinenvLanguage -ne "zh-CN") {
            $items | Microsoft.PowerShell.Utility\Format-Table $properties -AutoSize:$AutoSize
            return
        }

        $localizedItems = @(foreach ($item in $items) {
            $row = [ordered]@{}
            foreach ($property in $properties) {
                $propertyName = [string]$property
                $value = $item.psobject.Properties[$propertyName].Value
                $row[(Get-WinenvLocalizedColumnName $propertyName)] = Get-WinenvLocalizedDisplayValue $propertyName $value
            }
            [pscustomobject]$row
        })
        $localizedItems | Microsoft.PowerShell.Utility\Format-Table -AutoSize:$AutoSize
    }
}

function Write-Step {
    param([string]$Message)
    Write-WinenvHost "`n==> $(ConvertTo-WinenvLocalizedText $Message)" -ForegroundColor Cyan
}

function Write-Plan {
    param([string]$Message)
    $localizedMessage = ConvertTo-WinenvLocalizedText $Message
    if ($DryRun) {
        Write-WinenvHost "[dry-run] $localizedMessage" -ForegroundColor DarkYellow
    } else {
        Write-WinenvHost $localizedMessage -ForegroundColor DarkGray
    }
}

function Show-WinenvVersion {
    if (Test-Path $VersionPath) {
        Write-Output ((Get-Content -Raw -Path $VersionPath).Trim())
    } else {
        Write-Output "development"
    }
}

function Show-WinenvHelp {
    if ($Script:WinenvLanguage -eq "zh-CN") {
        Write-WinenvHost (@($Script:WinenvLocalization.help) -join [Environment]::NewLine)
        return
    }
    Write-WinenvHost @"
Winenv keeps Windows software simple.

  win [software]       Search, select, and install
  win add [software]   Apply the profile, or install one known package
  win add <setup.exe|setup.msi>
                       Inspect and run a local Windows installer
  win add <manifest.yaml|folder>
                       Install from a local WinGet manifest
  win add <file.json>  Install a local or HTTPS Scoop manifest
  win bucket           List enabled Scoop buckets
  win bucket <name> [https-url]
                       Add a known or third-party Scoop bucket
  win rm [software]    Select and remove installed software
  win scan [software]  Inventory existing apps without changing anything
  win adopt [software] Select installed apps for a local reproducible profile
  win up               Update Winenv and all managed software
  win use <file|url>   Add, refresh, and install a profile
  win off [profile]    Disable one profile without uninstalling
  win ls               Show profiles and effective packages
  win diff [software]  Compare the effective profile with this PC
  win find <software>  Print search results without opening the picker
  win show <software>  Show package ownership and details
  win check            Check managers and command conflicts
  win clean            Remove unused package versions
  win lang [en|zh|auto]
                       Show or persist the interface language
  win ver              Print the Winenv version
  win help             Show this help

Useful shortcuts: -From winget|scoop|mise, -n (dry run), -y (confirm),
                  -Lang en|zh|auto, -Hash <sha256>, -Args <installer-arguments>.
"@
}

function Set-WinenvLanguage {
    $requested = if ([string]::IsNullOrWhiteSpace($Target)) { "" } else { ConvertTo-WinenvLanguage $Target }
    if ([string]::IsNullOrWhiteSpace($Target)) {
        $languageName = if ($Script:WinenvLanguage -eq "zh-CN") { [string]$Script:WinenvLocalization.displayName } else { "English" }
        Write-WinenvHost "Language: $languageName ($Script:WinenvLanguage)"
        Write-WinenvHost "Source:   $Script:WinenvLanguageSource"
        Write-WinenvHost "Use 'win lang en', 'win lang zh', or 'win lang auto' to change it." -ForegroundColor DarkGray
        return
    }
    if (-not $requested) {
        throw "Unsupported language '$Target'. Use en, zh, or auto."
    }

    $config = Read-WinenvConfig
    $config.language = $requested
    Initialize-WinenvLocalization $requested
    Write-WinenvConfig $config

    $languageName = if ($Script:WinenvLanguage -eq "zh-CN") { [string]$Script:WinenvLocalization.displayName } else { "English" }
    if ($DryRun) {
        Write-WinenvHost "Language would be set to $requested; current preview language is $languageName."
    } else {
        Write-WinenvHost "Language set to $requested. Current interface: $languageName." -ForegroundColor Green
    }
}

function Confirm-Operation {
    param([string]$Prompt)
    if ($Yes -or $DryRun) { return $true }
    $answer = Read-WinenvHost "$Prompt [y/N]"
    return $answer -match "^(?i:y|yes|\u662f|\u597d|\u786e\u8ba4)$"
}
