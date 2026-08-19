{****************************************************************************}
{                                                                            }
{ MODULE:         Kbd                                                        }
{                                                                            }
{ DESCRIPTION:    Implements a fast and easy interface with the keyboard.    }
{                 Uses the BIOS call for reading the keys.                   }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        17-Oct-1992 Documentation                                  }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT Kbd;

INTERFACE

{----------------------------------------------------------------------------}
{ Constants imported directly from Turbo Vision, but they work.              }
{____________________________________________________________________________}

CONST
 {kbXXXX Ctrl-Letter Key Codes}

  kbCtrlA    = $1E01;   kbCtrlN   = $310E;
  kbCtrlB    = $3002;   kbCtrlO   = $180F;
  kbCtrlC    = $2E03;   kbCtrlP   = $1910;
  kbCtrlD    = $2004;   kbCtrlQ   = $1011;
  kbCtrlE    = $1205;   kbCtrlR   = $1312;
  kbCtrlF    = $2106;   kbCtrlS   = $1F13;
  kbCtrlG    = $2207;   kbCtrlT   = $1414;
  kbCtrlH    = $2308;   kbCtrlU   = $1615;
  kbCtrlI    = $1709;   kbCtrlV   = $2F16;
  kbCtrlJ    = $240A;   kbCtrlW   = $1117;
  kbCtrlK    = $250B;   kbCtrlX   = $2D18;
  kbCtrlL    = $260C;   kbCtrlY   = $1519;
  kbCtrlM    = $320D;   kbCtrlZ   = $2C1A;

 {kbXXXX Alt-Letter Key Codes}

  kbAltA     = $1E00;   kbAltN    = $3100;
  kbAltB     = $3000;   kbAltO    = $1800;
  kbAltC     = $2E00;   kbAltP    = $1900;
  kbAltD     = $2000;   kbAltQ    = $1000;
  kbAltE     = $1200;   kbAltR    = $1300;
  kbAltF     = $2100;   kbAltS    = $1F00;
  kbAltG     = $2200;   kbAltT    = $1400;
  kbAltH     = $2300;   kbAltU    = $1600;
  kbAltI     = $1700;   kbAltV    = $2F00;
  kbAltJ     = $2400;   kbAltW    = $1100;
  kbAltK     = $2500;   kbAltX    = $2D00;
  kbAltL     = $2600;   kbAltY    = $1500;
  kbAltM     = $3200;   kbAltZ    = $2C00;

 {kbXXXX Special Key Codes}

  kbAltEqual = $8300;  kbEnd      = $4F00;
  kbAltMinus = $8200;  kbEnter    = $1C0D;
  kbAltSpace = $0200;  kbEsc      = $011B;
  kbBack     = $0E08;  kbGrayMinus= $4A2D;
  kbCtrlBack = $0E7F;  kbHome     = $4700;
  kbCtrlDel  = $0600;  kbIns      = $5200;
  kbCtrlEnd  = $7500;  kbLeft     = $4B00;
  kbCtrlEnter= $1C0A;  kbNoKey    = $0000;
  kbCtrlHome = $7700;  kbPgDn     = $5100;
  kbCtrlIns  = $0400;  kbPgUp     = $4900;
  kbCtrlLeft = $7300;  kbGrayPlus = $4E2B;
  kbCtrlPgDn = $7600;  kbRight    = $4D00;
  kbCtrlPgUp = $8400;  kbShiftDel = $0700;
  kbCtrlPrtSc= $7200;  kbShiftIns = $0500;
  kbCtrlRight= $7400;  kbShiftTab = $0F00;
  kbDel      = $5300;  kbTab      = $0F09;
  kbDown     = $5000;  kbUp       = $4800;

 {kbXXXX Alt-Number Key Codes}

  kbAlt1     = $7800;   kbAlt6    = $7D00;
  kbAlt2     = $7900;   kbAlt7    = $7E00;
  kbAlt3     = $7A00;   kbAlt8    = $7F00;
  kbAlt4     = $7B00;   kbAlt9    = $8000;
  kbAlt5     = $7C00;   kbAlt0    = $8100;

 {kbXXXX Function Key Codes}

  kbF1       = $3B00;   kbF6      = $4000;
  kbF2       = $3C00;   kbF7      = $4100;
  kbF3       = $3D00;   kbF8      = $4200;
  kbF4       = $3E00;   kbF9      = $4300;
  kbF5       = $3F00;   kbF10     = $4400;

 {kbXXXX Shift-Function Key Codes}

  kbShiftF1  = $5400;   kbShiftF6 = $5900;
  kbShiftF2  = $5500;   kbShiftF7 = $5A00;
  kbShiftF3  = $5600;   kbShiftF8 = $5B00;
  kbShiftF4  = $5700;   kbShiftF9 = $5C00;
  kbShiftF5  = $5800;   kbShiftF10= $5D00;

 {kbXXXX Ctrl-Function Key Codes}

  kbCtrlF1   = $5E00;   kbCtrlF6  = $6300;
  kbCtrlF2   = $5F00;   kbCtrlF7  = $6400;
  kbCtrlF3   = $6000;   kbCtrlF8  = $6500;
  kbCtrlF4   = $6100;   kbCtrlF9  = $6600;
  kbCtrlF5   = $6200;   kbCtrlF10 = $6700;

 {kbXXXX Alt-Function Key Codes}

  kbAltF1    = $6800;   kbAltF6   = $6D00;
  kbAltF2    = $6900;   kbAltF7   = $6E00;
  kbAltF3    = $6A00;   kbAltF8   = $6F00;
  kbAltF4    = $6B00;   kbAltF9   = $7000;
  kbAltF5    = $6C00;   kbAltF10  = $7100;




FUNCTION  KbdKeyPressed : BOOLEAN; { TRUE if there is a key waiting.                }
FUNCTION  KbdReadKey    : WORD;    { Waits for a key and returns ASCII in the lower }
                                   { byte and scan code in the higher byte.         }
PROCEDURE KbdFlush;                { Flushes the keyboard buffer.                   }




IMPLEMENTATION

VAR
  KbHead : WORD ABSOLUTE 0:$41A; 
  KbTail : WORD ABSOLUTE 0:$41C; { Keyboard buffer indexes in the ROM BIOS data area. }




{----------------------------------------------------------------------------}
{ Exported routines.                                                         }
{____________________________________________________________________________}


FUNCTION KbdKeyPressed : BOOLEAN; ASSEMBLER;
  ASM
        XOR     AX,AX
        MOV     ES,AX
        MOV     AX,[ES:KbHead]
        SUB     AX,[ES:KbTail]
        JZ      @@1
         MOV    AX,1
@@1:
        STI
  END;


FUNCTION KbdReadKey : WORD; ASSEMBLER;
  ASM
        XOR     AX,AX
        INT     $16
  END;


PROCEDURE KbdFlush;
  BEGIN
    KbHead := KbTail;
  END;




END.
