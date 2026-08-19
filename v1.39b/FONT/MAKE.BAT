@echo off
getfont font.cel . font.dat
binobj font.dat font.obj Font8x8
copy font.obj ..\lib
