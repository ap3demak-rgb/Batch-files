@echo off
rem ============================================================
rem  ShaderWeaver.bat
rem  Copyright (c) 2026 Patrick JAILLET
rem
rem  Pipeline de build pour shaders GLSL ou HLSL :
rem    1. Assemblage : concatene les fragments du dossier, par ordre
rem       alphabetique (prefixes 00_, 10_, 20_... pour fixer l'ordre)
rem    2. Minification : supprime les commentaires //, les lignes vides,
rem       l'indentation, les espaces multiples et les espaces inutiles
rem       autour de , ; ( ) { }. Les "!" sont proteges par PowerShell.
rem    3. Validation : glslangValidator -S frag (GLSL), ou dxc / fxc
rem       (HLSL), appliques au shader assemble ET au shader minifie.
rem       Les erreurs sont extraites du journal et affichees.
rem    4. Mode watch : recompile a chaque modification d'un fragment.
rem  Usage : ShaderWeaver.bat "dossier" [glsl|hlsl] [watch]
rem  Sorties : dossier\build\assembled.* (brut) et final.* (minifie)
rem  Les outils glslangValidator, dxc ou fxc doivent etre dans le PATH.
rem  Non fait : suppression des variables mortes (demande une analyse
rem  syntaxique complete, impossible de facon fiable en Batch).
rem ============================================================
setlocal EnableDelayedExpansion
title ShaderWeaver - Copyright 2026 Patrick JAILLET

if "%~1"=="" (
    echo Usage : %~nx0 "dossier" [glsl ou hlsl] [watch]
    exit /b 1
)
set "SRC=%~f1"
if not exist "%SRC%\" (
    echo [ERREUR] Dossier introuvable : "%SRC%"
    exit /b 1
)

set "SW_LANG=%~2"
if "%SW_LANG%"=="" set "SW_LANG=glsl"
if /i "%SW_LANG%"=="hlsl" (
    set "EXT=hlsl"
) else if /i "%SW_LANG%"=="glsl" (
    set "EXT=frag"
) else (
    echo [ERREUR] Langage inconnu : %SW_LANG%  ^(glsl ou hlsl attendu^)
    exit /b 1
)

rem Point d'entree HLSL (fonction principale du shader)
set "ENTRY=main"

set "BUILD=%SRC%\build"
if not exist "%BUILD%" mkdir "%BUILD%"
set "RAW=%BUILD%\assembled.%EXT%"
set "FINAL=%BUILD%\final.%EXT%"
set "ENC=%BUILD%\enc.tmp"
set "MINTMP=%BUILD%\min.tmp"
set "VLOG=%BUILD%\validate.log"

echo === ShaderWeaver : "%SRC%" [%SW_LANG%] ===
call :Build

if /i not "%~3"=="watch" goto :EndMain
call :WatchLoop

:EndMain
echo.
echo === Termine ===
pause
endlocal
exit /b 0


rem ============================================================
rem  :Build  - assemble, minifie et valide une fois
rem ============================================================
:Build
echo.
echo [%TIME%] Assemblage...
> "%RAW%" type nul
set "COUNT=0"
if /i "%SW_LANG%"=="hlsl" (
    for /f "delims=" %%F in ('dir /b /on /a-d "%SRC%\*.hlsl" 2^>nul') do call :Append "%SRC%\%%F"
) else (
    for /f "delims=" %%F in ('dir /b /on /a-d "%SRC%\*.glsl" "%SRC%\*.frag" 2^>nul') do call :Append "%SRC%\%%F"
)
if "%COUNT%"=="0" (
    echo [ERREUR] Aucun fragment .%EXT% dans "%SRC%"
    goto :eof
)
echo   %COUNT% fragment(s) assemble(s)

rem --- Protection du "!" par PowerShell, puis minification en Batch ---
echo   Minification...
set "SW_IN=%RAW%"
set "SW_OUT=%ENC%"
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:SW_OUT,[IO.File]::ReadAllText($env:SW_IN).Replace([string][char]33,'_BANG_'))"
> "%MINTMP%" type nul
for /f "usebackq delims=" %%L in ("%ENC%") do (
    set "L=%%L"
    call :Squeeze
    if defined L if not "!L:~0,2!"=="//" >>"%MINTMP%" echo(!L!
)

rem --- Restauration du "!" dans le fichier final ---
set "SW_IN=%MINTMP%"
set "SW_OUT=%FINAL%"
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:SW_OUT,[IO.File]::ReadAllText($env:SW_IN).Replace('_BANG_',[string][char]33))"
del /q "%ENC%" "%MINTMP%" 2>nul

