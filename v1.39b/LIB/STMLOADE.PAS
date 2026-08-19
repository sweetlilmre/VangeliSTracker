UNIT StmLoader;

INTERFACE

USES Objects, SongUnit;




PROCEDURE LoadStmFileFormat(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);




IMPLEMENTATION

USES SongElements, SongUtils, Heaps, AsciiZ;




{----------------------------------------------------------------------------}
{ Internal definitions. Format of the files.                                 }
{____________________________________________________________________________}

TYPE
  TStmFileMagic = ARRAY[1..8] OF CHAR;

CONST
  MagicStm : TStmFileMagic = ( '!', 'S', 'c', 'r', 'e', 'a', 'm', '!' );

TYPE

  TStmInstrument =
    RECORD
      Name      : ARRAY[1..14] OF CHAR;
      fill1     : WORD;
      Size      : WORD;
      RepStart  : WORD;
      RepEnd    : WORD;
      Volume    : WORD;
      NAdj      : WORD;
      fill2     : ARRAY[1..6] OF BYTE;
    END;

  TStmHeader =
    RECORD
      Name        : ARRAY[1..20] OF CHAR;
      Magic       : TStmFileMagic;
      fill1       : LONGINT;
      Tempo       : BYTE;
      NPatterns   : BYTE;
      Volume      : BYTE;
      fill2       : ARRAY[1..13]  OF BYTE;
      Instruments : ARRAY[1..31]  OF TStmInstrument;
      Sequence    : ARRAY[1..128] OF BYTE;
    END;

  TStmPattern = ARRAY[1..64, 1..4] OF
    RECORD
      b1, b2,
      b3, b4 : BYTE;
    END;




PROCEDURE ProcessPatterns(VAR Song: TSong; VAR St: TStream; Num: WORD);
  VAR
    Patt      : TStmPattern;
    FullTrack : TFullTrack;
    Pattern   : PPattern;
    Track     : PTrack;
    c         : BYTE;
    i, j      : WORD;
    n, t      : WORD;
    Row       : WORD;
    Size      : WORD;
    NAdj      : WORD;
    Perd      : WORD;
    l         : LONGINT;
  BEGIN
    t := 1;
    FOR n := 1 TO Num DO
      BEGIN
{WriteLn('Patt ', n : 3, FullHeap.HMaxAvail : 10, FullHeap.HMemAvail : 10);}
        Pattern := Song.GetPattern(n);
        IF Pattern = NIL THEN
          BEGIN
            Song.Status := msOutOfMemory;
            EXIT;
          END;

        WITH Pattern^.Patt^ DO
          BEGIN
            NNotes := 64;
            NChans := Song.NumChannels;
            Tempo  := 0;
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
                  FillChar(FullTrack[i-1], SizeOf(FullTrack[0]), 0);

                  IF b1 <> $FF THEN
                    BEGIN
                      Period := b1;
                      IF ((Period AND $F0) > $70) OR
                         ((Period AND $F0) < $00) OR
                         ((Period AND $0F) > $0B) THEN
                        Period := 0;
                      Instrument := b2 SHR 3;
                    END;

                  Volume := ((b3 AND $F0) SHR 1) + (b2 AND $07);

                  IF Volume > 64 THEN
                    Volume := 0
                  ELSE IF Volume < 64 THEN
                    INC(Volume);

                  Parameter := b4;
                  CASE b3 AND $F OF
                     0 : Command := mcNone;
                     1 : BEGIN
                           Command   := mcSetTempo;
                           Parameter := b4 SHR 4;
                         END;
                     2 : BEGIN
                           Command := mcJumpPattern;
                           INC(Parameter);
                         END;
                     3 : Command := mcEndPattern;
                     4 : Command := mcVolSlide;
                     5 : Command := mcTPortDown;
                     6 : Command := mcTPortUp;
                     7 : Command := mcNPortamento;
                     8 : Command := mcVibrato;
                    10 : Command := mcArpeggio;
                  ELSE
                    Command := TModCommand(ORD(mcLast) + (b3 AND $F));
                  END;

                  IF ((Command = mcEndPattern) OR (Command = mcJumpPattern)) AND
                     (Pattern^.Patt^.NNotes > i) THEN
                    Pattern^.Patt^.NNotes := i;

                  IF Period <> 0 THEN
                    BEGIN
{
                      IF (Song.GetInstrument(Instrument)        = NIL) OR
                         (Song.GetInstrument(Instrument)^.Instr = NIL) THEN
                        Dadj := NAdj
                      ELSE
                        DAdj := Song.GetInstrument(Instrument)^.Instr^.DAdj;
}
                      Perd := PeriodSet[(Period SHR 4), Period AND 15];
{
                      IF DAdj > $3E7 THEN
                        ASM
                          MOV     AX,Perd
                          MOV     BX,$20AB
                          MUL     BX
                          MOV     BX,DAdj
                          DIV     BX
                          MOV     Perd,AX
                        END;
}
                      Period := Perd;
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


