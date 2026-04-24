@echo off
setlocal

cd /d "%~dp0"

echo Uninstalling Win11 Left-Handed Cursor Sync...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-mouse-cursor-sync.ps1" -RestoreCursorForCurrentButton
set "exit_code=%ERRORLEVEL%"

echo.
if not "%exit_code%"=="0" (
    echo Uninstall failed.
    echo.
    pause
    exit /b %exit_code%
)

echo Uninstall completed successfully.
echo.
pause
exit /b 0
