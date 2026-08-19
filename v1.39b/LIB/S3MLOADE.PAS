UNIT S3mLoader;

INTERFACE

USES Objects, SongUnit;




PROCEDURE LoadS2mFileFormat  (VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);
PROCEDURE LoadS3mFileFormat  (VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);




IMPLEMENTATION

USES SongElements, SongUtils, Heaps, AsciiZ;




{----------------------------------------------------------------------------}
{ Internal definitions. Format of the files.                                 }
{____________________________________________________________________________}

TYPE
  TS3mFileMagic1 = WORD;
  TS3mFileMagic2 = ARRAY[0..3] OF CHAR;
  TS2mFileMagic  = ARRAY[0..3] OF CHAR;

CONST
  S3mMagic1 = $101A;
  S3mMagic2 : TS3mFileMagic2 = ( 'S', 'C', 'R', 'M' );
  S3mInstr2 : TS3mFileMagic2 = ( 'S', 'C', 'R', 'S' );
  S2mMagic  : TS3mFileMagic2 = ( 'S', 'C', 'R', 'M' );

TYPE

  TS3mHeader =
    RECORD
      Name        : ARRAY[1..28] OF CHAR;
      Magic1      : TS3mFileMagic1;
      NPI1        : WORD;
      SeqLen      : WORD;
      NInstruments: WORD;
      NPatts      : WORD;
      Word4       : WORD;
      Long1       : LONGINT;
      Magic2      : TS3mFileMagic2;
      Volume      : BYTE;
      Tempo       : BYTE;
      BPM         : BYTE;
      fill1       : ARRAY[1..13] OF BYTE;
      ChannelMaps : TPanPositions;
    END;

  TS2mHeader =
    RECORD
      Name        : ARRAY[1..20] OF CHAR;
      Scream      : ARRAY[1.. 8] OF CHAR;
      Version     : BYTE;
      fill1       : ARRAY[1.. 3] OF BYTE;
      PattOfs     : WORD;
      InstrOfs    : WORD;
      SeqOfs      : WORD;
      fill2       : ARRAY[1.. 4] OF BYTE;
      Volume      : BYTE;
      Tempo       : BYTE;
      fill3       : ARRAY[1.. 4] OF BYTE;
      NPatts      : WORD;
      NInstruments: WORD;
      SeqLen      : WORD;
      Word4       : WORD;
      Long1       : LONGINT;
      Magic       : TS2mFileMagic;
    END;

  TS3mInstrument =
    RECORD
      Flag      : BYTE;                 { 00 }
      Name      : ARRAY[1..13] OF CHAR; { 01 }
      Position  : WORD;                 { 0E }
      Size      : LONGINT;              { 10 }
      RepStart  : LONGINT;              { 14 }
      RepLen    : LONGINT;              { 18 }
      Volume    : WORD;                 { 1C }
      Byte1     : BYTE;                 { 1E }
      Looped    : BOOLEAN;              { 1F }
      PeriodFine: WORD;                 { 20 }
      fill3     : ARRAY[1..10] OF BYTE; { 22 }
      Word3     : WORD;                 { 2C }
      Word4     : WORD;                 { 2E }
      Comment   : ARRAY[1..28] OF CHAR; { 30 }
      Id        : TS3mFileMagic2;       { 4C }
    END;

  TOffsets    = ARRAY[1..256] OF WORD;
  TInstrFlags = ARRAY[1..256] OF BOOLEAN;

VAR
  MaxChans   : WORD;
  InitialPos : LONGINT;




PROCEDURE SeekToOfs(VAR St: TStream; Ofs: WORD);
  BEGIN
    St.Seek(InitialPos + 16*LONGINT(Ofs));
  END;



