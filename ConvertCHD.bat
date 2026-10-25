@echo off
rem ============================================================
rem  ConvertCHD.bat
rem  Copyright (c) 2026 Patrick JAILLET
rem
rem  Convertit en parallele des images CD (.cue, .gdi) et DVD (.iso, .img)
rem  en .chd avec chdman, dans un dossier et tous ses sous-dossiers.
rem    - Ignore les sources dont le .chd existe deja (deja traitees)
rem    - Limite les conversions simultanees (defaut : coeurs / 2, max 8)
rem    - Codec selon le support : CD (createcd) ou DVD (createdvd)
rem    - Verifie chaque .chd (chdman verify) avant de supprimer la source
rem    - Supprime la source, et les pistes .bin/.raw referencees par
rem      le .cue ou .gdi, uniquement si la conversion et la verification
rem      ont reussi (code retour 0)
rem  Usage : ConvertCHD.bat "D:\Dossier" [nombre_de_taches]
rem  chdman.exe doit etre dans le PATH ou a cote de ce script.
rem ============================================================
setlocal EnableDelayedExpansion

if "%~1"=="" (
    echo Usage : %~nx0 "dossier" [nombre_de_taches]
    exit /b 1
)
set "ROOT=%~1"
if not exist "%ROOT%\" (
    echo [ERREUR] Dossier introuvable : "%ROOT%"
    exit /b 1
)

rem === Localisation de chdman ===
set "CHDMAN="
where chdman >nul 2>&1 && set "CHDMAN=chdman"
if not defined CHDMAN if exist "%~dp0chdman.exe" set "CHDMAN=%~dp0chdman.exe"
if not defined CHDMAN echo [ERREUR] chdman.exe introuvable : placez-le dans le PATH ou a cote du script & exit /b 1

rem === Codecs par type de support (ajustez selon votre version de chdman) ===
set "CD_CODECS=cdlz,cdzs,cdzl,cdfl"
set "DVD_CODECS=lzma,zlib,huff,flac"

rem === Nombre de taches simultanees ===
set "CORES=%NUMBER_OF_PROCESSORS%"
set /a MAX=CORES/2
if %MAX% lss 1 set "MAX=1"
if %MAX% gtr 8 set "MAX=8"
if not "%~2"=="" set "MAX=%~2"

rem === Dossier de travail : verrous, resultats et journaux ===
set "WORK=%TEMP%\chdbatch"
if exist "%WORK%" rd /s /q "%WORK%"
mkdir "%WORK%\run" "%WORK%\done" "%WORK%\log"

echo === Conversion CHD de "%ROOT%" ===
echo Taches simultanees : %MAX%   (coeurs logiques : %CORES%)
echo.

rem ============================================================
rem  Exploration recursive et lancement des conversions
rem ============================================================
set "N=0"
set "SKIP=0"
for /r "%ROOT%" %%F in (*.cue *.gdi *.iso *.img) do (
    if exist "%%~dpnF.chd" (
        set /a SKIP+=1
    ) else (
        set /a N+=1
        set "JN=!N!"
        set "JSRC=%%~fF"
        set "JDST=%%~dpnF.chd"
        call :WaitFor %MAX%
        > "%WORK%\run\!N!.lock" echo %%~nxF
        echo [!N!] %%~nxF
        start "" /b cmd /c call "%~f0" :Job !N!
    )
)

rem Attente de la fin de toutes les taches
call :WaitFor 1

set "OK=0"
set "KO=0"
for /f %%n in ('dir /b /a-d "%WORK%\done\*.ok" 2^>nul ^| find /c /v ""') do set "OK=%%n"
for /f %%n in ('dir /b /a-d "%WORK%\done\*.fail" 2^>nul ^| find /c /v ""') do set "KO=%%n"

echo.
echo === Resultat ===
echo Deja convertis (ignores) : %SKIP%
echo Reussis                  : %OK%
echo Echecs                   : %KO%
echo Journaux                 : %WORK%\log
if exist "%WORK%\done\*.fail" (
    echo.
    echo Fichiers en echec :
    for %%R in ("%WORK%\done\*.fail") do type "%%R"
)
echo.
echo === Termine ===
pause
endlocal
exit /b 0


rem ============================================================
rem  :WaitFor <limite>  - attend tant que le nombre de taches actives
rem  (fichiers .lock presents) est >= limite
rem ============================================================
:WaitFor
set "LIMIT=%~1"
:WaitLoop
set "RUN=0"
for /f %%n in ('dir /b /a-d "%WORK%\run" 2^>nul ^| find /c /v ""') do set "RUN=%%n"
if %RUN% geq %LIMIT% (
    ping -n 2 127.0.0.1 >nul
    goto :WaitLoop
)
goto :eof


rem ============================================================
rem  :Job <numero>  - execute une conversion, lancee en arriere-plan
rem  Les variables JSRC et JDST sont heritees du script appelant.
rem ============================================================
:Job
setlocal EnableDelayedExpansion
set "JN=%~2"
set "SRCF=%JSRC%"
set "DSTF=%JDST%"

for %%E in ("%SRCF%") do set "EXT=%%~xE"

set "CMD=createcd"
set "CODECS=%CD_CODECS%"
if /i "%EXT%"==".iso" set "CMD=createdvd"
if /i "%EXT%"==".img" set "CMD=createdvd"
if /i "%CMD%"=="createdvd" set "CODECS=%DVD_CODECS%"

rem --- Conversion ---
"%CHDMAN%" %CMD% -i "%SRCF%" -o "%DSTF%" -c %CODECS% >"%WORK%\log\%JN%.log" 2>&1
set "RC=!ERRORLEVEL!"

rem --- Verification stricte du .chd produit ---
if "!RC!"=="0" (
    "%CHDMAN%" verify -i "%DSTF%" >>"%WORK%\log\%JN%.log" 2>&1
    set "RC=!ERRORLEVEL!"
)

rem --- Nettoyage conditionnel ---
if "!RC!"=="0" (
    call :Cleanup
    > "%WORK%\done\%JN%.ok" echo OK !SRCF!
) else (
    if exist "%DSTF%" del /f /q "%DSTF%"
    > "%WORK%\done\%JN%.fail" echo FAIL !SRCF!
)

rem Le verrou est retire en dernier pour que le script principal attende la fin
del /f /q "%WORK%\run\%JN%.lock" 2>nul
endlocal
exit /b 0


rem ============================================================
rem  :Cleanup  - supprime la source, et les pistes referencees
rem  pour les .cue et .gdi (appele uniquement apres succes)
rem ============================================================
:Cleanup
for %%D in ("%SRCF%") do set "DIR=%%~dpD"
if /i "%EXT%"==".cue" call :RemoveRefs
if /i "%EXT%"==".gdi" call :RemoveRefs
del /f /q "%SRCF%"
goto :eof


rem ============================================================
rem  :RemoveRefs  - supprime les fichiers .bin/.raw cites dans la source
rem ============================================================
:RemoveRefs
for /f tokens^=2^ delims^=^" %%B in ('findstr /i /c:".bin" /c:".raw" "%SRCF%"') do if exist "%DIR%%%~B" del /f /q "%DIR%%%~B"
goto :eof