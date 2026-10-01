@echo off
rem Runs the SHIPWRIGHT spider boss test scene directly (pinned Godot version). Extra args: --phase2, --godmode, --show (boss roams without attacking)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/spider.tscn -- %*
