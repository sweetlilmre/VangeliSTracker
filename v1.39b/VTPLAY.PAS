UNIT VTPlay;

INTERFACE

USES VTGlobal, VTWins, VTStrConst, StrConst,
     SongUnit, SongElements, PlayMod,
     SoundDevices,
     Output43, vid43,
     Filters, Debugging;




{----------------------------------------------------------------------------}
{ Definiciones generales                                                     }
{____________________________________________________________________________}

PROCEDURE InitPlayData(VAR Song: TSong);




{----------------------------------------------------------------------------}
{ Definiciones para la ventana de informaci¢n de posici¢n.                   }
{____________________________________________________________________________}

VAR
  LastFilterOn,
  LastFilterOff : TFilterMethod;
  LastFilter    : BOOLEAN;

PROCEDURE UpdateRunInfo(BPM, spd, patt, pos, seq, PSize: WORD);




{----------------------------------------------------------------------------}
{ Definiciones para las barras de v£metros.                                  }
{____________________________________________________________________________}

VAR
  barlen         : ARRAY[1..MaxChannels] OF BYTE;
  obarlen        : ARRAY[1..MaxChannels] OF BYTE;
  barofs         : ARRAY[1..16]          OF WORD;

PROCEDURE UpdateBars;

PROCEDURE ParseBarInit(VAR nt: TFullNote; i: WORD);




{----------------------------------------------------------------------------}
{ Definiciones para las ventanas de informaci¢n de notas.                    }
{____________________________________________________________________________}

VAR
  SampleStrings : ARRAY[1..99] OF STRING[24];
  VolumeStrings : ARRAY[0..64] OF STRING[2];

  DispVolumes   : ARRAY[1..MaxChannels] OF BYTE;
  DispNotes     : ARRAY[1..MaxChannels] OF TFullNote;
  RealVolumes   : ARRAY[1..MaxChannels] OF BYTE;
  RealNotes     : ARRAY[1..MaxChannels] OF TFullNote;

  DispSplName   : ARRAY[1..MaxChannels] OF BYTE;

PROCEDURE UpdateNoteInfo(VAR Song: TSong; VAR nt: TFullNote; i: WORD);

PROCEDURE Update2ndLine(VAR Song: TSong; NewNote: BOOLEAN);




{----------------------------------------------------------------------------}
{ Definiciones para las ventanas de informaci¢n de samples.                  }
{____________________________________________________________________________}

VAR
  DispSamples   : ARRAY[1..99] OF BYTE;
  RealSamples   : ARRAY[1..99] OF BYTE;

  siPermiso     : BOOLEAN;                  { Sample information }
  siTickForce   : BOOLEAN;
  siCounter     : BYTE;

CONST
  sfNoSample = 0;
  sfNotUsed  = 1;
  sfUsed     = 2;
  sfNowUsed  = 3;
  sfFlashing = 4;

PROCEDURE UpdateSampleInfo(VAR Song: TSong; VAR nt: TFullNote; i: WORD);

PROCEDURE TickSampleInfo;

PROCEDURE SampleAttr(s, a: BYTE);




{----------------------------------------------------------------------------}
{ Definiciones para la ventana de osciloscopio.                              }
{____________________________________________________________________________}

VAR
  OscWinBuff    : ARRAY[1..16, 1..90*2] OF CHAR;
  OscSamples    : ARRAY[1..360] OF INTEGER;

PROCEDURE UpdateOscilloscInfo;




{----------------------------------------------------------------------------}
{ Definiciones para la ventana de canal on/off.                              }
{____________________________________________________________________________}

VAR
  DispPermisos   : ARRAY[1..16] OF BOOLEAN;

PROCEDURE UpdateOnOff;




IMPLEMENTATION

USES SongUtils;

CONST
  Channels : BYTE = 0;






{----------------------------------------------------------------------------}
{ Implementaci¢n de la ventana de informaci¢n de posici¢n.                   }
{____________________________________________________________________________}

