@echo off
rem Runs only the B storyboard preview room. Does not start a combat run.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/mammoth_death_lab.tscn
