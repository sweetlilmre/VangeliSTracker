UNIT VTWins;

INTERFACE

USES VTGlobal, VTStrConst, StrConst,
     SoundDevices, SongUnit, SongElements, PlayMod,
     Output43, Vid43, Kbd;


TYPE
  TChWindows = ARRAY[1..4] OF TWindow;

CONST

  { 0 -> 0 }
  { 1 -> 3 }
  { 2 -> 7 }
  { 3 -> 4 }
  { 4 -> 2 }
  { 5 -> 1 }
  { 6 -> 5 }
  { 7 -> 6 }


  EmptyPalet        = #$30;

  ScreenPalet       = #$35#$75#$34;

  F8Palet           = #$03#$04#$03;

  RunInfoPalet      = #$31#$06#$30#$47;
  MiscInfoPalet     = #$31#$06;
  LabelPalet        = #$31#$64;

  ChannelNumPalet   = #$17;
  RunSamplePalet    = #$30;
  InfoNotePalet     = #$36#$17#$06;
  PlayBarsPalet     = #$05#$02#$04;

  MenusPalet        = #$35#$75#$34;
  OscilloscPalet    = #$34#$5F;
  SamplesPalet      = #$30#$36#$06#$07#$07#$16#$47#$64;

  PartPalet         = #$82#$07#$30#$17;

  CreditsPalet      = #$31#$37#$34;


  wF8Demo      : TWindow = (x: 0; y:-1; w:90; h:26; col: F8Palet;        vis:FALSE; forz:FALSE; act:FALSE);
  wF8DemoUp    : TWindow = (x: 0; y: 0; w:90; h:11; col: ScreenPalet;    vis:FALSE; forz:FALSE; act:FALSE);
  wF8DemoDown  : TWindow = (x: 0; y:25; w:90; h:16; col: ScreenPalet;    vis:FALSE; forz:FALSE; act:FALSE);

  wScreen      : TWindow = (x: 0; y: 0; w:90; h:63; col: ScreenPalet;    vis:FALSE; forz:FALSE; act:FALSE);

  wTopLine     : TWindow = (x: 0; y: 0; w:90; h: 6; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE);
  wRunInfo     : TWindow = (x: 0; y: 0; w:24; h: 6; col: RunInfoPalet;   vis:FALSE; forz:FALSE; act:FALSE);
  wMiscInfo    : TWindow = (x:23; y: 0; w:57; h: 6; col: MiscInfoPalet;  vis:FALSE; forz:FALSE; act:FALSE);
  wLabel       : TWindow = (x:69; y: 0; w:21; h: 6; col: LabelPalet;     vis:FALSE; forz:FALSE; act:FALSE);

  w2ndLine     : TWindow = (x: 0; y: 5; w:90; h:18; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE);
  wChannelNum  : TWindow = (x: 0; y: 5; w: 5; h:18; col: ChannelNumPalet;vis:FALSE; forz:FALSE; act:FALSE);
  wRunSample   : TWindow = (x: 3; y: 5; w:30; h:18; col: RunSamplePalet; vis:FALSE; forz:FALSE; act:FALSE);
  wInfoNote    : TWindow = (x:32; y: 5; w:30; h:18; col: InfoNotePalet;  vis:FALSE; forz:FALSE; act:FALSE);
  wPlayBars    : TWindow = (x:61; y: 5; w:18; h:18; col: PlayBarsPalet;  vis:FALSE; forz:FALSE; act:FALSE);
  wPanning     : TWindow = (x:78; y: 5; w: 8; h:18; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE);
  wVoiceOnOff  : TWindow = (x:85; y: 5; w: 5; h:18; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE);


  wMenus       : TWindow = (x: 0; y:22; w:90; h:22; col: MenusPalet;     vis:FALSE; forz:FALSE; act:FALSE);
  wOscillosc   : TWindow = (x: 0; y:22; w:90; h:22; col: OscilloscPalet; vis:FALSE; forz:FALSE; act:FALSE);
  wSamples     : TWindow = (x: 0; y:22; w:90; h:22; col: SamplesPalet;   vis:FALSE; forz:FALSE; act:FALSE);
  wSamples1    : TWindow = (x: 1; y:22; w:30; h:22; col: SamplesPalet;   vis:FALSE; forz:FALSE; act:FALSE);
  wSamples2    : TWindow = (x:30; y:22; w:30; h:22; col: SamplesPalet;   vis:FALSE; forz:FALSE; act:FALSE);
  wSamples3    : TWindow = (x:59; y:22; w:30; h:22; col: SamplesPalet;   vis:FALSE; forz:FALSE; act:FALSE);

  wPartSmall   : TWindow = (x: 0; y:43; w:90; h:20; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE);
  wPartPastIdx : TWindow = (x: 0; y:43; w: 5; h: 9; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE);
  wPartPast    : TChWindows = (
                           (x: 5; y:43; w:22; h: 9; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:26; y:43; w:22; h: 9; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:47; y:43; w:22; h: 9; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:68; y:43; w:22; h: 9; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE)
                 );
  wPartActIdx  : TWindow = (x: 0; y:51; w: 5; h: 4; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE);
  wPartAct     : TChWindows = (
                           (x: 5; y:51; w:22; h: 4; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE),
                           (x:26; y:51; w:22; h: 4; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE),
                           (x:47; y:51; w:22; h: 4; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE),
                           (x:68; y:51; w:22; h: 4; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE)
                 );
  wPartFutIdx  : TWindow = (x: 0; y:54; w: 5; h: 9; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE);
  wPartFut     : TChWindows = (
                           (x: 5; y:54; w:22; h: 9; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:26; y:54; w:22; h: 9; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:47; y:54; w:22; h: 9; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:68; y:54; w:22; h: 9; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE)
                 );

  wPartBig     : TWindow = (x: 0; y: 5; w:90; h:58; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE);
  wPartPastBIdx: TWindow = (x: 0; y: 5; w: 5; h:28; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE);
  wPartPastBig : TChWindows = (
                           (x: 5; y: 5; w:22; h:28; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:26; y: 5; w:22; h:28; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:47; y: 5; w:22; h:28; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:68; y: 5; w:22; h:28; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE)
                 );
  wPartActBIdx : TWindow = (x: 0; y:32; w: 5; h: 4; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE);
  wPartActBig  : TChWindows = (
                           (x: 5; y:32; w:22; h: 4; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE),
                           (x:26; y:32; w:22; h: 4; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE),
                           (x:47; y:32; w:22; h: 4; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE),
                           (x:68; y:32; w:22; h: 4; col: EmptyPalet;     vis:FALSE; forz:FALSE; act:FALSE)
                 );
  wPartFutBIdx : TWindow = (x: 0; y:35; w: 5; h:28; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE);
  wPartFutBig  : TChWindows = (
                           (x: 5; y:35; w:22; h:28; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:26; y:35; w:22; h:28; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:47; y:35; w:22; h:28; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE),
                           (x:68; y:35; w:22; h:28; col: PartPalet;      vis:FALSE; forz:FALSE; act:FALSE)
                 );
  wCredits     : TWindow = (x: 0; y: 5; w:90; h:58; col: CreditsPalet;   vis:FALSE; forz:FALSE; act:FALSE);

