@echo off
rem Runs every tests\*.gd headless with the pinned Godot version.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run_tests.ps1" %*
pause
