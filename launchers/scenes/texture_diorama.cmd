@echo off
rem Texture diorama: real game props, wall and floor materials.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" run res://scenes/texture_diorama.tscn %*
