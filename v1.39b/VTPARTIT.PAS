UNIT VTPartitura;

INTERFACE

USES SongUnit, PlayMod,
     Output43;

VAR
  IsBig       : BOOLEAN;
  PartWin     : PWindow;
{
  ForceReDraw : BOOLEAN;
}





PROCEDURE SetPartWindow(x, y, p, f: WORD);

PROCEDURE SetBigPartWindow;

PROCEDURE SetSmallPartWindow;

PROCEDURE DrawPartiture(VAR Song: TSong; mdpos, mdseq: WORD);




IMPLEMENTATION

USES VTPlay, VTWins, VTBitmaps,
     SongUtils, SongElements,
     HexConversions;

TYPE
  TFullNoteStr = STRING[20];

VAR
  wx, wn,
  py, fy,
  hp, hf,

  PastNotes,
  FutNotes,
  TotNotes,
  ActNote,
  FirstNote   : WORD;

  ps          : ARRAY[1..53] OF ARRAY[1..4] OF TFullNoteStr;
  fs          : ARRAY[1..53] OF ARRAY[1..4] OF BOOLEAN;
  ls          : ARRAY[1..53] OF ARRAY[1..4] OF TFullNote;

  Permit      : ARRAY[1..4] OF BOOLEAN;

  omdpos,
  omdseq      : WORD;

  wPastIdx,
  wActIdx,
  wFutIdx     : TWindow;
  wPast,
  wAct,
  wFut        : TChWindows;





PROCEDURE SetPartWindow(x, y, p, f: WORD);
  BEGIN
    wx := x;
    wn := 20;
    py := y;
    fy := y + p + 5;
    hp := p + 2;
    hf := f + 2;

    FillChar(Permit, SIZEOF(Permit), 0);

    PastNotes   := p;
    FutNotes    := f;
    TotNotes    := p+f+1;
    ActNote     := p+1;
  END;




PROCEDURE SetBigPartWindow;
  BEGIN
    wPastIdx := wPartPastBIdx;
    wActIdx  := wPartActBIdx;
    wFutIdx  := wPartFutBIdx;
    wPast    := wPartPastBig;
    wAct     := wPartActBig;
    wFut     := wPartFutBig;
    PartWin  := @wPartBig;

    PastNotes   := 26;
    FutNotes    := 26;
    TotNotes    := 53;
    ActNote     := 27;
    IsBig       := TRUE;
  END;




PROCEDURE SetSmallPartWindow;
  BEGIN
    wPastIdx := wPartPastIdx;
    wActIdx  := wPartActIdx;
    wFutIdx  := wPartFutIdx;
    wPast    := wPartPast;
    wAct     := wPartAct;
    wFut     := wPartFut;
    PartWin  := @wPartSmall;

    PastNotes   := 7;
    FutNotes    := 7;
    TotNotes    := 15;
    ActNote     := 8;
    IsBig       := FALSE;
  END;





PROCEDURE InsertStr(VAR s, t: STRING; p: WORD); ASSEMBLER;
  ASM
        PUSH    DS
        CLD
        LDS     SI,t
        LES     DI,s
        MOV     AX,p
        ADD     DI,AX
        LODSB
        MOV     CL,AL
        XOR     CH,CH
        REP MOVSB
        POP     DS
  END;