CONST
  BarVal : CHAR = '±';   { '±', '¦', '˜' }

  FirstChannel : BYTE = 1;

VAR
  wriX1, wriX2,
  wmiX1, wmiX2, wmiX3,
  winX1, winX2, winX3, winX4, winX5,
  wsX1                              : WORD;



PROCEDURE InitWinF8Demo;
PROCEDURE InitWinF8Line;
PROCEDURE InitWinScreen;
PROCEDURE InitWinTopLine;
PROCEDURE InitWin2ndLine;
PROCEDURE InitWinMenus;
PROCEDURE InitWinOscillosc;
PROCEDURE InitWinSamples;
PROCEDURE InitWinPart;
PROCEDURE InitWinBigPart;
PROCEDURE InitWinCredits;

PROCEDURE InitScreen;

PROCEDURE RefreshMiscInfo   (VAR Song: TSong);
PROCEDURE RefreshModuleInfo (VAR Song: TSong);




IMPLEMENTATION

USES Objects, Heaps, HexConversions;




PROCEDURE InitWinF8Demo;
  VAR
    i       : WORD;
    SaveOfs : WORD;
    Spaces  : STRING[90];
  BEGIN
    SaveOfs   := ScrOffset;
    ScrOffset := 0;

    ClearScreen;
    PutWindowBigFrame(wF8Demo);

    WITH wF8Demo DO
      BEGIN

        FillChar(Spaces, SIZEOF(Spaces), ' ');
        Spaces[0] := #90;

        FOR i := 0 TO 26 DO
          DirectWriteAttr(ParseCoords(0, i), Spaces, BYTE(Col[3]));

        PutWindowBigFrame(wF8DemoDown);

        DirectWriteAttr(ParseCoords(27, 4), 'Demo de ventanas  en el VT', BYTE(Col[3]));
        DirectWriteAttr(ParseCoords(35, 6), '¨Te gusta?',                 BYTE(Col[3]));

        DirectWriteAttr(ParseCoords(7, 10),
          'En la pr¢xima versi¢n se supone que aqu¡ podr s hacer el Shell.',                 BYTE(Col[2]));
      END;

    ScrOffset := SaveOfs;
  END;


