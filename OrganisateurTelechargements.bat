@echo off
rem ============================================================
rem  OrganisateurTelechargements.bat
rem  Copyright (c) 2026 Patrick JAILLET
rem
rem  Trie automatiquement le dossier Telechargements de l'utilisateur
rem  courant selon l'extension des fichiers :
rem    .exe, .msi         -> Installateurs
rem    .zip, .rar, .7z    -> Archives
rem    .jpg, .png, .gif   -> Images
rem    .mp4, .mkv, .avi   -> Videos
rem    .pdf, .docx, .txt  -> Documents
rem  Les dossiers manquants sont crees automatiquement, et en cas de
rem  nom identique, le fichier est renomme (ex. "rapport (1).pdf").
rem ============================================================
setlocal

rem === Dossier source : Telechargements de l'utilisateur courant ===
set "SRC=%USERPROFILE%\Downloads"
cd /d "%SRC%" || (
    echo [ERREUR] Dossier introuvable : "%SRC%"
    pause
    exit /b 1
)

echo === Organisation de "%SRC%" ===
echo.

rem === Creation automatique des dossiers de destination ===
for %%D in (Installateurs Archives Images Videos Documents) do (
    if not exist "%%D" mkdir "%%D"
)

rem === Deplacement par extension ===
call :MoveByExt Installateurs exe msi
call :MoveByExt Archives      zip rar 7z
call :MoveByExt Images        jpg png gif
call :MoveByExt Videos        mp4 mkv avi
call :MoveByExt Documents     pdf docx txt

echo.
echo === Termine ===
pause
endlocal
exit /b 0


rem ------------------------------------------------------------
rem :MoveByExt <dossier> <ext1> [ext2] [ext3] ...
rem Deplace tous les fichiers des extensions donnees vers <dossier>
rem ------------------------------------------------------------
:MoveByExt
set "DEST=%~1"
shift

:NextExt
if "%~1"=="" goto :eof
for %%F in ("*.%~1") do (
    if exist "%%~fF" call :SafeMove "%%~fF" "%DEST%"
)
shift
goto :NextExt


rem ------------------------------------------------------------
rem :SafeMove <fichier> <dossier>
rem Deplace le fichier. Si le nom existe deja, ajoute " (1)", " (2)", etc.
rem ------------------------------------------------------------
:SafeMove
set "NAME=%~n1"
set "EXT=%~x1"
set "TARGETDIR=%~2"
set "TARGET=%TARGETDIR%\%NAME%%EXT%"
set /a N=1

:CheckName
if exist "%TARGET%" (
    set "TARGET=%TARGETDIR%\%NAME% (%N%)%EXT%"
    set /a N+=1
    goto :CheckName
)

move "%~1" "%TARGET%" >nul
echo  %~nx1  -^>  %TARGETDIR%\
goto :eof