@echo off
setlocal

set "SCRIPT=%~dp0Windows-Info.ps1"

if not exist "%SCRIPT%" (
    echo.
    echo [ERROR] Windows-Info.ps1 was not found:
    echo %SCRIPT%
    echo.
    pause
    exit /b 1
)

echo.
echo Collecting Windows installation and license information...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo [ERROR] Windows-Info.ps1 returned exit code %RC%.
) else (
    echo Done.
)

echo.
pause
exit /b %RC%
