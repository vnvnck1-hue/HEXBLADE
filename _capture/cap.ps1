param([string]$name = "cap1", [string]$extra = "--bot", [int]$every = 30, [int]$seconds = 24, [int]$start = 0, [int]$step = 4)
$p = Split-Path $PSScriptRoot -Parent
$c = $PSScriptRoot
$out = Join-Path $c $name
if (Test-Path $out) { Get-ChildItem $out -Filter "f_*.png" | Remove-Item -Force }
New-Item -ItemType Directory -Force $out | Out-Null
$g = (Get-ChildItem "C:\Users\Loadcomplete\Documents\ChatGPT\*\.tools\godot\Godot_v4.6.3-stable_win64_console.exe" | Select-Object -First 1).FullName
$d = $out -replace '\\', '/'
& $g --path $p --fixed-fps 60 -- "--capture=$d" "--every=$every" "--seconds=$seconds" ($extra -split " ") 2>&1 | Out-File -Encoding utf8 (Join-Path $c "$name.log")
Set-Location $c
python sheet.py $name "$name-sheet.png" $start $step
Select-String -Path (Join-Path $c "$name.log") -Pattern "ERROR|WARNING|SCRIPT" | Select-Object -First 20 | ForEach-Object { $_.Line }
