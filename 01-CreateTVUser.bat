@echo off
:: TV Workspace - Step 1: Create TV User Account
:: Run this ONCE during first-time setup.
:: Auto-requests admin if needed.

NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    powershell -WindowStyle Hidden -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%~dp001-CreateTVUser.ps1"
