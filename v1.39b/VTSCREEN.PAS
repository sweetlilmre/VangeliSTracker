UNIT VTScreens;

INTERFACE

USES VTWins, VTCfg, VTPartitura,
     SongUnit,
     SwapManager,
     Output43, Vid43;


VAR
  TopLineHandle   : TSwapHandle;
  _2ndLineHandle  : TSwapHandle;
  SamplesHandle   : TSwapHandle;
  OscilloscHandle : TSwapHandle;
  MenusHandle     : TSwapHandle;
  SmallPartHandle : TSwapHandle;
  BigPartHandle   : TSwapHandle;
  CreditsHandle   : TSwapHandle;
  F8DemoHandle    : TSwapHandle;

CONST
  wfTopLine   = $0001;
  wf2ndLine   = $0002;
  wfSamples   = $0004;
  wfOscillosc = $0008;
  wfMenus     = $0010;
  wfSmallPart = $0020;
  wfBigPart   = $0040;
  wfCredits   = $0080;
  wfF8Demo    = $0100;

  ActiveWindows : WORD = 0;

  CreditWins          = wfTopLine + wfCredits;
  BigWins             = wfTopLine + wfBigPart;
  Small_SamplesWins   = wfTopLine + wf2ndLine + wfSamples   + wfSmallPart;
  Small_OscilloscWins = wfTopLine + wf2ndLine + wfOscillosc + wfSmallPart;
  Small_MenuWins      = wfTopLine + wf2ndLine + wfMenus     + wfSmallPart;
  F8Demo              = wfTopLine + wf2ndLine + wfF8Demo;




PROCEDURE InitVTScreens(VAR Song: TSong);
PROCEDURE RefreshVTScreens;

PROCEDURE SetCredits;
PROCEDURE SetBig;
PROCEDURE SetSmall_Samples;
PROCEDURE SetSmall_Oscillosc;
PROCEDURE SetSmall_Menu;
PROCEDURE SetNothing;
PROCEDURE SetUser(w: WORD);




IMPLEMENTATION

USES SongElements, Heaps;


TYPE
  PScreen = ^TScreen;
  TScreen = ARRAY[1..90*63] OF WORD;

CONST
  VirtualScreen : PScreen = NIL;
  TempBuffer    : PScreen = NIL;

  NoDots : BOOLEAN = FALSE;



PROCEDURE PutDot;
  BEGIN
    IF NOT NoDots THEN
      Write('o');
  END;
  


PROCEDURE MySaveW(VAR Handle: TSwapHandle; x, y, w, h: WORD);
  BEGIN
    StoreWindow(POINTER(TempBuffer), x, y, w, h);
    IF NOT NoDots THEN
      Handle.Init;
    Handle.Write(TempBuffer^, SavedWindowSize(POINTER(TempBuffer)));
  END;


