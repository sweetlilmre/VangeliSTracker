UNIT SongElements;

INTERFACE

USES Objects, SoundDevices;




{----------------------------------------------------------------------------}
{ Definitions for handling the format of individual notes.                   }
{ Notes are composed of four fields:                                         }
{                                                                            }
{   Period:     A number in the range 0..2047 which states the period of     }
{               the note in units of 1/3584000 per sample. (this is a        }
{               somewhat empyric number. If anyone knows the exact Amiga     }
{               number, please, tell us). A zero means to keep using the     }
{               same period used before.                                     }
{   Instrument: A number in range 0..63 meaning the number of the instrument }
{               which will be used for the note. A zero means use the same.  }
{   Command:    A number (no real range) of the way the note should be       }
{               played (i.e. Vibrato) a change in the playing sequence (i.e. }
{               pattern break) or a change in the general parameters of the  }
{               module player (i.e. set tempo). All the possible values are  }
{               defined in the TModCommand enumerated type below.            }
{   Parameter:  A parameter for the command. Its meaning differs from one    }
{               command to another. Sometimes each nibble is considered as a }
{               different parameter.                                         }
{____________________________________________________________________________}

TYPE
  TModCommand = (
                 mcNone,       { 0 00 } { Just play the note, without any special option. }

                 mcArpeggio,   { 0 xy } { Rotate through three notes rapidly. }
                 mcTPortUp,    { 1 xx } { Tone Portamento Up:   Gradual change of tone towards high frequencies. }
                 mcTPortDown,  { 2 xx } { Tone Portamento Down: Gradual change of tone towards low  frequencies. }
                 mcNPortamento,{ 3 xy } { Note Portamento:      Gradual change of tone towards a given note.     }
                 mcVibrato,    { 4 xy } { Vibrato: Frequency changes around the note. }
                 mcT_VSlide,   { 5 xy } { Tone Port. Up + Volume slide: Parameter means vol. slide. }
                 mcVib_VSlide, { 6 xy } { Vibrato       + Volume slide: Parameter means vol. slide. }
                 mcTremolo,    { 7 xy } { Tremolo: I don't know for sure. Fast volume variations, I think. }
                 mcNPI1,       { 8 xx } { Do Nothing (as far as I know). }
                 mcSampleOffs, { 9 xx } { Start the sample from the middle. }
                 mcVolSlide,   { A xy } { Volume slide: Gradual change in volume. }
                 mcJumpPattern,{ B xx } { End pattern and continue from a different pattern sequence position. }
                 mcSetVolume,  { C xx } { Set the volume of the sound. }
                 mcEndPattern, { D xx } { Continue at the start of the next pattern. }
                 mcExtended,   { E xy } { Extended set of commands (ProTracker). }
                 mcSetTempo,   { F xx } { Set the tempo of the music, in 1/50ths of a second. }

                 mcSetFilter,  { E 0x } { Set the output filter to the on or off value. }
                 mcFinePortaUp,{ E 1x } { Like TPortUp,   but slower. }
                 mcFinePortaDn,{ E 2x } { Like TPortDown, but slower. }
                 mcGlissCtrl,  { E 3x } { ¨?¨?¨? }
                 mcVibCtrl,    { E 4x } { Set the vibrato waveform. }
                 mcFineTune,   { E 5x } { Fine tune the frequency of the sound. }
                 mcJumpLoop,   { E 6x } { Make a loop inside a pattern. }
                 mcTremCtrl,   { E 7x } { Set the tremolo waveform (I think). }
                 mcNPI2,       { E 8x } { Do Nothing (as far as I know). }
                 mcRetrigNote, { E 9x } { ¨?¨?¨? }
                 mcVolFineUp,  { E Ax } { Like VolSlide, but slower and towards high frequencies. }
                 mcVolFineDown,{ E Bx } { Like VolSlide, but slower and towards low  frequencies. }
                 mcNoteCut,    { E Cx } { ¨?¨?¨? }
                 mcNoteDelay,  { E Dx } { Wait a little before starting note. }
                 mcPattDelay,  { E Ex } { ¨?¨?¨? }
                 mcFunkIt,     { E Fx } { No idea, but sounds funny. }

                 mcOktArp,     {      } { Oktalizer arpeggio  }
                 mcOktArp2,    {      } { Oktalizer arpeggio2 }

                 mcS3mRetrigNote,

                 mcLast
  );

TYPE
  PNoCommandNote = ^TNoCommandNote;
  TNoCommandNote = RECORD
    Instrument : BYTE;
    Period     : WORD;
    Volume     : BYTE;
  END;

  PCommandNote = ^TCommandNote;
  TCommandNote = RECORD
    Command    : TModCommand;
    Parameter  : BYTE;
  END;

  PFullNote = ^TFullNote;
  TFullNote = RECORD
    CASE BYTE OF
      0 : ( Instrument : BYTE;
            Period     : WORD;
            Volume     : BYTE;
            Command    : TModCommand;
            Parameter  : BYTE        );
      1 : ( Note : TNoCommandNote;
            Comm : TCommandNote      );
  END;




{----------------------------------------------------------------------------}
{ Definitions for handling the instruments used in the module.               }
{ Instruments are fragments of sampled sound (long arrays of bytes which     }
{ describe the wave of the sound of the instrument). The samples used in     }
{ music modules have a default volume and also, they can have a loop (for    }
{ sustained instruments) and a fine tuning constant (not yet implemented).   }
{____________________________________________________________________________}

CONST
  MaxSample      = 65520;
  MaxInstruments = 255;

  LowQuality : BOOLEAN = TRUE;

  { Properties }

  ipMonoFreq = $0001;  { Set if the instrument is played always at the same freq (not implemented). }
  ipLong     = $0002;  { Set if the instrument's sample is longer than 65520 bytes.                 }

TYPE
  PSample = ^TSample;
  TSample = ARRAY[0..MaxSample-1] OF SHORTINT;

  TIProperties = WORD; { Properties of the instrument. }

  PInstrumentRec = ^TInstrumentRec;
  TInstrumentRec =
    RECORD
      Len,                  { Length of the instrument's sampled image.                           }
      Reps,                 { Starting offset of the repeated portion.                            }
      Repl  : LONGINT;      { Size of the repeated portion.                                       }
      Vol   : BYTE;         { Default volume of the instrument (0..64)                            }
      Ftune : BYTE;         { Fine tuning value for the instrument (not yet implemented).         }
      NAdj  : WORD;         { Numerator of note adjutment.                                        }
      DAdj  : WORD;         { Denominator of note adjutment.                                      }
      Data  : ^TSample;     { Pointer to the first  65520 bytes of the sample.                    }
      Xtra  : ^TSample;     { Pointer to the second 65520 bytes of the sample (if there is such). }
      Prop  : TIProperties; { Bit mapped properties value.                                        }
    END;

  PInstrument = ^TInstrument;
  TInstrument =
    OBJECT(TObject)
      Name  : PString;
      Instr : PInstrumentRec;

      CONSTRUCTOR Init;
      DESTRUCTOR  Done; VIRTUAL;

      PROCEDURE FreeContents;
      PROCEDURE Desample;
      PROCEDURE Resample;

      PROCEDURE Change(Instrument : PInstrumentRec);
      FUNCTION  GetName                             : STRING;
      PROCEDURE SetName(S: STRING);
    END;




{----------------------------------------------------------------------------}
{ Definitions for handling the tracks of which patterns are built.           }
{ Tracks are lists of notes and command values of which the empty leading    }
{ and trailing blanks have been removed (obviated).                          }
{____________________________________________________________________________}

TYPE
  PNoteTrack = ^TNoteTrack;
  TNoteTrack =
    RECORD
      NoteOffset : BYTE;
      NumNotes   : BYTE;
      Notes      : ARRAY[0..255] OF TNoCommandNote;
    END;

  PCommTrack = ^TCommTrack;
  TCommTrack =
    RECORD
      NoteOffset : BYTE;
      NumNotes   : BYTE;
      Notes      : ARRAY[0..255] OF TCommandNote;
    END;

  PFullTrack = ^TFullTrack;
  TFullTrack = ARRAY[0..255] OF TFullNote;
{
  PTrackCache = ^TTrackCache;
  TTrackCache =
    RECORD
      InUse    : BOOLEAN;
      Modified : BOOLEAN;
      LastUse  : WORD;
      Track    : PFullTrack;
    END;

VAR
  TrackCaches = ARRAY[1..MaxChannels] OF TTrackCache;
}
TYPE
  PTrack = ^TTrack;
  TTrack =
    OBJECT(TObject)
      Name : PString;
      Note : PNoteTrack;
      Comm : PCommTrack;

      CONSTRUCTOR Init;
      DESTRUCTOR  Done; VIRTUAL;

      PROCEDURE FreeContents;

      PROCEDURE ChangeNote(At: WORD; VAR FullNote: TFullNote);
      PROCEDURE GetNote   (At: WORD; VAR FullNote: TFullNote);

      PROCEDURE GetFullTrack(VAR Track: TFullTrack);
      PROCEDURE SetFullTrack(VAR Track: TFullTrack);

      FUNCTION GetName : STRING;
    END;




{----------------------------------------------------------------------------}
{ Definitions for handling the format of the patterns.                       }
{ Patterns are arrays of pointers to tracks (up to 12 tracks).               }
{ A music module can have up to 255 individual patterns, arranged in a       }
{ sequence of up to 255.                                                     }
{ Empty patterns are not counted.                                            }
{____________________________________________________________________________}

CONST
  MaxSequence     = 256;
  MaxPatterns     = 256;
  MaxPatternLines = 256;
  MaxChannels     = SoundDevices.MaxChannels;

TYPE
  PPatternRec = ^TPatternRec;
  TPatternRec =
    RECORD
      NNotes   : BYTE;
      NChans   : BYTE;
      Tempo    : BYTE;
      BPM      : BYTE;
      Channels : ARRAY[1..MaxChannels] OF WORD;
    END;

  PPattern = ^TPattern;
  TPattern =
    OBJECT(TObject)
      Name : PString;
      Patt : PPatternRec;

      CONSTRUCTOR Init(Chans: WORD);
      DESTRUCTOR  Done; VIRTUAL;

      PROCEDURE FreeContents;

      FUNCTION GetName : STRING;
    END;

  PPatternSequence = ^TPatternSequence;
  TPatternSequence = ARRAY[1..MaxSequence] OF BYTE;




{----------------------------------------------------------------------------}
{ General definitions for the song.                                          }
{____________________________________________________________________________}

TYPE
  PSongComment = ^TSongComment;
  TSongComment = ARRAY[1..16] OF STRING[60];




IMPLEMENTATION

USES Heaps, GUS, Debugging, HexConversions;



{----------------------------------------------------------------------------}
{ TInstrument object implementation.                                         }
{____________________________________________________________________________}

CONST
  GUSAddr : LONGINT = 0;

CONSTRUCTOR TInstrument.Init;
  BEGIN
    TObject.Init;
  END;


DESTRUCTOR TInstrument.Done;
  BEGIN
    GUSAddr := 0;
    SetName('');
    FreeContents;
    TObject.Done;
  END;


PROCEDURE TInstrument.FreeContents;
  BEGIN
    IF Instr = NIL THEN EXIT;

    IF NOT UsingGUS THEN
      BEGIN
        IF Instr^.Len > 65520 THEN
          BEGIN
            IF Instr^.Xtra <> NIL THEN
              FullHeap.HFreeMem(POINTER(Instr^.Xtra), Instr^.Len - 65520);
            Instr^.Len := 65520;
          END;
        IF Instr^.Data <> NIL THEN
          FullHeap.HFreeMem(POINTER(Instr^.Data), Instr^.Len);
      END;

    FullHeap.HFreeMem(POINTER(Instr), SizeOf(Instr^));
  END;


PROCEDURE TInstrument.Change(Instrument : PInstrumentRec);
  CONST
    Zero : BYTE = 0;
  VAR
    l : LONGINT;
  BEGIN
    FreeContents;
    IF Instrument <> NIL THEN
      BEGIN
        FullHeap.HGetMem(POINTER(Instr), SizeOf(Instr^));
        IF Instr <> NIL THEN
          BEGIN
            Move(Instrument^, Instr^, SizeOf(Instr^));
            IF Instr^.Vol > 63 THEN
              Instr^.Vol := 63;
            IF Instr^.NAdj = 0 THEN
              BEGIN
                Instr^.NAdj := $2000;
                Instr^.DAdj := $2000;
              END;
            IF Instr^.Repl <= 4 THEN
              Instr^.Repl := 0;
            IF LowQuality THEN
              BEGIN
                Desample;
                Resample;
              END;

            IF UsingGUS AND (Instr^.Data <> NIL) THEN
              BEGIN
                l := Instr^.Len;
                IF l > 65520 THEN
                  l := 65520;
                DumpToUltrasound(Instr^.Data^, l, GUSAddr, TRUE);
                FullHeap.HFreeMem(POINTER(Instr^.Data), l);
                Instr^.Data := POINTER(GUSAddr);
                INC(GUSAddr, l);
                IF l <> Instr^.Len THEN
                  BEGIN
                    l := Instr^.Len - l;
                    DumpToUltrasound(Instr^.Xtra^, l, GUSAddr, TRUE);
                    FullHeap.HFreeMem(POINTER(Instr^.Xtra), l);
                    INC(GUSAddr, l);
                  END;
{
                IF Instr^.Repl = 0 THEN
                  BEGIN
                    DumpToUltrasound(Zero, 1, GUSAddr, TRUE);
                    INC(GUSAddr);
                    INC(Instr^.Len);
                  END;
}
              END;

            IF Debug THEN
              WriteLn(HexPtr(Instr^.Data));

          END;
      END;
  END;

FUNCTION TInstrument.GetName : STRING;
  BEGIN
    IF Name <> NIL THEN
      GetName := Name^
    ELSE
      GetName := '';
  END;


PROCEDURE TInstrument.Desample;
  VAR
    w        : WORD;
    p        : POINTER;
    SizeFree : WORD;
  BEGIN
    WITH Instr^ DO
      IF (Instr <> NIL) AND (Instr^.Data <> NIL)        AND
         (Len > 128) AND ((Repl >= 2000) OR (Repl = 0)) THEN
        BEGIN
          FOR w := 0 TO Len DIV 2 - 1 DO
            Data^[w] := (INTEGER(Data^[w*2]) +
                         INTEGER(Data^[w*2+1])) DIV 2;

          p := Ptr(SEG(Data^), OFS(Data^) + Len DIV 2 + 7);
          p := Ptr(SEG(p^) + (OFS(p^) SHR 4), OFS(p^) AND $8);

          SizeFree := Len -
                      (WORD((SEG(p^) - SEG(Data^)) SHL 4) +
                       WORD( OFS(p^) - OFS(Data^))        );

          FullHeap.HFreeMem(p, SizeFree);

          Len  := Len  DIV 2;
          Reps := Reps DIV 2;
          Repl := Repl DIV 2;
          NAdj := NADJ  *  2;
        END;
  END;



PROCEDURE TInstrument.Resample;
  VAR
    w        : WORD;
    p        : ^TSample;
    SizeFree : WORD;
  BEGIN
    WITH Instr^ DO
      IF (Instr <> NIL) AND (Instr^.Data <> NIL) AND
         (Len < 128) AND (Repl > 0)              THEN
        BEGIN
          FullHeap.HGetMem(POINTER(p), Reps + Repl*3);
          FOR w := 0 TO Reps+Repl-1 DO
            p^[w] := Data^[w];

          FOR w := Reps TO Reps + Repl - 1 DO
            BEGIN
              p^[w+Repl  ] := Data^[w];
              p^[w+Repl*2] := Data^[w];
              p^[w+Repl*3] := Data^[w];
            END;

          FullHeap.HFreeMem(POINTER(Data), Len);
          Data := POINTER(p);

          Len  := Reps + Repl*4;
          Repl := Repl * 4;
        END;
  END;



PROCEDURE TInstrument.SetName(S: STRING);
  BEGIN
    IF Name <> NIL THEN
      FullHeap.HDisposeStr(Name);

    IF S <> '' THEN
      Name := FullHeap.HNewStr(S);
  END;



{----------------------------------------------------------------------------}
{ TTrack object implementation.                                              }
{____________________________________________________________________________}

CONSTRUCTOR TTrack.Init;
  BEGIN
    TObject.Init;
  END;


DESTRUCTOR TTrack.Done;
  BEGIN
    FullHeap.HDisposeStr(Name);
    FreeContents;
    TObject.Done;
  END;


PROCEDURE TTrack.FreeContents;
  BEGIN
    IF Note <> NIL THEN
      FullHeap.HFreeMem(POINTER(Note), Note^.NumNotes*SizeOf(TNoCommandNote) + 2);
    IF Comm <> NIL THEN
      FullHeap.HFreeMem(POINTER(Comm), Comm^.NumNotes*SizeOf(TCommandNote)   + 2);
  END;


PROCEDURE TTrack.ChangeNote(At: WORD; VAR FullNote: TFullNote);
  VAR
    Track : TFullTrack;
  BEGIN
    GetFullTrack(Track);
    Track[At] := FullNote;
    SetFullTrack(Track);
  END;


PROCEDURE TTrack.GetFullTrack(VAR Track: TFullTrack);
  VAR
    i : WORD;
  BEGIN
    FillChar(Track, SizeOf(Track), 0);

    IF Note <> NIL THEN
      FOR i := 0 TO Note^.NumNotes DO
        Track[i+Note^.NoteOffset].Note := Note^.Notes[i];

    IF Comm <> NIL THEN
      FOR i := 0 TO Note^.NumNotes DO
        Track[i+Note^.NoteOffset].Note := Note^.Notes[i];
  END;


PROCEDURE TTrack.SetFullTrack(VAR Track: TFullTrack);
  VAR
    i     : WORD;
    MNote : TNoteTrack;
    MComm : TCommTrack;
  BEGIN
    FillChar(MNote, SizeOf(MNote), 0);
    FillChar(MComm, SizeOf(MComm), 0);
    FOR i := 0 TO 255 DO
      BEGIN
        IF (Track[i].Instrument = 0) AND
           (Track[i].Period     = 0) AND
           (Track[i].Volume     = 0) THEN
          BEGIN
            IF MNote.NoteOffset = i THEN
              INC(MNote.NoteOffset);
          END
        ELSE
          BEGIN
            MNote.NumNotes := i - MNote.NoteOffset + 1;
            MNote.Notes[i - MNote.NoteOffset] := Track[i].Note;
          END;

        IF Track[i].Command = mcNone THEN
          BEGIN
            IF MComm.NoteOffset = i THEN
              INC(MComm.NoteOffset);
          END
        ELSE
          BEGIN
            MComm.NumNotes := i - MComm.NoteOffset + 1;
            MComm.Notes[i - MComm.NoteOffset] := Track[i].Comm;
          END;
      END;

    FreeContents;

    FullHeap.HGetMem(POINTER(Note), MNote.NumNotes*SizeOf(TNoCommandNote) + 2);
    FullHeap.HGetMem(POINTER(Comm), MComm.NumNotes*SizeOf(TCommandNote)   + 2);

    IF Note <> NIL THEN
      Move(MNote, Note^, MNote.NumNotes*SizeOf(TNoCommandNote) + 2);
    IF Comm <> NIL THEN
      Move(MComm, Comm^, MComm.NumNotes*SizeOf(TCommandNote)   + 2);
  END;


PROCEDURE TTrack.GetNote(At: WORD; VAR FullNote: TFullNote);
  BEGIN
    DEC(At);
    FillChar(FullNote, SizeOf(FullNote), 0);

    IF (Note <> NIL) AND (At >= Note^.NoteOffset) AND
       (At < Note^.NoteOffset + Note^.NumNotes)   THEN
      FullNote.Note := Note^.Notes[At - Note^.NoteOffset];

    IF (Comm <> NIL) AND (At >= Comm^.NoteOffset) AND
       (At < Comm^.NoteOffset + Comm^.NumNotes)   THEN
      FullNote.Comm := Comm^.Notes[At - Comm^.NoteOffset];
  END;


FUNCTION TTrack.GetName : STRING;
  BEGIN
    IF Name <> NIL THEN
      GetName := Name^
    ELSE
      GetName := '';
  END;




{----------------------------------------------------------------------------}
{ TPattern object implementation.                                            }
{____________________________________________________________________________}

CONSTRUCTOR TPattern.Init(Chans: WORD);
  BEGIN
    TObject.Init;

    FullHeap.HGetMem(POINTER(Patt), Chans*2 + 4);

    IF Patt <> NIL THEN
      FillChar(Patt^, Chans*2 + 4, 0);
    Patt^.NChans := Chans;
  END;


DESTRUCTOR TPattern.Done;
  BEGIN
    FullHeap.HDisposeStr(Name);
    FreeContents;
    TObject.Done;
  END;


PROCEDURE TPattern.FreeContents;
  BEGIN
    IF Patt <> NIL THEN
      FullHeap.HFreeMem(POINTER(Patt), Patt^.NChans*2 + 4);
  END;


FUNCTION TPattern.GetName : STRING;
  BEGIN
    IF Name <> NIL THEN
      GetName := Name^
    ELSE
      GetName := '';
  END;




END.