PROCEDURE InitWinF8Line;
  BEGIN
    PutWindowBigFrame(wF8DemoUp);
  END;


PROCEDURE InitWinScreen;
  BEGIN
    ClearScreen;
    PutWindowBigFrame(wScreen);
  END;


PROCEDURE InitWinRunInfo;
  BEGIN
    PutWindow(wRunInfo);

    WITH wRunInfo DO BEGIN
      vis  := FALSE;
      forz := FALSE;
      act  := FALSE;

      wriX1 := 12;
      wriX2 := 16;
      DirectWrite     (ParseCoords(x+ 1, y+1), GetString(StrPosition));
      DirectWrite     (ParseCoords(x+ 1, y+2), GetString(StrPattern));
      DirectWrite     (ParseCoords(x+ 1, y+3), GetString(StrNote));
      DirectWrite     (ParseCoords(x+ 1, y+4), GetString(StrTempo));
      DirectWriteAttr (ParseCoords(x+wriX2-1, y+1), '/',   BYTE(col[3]));
      DirectWriteAttr (ParseCoords(x+wriX2-1, y+2), '/',   BYTE(col[3]));
      DirectWriteAttr (ParseCoords(x+wriX2-1, y+3), '/',   BYTE(col[3]));
      DirectWriteAttr (ParseCoords(x+wriX2-1, y+4), 'B',   BYTE(col[3]));
      RectAttr        (ParseCoords(x+wriX2,   y+1), 3, 4,  BYTE(col[2]));
      RectAttr        (ParseCoords(x+wriX1,   y+1), 3, 4,  BYTE(col[2]));
      DirectWriteAttr (ParseCoords(x+wriX2+4, y+4), 'F',   BYTE(col[3]));
      DirectWriteAttr (ParseCoords(x+wriX2+5, y+4), '  ',  BYTE(col[2]));
    END;
  END;


