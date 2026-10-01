@echo off
rem Runs the LAYER 01 abyss sanctum test scene directly (pinned Godot version). Extra args: --phase=N (1-6), --godmode, --nopost
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/abyss.tscn -- %*
