PROGRAM VT;

{$M 30000,20000,655360}

USES CleanHeap,
     SoundDevices,                   { Sound output devices.               }
     {DevSbDAC, DevDAC, DevSB, }DevGUS,{                                     }
     {DevFile, DevAdLib, DevSpkr,}     {                                     }
     VTSpecial,                      { Installation check.                 }
     VTStrConst, StrConst,           { Language support.                   }
     Dos,                            { Standard TP UNITs.                  }
     Objects,                        {                                     }
     VTCfg, VTGlobal, VTCmd,         { VT-Specific UNITs.                  }
     VTWins, VTPlay, VTPartitura,    {                                     }
     VTScreens, VTShell,             {                                     }
     SongUnit, SongElements,         { Song definition UNITs.              }
     SongUtils,                      {                                     }
     PlayMod, Filters, ModCommands,  {                                     }
     SoundBlaster,                   {                                     }
     Vid43, Output43,                { Video routines.                     }
     Kbd, Debugging,                 { Miscelaneous UNITs.                 }
     HexConversions, Mouse,          {                                     }
     CmdLine,                        {                                     }
     Heaps,                          {                                     }
     SwapStream, SwapManager,        {                                     }
     FileUtil;                       {                                     }




VAR
  nt             : TFullNote;
  pp             : PPattern;
  omd,
  md             : TPlayingNote;
  ThereIsNewNote : BOOLEAN;
  EmptySong      : TSong;

CONST
  Funking    : BOOLEAN = FALSE;
  FunkGoesUp : BOOLEAN = FALSE;
  FadingOut  : BOOLEAN = FALSE;
  FadedOut   : BOOLEAN = FALSE;
  FadeCount  : WORD    = 0;
  LastSeq    : BYTE    = 255;

VAR
  Sequences  : ARRAY[1..256] OF BOOLEAN;




{ -------------------------------------------------------------------------- }

FUNCTION IsAConsole(VAR f) : BOOLEAN; ASSEMBLER;
  ASM
                MOV     AX,$4400
                LES     BX,[f]
                MOV     BX,TextRec([ES:BX]).Handle
                INT     $21
                XOR     AX,AX
                TEST    DL,$80
                JZ      @@Fin
                INC     AX
@@Fin:
  END;

FUNCTION RJust(s: STRING; i: WORD) : STRING;
  VAR
    r : STRING;
  BEGIN
    IF i <= Length(s) THEN
      BEGIN
        RJust := s;
        EXIT;
      END;
    r[0] := CHAR(i - Length(s));
    FillChar(r[1], i - Length(s), ' ');
    RJust := r + s;
  END;


FUNCTION LJust(s: STRING; i: WORD) : STRING;
  VAR
    r : STRING;
  BEGIN
    IF i <= Length(s) THEN
      BEGIN
        LJust := s;
        EXIT;
      END;
    r[0] := CHAR(i - Length(s));
    FillChar(r[1], i - Length(s), ' ');
    LJust := s + r;
  END;


FUNCTION Char2Str(c: CHAR; n: BYTE) : STRING;
  VAR
    s : STRING;
  BEGIN
    FillChar(s, SIZEOF(s), c);
    s[0] := CHAR(n);
    Char2Str := s;
  END;


