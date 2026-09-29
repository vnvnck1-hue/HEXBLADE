@echo off
rem Finds Godot 4.6.3 in a sibling folder's .tools\godot and runs this project.
setlocal
set "G="
for /d %%D in ("%~dp0..\*") do (
  if exist "%%~fD\.tools\godot\Godot_v4.6.3-stable_win64.exe" set "G=%%~fD\.tools\godot\Godot_v4.6.3-stable_win64.exe"
)
if not defined G (
  echo Godot 4.6.3 not found. Open project.godot with Godot 4.6 or newer.
  pause
  exit /b 1
)
if /i "%~1"=="editor" (
  start "" "%G%" --editor --path "%~dp0."
) else (
  start "" "%G%" --path "%~dp0."
)
