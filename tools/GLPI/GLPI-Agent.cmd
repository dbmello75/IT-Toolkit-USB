@echo off
setlocal

rem ================================
rem Configuracoes
rem ================================
set "GLPI_TAG=KBS"
set "GLPI_SERVER=https://infra.vicpro.co/front/inventory.php"
set "GLPI_CLIENT_ID=8df607893dbbdd4c1a11ecd9487732bc0c4253330bd0b6f4f60ba6ea0f858079"
set "GLPI_CLIENT_SECRET=bb74a13d90f9e9bbbfc6de85638b05983efcaa9a4df6d1e51578adaddb0a43a5"

set "MSI=\\KBS-FS\it\GLPI\GLPI-Agent.msi"
set "LOG=C:\Windows\Temp\glpi-agent-install.log"

if not exist "%MSI%" (
    echo [%date% %time%] MSI nao encontrado: %MSI% >> "%LOG%"
    exit /b 1
)

sc query glpi-agent >nul 2>&1
if %errorlevel% equ 0 (
    echo [%date% %time%] GLPI Agent ja instalado. TAG esperado: %GLPI_TAG% >> "%LOG%"
    exit /b 0
)

echo [%date% %time%] Instalando GLPI Agent com TAG %GLPI_TAG% >> "%LOG%"

start /wait "" msiexec.exe /i "%MSI%" /quiet /norestart ^
    SERVER="%GLPI_SERVER%" ^
    OAUTH_CLIENT_ID="%GLPI_CLIENT_ID%" ^
    OAUTH_CLIENT_SECRET="%GLPI_CLIENT_SECRET%" ^
    TAG="%GLPI_TAG%" ^
    RUNNOW=1 ^
    EXECMODE=1 ^
    /L*V "%LOG%"

set "RESULT=%errorlevel%"

echo [%date% %time%] Resultado da instalacao: %RESULT% >> "%LOG%"

if "%RESULT%"=="0" exit /b 0
if "%RESULT%"=="3010" exit /b 0

exit /b %RESULT%
