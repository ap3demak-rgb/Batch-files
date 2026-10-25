@echo off
rem ============================================================
rem  RaycastBatch.bat
rem  Copyright (c) 2026 Patrick JAILLET
rem
rem  Moteur de rendu raycasting 3D simplifie en pur Batch :
rem    - Labyrinthe 8x8, vue 3D rendue en caracteres ASCII
rem    - Calculs en virgule fixe (valeurs x1000), pas de flottants
rem    - Table cosinus precalculee sur 32 angles (la sinus en decoule)
rem    - Tampon d'image ecrit dans %TEMP% puis affiche d'un seul coup
rem  Commandes : W avancer, S reculer, A tourner a gauche,
rem              D tourner a droite, Q quitter
rem  Taille de la fenetre : 44 colonnes x 22 lignes
rem ============================================================
setlocal EnableDelayedExpansion
title Raycasting Batch - Copyright 2026 Patrick JAILLET
mode con: cols=44 lines=22

rem --- Constantes : largeur et hauteur de l'ecran en caracteres ---
set "W=40"
set "H=18"
set "MOVE=120"
set "FB=%TEMP%\raycast_frame.txt"
set "SH=#O+:-."

rem --- Table cosinus x1000 sur 32 angles (pas de 11.25 degres) ---
set /a "i=0"
for %%V in (1000 981 924 831 707 556 383 195 0 -195 -383 -556 -707 -831 -924 -981 -1000 -981 -924 -831 -707 -556 -383 -195 0 195 383 556 707 831 924 981) do (
  set "COS!i!=%%V"
  set /a "i+=1"
)

rem --- Carte 8x8 : # = mur, . = sol ---
set "R0=########"
set "R1=#......#"
set "R2=#..##..#"
set "R3=#......#"
set "R4=#.#....#"
set "R5=#....#.#"
set "R6=#.#....#"
set "R7=########"

rem --- Etat du joueur : position x1000 par case, angle index 0..31 ---
set "posX=3500"
set "posY=3500"
set "A=0"
call :Now
set "LAST=!NOW!"


rem ============================================================
rem  Boucle principale
rem ============================================================
:Main
call :Now
set /a "DT=NOW-LAST"
if !DT! lss 1 set "DT=1"
set /a "FPS=100/DT"
set "LAST=!NOW!"

call :Render

rem choice /t 0 ne bloque pas : il retourne la touche en attente ou N
choice /c NWASDQ /n /t 0 /d N >nul
set "KEY=%errorlevel%"
if "!KEY!"=="6" goto :Quit
if "!KEY!"=="5" set /a "A=(A-1)&31"
if "!KEY!"=="4" call :Move -1
if "!KEY!"=="3" set /a "A=(A+1)&31"
if "!KEY!"=="2" call :Move 1
goto :Main

:Quit
cls
endlocal
exit /b 0


rem ============================================================
rem  :Render  - calcule toutes les colonnes puis dessine le tampon
rem ============================================================
:Render
rem Direction (DX,DY) et plan camera (PX,PY), plan = direction +90 deg, longueur 0.66
set /a "A1=(A+8)&31"
set /a "A2=(A+24)&31"
set "DX=!COS%A%!"
set "DY=!COS%A2%!"
set /a "PX=!COS%A1%!*660/1000"
set /a "PY=!COS%A%!*660/1000"

rem Un rayon par colonne (40 colonnes)
for /L %%x in (0,1,39) do call :Cast %%x

