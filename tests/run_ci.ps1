param([Parameter(Mandatory = $true)][string]$Godot)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$tests = @(
    'run_tests',
    'world_state_providers',
    'lifecycle_reentrancy',
    'budgeted_planning',
    'planning_safety',
    'diagnostics',
    'runtime_monitor',
    'target_stability',
    'camp_hauling',
    'fire_haul_interrupt',
    'physical_pickups',
    'single_carry_workbench',
    'stow_supplies',
    'warehouse_goal',
    'survival_structure',
    'camp_replenishment',
    'example_smoke'
)

Push-Location $projectRoot
try {
    & $Godot --headless --editor --path . --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }

    foreach ($test in $tests) {
        $arguments = @('--headless', '--path', '.')
        if ($test -in @('example_smoke', 'camp_hauling', 'fire_haul_interrupt', 'physical_pickups', 'single_carry_workbench', 'stow_supplies', 'warehouse_goal', 'survival_structure', 'camp_replenishment')) { $arguments += @('--fixed-fps', '60') }
        $arguments += @('--script', "tests/$test.gd")
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = & $Godot @arguments 2>&1 | Out-String
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $savedPreference
        }
        if ($code -ne 0 -or $output -match '(SCRIPT ERROR:|ERROR:)' -or $output -notmatch '\d+ checks, 0 failures') {
            Write-Output $output
            throw "Failed: $test"
        }
        Write-Output "$test passed"
    }
} finally {
    Pop-Location
}
