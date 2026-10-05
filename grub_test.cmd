@echo off
rem Runs the bug test scene with only the GRUB (basic caterpillar monster). Key 4 = animation gallery, 8 = spawn grub.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/bugs.tscn -- --only=grub
