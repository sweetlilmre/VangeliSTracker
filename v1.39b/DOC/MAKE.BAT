@echo off
call tpc MAKEDOC
tdstrip  MAKEDOC
lzexe    MAKEDOC
makedoc vt.txt     ..\vt.doc
makedoc vt_eng.txt ..\english.doc
makedoc 139_ADD.txt ..\README.139
makedoc 139_MAS.txt ..\ARREADME.139
makedoc banner.txt ..\banner.txt
