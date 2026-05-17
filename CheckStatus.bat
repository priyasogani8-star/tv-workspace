@echo off
:: TV Workspace - Check Setup Status
:: Shows green/red for every requirement.
:: No admin needed.

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%~dp0CheckStatus.ps1"
