@echo off
rem Runs the bug test scene with only the CHOMPER (tutorial space bug). Key 4 = animation gallery, 7 = spawn chomper.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" run res://scenes/bugs.tscn -- --only=chomp
