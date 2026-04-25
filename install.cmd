@echo off
setlocal

cd /d "%~dp0"

echo Installing Win11 Left-Handed Cursor Sync...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-mouse-cursor-sync.ps1"
set "exit_code=%ERRORLEVEL%"

echo.
if not "%exit_code%"=="0" (
    echo Installation failed.
    echo.
    pause
    exit /b %exit_code%
)

echo Installation completed successfully.
echo You can now change "Primary mouse button" in Windows settings and the Arrow / Hand cursors will follow automatically.
echo.
pause
exit /b 0
