@echo off



rem ---------------------------------------------------------------------------
rem
rem  Int‚rprete de la llamada a funci¢n.
rem
rem ---------------------------------------------------------------------------

if %1==-?  goto Usage
if %1==/?  goto Usage
if %1==-h  goto Usage
if %1==/h  goto Usage
if %1==-H  goto Usage
if %1==/H  goto Usage
if %1==vt  goto MakeVT
if %1==VT  goto MakeVT
if %1==run goto MakeRun
if %1==RUN goto MakeRun
if %1==exe goto MakeExe
if %1==EXE goto MakeExe
if %1==src goto MakeSrc
if %1==SRC goto MakeSrc
if %1==all goto MakeAll
if %1==ALL goto MakeAll
if %1==pke goto PackExe
if %1==PKE goto PackExe
if %1==pks goto PackSrc
if %1==PKS goto PackSrc
if .%1==.  goto NoOption
goto %1



rem ---------------------------------------------------------------------------
rem
rem  Funciones de compilaci¢n.
rem
rem ---------------------------------------------------------------------------

:MakeVT
  cd FONT
  call make
  cd ..
  call tpc MAKESTR
  tdstrip  MAKESTR
  lzexe    MAKESTR
  del      MAKESTR.OLD
  MakeStr
  call tpc VT
  tdstrip  VT
  lzexe    VT
  del      VT.OLD
  call tpc ShellVT
  tdstrip  ShellVT
  lzexe    ShellVT
  del      SHELLVT.OLD
rem  call tpc OS2VT
rem  tdstrip  OS2VT
rem  lzexe    OS2VT
rem  del      OS2VT.OLD
  goto Fin



:MakeRun
  call make VT
  copy VT.EXE      \MODP > NUL
  copy VT_ESP.LNG  \MODP > NUL
  copy VT_ENG.LNG  \MODP > NUL
  copy ShellVT.EXE \MODP > NUL
rem  copy OS2VT.EXE   \MODP > NUL
  goto Fin



rem ---------------------------------------------------------------------------
rem
rem  Funciones de creaci¢n de nuevas versiones.
rem
rem ---------------------------------------------------------------------------

:MakeDocs
rem  cd DOC
rem  call make
rem  cd ..
rem  doc\makedoc VT_HIS.TXT   VT.HIS
rem  doc\makedoc VT_H_ENG.TXT VT_ENG.HIS
rem  doc\makedoc COMPATIB.TXT COMPATIB.LST
  goto Fin



:MakeExe
  if %2.==.                   goto NeedVersion
  if exist VERSIONS\VTE%2.ARJ goto AlreadyExists
  call make MakeDocs
  call make RUN
  call make PackExe %2
  goto Fin



:MakeSrc
  if %2.==.                   goto NeedVersion
  if exist VERSIONS\VTS%2.ARJ goto AlreadyExists
  call make MakeDocs
  call make RUN
  call make PackSrc %2
  goto Fin



:MakeAll
  if %2.==.                   goto NeedVersion
  if exist VERSIONS\VT?%2.ARJ goto OneExists
:OnlyOneExists
  call make MakeDocs
  call make RUN
  call make PackExe %2
  call make PackSrc %2
  goto Fin



rem ---------------------------------------------------------------------------
rem
rem  Funciones de empaquetado de los fuentes y los ejecutables.
rem
rem ---------------------------------------------------------------------------

:PackSrc
  md VERSIONS > NUL
  if exist VERSIONS\VTS%2.ARJ goto Fin
  arj a -zBANNER.TXT VERSIONS\VTS%2.ARJ !VTSRC.LST
  goto Fin



:PackExe
  md VERSIONS > NUL
  if exist VERSIONS\VTE%2.ARJ goto Fin
  arj a -zBANNER.TXT VERSIONS\VTE%2.ARJ !VTEXE.LST
  goto Fin



rem ---------------------------------------------------------------------------
rem
rem  Funciones de utilidad.
rem
rem ---------------------------------------------------------------------------

:Usage
  echo "    MAKE { VT | RUN | EXE | SRC | ALL } [<versi¢n>]"
  goto Fin



:OneExists
  if exist VERSIONS\VTEXE%2.ARJ goto AlreadyExists
  goto OnlyOneExists



:NeedVersion
  echo Necesito un n£mero de versi¢n.
  goto Usage



:AlreadyExists
  echo Esa versi¢n ya existe: %2
  goto Fin

  

:NoOption
  echo "Tienes que especificarme una opci¢n v lida."
  echo.
  goto Usage



:Fin
