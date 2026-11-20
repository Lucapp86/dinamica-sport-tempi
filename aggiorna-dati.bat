@echo off
cd /d "%~dp0"
set /p TEAM_PW=Inserisci la password di squadra per cifrare i dati: 
if "%TEAM_PW%"=="" (
  echo Password vuota, operazione annullata.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\update_results.ps1" -Password "%TEAM_PW%" -Force
if %ERRORLEVEL% equ 0 (
  echo.
  echo Pubblicazione automatica online su GitHub Pages in corso...
  git add data/team-data.enc.json config.team.json
  git commit -m "Aggiornamento automatico dati gare e atleti"
  git push origin main
  if %ERRORLEVEL% equ 0 (
    echo.
    echo ========================================================
    echo DATI AGGIORNATI E PUBBLICATI ONLINE CON SUCCESSO!
    echo L'app sullo smartphone si aggiornera automaticamente.
    echo ========================================================
  ) else (
    echo.
    echo ATTENZIONE: Errore durante la pubblicazione online (git push).
  )
)
pause

