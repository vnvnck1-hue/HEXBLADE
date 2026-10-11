@echo off
rem Runs the first field cleaning partner introduction with the pinned Godot.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" run res://scenes/partner_dialogue.tscn -- %*