PROCEDURE InitWinMiscInfo;
  BEGIN
    PutWindow(wMiscInfo);

    WITH wMiscInfo DO BEGIN
      DirectWrite (ParseCoords(x+1,  y+1), GetString(StrModule));
      DirectWrite (ParseCoords(x+1,  y+2), GetString(StrFilename));
      DirectWrite (ParseCoords(x+1,  y+3), GetString(StrMemoryLeft));
      DirectWrite (ParseCoords(x+1,  y+4), GetString(StrSampleRate));
      DirectWrite (ParseCoords(x+18, y+4), GetString(StrVolume));
      wmiX1 := 12;
      wmiX2 := 25;
      wmiX3 := 26;
      DirectWrite (ParseCoords(x+wmiX2-1, y+2), '/');
      RectAttr    (ParseCoords(x+wmiX1, y+1), 20,         1, BYTE(col[2]));
      RectAttr    (ParseCoords(x+wmiX1, y+2), 12,         1, BYTE(col[2]));
      RectAttr    (ParseCoords(x+wmiX2, y+2), 12,         1, BYTE(col[2]));
      RectAttr    (ParseCoords(x+wmiX1, y+3), 21,         1, BYTE(col[2]));
      RectAttr    (ParseCoords(x+wmiX1, y+4), 5,          1, BYTE(col[2]));
      RectAttr    (ParseCoords(x+wmiX3, y+4), 3,          1, BYTE(col[2]));
    END;
  END;


PROCEDURE InitWinLabel;
  BEGIN
    PutWindow(wLabel);

    WITH wLabel DO BEGIN
      RectAttr    (ParseCoords(x+2, y+2), 17, 2, BYTE(col[2]));
      DirectWrite (ParseCoords(x+3, y+2), 'Vangeli©ªracker');
      DirectWrite (ParseCoords(x+4, y+3), NoBetaPadding+Version+BetaPadStr);
    END;
  END;


PROCEDURE InitWinTopLine;
  BEGIN
    InitWinRunInfo;
    InitWinMiscInfo;
    InitWinLabel;
  END;


PROCEDURE InitWinChannelNum;
  CONST
    s : STRING[2] = '  ';
  VAR
    i : WORD;
  BEGIN
    PutWindow(wChannelNum);

    WITH wChannelNum DO
      FOR i := 1 TO 16 DO
        BEGIN
          IF i = 10 THEN s[1] := '1';
          s[2] := CHAR(i MOD 10 + ORD('0'));
          DirectWrite(ParseCoords(x+1, y+i), s);
        END;
  END;


PROCEDURE InitWinRunSample;
  BEGIN
    PutWindow(wRunSample);
  END;


PROCEDURE InitWinInfoNote;
  BEGIN
    PutWindow(wInfoNote);

    WITH wInfoNote DO BEGIN
      winX1 :=  2;
      winX2 :=  6;
      winX3 :=  9;
      winX4 := 16;
      winX5 := 23;
      PutRotulo (ParseCoords(x+ 1, y), 'note', BYTE(col[2]));
      PutRotulo (ParseCoords(x+ 6, y), 'vl',   BYTE(col[2]));
      PutRotulo (ParseCoords(x+11, y), 'reps', BYTE(col[2]));
      PutRotulo (ParseCoords(x+18, y), 'repl', BYTE(col[2]));
      PutRotulo (ParseCoords(x+26, y), 'len',  BYTE(col[2]));
      RectAttr  (ParseCoords(x+ 2, y+1), 3, 16, BYTE(col[3]));
      RectAttr  (ParseCoords(x+ 6, y+1), 2, 16, BYTE(col[3]));
      RectAttr  (ParseCoords(x+ 9, y+1), 6, 16, BYTE(col[3]));
      RectAttr  (ParseCoords(x+16, y+1), 6, 16, BYTE(col[3]));
      RectAttr  (ParseCoords(x+23, y+1), 6, 16, BYTE(col[3]));
    END;
  END;


PROCEDURE InitWinPlayBars;
  VAR
    i, j : WORD;
  BEGIN
    PutWindow(wPlayBars);

    WITH wPlayBars DO BEGIN
      vis  := FALSE;
      forz := FALSE;
      act  := FALSE;

      FOR i := 1 TO 16 DO
        FOR j := 1 TO 16 DO
          DirectWriteAttr(ParseCoords(x+j, y+i), Barval, BYTE(col[1]));
    END;
  END;


