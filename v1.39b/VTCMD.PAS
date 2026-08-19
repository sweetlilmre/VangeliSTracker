UNIT VTCmd;

INTERFACE

USES Dos, Objects,
     SoundDevices, DevGus,
     CmdLine;




TYPE
  TDoOneProc = FUNCTION(FName, InsidePath: PathStr) : BOOLEAN;

CONST
  OneModPtr  : POINTER = NIL;
VAR
  OneMODProc : TDoOneProc ABSOLUTE OneModPtr;

TYPE
  TCmdOptions =
    RECORD
      LowQuality : BOOLEAN;
      DevID      : TDevID;
      Freq       : WORD;
      Volume     : WORD;
    END;

  TVTCmdSwitch =
    OBJECT(TCmdLineInterpreter)
      PROCEDURE CmdInitShell     (Shell: STRING);        VIRTUAL;
      PROCEDURE InterpretSwitch  (Token: TCmdLine);      VIRTUAL;
      PROCEDURE GetCmdOptions    (VAR Opt: TCmdOptions); VIRTUAL;
      PROCEDURE SetCmdOptions    (VAR Opt: TCmdOptions); VIRTUAL;
    END;

  TVTCmd =
    OBJECT(TVTCmdSwitch)
      PROCEDURE InterpretNoSwitch(Token: TCmdLine); VIRTUAL;
    END;

VAR
  Cmd      : TVTCmd;
  SongColl : TStringCollection;




PROCEDURE SetVTFreq;
PROCEDURE SetVTDevice;

FUNCTION DoSongColl(Path: PathStr) : BOOLEAN;




IMPLEMENTATION

USES VTGlobal, VTScreens,
     SongUnit, SongElements,
     PlayMod, SoundBlaster, Gus,
     FileUtil;




{ -------------------------------------------------------------------------- }

CONST
  DeviceSet : BOOLEAN = FALSE;

PROCEDURE SetVTDevice;
  BEGIN
    IF DeviceSet THEN EXIT;

    DevPtr := LocateDevice(DevID);

    UsingGUS := FALSE;

    IF (DevPtr = NIL) OR NOT DevPtr^.Autodetect THEN
      DevPtr := LocateDevice(GUSDevID);

    SetDevice(DevPtr);
  END;


PROCEDURE SetVTFreq;
  BEGIN
    ChangeSamplingRate(DesiredHz);
  END;

{ -------------------------------------------------------------------------- }

FUNCTION DoAllMODs(DefaultPath: PathStr; Path: PathStr; DoOne: TDoOneProc) : BOOLEAN;
  CONST
    NumExts = 6;
    Exts : ARRAY[0..NumExts] OF ExtStr =
      (
        '.123',

        '.MOD', '.STX', '.WOW', '.OKT', '.S?M', '.669'
      );

    Dirs : ARRAY[0..3] OF PathStr =
      (
        '',
        '',
        '',
        ''
      );
  VAR
    InsidePath : PathStr;
    Dir        : DirStr;
    Name       : NameStr;
    Ext        : ExtStr;
    DirIdx,
    DirF,
    DirL       : WORD;
    ExtF,
    ExtL       : WORD;
    i, j       : WORD;
    SearchR    : SearchRec;
  LABEL
    Sigue;
  BEGIN
    DoAllMODs := TRUE;

    i := Pos('/', Path);
    IF i > 0 THEN
      BEGIN
        InsidePath := Copy(Path, i+1, 255);
        Path       := Copy(Path, 1,   i-1);
      END
    ELSE
      InsidePath := '';

    FSplit(Path, Dir, Name, Ext);
    IF Dir <> '' THEN
      BEGIN
        Dirs[0] := FExpand(Dir);
        AddBar2Path(Dirs[0]);
        DirF    := 0;
        DirL    := 0;
      END
    ELSE
      BEGIN
        Dirs[3] := FExpand(ModPath);
        AddBar2Path(Dirs[3]);

        DefaultPath := FExpand(DefaultPath);
        AddBar2Path(DefaultPath);
        Dirs[1] := DefaultPath;

        DirF := 1;
        DirL := 3;
      END;

    Path := FExpand(Path);
    FSplit(Path, Dir, Name, Ext);

    IF DirF > 0 THEN
      BEGIN
        Dirs[2] := Dir;

        FOR DirIdx := DirL DOWNTO 2 DO
          BEGIN
            FOR i := DirF TO DirIdx - 1 DO
              IF Dirs[DirIdx] = Dirs[i] THEN
                BEGIN
                  FOR i := DirIdx TO DirL - 1 DO
                    Dirs[i] := Dirs[i+1];
                  DEC(DirL);
                  GOTO Sigue;
                END;
