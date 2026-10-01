@echo off
rem Runs the hex sector run directly, skipping the lobby (pinned Godot version).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/run.tscn
