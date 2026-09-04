$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$entry = Join-Path $root "win.ps1"
$resource = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $root "locales\zh-CN.json") | ConvertFrom-Json
$runtimeFiles = @(
    Get-Item -LiteralPath $entry
    Get-ChildItem -Path (Join-Path $root "src") -Filter "*.ps1" -File -Recurse
)
$asts = @(foreach ($runtimeFile in $runtimeFiles) {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($runtimeFile.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) { throw "Cannot inspect localization coverage because $($runtimeFile.FullName) has parser errors." }
    $ast
})

function ConvertTo-TestLocalization {
    param([string]$Text)
    $property = $resource.exact.psobject.Properties[$Text]
    if ($null -ne $property) { return [string]$property.Value }
    $localized = $Text
    foreach ($rule in @($resource.patterns)) {
        $localized = [regex]::Replace($localized, [string]$rule.pattern, [string]$rule.replacement)
    }
    foreach ($rule in @($resource.replacements)) {
        $localized = $localized.Replace([string]$rule.source, [string]$rule.target)
    }
    return $localized
}

$messages = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$localizedCommands = @("Write-WinenvHost", "Write-Step", "Write-Plan", "Read-WinenvHost", "Confirm-Operation")
$commandAsts = @($asts | ForEach-Object {
    $_.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in $localizedCommands
    }, $true)
})
foreach ($commandAst in $commandAsts) {
    if ($commandAst.CommandElements.Count -lt 2) { continue }
    $element = $commandAst.CommandElements[1]
    $stringAsts = @($element.FindAll({
        param($node)
        $node -is [Management.Automation.Language.StringConstantExpressionAst] -or
        $node -is [Management.Automation.Language.ExpandableStringExpressionAst]
    }, $true))
    if ($stringAsts.Count -eq 0 -and
        ($element -is [Management.Automation.Language.StringConstantExpressionAst] -or
         $element -is [Management.Automation.Language.ExpandableStringExpressionAst])) {
        $stringAsts = @($element)
    }
    foreach ($stringAst in $stringAsts) {
        if ($stringAst.Extent.Text.TrimStart() -notmatch '^(?:@?["''])') { continue }
        [void]$messages.Add([string]$stringAst.Value)
    }
}

foreach ($throwAst in @($asts | ForEach-Object {
    $_.FindAll({ param($node) $node -is [Management.Automation.Language.ThrowStatementAst] }, $true)
})) {
    $elements = @($throwAst.Pipeline.PipelineElements)
    if ($elements.Count -ne 1) { continue }
    $expression = $elements[0].Expression
    if ($expression -is [Management.Automation.Language.StringConstantExpressionAst] -or
        $expression -is [Management.Automation.Language.ExpandableStringExpressionAst]) {
        [void]$messages.Add([string]$expression.Value)
    }
}

$ignored = @(
    "",
    "English",
    "WinGet",
    "Scoop",
    "mise",
    "PowerShell 7",
    "fzf",
    "action",
    "location",
    "manager",
    "name",
    "path",
    "requirement",
    "status",
    "version"
)
$untranslated = @($messages | Where-Object {
    $candidate = $_.TrimStart()
    $_ -notin $ignored -and
    $_ -match "[A-Za-z]" -and
    $candidate -notmatch "^(?:\$|==>)" -and
    $candidate -notmatch "^Winenv keeps Windows software simple" -and
    (ConvertTo-TestLocalization $_) -eq $_
} | Sort-Object)

if ($untranslated.Count -gt 0) {
    throw "Static user-facing messages without a Simplified Chinese rule:`n - $($untranslated -join "`n - ")"
}

Write-Host "Validated Simplified Chinese coverage for $($messages.Count) static CLI messages."
