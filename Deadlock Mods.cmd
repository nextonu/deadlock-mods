@echo off
rem Starts the app (PowerShell + Windows Forms, nothing to install).
cd /d "%~dp0"
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse | Unblock-File" >nul 2>&1
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0DeadlockModToggle.ps1"