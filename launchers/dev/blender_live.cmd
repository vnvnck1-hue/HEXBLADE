@echo off
rem Opens the pinned Blender with the live bridge, so an agent can model in this window (tools\blender.ps1 send).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\blender.ps1" live %*