PROCEDURE ProcessPatterns(VAR Song: TSong; VAR St: TStream; VAR InstrFlags : TInstrFlags;
                          VAR PattOfs: TOffsets; Num: WORD; S3m: BOOLEAN; Vers: BYTE);
  VAR
    Patt      : ARRAY[1..5000] OF BYTE;
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
    LastChan  : WORD;
  LABEL
    Ya, No;
  BEGIN
    t := 1;
    FOR n := 1 TO Num DO
      BEGIN
        FOR i := 1 TO Song.SequenceLength DO
          IF Song.PatternSequence^[i] = n THEN GOTO Ya;

        GOTO No;
Ya:
{WriteLn('Patt ', n : 3, FullHeap.HMaxAvail : 10, FullHeap.HMemAvail : 10);}
        Pattern := Song.GetPattern(n);
        IF Pattern = NIL THEN
          BEGIN
            Song.Status := msOutOfMemory;
            EXIT;
          END;

        WITH Pattern^.Patt^ DO
          BEGIN
            NNotes   := 64;
            NChans   := Song.NumChannels;
            Tempo    := 0;
            BPM      := 0;
          END;

        SeekToOfs(St, PattOfs[n]);


        IF S3m OR (Vers > $1A) THEN
          St.Read(Size, 2)
        ELSE
          Size := SizeOf(Patt) + 2;

        DEC(Size, 2);

        IF Size > SizeOf(Patt) THEN
          Size := SizeOf(Patt);

        St.Read(Patt, Size);
        IF St.Status <> stOk THEN
          BEGIN
            Song.Status := msFileTooShort;
            EXIT;
          END;

        LastChan := 1;
        FOR j := 1 TO Song.NumChannels DO
          BEGIN
            FillChar(FullTrack, SizeOf(FullTrack), 0);

            i    := 1;
            Row  := 0;
            WHILE (i <= Size)         AND
                  (S3m OR (Row < 64)) DO
              BEGIN

                c := Patt[i];
                INC(i);

                IF c = 0 THEN
                  Inc(Row)
                ELSE IF (c AND $1F) = (j - 1) THEN
                  BEGIN

                    FillChar(Note, SizeOf(Note), 0);

                    IF c AND $20 <> 0 THEN
                      BEGIN
                        Note.Period     := Patt[i];
                        IF NOT S3m THEN
                          INC(Note.Period, $20);
{                        INC(Note.Period, $10);}
                        IF ((Note.Period AND $F0) > $90) OR
                           ((Note.Period AND $F0) < $20) OR
                           ((Note.Period AND $0F) > $0B) THEN
                          BEGIN
{
                            Song.Status := msFileDamaged;
                            EXIT;
}
                            Note.Period := 0;
                          END;

                        IF Note.Period <> 0 THEN
                          BEGIN
                            Note.Period := PeriodSet[
                              (Note.Period SHR 4) - 2, Note.Period AND 15];
                            IF MaxChans <= (c AND $1F) THEN
                              MaxChans := (c AND $1F) + 1;
                          END;

                        Note.Instrument := Patt[i+1];

                        IF Note.Instrument <> 0 THEN
                          InstrFlags[Note.Instrument] := TRUE;

                        INC(i, 2);
                      END;

                    IF c AND $40 <> 0 THEN
                      BEGIN
                        Note.Volume := Patt[i] + 1;
                        IF Note.Volume > 64 THEN
                          Note.Volume := 64;
                        INC(i, 1);
                      END;

                    IF c AND $80 <> 0 THEN
                      BEGIN
                        Note.Parameter := Patt[i+1];
                        CASE Patt[i] OF
                           1 : BEGIN
                                 Note.Command := mcSetTempo;
                                 IF NOT S3m THEN
                                   Note.Parameter := Note.Parameter SHR 4;
                               END;
                           2 : BEGIN
                                 Note.Command := mcJumpPattern;
                                 INC(Note.Parameter);
                               END;
                           3 : Note.Command := mcEndPattern;
                           4 : BEGIN
                                 IF Note.Parameter > $F0 THEN
                                   BEGIN
                                     Note.Command   := mcVolFineDown;
                                     Note.Parameter := Note.Parameter AND $F;
                                   END
                                 ELSE IF ((Note.Parameter AND $F) = $F) AND
                                         (Note.Parameter > $F)          THEN
                                   BEGIN
                                     Note.Command   := mcVolFineUp;
                                     Note.Parameter := Note.Parameter SHR 4;
                                   END
                                 ELSE
                                   Note.Command := mcVolSlide;
                               END;
                           5 : BEGIN
                                 IF Note.Parameter >= $F0 THEN
                                   BEGIN
                                     Note.Command   := mcFinePortaDn;
                                     Note.Parameter := Note.Parameter AND $F;
                                   END
                                 ELSE IF Note.Parameter >= $E0 THEN
                                   BEGIN
                                     Note.Command   := mcFinePortaDn;
                                     Note.Parameter := ((Note.Parameter AND $F) + 2) SHR 2;
                                   END
                                 ELSE
                                   Note.Command := mcTPortDown;
                               END;
                           6 : BEGIN
                                 IF Note.Parameter >= $F0 THEN
                                   BEGIN
                                     Note.Command   := mcFinePortaUp;
                                     Note.Parameter := Note.Parameter AND $F;
                                   END
                                 ELSE IF Note.Parameter >= $E0 THEN
                                   BEGIN
                                     Note.Command   := mcFinePortaUp;
                                     Note.Parameter := ((Note.Parameter AND $F) + 2) SHR 2;
                                   END
                                 ELSE
                                   Note.Command := mcTPortUp;
                               END;
                           7 : Note.Command := mcNPortamento;
                           8 : Note.Command := mcVibrato;
                          10 : Note.Command := mcArpeggio;
                          11 : Note.Command := mcVib_VSlide;
                          15 : Note.Command := mcSampleOffs;
                          17 : BEGIN
                                 Note.Command   := mcS3mRetrigNote;
                                 Note.Parameter := Note.Parameter;
                               END;
                          20 : IF Note.Parameter > $30 THEN
                                 Note.Command   := mcSetTempo
                               ELSE
                                 Note.Command   := mcNone;
                        ELSE
                          Note.Command := TModCommand(ORD(mcLast) + Patt[i]);
                        END;

                        IF ((Note.Command = mcEndPattern) OR (Note.Command = mcJumpPattern)) AND
                           (Pattern^.Patt^.NNotes > Row + 1) THEN
                          Pattern^.Patt^.NNotes := Row + 1;

                        INC(i, 2);
                      END;

                    FullTrack[Row] := Note;
                  END
                ELSE
                  BEGIN
                    IF (j = 1) AND (LastChan < (c AND $1F) + 1) THEN
                      LastChan := (c AND $1F) + 1;
                    IF c AND $20 <> 0 THEN INC(i, 2);
                    IF c AND $40 <> 0 THEN INC(i, 1);
                    IF c AND $80 <> 0 THEN INC(i, 2);
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

            IF j > LastChan THEN GOTO No;
          END;
