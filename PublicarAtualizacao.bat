@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CoreCAIJ\PublicarAtualizacao.ps1"
if errorlevel 1 (
    echo.
    echo Nao foi possivel publicar a atualizacao.
    pause
    exit /b 1
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CoreCAIJ\AplicarServidorLocal.ps1"
if errorlevel 1 (
    echo.
    echo O pacote foi publicado, mas o servidor local nao foi atualizado.
    pause
    exit /b 1
)
echo.
echo Atualizacao pronta para os pendrives.
pause
