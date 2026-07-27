@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0restore_latest_backup.ps1"
pause
