@echo off
rem Rebuilds HEXBLADE.exe (project root) from HexbladeLauncher.cs with the icon hexblade.ico.
rem Uses the .NET Framework compiler that ships with Windows. Icon: python tools\launcher\make_icon.py
"%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /optimize+ /codepage:65001 /win32icon:"%~dp0hexblade.ico" /reference:System.Windows.Forms.dll /reference:System.Core.dll /out:"%~dp0..\..\HEXBLADE.exe" "%~dp0HexbladeLauncher.cs"
if errorlevel 1 pause
