@echo off
setlocal
title OnePlus USB Mirror

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Start-PhoneMirror.ps1"
set "MIRROR_EXIT_CODE=%ERRORLEVEL%"

if not "%MIRROR_EXIT_CODE%"=="0" (
    echo.
    echo The phone mirror could not start. Review the message above, then try again.
    pause
)

exit /b %MIRROR_EXIT_CODE%
