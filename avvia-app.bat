@echo off
cd /d "%~dp0"
echo Avvio del portale Dinamica Sport su http://127.0.0.1:8765 ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\serve_local.ps1" -Port 8765
pause