No:
      END;
  END;


PROCEDURE ProcessInstruments(VAR Song: TSong; VAR St: TStream; VAR InstrFlags : TInstrFlags;
                             VAR InstrOfs: TOffsets; Num: WORD; S3m: BOOLEAN; Vers: BYTE);
  VAR
    Instrument : TInstrumentRec;
    Instr      : PInstrument;
    S3mInstr   : TS3mInstrument;
    i, w       : WORD;
    Signo      : LONGINT;
    NoSigno    : LONGINT;
  BEGIN
    FOR i := 1 TO Num DO
      WITH Instrument DO
        BEGIN
{WriteLn('Instr ', i : 3, FullHeap.HMaxAvail : 10, FullHeap.HMemAvail : 10);}
          FillChar(Instrument, SizeOf(Instrument), 0);

          Instr := Song.GetInstrument(i);
          IF Instr = NIL THEN
            BEGIN
              Song.Status := msOutOfMemory;
              EXIT;
            END;

          SeekToOfs(St, InstrOfs[i]);
          St.Read(S3mInstr, SizeOf(S3mInstr));

          IF S3mInstr.Comment[1] <> #0 THEN
            Instr^.SetName(StrASCIIZ(S3mInstr.Comment, 25))
          ELSE
            Instr^.SetName(StrASCIIZ(S3mInstr.Name,    13));

          IF S3mInstr.Flag = 1 THEN
            BEGIN
              IF InstrFlags[i] THEN
                Len := S3mInstr.Size;

              IF Len > 0 THEN
                BEGIN

                  IF S3mInstr.Looped THEN
                    BEGIN
                      Reps := S3mInstr.RepStart;
                      Repl := S3mInstr.RepLen - Reps;
                    END
                  ELSE
                    BEGIN
                      Reps := 0;
                      Repl := 0;
                    END;

                  Vol  := S3mInstr.Volume;
                  DAdj := S3mInstr.PeriodFine;
                  IF S3m THEN
                    NAdj := $20AB
                  ELSE
                    NAdj := $2100;

                  IF Repl        > Len THEN Repl := Len;
                  IF Reps + Repl > Len THEN Repl := Len - Reps;

                  IF Vol > $40 THEN
                    Vol := $40;

                  SeekToOfs(St, S3mInstr.Position);

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

                      Signo   := 0;
                      NoSigno := 0;
                      FOR w := 1 TO Len - 1 DO
                        BEGIN
                          IF (Data^[w-1] XOR Data^[w]) AND $80 <> 0 THEN
                            BEGIN
                              IF (SHORTINT(Data^[w]   - 64) < 0) AND
                                 (SHORTINT(Data^[w-1] - 64) < 0) THEN
                                INC(Signo)
                              ELSE IF (SHORTINT(Data^[w]   - 64) >= 0) AND
                                      (SHORTINT(Data^[w-1] - 64) >= 0) THEN
                                INC(NoSigno)
                            END;
                        END;

                      IF NoSigno > Signo THEN
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

                  Instr^.Change(@Instrument);
                END
              ELSE
                Instr^.Change(NIL);
            END;
        END;
  END;


