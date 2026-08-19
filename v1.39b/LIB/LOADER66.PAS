UNIT Loader669;

INTERFACE

USES Objects, SongUnit;




PROCEDURE Load669FileFormat  (VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);




IMPLEMENTATION

USES SongElements, SongUtils, Heaps, AsciiZ;




{----------------------------------------------------------------------------}
{ Internal definitions. Format of the files.                                 }
{____________________________________________________________________________}

TYPE
  T669FileMagic = WORD;

CONST
  Magic669 = $6669;

TYPE

  TSizes = ARRAY[1..128] OF BYTE;

  T669Header =
    RECORD
      Magic       : T669FileMagic;
      Comment     : ARRAY[1..3, 1..36] OF CHAR;
      NInstruments: BYTE;
      NPatterns   : BYTE;
      RepStart    : BYTE;
      Sequence    : TSizes;
      Tempos      : TSizes;
      Lengths     : TSizes;
    END;

  T669Instrument =
    RECORD
      Name      : ARRAY[1..13] OF CHAR;
      Size      : LONGINT;
      RepStart  : LONGINT;
      RepLen    : LONGINT;
    END;

  T669Pattern = ARRAY[1..64, 1..8] OF
    RECORD
      CASE BYTE OF
        0 : ( w1 : WORD;
              b  : BYTE );
        1 : ( b1,
              b2,
              b3 : BYTE );
    END;




PROCEDURE ProcessPatterns(VAR Song: TSong; VAR St: TStream; VAR Sizes: TSizes; Num: WORD; Tempos: TSizes);
  VAR
    Patt      : T669Pattern;
    FullTrack : TFullTrack;
    Pattern   : PPattern;
    Track     : PTrack;
    Note      : TFullNote;
    c         : BYTE;
    i, j      : WORD;
    n, t      : WORD;
    Row       : WORD;
    Size      : WORD;
    NAdj      : WORD;
    l         : LONGINT;
  BEGIN
    t := 1;
    FOR n := 1 TO Num DO
      BEGIN
        Pattern := Song.GetPattern(n);
        IF Pattern = NIL THEN
          BEGIN
            Song.Status := msOutOfMemory;
            EXIT;
          END;

        WITH Pattern^.Patt^ DO
          BEGIN
            NNotes := Sizes[n] + 1;
            NChans := Song.NumChannels;
            Tempo  := Tempos[n];
            BPM    := 0;
          END;

        St.Read(Patt, SizeOf(Patt));

        IF St.Status <> stOk THEN
          BEGIN
            Song.Status := msFileTooShort;
            EXIT;
          END;

        FOR j := 1 TO Song.NumChannels DO
          BEGIN
            FillChar(FullTrack, SizeOf(FullTrack), 0);

            FOR i := 1 TO 64 DO
              WITH FullTrack[i-1], Patt[i][j] DO
                BEGIN
                  IF b1 < $FE THEN
                    BEGIN
                      Period     := PeriodArray[b1 SHR 2];
                      Instrument := ((SWAP(w1) SHR 4) AND 63) + 1;
                    END;

                  IF b1 < $FF THEN
                    Volume   := ((b2 AND 15) SHL 2) + ((b2 AND 15) SHR 2) + 1;

                  Parameter  := b3 AND 15;
                  Command    := mcNone;

                  IF Parameter <> 0 THEN
                    CASE b3 SHR 4 OF
                      0 : Command := mcTPortUp;
                      1 : Command := mcTPortDown;
                      2 : Command := mcNPortamento;
                      3 : INC(Period);
                      4 : BEGIN
                            Command   := mcVibrato;
                            Parameter := (Parameter SHL 4) + 1
                          END;
                      5 : Command := mcSetTempo;
                    END;
                END;

            Track := Song.GetTrack(t);
            IF Track = NIL THEN
              BEGIN
                Song.Status := msOutOfMemory;
                EXIT;
              END;

            Track^.SetFullTrack(FullTrack);

            Pattern^.Patt^.Channels[j] := t;

            INC(t);
          END;

      END;
  END;


PROCEDURE ProcessInstruments(VAR Song: TSong; VAR St: TStream; Num: WORD);
  VAR
    Instrument : TInstrumentRec;
    Instr      : PInstrument;
    Instr669   : T669Instrument;
    i, w       : WORD;
    Signo      : LONGINT;
    NoSigno    : LONGINT;
  BEGIN
    FOR i := 1 TO Num DO
      WITH Instrument DO
        BEGIN
          FillChar(Instrument, SizeOf(Instrument), 0);

          Instr := Song.GetInstrument(i);
          IF Instr = NIL THEN
            BEGIN
              Song.Status := msOutOfMemory;
              EXIT;
            END;

          St.Read(Instr669, SizeOf(Instr669));

          Instr^.SetName(StrASCIIZ(Instr669.Name, 13));

          Len  := Instr669.Size;

          IF Len > 0 THEN
            BEGIN

              IF Instr669.RepLen <= Len THEN
                BEGIN
                  Reps := Instr669.RepStart;
                  Repl := Instr669.RepLen;
                END
              ELSE
                BEGIN
                  Reps := 0;
                  Repl := 0;
                END;

              Vol  := 64;

              IF Repl        > Len THEN Repl := Len;
              IF Reps + Repl > Len THEN Repl := Len - Reps;


              Instr^.Change(@Instrument);
            END
          ELSE
            Instr^.Change(NIL);
        END;
  END;



