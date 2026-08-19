{****************************************************************************}
{                                                                            }
{ MODULE:         VTCfg                                                      }
{                                                                            }
{ DESCRIPTION:    Implements the reading of the VT.CFG configuration file.   }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        17-Oct-1992 Documentation                                  }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT VTCfg;

{$I-}

INTERFACE

USES Dos,
     VTGlobal,
     PlayMod, ModCommands, SongElements,
     SoundDevices, DevSpkr, DevSB, DevDAC, GUS,
     Vid43, SoundBlaster, SwapStream;




PROCEDURE ReadConfiguration(FName: PathStr); { Read and interpretate the file as a configuration file. }




IMPLEMENTATION


VAR
  ConfFile : TEXT;   { Open configuration file.      }
  Line     : STRING; { Last line read from the file. }




{----------------------------------------------------------------------------}
{ Miscelaneous string handling routines.                                     }
{____________________________________________________________________________}


{ KillSpaces. Deletes the blanks from the beginning and end of the string. }

PROCEDURE KillSpaces(VAR s: STRING);
  CONST
    ValidBlanks = [' ', #9, #0, #255];
  BEGIN
    WHILE (Length(s) > 0) AND (s[1]         IN ValidBlanks) DO
      s := COPY(s, 2, 255);
    WHILE (Length(s) > 0) AND (s[Length(s)] IN ValidBlanks) DO
      DEC(s[0]);
  END;


{ NotInStr. Returns TRUE if the first parameter doesn't contain the second
            at the beginning.                                              }

FUNCTION NotInStr(s, ss: STRING) : BOOLEAN;
  VAR
    i : WORD;
  BEGIN
    NotInStr := TRUE;
    IF Length(ss) > Length(s) THEN EXIT;
    FOR i := 1 TO Length(ss) DO
      IF UpCase(s[i]) <> UpCase(ss[i]) THEN EXIT;
    NotInStr := FALSE;
  END;




{----------------------------------------------------------------------------}
{ Routines for reading different data types They all assume that 'Line'      }
{ contains a string in the format "<Identifier> = <value>".                  }
{ Their names ar self-explicative.                                           }
{____________________________________________________________________________}


FUNCTION GetString(VAR st: STRING; ml: WORD) : BOOLEAN;
  VAR
    s     : STRING;
    s1    : STRING;
    i, j,
    k, l  : LONGINT;
  BEGIN
    i := Pos('=', Line) + 1;

    s := Copy(Line, i, 255);
    KillSpaces(s);

    s1 := '';
    WHILE Length(s) > 0 DO
        IF s[1] = '''' THEN
          BEGIN
            s  := Copy(s, 2, 255);
            i  := Pos('''', s);
            IF i = 0 THEN i := 254;
            s1 := s1 + Copy(s, 1, i-1);
            IF (Length(s) > i) AND (s[i+1] = '''') THEN
              s1 := s1 + '''';
            s := Copy(s, i+1, 255);
            IF Pos('''', s) = 0 THEN s := '';
          END
        ELSE
          BEGIN
            j := Pos(';', s);
            k := Pos(':', s); IF (k <> 0) AND (j > k) THEN j := k;
            k := Pos('#', s); IF (k <> 0) AND (j > k) THEN j := k;
                                 IF  j =  0           THEN j := Length(s) + 1;
            s1 := Copy(s, 1, j-1);
            KillSpaces(s1);
            s := ''
          END;

    IF Length(s1) > ml THEN s1[0] := CHAR(ml);
    st := s1;
    GetString := TRUE;
  END;


FUNCTION GetBool(VAR b: BOOLEAN) : BOOLEAN;
  VAR
    s       : STRING;
  BEGIN
    GetBool := FALSE;
    IF NOT GetString(s, SIZEOF(s) - 1) THEN EXIT;
    IF (NOT NotInStr(s, 'S'    )) OR
       (NOT NotInStr(s, 'Y'    )) OR
       (NOT NotInStr(s, 'OUI'  )) OR
       (NOT NotInStr(s, 'DA'   )) OR
       (NOT NotInStr(s, 'POR'  )) OR
       (NOT NotInStr(s, 'TAMB' )) OR
       (NOT NotInStr(s, 'ALSO' )) OR
       (NOT NotInStr(s, 'TRUE' )) OR
       (NOT NotInStr(s, 'VERD' )) OR
       (NOT NotInStr(s, 'CIER' )) OR
       (NOT NotInStr(s, '1'    )) THEN
      BEGIN
        b       := TRUE;
        GetBool := TRUE;
      END
    ELSE IF (NOT NotInStr(s, 'N'     )) OR
            (NOT NotInStr(s, 'PAS'   )) OR
            (NOT NotInStr(s, 'TAMP'  )) OR
            (NOT NotInStr(s, 'FALS'  )) OR
            (NOT NotInStr(s, '0'     )) THEN
      BEGIN
        b       := FALSE;
        GetBool := TRUE;
      END;
  END;


FUNCTION GetPath(VAR p: PathStr) : BOOLEAN;
  BEGIN
    GetPath := FALSE;
    IF NOT GetString(p, SIZEOF(p) - 1) THEN EXIT;
    p := FExpand(p);
    GetPath := TRUE;
  END;


FUNCTION GetNum(VAR b: LONGINT) : BOOLEAN;
  TYPE
    LP = ^LONGINT;
  VAR
    s       : STRING;
    i, j, k : LONGINT;
  BEGIN
    i := Pos('=', Line) + 1;
    j := Pos(';', Line);
    k := Pos(':', Line); IF (k <> 0) AND (j > k) THEN j := k;
    k := Pos('#', Line); IF (k <> 0) AND (j > k) THEN j := k;
                         IF               j = 0  THEN j := Length(Line) + 1;
    s := Copy(Line, i, j-i);
    KillSpaces(s);

    j := 1;

    IF (Length(s) > 3) AND (s[1] = '[') THEN
      BEGIN
        j := Pos(']', s);
        IF j <> 0 THEN
          BEGIN
            VAL(Copy(s, 2, j-2), i, WORD(j));
            IF j = 0 THEN
              i := LP(Ptr((i AND $F0000) SHR 4, i AND $FFFF))^;
          END
        ELSE
          j := 1;
      END
    ELSE
      VAL(s, i, WORD(j));

    IF j <> 0 THEN
      BEGIN
        GetNum := FALSE;
        EXIT;
      END;
    b := i;
    GetNum := TRUE;
  END;


FUNCTION GetWord(VAR b: WORD) : BOOLEAN;
  VAR
    l : LONGINT;
  BEGIN
    IF GetNum(l) THEN
      BEGIN
        b := WORD(l);
        GetWord := TRUE;
      END
    ELSE
      GetWord := FALSE;
  END;


FUNCTION GetByte(VAR b: BYTE) : BOOLEAN;
  VAR
    l : LONGINT;
  BEGIN
    IF GetNum(l) THEN
      BEGIN
        b := BYTE(l);
        GetByte := TRUE;
      END
    ELSE
      GetByte := FALSE;
  END;




{----------------------------------------------------------------------------}
{ Routines that implement the actual interpretation of the identifiers.      }
{ One routine for each section.                                              }
{____________________________________________________________________________}

TYPE
  Proc = PROCEDURE;


{ DoSectSB. [VT-SBlaster] (Sound Blaster) section. }

PROCEDURE DoSectSB; FAR;
  BEGIN
    IF NOT NotInStr(Line, 'IRQ'         ) THEN GetWord(SbIrq);
    IF NOT NotInStr(Line, 'Port'        ) THEN GetWord(SbPort);
    IF NOT NotInStr(Line, 'DMA'         ) THEN GetWord(SbDMAChan);
    IF NOT NotInStr(Line, 'SbSplTimeout') THEN GetWord(SbSplTimeout);
    IF NOT NotInStr(Line, 'HiSpeedDMA'  ) THEN GetBool(SbHiSpeed);
  END;


{ DoSectGUS. [VT-GUS] (Ultrasound) section. }

PROCEDURE DoSectGUS; FAR;
  BEGIN
    IF NOT NotInStr(Line, 'Port'        ) THEN GetWord(GUSPort);
    IF NOT NotInStr(Line, 'IRQ'         ) THEN GetWord(GUSIrq);
  END;


{ DoSectSBPro. [VT-SBPro] (Sound Blaster Pro) section. }

PROCEDURE DoSectSBPro; FAR;
  BEGIN
    IF NOT NotInStr(Line, 'MasterVol'   ) THEN GetByte(SbProMixMasterVol);
    IF NOT NotInStr(Line, 'DACVol'      ) THEN GetByte(SbProMixDACVol);
    IF NOT NotInStr(Line, 'FMVol'       ) THEN GetByte(SbProMixFMVol);
    IF NOT NotInStr(Line, 'Filter'      ) THEN GetBool(SbProMixFilter);
  END;


{ DoSectDAC. [VT-DAC] section. }

PROCEDURE DoSectDAC; FAR;
  BEGIN
    IF NOT NotInStr(Line, 'Port' ) THEN GetWord(DACPort);
    IF NOT NotInStr(Line, 'LPort') THEN GetWord(LDACPort);
    IF NOT NotInStr(Line, 'RPort') THEN GetWord(RDACPort);
  END;


{ DoSectPlayMod. [VT-PlayMod] section }

PROCEDURE DoSectPlayMod; FAR;
  BEGIN
    IF NOT NotInStr(Line, 'PermitFade'  ) THEN GetBool(PermitFade);
    IF NOT NotInStr(Line, 'FadeSpeed'   ) THEN GetWord(FadeIncr);
    IF NOT NotInStr(Line, 'LoopMod'     ) THEN GetBool(VTLoopMod);
    IF NOT NotInStr(Line, 'ForceLoopMod') THEN GetBool(ForceLoopMod);
    IF NOT NotInStr(Line, 'ShellLoopMod') THEN GetBool(ShellLoopMod);
    IF NOT NotInStr(Line, 'SampleFreq'  ) THEN GetWord(DesiredHz);
    IF NOT NotInStr(Line, 'TicksPerSec' ) THEN GetWord(TicksPerSecond);
    IF NOT NotInStr(Line, 'ShellFreq'   ) THEN GetWord(ShellHz);
    IF NOT NotInStr(Line, 'MaxFreq'     ) THEN GetWord(MaxOutputFreq);
    IF NOT NotInStr(Line, 'Volume'      ) THEN GetByte(VtVolume);
    IF NOT NotInStr(Line, 'Device'      ) THEN GetString(DevID, SIZEOF(DevID) - 1);
    IF NOT NotInStr(Line, 'FilterOn'    ) THEN GetByte(BYTE(FilterOn));
    IF NOT NotInStr(Line, 'FilterOff'   ) THEN GetByte(BYTE(FilterOff));
    IF NOT NotInStr(Line, 'FilterIsOn'  ) THEN GetBool(FilterIsOn);
    IF NOT NotInStr(Line, 'CanFallBack' ) THEN GetBool(CanFallBack);
    IF NOT NotInStr(Line, 'FilterChange') THEN GetBool(PermitFilterChange);
    IF NOT NotInStr(Line, 'BassFilter'  ) THEN GetBool(DoBassPower);
    IF NOT NotInStr(Line, 'DMAOffset'   ) THEN GetWord(DMAOffset);
    IF NOT NotInStr(Line, 'LowQuality'  ) THEN GetBool(LowQuality);
    IF NOT NotInStr(Line, 'Volume'      ) THEN GetByte(VtVolume);
  END;


{ DoSectDAC. [VT-Misc] section. }

PROCEDURE DoSectMisc; FAR;
  BEGIN
    IF NOT NotInStr(Line, 'ShellPath'  ) THEN GetPath  (ShellPath);
    IF NOT NotInStr(Line, 'ShellParams') THEN GetString(ShellParam,   SIZEOF(ShellParam)   - 1);
    IF NOT NotInStr(Line, 'Language')    THEN GetPath  (StringsFName);
    IF NOT NotInStr(Line, 'ModPath')     THEN GetPath  (ModPath);
    IF NOT NotInStr(Line, 'TmpPath')     THEN GetPath  (SwapPrimPath);
  END;


{ DoSectDAC. [VT-Screen] section. }

PROCEDURE DoSectScreen; FAR;
  BEGIN
    IF NOT NotInStr(Line, 'ForceEGA') THEN GetBool(ForceEGA);
  END;


{ DoSectGeneric. Generic section interpreter. It calls one of the above. }

PROCEDURE DoSectGeneric(Offs: WORD); FAR;
  VAR
    DoSect : POINTER;
  BEGIN
    DoSect := Ptr(SEG(DoSectGeneric), Offs);
    WHILE NOT EoF(ConfFile) DO
      BEGIN
        ReadLn(ConfFile, Line);
        KillSpaces(Line);
        IF (Length(Line) > 0) THEN
          BEGIN
            IF (Line[1] = '[') THEN EXIT;
            IF (Line[1] <> ';') AND
               (Line[1] <> ':') AND
               (Line[1] <> '#') THEN
              ASM

                        CALL    [DoSect];
              END;
          END;
      END;
  END;


{ Sections definitions. }

TYPE
  SectProc = PROCEDURE;

CONST
  NumSects = 7;                                 { Number of controlled sections. }
  SectList : ARRAY[1..NumSects] OF RECORD       { List of controlled sections.   }
                                    Proc : WORD;
                                    Name : STRING[16];
                                  END =  
    ( ( Proc:OFS(DoSectSB);      Name:'[VT-SBlaster]' ) ,
      ( Proc:OFS(DoSectGUS);     Name:'[VT-GUS]'      ) ,
      ( Proc:OFS(DoSectSBPro);   Name:'[VT-SBPro]'    ) ,
      ( Proc:OFS(DoSectPlayMod); Name:'[VT-PlayMod]'  ) ,
      ( Proc:OFS(DoSectDAC);     Name:'[VT-DAC]'      ) ,
      ( Proc:OFS(DoSectMisc);    Name:'[VT-Misc]'     ) ,
      ( Proc:OFS(DoSectScreen);  Name:'[VT-Screen]'   )
    );




{----------------------------------------------------------------------------}
{ Configuration reader's main loop.                                          }
{____________________________________________________________________________}


{ FindNextSect. Skips until the beginning of the next section. }

PROCEDURE FindNextSect;
  BEGIN
    WHILE NOT EoF(ConfFile) DO
      BEGIN
        ReadLn(ConfFile, Line);
        KillSpaces(Line);
        IF (Length(Line) > 0) AND (Line[1] = '[') THEN EXIT;
      END;
  END;


{ ReadConfiguration. Configuration reader. Main loop. }

PROCEDURE ReadConfiguration(FName: PathStr);
  VAR
    i    : WORD;
    Good : BOOLEAN;
  BEGIN
    Assign(ConfFIle, FName);
    i := FileMode;
    FileMode := 0;
    Reset(ConfFile);
    FileMode := i;
    IF IOResult <> 0 THEN EXIT;

    WHILE NOT EoF(ConfFile) DO
      BEGIN
        FindNextSect;
        Good := TRUE;
        WHILE (Good)              AND
              (NOT EoF(ConfFile)) AND
              (Length(Line) <> 0) AND
              (Line[1] = '[')     DO
          BEGIN
            Good := FALSE;
            FOR i := 1 TO NumSects DO
              IF NOT NotInStr(SectList[i].Name, Line) THEN
                BEGIN
                  DoSectGeneric(SectList[i].Proc);
                  Good := TRUE;
                END;
          END;
      END;

    Close(ConfFile);
  END;




{----------------------------------------------------------------------------}
{ Unit initialization code. It reads two configuration files:                }
{   1st. - A file named like the executable, but with the extension .CFG, in }
{          the same directory as the executable.                             }
{   2nd. - A file named VT.CFG in the current directory.                     }
{                                                                            }
{ The changes read from the second file may overwrite those read from the    }
{ first.                                                                     }
{____________________________________________________________________________}

VAR
  Path : PathStr;
  Name : NameStr;
  Ext  : ExtStr;

BEGIN

  Path := ParamStr(0);          { Executable's full pathname. }
  FSplit(Path, VTDir, Name, Ext);
  IF Name <> 'VT' THEN
    BEGIN
      ReadConfiguration(VTDir+'VT.CFG');
      ReadConfiguration('VT.CFG');
    END;

  ReadConfiguration(VTDir+Name+'.CFG');
  ReadConfiguration(Name+'.CFG');

END.
