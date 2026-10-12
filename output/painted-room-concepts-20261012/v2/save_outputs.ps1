$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$taskSourceRoot = 'C:\Users\Loadcomplete\.codex\generated_images\01a12f45-9233-7e42-92c6-aff9d55cc531'
$taskItems = @(
    @{ file = '01_coral_workshop.png'; source = 'exec-f4596f61-3617-4760-95ed-45c3fe0b325e.png'; name = '코랄 작업실' },
    @{ file = '02_teal_cooling_bay.png'; source = 'exec-c8bd23d9-d7b6-41f1-ba31-18ca25bc5f4c.png'; name = '청록 냉각 설비실' },
    @{ file = '03_cream_service_dock.png'; source = 'exec-72f4a2d6-a34d-4873-bbf8-234a6e57a38a.png'; name = '크림 청소·정비 도크' }
)
Add-Type -AssemblyName System.Drawing
$taskResults = foreach ($taskItem in $taskItems) {
    $taskSource = Join-Path $taskSourceRoot $taskItem.source
    $taskDestination = Join-Path $taskRoot $taskItem.file
    if (Test-Path -LiteralPath $taskDestination) { throw "Destination exists: $taskDestination" }
    Copy-Item -LiteralPath $taskSource -Destination $taskDestination
    $taskHash = (Get-FileHash -LiteralPath $taskDestination -Algorithm SHA256).Hash
    if ($taskHash -ne (Get-FileHash -LiteralPath $taskSource -Algorithm SHA256).Hash) { throw 'Hash mismatch' }
    $taskDecoded = [System.Drawing.Image]::FromFile($taskDestination)
    $taskRow = [pscustomobject]@{ name = $taskItem.name; file = $taskItem.file; source = $taskSource; edit_target = (Join-Path (Split-Path $taskRoot -Parent) $taskItem.file); width = $taskDecoded.Width; height = $taskDecoded.Height; sha256 = $taskHash; decoded = $true; copy_hash_equal = $true }
    $taskDecoded.Dispose()
    $taskRow
}
$taskReport = [ordered]@{ date = '2026-10-12'; generator = 'built-in image_gen'; completed_count = $taskResults.Count; scope = 'Three redrawn concept paintings only; no runtime texture or model changes'; visual_review = 'PASS: broader brush-painted color planes, chunky bevels, simplified bolts and surface marks, more colorful purple/teal shadows; original room themes retained; no character or UI'; files = @($taskResults) }
$taskReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $taskRoot 'validation.json') -Encoding utf8
$taskResults | Format-Table name,width,height,copy_hash_equal
