param([Parameter(Mandatory = $true)][string]$Godot, [string]$ReleaseTemplate)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('goap-export-tests-' + [guid]::NewGuid().ToString('N'))
$buildRoot = Join-Path $testRoot 'source'
$runRoot = Join-Path $testRoot 'runtime'
$utf8 = [Text.UTF8Encoding]::new($false)

function Invoke-GodotChecked([string[]]$Arguments, [string]$Log, [string]$Expected, [string]$Executable = $Godot) {
    # GUI release templates do not reliably expose stdout to PowerShell.
    # Wait explicitly and verify the engine log as well as the process exit code.
    $nativeArguments = @('--log-file', $Log) + $Arguments
    $quotedArguments = $nativeArguments | ForEach-Object { '"' + $_.Replace('"', '\"') + '"' }
    $process = Start-Process -FilePath $Executable -ArgumentList $quotedArguments -WorkingDirectory $runRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput "$Log.stdout" -RedirectStandardError "$Log.stderr"
    $code = $process.ExitCode
    $output = ''
    foreach ($part in @($Log, "$Log.stdout", "$Log.stderr")) {
        if (Test-Path -LiteralPath $part) { $output += [IO.File]::ReadAllText($part) }
    }
    $checkedOutput = $output
    if (($Arguments -contains '--export-pack') -or ($Arguments -contains '--export-release')) {
        # Godot's headless resource exporter reports renderer RIDs at shutdown.
        # Restrict this exception to that exact exporter diagnostic; runtime is strict.
        $checkedOutput = $output -replace '(?m)^ERROR: \d+ RID allocations of type .* were leaked at exit\.\r?$', ''
    }
    if ($null -eq $code -or $code -ne 0 -or $checkedOutput -match '(SCRIPT ERROR:|ERROR:)' -or ($Expected -and ([string]::IsNullOrWhiteSpace($output) -or $output -notmatch $Expected))) {
        Write-Output $output
        throw "Godot export check failed (exit $code): $Log"
    }
    if ($Expected) { Write-Output ($output -split "`n" | Where-Object { $_ -match $Expected } | ForEach-Object { $_.Trim() } | Select-Object -Unique) }
}

New-Item -ItemType Directory -Path $buildRoot, $runRoot | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $projectRoot 'addons') -Destination $buildRoot -Recurse
    New-Item -ItemType Directory -Path (Join-Path $buildRoot 'tests') | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'export_fixture') -Destination (Join-Path $buildRoot 'tests/export_fixture') -Recurse
    $project = @'
config_version=5
[application]
config/name="GOAP export smoke"
run/main_scene="res://tests/export_fixture/main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
[autoload]
GoapInspector="*res://addons/goap/debugger/goap_debugger_autoload.gd"
[editor_plugins]
enabled=PackedStringArray("res://addons/goap/plugin.cfg")
[rendering]
renderer/rendering_method="gl_compatibility"
[debug]
file_logging/enable_file_logging=true
'@
    [IO.File]::WriteAllText((Join-Path $buildRoot 'project.godot'), $project, $utf8)
    Invoke-GodotChecked @('--headless', '--editor', '--path', $buildRoot, '--import', '--quit') (Join-Path $testRoot 'import.log') ''
    foreach ($mode in @(0, 2)) {
        $preset = @"
[preset.0]
name="Smoke"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
script_export_mode=$mode
[preset.0.options]
binary_format/architecture="x86_64"
"@
        [IO.File]::WriteAllText((Join-Path $buildRoot 'export_presets.cfg'), $preset, $utf8)
        $pack = Join-Path $runRoot "mode-$mode.pck"
        Invoke-GodotChecked @('--headless', '--editor', '--path', $buildRoot, '--export-pack', 'Smoke', $pack) (Join-Path $testRoot "export-$mode.log") ''
        if ($ReleaseTemplate) {
            $templatePath = [IO.Path]::GetFullPath($ReleaseTemplate).Replace('\', '/')
            $preset += "`ncustom_template/release=`"$templatePath`"`n"
            [IO.File]::WriteAllText((Join-Path $buildRoot 'export_presets.cfg'), $preset, $utf8)
            Invoke-GodotChecked @('--headless', '--editor', '--path', $buildRoot, '--export-release', 'Smoke', (Join-Path $runRoot "release-$mode.exe")) (Join-Path $testRoot "release-export-$mode.log") ''
        }
    }
    # Remove source/cache visibility before executing either pack.
    $hiddenSource = Join-Path $testRoot 'hidden-source'
    $resolvedBuild = (Resolve-Path -LiteralPath $buildRoot).Path
    if ($resolvedBuild -ne [IO.Path]::GetFullPath((Join-Path $testRoot 'source')) -or
        -not $resolvedBuild.StartsWith([IO.Path]::GetFullPath($testRoot) + [IO.Path]::DirectorySeparatorChar)) {
        throw 'Refusing to move an unexpected source directory.'
    }
    Move-Item -LiteralPath $resolvedBuild -Destination $hiddenSource
    foreach ($mode in @(0, 2)) {
        $arguments = @('--headless', '--path', $runRoot, '--main-pack', (Join-Path $runRoot "mode-$mode.pck"), '--max-fps', '120')
        if ($mode -eq 2) { $arguments += @('--', '--binary') }
        Invoke-GodotChecked $arguments (Join-Path $testRoot "run-$mode.log") 'GOAP export smoke: \d+ checks, 0 failures'
        if ($ReleaseTemplate) {
            $reportPath = Join-Path $runRoot "release-report-$mode.json"
            $releaseArguments = @('--headless', '--max-fps', '120', '--', '--standalone', "--report=$reportPath")
            if ($mode -eq 2) { $releaseArguments += '--binary' }
            Invoke-GodotChecked $releaseArguments (Join-Path $testRoot "release-run-$mode.log") '' (Join-Path $runRoot "release-$mode.exe")
            $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
            if (-not $report.completed -or -not $report.template -or $report.checks -ne 10 -or $report.failures -ne 0) {
                throw "Standalone release mode $mode failed: $($report | ConvertTo-Json -Compress)"
            }
            Write-Output "GOAP standalone release (mode $mode): 10 checks, 0 failures"
        }
    }
} finally {
    $resolved = (Resolve-Path -LiteralPath $testRoot).Path
    if ($resolved -ne [IO.Path]::GetFullPath($testRoot) -or (Split-Path -Leaf $resolved) -notmatch '^goap-export-tests-[a-f0-9]{32}$') {
        throw 'Refusing to clean an unexpected test directory.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
