@echo off
rem Runs the VULCAN forge boss battle directly (pinned Godot version).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/forge.tscn
