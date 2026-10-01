# Runs every tests\*.gd headless with the pinned Godot and prints a summary. Exit code 1 if any test fails.
#   tools\run_tests.ps1 [name ...]     e.g. tools\run_tests.ps1 ammo_check room_wave_check

$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $PSScriptRoot 'godot.ps1'
& $godot setup
if ($LASTEXITCODE -ne 0) { exit 1 }

$tests = Get-ChildItem -LiteralPath (Join-Path $root 'tests') -Filter '*.gd' | Sort-Object Name
$names = @($args)   # inside Where-Object { } $args is the block's own (empty) list, so keep the script's here
if ($names.Count -gt 0) { $tests = $tests | Where-Object { $names -contains $_.BaseName } }

$failed = @()
foreach ($t in $tests) {
	Write-Host "=== $($t.BaseName)" -ForegroundColor Cyan
	$out = & $godot wait --headless -s "res://tests/$($t.Name)" 2>&1 | ForEach-Object { "$_" }
	$code = $LASTEXITCODE
	$out | Where-Object { $_ -match 'FAIL|ERROR|RESULT|_OK|_FAILED|CHECK' } | ForEach-Object { Write-Host "  $_" }
	if ($code -ne 0 -or ($out | Where-Object { $_ -match '^\s*FAIL\b|SCRIPT ERROR' })) { $failed += $t.BaseName }
}

Write-Host ''
if ($failed.Count -gt 0) {
	Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
	exit 1
}
Write-Host "ALL $(@($tests).Count) TESTS PASSED" -ForegroundColor Green
exit 0
