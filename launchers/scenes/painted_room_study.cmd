@echo off
set "ROOT=%~dp0..\..\"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tools\godot.ps1" run res://scenes/painted_room_study.tscn
