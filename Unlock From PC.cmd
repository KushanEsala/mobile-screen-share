@echo off
setlocal
title Android Secure PIN Entry

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Enter-SecurePin.ps1"
exit /b %ERRORLEVEL%
