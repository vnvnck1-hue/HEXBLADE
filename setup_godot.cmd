@echo off
rem Installs the pinned Godot version (godot-version.txt) into .tools\godot. Run once on a new PC.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" setup
pause