PROCEDURE UpdateRunInfo(BPM, spd, patt, pos, seq, PSize: WORD);
  CONST
    s    : STRING   = '';
    aon  : BYTE     = 0;
    aoff : BYTE     = 0;
  BEGIN

    WITH wRunInfo DO 
      IF wTopLine.vis AND wTopLine.act THEN BEGIN
        IF pos > 256 THEN pos := 1;
        STR(seq   : 3, s); DirectWrite (ParseCoords(x+wriX1,   y+1), s);
        STR(patt  : 3, s); DirectWrite (ParseCoords(x+wriX1,   y+2), s);
        STR(pos   : 3, s); DirectWrite (ParseCoords(x+wriX1,   y+3), s);
        STR(PSize : 3, s); DirectWrite (ParseCoords(x+wriX2,   y+3), s);
        STR(spd   : 3, s); DirectWrite (ParseCoords(x+wriX1,   y+4), s);
        STR(BPM   : 3, s); DirectWrite (ParseCoords(x+wriX2,   y+4), s);

        IF (LastFilter    <> FilterIsOn) OR
           (LastFilterOn  <> FilterOn)   OR
           (LastFilterOff <> FilterOff)  OR wTopLine.forz THEN BEGIN
          IF FilterIsOn THEN BEGIN
            aon  := BYTE(col[4]);
            aoff := BYTE(col[2]);
          END ELSE BEGIN
            aon  := BYTE(col[2]);
            aoff := BYTE(col[4]);
          END;
          s[0] := #1;
          s[1] := CHAR(ORD(FilterOn)  + ORD('0'));
          DirectWriteAttr(ParseCoords(x+wriX2+5, y+4), s, aon);
          s[1] := CHAR(ORD(FilterOff) + ORD('0'));
          DirectWriteAttr(ParseCoords(x+wriX2+6, y+4), s, aoff);
          LastFilter    := FilterIsOn;
          LastFilterOn  := FilterOn;
          LastFilterOff := FilterOff;
        END;

      END;

  END;




{----------------------------------------------------------------------------}
{ Implementaci¢n de las barras de v£metros.                                  }
{                                                                            }
{   DL: Valor                                                                }
{   DH: Primer cambiado                                                      }
{   CH: Tama¤o                                                               }
{   ES:SI: Pantalla                                                          }
{____________________________________________________________________________}

VAR
  bararray : ARRAY[1..16] OF BYTE;
  graybar  : ARRAY[1..16] OF BYTE;


PROCEDURE MyWriteBar; ASSEMBLER;
  ASM
                MOV     AL,[w2ndLine.act]
                AND     AL,[w2ndLine.vis]
                JZ      @@Fin

                CMP     CH,32
                JC      @@ok
                 MOV    CH,31
@@ok:
                INC     CH
                SHR     CH,1
                INC     DH
                SHR     DH,1

                MOV     DI,OFFSET bararray

                MOV     AL,DH
                XOR     AH,AH

                ADD     DI,AX
                ADD     SI,AX
                ADD     SI,AX
                SUB     CH,DH
                SUB     DL,DH
                SUB     DL,DH

                TEST    DL,$80
                JNZ     @@nobar

                PUSH    DX
                INC     DL
                SHR     DL,1
                CALL    @@dolp
                POP     DX
                TEST    DL,1
                JZ      @@nobar
                INC     [BYTE PTR ES:SI-2]

@@nobar:        MOV     DL,CH
                MOV     DI,OFFSET graybar

@@dolp:         OR      DL,DL
                JZ      @@Fin
                OR      CH,CH
                JZ      @@Fin
@@lp:            MOV    AL,BarVal
                 MOV    AH,[DI]
                 MOV    [ES:SI],AX
                 INC    SI
                 INC    SI
                 INC    DI
                 DEC    CH
                 JZ     @@Fin
                 DEC    DL
                 JNZ    @@lp
@@Fin:
  END;



PROCEDURE WriteBar(i: WORD); ASSEMBLER;
  ASM
        MOV     AX,i
        DEC     AX
        MOV     BX,OFFSET barlen
        MOV     DI,OFFSET obarlen
        ADD     BX,AX
        ADD     DI,AX
        MOV     DL,[BX]
        MOV     CH,DL
        MOV     DH,[DI]
        CMP     CH,DH
        JZ      @@Fin
        JNC     @@ok
         XCHG   DH,CH
@@ok:
        MOV     [DI],DL
        AND     AL,15
        MOV     SI,ScrSegment
        CMP     SI,$A000
        JC      @@Fin
        MOV     ES,SI
        MOV     SI,OFFSET barofs
        ADD     SI,AX
        ADD     SI,AX
        MOV     SI,[SI]
        CALL    MyWriteBar