for %%S in ("%RAW%") do set "SZ1=%%~zS"
for %%S in ("%FINAL%") do set "SZ2=%%~zS"
echo   Taille : %SZ1% octets -^> %SZ2% octets

rem --- Validation du shader assemble puis du shader minifie ---
call :Validate "%RAW%" "assemble"
call :Validate "%FINAL%" "minifie"
goto :eof


rem ============================================================
rem  :Append <fichier>  - ajoute un fragment au shader assemble
rem ============================================================
:Append
set /a COUNT+=1
>>"%RAW%" echo // ---- %~nx1
type "%~1" >>"%RAW%"
>>"%RAW%" echo(
goto :eof


rem ============================================================
rem  :Squeeze  - sur la variable L : trim, espaces multiples,
rem  espaces inutiles autour de , ; ( ) { }
rem ============================================================
:Squeeze
:TrimL
if "!L:~0,1!"==" " (set "L=!L:~1!" & goto :TrimL)
:TrimR
if "!L:~-1!"==" " (set "L=!L:~0,-1!" & goto :TrimR)
:Dbl
set "T=!L:  = !"
if "!T!"=="!L!" goto :Sep
set "L=!T!"
goto :Dbl
:Sep
set "L=!L:, =,!"
set "L=!L:; =;!"
set "L=!L: ;=;!"
set "L=!L:( =(!"
set "L=!L: )=)!"
set "L=!L:{ ={!"
set "L=!L: }=}!"
goto :eof


rem ============================================================
rem  :Validate <fichier> <libelle>  - compile sans lancer l'application
rem ============================================================
:Validate
set "VF=%~1"
set "VRES=OK"
if /i "%SW_LANG%"=="hlsl" (
    where dxc >nul 2>&1
    if not errorlevel 1 (
        dxc -T ps_6_0 -E %ENTRY% -Fo "%BUILD%\out.dxil" "%VF%" >"%VLOG%" 2>&1
    ) else (
        fxc /nologo /T ps_5_0 /E %ENTRY% /Fo "%BUILD%\out.cso" "%VF%" >"%VLOG%" 2>&1
    )
) else (
    where glslangValidator >nul 2>&1
    if errorlevel 1 (
        echo   [ERREUR] glslangValidator introuvable : ajoutez-le au PATH
        goto :eof
    )
    glslangValidator -S frag "%VF%" >"%VLOG%" 2>&1
)
if errorlevel 1 set "VRES=FAIL"
if "%VRES%"=="FAIL" (
    echo   [ECHEC] %~2 : erreurs de compilation
    findstr /i /c:"error" "%VLOG%"
) else (
    echo   [OK] %~2 : valide
)
goto :eof


rem ============================================================
rem  :WatchLoop  - recompile quand un fragment est modifie
rem  Signature = date, heure et nom de chaque fragment (forfiles)
rem ============================================================
:WatchLoop
echo.
echo Mode watch actif : modifiez un fragment pour recompiler. Ctrl+C pour arreter.
call :Sig "%BUILD%\sig.old"
:WLoop
ping -n 2 127.0.0.1 >nul
call :Sig "%BUILD%\sig.new"
fc /b "%BUILD%\sig.new" "%BUILD%\sig.old" >nul 2>&1
if not errorlevel 1 goto :WLoop
move /y "%BUILD%\sig.new" "%BUILD%\sig.old" >nul
echo.
echo ---- Modification detectee ----
call :Build
goto :WLoop


rem ============================================================
rem  :Sig <fichier>  - ecrit la signature des fragments dans fichier
rem ============================================================
:Sig
> "%~1" type nul
forfiles /p "%SRC%" /m *.glsl /c "cmd /c echo @fdate @ftime @file" >>"%~1" 2>nul
forfiles /p "%SRC%" /m *.frag /c "cmd /c echo @fdate @ftime @file" >>"%~1" 2>nul
forfiles /p "%SRC%" /m *.hlsl /c "cmd /c echo @fdate @ftime @file" >>"%~1" 2>nul
goto :eof