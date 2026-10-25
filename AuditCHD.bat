@echo off
rem ============================================================
rem  AuditCHD.bat
rem  Copyright (c) 2026 Patrick JAILLET
rem
rem  Audit d'integrite et analyse de metadonnees d'une collection .chd :
rem    - Verification en lot avec chdman verify (SHA1, erreurs)
rem    - Extraction des metadonnees avec chdman info (taille logique,
rem      taille des hunks, compression, SHA1 global, nombre de pistes)
rem    - Rapport chd_audit_report.txt separant :
rem        VALIDES, AVERTISSEMENTS, CORROMPUS (a redumper)
rem    - Mode interactif : quarantaine ou suppression des fichiers
rem      corrompus, fichier par fichier (ou tout ignorer)
rem  Usage : AuditCHD.bat "D:\Collection"
rem  chdman.exe doit etre dans le PATH ou a cote de ce script.
rem ============================================================
setlocal EnableDelayedExpansion
title Audit CHD - Copyright 2026 Patrick JAILLET

if "%~1"=="" (
    echo Usage : %~nx0 "dossier"
    exit /b 1
)
set "ROOT=%~f1"
if not exist "%ROOT%\" (
    echo [ERREUR] Dossier introuvable : "%ROOT%"
    exit /b 1
)

rem === Localisation de chdman ===
set "CHDMAN="
where chdman >nul 2>&1 && set "CHDMAN=chdman"
if not defined CHDMAN if exist "%~dp0chdman.exe" set "CHDMAN=%~dp0chdman.exe"
if not defined CHDMAN (
    echo [ERREUR] chdman.exe introuvable : placez-le dans le PATH ou a cote du script.
    exit /b 1
)

rem === Fichiers de travail et de rapport ===
set "REPORT=%ROOT%\chd_audit_report.txt"
set "QUAR=%ROOT%\_quarantaine"
set "WORK=%TEMP%\chdaudit"
if exist "%WORK%" rd /s /q "%WORK%"
mkdir "%WORK%"
set "OKF=%WORK%\valid.txt"
set "WARNF=%WORK%\warn.txt"
set "BADF=%WORK%\corrupt_paths.txt"
set "BADR=%WORK%\corrupt_rep.txt"
set "WARNR=%WORK%\warn_rep.txt"
type nul > "%OKF%"
type nul > "%WARNF%"
type nul > "%BADF%"
type nul > "%BADR%"

echo === Audit de "%ROOT%" ===
echo.

rem ============================================================
rem  Verification et extraction des metadonnees
rem ============================================================
set "TOTAL=0"
for /r "%ROOT%" %%F in (*.chd) do (
    set /a TOTAL+=1
    set "CUR=%%~fF"
    set "NAME=%%~nxF"
    echo [!TOTAL!] %%~nxF
    "%CHDMAN%" verify -i "%%~fF" >"%WORK%\v.log" 2>&1
    set "RC=!ERRORLEVEL!"
    "%CHDMAN%" info -i "%%~fF" >"%WORK%\i.log" 2>&1
    call :Classify
)

if %TOTAL%==0 (
    echo Aucun fichier .chd trouve dans "%ROOT%".
    rd /s /q "%WORK%" 2>nul
    pause
    endlocal
    exit /b 0
)

rem === Comptage des resultats ===
for /f %%n in ('find /c /v "" "%OKF%"') do set "NOK=%%n"
for /f %%n in ('find /c /v "" "%WARNF%"') do set "NWARN=%%n"
for /f %%n in ('find /c /v "" "%BADF%"') do set "NBAD=%%n"

rem ============================================================
rem  Generation du rapport structure
rem ============================================================
> "%REPORT%" echo Rapport d'audit CHD
>>"%REPORT%" echo Dossier audite : %ROOT%
>>"%REPORT%" echo Date           : %DATE% %TIME%
>>"%REPORT%" echo Fichiers .chd  : %TOTAL%
>>"%REPORT%" echo.
>>"%REPORT%" echo ===== VALIDES (%NOK%) =====
type "%OKF%" >>"%REPORT%"
>>"%REPORT%" echo.
>>"%REPORT%" echo ===== AVERTISSEMENTS (%NWARN%) =====
type "%WARNR%" >>"%REPORT%"
>>"%REPORT%" echo.
>>"%REPORT%" echo ===== CORROMPUS - REDUMP NECESSAIRE (%NBAD%) =====
type "%BADR%" >>"%REPORT%"
>>"%REPORT%" echo.
>>"%REPORT%" echo ===== ACTIONS =====

echo.
echo === Resultat de l'audit ===
echo Fichiers .chd analyses : %TOTAL%
echo Valides                : %NOK%
echo Avertissements         : %NWARN%
echo Corrompus              : %NBAD%
echo Rapport                : %REPORT%