PROCEDURE LoadS3mFileFormat(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);
  VAR
    Hdr        : TS3mHeader ABSOLUTE Header;
    InstrOfs   : TOffsets;
    PattOfs    : TOffsets;
    i          : WORD;
    InstrFlags : TInstrFlags;
  BEGIN
    Song.FileFormat := mffS3m;

    InitialPos := St.GetPos;

    St.Seek(InitialPos + SizeOf(TS3mHeader));

    IF {(Hdr.Magic1 <> S3mMagic1) OR }(Hdr.Magic2 <> S3mMagic2) THEN
      BEGIN
        Song.Status := msNotLoaded;
        EXIT;
      END;

    Song.Status := msOK;

    FillChar(InstrFlags, SizeOf(InstrFlags), 0);

    Song.Name := FullHeap.HNewStr(StrASCIIZ(Hdr.Name, 28));

    IF Hdr.Volume = 64 THEN Hdr.Volume := 63;
{    Song.FirstTick    := TRUE;}
    Song.InitialTempo := Hdr.Tempo;
    Song.InitialBPM   := Hdr.BPM;
    Song.Volume       := Hdr.Volume * 4 + 3;
    Song.NumChannels  := MaxChannels;
    MaxChans := 1;

    FOR i := 1 TO 32 DO
      IF Hdr.ChannelMaps[i] <> $FF THEN
        IF (Hdr.ChannelMaps[i] AND 8) = 0 THEN
          Song.PanPositions[i] := $40
        ELSE
          Song.PanPositions[i] := $B0;

    Song.SequenceRepStart := 0;{Hdr.NPI1 + 1;}
    St.Read(Song.PatternSequence^, Hdr.SeqLen);

    IF Hdr.SeqLen > Song.SongLen THEN
      Hdr.SeqLen := Song.SongLen;
    Song.SequenceLength   := Hdr.SeqLen;

    FOR i := 1 TO Hdr.SeqLen DO
      INC(Song.PatternSequence^[i]);

    St.Read(InstrOfs, Hdr.NInstruments*2);
    St.Read(PattOfs,  Hdr.NPatts*2);

    WHILE (Song.SequenceLength                        > 1) AND
          (Song.PatternSequence^[Song.SequenceLength] = 0) DO
      DEC(Song.SequenceLength);

    FOR i := 1 TO Song.SongStart - 1 DO
      Song.PatternSequence^[i] := 0;


    { Processing of the patterns (the partiture) }

    ProcessPatterns(Song, St, InstrFlags, PattOfs, Hdr.NPatts, TRUE, $FF);
    IF Song.Status > msOk THEN EXIT;


    { Processing of the instruments }

    ProcessInstruments(Song, St, InstrFlags, InstrOfs, Hdr.NInstruments, TRUE, $FF);
    IF Song.Status > msFileTooShort THEN EXIT;

    IF Song.NumChannels > MaxChans THEN
      Song.NumChannels := MaxChans;
  END;




