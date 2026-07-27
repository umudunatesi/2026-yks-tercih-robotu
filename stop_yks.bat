@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop_yks.ps1"
if errorlevel 1 pause
