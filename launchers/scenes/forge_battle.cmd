@echo off
rem Runs the VULCAN forge boss battle directly (pinned Godot version).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" run res://scenes/forge.tscn