PROCEDURE InitVTScreens(VAR Song: TSong);
  VAR
    SaveSeg : WORD;
    SaveOfs : WORD;
  BEGIN
    IF VirtualScreen = NIL THEN
      FullHeap.HGetMem(POINTER(VirtualScreen), SizeOf(VirtualScreen^));

    IF TempBuffer = NIL THEN
      FullHeap.HGetMem(POINTER(TempBuffer), SizeOf(TempBuffer^));

                                                                          PutDot;
    SaveSeg := ScrSegment;
    SaveOfs := ScrOffset;
    ScrSegment := SEG(VirtualScreen^);
    ScrOffset  := OFS(VirtualScreen^);

    InitWinScreen;                                                        PutDot;
    InitWinF8Line;                                                        PutDot;
    InitWinTopLine;                                                       PutDot;

    IF NOT NoDots THEN
      WITH w2ndLine DO MySaveW(F8DemoHandle, x, y+h-1, w, 1);             PutDot;

    InitWinScreen;                                                        PutDot;
    InitWinTopLine;                                                       PutDot;
    InitWin2ndLine;                                                       PutDot;
    InitWinSamples;                                                       PutDot;
    InitWinPart;                                                          PutDot;
    RefreshModuleInfo(Song);                                              PutDot;
    WITH wTopLine   DO MySaveW(TopLineHandle,      x,   y, w,   h-1);     PutDot;
    WITH wSamples   DO MySaveW(SamplesHandle,      x,   y, w,   h  );     PutDot;

    IF NOT NoDots THEN
      BEGIN

        InitWinMenus;                                                     PutDot;

        WITH w2ndLine   DO MySaveW(_2ndLineHandle,     x,   y,   w, h-1); PutDot;
        WITH wMenus     DO MySaveW(MenusHandle,        x,   y,   w, h  ); PutDot;
        WITH wPartSmall DO MySaveW(SmallPartHandle,    x,   y+1, w, h-1); PutDot;

        InitWinOscillosc;                                                 PutDot;
        InitWinPart;                                                      PutDot;
        WITH wOscillosc DO MySaveW(OscilloscHandle,    x,   y,   w, h  ); PutDot;

        InitWinBigPart;                                                   PutDot;
        WITH wPartBig   DO MySaveW(BigPartHandle,      x,   y,   w, h-1); PutDot;

        InitWinCredits;                                                   PutDot;
        WITH wCredits   DO MySaveW(CreditsHandle,      x,   y,   w, h  ); PutDot;

      END;

    ScrSegment := SaveSeg;
    ScrOffset  := SaveOfs;

    NoDots := TRUE;

  END;


(*
PROCEDURE InitVTScreens;
  VAR
    SaveSeg : WORD;
    SaveOfs : WORD;
  BEGIN
                                                                      PutDot;
    SaveSeg := ScrSegment;
    SaveOfs := ScrOffset;
    ScrSegment := SEG(VirtualScreen^);
    ScrOffset  := OFS(VirtualScreen^);

    InitWinScreen;                                                    PutDot;
    InitWinTopLine;                                                   PutDot;
    InitWin2ndLine;                                                   PutDot;
    InitWinSamples;                                                   PutDot;
    RefreshModuleInfo;                                                PutDot;
    WITH wTopLine   DO SaveWindow(SegTopLine,      x,   y, w,   h-1); PutDot;
    WITH wSamples   DO SaveWindow(SegSamples,      x,   y, w-1, h-1); PutDot;
    WITH w2ndLine   DO SaveWindow(Seg2ndLine,      x,   y, w,   h-1); PutDot;

    IF SegOscillosc = NIL THEN
      BEGIN

        InitWinMenus;                                                     PutDot;
        InitWinPart;                                                      PutDot;

        WITH wMenus     DO SaveWindow(SegMenus,        x,   y, w,   h-1); PutDot;
        WITH wPartSmall DO SaveWindow(SegSmallPart,    x,   y, w,   h  ); PutDot;

        InitWinOscillosc;                                                 PutDot;
        InitWinPart;                                                      PutDot;
        WITH wOscillosc DO SaveWindow(SegOscillosc,    x,   y, w,   h-1); PutDot;

        InitWinBigPart;                                                   PutDot;
        WITH wPartBig   DO SaveWindow(SegBigPart,      x,   y, w,   h  ); PutDot;

        InitWinCredits;                                                   PutDot;
        WITH wCredits   DO SaveWindow(SegCredits,      x,   y, w,   h  ); PutDot;

      END;

    ScrSegment := SaveSeg;
    ScrOffset  := SaveOfs;

    NoDots := TRUE;

  END;
*)

PROCEDURE DoDeactivate(VAR w: TWindow);
  BEGIN
    w.vis  := FALSE;
    w.forz := FALSE;
    w.act  := FALSE;
  END;


PROCEDURE DoActivate(VAR w: TWindow; VAR Handle: TSwapHandle);
  BEGIN
    Handle.Read(TempBuffer^, SizeOf(TempBuffer^));
    RestoreWindow(POINTER(TempBuffer));
    w.vis  := TRUE;
    w.forz := TRUE;
    w.act  := TRUE;
  END;


