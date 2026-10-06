@echo off
cd /d "%~dp0..\..\"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File tools\blender.ps1 wait "output\models\tutorial_alien_b\tutorial_alien_b_toon_studio.blend"
if errorlevel 1 pause
