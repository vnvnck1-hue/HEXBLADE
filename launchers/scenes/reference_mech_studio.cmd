@echo off
rem Opens the reference mech studio scene (pinned Godot version).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" run --resolution 1440x1000 res://scenes/reference_mech_studio.tscn