rem ============================================================
rem  Mode interactif de reparation
rem ============================================================
if %NBAD% gtr 0 (
    echo.
    echo %NBAD% fichier^(s^) corrompu^(s^) detecte^(s^). Choisissez l'action pour chacun.
    set "REPAIR_ALL="
    for /f "usebackq delims=" %%P in ("%BADF%") do call :Repair "%%P"
)

echo.
echo === Termine ===
rd /s /q "%WORK%" 2>nul
pause
endlocal
exit /b 0


rem ============================================================
rem  :Classify  - decide VALID / WARN / CORRUPT et ecrit les lignes
rem  Variables attendues : CUR, NAME, RC (code retour de verify)
rem ============================================================
:Classify
set "STATE=VALID"
set "REASON="

rem Erreur de verification : corrompu, sauf cas "parent manquant" (avertissement)
if not "!RC!"=="0" (
    set "STATE=CORRUPT"
    findstr /i "parent" "%WORK%\v.log" >nul && set "STATE=WARN"
)
rem Verification reussie mais avec un avertissement dans la sortie
if "!RC!"=="0" findstr /i "warning" "%WORK%\v.log" >nul && set "STATE=WARN"

rem Premiere ligne de diagnostic pour les fichiers non valides
if not "!STATE!"=="VALID" (
    for /f "delims=" %%L in ('findstr /i /c:"error" /c:"warning" /c:"mismatch" /c:"fail" /c:"parent" "%WORK%\v.log"') do set "REASON=%%L"
)

rem Metadonnees (chdman info) : champs lus en debut de ligne
set "LSIZE=?"
set "HUNK=?"
set "COMP=?"
set "SHA=?"
set "NTRK=0"
for /f "tokens=1* delims=:" %%A in ('findstr /b /i /c:"Logical size" "%WORK%\i.log"') do set "LSIZE=%%B"
for /f "tokens=1* delims=:" %%A in ('findstr /b /i /c:"Hunk Size" "%WORK%\i.log"') do set "HUNK=%%B"
for /f "tokens=1* delims=:" %%A in ('findstr /b /i /c:"Compression" "%WORK%\i.log"') do set "COMP=%%B"
for /f "tokens=1* delims=:" %%A in ('findstr /b /i /c:"SHA1" "%WORK%\i.log"') do set "SHA=%%B"
for /f %%n in ('findstr /i /c:"TRACK:" "%WORK%\i.log" ^| find /c /v ""') do set "NTRK=%%n"

set "LINE=!NAME! | taille:!LSIZE! | hunk:!HUNK! | compression:!COMP! | pistes:!NTRK! | sha1:!SHA!"
if defined REASON set "LINE=!LINE! | !REASON!"

if "!STATE!"=="VALID" >>"%OKF%" echo(!LINE!
if "!STATE!"=="WARN" (
    >>"%WARNF%" echo(!LINE!
    >>"%WARNR%" echo(!LINE!
)
if "!STATE!"=="CORRUPT" (
    >>"%BADF%" echo(!CUR!
    >>"%BADR%" echo(!LINE!
)
goto :eof


rem ============================================================
rem  :Repair <chemin>  - propose quarantaine, suppression ou ignore
rem ============================================================
:Repair
if "%REPAIR_ALL%"=="I" goto :eof
echo.
echo Corrompu : %~nx1
choice /c QSIT /n /m "[Q]uarantaine  [S]upprimer  [I]gnorer  [T]out ignorer : "
if errorlevel 4 (
    set "REPAIR_ALL=I"
    goto :eof
)
if errorlevel 3 goto :eof
if errorlevel 2 (
    call :DelOne "%~1"
    goto :eof
)
call :ToQuar "%~1"
goto :eof


rem ============================================================
rem  :ToQuar <chemin>  - deplace le fichier dans _quarantaine
rem  Renomme "nom (1).chd" si un fichier homonyme existe deja
rem ============================================================
:ToQuar
if not exist "%QUAR%\" mkdir "%QUAR%"
set "DST=%QUAR%\%~nx1"
set "K=1"
:QLoop
if exist "!DST!" (
    set "DST=%QUAR%\%~n1 (!K!)%~x1"
    set /a K+=1
    goto :QLoop
)
move "%~1" "!DST!" >nul && (
    echo   deplace vers _quarantaine
    >>"%REPORT%" echo Quarantaine : %~nx1
)
goto :eof


rem ============================================================
rem  :DelOne <chemin>  - suppression definitive, apres confirmation
rem ============================================================
:DelOne
choice /c ON /n /m "Supprimer definitivement ce fichier ? [O]ui [N]on : "
if errorlevel 2 goto :eof
del /f /q "%~1" && (
    echo   supprime
    >>"%REPORT%" echo Supprime   : %~nx1
)
goto :eof