@echo off
cd /d "%~dp0"
start "" PowerShell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ".\IPConfigGUI.ps1"