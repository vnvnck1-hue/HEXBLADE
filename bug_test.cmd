@echo off
rem Runs the bug-creature test scene (ant soldier / pill bug, key 4 = animation gallery) with the pinned Godot version.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/bugs.tscn