PROCEDURE InitWinPanning;
  VAR
    i : WORD;
  BEGIN
    PutWindow(wPanning);
{
    WITH wPanning DO BEGIN
      FOR i := 1 TO 16 DO
        IF Odd(i SHR 1) THEN
          DirectWriteAttr(ParseCoords(x+1, y+i), 'õöõõõõ', BYTE(col[1]))
        ELSE
          DirectWriteAttr(ParseCoords(x+1, y+i), 'õõõõ÷õ', BYTE(col[1]));
    END;
}
  END;


PROCEDURE InitWinVoiceOnOff;
  BEGIN
    PutWindow(wVoiceOnOff);
  END;


PROCEDURE InitWin2ndLine;
  BEGIN
    InitWinChannelNum;
    InitWinRunSample;
    InitWinInfoNote;
    InitWinPlayBars;
    InitWinPanning;
    InitWinVoiceOnOff;
  END;

{

PROCEDURE InitOscilloscInfo;
  CONST
    EmptyStr : STRING[51] = '                                                   ';
    OscView  : STRING[30] = '';
    i        : WORD       = 0;
    j        : WORD       = 0;
    ofs      : WORD       = 0;
  VAR
    OscWinBuff    : ARRAY[1..16, 1..51*2] OF CHAR;
  BEGIN
    OscView := GetString(StrOscilloscView);
    WITH wOscillosc DO BEGIN
      FOR i := 1 TO 16 DO PutStr(OscWinBuff[i], EmptyStr, BYTE(col[1]));
      PutStr(OscWinBuff[1][21*2-1], OscView, BYTE(col[1]));
      FOR i := 3 TO 14 DO BEGIN
        OscWinBuff[i][4] := col[1];
        OscWinBuff[i][6] := col[1];
        OscWinBuff[i][8] := col[1];
        OscWinBuff[i][3] := ' ';
        OscWinBuff[i][5] := ' ';
        OscWinBuff[i][7] := #131;
        FOR j := 5 TO 50 DO BEGIN
          OscWinBuff[i][j*2]   := col[2];
          OscWinBuff[i][j*2-1] := #0;
        END;
      END;
      OscWinBuff[15][8] := col[1];
      OscWinBuff[15][7] := #150;
      FOR j := 5 TO 50 DO BEGIN
        OscWinBuff[15][j*2]   := col[1];
        OscWinBuff[15][j*2-1] := #148;
      END;

      Ofs := ParseCoords(x+1, y+1);
      FOR i := 1 TO 16 DO BEGIN
        Move(OscWinBuff[i], Ptr(ScrSegment, Ofs)^, SIZEOF(OscWinBuff[1]));
        INC(Ofs, ScreenBytesX);
      END;
    END;
  END;

}

PROCEDURE InitWinMenus;
  BEGIN
    PutWindow(wMenus);
  END;


