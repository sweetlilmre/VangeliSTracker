{****************************************************************************}
{                                                                            }
{ MODULE:         ModCommands                                                }
{                                                                            }
{ DESCRIPTION:    This UNIT implements the routines that interpret the       }
{                 various commands that appear in a MOD file`s partiture     }
{                                                                            }
{                 It's independent of the number of channels used.           }
{                                                                            }
{                 Designed for use from within the PlayMod UNIT.             }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet... ;-)                                         }
{                                                                            }
{ HISTORY:        02-Jan-1993 Creation/definition. It used to be part of the }
{                             PlayMod UNIT, but it was getting too big.      }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT ModCommands;

INTERFACE

USES SongUnit, SongElements;




{ Configuration. }

CONST
  MyLoopMod          : BOOLEAN       = FALSE;  { If TRUE, then the MOD will loop if it was so defined.  }
  PermitFilterChange : BOOLEAN       = FALSE;  { TRUE if the partiture is allowed to change the filter. }
  BPMDivider         : WORD          = 125;
  BPMIncrement       : WORD          = 125;
  BPMCount           : WORD          = 0;
  MyFirstPattern     : WORD          = 0;
  MyRepStart         : WORD          = 0;
  MySongLen          : WORD          = 0;
  FirstPattern       : WORD          = 0;
  RepStart           : WORD          = 0;
  SongLen            : WORD          = 0;




{ Values common to all the channels. }

CONST
  FilterIsOn         : BOOLEAN       = FALSE;  { Position of the filter (FALSE = OFF).                  }
  Tempo              : BYTE          = 6;      { Number of ticks in the current note.                   }




{ Values set from outside this UNIT, apart from this one. }

CONST
  NextNote           : WORD          = 1;      { Next note in the pattern.                              }
  NextSeq            : WORD          = 1;      { Next pattern index (for the next note).                }
                                               { They both must have been set BEFORE calling this UNIT. }

  TempoCt            : BYTE          = 0;      { Number of the actual tick. Not changed in this UNIT.   }




{ General definition of the state of a channel. }

TYPE                       { Channel state definition. }
  PCanal = ^TCanal;
  TCanal = RECORD
    Note       : TFullNote;      { Note being played in the channel.   }
    Instrument : PInstrumentRec; { Pointer to the instrument data.     }
    Volume     : BYTE;           { Actual volume (0 - 64).             }
    Period     : WORD;           { Actual Period.                      }
    RealPeriod : WORD;           { Actual adjusted Period.             }

    PeriodIncr,                  { Note portamento increment.          }
    PeriodDest : INTEGER;        { Note portamento destination.        }

    arpct      : BYTE;           { Arpeggio count.                     }
    arp0,                        { Arpeggio 1st Period.                }
    arp1,                        { Arpeggio 2nd Period.                }
    arp2       : WORD;           { Arpeggio 3rd Period.                }

    VibWave,                     { Vibrato wave form.                  }
    VibPos,                      { Vibrato position.                   }
    VibWidth,                    { Vibrato width (period).             }
    VibDepth   : BYTE;           { Vibrato depth (amplitude).          }
    VibReset   : BOOLEAN;        { Vibrato reset.                      }

    TPortaIncr : INTEGER;        { Tone portamento increment.          }
    VolumeIncr : SHORTINT;       { Volume increment.                   }
    TPortIsFine: BOOLEAN;
    VSldIsFine : BOOLEAN;

    RetrigCt   : BYTE;
    RetrigVal  : BYTE;
    DoRetrig   : BOOLEAN;

    SOffs      : BOOLEAN;
    SOffsVal   : WORD;

    S3mRetAdd  : BOOLEAN;
    S3mRetVal  : SHORTINT;
  END;




PROCEDURE DoTickCommand; 
PROCEDURE CommandStart  (VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);




IMPLEMENTATION

USES SongUtils, SoundDevices;



{----------------------------------------------------------------------------}
{ Rutinas de comandos, para el comienzo y cada Tick.                         }
{                                                                            }
{ En las del tick, se entra con SI apuntando al TCanal correspondiente.      }
{____________________________________________________________________________}


{ 0 xx }

PROCEDURE StartArpeggio(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  CONST
    ArpTable : ARRAY[0..15] OF WORD = ( $4000,$43CE,$47D6,$4C1B,
                                        $50A2,$556D,$5A82,$5FE4,
                                        $6597,$6BA2,$7209,$78D0,
                                        $8000,$879B,$8FAD,$9837 );
  VAR
    f, g: LONGINT;
  BEGIN
    can.arpct := 0;

    f := n.Period;
    IF f = 0 THEN f := can.Note.Period;

    g := f SHL 14;

    can.arp0 := f;
    can.arp1 := g DIV ArpTable[can.Note.Parameter SHR  4];
    can.arp2 := g DIV ArpTable[can.Note.Parameter AND $F];
  END;

PROCEDURE TickArpeggio;    ASSEMBLER;
  ASM

        INC     TCanal([SI]).arpct
        MOV     AL,TCanal([SI]).arpct
        DEC     AL
        JNZ     @@2
         MOV    AX,TCanal([SI]).arp0
         MOV    TCanal([SI]).Period,AX
        JMP    @@Fin
@@2:    DEC     AL
        JNZ     @@3
         MOV    AX,TCanal([SI]).arp1
         MOV    TCanal([SI]).Period,AX
        JMP    @@Fin
@@3:     MOV    AX,TCanal([SI]).arp2
         MOV    TCanal([SI]).Period,AX
         MOV    TCanal([SI]).arpct,0
@@Fin:
  END;


{ 1 xx , 2 xx }

PROCEDURE StartFinePortaUp  (VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote); FORWARD;

PROCEDURE StartFinePortaDown(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote); FORWARD;

PROCEDURE StartTPortUp(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter <> 0 THEN
      BEGIN
        can.TPortaIncr  := WORD(n.Parameter) SHL 2;
        can.TPortIsFine := FALSE;
      END
    ELSE IF can.TPortIsFine THEN
      BEGIN
        can.Note.Command := mcFinePortaUp;
        StartFinePortaUp(Song, can, n);
      END;
  END;

PROCEDURE StartTPortDown(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter <> 0 THEN
      BEGIN
        can.TPortaIncr  := WORD(n.Parameter) SHL 2;
        can.TPortIsFine := FALSE;
      END
    ELSE IF can.TPortIsFine THEN
      BEGIN
        can.Note.Command := mcFinePortaDn;
        StartFinePortaDown(Song, can, n);
      END;
  END;

PROCEDURE TickTPortUp; ASSEMBLER;
  ASM

        MOV     AX,TCanal([SI]).Note.Period
        SUB     AX,TCanal([SI]).TPortaIncr
{
        JNC     @@c
          XOR   AX,AX
    @@c:
}
{
        JC      @@c2
        CMP     AX,$39
        JA      @@c1
    @@c2:MOV    AX,$39
    @@c1:
}
        MOV     TCanal([SI]).Note.Period,AX
        MOV     TCanal([SI]).Period,AX

  END;


PROCEDURE TickTPortDown; ASSEMBLER;
  ASM

        MOV     AX,TCanal([SI]).Note.Period
        ADD     AX,TCanal([SI]).TPortaIncr
{
        CMP     AX,$6B0
        JB      @@c1
         MOV    AX,$6B0
    @@c1:
}
        MOV     TCanal([SI]).Note.Period,AX
        MOV     TCanal([SI]).Period,AX

  END;


{ 3 xy }

PROCEDURE StartNPortamento(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Period <> 0 THEN
      can.PeriodDest := n.Period
    ELSE IF can.PeriodDest = 0 THEN
      can.PeriodDest := can.Period;

    IF n.Parameter = 0 THEN BEGIN
      IF can.PeriodIncr > 0 THEN n.Parameter := BYTE(( can.PeriodIncr) SHR 2)
                            ELSE n.Parameter := BYTE((-can.PeriodIncr) SHR 2);
    END;

    IF INTEGER(can.PeriodDest - can.Period) >= 0 THEN
      can.PeriodIncr :=  INTEGER(WORD(n.Parameter) SHL 2)
    ELSE
      can.PeriodIncr := -INTEGER(WORD(n.Parameter) SHL 2);

    can.Note.Period := can.Period;
  END;

PROCEDURE TickNPortamento; ASSEMBLER; 
  ASM

        MOV     AX,TCanal([SI]).PeriodDest
        AND     AX,AX
        JZ      @@Fin
        MOV     AX,TCanal([SI]).PeriodIncr
        AND     AX,AX
        JZ      @@Fin
        MOV     BX,TCanal([SI]).Note.Period
        ADD     BX,AX
        TEST    AH,80h
        JNZ      @@neg
         CMP    BX,TCanal([SI]).PeriodDest
         JA     @@pneg
        JMP     @@cnt
@@neg:   TEST   BH,80h
         JNZ    @@pneg
         CMP    BX,TCanal([SI]).PeriodDest
         JAE    @@cnt
@@pneg:  MOV    BX,TCanal([SI]).PeriodDest
@@cnt:  MOV     TCanal([SI]).Note.Period,BX
        MOV     TCanal([SI]).Period,BX
@@Fin:

  END;


{ 4 xy }

PROCEDURE StartVibrato(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  VAR
    f : WORD;
  BEGIN
    f := n.Parameter AND $F;
    IF f <> 0 THEN
      CASE can.VibWave OF
        0: can.VibWidth := f;
        1: can.VibWidth := f;
        2: can.VibWidth := (f*255) SHR 7;
      END;

    f := n.Parameter SHR  4;
    IF f <> 0 THEN can.VibDepth := f SHL 2;

    IF (n.Period <> 0) AND can.VibReset THEN
      can.VibPos := 0;
  END;

PROCEDURE TickVibrato;     ASSEMBLER; 
  CONST
    VibTabla : ARRAY[0..31] OF BYTE = (   { Sinus table for the vibrato. }
        0, 24, 49, 74, 97,120,141,161,
      180,197,212,224,235,244,250,253,
      255,253,250,244,235,224,212,197,
      180,161,141,120, 97, 74, 49, 24
    );
  ASM

        MOV     AH,TCanal([SI]).VibWave
        MOV     DH,TCanal([SI]).VibWidth
        MOV     DL,TCanal([SI]).VibPos
        MOV     AL,DL
        AND     AH,AH
        JNZ     @@nosn
         SHR    AL,2
         AND    AL,1Fh
         MOV    BX,OFFSET VibTabla
         XLAT
         JMP    @@set
@@nosn: DEC     AH
        JNZ     @@notr
         SHL    AL,1
         JNC    @@set
          NOT   AL
@@set:   MUL    DH
         SHL    AX,1
         MOV    AL,AH
         XOR    AH,AH
        JMP     @@calc
@@notr:  MOV    AL,DH
         XOR    AH,AH
@@calc: MOV     BX,TCanal([SI]).Note.Period
        SHL     AX,2
        TEST    DL,80h
        JZ      @@mas
         NEG    AX
@@mas:  ADD     BX,AX
        MOV     TCanal([SI]).Period,BX
        ADD     DL,TCanal([SI]).VibDepth
        MOV     TCanal([SI]).VibPos,DL

  END;


{ 5 xy }

PROCEDURE TickVolSlide; FORWARD;

PROCEDURE TickT_VSlide; ASSEMBLER;
  ASM

        CALL    TickNPortamento
        JMP     TickVolSlide

  END;


{ 6 xy }

PROCEDURE TickVib_VSlide; ASSEMBLER; 
  ASM

        CALL    TickVibrato
        JMP     TickVolSlide

  END;


{ 7 xy }

PROCEDURE TickTremolo;     ASSEMBLER; 
  ASM
  END;


{ 8 xx }

PROCEDURE TickNPI1;        ASSEMBLER; 
  ASM
  END;


{ 9 xx }

PROCEDURE StartSampleOffs(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter <> 0 THEN
      BEGIN
        can.SOffs := TRUE;
        can.SOffsVal := WORD(n.Parameter) * 256;
      END;
  END;

PROCEDURE TickSampleOffs;  ASSEMBLER;
  ASM
  END;


{ A xy }

PROCEDURE StartVolSlide(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter <> 0 THEN
      BEGIN
        can.VSldIsFine := FALSE;
        IF n.Parameter > $F THEN can.VolumeIncr := n.Parameter SHR 4
                            ELSE can.VolumeIncr := -SHORTINT(n.Parameter AND $F);
      END
    ELSE
      BEGIN
        IF can.VSldIsFine THEN
          BEGIN
            can.VSldIsFine := FALSE;
            ASM
                MOV     SI,WORD PTR can
                CALL    TickVolSlide
            END;
            can.VSldIsFine := TRUE;
          END;
      END;

  END;

PROCEDURE TickVolSlide; ASSEMBLER;
  ASM

        MOV     AL,TCanal([SI]).VSldIsFine
        AND     AL,AL
        JNZ     @@Sale

        MOV     AL,TCanal([SI]).Volume
        MOV     AH,TCanal([SI]).VolumeIncr
        ADD     AL,AH
        CMP     AL,64
        JBE     @@Fin
         XOR    AL,AL
         TEST   AH,80h
         JNZ    @@Fin
          MOV   AL,64
@@Fin:  MOV     TCanal([SI]).Volume,AL
@@Sale:
  END;



{ B xx }

PROCEDURE StartJumpPattern(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    NextSeq := n.Parameter;
    IF NextSeq > MySongLen THEN
      NextNote := $FFFF
    ELSE
      NextNote := 1;
  END;


{ C xx }

PROCEDURE StartSetVolume(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter > 64 THEN n.Parameter := 64;
    can.Volume := n.Parameter;
  END;


{ D xx }

PROCEDURE StartEndPattern(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF NextNote <> 1 THEN INC(NextSeq);
    IF NextSeq > MySongLen THEN
      NextNote := $FFFF
    ELSE BEGIN
      NextNote := (n.Parameter AND $0F) +
                  (n.Parameter SHR   4)*10 + 1;
    END;
    IF NextNote <> $FFFF THEN NextNote := 1;
  END;


{ F xx }

PROCEDURE StartSetTempo(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter  > $30 THEN
      BPMIncrement := n.Parameter
    ELSE
      IF n.Parameter <>  0  THEN Tempo := n.Parameter;
  END;


{ E 0x }

PROCEDURE StartSetFilter(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF PermitFilterChange THEN
      FilterIsOn := n.Parameter <> 0;
  END;

PROCEDURE TickSetFilter;   ASSEMBLER; 
  ASM
  END;


{ E 1x , E 2x }

PROCEDURE StartFinePortaUp(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter <> 0 THEN
      BEGIN
        can.TPortaIncr  := WORD(n.Parameter) SHL 2;
        can.TPortIsFine := TRUE;
      END
    ELSE IF NOT can.TPortIsFine THEN
      BEGIN
        can.Note.Command := mcTPortUp;
      END;

    IF can.TPortIsFine THEN
      ASM
        MOV       SI,WORD PTR [can]
        CALL      TickTPortUp
      END;
  END;

PROCEDURE StartFinePortaDown(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter <> 0 THEN
      BEGIN
        can.TPortaIncr  := WORD(n.Parameter) SHL 2;
        can.TPortIsFine := TRUE;
      END
    ELSE IF NOT can.TPortIsFine THEN
      BEGIN
        can.Note.Command := mcTPortDown;
      END;

    IF can.TPortIsFine THEN
      ASM
        MOV       SI,WORD PTR [can]
        CALL      TickTPortDown
      END;
  END;

PROCEDURE TickFPortUpDown; ASSEMBLER;
  ASM
  END;


{ E 3x }

PROCEDURE TickGlissCtrl;   ASSEMBLER; 
  ASM
  END;


{ E 4x }

PROCEDURE TickVibCtrl;     ASSEMBLER; 
  ASM
  END;


{ E 5x }

PROCEDURE TickFineTune;    ASSEMBLER; 
  ASM
  END;


{ E 6x }

PROCEDURE TickJumpLoop;    ASSEMBLER; 
  ASM
  END;


{ E 7x }

PROCEDURE TickTremCtrl;    ASSEMBLER; 
  ASM
  END;


{ E 8x }

PROCEDURE TickNPI2;        ASSEMBLER; 
  ASM
  END;


{ E 9x }

PROCEDURE StartRetrigNote(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter <> 0 THEN
      can.retrigval := n.Parameter;
  END;

PROCEDURE TickRetrigNote;  ASSEMBLER; 
  ASM
        INC     TCanal([SI]).retrigct
        MOV     AL,TCanal([SI]).retrigct
        CMP     AL,TCanal([SI]).retrigval
        JC      @@ret
         MOV    TCanal([SI]).retrigct,0
         MOV    TCanal([SI]).doretrig,1
@@ret:
  END;


{ E Ax y E Bx }

PROCEDURE StartVolFineUp(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter <> 0 THEN
      BEGIN
        can.VSldIsFine := TRUE;
        can.VolumeIncr := n.Parameter AND $F;
      END;

    IF can.VSldIsFine THEN
      BEGIN
        can.VSldIsFine := FALSE;
          ASM
                MOV     SI,WORD PTR can
                CALL    TickVolSlide
          END;
        can.VSldIsFine := TRUE;
      END;
  END;

PROCEDURE StartVolFineDown(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  BEGIN
    IF n.Parameter <> 0 THEN
      BEGIN
        can.VSldIsFine := TRUE;
        can.VolumeIncr := -SHORTINT(n.Parameter AND $F);
      END;

    IF can.VSldIsFine THEN
      BEGIN
        can.VSldIsFine := FALSE;
          ASM
                MOV     SI,WORD PTR can
                CALL    TickVolSlide
          END;
        can.VSldIsFine := TRUE;
      END;
  END;

PROCEDURE TickVolFineUpDn; ASSEMBLER; 
  ASM
                JMP     TickVolSlide
  END;


{ E Cx }

PROCEDURE TickNoteCut;     ASSEMBLER; 
  ASM
  END;


{ E Dx }

PROCEDURE TickNoteDelay;   ASSEMBLER; 
  ASM
  END;


{ E Ex }

PROCEDURE TickPattDelay;   ASSEMBLER; 
  ASM
  END;


{ E Fx }

PROCEDURE TickFunkIt;      ASSEMBLER; 
  ASM
  END;


{ 0 00 }

PROCEDURE TickNone;        ASSEMBLER; 
  ASM
  END;


PROCEDURE StartOktArp(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  CONST
    ArpTable : ARRAY[0..15] OF WORD = ( $4000,$43CE,$47D6,$4C1B,
                                        $50A2,$556D,$5A82,$5FE4,
                                        $6597,$6BA2,$7209,$78D0,
                                        $8000,$879B,$8FAD,$9837 );
  VAR
    f, g: LONGINT;
  BEGIN
    can.arpct := 0;

    f := n.Period;
    IF f = 0 THEN f := can.Note.Period;

    g := f SHL 14;

    can.arp0 := f;
    can.arp2 := g DIV ArpTable[can.Note.Parameter AND $F];

    f := f SHL 1;
    can.arp1 := g DIV ArpTable[(can.Note.Parameter SHR  4) XOR $F];
  END;



PROCEDURE TickArpeggio2;   ASSEMBLER;
  ASM

        INC     TCanal([SI]).arpct
        MOV     AL,TCanal([SI]).arpct
        DEC     AL
        JNZ     @@2
         MOV    AX,TCanal([SI]).arp1
         MOV    TCanal([SI]).Period,AX
        JMP    @@Fin
@@2:    DEC     AL
        JNZ     @@3
         MOV    AX,TCanal([SI]).arp2
         MOV    TCanal([SI]).Period,AX
        JMP    @@Fin
@@3:    DEC     AL
        JNZ     @@4
         MOV    AX,TCanal([SI]).arp1
         MOV    TCanal([SI]).Period,AX
        JMP    @@Fin
@@4:     MOV    AX,TCanal([SI]).arp0
         MOV    TCanal([SI]).Period,AX
         MOV    TCanal([SI]).arpct,0
@@Fin:
  END;



PROCEDURE StartS3mRetrigNote(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  CONST
    RetMult : ARRAY[0..15] OF BYTE     = ( 0,  0,  0,  0,  0,   0, $0C, $08,
                                           0,  0,  0,  0,  0,   0, $18, $20 );
    RetAdd  : ARRAY[0..15] OF SHORTINT = ( 0, -1, -2, -4, -8, -16,   0,   0,
                                           0,  1,  2,  4,  8,  16,   0,   0 );
  BEGIN
    IF n.Parameter <> 0 THEN
      BEGIN
        can.s3mretadd := RetMult[n.Parameter SHR 4] = 0;
        IF can.s3mretadd THEN
          can.s3mretval := RetAdd[n.Parameter SHR 4]
        ELSE
          can.s3mretval := RetMult[n.Parameter SHR 4];

        n.Parameter := n.Parameter AND $F;

        StartRetrigNote(Song, can, n);
      END;
  END;

PROCEDURE TickS3mRetrigNote;  ASSEMBLER;
  ASM
        CALL    TickRetrigNote

        CMP     TCanal([SI]).doretrig,0
        JZ      @@ret
        CMP     TCanal([SI]).s3mretadd,0
        JNZ     @@add
         MOV    AL,TCanal([SI]).s3mretval
         MOV    AH,TCanal([SI]).volume
         MUL    AH
         CMP    AX,16
         JNC    @@c1
          MOV   AX,16
    @@c1:SHR    AX,4
         CMP    AX,63
         JC     @@c2
          MOV   AL,63
    @@c2:MOV    TCanal([SI]).volume,AL
        JMP     @@ret

    @@add:
         MOV    AL,TCanal([SI]).s3mretval
         MOV    AH,TCanal([SI]).volume
         ADD    AH,AL
         JNC    @@c3
          MOV   AH,0
    @@c3:CMP    AH,63
         JC     @@c4
          MOV   AH,63
    @@c4:MOV    TCanal([SI]).volume,AH

@@ret:
  END;







CONST
  TickCommOfs : ARRAY[mcNone..mcLast] OF WORD = (
    OFS(TickNone),       { 0 00 }

    OFS(TickArpeggio),   { 0 xx }
    OFS(TickTPortUp),    { 1 xx }
    OFS(TickTPortDown),  { 2 xx }
    OFS(TickNPortamento),{ 3 xy }
    OFS(TickVibrato),    { 4 xy }
    OFS(TickT_VSlide),   { 5 xy }
    OFS(TickVib_VSlide), { 6 xy }
    OFS(TickTremolo),    { 7 xy }
    OFS(TickNPI1),       { 8 xx }
    OFS(TickSampleOffs), { 9 xx }
    OFS(TickVolSlide),   { A xy }
    OFS(TickNone),       { B xx }
    OFS(TickNone),       { C xx }
    OFS(TickNone),       { D xx }
    OFS(TickNone),       { E xy }
    OFS(TickNone),       { F xx }

    OFS(TickSetFilter),  { E 0x }
    OFS(TickFPortUpDown),{ E 1x }
    OFS(TickFPortUpDown),{ E 2x }
    OFS(TickGlissCtrl),  { E 3x }
    OFS(TickVibCtrl),    { E 4x }
    OFS(TickFineTune),   { E 5x }
    OFS(TickJumpLoop),   { E 6x }
    OFS(TickTremCtrl),   { E 7x }
    OFS(TickNPI2),       { E 8x }
    OFS(TickRetrigNote), { E 9x }
    OFS(TickVolFineUpDn),{ E Ax }
    OFS(TickVolFineUpDn),{ E Bx }
    OFS(TickNoteCut),    { E Cx }
    OFS(TickNoteDelay),  { E Dx }
    OFS(TickPattDelay),  { E Ex }
    OFS(TickFunkIt),     { E Fx }

    OFS(TickArpeggio),   { Okt  }
    OFS(TickArpeggio2),  { Okt  }

    OFS(TickS3mRetrigNote), { S3m  }

    OFS(TickNone)        { 0 00 }

  );

PROCEDURE DoTickCommand; ASSEMBLER;
  ASM
                CMP     BX,mcLast*2
                JNC     @@1
                MOV     TCanal([SI]).doretrig,0
                ADD     BX,OFFSET TickCommOfs
                CALL    WORD PTR [BX]
@@1:
  END;




PROCEDURE CommandStart(VAR Song: TSong; VAR can: TCanal; VAR n: TFullNote);
  CONST
    f   : INTEGER      = 0;
    g   : INTEGER      = 0;
  BEGIN

    IF (can.Note.Command    = mcArpeggio)  OR
       (((can.Note.Command  = mcVibrato) OR
         (can.Note.Command  = mcVib_VSlide)) AND
        ((       n.Command <> mcVibrato) AND
         (       n.Command <> mcVib_VSlide))) THEN can.Period := can.Note.Period;

    IF ((can.Note.Command <> mcS3mRetrigNote) AND
        (can.Note.Command <> mcRetrigNote))   AND
       ((       n.Command  = mcS3mRetrigNote) OR
        (       n.Command  = mcRetrigNote))   THEN
      can.retrigct := 0;

    IF (can.Note.Command =  mcNPortamento) AND
       (       n.Command <> mcNPortamento) THEN
      BEGIN
        can.Note.Period := can.PeriodDest;
        can.Period      := can.PeriodDest;
      END;

    IF (n.Period <> 0) THEN
      can.Note.Period := n.Period;

    can.SOffs := FALSE;

    can.Note.Command   := n.Command;
    can.Note.Parameter := n.Parameter;

    CASE n.Command OF
      mcArpeggio:      StartArpeggio     (Song, can, n);
      mcTPortUp:       StartTPortUp      (Song, can, n);
      mcTPortDown:     StartTPortDown    (Song, can, n);
      mcNPortamento:   StartNPortamento  (Song, can, n);
      mcVibrato:       StartVibrato      (Song, can, n);
      mcJumpPattern:   StartJumpPattern  (Song, can, n);
      mcT_VSlide,
      mcVib_VSlide,
      mcVolSlide:      StartVolSlide     (Song, can, n);
      mcSampleOffs:    StartSampleOffs   (Song, can, n);
      mcSetVolume:     StartSetVolume    (Song, can, n);
      mcEndPattern:    StartEndPattern   (Song, can, n);
      mcSetTempo:      StartSetTempo     (Song, can, n);
      mcSetFilter:     StartSetFilter    (Song, can, n);
      mcRetrigNote:    StartRetrigNote   (Song, can, n);
      mcVolFineUp:     StartVolFineUp    (Song, can, n);
      mcVolFineDown:   StartVolFineDown  (Song, can, n);
      mcFinePortaUp:   StartFinePortaUp  (Song, can, n);
      mcFinePortaDn:   StartFinePortaDown(Song, can, n);
      mcOktArp:        StartOktArp       (Song, can, n);
      mcOktArp2:       StartOktArp       (Song, can, n);
      mcS3mRetrigNote: StartS3mRetrigNote(Song, can, n);
    END;

    IF (n.Period <> 0) AND (n.Command <> mcNPortamento) THEN
      can.Period := n.Period;

  END;




END.
