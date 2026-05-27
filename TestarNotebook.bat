@echo off
attrib +h "%~dp0InfoNotebookMac.command" >nul 2>nul
start "" powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0CoreCAIJ\TestarNotebook.ps1"
