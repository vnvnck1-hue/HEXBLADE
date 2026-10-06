@echo off
rem Runs the owner and mechanic introduction dialogue with the pinned Godot.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" run res://scenes/coworker_dialogue.tscn -- %*