Sigue:
          END;
      END;


    IF Ext <> '' THEN
      BEGIN
        Exts[0] := Ext;
        ExtF    := 0;
        ExtL    := 0;
      END
    ELSE
      BEGIN
        ExtF := 1;
        ExtL := NumExts;
      END;

    Path := Dir + Name;



    { Loop for all MODs. }

    DoAllMODs := FALSE;

    FOR j := DirF TO DirL DO
      FOR i := ExtF TO ExtL DO
        BEGIN
          FindFirst(Dirs[j]+Name+Exts[i], ReadOnly, SearchR);

          WHILE DosError = 0 DO
            BEGIN
              IF NOT DoOne(Dirs[j] + SearchR.Name, InsidePath) THEN EXIT;

              FindNext(SearchR);
            END;
        END;

    DoAllMODs := TRUE;
  END;


{ -------------------------------------------------------------------------- }




PROCEDURE CmdInitDevice(s: STRING);
  BEGIN
    IF s = '' THEN EXIT;

    DevID := s;

    SetVTDevice;
  END;




PROCEDURE CmdInitFreq(s: STRING);
  VAR
    i, r : WORD;
  BEGIN
    IF s = '' THEN EXIT;

    VAL(s, i, r);
    VAL(s, i, r);
    IF r = 0 THEN
      DesiredHz := i;
  END;




PROCEDURE CmdInitVolume(s: STRING);
  VAR
    i, r : WORD;
  BEGIN
    IF s = '' THEN EXIT;

    VAL(s, i, r);
    IF r = 0 THEN
      BEGIN
        IF i > 255 THEN i := 255;
        VTVolume := i;
      END;
  END;

PROCEDURE CmdLoopMod(f: BOOLEAN);
  BEGIN
    VTLoopMod := f;
  END;


PROCEDURE CmdForceLoop(f: BOOLEAN);
  BEGIN
    ForceLoopMod := f;
  END;


PROCEDURE CmdLowQuality(f: BOOLEAN);
  BEGIN
    LowQuality := f;
  END;


PROCEDURE CmdBassFilter(f: BOOLEAN);
  BEGIN
    DoBassPower := f;
  END;


PROCEDURE CmdInit1stSong(s: STRING);
  VAR
    i : WORD;
  BEGIN
    FOR i := 1 TO Length(s) DO
      s[i] := UpCase(s[i]);

    FirstSong := s;
  END;


PROCEDURE CmdInit1stPattern (s: STRING);
  VAR
    i, r : WORD;
  BEGIN
    IF s = '' THEN EXIT;

    VAL(s, i, r);
    IF r = 0 THEN
      VT1stPattern := i;
  END;


PROCEDURE CmdInitSongLen    (s: STRING);
  VAR
    i, r : WORD;
  BEGIN
    IF s = '' THEN EXIT;

    VAL(s, i, r);
    IF r = 0 THEN
      VTSongLen := i;
  END;


PROCEDURE CmdInitRepStart   (s: STRING);
  VAR
    i, r : WORD;
  BEGIN
    IF s = '' THEN EXIT;

    VAL(s, i, r);
    IF r = 0 THEN
      VTRepStart := i;
  END;


PROCEDURE CmdSetPort(s: STRING);
  VAR
    i, r : WORD;
  BEGIN
    IF s = '' THEN EXIT;

    VAL(s, i, r);
    IF r = 0 THEN
      BEGIN
        SbPort  := i;
        GusPort := i;
      END;
  END;


PROCEDURE CmdSetIRQ(s: STRING);
  VAR
    i, r : WORD;
  BEGIN
    IF s = '' THEN EXIT;

    VAL(s, i, r);
    IF r = 0 THEN
      BEGIN
        SbIRQ  := i;
        GusIrq := i;
      END;
  END;


PROCEDURE CmdSetDMA(s: STRING);
  VAR
    i, r : WORD;
  BEGIN
    IF s = '' THEN EXIT;

    VAL(s, i, r);
    IF r = 0 THEN
      SbDMAChan := i;
  END;




