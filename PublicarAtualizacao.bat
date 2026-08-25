@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CoreCAIJ\PublicarAtualizacao.ps1"
if errorlevel 1 (
    echo.
    echo Nao foi possivel publicar a atualizacao.
    pause
    exit /b 1
)
echo.
echo Atualizacao pronta para os pendrives.
pause