PROCEDURE LoadS2mFileFormat(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);
  VAR
    Hdr        : TS2mHeader ABSOLUTE Header;
    InstrOfs   : TOffsets;
    PattOfs    : TOffsets;
    i          : WORD;
    InstrFlags : TInstrFlags;
  BEGIN
    Song.FileFormat := mffS2m;

    InitialPos := St.GetPos;

    St.Seek(InitialPos + SizeOf(TS2mHeader));

    IF Hdr.Magic <> S2mMagic THEN
      BEGIN
        Song.Status := msNotLoaded;
        EXIT;
      END;

    Song.Status := msOK;

    FillChar(InstrFlags, SizeOf(InstrFlags), 0);

    Song.Name := FullHeap.HNewStr(StrASCIIZ(Hdr.Name, 20));

    IF Hdr.Volume = 64 THEN Hdr.Volume := 63;
    Song.FirstTick    := TRUE;
    Song.InitialTempo := Hdr.Tempo SHR 4;
    Song.InitialBPM   := 125;
    Song.Volume       := Hdr.Volume * 4 + 3;
    Song.NumChannels  := MaxChannels;
    MaxChans := 1;

    Song.SequenceRepStart := 0;

    SeekToOfs(St, Hdr.InstrOfs);
    St.Read(InstrOfs, (Hdr.NInstruments*2 + 15) AND $FFF0);

    SeekToOfs(St, Hdr.PattOfs);
    St.Read(PattOfs,  (Hdr.NPatts*2 + 15) AND $FFF0);

    SeekToOfs(St, Hdr.SeqOfs);
    St.Read(Song.PatternSequence^, 16);
    St.Read(Song.PatternSequence^, 16);

    DEC(Hdr.SeqLen);
    FOR i := 1 TO Hdr.SeqLen DO
      BEGIN
        St.Read(Song.PatternSequence^[i], 5);
        INC(Song.PatternSequence^[i]);
      END;

    IF Hdr.SeqLen > Song.SongLen THEN
      Hdr.SeqLen := Song.SongLen;
    Song.SequenceLength   := Hdr.SeqLen;

    WHILE (Song.SequenceLength                        > 1) AND
          (Song.PatternSequence^[Song.SequenceLength] = 0) DO
      DEC(Song.SequenceLength);

    FOR i := 1 TO Song.SongStart - 1 DO
      Song.PatternSequence^[i] := 0;


    { Processing of the patterns (the partiture) }

    ProcessPatterns(Song, St, InstrFlags, PattOfs, Hdr.NPatts, FALSE, Hdr.Version);
    IF Song.Status > msOk THEN EXIT;


    { Processing of the instruments }

    ProcessInstruments(Song, St, InstrFlags, InstrOfs, Hdr.NInstruments, FALSE, Hdr.Version);
    IF Song.Status > msFileTooShort THEN EXIT;

    IF Song.NumChannels > MaxChans THEN
      Song.NumChannels := MaxChans;
  END;




END.
