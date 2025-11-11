@echo off
echo Iniciando script de limpeza como Administrador...
powershell.exe -ExecutionPolicy Bypass -File "%~dp0LimpezaAvancada.ps1"
pause
