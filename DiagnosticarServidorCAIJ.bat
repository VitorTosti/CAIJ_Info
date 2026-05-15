@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0CoreCAIJ\DiagnosticoConexaoCAIJ.ps1"
pause
