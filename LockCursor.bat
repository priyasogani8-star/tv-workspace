@echo off
:: Lock cursor to laptop screen - close this window to unlock
powershell.exe -ExecutionPolicy Bypass -File "%~dp0LockCursor.ps1"
