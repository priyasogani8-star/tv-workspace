@echo off
:: TV Workspace - Step 2: Install & Configure RDP Tools
:: Run this ONCE during first-time setup.
:: Auto-requests admin if needed.

NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    powershell -WindowStyle Hidden -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%~dp002-Setup.ps1"
