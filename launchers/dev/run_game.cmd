@echo off
rem Starts the game (lobby) with the pinned Godot version in godot-version.txt. "run_game.cmd editor" opens the editor.
if /i "%~1"=="editor" ("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" editor) else ("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" run)