PROCEDURE InitWinOscillosc;
  VAR
    i : WORD;
  BEGIN
    PutWindow(wOscillosc);

    WITH wOscillosc DO BEGIN
      DirectWrite(ParseCoords(x+39, y+1), GetString(StrOscilloscView));
{
      FOR i := 3 TO 14 DO
        DirectWrite(ParseCoords(x+4, y+i),  #131);
      DirectWrite  (ParseCoords(x+4, y+15), #150);
      FOR i := 5 TO 50 DO
        DirectWrite(ParseCoords(x+i, y+15), #148);
}
    END;
  END;


PROCEDURE InitWinSamples;
  BEGIN
    PutWindow(wSamples);
    PutWindow(wSamples1);
    PutWindow(wSamples2);
    PutWindow(wSamples3);
  END;


PROCEDURE InitWinPart;
  VAR
    i : WORD;
  BEGIN
    PutWindow(wPartSmall);
    PutWindow(wPartPastIdx);
    PutWindow(wPartActIdx);
    PutWindow(wPartFutIdx);
    FOR i := 1 TO 4 DO BEGIN
      PutWindow(wPartPast[i]);
      PutWindow(wPartAct[i]);
      PutWindow(wPartFut[i]);
      WITH wPartPast[i] DO BEGIN
        PutRotulo(ParseCoords(x+5,                               y), GetString(StrChannel), BYTE(col[4]));
        PutRotulo(ParseCoords(x+5+Length(GetString(StrChannel)), y), CHAR(i+ORD('0')),      BYTE(col[4]));
      END;
    END;
  END;


PROCEDURE InitWinBigPart;
  VAR
    i : WORD;
  BEGIN
    PutWindow(wPartBig);
    PutWindow(wPartPastBIdx);
    PutWindow(wPartActBIdx);
    PutWindow(wPartFutBIdx);
    FOR i := 1 TO 4 DO BEGIN
      PutWindow(wPartPastBig[i]);
      PutWindow(wPartActBig[i]);
      PutWindow(wPartFutBig[i]);
      WITH wPartPastBig[i] DO BEGIN
        PutRotulo(ParseCoords(x+5,                               y), GetString(StrChannel), BYTE(col[4]));
        PutRotulo(ParseCoords(x+5+Length(GetString(StrChannel)), y), CHAR(i+ORD('0')),      BYTE(col[4]));
      END;
    END;
  END;


PROCEDURE InitWinCredits;
  VAR
    i : WORD;
  BEGIN
    PutWindow(wCredits);

    WITH wCredits DO BEGIN
      DirectWriteAttr(ParseCoords  (x+10, y+   2), GetString(StrCreditsTitle), BYTE(col[3]));

      i := 0;
      WHILE GetString(StrCredits + i) <> #0 DO
        BEGIN
          DirectWriteAttr(ParseCoords(x+10, y+i+ 4), GetString(StrCredits + i), BYTE(col[1]));
          INC(i);
        END;

      i := 0;
      WHILE GetString(StrDedicat + i) <> #0 DO
        BEGIN
          DirectWriteAttr(ParseCoords(x+10, y+i+38), GetString(StrDedicat + i), BYTE(col[2]));
          INC(i);
        END;
    END;

  END;




PROCEDURE InitScreen;
  VAR
    i, j : WORD;
    s    : STRING;
  BEGIN

    InitWinScreen;
    InitWinTopLine;
    InitWin2ndLine;
    InitWinSamples;
    InitWinPart;

  END;



PROCEDURE RefreshMiscInfo(VAR Song: TSong);
  VAR
    s : STRING;
    t : STRING;
    u : STRING;
    i : WORD;
  BEGIN
    WITH wMiscInfo DO BEGIN
      DirectWriteAttr(ParseCoords(x+wmiX1, y+1), Song.GetName,               BYTE(col[2]));
      DirectWriteAttr(ParseCoords(x+wmiX1, y+2), Song.FileName+Song.FileExt, BYTE(col[2]));
      DirectWriteAttr(ParseCoords(x+wmiX2, y+2), Song.GetInsidePath,         BYTE(col[2]));
      STR(Heap.HMaxAvail,    s);
      STR(Heap.HMemAvail,    t);
      STR(UmbHeap.HMemAvail, u);
                                                 {xxxxx (xxxxx) | xxxxxx}
      DirectWriteAttr(ParseCoords(x+wmiX1, y+3), '                      ', BYTE(col[2]));
      DirectWriteAttr(ParseCoords(x+wmiX1, y+3), t+' ('+s+') | '+u,        BYTE(col[2]));

(*
      IF SoundHz >= 500 THEN
        STR(SoundHz + 50 - ((SoundHz + 50) MOD 100), s)
      ELSE
        s := 'FallB';
      DirectWriteAttr(ParseCoords(x+wmiX1, y+4), '     ',                  BYTE(col[2]));
      DirectWriteAttr(ParseCoords(x+wmiX1, y+4), s,                        BYTE(col[2]));
*)

      STR(UserVols[1] : 3, s);
      DirectWriteAttr(ParseCoords(x+wmiX3, y+4), s,                        BYTE(col[2]));
    END;

  END;




PROCEDURE SaveInstrument(Name: STRING; Buf: POINTER; Len: WORD);
  VAR
    St : TDosStream;
  BEGIN
    St.Init(Name, stCreate);
    St.Write(Buf^, Len);
    St.Done;
  END;

PROCEDURE InitSampleWin(VAR Song: TSong);
  CONST
    s     : STRING      = '';
    i     : WORD        = 0;
    Instr : PInstrument = NIL;
  BEGIN
    wsX1 := 4;

    WITH wSamples1 DO
      FOR i := 1 TO 20 DO BEGIN
        STR(i : 2, s);
        DirectWriteAttr   (ParseCoords(x+1,    y+i), s,                      BYTE(col[3]));
        Instr := Song.GetInstrument(i);
        IF Instr = NIL THEN
          DirectWriteAttr (ParseCoords(x+wsX1, y+i), '                         ', BYTE(col[2]))
        ELSE IF Instr^.Instr = NIL THEN
          DirectWriteAttr (ParseCoords(x+wsX1, y+i), Instr^.GetName,         BYTE(col[2]))
        ELSE
          DirectWriteAttr (ParseCoords(x+wsX1, y+i), Instr^.GetName,         BYTE(col[3]));
      END;

    WITH wSamples2 DO
      FOR i := 21 TO 40 DO BEGIN
        STR(i : 2, s);
        DirectWriteAttr   (ParseCoords(x+1,    y+i-20), s,                      BYTE(col[3]));
        Instr := Song.GetInstrument(i);
        IF Instr = NIL THEN
          DirectWriteAttr (ParseCoords(x+wsX1, y+i-20), '                         ', BYTE(col[2]))
        ELSE IF Instr^.Instr = NIL THEN
          DirectWriteAttr (ParseCoords(x+wsX1, y+i-20), Instr^.GetName,         BYTE(col[2]))
        ELSE
          DirectWriteAttr (ParseCoords(x+wsX1, y+i-20), Instr^.GetName,         BYTE(col[3]));
      END;

    WITH wSamples3 DO
      FOR i := 41 TO 60 DO BEGIN
        STR(i : 2, s);
        DirectWriteAttr   (ParseCoords(x+1,    y+i-40), s,                      BYTE(col[3]));
        Instr := Song.GetInstrument(i);
        IF Instr = NIL THEN
          DirectWriteAttr (ParseCoords(x+wsX1, y+i-40), '                         ', BYTE(col[2]))
        ELSE IF Instr^.Instr = NIL THEN
          DirectWriteAttr (ParseCoords(x+wsX1, y+i-40), Instr^.GetName,         BYTE(col[2]))
        ELSE
          DirectWriteAttr (ParseCoords(x+wsX1, y+i-40), Instr^.GetName,         BYTE(col[3]));
      END;

  END;




PROCEDURE RefreshModuleInfo(VAR Song: TSong);
  VAR
    s : STRING;
    i : WORD;
  BEGIN

    WITH wRunInfo DO BEGIN
      STR(Song.SequenceLength   : 3, s); DirectWrite(ParseCoords(x+wriX2, y+1), s);
      STR(Song.Patterns.Count   : 3, s); DirectWrite(ParseCoords(x+wriX2, y+2), s);
      s := '   ';
      DirectWrite(ParseCoords(x+wriX1, y+1), s);
      DirectWrite(ParseCoords(x+wriX1, y+2), s);
      DirectWrite(ParseCoords(x+wriX1, y+3), s);
      DirectWrite(ParseCoords(x+wriX1, y+4), s);
    END;

    RefreshMiscInfo(Song);

    InitSampleWin(Song);
  END;







{
VAR
  BIOSScrOffset : WORD ABSOLUTE 0:$44E;
}
BEGIN

  pwAttr    := BYTE(wScreen.col[2]);
{  ScrOffset := BIOSScrOffset;}

END.
