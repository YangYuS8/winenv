$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root "win.ps1"
$sourceRoot = Join-Path $root "src"

Write-Host "Checking internal module and provider contracts..."

$entryTokens = $null
$entryErrors = $null
$entryAst = [Management.Automation.Language.Parser]::ParseFile($entry, [ref]$entryTokens, [ref]$entryErrors)
if ($entryErrors.Count -gt 0) { throw "The Winenv entry script has parser errors." }
$entryFunctions = @($entryAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst]
}, $true))
if ($entryFunctions.Count -ne 0) {
    throw "win.ps1 must remain a thin entry point without function implementations."
}

$sourceFiles = @(Get-ChildItem -Path $sourceRoot -Filter "*.ps1" -File -Recurse)
$functionOwners = @{}
foreach ($sourceFile in $sourceFiles) {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($sourceFile.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Module has parser errors: $($sourceFile.FullName)" }
    foreach ($function in $ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst]
    }, $true)) {
        if ($functionOwners.ContainsKey($function.Name)) {
            throw "Internal function '$($function.Name)' is defined in both $($functionOwners[$function.Name]) and $($sourceFile.FullName)."
        }
        $functionOwners[$function.Name] = $sourceFile.FullName
    }
}
if ($functionOwners.Count -lt 140) { throw "The module inventory is unexpectedly incomplete." }

$previousLocalAppData = $env:LOCALAPPDATA
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("winenv-architecture-" + [Guid]::NewGuid().ToString("N"))
try {
    $env:LOCALAPPDATA = $testRoot
    . $entry version | Out-Null

    $loaded = @($WinenvModulePaths | ForEach-Object { $_.Replace("/", [IO.Path]::DirectorySeparatorChar) } | Sort-Object)
    $discovered = @($sourceFiles | ForEach-Object {
        $_.FullName.Substring($root.Length + 1)
    } | Sort-Object)
    if (($loaded -join "|") -ne ($discovered -join "|")) {
        throw "The entry point does not load every internal module exactly once."
    }

    $expected = [ordered]@{
        winget = @("Search", "Install", "Remove")
        scoop = @("Search", "Install", "Remove")
        mise = @("Search", "Install", "Remove")
        vendor = @("Install", "Remove")
    }
    foreach ($providerName in $expected.Keys) {
        $provider = Get-WinenvProvider $providerName
        foreach ($operation in $expected[$providerName]) {
            if (-not $provider.Operations.Contains($operation)) {
                throw "Provider '$providerName' is missing '$operation'."
            }
        }
    }

    $script:SearchDispatch = ""
    function Get-WinGetCandidates { param([string]$Query) $script:SearchDispatch = $Query }
    Invoke-WinenvProviderOperation "winget" "Search" @("ripgrep") | Out-Null
    if ($script:SearchDispatch -ne "ripgrep") { throw "Provider search dispatch did not invoke the registered handler." }

    $unsupported = ""
    try { Invoke-WinenvProviderOperation "vendor" "Search" @("anything") } catch { $unsupported = $_.Exception.Message }
    if ($unsupported -notmatch "does not support operation") {
        throw "Unsupported provider operations do not fail through the contract."
    }
} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host "Internal architecture checks passed." -ForegroundColor Green
