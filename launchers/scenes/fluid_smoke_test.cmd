@echo off
rem Runs the Navier-Stokes fluid smoke test scene directly (pinned Godot version).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" run res://scenes/fluid_smoke.tscn