{
PROCEDURE DoActivate(VAR w: TWindow; SavePtr: PAoW);
  BEGIN
    RestoreWindow(SavePtr);
    w.vis  := TRUE;
    w.forz := TRUE;
    w.act  := TRUE;
  END;
}

PROCEDURE DeactivateWins(NewWins: WORD);
  VAR
    f : WORD;
  BEGIN
    f := (NOT NewWins) AND ActiveWindows;
    IF (f AND wfTopLine)   <> 0 THEN DoDeactivate(wTopLine);
    IF (f AND wf2ndLine)   <> 0 THEN DoDeactivate(w2ndLine);
    IF (f AND wfSamples)   <> 0 THEN DoDeactivate(wSamples);
    IF (f AND wfOscillosc) <> 0 THEN DoDeactivate(wOscillosc);
    IF (f AND wfMenus)     <> 0 THEN DoDeactivate(wMenus);
    IF (f AND wfSmallPart) <> 0 THEN DoDeactivate(wPartSmall);
    IF (f AND wfBigPart)   <> 0 THEN DoDeactivate(wPartBig);
    IF (f AND wfCredits)   <> 0 THEN DoDeactivate(wCredits);

    ActiveWindows := ActiveWindows AND NewWins;
  END;


PROCEDURE ActivateWins(NewWins: WORD);
  VAR
    f : WORD;
  BEGIN
    f := NewWins AND (NOT ActiveWindows) ;
    IF (f AND wfTopLine)   <> 0 THEN   DoActivate(wTopLine,   TopLineHandle);
    IF (f AND wf2ndLine)   <> 0 THEN   DoActivate(w2ndLine,   _2ndLineHandle);
    IF (f AND wfSamples)   <> 0 THEN   DoActivate(wSamples,   SamplesHandle);
    IF (f AND wfOscillosc) <> 0 THEN   DoActivate(wOscillosc, OscilloscHandle);
    IF (f AND wfMenus)     <> 0 THEN   DoActivate(wMenus,     MenusHandle);
    IF (f AND wfSmallPart) <> 0 THEN BEGIN
                                       DoActivate(wPartSmall, SmallPartHandle);
                                       SetSmallPartWindow;
                                     END;
    IF (f AND wfBigPart)   <> 0 THEN BEGIN
                                       DoActivate(wPartBig,   BigPartHandle);
                                       SetBigPartWindow;
                                     END;
    IF (f AND wfCredits)   <> 0 THEN   DoActivate(wCredits,   CreditsHandle);

    ActiveWindows := ActiveWindows OR NewWins;
  END;


PROCEDURE SetCredits;
  BEGIN
    DeactivateWins(CreditWins);
    ActivateWins(CreditWins);
  END;


PROCEDURE SetBig;
  BEGIN
    DeactivateWins(BigWins);
    ActivateWins(BigWins);
  END;


PROCEDURE SetSmall_Samples;
  BEGIN
    DeactivateWins(Small_SamplesWins);
    ActivateWins(Small_SamplesWins);
  END;


PROCEDURE SetSmall_Oscillosc;
  BEGIN
    DeactivateWins(Small_OscilloscWins);
    ActivateWins(Small_OscilloscWins);
  END;


PROCEDURE SetSmall_Menu;
  BEGIN
    DeactivateWins(Small_MenuWins);
    ActivateWins(Small_MenuWins);
  END;


PROCEDURE SetNothing;
  BEGIN
    DeactivateWins(0);
    ActivateWins(0);
  END;


PROCEDURE SetUser(w: WORD);
  BEGIN
    DeactivateWins(w);
    ActivateWins(w);
  END;


PROCEDURE RefreshVTScreens;
  VAR
    i : WORD;
  BEGIN
    i := ActiveWindows;
    SetUser(0);
    SetUser(i);
  END;




END.
