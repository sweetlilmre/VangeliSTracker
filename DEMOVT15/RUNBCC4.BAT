@echo off
copy BCC4\BCCTst.Exe Example.Exe

Setup\DVTSetup
DemoVT @DVT.VTO
del DVT.VTO > nul

del Example.Exe > nul
