@echo off
rem Runs the field gimmick test scene (smoke, rail, gas canister, repair hatch) directly (pinned Godot version).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" run res://scenes/gimmicks.tscn
