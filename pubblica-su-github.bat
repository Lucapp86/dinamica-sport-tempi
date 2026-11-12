@echo off
cd /d "%~dp0"

set "GIT_EXE=git"
where git >nul 2>nul
if errorlevel 1 (
  if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages\Git.MinGit_Microsoft.Winget.Source_8wekyb3d8bbwe\cmd\git.exe" (
    set "GIT_EXE=%LOCALAPPDATA%\Microsoft\WinGet\Packages\Git.MinGit_Microsoft.Winget.Source_8wekyb3d8bbwe\cmd\git.exe"
  ) else (
    echo Git non trovato su questo PC.
    pause
    exit /b 1
  )
)

echo Preparazione pubblicazione su GitHub...
"%GIT_EXE%" add -A
"%GIT_EXE%" diff --cached --quiet
if errorlevel 1 (
  "%GIT_EXE%" commit -m "Aggiornamento portale Dinamica Sport"
)

echo Invio aggiornamenti su GitHub (se si apre la finestra di login nel browser, conferma l'accesso)...
"%GIT_EXE%" push -u origin main
echo.
if errorlevel 1 (
  echo Si e verificato un problema durante il push. Controlla il messaggio qui sopra.
) else (
  echo Pubblicazione completata! Attendi circa 1 minuto e ricarica il sito su smartphone.
)
pause
