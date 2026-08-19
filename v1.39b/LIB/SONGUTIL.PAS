UNIT SongUtils;

INTERFACE

USES SongUnit, SongElements;




{----------------------------------------------------------------------------}
{ Definitions for accelerating the use of note periods.                      }
{____________________________________________________________________________}

CONST
  NumberOctaves = 6;
  NumberNotes   = 12;
  NumberPeriods = NumberOctaves * NumberNotes;

TYPE
  TPeriodSet = ARRAY[0..NumberOctaves-1] OF         { Octave }
               ARRAY[0..NumberNotes  -1] OF WORD;   { Note   }

  TPeriodArray = ARRAY[0..NumberPeriods - 1] OF WORD;

CONST
  { The different note values. }

  PeriodSet : TPeriodSet = (
    {  C     C#    D     D#    E     F     F#    G     G#    A     A#    B  }
    ($06B0,$0650,$05F5,$05A0,$054F,$0503,$04BB,$0477,$0436,$03FA,$03C1,$038B),
    ($0358,$0328,$02FB,$02D0,$02A7,$0281,$025D,$023B,$021B,$01FD,$01E0,$01C5),
    ($01AC,$0194,$017D,$0168,$0154,$0141,$012F,$011E,$010E,$00FE,$00F0,$00E3),
    ($00D6,$00CA,$00BF,$00B4,$00AA,$00A0,$0097,$008F,$0087,$007F,$0078,$0071),
    ($006B,$0065,$005F,$005A,$0055,$0050,$004C,$0047,$0043,$0040,$003C,$0039),
    ($0035,$0032,$0030,$002D,$002A,$0028,$0026,$0024,$0022,$0020,$001E,$001C)
{
    ($001B,$0019,$0018,$0016,$0015,$0014,$0013,$0012,$0011,$0010,$000F,$000E)
}
  );

  { The different inter-note values. }

  PeriodDiff : TPeriodSet = (
    ($0680,$0622,$05CA,$0577,$0529,$04DF,$0499,$0456,$0418,$03DD,$03A6,$0371),
    ($0340,$0311,$02E5,$02BB,$0294,$026F,$024C,$022B,$020C,$01EE,$01D2,$01B8),
    ($01A0,$0188,$0172,$015E,$014A,$0138,$0126,$0116,$0106,$00F7,$00E9,$00DC),
    ($00D0,$00C4,$00B9,$00AF,$00A5,$009B,$0093,$008B,$0083,$007B,$0074,$006E),
    ($0068,$0062,$005C,$0057,$0052,$004E,$0049,$0045,$0041,$003E,$003A,$0037),
    ($0033,$0031,$002E,$002B,$0029,$0027,$0025,$0023,$0021,$001F,$001D,$001B)
{
    ($001A,$0018,$0017,$0015,$0014,$0013,$0012,$0011,$0010,$000F,$000E,$000E)
}
  );

VAR
  PeriodArray : TPeriodArray ABSOLUTE PeriodSet;

TYPE
  TNoteString    = STRING[3];

  TNoteSet       = ARRAY[0..2047] OF WORD;
  TNoteStringSet = ARRAY[0..NumberPeriods] OF TNoteString;

VAR
  NoteIdx : TNoteSet;       { For each period, specifies its closest note, in two ways:      }
                            {   Hi byte: octave in the hi nibble and note in the low nibble. }
                            {  Low byte: sequential note for indexing.                       }

  NoteStr : TNoteStringSet; { The strings for each note (e.g. 'A#2'). }




FUNCTION  SwapLong (l: LONGINT)                  : LONGINT;
PROCEDURE NoteFreq (f: WORD; VAR s: TNoteString);

PROCEDURE InitModVideoTables;
PROCEDURE InitModUnit;

FUNCTION  FullNotesEqual (VAR fn1, fn2: TFullNote) : BOOLEAN;



IMPLEMENTATION





FUNCTION SwapLong(l: LONGINT) : LONGINT;
  VAR
    w : ARRAY[0..1] OF WORD ABSOLUTE l;
    r : WORD;
  BEGIN
    r    := SWAP(w[0]);
    w[0] := SWAP(w[1]);
    w[1] := r;
    SwapLong := l;
  END;




PROCEDURE NoteFreq(f: WORD; VAR s: TNoteString);
  BEGIN
    IF f > 2047 THEN
      f := 2047;

    s := NoteStr[NoteIdx[f] AND $FF];
{    STR(f, s);}
  END;




{----------------------------------------------------------------------------}
{ Initialization routines.                                                   }
{____________________________________________________________________________}

PROCEDURE InitModUnit;
  VAR
    l    : LONGINT;
    f,
    o, i : WORD;
  LABEL
    Octava, NextFreq;
  BEGIN
    FOR f := 0 TO 2047 DO BEGIN

      FOR o := 0 TO NumberOctaves-1 DO
        IF f > PeriodDiff[o][11] THEN GOTO Octava;
      i := 0; o := 0;
      GOTO NextFreq;

Octava:
      FOR i := 0 TO NumberNotes-1 DO
        IF f > PeriodDiff[o][i]  THEN GOTO NextFreq;
      i := 0; o := 0;

NextFreq:
      NoteIdx[f] := (o*16+i)*256 + (o*12+i)

    END;
  END;




PROCEDURE InitModVideoTables;
  CONST
    NoteLet : STRING[12] = 'CCDDEFFGGAAB';
    NoteSus : STRING[12] = ' # #  # # # ';
  VAR
    o, i : WORD;
    s    : STRING[3];
  BEGIN
     FOR i := 0 TO NumberPeriods-1 DO BEGIN
       s[0] := CHR(3);
       o    := i DIV 12;
       s[3] := CHR(o + ORD('0'));
       o    := i MOD 12 + 1;
       s[1] := NoteLet[o];
       s[2] := NoteSus[o];

       NoteStr[i] := s;
     END;

     NoteStr[NumberPeriods] := '---';
  END;




FUNCTION  FullNotesEqual (VAR fn1, fn2: TFullNote) : BOOLEAN;
  TYPE
    TFNArray = ARRAY[1..SizeOf(TFullNote)] OF BYTE;
  VAR
    fna1 : TFNArray ABSOLUTE fn1;
    fna2 : TFNArray ABSOLUTE fn2;
    i    : WORD;
  BEGIN
    FullNotesEqual := FALSE;
    FOR i := 1 TO SizeOf(TFullNote) DO
      IF fna1[i] <> fna2[i] THEN EXIT;
    FullNotesEqual := TRUE;
  END;




END.