# Internal Winenv implementation. Dot-sourced by win.ps1; not a public API.

function Read-State {
    if (-not (Test-Path $StatePath)) {
        return @{ appliedMigrations = @() }
    }
    $state = Get-Content -Raw -Encoding UTF8 -Path $StatePath | ConvertFrom-Json
    return @{ appliedMigrations = @($state.appliedMigrations) }
}

function Write-State {
    param($State)
    if ($DryRun) { return }
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    $State | ConvertTo-Json -Depth 5 | Set-Content -Path $StatePath -Encoding UTF8
}

function Invoke-Migrations {
    Write-Step "Running pending migrations"
    if (-not (Test-Path $MigrationPath)) { return }

    $state = Read-State
    $applied = @($state.appliedMigrations)
    $migrations = @(Get-ChildItem -Path $MigrationPath -Filter "*.ps1" -File | Sort-Object Name)

    foreach ($migration in $migrations) {
        if ($applied -contains $migration.Name) { continue }
        Write-Plan "Run migration $($migration.Name)"
        if ($DryRun) { continue }

        & $migration.FullName
        $applied += $migration.Name
        $state.appliedMigrations = @($applied)
        Write-State $state
    }
}