PROCEDURE StrNote(nt: TFullNote; VAR s: TFullNoteStr);
  CONST
    Commands : ARRAY[mcNone..mcLast] OF STRING[5] = (
      'תתתת',

      'ARPG', 'TPUP', 'TPDN', 'NOTP',
      'VIBR', 'TVSL', 'VVSL', 'TREM',
      'XX-1', 'SOFF', 'VSLD', 'JUMP',
      'VOLM', 'BRCK', 'XX-2', 'TEMP',

      'FILT', 'FPUP', 'FPDN', 'GLIS',
      'VCTL', 'FTUN', 'LOOP', 'TRMC',
      '?? 3', 'RETN', 'VFUP', 'VFDN',
      'NCUT', 'NDLY', 'PDLY', 'FUNK',

      'ARP1', 'ARP2', 'S3MR',

      'תתתת'
    );
  VAR
    bs : STRING[16];
  BEGIN

    s := ' תתתתתתתתתתתתתתתתתת ';

    IF (nt.Period <> 0) OR (nt.Instrument <> 0) THEN
      BEGIN
        s[8] := ' ';
        s[5] := ' ';

        IF nt.Period = 0 THEN
          BEGIN
            bs := '---';
            InsertStr(s, bs, 2);
          END
        ELSE
          BEGIN
            NoteFreq(nt.Period, bs);
            InsertStr(s, bs, 2);
          END;

        IF nt.Instrument = 0 THEN
          BEGIN
            bs := '--';
            InsertStr(s, bs, 6);
          END
        ELSE
          BEGIN
            STR(nt.Instrument : 2, bs);
            IF bs[1] = ' ' THEN bs[1] := '0';
            InsertStr(s, bs, 6);
	  END;
      END;

    IF nt.Volume <> 0 THEN
      BEGIN
        s[9]  := ' ';
        s[12] := ' ';
        STR(nt.volume-1 : 2, bs);
        IF bs[1] = ' ' THEN
          s[10] := '0'
        ELSE
          s[10] := bs[1];
        s[11] := bs[2];
      END;

    IF nt.Command <> mcNone THEN
      BEGIN
        s[12] := ' ';
        s[17] := ' ';

        IF nt.Command < mcLast THEN
          InsertStr(s, Commands[nt.Command], 13)
        ELSE
          BEGIN
            STR(ORD(nt.Command) - ORD(mcLast) : 2, bs);
            bs := 'X-'+bs;
            InsertStr(s, bs, 13);
          END;

        bs := HexByte(nt.Parameter);
        InsertStr(s, bs, 18);
      END;
  END;




PROCEDURE DrawPartiture(VAR Song: TSong; mdpos, mdseq: WORD);
  CONST
    EmptyLine : STRING[20] = '                    ';
    count : WORD = 0;
  VAR
    PattSize : WORD;
    nn   : WORD;
    n, w,
    k, p : INTEGER;
    i, j : WORD;
    nt   : TFullNote;
    strn : STRING;
  BEGIN

    IF NOT (PartWin^.vis AND PartWin^.act) THEN EXIT;

    FOR j := 1 TO 4 DO BEGIN

      IF PartWin^.forz THEN
        BEGIN
          STR(FirstChannel-1+j : 2, strn);
          WITH wPast[j] DO 
            DirectWriteAttr(ParseCoords(x+13, y), strn, BYTE(col[4]));
        END;


      IF NOT Permisos[FirstChannel - 1 + j] THEN BEGIN
        IF {Permit[j] OR }PartWin^.forz THEN BEGIN
          WITH wPast[j] DO BEGIN
            FOR i := 1 TO PastNotes DO
              DirectWriteAttr(ParseCoords(x + 1, y+i), EmptyLine, BYTE(col[3]));
            WriteVTLogo(ParseCoords(x + 7, y+(PastNotes - 1) DIV 2 - 1));
          END;

          WITH wAct[j] DO BEGIN
            FOR i := 1 TO 2 DO
              DirectWriteAttr(ParseCoords(x + 1, y+i), EmptyLine, BYTE(col[1]));
            WriteVTNoPartAct(ParseCoords(x + 3, y+1));
          END;

          WITH wFut[j] DO BEGIN
            FOR i := 1 TO FutNotes DO
              DirectWriteAttr(ParseCoords(x + 1, y+i), EmptyLine, BYTE(col[3]));
            WriteVTLogo(ParseCoords(x + 7, y+(FutNotes - 1) DIV 2 - 1));
          END;
        END;
      END;

      Permit[j] := Permisos[FirstChannel - 1 + j];
    END;
{
    PartWin^.forz := TRUE;
}
    PattSize := 0;
    IF (Song.GetPatternSeq(mdseq)       <> NIL) AND
       (Song.GetPatternSeq(mdseq)^.Patt <> NIL) THEN
      PattSize := Song.GetPatternSeq(mdseq)^.Patt^.NNotes;

    IF PartWin^.forz OR (mdseq <> omdseq) OR
       (WORD(mdpos - omdpos) >= FutNotes) THEN BEGIN

      FirstNote := 1;

      n := mdpos - PastNotes;
      w := 1;

      FOR i := 1 TO PastNotes + FutNotes + 1 DO
        BEGIN
          IF (WORD(n) <= PattSize) AND (n <> 0) THEN
            FOR j := 1 TO 4 DO
              BEGIN
                Song.GetNote(mdseq, n, FirstChannel - 1 + j, nt);
                ls[w][j] := nt;
                fs[w][j] := TRUE;
                StrNote(nt, ps[w][j]);
              END
          ELSE
            FOR j := 1 TO 4 DO
              BEGIN
                ls[w][j].Instrument := $FF;
                fs[w][j] := TRUE;
                ps[w][j] := '                    ';
              END;
          INC(n); INC(w);
        END;

    END ELSE BEGIN

      k := mdpos - omdpos;
      IF k = 0 THEN EXIT;
      IF k > 0 THEN BEGIN
        p := 1;
        n := omdpos + FutNotes + 1;
      END;

      w  := FirstNote;
      nn := ((FirstNote - 1 + TotNotes + k) MOD TotNotes) + 1;
      FOR i := 1 TO TotNotes - k DO BEGIN
        FOR j := 1 TO 4 DO
          fs[nn][j] := NOT FullNotesEqual(ls[nn][j], ls[w][j]);
        w  := (w  MOD TotNotes) + 1;
        nn := (nn MOD TotNotes) + 1;
      END;

      w := FirstNote;
      FirstNote := ((FirstNote - 1 + TotNotes + k) MOD TotNotes) + 1;

      FOR i := 1 TO ABS(k) DO BEGIN
        IF (WORD(n) <= PattSize) AND (n <> 0) THEN
          FOR j := 1 TO 4 DO
            BEGIN
              Song.GetNote(mdseq, n, FirstChannel - 1 + j, nt);
              ls[w][j] := nt;
              fs[w][j] := TRUE;
              StrNote(nt, ps[w][j]);
            END
        ELSE
          FOR j := 1 TO 4 DO
            BEGIN
              fs[w][j] := ls[w][j].Instrument <> $FF;
              ls[w][j].Instrument := $FF;
              ps[w][j] := '                    ';
            END;
        INC(n, p);
        w := ((w - 1 + TotNotes + p) MOD TotNotes) + 1;
      END;

    END;

    n  := FirstNote;
    nn := mdpos - PastNotes;

    FOR i := 1 TO PastNotes DO BEGIN
      WITH wPastIdx DO BEGIN
        STR(nn : 3, strn);
        IF (nn <= PattSize) AND (nn <> 0) THEN
          DirectWriteAttr(ParseCoords(x+1, y+i), strn, BYTE(col[1]))
        ELSE
          DirectWriteAttr(ParseCoords(x+1, y+i), '   ', BYTE(col[2]));
      END;

