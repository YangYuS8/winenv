# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function Register-WinenvProvider {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Operations
    )

    if ($AllowedOwners -notcontains $Name) { throw "Unknown provider: $Name" }
    if ($WinenvProviderRegistry.Contains($Name)) { throw "Provider already registered: $Name" }
    if ($Operations.Count -eq 0) { throw "Provider does not define any operations: $Name" }

    $normalized = [ordered]@{}
    foreach ($operation in $Operations.GetEnumerator()) {
        $operationName = [string]$operation.Key
        $handlerName = [string]$operation.Value
        if ($operationName -notin @("Search", "Install", "Remove")) {
            throw "Unsupported provider operation '$operationName' for '$Name'."
        }
        $handler = Get-Command $handlerName -CommandType Function -ErrorAction SilentlyContinue
        if ($null -eq $handler) { throw "Provider handler is unavailable: $handlerName" }
        $normalized[$operationName] = $handlerName
    }

    $WinenvProviderRegistry[$Name] = [pscustomobject]@{
        Name = $Name
        Operations = $normalized
    }
}

function Initialize-WinenvProviders {
    $WinenvProviderRegistry.Clear()
    Register-WinenvProvider "winget" ([ordered]@{
        Search = "Get-WinGetCandidates"
        Install = "Invoke-WinGetProviderInstall"
        Remove = "Invoke-WinGetProviderRemove"
    })
    Register-WinenvProvider "scoop" ([ordered]@{
        Search = "Get-ScoopCandidates"
        Install = "Invoke-ScoopProviderInstall"
        Remove = "Invoke-ScoopProviderRemove"
    })
    Register-WinenvProvider "mise" ([ordered]@{
        Search = "Get-MiseCandidates"
        Install = "Invoke-MiseProviderInstall"
        Remove = "Invoke-MiseProviderRemove"
    })
    Register-WinenvProvider "vendor" ([ordered]@{
        Install = "Invoke-VendorProviderInstall"
        Remove = "Invoke-VendorProviderRemove"
    })

    $missing = @($AllowedOwners | Where-Object { -not $WinenvProviderRegistry.Contains($_) })
    $extra = @($WinenvProviderRegistry.Keys | Where-Object { $AllowedOwners -notcontains $_ })
    if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        throw "Provider registry does not match profile owners: missing=$($missing -join ','); extra=$($extra -join ',')"
    }
}

function Get-WinenvProvider {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Operation
    )

    if (-not $WinenvProviderRegistry.Contains($Name)) { throw "Unknown provider: $Name" }
    $provider = $WinenvProviderRegistry[$Name]
    if (-not [string]::IsNullOrWhiteSpace($Operation) -and -not $provider.Operations.Contains($Operation)) {
        throw "Provider '$Name' does not support operation '$Operation'."
    }
    return $provider
}

function Get-WinenvProviderNames {
    param([string]$Operation)
    return @($WinenvProviderRegistry.Keys | Where-Object {
        [string]::IsNullOrWhiteSpace($Operation) -or $WinenvProviderRegistry[$_].Operations.Contains($Operation)
    })
}

function Invoke-WinenvProviderOperation {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Operation,
        [object[]]$Arguments = @()
    )

    $provider = Get-WinenvProvider $Name $Operation
    $handlerName = [string]$provider.Operations[$Operation]
    return & $handlerName @Arguments
}
