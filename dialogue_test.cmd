@echo off
rem Runs the character dialogue test scene directly (pinned Godot version). Extra args: --script=feature_demo, --bot
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/dialogue.tscn -- %*
