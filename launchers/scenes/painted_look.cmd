@echo off
rem Hand-painted look comparison viewer (keys 1-8 switch look, 7-8 = Hearthstone style, Space stop turntable, C close-up).
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\..\tools\godot.ps1" run -s _capture/painted_look_show.gd