PROCEDURE ProcessInstruments(VAR Song: TSong; VAR St: TStream; VAR Hdr: TStmHeader);
  VAR
    Instrument : TInstrumentRec;
    Instr      : PInstrument;
    i, w       : WORD;
    Signo      : LONGINT;
    NoSigno    : LONGINT;
  BEGIN
    FOR i := 1 TO 31 DO
      WITH Instrument DO
        BEGIN
          FillChar(Instrument, SizeOf(Instrument), 0);

          Instr := Song.GetInstrument(i);
          IF Instr = NIL THEN
            BEGIN
              Song.Status := msOutOfMemory;
              EXIT;
            END;

          Instr^.SetName(StrASCIIZ(Hdr.Instruments[i].Name, 14));

          Len  := Hdr.Instruments[i].Size;

          IF Len > 0 THEN
            BEGIN

              IF (Hdr.Instruments[i].RepStart <>     0) OR
                 (Hdr.Instruments[i].RepEnd   <> 65535) THEN
                BEGIN
                  Reps := Hdr.Instruments[i].RepStart;
                  Repl := Hdr.Instruments[i].RepEnd - Reps;
                END
              ELSE
                BEGIN
                  Reps := 0;
                  Repl := 0;
                END;

              Vol  := Hdr.Instruments[i].Volume;
              Dadj := Hdr.Instruments[i].Nadj;
              NAdj := $2100;

              IF Vol > $40 THEN
                Vol := $40;

              IF Repl        > Len THEN Repl := Len;
              IF Reps + Repl > Len THEN Repl := Len - Reps;

              Instr^.Change(@Instrument);
            END
          ELSE
            Instr^.Change(NIL);
        END;
  END;



PROCEDURE ProcessSamples(VAR Song: TSong; VAR St: TStream);
  VAR
    Instr      : PInstrument;
    Instrument : TInstrumentRec;
    i, w       : WORD;
    l          : LONGINT;
  BEGIN
    FOR i := 1 TO 31 DO
      BEGIN
{WriteLn('Instr ', i : 3, FullHeap.HMaxAvail : 10, FullHeap.HMemAvail : 10);}
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
      {
                        FOR w := 0 TO Len - 1 DO
                          INC(Data^[w], 128);
      }
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
              END;
            Instr^.Change(@Instrument);
          END;

        IF LowQuality THEN
          Instr^.Desample;

      END;
  END;

PROCEDURE LoadStmFileFormat(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);
  VAR
    Hdr        : TStmHeader ABSOLUTE Header;
    InitialPos : LONGINT;
    i          : WORD;
  BEGIN
    Song.FileFormat := mffStm;

    InitialPos := St.GetPos;

    St.Seek(InitialPos + SizeOf(TStmHeader));

    IF Hdr.Magic <> MagicStm THEN
      BEGIN
        Song.Status := msNotLoaded;
        EXIT;
      END;

    Song.Status := msOK;

    Song.Name := FullHeap.HNewStr(StrAsciiZ(Hdr.Name, 20));

    IF Hdr.Volume = 64 THEN
      Hdr.Volume := 63;

    Song.FirstTick    := TRUE;
    Song.InitialTempo := Hdr.Tempo SHR 4;
    Song.InitialBPM   := 125;
    Song.Volume       := Hdr.Volume SHL 2;
    Song.NumChannels  := 4;

    Song.SequenceLength := 0;
    FOR i := 1 TO 128 DO
      IF Hdr.Sequence[i] < 99 THEN
        Song.SequenceLength := i;

    Song.SequenceRepStart := 1;
    Move(Hdr.Sequence, Song.PatternSequence^, Song.SequenceLength);

    FOR i := 1 TO Song.SequenceLength DO
      INC(Song.PatternSequence^[i]);


    { Processing of the instruments }

    ProcessInstruments(Song, St, Hdr);
    IF Song.Status > msOk THEN EXIT;


    { Processing of the patterns (the partiture) }

    ProcessPatterns(Song, St, Hdr.NPatterns);
    IF Song.Status > msOk THEN EXIT;


    { Processing of the samples }

    ProcessSamples(Song, St);
    IF Song.Status > msFileTooShort THEN EXIT;
  END;




END.