{
      IF ps[n][1][0] <> #0 THEN
}
        FOR j := 1 TO 4 DO
          IF fs[n][j] THEN
            IF Permisos[FirstChannel - 1 + j] THEN
              WITH wPast[j] DO IF ls[n][j].Instrument = $FF THEN
                DirectWriteAttr(ParseCoords(x + 1, y+i), ps[n][j], BYTE(col[2]))
              ELSE
                DirectWriteAttr(ParseCoords(x + 1, y+i), ps[n][j], BYTE(col[1]));
      n := (n MOD TotNotes) + 1;
      INC(nn);
    END;

    WITH wActIdx DO BEGIN
      IF nn < 100 THEN
        STR(nn : 3, strn)
      ELSE
        strn := '   ';
      DirectWriteBig(ParseCoords(x+1, y+1), strn)
    END;

    FOR j := 1 TO 4 DO
      IF fs[n][j] THEN
        IF Permisos[FirstChannel - 1 + j] THEN
          WITH wAct[j] DO BEGIN
            RectAttr       (ParseCoords(x+1, y+1), 18, 2, BYTE(col[1]));
            DirectWriteBig (ParseCoords(x+1, y+1), ps[n][j]);
          END;
    n := (n MOD TotNotes) + 1;
    INC(nn);

    FOR i := 1 TO FutNotes DO BEGIN
      WITH wFutIdx DO BEGIN
        STR(nn : 3, strn);
        IF (nn <= PattSize) AND (n <> 0) THEN
          DirectWriteAttr(ParseCoords(x+1, y+i), strn, BYTE(col[1]))
        ELSE
          DirectWriteAttr(ParseCoords(x+1, y+i), '   ', BYTE(col[2]));
      END;

{
      IF ps[n][1][0] <> #0 THEN
}
        FOR j := 1 TO 4 DO
          IF fs[n][j] THEN
            IF Permisos[FirstChannel - 1 + j] THEN
              WITH wFut[j] DO IF ls[n][j].Instrument = $FF THEN
                DirectWriteAttr(ParseCoords(x + 1, y+i), ps[n][j], BYTE(col[2]))
              ELSE
                DirectWriteAttr(ParseCoords(x + 1, y+i), ps[n][j], BYTE(col[1]));
      n := (n MOD TotNotes) + 1;
      INC(nn);
    END;

    omdseq := mdseq;
    omdpos := mdpos;

    PartWin^.forz := FALSE;

  END;




END.
