@echo off
cd /d "%~dp0"
set /p TEAM_PW=Inserisci la password di squadra per cifrare i dati: 
if "%TEAM_PW%"=="" (
  echo Password vuota, operazione annullata.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update_results.ps1" -Password "%TEAM_PW%" -Force
pause

