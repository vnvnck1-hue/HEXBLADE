@echo off
rem Codex-only background studio. No changes to main game or Claude assets.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/codex_background_first_pass.tscn %*
