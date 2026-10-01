@echo off
rem Starts the game (lobby) with the pinned Godot version in godot-version.txt. "run_game.cmd editor" opens the editor.
if /i "%~1"=="editor" (powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" editor) else (powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run)
