@echo off
rem Runs the SHIPWRIGHT spider boss test scene directly (pinned Godot version). Extra args: --phase2, --godmode, --show (boss roams without attacking)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/spider.tscn -- %*
