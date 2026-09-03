@echo off
copy TPas\PasTst.Exe Example.Exe

Setup\DVTSetup
DemoVT @DVT.VTO
del DVT.VTO > nul

del Example.Exe > nul
