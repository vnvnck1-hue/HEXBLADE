@echo off
rem Installs the pinned Blender version (blender-version.txt) into .tools\blender. Run once on a new PC.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\blender.ps1" setup
pause
