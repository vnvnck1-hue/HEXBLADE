@echo off
setlocal
set "G="
rem Project-local Godot 4.x (.tools\godot) first.
for %%E in ("%~dp0.tools\godot\Godot_v4*-stable_win64.exe") do set "G=%%~fE"
if not defined G for /d %%D in ("%~dp0..\*") do (
  if exist "%%~fD\.tools\godot\Godot_v4.6.3-stable_win64.exe" set "G=%%~fD\.tools\godot\Godot_v4.6.3-stable_win64.exe"
)
if not defined G exit /b 1
start "" "%G%" --path "%~dp0." --resolution 1440x1000 res://scenes/reference_mech_studio.tscn
