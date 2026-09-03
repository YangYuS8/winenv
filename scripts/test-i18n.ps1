$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root "win.ps1"
$localeRoot = Join-Path $root "locales"

Write-Host "Testing English-first localization..."

foreach ($locale in @("en-US", "zh-CN")) {
    $path = Join-Path $localeRoot "$locale.json"
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Locale resource is missing: $path"
    }
    try {
        $resource = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "Locale resource is not valid JSON: $path"
    }
    if ([string]$resource.language -ne $locale) {
        throw "Locale resource language does not match its file name: $path"
    }
}

$winSource = Get-Content -Raw -LiteralPath $entry
if ($winSource -match "[^\x00-\x7F]") {
    throw "win.ps1 must remain ASCII so Windows PowerShell can load it before locale resources."
}
$installerSource = Get-Content -Raw -LiteralPath (Join-Path $root "install.ps1")
if ($installerSource -match "[^\x00-\x7F]") {
    throw "install.ps1 must remain ASCII for Windows PowerShell bootstrap compatibility."
}
$tokens = $null
$errors = $null
$winAst = [Management.Automation.Language.Parser]::ParseInput($winSource, [ref]$tokens, [ref]$errors)
foreach ($command in @("Write-Host", "Read-Host", "Format-Table")) {
    $bypasses = @($winAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq $command
    }, $true) | Where-Object {
        $parent = $_.Parent
        while ($null -ne $parent -and $parent -isnot [Management.Automation.Language.FunctionDefinitionAst]) {
            $parent = $parent.Parent
        }
        -not ($command -eq "Read-Host" -and $null -ne $parent -and $parent.Name -eq "Read-WinenvHost")
    })
    if ($bypasses.Count -gt 0) { throw "win.ps1 bypasses the localization wrapper with $command." }
}

$previousLocalAppData = $env:LOCALAPPDATA
$previousLanguage = $env:WINENV_LANG
$previousCulture = [Globalization.CultureInfo]::CurrentCulture
$previousUICulture = [Globalization.CultureInfo]::CurrentUICulture
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-i18n-" + [Guid]::NewGuid().ToString("N"))

try {
    $env:LOCALAPPDATA = $testRoot
    $env:WINENV_LANG = $null

    $englishHelp = (& $entry help -Language en 6>&1 | Out-String -Width 4096)
    $chineseHelp = (& $entry help -Language zh 6>&1 | Out-String -Width 4096)
    if ($englishHelp -notmatch "Winenv keeps Windows software simple" -or $englishHelp -match "Winenv 让 Windows") {
        throw "The explicit English interface did not render English help."
    }
    if ($chineseHelp -notmatch "Winenv 让 Windows 软件管理保持简单" -or $chineseHelp -match "Winenv keeps Windows") {
        throw "The explicit Chinese interface did not render Chinese help."
    }

    $installerPrefix = $installerSource.Substring(0, $installerSource.IndexOf('$release = Get-WinenvRelease'))
    $installerProbe = [scriptblock]::Create($installerPrefix + "`n" + 'Get-InstallerText Downloading -Arguments @("1.2.3")')
    $installerText = (& $installerProbe -Language zh | Out-String)
    if ($installerText -notmatch "正在下载 Winenv 1\.2\.3") {
        throw "The bootstrap installer did not render its embedded Chinese messages."
    }

    & $entry lang zh | Out-Null
    $configPath = Join-Path $testRoot "Winenv\config.json"
    $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    $storedHelp = (& $entry help 6>&1 | Out-String -Width 4096)
    if ($config.language -ne "zh-CN" -or $storedHelp -notmatch "Winenv 让 Windows") {
        throw "The persisted language preference was not reused."
    }

    $env:WINENV_LANG = "en"
    $environmentHelp = (& $entry help 6>&1 | Out-String -Width 4096)
    $parameterHelp = (& $entry help -Language zh 6>&1 | Out-String -Width 4096)
    if ($environmentHelp -notmatch "Winenv keeps Windows" -or $parameterHelp -notmatch "Winenv 让 Windows") {
        throw "Language parameter and environment-variable precedence is incorrect."
    }

    $env:WINENV_LANG = $null
    & $entry lang auto | Out-Null
    $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    if ($config.language -ne "auto") {
        throw "Automatic language selection was not persisted."
    }

    [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo("zh-CN")
    [Globalization.CultureInfo]::CurrentUICulture = [Globalization.CultureInfo]::GetCultureInfo("zh-CN")
    $automaticHelp = (& $entry help -Language auto 6>&1 | Out-String -Width 4096)
    if ($automaticHelp -notmatch "Winenv 让 Windows") {
        throw "Automatic language selection did not follow the UI culture."
    }

    $localizedTable = (& $entry list -Language zh 6>&1 | Out-String -Width 4096)
    if ($localizedTable -notmatch "显示名称" -or $localizedTable -notmatch "PowerShell 7") {
        throw "Localized tabular output is incomplete."
    }

    $preview = (& $entry lang en -DryRun 6>&1 | Out-String -Width 4096)
    $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    if ($preview -notmatch "Language would be set to en-US" -or $config.language -ne "auto") {
        throw "The language dry run changed persisted state or omitted its preview."
    }
} finally {
    [Globalization.CultureInfo]::CurrentCulture = $previousCulture
    [Globalization.CultureInfo]::CurrentUICulture = $previousUICulture
    $env:LOCALAPPDATA = $previousLocalAppData
    $env:WINENV_LANG = $previousLanguage
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
