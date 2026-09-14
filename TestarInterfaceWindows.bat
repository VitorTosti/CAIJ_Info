@echo off
start "" /b powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0CoreCAIJ\InfoNotebookWindowsPreview.ps1"
exit /b
