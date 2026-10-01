@echo off
rem Runs every tests\*.gd headless with the pinned Godot version.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_tests.ps1" %*
pause