@@Fin:
  END;




PROCEDURE WriteBarForced(i: WORD); ASSEMBLER;
  ASM
{
PUSH    DS
MOV     AX,$B800
MOV     DS,AX
INC     [WORD PTR 4]
POP     DS
}
        MOV     AX,i
        DEC     AX
        MOV     BX,OFFSET barlen
        MOV     DI,OFFSET obarlen
        ADD     BX,AX
        ADD     DI,AX
        MOV     DL,[BX]
        MOV     [DI],DL
        MOV     CH,32
        MOV     DH,0
        AND     AL,15
        MOV     SI,ScrSegment
        CMP     SI,$A000
        JC      @@Fin
        MOV     ES,SI
        MOV     SI,OFFSET barofs
        ADD     SI,AX
        ADD     SI,AX
        MOV     SI,[SI]
        CALL    MyWriteBar
@@Fin:
  END;




PROCEDURE InitBar(i, l: WORD);
  BEGIN
    IF l > 32 THEN l := 32;
    barlen[i] := l+1;
    IF Permisos[i] THEN
      IF w2ndLine.forz THEN
        WriteBarForced(i)
      ELSE
        WriteBar(i);
  END;



PROCEDURE UpdateBars;
  CONST
    i : WORD = 0;
  BEGIN
    FOR i := 1 TO 16{MaxChannels} DO
      BEGIN
        IF NOT Permisos[i] THEN barlen[i] := 0;
        IF barlen[i] > 0 THEN
          DEC(barlen[i]);
        IF w2ndLine.act AND w2ndLine.vis THEN
          IF w2ndLine.forz THEN
            WriteBarForced(i)
          ELSE
            WriteBar(i)
      END;
  END;





PROCEDURE ParseBarInit(VAR nt: TFullNote; i: WORD);
  BEGIN

    IF      nt.Command     = mcSetVolume THEN InitBar(i, nt.Parameter      SHR 1)
    ELSE IF nt.Instrument <> 0           THEN InitBar(i, Canales[i].Volume SHR 1)
    ELSE IF nt.Period     <> 0           THEN InitBar(i, RealVolumes[i]    SHR 1);

  END;




{----------------------------------------------------------------------------}
{ Implementaci¢n de las ventanas de informaci¢n de notas.                    }
{____________________________________________________________________________}

