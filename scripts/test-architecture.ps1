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

    # Successful dispatch alone does not prove startup validation is useful.
    # These faults must be rejected before an invalid descriptor is usable.
    $registrationFaults = @(
        @{ Name = "unknown provider"; Pattern = "Unknown provider"; Run = {
            Register-WinenvProvider unknown @{ Install = "Invoke-WinGetProviderInstall" }
        } },
        @{ Name = "duplicate provider"; Pattern = "already registered"; Run = {
            Register-WinenvProvider winget @{ Install = "Invoke-WinGetProviderInstall" }
        } },
        @{ Name = "empty operations"; Pattern = "does not define any operations"; Run = {
            $WinenvProviderRegistry.Clear()
            Register-WinenvProvider winget ([ordered]@{})
        } },
        @{ Name = "unknown operation"; Pattern = "Unsupported provider operation"; Run = {
            $WinenvProviderRegistry.Clear()
            Register-WinenvProvider winget @{ Surprise = "Invoke-WinGetProviderInstall" }
        } },
        @{ Name = "missing handler"; Pattern = "handler is unavailable"; Run = {
            $WinenvProviderRegistry.Clear()
            Register-WinenvProvider winget @{ Install = "Invoke-AbsentWinenvTestHandler" }
        } },
        @{ Name = "owner mismatch"; Pattern = "does not match profile owners"; Run = {
            $AllowedOwners = @($AllowedOwners) + @("unimplemented")
            Initialize-WinenvProviders
        } }
    )
    foreach ($fault in $registrationFaults) {
        Initialize-WinenvProviders
        $message = ""
        try { & $fault.Run | Out-Null } catch { $message = $_.Exception.Message }
        if ($message -notmatch $fault.Pattern) {
            throw "Provider registration accepted $($fault.Name), or failed for the wrong reason: $message"
        }
    }
    Initialize-WinenvProviders

    # Exercise the registered handlers, not their current helper layout. Exact
    # native calls and failures must survive removal of pure forwarding layers.
    function Get-ResolvedManagerCommand { param([string]$Name) return "mock-$Name" }
    function Invoke-Native {
        param([string]$Command, [string[]]$Arguments)
        if ($script:FailNative) { throw "native-failure-sentinel" }
        $script:NativeCalls += [pscustomobject]@{ Command = $Command; Arguments = $Arguments }
        return "native-result-sentinel"
    }
    $installCases = @(
        @{ Owner = "winget"; Package = [pscustomobject]@{ id = "Test.App" }; Context = $null; Expected = @("install", "--id", "Test.App", "--exact", "--source", "winget", "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity") },
        @{ Owner = "winget"; Package = [pscustomobject]@{ id = "Test App"; source = "msstore" }; Context = [pscustomobject]@{ ProfileManagedMise = $true }; Expected = @("install", "--id", "Test App", "--exact", "--source", "msstore", "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity") },
        @{ Owner = "scoop"; Package = [pscustomobject]@{ id = "test-app" }; Context = $null; Expected = @("install", "test-app") },
        @{ Owner = "scoop"; Package = [pscustomobject]@{ id = "test-app"; bucket = "extras" }; Context = [pscustomobject]@{ ProfileManagedMise = $true }; Expected = @("install", "extras/test-app") },
        @{ Owner = "mise"; Package = [pscustomobject]@{ id = "node"; version = "26" }; Context = [pscustomobject]@{ ProfileManagedMise = $true }; Expected = @("install", "node@26") },
        @{ Owner = "mise"; Package = [pscustomobject]@{ id = "node"; version = "26" }; Context = [pscustomobject]@{ ProfileManagedMise = $false }; Expected = @("use", "--global", "node@26") },
        @{ Owner = "mise"; Package = [pscustomobject]@{ id = "node" }; Context = $null; Expected = @("use", "--global", "node@latest") }
    )
    foreach ($case in $installCases) {
        $script:NativeCalls = @()
        $script:FailNative = $false
        $output = @(Invoke-WinenvProviderOperation $case.Owner "Install" @($case.Package, $case.Context))
        if ($output.Count -ne 1 -or $output[0] -ne "native-result-sentinel" -or
            $script:NativeCalls.Count -ne 1 -or $script:NativeCalls[0].Command -ne "mock-$($case.Owner)" -or
            ($script:NativeCalls[0].Arguments | ConvertTo-Json -Compress) -cne ($case.Expected | ConvertTo-Json -Compress)) {
            throw "Provider '$($case.Owner)' changed the native command, arguments, invocation count, or returned result."
        }
    }
    foreach ($owner in @("winget", "scoop")) {
        $script:FailNative = $true
        $message = ""
        try { Invoke-WinenvProviderOperation $owner "Install" @([pscustomobject]@{ id = "Test.App" }, $null) | Out-Null }
        catch { $message = $_.Exception.Message }
        if ($message -ne "native-failure-sentinel") { throw "Provider '$owner' did not propagate the native failure." }
    }
    $script:FailNative = $false

    # Composition may revisit the same override while resolving conflicts. It
    # must not leak computed ownership fields into the source profile/snapshot.
    $package = [pscustomobject]@{ key = "sample"; displayName = "Sample"; owner = "winget"; id = "Test.Sample"; source = "winget"; profiles = @("default"); commands = @("sample") }
    $profile = [pscustomobject]@{ schemaVersion = 1; name = "sample"; defaultProfiles = @("default"); scoopBuckets = @(); packages = @($package) }
    $config = [pscustomobject]@{ profiles = @([pscustomobject]@{ id = "sample"; name = "sample"; enabled = $true }); resolutions = @() }
    $before = $profile | ConvertTo-Json -Depth 20 -Compress
    $first = Resolve-ProfileDefinitions $config @{ sample = $profile }
    $second = Resolve-ProfileDefinitions $config @{ sample = $profile }
    if (($profile | ConvertTo-Json -Depth 20 -Compress) -cne $before -or
        ($first | ConvertTo-Json -Depth 20 -Compress) -cne ($second | ConvertTo-Json -Depth 20 -Compress)) {
        throw "Repeated profile composition mutated its input or changed its result."
    }
} finally {
    $env:LOCALAPPDATA = $previousLocalAppData
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}

Write-Host "Internal architecture checks passed." -ForegroundColor Green
