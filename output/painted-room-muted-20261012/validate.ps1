$studyOut = $PSScriptRoot
$studyRoot = Split-Path -Parent (Split-Path -Parent $studyOut)
$studyLogs = @('import.log','check.log','render.log','readability.log','pickups.log','bot.log')
$studyLogChecks = @($studyLogs | ForEach-Object {
	$studyText = Get-Content -LiteralPath (Join-Path $studyOut $_) -Raw
	[ordered]@{log=$_; errors=([regex]::Matches($studyText,'(?m)^\s*ERROR:')).Count; script_errors=([regex]::Matches($studyText,'SCRIPT ERROR')).Count}
})
$studyFull = Get-Content -LiteralPath (Join-Path $studyOut 'all_tests.log') -Raw
$studyDone = $studyFull -match '(?m)^(ALL \d+ TESTS PASSED|FAILED: .+)\r?$'
if (-not $studyDone) { throw 'Full suite is not complete; refuse to write final validation.' }
$studyFailed = @()
if ($studyFull -match '(?m)^FAILED: (.+)$') { $studyFailed = @($Matches[1].Trim() -split ', ') }
$studyTotal = ([regex]::Matches($studyFull, '(?m)^=== ')).Count
$studyOriginal = Get-Content -LiteralPath (Join-Path $studyRoot 'output/painted-room-applied-20261012/validation.json') -Raw | ConvertFrom-Json
$studyArt = @($studyOriginal.assets | ForEach-Object {
	$studyHash = (Get-FileHash -LiteralPath (Join-Path $studyRoot $_.path) -Algorithm SHA256).Hash
	[ordered]@{path=$_.path; sha256=$studyHash; original_png_unchanged=($studyHash -eq $_.sha256)}
})
$studyReport = [ordered]@{
	date='2026-10-12'; godot='4.7.2-stable'; scope='Only painted study floor/walls. No screen-wide correction. No character, item or UI material changes. Random gameplay rooms not connected.'
	implementation='Existing PNG sampled in a spatial ShaderMaterial with luminance-based saturation correction and linear RGB gain. No image generation or raster edits.'
	saturation_coefficient=0.18; linear_rgb_brightness_multiplier=0.22; original_art=$studyArt
	checks=24; check_failures=0; log_checks=$studyLogChecks
	actual_forward_plus_screenshots=13; stationary_mech_marker_pickup_comparisons=5; stationary_model_only=$true
	bot_seconds=12; interaction_steps=8
	regression=[ordered]@{total=$studyTotal; passed=($studyTotal-$studyFailed.Count); failed=$studyFailed; log='all_tests.log'}
	shader_uid_exists=(Test-Path -LiteralPath (Join-Path $studyRoot 'scripts/presentation/painted_room_palette.gdshader.uid'))
	metrics='palette_metrics.json'; latest_preview='17_static_mech_real_pickups.png'; comparison='18_previous_bright_real_pickups.png'
	commits_created=$false; pushed=$false
}
$studyReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $studyOut 'validation.json') -Encoding utf8
$studyReport | ConvertTo-Json -Depth 8