PROCEDURE UpdateNoteInfo(VAR Song: TSong; VAR nt: TFullNote; i: WORD);
  CONST
    s        : STRING         = '';
    MySample : BYTE           = 0;
    vol      : WORD           = 0;
    f        : BOOLEAN        = FALSE;
    p        : PFullNote      = NIL;
    Instr    : PInstrumentRec = NIL;
  BEGIN
    Channels := Song.NumChannels;

    IF w2ndLine.forz AND w2ndLine.vis AND w2ndLine.act AND (i <= 16) THEN
      BEGIN
        STR(i : 2, s);
        WITH wChannelNum DO
          DirectWrite(ParseCoords(x+1, y+i), s);

        IF NOT PlayMod.Permisos[i] THEN
          BEGIN
            WITH wInfoNote  DO DirectWrite(ParseCoords(x+1, y+i), '                            ');
            WITH wRunSample DO DirectWrite(ParseCoords(x+1, y+i), '                        ');
          END;
      END;

    p := @DispNotes[i];

    WITH RealNotes[i] DO BEGIN

      IF (nt.Period <> Period) AND (nt.Period <> 0) THEN
        Period := nt.Period
      ELSE
        Period := p^.Period;

      IF (nt.Instrument <> Instrument) AND (nt.Instrument <> 0) THEN
        Instrument := nt.Instrument
      ELSE
        Instrument := p^.Instrument;

      vol := $FFFF;

      IF (nt.Period <> 0) OR (nt.Instrument <> 0) THEN vol := Canales[i].Volume;
      IF nt.Command = mcSetVolume THEN vol := nt.Parameter;

      IF (vol <> $FFFF) AND (vol <> RealVolumes[i]) THEN
        RealVolumes[i] := vol
      ELSE
        vol := RealVolumes[i];

      IF w2ndLine.act AND w2ndLine.vis AND PlayMod.Permisos[i] THEN BEGIN
        IF w2ndLine.forz OR (p^.Period <> Period) THEN BEGIN
          IF Period <> 0 THEN
            BEGIN
              p^.Period := Period;

              IF i <= 16 THEN
                BEGIN
                  NoteFreq(Period, s);
                  WITH wInfoNote DO DirectWrite(ParseCoords(x+winX1, y+i), s);
                END;
            END;
        END;

        IF w2ndLine.forz OR (Instrument <> p^.Instrument) THEN BEGIN
          p^.Instrument := Instrument;
          IF i <= 16 THEN
            WITH wInfoNote DO
              BEGIN
                Instr := PInstrument(Song.GetInstrument(p^.Instrument))^.Instr;
                IF Instr <> NIL THEN
                  BEGIN
                    STR(Instr^.reps : 6, s); DirectWrite(ParseCoords(x+winX3, y+i), s);
                    STR(Instr^.repl : 6, s); DirectWrite(ParseCoords(x+winX4, y+i), s);
                    STR(Instr^.len  : 6, s); DirectWrite(ParseCoords(x+winX5, y+i), s);
                  END
                ELSE
                  BEGIN
                    DirectWrite(ParseCoords(x+winX3, y+i), '      ');
                    DirectWrite(ParseCoords(x+winX4, y+i), '      ');
                    DirectWrite(ParseCoords(x+winX5, y+i), '     ');
                  END;
              END;
        END;

        IF w2ndLine.forz OR (Instrument <> DispSplName[i]) THEN BEGIN
          DispSplName[i]   := Instrument;
          IF i <= 16 THEN
            WITH wRunSample DO
              IF Instrument <> 0 THEN
                DirectWrite(ParseCoords(x+1, y+i), SampleStrings[Instrument])
              ELSE
                DirectWrite(ParseCoords(x+1, y+i), '                        ');
        END;

        IF w2ndLine.forz OR (DispVolumes[i] <> vol) THEN BEGIN
          DispVolumes[i]   := vol;
          IF i <= 16 THEN
            WITH wInfoNote DO
              IF DispVolumes[i] <> $FF THEN
                DirectWrite(ParseCoords(x+winX2, y+i), VolumeStrings[vol])
              ELSE
                DirectWrite(ParseCoords(x+winX2, y+i), '  ');
        END;

      END;
    END;
  END;




PROCEDURE SampleAttr(s, a: BYTE);
  BEGIN
    IF s > 60 THEN EXIT;

    IF s > 40 THEN
      WITH wSamples3 DO RectAttr(ParseCoords(x+wsX1, y+s-40), 25, 1, a)
    ELSE IF s > 20 THEN
      WITH wSamples2 DO RectAttr(ParseCoords(x+wsX1, y+s-20), 25, 1, a)
    ELSE
      WITH wSamples1 DO RectAttr(ParseCoords(x+wsX1, y+s),    25, 1, a);
  END;




PROCEDURE UpdateSampleInfo(VAR Song: TSong; VAR nt: TFullNote; i: WORD);
  CONST
    j      : WORD = 0;
  LABEL
    Passa;
  BEGIN                 
    IF i = 1 THEN BEGIN
      FOR j := 1 TO 60 DO
        IF RealSamples[j] >= sfNowUsed THEN
          RealSamples[j] := sfUsed;
    END;

    IF Permisos[i] AND (RealNotes[i].Instrument <> 0) THEN
      IF (nt.Instrument <> 0) OR (nt.Period <> 0) OR ((nt.Command = mcSetVolume) AND (nt.Parameter <> 0)) THEN
        RealSamples[RealNotes[i].Instrument] := sfFlashing
      ELSE
        IF RealSamples[RealNotes[i].Instrument] <> sfFlashing THEN
          RealSamples[RealNotes[i].Instrument] := sfNowUsed;

    IF i = Song.NumChannels THEN BEGIN
{
      siCounter := NoteSound^.Tempo-1;
      IF siCounter < 2 THEN siCounter := 2;
}
siCounter := 0;

      WITH wSamples DO BEGIN
        siPermiso := act AND vis;

        IF siPermiso AND forz THEN BEGIN
{          InitSampleWin(Song);}
          siTickForce := forz;
{          TickSampleInfo;}
        END;

        forz := FALSE;
      END;
    END;
  END;




