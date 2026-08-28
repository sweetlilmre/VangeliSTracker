@echo off
del *.TPU > NUL
echo === build > BUILD.LOG
echo. >> BUILD.LOG
echo ---- IDXPROBE.PAS >> BUILD.LOG
C:\TP600\TPC.EXE /$A+ /$B- /$D+ /$E+ /$F- /$G+ /$I- /$L+ /$N+ /$O- /$R- /$S- /$V- /$X+ /Q IDXPROBE.PAS >> BUILD.LOG
if errorlevel 1 echo ** FAILED >> BUILD.LOG
if not errorlevel 1 echo ** OK >> BUILD.LOG
exit