PROCEDURE ProcessSamples(VAR Song: TSong; VAR St: TStream; Num: WORD);
  VAR
    Instr      : PInstrument;
    Instrument : TInstrumentRec;
    i, w       : WORD;
    l          : LONGINT;
  BEGIN
    FOR i := 1 TO Num DO
      BEGIN
        Instr := Song.GetInstrument(i);

        IF (Instr^.Instr     <> NIL) AND
           (Instr^.Instr^.Len > 0)   THEN
          BEGIN
            Move(Instr^.Instr^, Instrument, SizeOf(Instrument));
            Instr^.FreeContents;

            WITH Instrument DO
              BEGIN

                l := St.GetPos;
                l := St.GetSize - l;
                IF Len > l THEN
                  BEGIN
                    Song.Status := msFileTooShort;
                    Len := l;
                  END;

                l := St.GetPos + Len;

                IF Len > 0 THEN
                  BEGIN
                    IF Len <= MaxSample THEN
                      BEGIN
                        FullHeap.HGetMem(POINTER(Data), Len);
                        IF Data = NIL THEN BEGIN
                          Song.Status := msOutOfMemory;
                          EXIT;
                        END;

                        St.Read(Data^, Len);

                        IF St.Status <> stOk THEN BEGIN
                          Song.Status := msFileDamaged;
                          EXIT;
                        END;

                        FOR w := 0 TO Len - 1 DO
                          INC(Data^[w], 128);
                      END
                    ELSE
                      BEGIN
                        FullHeap.HGetMem(POINTER(Data), MaxSample);
                        FullHeap.HGetMem(POINTER(Xtra), Len-MaxSample);

                        IF (Data = NIL) OR (Xtra = NIL) THEN BEGIN
                          Song.Status := msOutOfMemory;
                          EXIT;
                        END;

                        St.Read(Data^, MaxSample);
                        St.Read(Xtra^, Len-MaxSample);

                        IF St.Status <> 0 THEN BEGIN
                          Song.Status := msFileDamaged;
                          EXIT;
                        END;
                      END;
                  END;
                St.Seek(l);
              END;
            Instr^.Change(@Instrument);
          END;

        IF LowQuality THEN
          Instr^.Desample;

      END;
  END;

PROCEDURE Load669FileFormat(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);
  VAR
    Hdr        : T669Header ABSOLUTE Header;
    InitialPos : LONGINT;
    i          : WORD;
  BEGIN
    Song.FileFormat := mffComposer669;

    InitialPos := St.GetPos;

    St.Seek(InitialPos + SizeOf(T669Header));

    IF Hdr.Magic <> Magic669 THEN
      BEGIN
        Song.Status := msNotLoaded;
        EXIT;
      END;

    Song.Status := msOK;

    Song.Name := FullHeap.HNewStr(Song.FileName);

    Song.InitialTempo := 4;
    Song.InitialBPM   := 80;
    Song.Volume       := 255;
    Song.NumChannels  := 8;

    Song.SequenceLength := 0;
    FOR i := 1 TO 128 DO
      IF Hdr.Sequence[i] < 128 THEN
        Song.SequenceLength := i;

    Song.SequenceRepStart := Hdr.RepStart + 1;
    Move(Hdr.Sequence, Song.PatternSequence^, Song.SequenceLength);

    FOR i := 1 TO Song.SequenceLength DO
      INC(Song.PatternSequence^[i]);

    FOR i := 1 TO MaxChannels DO
      IF Odd(i) THEN
        Song.PanPositions[i] := $B0
      ELSE
        Song.PanPositions[i] := $40;


    { Processing of the instruments }

    ProcessInstruments(Song, St, Hdr.NInstruments);
    IF Song.Status > msOk THEN EXIT;


    { Processing of the patterns (the partiture) }

    ProcessPatterns(Song, St, Hdr.Lengths, Hdr.NPatterns, Hdr.Tempos);
    IF Song.Status > msOk THEN EXIT;


    { Processing of the samples }

    ProcessSamples(Song, St, Hdr.NInstruments);
    IF Song.Status > msFileTooShort THEN EXIT;
  END;




END.