PROCEDURE TickSampleInfo;
  CONST
    i  : WORD = 0;
    vl : BYTE = 0;
  BEGIN
    WITH wSamples DO 
      IF NOT (act AND vis) THEN EXIT;

    INC(siCounter);

    FOR i := 1 TO 60 DO BEGIN
      vl := RealSamples[i];
      IF (siCounter > NoteSound^.Tempo) AND (vl = sfFlashing) THEN
        BEGIN
          vl             := sfNowUsed;
          RealSamples[i] := sfNowUsed;
        END;

      IF (vl > sfNoSample) AND ((vl <> DispSamples[i]) OR siTickForce) THEN
        BEGIN
          DispSamples[i] := vl;

          IF siPermiso THEN
            SampleAttr(i, BYTE(wSamples.col[vl+4]));
        END;
    END;

    siTickForce := FALSE;

  END;




PROCEDURE UpdateOnOff;
  CONST
    Strn : ARRAY[0..1] OF STRING[3] = ('OFF', 'ON ');
    i    : WORD = 0;
  BEGIN
    IF w2ndLine.act AND w2ndLine.vis THEN
      FOR i := 1 TO 16 DO
        IF i > Channels THEN
          BEGIN
            DispPermisos[i] := FALSE;
            WITH wVoiceOnOff DO DirectWrite(ParseCoords(x+1, y+i), Strn[0]);
          END
        ELSE IF w2ndLine.forz OR (Permisos[i] <> DispPermisos[i]) THEN
          BEGIN
            DispPermisos[i] := Permisos[i];
            WITH wVoiceOnOff DO DirectWrite(ParseCoords(x+1, y+i), Strn[ORD(Permisos[i])]);
          END;
  END;




PROCEDURE Update2ndLine(VAR Song: TSong; NewNote: BOOLEAN);
  VAR
    i : WORD;
  BEGIN

    UpdateOnOff;
    UpdateBars;

    IF w2ndLine.forz AND w2ndLine.act AND w2ndLine.vis THEN
      WITH wPanning DO BEGIN
        FOR i := 1 TO 16 DO
          IF Song.PanPositions[i] < $80 THEN
            DirectWriteAttr(ParseCoords(x+1, y+i), 'õöõõõõ', BYTE(col[1]))
          ELSE
            DirectWriteAttr(ParseCoords(x+1, y+i), 'õõõõ÷õ', BYTE(col[1]));
      END;

    IF NewNote THEN
      w2ndLine.forz := FALSE;

  END;




PROCEDURE PutStr(VAR Buf; VAR s: STRING; c: BYTE);
  CONST
    i : WORD = 0;
  VAR
    CBuf : ARRAY[1..32000, 1..2] OF BYTE ABSOLUTE Buf;
  BEGIN

    FOR i := 1 TO Length(s) DO BEGIN
      CBuf[i][1] := BYTE(s[i]);
      CBuf[i][2] := c;
    END;

  END;




{
PROCEDURE FillWithSamples(VAR Buff; Size: WORD);
  VAR
    mBuff : ARRAY[0..FinalBufferSize-1] OF INTEGER ABSOLUTE Buff;
  BEGIN
    IF FinalBufferPos >= Size THEN
      Move(FinalBuffer[FinalBufferPos - Size], mBuff, Size*2)
    ELSE
      Move(FinalBuffer[FinalBufferSize - Size], mBuff, Size*2)
  END;
}


PROCEDURE UpdateOscilloscInfo;
  CONST
    Count    : WORD = 0;
    Semaphor : BYTE = 0;
    i        : WORD = 0;
    j        : WORD = 0;
    ofs      : WORD = 0;
  LABEL
    Fin;
  BEGIN
    IF Semaphor > 0 THEN EXIT;

    INC(Semaphor);

    WITH wOscillosc DO BEGIN
      IF NOT (act AND vis) THEN GOTO Fin;

      INC(Count);
      IF Count < 1 THEN GOTO Fin;

      Count := 0;

      IF UsingGUS THEN
        BEGIN
          IF forz THEN
            DirectWriteAttr(ParseCoords(x+1, y+9), GetString(StrGUSOscillosc), BYTE(col[1]));
          GOTO Fin;
        END;

      FillWithSamples(OscSamples, 82*4);

      ASM
        CLD
        MOV     CX,16
        MOV     DI,OFFSET OscWinBuff + 8
        PUSH    DS
        POP     ES
        MOV     DX,90*2 - 82*2
        MOV     AH,BYTE PTR [wOscillosc.col[2]]
        XOR     AL,AL
