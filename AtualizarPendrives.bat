@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0CoreCAIJ\AtualizarPendrives.ps1"
set "resultado=%errorlevel%"
echo.
if "%resultado%"=="0" (
    echo Pendrives preparados com sucesso.
) else (
    echo Nenhum pendrive foi atualizado. Codigo: %resultado%
)
pause
exit /b %resultado%
