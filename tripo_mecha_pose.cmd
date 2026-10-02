@echo off
cd /d "%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\blender.ps1" live "%~dp0output\models\tripo_mecha_proto\pose_trial.blend"
if errorlevel 1 pause