rem Tampon : 18 lignes construites colonne par colonne
if exist "%FB%" del "%FB%"
for /L %%r in (0,1,17) do (
  set "r=%%r"
  set "line="
  for /L %%x in (0,1,39) do (
    if !r! lss !T%%x! (set "line=!line! ") else if !r! gtr !B%%x! (set "line=!line!_") else (set "line=!line!!S%%x!")
  )
  >>"%FB%" echo(!line!
)
>>"%FB%" echo(Angle %A%/31   Pos %posX%,%posY%   FPS %FPS%
>>"%FB%" echo(W avancer  S reculer  A gauche  D droite  Q quitter

cls
type "%FB%"
goto :eof


rem ============================================================
rem  :Cast <x>  - lance le rayon de la colonne x (DDA en virgule fixe)
rem ============================================================
:Cast
set /a "cx=1000-(2000*%1)/W"
set /a "rdx=DX+PX*cx/1000"
set /a "rdy=DY+PY*cx/1000"

rem Case courante et position dans la case
set /a "mx=posX/1000, my=posY/1000"
set /a "fx=posX-mx*1000, fy=posY-my*1000"

rem Distance entre deux lignes de grille (deltaDist), avec plafond si direction nulle
set /a "sgx=(rdx<0)*-2+1"
set /a "sgy=(rdy<0)*-2+1"
set "ddx=100000"
set "ddy=100000"
if !rdx! neq 0 set /a "ddx=1000000/(rdx*sgx)"
if !rdy! neq 0 set /a "ddy=1000000/(rdy*sgy)"

rem Sens de pas et distance initiale au premier bord
set /a "sx=1-2*(rdx<0)"
set /a "sy=1-2*(rdy<0)"
set /a "sdx=((rdx<0)*fx+(rdx>=0)*(1000-fx))*ddx/1000"
set /a "sdy=((rdy<0)*fy+(rdy>=0)*(1000-fy))*ddy/1000"

set "hit=0"
set "side=0"
:Dda
if !sdx! lss !sdy! (
  set /a "sdx+=ddx"
  set /a "mx+=sx"
  set "side=0"
) else (
  set /a "sdy+=ddy"
  set /a "my+=sy"
  set "side=1"
)
call :IsWall !mx! !my!
if "!hit!"=="0" goto :Dda

rem Distance perpendiculaire (evite la distorsion en fisheye)
if "!side!"=="0" (set /a "perp=sdx-ddx") else (set /a "perp=sdy-ddy")
if !perp! lss 200 set "perp=200"

rem Hauteur du mur, centree verticalement
set /a "lh=H*1000/perp"
if !lh! gtr H set "lh=H"
set /a "top=(H-lh)/2"
set /a "bot=top+lh-1"

rem Ombrage : plus loin = caractere plus clair, face y = plus sombre
set /a "si=perp/1000+side"
if !si! gtr 5 set "si=5"
set "ch=!SH:~%si%,1!"

set "T%1=!top!"
set "B%1=!bot!"
set "S%1=!ch!"
goto :eof


rem ============================================================
rem  :IsWall <x> <y>  - hit=1 si mur ou hors carte, 0 si sol
rem ============================================================
:IsWall
set "hit=1"
set "wx=%1"
set "wy=%2"
if %1 lss 0 goto :eof
if %1 gtr 7 goto :eof
if %2 lss 0 goto :eof
if %2 gtr 7 goto :eof
set "c=!R%wy%:~%wx%,1!"
if "!c!"=="." set "hit=0"
goto :eof


rem ============================================================
rem  :Move <sens>  - sens = 1 avance, -1 recule, avec glissement sur les murs
rem ============================================================
:Move
set /a "nx=posX+%1*DX*MOVE/1000"
set /a "ny=posY+%1*DY*MOVE/1000"
set /a "cxn=nx/1000, cyn=ny/1000"
set /a "cx0=posX/1000, cy0=posY/1000"
call :IsWall %cxn% %cy0%
if "!hit!"=="0" set "posX=!nx!"
call :IsWall %cx0% %cyn%
if "!hit!"=="0" set "posY=!ny!"
goto :eof


rem ============================================================
rem  :Now  - heure courante en centiemes de seconde, dans NOW
rem ============================================================
:Now
set "t=%time: =0%"
set /a "NOW=(((1%t:~0,2%-100)*60+(1%t:~3,2%-100))*60+(1%t:~6,2%-100))*100+(1%t:~9,2%-100)"
goto :eof