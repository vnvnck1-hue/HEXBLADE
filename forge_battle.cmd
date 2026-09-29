@echo off
rem Runs the forge (furnace) boss battle scene directly (Godot 4.6.3 in a sibling folder's .tools\godot).
setlocal
set "G="
for /d %%D in ("%~dp0..\*") do (
  if exist "%%~fD\.tools\godot\Godot_v4.6.3-stable_win64.exe" set "G=%%~fD\.tools\godot\Godot_v4.6.3-stable_win64.exe"
)
rem Fallback: Godot 4.x installed via winget.
if not defined G (
  for /d %%P in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine*") do (
    for %%E in ("%%~fP\Godot_v4*-stable_win64.exe") do set "G=%%~fE"
  )
)
if not defined G (
  echo Godot 4.6.3 not found. Open project.godot with Godot 4.6 or newer.
  pause
  exit /b 1
)
start "" "%G%" --path "%~dp0." res://scenes/forge.tscn
