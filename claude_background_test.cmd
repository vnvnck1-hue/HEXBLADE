@echo off
rem Background first pass test scene (Claude version): F01/W01/A01/A02 in an 8x8m room (pinned Godot version).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/claude_background_first_pass.tscn