PROCEDURE CmdModOffset(s: STRING);
  VAR
    l : LONGINT;
    r : WORD;
  BEGIN
    IF s = '' THEN EXIT;

    VAL(s, l, r);
    IF r = 0 THEN
      ModOffset := l;
  END;




(*
  { Read and initialize Sound Blaster timeout value from command line. }

  IF ParamStr(4) <> '' THEN BEGIN
    VAL(ParamStr(4), i, r);
    SbSplTimeout := i;
  END;



  { Read and initialize Sound Blaster IRQ value from command line. }

  IF ParamStr(5) <> '' THEN BEGIN
    VAL(ParamStr(5), i, r);
    SbIrq := i;
  END;
*)




FUNCTION DoSongColl(Path: PathStr) : BOOLEAN;
  VAR
    i : WORD;
  LABEL
    Fin;
  BEGIN
    DoSongColl := TRUE;
    IF SongColl.Count = 0 THEN EXIT;

    DoSongColl := FALSE;
    FOR i := 0 TO SongColl.Count - 1 DO
      IF NOT DoAllMODs(Path, PString(SongColl.At(i))^, OneMODProc) THEN GOTO Fin;
    DoSongColl := TRUE;

Fin:
    SongColl.FreeAll;
  END;




PROCEDURE TVTCmd.InterpretNoSwitch(Token: TCmdLine);
  BEGIN
    SongColl.AtInsert(SongColl.Count, NewStr(Token));
  END;


PROCEDURE TVTCmdSwitch.CmdInitShell(Shell: STRING);
  VAR
    i, r : WORD;
  BEGIN
    ShellPath  := Shell;
    ShellParam := Copy(Line, Idx, 255);
  END;


PROCEDURE TVTCmdSwitch.InterpretSwitch  (Token: TCmdLine);
  BEGIN

    IF      Token = ''               THEN BEGIN IF NOT DoSongColl(FileDir) THEN Abort; END
    ELSE IF CmpSwitch(Token, 'nobf') THEN CmdBassFilter     (FALSE)
    ELSE IF CmpSwitch(Token, 'bfil') THEN CmdBassFilter     (TRUE)
    ELSE IF CmpSwitch(Token, 'nolp') THEN CmdLoopMod        (FALSE)
    ELSE IF CmpSwitch(Token, 'loop') THEN CmdLoopMod        (TRUE)
    ELSE IF CmpSwitch(Token, 'nofl') THEN CmdForceLoop      (FALSE)
    ELSE IF CmpSwitch(Token, 'frst') THEN CmdInit1stSong    (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'port') THEN CmdSetPort        (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'irq' ) THEN CmdSetIRQ         (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'dma' ) THEN CmdSetDMA         (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'off' ) THEN CmdModOffset      (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'flp' ) THEN CmdForceLoop      (TRUE)
    ELSE IF CmpSwitch(Token, 'lq'  ) THEN CmdLowQuality     (TRUE)
    ELSE IF CmpSwitch(Token, 'hq'  ) THEN CmdLowQuality     (FALSE)
    ELSE IF CmpSwitch(Token, 'ss'  ) THEN CmdInit1stPattern (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'sl'  ) THEN CmdInitSongLen    (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'sr'  ) THEN CmdInitRepStart   (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'sh'  ) THEN CmdInitShell      (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'd'   ) THEN CmdInitDevice     (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'f'   ) THEN CmdInitFreq       (TokenParam(Token))
    ELSE IF CmpSwitch(Token, 'v'   ) THEN CmdInitVolume     (TokenParam(Token))
    ;

  END;


PROCEDURE TVTCmdSwitch.GetCmdOptions(VAR Opt: TCmdOptions);
  BEGIN
    Opt.LowQuality := LowQuality;
    Opt.DevID      := DevID;
    Opt.Freq       := DesiredHz;
    Opt.Volume     := VTVolume;

    SetVTDevice;
  END;


PROCEDURE TVTCmdSwitch.SetCmdOptions(VAR Opt: TCmdOptions);
  BEGIN
    LowQuality := Opt.LowQuality;
    DevID      := Opt.DevID;
    DesiredHz  := Opt.Freq;
    VTVolume   := Opt.Volume;

    SetVTDevice;
  END;









END.