PROCEDURE MyWriteLn(s: STRING);
  CONST
    Linea : WORD = 0;
  BEGIN
    IF ((Linea > 24) OR (s = '')) AND IsAConsole(Output) THEN
      BEGIN
        Write(StdErr, GetString(StrUsagePressAKey));
        KbdReadKey;
        Write(StdErr, #13+Char2Str(' ', 79)+#13);
        Linea := 0;
      END;
    IF s <> '' THEN WriteLn(Output, s);
    INC(Linea);
  END;



PROCEDURE UsagePart(Str: WORD);
  BEGIN
    MyWriteLn(GetString(StrUsageTop));

    WHILE GetString(Str) <> #0 DO
      BEGIN
        IF GetString(Str) = '' THEN
          MyWriteLn(GetString(StrUsageEmpty))
        ELSE
          MyWriteLn(GetString(Str));
        INC(Str);
      END;

    MyWriteLn(GetString(StrUsageBottom));
  END;

PROCEDURE USAGE;
  VAR
    i : WORD;
    p : PSoundDevice;
  BEGIN
    MyWriteLn('                           ÉÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ»');
    MyWriteLn('                           º VangeliSTracker  v'+Version+' º');
    MyWriteLn('                           ÈÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍÍ¼');

    IF Beta THEN
      MyWriteLn('                                    '+BetaStr);

    MyWriteLn(GetString(StrUsageTop));
    MyWriteLn(GetString(StrUsage01));
    MyWriteLn(GetString(StrUsageBottom));

    UsagePart(Strusage1Beg);
    MyWriteLn('');

    UsagePart(Strusage2Beg);
    MyWriteLn('');
    
{    MyWriteLn(GetString(StrUsageTop));}
    UsagePart(StrUsage3Beg);
{
    FOR i := 1 TO NumDevices DO
      BEGIN
        p := IndexDevice(i);
        MyWriteLn(LJust(' ³   '+RJust(p^.DevID+':', SIZEOF(TDevID))+' '+p^.Name, 78)+'³');
      END;
    MyWriteLn(GetString(StrUsageBottom));
}
    MyWriteLn('');

    UsagePart(Strusage4Beg);

    HALT(1);
  END;

{ -------------------------------------------------------------------------- }

PROCEDURE ORROR(s: STRING; Go: BOOLEAN);
  VAR
    OldScr : WORD;
  BEGIN
    QuitaVideoMode43;

    WriteLn('ORROR: ', s);

    IF Go THEN
      HALT(1);

    PoneVideoMode43;
    InitWinF8Demo;
    OldScr := ActiveWindows;
    SetUser(0);
    SetUser(OldScr);
    RefreshMiscInfo(EmptySong);
  END;

{ -------------------------------------------------------------------------- }

PROCEDURE DoNotes(VAR Song: TSong; VAR note, NewNote, L2ndForz: BOOLEAN);
  CONST
    i     : WORD     = 0;
    PSize : WORD     = 0;
    Patt  : PPattern = NIL;
  BEGIN
    IF NewNote THEN BEGIN
      md := NoteSound^;

      PSize := 0;
      Patt := Song.GetPatternSeq(md.SeqPlaying);
      IF (Patt <> NIL) AND (Patt^.Patt <> NIL) THEN
        PSize := Patt^.Patt^.NNotes;

      UpdateRunInfo(BPMIncrement, md.Tempo, Song.GetPatternSequence(md.SeqPlaying), md.NotePlaying, md.SeqPlaying, PSize);

      w2ndLine.forz := L2ndForz;


      FOR i := 1 TO Song.NumChannels DO BEGIN
        Song.GetNote(md.SeqPlaying, md.NotePlaying, i, nt);

        UpdateNoteInfo  (Song, nt, i);
        UpdateSampleInfo(Song, nt, i);
        ParseBarInit    (nt, i);
      END;


      IF (md.SeqPlaying <= 256) AND (LastSeq <> md.SeqPlaying) THEN
        BEGIN
          IF (NOT VTLoopMod) AND Sequences[md.SeqPlaying] THEN
            FadingOut := TRUE;

          Sequences[md.Seqplaying] := TRUE;
          LastSeq := md.SeqPlaying;
        END;

      NewNote  := FALSE;
      L2ndForz := FALSE;
    END;

    Update2ndLine(Song, note);
    TickSampleInfo;
  END;


CONST
  StkSize = 500;
VAR
  Stack1 : ARRAY[1..StkSize] OF BYTE;

PROCEDURE TickProc(VAR Song: TSong; note: BOOLEAN); FAR;
  CONST
    Semaphor  : BYTE    = 0;
    Semaphor2 : BYTE    = 0;
    Semaphor3 : BYTE    = 0;
    Semaphor4 : BYTE    = 0;
    NewNote   : BOOLEAN = FALSE;
    L2ndForz  : BOOLEAN = FALSE;
    Count     : BYTE    = 0;
    i         : WORD    = 0;
    j         : WORD    = 0;
    k         : WORD    = 0;
    SS_1      : WORD    = 0;
    SP_1      : WORD    = 0;
    SongP     : PSong   = NIL;
    noteP     : BOOLEAN = FALSE;
  BEGIN

    IF (NOT Playing) AND (Semaphor4 = 0) THEN
      BEGIN
        INC(Semaphor4);
        UpdateBars;
{
        FillChar(nt, SIZEOF(nt), 0);
        FOR i := 1 TO ModUnit.NumChannels DO
          UpdateSampleInfo(nt, i);
        TickSampleInfo;
}
        DEC(Semaphor4);
        EXIT;
      END;

    IF note THEN BEGIN
      NewNote        := TRUE;
      ThereIsNewNote := TRUE;
    END;

    L2ndForz := L2ndForz OR w2ndLine.forz;

    IF Semaphor = 0 THEN BEGIN
      INC(Semaphor);

      SongP := @Song;
      noteP := note;

       ASM
                MOV     [SS_1],SS
                MOV     [SP_1],SP
                MOV     AX,DS
                MOV     SS,AX
                MOV     SP,OFFSET Stack1 + StkSize
       END;

       DoNotes(SongP^, noteP, NewNote, L2ndForz);

       ASM
                MOV     SS,[SS_1]
                MOV     SP,[SP_1]
       END;

      DEC(Semaphor);
    END;

    UpdateOscilloscInfo;

    IF Semaphor2 = 0 THEN
      BEGIN
        INC(Semaphor2);
        IF Funking THEN
          ASM
{
                MOV     DX,$3DA
@@lp1:           IN     AL,DX
                 AND    AL,8
                 JZ     @@lp1

                MOV     DX,$3D4
                MOV     AL,$18
                MOV     AH,[Count]
                OUT     DX,AX

                MOV     DL,[FunkGoesUp]
@@otra:         AND     DL,DL
                JZ      @@down
                 DEC    AH
                JMP     @@up
@@down:          INC    AH
@@up:           AND     AH,AH
                JNZ     @@ya
                 AND    DL,1
                 XOR    DL,1
                 MOV    [FunkGoesUp],DL
                 JMP    @@otra
@@ya:           MOV     [Count],AH
}
          END;
        DEC(Semaphor2);
      END;

    IF (FadingOut) AND (Semaphor3 = 0) THEN
      BEGIN
        INC(Semaphor3);
        IF NOT PermitFade THEN
          FadedOut := TRUE
        ELSE
          BEGIN
            INC(FadeCount, FadeIncr);
            FOR j := 1 TO HI(FadeCount) DO
              BEGIN
                FadedOut := TRUE; 
                FOR k := 1 TO MaxChannels DO
                  IF UserVols[k] > 0 THEN
                    BEGIN
                      DEC(UserVols[k]);
                      FadedOut := FALSE;
                    END;
              END;
            FadeCount := LO(FadeCount);
          END;
        DEC(Semaphor3);
      END;
  END;

{ -------------------------------------------------------------------------- }

PROCEDURE OsShell;
  VAR
    OldScr  : WORD;
    OldHz   : WORD;
    OldLMod : BOOLEAN;
    OldVMod : BOOLEAN;
    OldFall : BOOLEAN;
    i       : WORD;
    HeapSize: LONGINT;
  BEGIN
    OldFall       := MyCanFallBack;
    OldScr        := ActiveWindows;
    OldVMod       := VTLoopMod;
    OldLMod       := MyLoopMod;
    OldHz         := DesiredHz;

    MyCanFallBack := FALSE;
    VTLoopMod     := TRUE;
    MyLoopMod     := TRUE;

    SetNothing;
    QuitaVideoMode43;
    IF DesiredHz > ShellHz THEN
      DesiredHz := ShellHz;
    ChangeSamplingRate(DesiredHz);

    WriteLn('Type EXIT to return to VangeliSTracker');

    HeapSize := Heap.HTotalAvail;
    ShrinkSystemHeap(0);
    SwapVectors;
    Exec(ShellPath, ShellParam);
    SwapVectors;
    ShrinkSystemHeap(HeapSize);

{FOR i := 1 TO 50000 DO;}

    ChangeSamplingRate(OldHz);
    PoneVideoMode43;
    InitWinF8Demo;
    SetUser(OldScr);
    RefreshMiscInfo(PlayingSong^);
    HideMouse;
    MOUReset(FALSE);
    ShowMouse;
    MyLoopMod   := OldLMod;
    VTLoopMod   := OldVMod;
    MyCanFallBack := OldFall;
  END;



PROCEDURE WindowShell;
  VAR
    OldScr  : WORD;
    OldHz   : WORD;
    OldLMod : BOOLEAN;
    OldVMod : BOOLEAN;
    OldFall : BOOLEAN;
    i       : WORD;
  BEGIN
    OldFall       := MyCanFallBack;
    OldScr        := ActiveWindows;
    OldVMod       := VTLoopMod;
    OldLMod       := MyLoopMod;
    OldHz         := DesiredHz;

    MyCanFallBack := FALSE;
    VTLoopMod     := TRUE;
    MyLoopMod     := TRUE;

    IF DesiredHz > ShellHz THEN
      DesiredHz := ShellHz;
    ChangeSamplingRate(DesiredHz);

    DoWindowShell;

    ChangeSamplingRate(OldHz);
    SetUser(OldScr);
    RefreshMiscInfo(PlayingSong^);
    MyLoopMod   := OldLMod;
    VTLoopMod   := OldVMod;
    MyCanFallBack := OldFall;
  END;



PROCEDURE DoFunk;
  CONST
    f : BOOLEAN = FALSE;
  BEGIN

    IF NOT f THEN
      ASM

          MOV     DX,$3D4

          MOV     AL,9
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          AND     AL,$BF
          OUT     DX,AL
          DEC     DX

          MOV     AL,$11
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          AND     AL,$7F
          OUT     DX,AL
          DEC     DX

          MOV     AL,7
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          AND     AL,$EF
          OUT     DX,AL
          DEC     DX

          MOV     AL,$18
          MOV     AH,8*23 - 1
          OUT     DX,AX

      END
    ELSE
      ASM

          MOV     DX,$3D4

          MOV     AL,9
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          OR      AL,$40
          OUT     DX,AL
          DEC     DX

          MOV     AL,7
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          OR      AL,$10
          OUT     DX,AL
          DEC     DX

          MOV     AL,$11
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          OR      AL,$80
          OUT     DX,AL
          DEC     DX

      END;

    f := NOT f;

  END;

{
PROCEDURE DoFunk;
  CONST
    f : BOOLEAN = FALSE;
  BEGIN

    IF NOT f THEN
      BEGIN
        ASM

          MOV     DX,$3D4

          MOV     AL,9
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          AND     AL,$BF
          OUT     DX,AL
          DEC     DX

          MOV     AL,$11
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          AND     AL,$7F
          OUT     DX,AL
          DEC     DX

          MOV     AL,7
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          AND     AL,$EF
          OUT     DX,AL
          DEC     DX

          MOV     AL,$18
          MOV     AH,8*11 - 1
          OUT     DX,AX

      END
    ELSE
      ASM

          MOV     DX,$3D4

          MOV     AL,9
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          OR      AL,$40
          OUT     DX,AL
          DEC     DX

          MOV     AL,7
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          OR      AL,$10
          OUT     DX,AL
          DEC     DX

          MOV     AL,$11
          OUT     DX,AL
          INC     DX
          IN      AL,DX
          OR      AL,$80
          OUT     DX,AL
          DEC     DX

      END;

      f := NOT f;

  END;
}
{ -------------------------------------------------------------------------- }

PROCEDURE IncVal(VAR Val: INTEGER; Incr, Min, Max: INTEGER);
  BEGIN
    IF      Val + Incr < Min THEN Val := Min
    ELSE IF Val + Incr > Max THEN Val := Max
    ELSE                          INC(Val, Incr);
  END;


FUNCTION DoPlayMod(VAR Song: TSong) : BOOLEAN;
  CONST
    Puerto  : BYTE = 4;

  PROCEDURE WriteCRTC;
    BEGIN
      DirectWriteAttr(2, 'CRTC:   Reg ' + HexByte(Puerto) + '  val ' + HexByte(Port[$3d5]), $97);
    END;

  PROCEDURE WriteFilt;
    BEGIN
      DirectWriteAttr(182, 'Loudness filter.' +
        '   HI pass: shape ' + HexDigit(TrebleFilterVal_Left) +
           '  amplif ' + HexDigit(TrebleFilterMult_Left)     +
        '   LO pass: shape ' + HexDigit(BassFilterVal_Left)   +
           '  amplif ' + HexDigit(BassFilterMult_Left)       , $97);
    END;

  VAR
    cr   : CHAR;
    ch,
    LastVol,
    LastHz,
    MyHz,
    i, r : WORD;
    s    : STRING;
  BEGIN

    Port[$3d4] := Puerto;

    WriteCRTC;
    WriteFilt;

    ThereIsNewNote := FALSE;

    IF FirstChannel > Song.NumChannels-3 THEN
      FirstChannel := Song.NumChannels-3;

    IF Song.NumChannels <= 4 THEN
      FirstChannel := 1;

    DrawPartiture(Song, 0, 0);

    ModTickProc      := TickProc;
    ModTickProcValid := TRUE;

    FadingOut := FALSE;
    FadedOut  := FALSE;

    FillChar(Sequences, SIZEOF(Sequences), FALSE);
    LastSeq := 255;

    FillChar(UserVols, SIZEOF(UserVols), VtVolume);

    LastHz := SoundHz;

{    VTLoopMod := TRUE;}

    FirstPattern := VT1stPattern;
    RepStart     := VTRepStart;
    SongLen      := VTSongLen;

    InitPlayData(Song);
    PlayStart(Song);

    ChangeSamplingRate(DesiredHz);
    RefreshMiscInfo(Song);

    { Adjust looping flag. }

{
    VTLoopMod := MyLoopMod;
    IF (NOT MyLoopMod) AND (Song.SequenceRepStart < Song.SequenceLength) THEN
      MyLoopMod := TRUE;
}
    REPEAT

{
      WHILE NOT KbdKeyPressed DO;
}

      ch := 0;
      cr := #0;
      WHILE KbdKeyPressed DO
        BEGIN
          ch := KbdReadKey;
          cr := UPCASE(CHAR(ch));

          CASE ch OF
            kbPgDn: IF NextSeq < Song.SequenceLength THEN BEGIN
                      Sequences[NextSeq]   := TRUE;
                      Sequences[NextSeq+1] := FALSE;
                      INC(NextSeq);
                    END;
            kbPgUp: IF NextSeq > 1 THEN BEGIN
                      Sequences[NextSeq]   := FALSE;
                      Sequences[NextSeq-1] := FALSE;
                      DEC(NextSeq);
                    END;
            kbHome: BEGIN
                      IF (NextNote < 8) AND (NextSeq > 1) THEN
                        BEGIN
                          Sequences[NextSeq]   := FALSE;
                          Sequences[NextSeq-1] := FALSE;
                          DEC(NextSeq);
                        END;
                      NextNote := 1;
                    END;
            kbEnd:  IF NextSeq < Song.SequenceLength THEN BEGIN
                      Sequences[NextSeq]   := TRUE;
                      Sequences[NextSeq+1] := FALSE;
                      INC(NextSeq);
                      NextNote := 1;
                    END;
    {
            kbLeft: BEGIN
                      DEC(TicksPerSecond);
                    END;
            kbRight:BEGIN
                      INC(TicksPerSecond);
                    END;
    }
            kbLeft: BEGIN
                      IF FirstChannel > 1 THEN
                        BEGIN
                          DEC(FirstChannel);
                          w2ndLine.forz             := TRUE;
                          VTPartitura.PartWin^.forz := TRUE;
                        END;
                    END;
            kbRight:BEGIN
                      IF FirstChannel + 4 <= Song.NumChannels THEN
                        BEGIN
                          INC(FirstChannel);
                          w2ndLine.forz             := TRUE;
                          VTPartitura.PartWin^.forz := TRUE;
                        END;
                    END;
{
            kbDown: BEGIN
                      IF DMAOffset > 0 THEN
                        BEGIN
                          DEC(DMAOffset);
                          HzChanged := TRUE;
                        END;
                    END;
            kbUp:   BEGIN
                      INC(DMAOffset);
                      HzChanged := TRUE;
                    END;
            kbCtrlPgUp: BEGIN
                      INC(Puerto);
                      Port[$3d4] := Puerto;
                      WriteCRTC;
                    END;
            kbCtrlPgDn: BEGIN
                      DEC(Puerto);
                      Port[$3d4] := Puerto;
                      WriteCRTC;
                    END;
}
            kbCtrlLeft: BEGIN
                      Port[$3d4] := Puerto;
                      Port[$3d5] := Port[$3d5] + 1;
                      WriteCRTC;
                    END;
            kbCtrlRight: BEGIN
                      Port[$3d4] := Puerto;
                      Port[$3d5] := Port[$3d5] - 1;
                      WriteCRTC;
                    END;
{
            kbCtrlHome: BEGIN
                      Port[$3d4] := Puerto;
                      WriteCRTC;
                      WriteFilt;
                    END;
            kbF1:   Playing := NOT Playing;
}
            kbF5:   SetBig;
            kbF6:   SetSmall_Samples;
            kbF7:   SetSmall_Oscillosc;
            kbF8:   SetCredits;
{
            kbF9:   DoFunk;
            kbAltA: BEGIN IncVal(INTEGER(TrebleFilterVal_Left),  -1, 0, 15); WriteFilt; END;
            kbAltQ: BEGIN IncVal(INTEGER(TrebleFilterVal_Left),   1, 0, 15); WriteFilt; END;
            kbAltS: BEGIN IncVal(INTEGER(TrebleFilterMult_Left), -1, 0, 15); WriteFilt; END;
            kbAltW: BEGIN IncVal(INTEGER(TrebleFilterMult_Left),  1, 0, 15); WriteFilt; END;
            kbAltD: BEGIN IncVal(INTEGER(BassFilterVal_Left),    -1, 0, 15); WriteFilt; END;
            kbAltE: BEGIN IncVal(INTEGER(BassFilterVal_Left),     1, 0, 15); WriteFilt; END;
            kbAltF: BEGIN IncVal(INTEGER(BassFilterMult_Left),   -1, 0, 15); WriteFilt; END;
            kbAltR: BEGIN IncVal(INTEGER(BassFilterMult_Left),    1, 0, 15); WriteFilt; END;
}
            kbAlt1..kbAlt6:
                    BEGIN
                      i := HI(ch - kbAlt1) + 11;
                      Permisos[i]               := NOT Permisos[i];
                      w2ndLine.forz             := TRUE;
                      VTPartitura.PartWin^.forz := TRUE;
                    END;
          ELSE
            CASE cr OF
{
              'L': DoBassPower := NOT DoBassPower;
}
              'D': OsShell;
              'N': FadingOut := TRUE;
              '1'..'9':
                   BEGIN
                     i := BYTE(cr) - BYTE('0');
                     Permisos[i]               := NOT Permisos[i];
                     w2ndLine.forz             := TRUE;
                     VTPartitura.PartWin^.forz := TRUE;
                   END;
              '0': BEGIN
                     i := 10;
                     Permisos[i]               := NOT Permisos[i];
                     w2ndLine.forz             := TRUE;
                     VTPartitura.PartWin^.forz := TRUE;
                   END;
{
              'F': FilterOn  := TFilterMethod((BYTE(FilterOn)  + 1) MOD FilterMod);
              'G': FilterOff := TFilterMethod((BYTE(FilterOff) + 1) MOD FilterMod);
}
              'W': IF ModCommands.Tempo > 1 THEN
                     DEC(ModCommands.Tempo);
              'E': IF ModCommands.Tempo < $30 THEN
                     INC(ModCommands.Tempo);
              '+': IF (NOT FadingOut) THEN
                     BEGIN
                       IF (VtVolume < 255-9) THEN
                         INC(VtVolume, 9)
                       ELSE
                         VtVolume := 255;
                       FOR i := 1 TO MaxChannels DO UserVols[i] := VtVolume;
                       RefreshMiscInfo(Song);
                     END;
              '-': IF (NOT FadingOut) THEN
                     BEGIN
                       IF (VtVolume > 9) THEN
                         DEC(VtVolume, 9)
                       ELSE
                         VtVolume := 0;
                       FOR i := 1 TO MaxChannels DO UserVols[i] := VtVolume;
                       RefreshMiscInfo(Song);
                     END;
{
              'R': BEGIN
                     MyHz := ActualHz;
                     WHILE (MyHz = ActualHz) AND (MyHz <> ActiveDevice^.GetRealFreqProc(0)) DO
                       BEGIN
                         DEC(DesiredHz, 100);
                         MyHz := ActiveDevice^.GetRealFreqProc(DesiredHz);
                       END;
                     ChangeSamplingRate(DesiredHz);
                     RefreshMiscInfo(Song);
                   END;
              'T': BEGIN
                     MyHz := ActualHz;
                     WHILE (MyHz = ActualHz) AND (MyHz <> ActiveDevice^.GetRealFreqProc(65535))  DO
                       BEGIN
                         INC(DesiredHz, 100);
                         MyHz := ActiveDevice^.GetRealFreqProc(DesiredHz);
                       END;
                     ChangeSamplingRate(DesiredHz);
                     RefreshMiscInfo(Song);
                   END;
}
              'S': BEGIN
                     Playing := NOT Playing;
                   END;
            END;
          END;

        END;

      IF (SoundHz <> LastHz) OR (UserVols[1] <> LastVol) THEN
        BEGIN
          RefreshMiscInfo(Song);
          LastHz  := SoundHz;
          LastVol := UserVols[1];
        END;

      IF ThereIsNewNote THEN
        DrawPartiture(Song, md.NotePlaying, md.SeqPlaying);

      WriteNum( 0, TrebleFilterVal_Left,  10);
      WriteNum(20, TrebleFilterMult_Left, 10);
      WriteNum(40, BassFilterVal_Left,    10);
      WriteNum(60, BassFilterMult_Left,   10);

      PollDevice;

    UNTIL (ch = kbESC) OR FadedOut OR NOT Playing;
    DoPlayMod := ch = kbESC;

    PlayStop;
  END;

{ -------------------------------------------------------------------------- }

VAR
  NoMods : BOOLEAN;

FUNCTION DoOneMOD(FName, InsidePath: PathStr) : BOOLEAN; FAR;
  VAR
    Song    : TSong;
    NoMod   : BOOLEAN;
{
    Cmd     : TVTCmdSwitch;
}
    SwName  : PathStr;
    Dir     : DirStr;
    Name    : NameStr;
    Ext     : ExtStr;

    i       : WORD;
    s       : STRING[2];
  LABEL
    Fin;
  BEGIN
    IF FirstSong <> '' THEN
      BEGIN
        FSplit(FName, Dir, Name, Ext);
        IF FirstSong = Name+Ext THEN
          FirstSong := ''
        ELSE
          BEGIN
            DoOneMod := TRUE;
{
            WriteLn(FName, ' <> ', FirstSong);
}
            EXIT;
          END;
      END;

    NoMods := FALSE;

    NoMod    := TRUE;
    DoOneMOD := FALSE;


    SetVTDevice;
    SetVTFreq;


{
    Cmd.Init;
}
    Song.Init;
    REPEAT
      Song.SetInsidePath(InsidePath);

      IF VT1stPattern <> 0 THEN
        Song.SongStart := VT1stPattern;

      IF VTSongLen <> 0 THEN
        Song.SongLen := VTSongLen;

{      StartSampling;}

      Song.LoadFName(FName);

      IF (Song.Status = msOk) OR (Song.Status = msFileTooShort) THEN
        BEGIN
          NoMod := FALSE;
{
          IF Song.GetInsidePath <> '' THEN
            BEGIN
              FSplit(Song.GetInsidePath, Dir, Name, Ext);
              SwName := Name + '.VTO';
              FSplit(FName, Dir, Name, Ext);
              SwName := Dir + SwName;
            END
          ELSE
            BEGIN
              FSplit(FName, Dir, Name, Ext);
              SwName := Dir + Name + '.VTO';
            END;

          Cmd.ParseFile(SwName);
}
          InitVTScreens(Song);
          RefreshVTScreens;

          IF DoPlayMod(Song) THEN GOTO Fin;
        END;
    UNTIL NOT Song.ThereIsMore;

    IF NoMod THEN
      ORROR(Song.GetErrorString + ' [' + FName + ']', FALSE);

    DoOneMOD := TRUE;
Fin:
    Song.Done;
{
    Cmd.Done;
}
  END;

{ -------------------------------------------------------------------------- }

CONST
  AppID : STRING[Length(NombreApp) + 2 + Length(Version) + Length(BetaStr)] = NombreApp+' v'+Version+BetaStr;

VAR
  Dir     : DirStr;
  Name    : NameStr;
  Ext     : ExtStr;
  p       : POINTER;
  l       : LONGINT;
  s       : STRING;
  i, r    : WORD;
LABEL
  Fin;
BEGIN

  { Initialize heaps }

  InitHeapVariables;
  InitUmbHeap;



  { Init command line objects }

  Cmd.Init;
  SongColl.Init(2, 3);



  { Initialize Song variables }

  EmptySong.Init;

    

  { Set debugging flag. }

  Debugging.Debug := FALSE;
  IF (ParamStr(1) = '/DEB') OR (ParamStr(1) = '/deb') THEN
    Debugging.Debug := TRUE;



  { Initialize language file. }

  StringsFName := FExpand(StringsFName);
  FSplit(StringsFName, Dir, Name, Ext);
  IF NOT FileExists(StringsFName) THEN
    StringsFName := Name+Ext;
  IF NOT FileExists(StringsFName) THEN
    StringsFName := VTDir+Name+Ext;

  IF (NOT FileExists(StringsFName)) OR NOT InitStrings(StringsFName) THEN
    BEGIN
      WriteLn(StdErr, 'VT needs a valid language file to run.');
      WriteLn(StdErr, 'VT necesita un fichero de lenguaje v lido para funcionar.');
      EXIT;
    END;



  { Display usage and exit if no parameters. }

  IF ParamCount = 0 THEN USAGE;

  ASM
        MOV     AX,3
        INT     10h
  END;

  WriteLn;
  WriteLn('   ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿    ');
  WriteLn('   ³ BETA    BETA    BETA    BETA    BETA    BETA    BETA    BETA    BETA ³    ');
  WriteLn('   ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ    ');
  WriteLn;
  WriteLn(' This is a beta version of the VangeliSTracker. It''s purposely incomplete.     ');
  WriteLn(' It was created to test two things:                                            ');
  WriteLn;
  WriteLn('   1st - The VIDEO MODE: experimental 90x63 text mode.                         ');
  WriteLn;
  WriteLn('   2nd - The GUS SUPPORT. See VT.CFG                                           ');
  WriteLn;
  WriteLn(' If the screen is misaligned, try CTRL+LEFT ARROW and CTRL+RIGHT ARROW.        ');
  WriteLn;
  WriteLn;
  WriteLn(' Comments welcome to:                                                          ');
  WriteLn;
  WriteLn('   Juan Carlos Ar‚valo                                                         ');
  WriteLn('     Fidonet:  2:341/27.16, 2:341/8.36                                        ');
  WriteLn('     CdNet:    94:640/200                                                      ');
  WriteLn('     Internet: jcarlos@gw.iic.uam.es                                           ');
  WriteLn('               mpetit@dit.upm.es                                               ');
  WriteLn('     P. O. Box 156405 (28080 - Madrid, Spain)                                  ');
  WriteLn;
  Write  ('Press any key to continue.');

  KbdReadKey;

  WriteLn;
  WriteLn;


  { Display Copyright notice. }

  WriteLn(AppID, ' (C) 1992-93, VangeliSTeam.');
  WriteLn;
  Write(GetString(StrInitializing));



  { Check for other VT's resident in memory. }

  VTResidentCheck(AppID);



  { Initialize Units. SoundDevices MUST be first. }

  InitSoundDevices;  Write('o');
  IF NOT InitSwapManager(New(PSwapStream, Init)) THEN
    BEGIN
      DoneSwapManager;
      WriteLn;
      WriteLn;
      WriteLn(GetString(StrSwapNotInit));
      EXIT;
    END;

  Write('o');

  InitVid43;          Write('o');
  InitModUnit;        Write('o');
  InitModVideoTables; Write('o');



  { Initialize and paint screen. }

  SetVTDevice;
  SetVTFreq;

  InitVTScreens(EmptySong); WriteLn;
  PoneVideoMode43;

  InitWinF8Demo;
  SetSmall_Samples;

  SetOffs(ScrOffset);

  InitMouse;
  SetMouse(TRUE);
  ShowMouse;

  InitPlayData(PSong(NIL)^);

  OneModProc := DoOneMod;



  { Loop for all MODs. }

  NoMods := TRUE;

  Cmd.ParseLine(GetDOSCmdLine);
  IF NOT DoSongColl(Cmd.FileDir) THEN GOTO Fin;

  IF NoMods THEN
    ORROR(GetString(StrFileNotExist), FALSE);


Fin:

  { Cleanup and finish. }

  EndSampling;
  QuitaVideoMode43;
  DoneSwapManager;

END.
