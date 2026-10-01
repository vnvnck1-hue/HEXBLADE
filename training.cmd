@echo off
rem Runs the combat training scene with dummies directly (pinned Godot version).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\godot.ps1" run res://scenes/training.tscn
