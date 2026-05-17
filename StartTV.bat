@echo off
:: TV Workspace Launcher - Double-click to start
:: Auto-requests admin if needed, no extra windows

NET SESSION >nul 2>&1
IF %ERRORLEVEL% NEQ 0 (
    powershell -WindowStyle Hidden -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%~dp0StartTV.ps1"
