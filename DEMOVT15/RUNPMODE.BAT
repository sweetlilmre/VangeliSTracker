@echo off
copy PMode\PModeTst.Exe Example.Exe

Setup\DVTSetup
DemoVT @DVT.VTO
del DVT.VTO > nul

del Example.Exe > nul