@@lp1:   PUSH   CX
         MOV    CX,82
         REP STOSW
         POP    CX
         ADD    DI,DX
         LOOP   @@lp1
      END;
      ASM

        CLD
        MOV     CH,82
        MOV     SI,OFFSET OscSamples
        MOV     BX,OFFSET OscWinBuff + 8
@@lp1:   MOV    CL,4
@@lp2:    LODSW
          XOR   AH,$80

          XOR   DX,DX
          MOV   DI,65536/16/3 - 1
          DIV   DI

          MOV   DL,3
          DIV   DL
          MOV   DL,AH
          INC   DL

          MOV   DI,CX
          DEC   CL
          ADD   CL,CL
          SHL   DL,CL
          MOV   CX,DI

          MOV   DH,90*2
          MUL   DH
          ADD   AX,BX
          XCHG  BX,AX
          ADD   [BX],DL
          XCHG  BX,AX

          DEC   CL
          JNZ   @@lp2
         INC    BX
         INC    BX
         DEC    CH
         JNZ    @@lp1

      END;

      Ofs := ParseCoords(x+4, y+3);
      FOR i := 1 TO 16 DO BEGIN
        Move(OscWinBuff[i][9], Ptr(ScrSegment, Ofs)^, 82*2);
        INC(Ofs, ScreenBytesX);
      END;

    END;

Fin:
    wOscillosc.forz := FALSE;

    DEC(Semaphor);

  END;




PROCEDURE InitPlayData(VAR Song: TSong);
  CONST
    i     : WORD           = 0;
    j     : WORD           = 0;
    Instr : PInstrumentRec = NIL;
  BEGIN

    LastFilterOn  := fmNone;
    LastFilterOff := fmNone;
    LastFilter    := FALSE;

    FillChar(barlen,  SizeOf(barlen),  0);
    FillChar(Obarlen, SizeOf(Obarlen), 0);
    FillChar(graybar, SizeOf(graybar), wPlayBars.col[1]);
    WITH wPlayBars DO BEGIN
      FOR i := 1 TO 16 DO
        BEGIN
          barofs[i]   := ParseCoords(wPlayBars.x + 1, wPlayBars.y + i);
          IF i < 13 THEN
            bararray[i] := BYTE(col[2])
          ELSE
            bararray[i] := BYTE(col[3]);
        END;
      forz := TRUE;
      act  := TRUE;
      vis  := TRUE;
    END;

    FOR i := 0 TO 64 DO
      STR(i : 2, VolumeStrings[i]);

    FillChar(DispVolumes, SIZEOF(DispVolumes), $FF);
    FillChar(DispNotes,   SIZEOF(DispNotes),   0);
    FillChar(RealVolumes, SIZEOF(RealVolumes), $FF);
    FillChar(RealNotes,   SIZEOF(RealNotes),   0);

    FillChar(DispSplName, SIZEOF(DispSplName), 0);

    FillChar(DispSamples, SIZEOF(DispSamples), sfNoSample);
    FillChar(RealSamples, SIZEOF(RealSamples), sfNoSample);

    IF @Song <> NIL THEN
      FOR i := 1 TO Song.Instruments.Count DO BEGIN
        STR(i : 2, SampleStrings[i]);
        SampleStrings[i] := SampleStrings[i] + ' ' + Song.GetInstrument(i)^.GetName;
        Instr := Song.GetInstrument(i)^.Instr;
        IF (Instr <> NIL) AND (Instr^.Len <> 0) THEN
          BEGIN
            DispSamples[i] := sfNotUsed;
            RealSamples[i] := sfNotUsed;
          END;
      END;

    siTickForce    := FALSE;
    siPermiso      := TRUE;
    siCounter      := 0;

    FillChar(DispPermisos, SIZEOF(DispPermisos), 0);
  END;





END.
