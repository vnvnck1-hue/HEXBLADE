@echo off
rem Opens the reference mech studio scene (pinned Godot version).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run --resolution 1440x1000 res://scenes/reference_mech_studio.tscn
