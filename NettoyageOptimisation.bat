@echo off
rem ============================================================
rem  NettoyageOptimisation.bat
rem  Copyright (c) 2026 Patrick JAILLET
rem
rem  Utilitaire de nettoyage et d'optimisation en un clic :
rem    - Supprime les fichiers temporaires utilisateur (%TEMP%)
rem    - Supprime les fichiers temporaires systeme (%SystemRoot%\Temp)
rem    - Vide le cache DNS (ipconfig /flushdns)
rem    - Nettoie le dossier Prefetch (%SystemRoot%\Prefetch)
rem    - Vide la corbeille
rem    - Affiche l'espace disque libere et met en pause a la fin
rem  Les fichiers utilises par le systeme ou un programme sont ignores.
rem  Le script demande les droits administrateur si necessaire.
rem ============================================================
setlocal

rem === Verification des droits administrateur (relance en mode admin si besoin) ===
net session >nul 2>&1
if errorlevel 1 (
    echo Droits administrateur requis : relance du script en mode administrateur...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo === Nettoyage et optimisation ===
echo.

rem === Espace libre avant nettoyage (en Mo) ===
call :FreeMB FREE_BEFORE

echo [1/5] Fichiers temporaires utilisateur...
call :CleanDir "%TEMP%"

echo [2/5] Fichiers temporaires systeme...
call :CleanDir "%SystemRoot%\Temp"

echo [3/5] Vidage du cache DNS...
ipconfig /flushdns

echo [4/5] Nettoyage du dossier Prefetch...
call :CleanDir "%SystemRoot%\Prefetch"

echo [5/5] Vidage de la corbeille...
powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue"

echo.

rem === Espace libre apres nettoyage et calcul du gain ===
call :FreeMB FREE_AFTER
set /a FREED=FREE_AFTER-FREE_BEFORE

echo === Resultat ===
echo Espace libre avant : %FREE_BEFORE% Mo
echo Espace libre apres : %FREE_AFTER% Mo
echo Espace libere      : %FREED% Mo
echo.
echo === Termine ===
pause
endlocal
exit /b 0


rem ------------------------------------------------------------
rem :CleanDir <dossier>
rem Supprime le contenu du dossier (fichiers et sous-dossiers),
rem sans supprimer le dossier lui-meme. Erreurs ignorees.
rem ------------------------------------------------------------
:CleanDir
if not exist "%~1" goto :eof
del /f /s /q "%~1\*" >nul 2>&1
for /d %%D in ("%~1\*") do rd /s /q "%%~D" >nul 2>&1
goto :eof


rem ------------------------------------------------------------
rem :FreeMB <variable>
rem Stocke dans <variable> l'espace libre du lecteur systeme, en Mo
rem ------------------------------------------------------------
:FreeMB
for /f %%S in ('powershell -NoProfile -Command "[math]::Round((Get-PSDrive %SystemDrive:~0,1%).Free/1MB)"') do set "%~1=%%S"
goto :eof