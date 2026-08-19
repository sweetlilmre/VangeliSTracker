UNIT ModLoader;

INTERFACE

USES Objects, SongUnit;




PROCEDURE LoadModFileFormat  (VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);




IMPLEMENTATION

USES SongElements, Heaps, AsciiZ;




{----------------------------------------------------------------------------}
{ Internal definitions. Format of the files.                                 }
{____________________________________________________________________________}

TYPE
  TModFileMagic = ARRAY[0..3] OF CHAR;

CONST
  Mod31MagicM_K_ : TModFileMagic = ( 'M', '.', 'K', '.' );
  Mod31MagicFLT4 : TModFileMagic = ( 'F', 'L', 'T', '4' );
  Mod31Magic6CHN : TModFileMagic = ( '6', 'C', 'H', 'N' );
  Mod31Magic8CHN : TModFileMagic = ( '8', 'C', 'H', 'N' );

TYPE

  { Instrument in a MOD file. 30 bytes. }

  TModFileInstrument = RECORD
    Name       : ARRAY [1..22] OF CHAR; { AsciiZ string, name of the instrument. }
    Len        : WORD;                  { Length of the sample DIV 2.            }
    FineTune,                           { Fine tuning value.                     }
    Vol        : BYTE;                  { Default volume.                        }
    LoopStart,                          { Offset of the loop DIV 2.              }
    LoopLen    : WORD;                  { Length of the loop DIV 2.              }
  END;

  { Note in the file. 4 bytes. }

  PModFileNote = ^TModFileNote;
  TModFileNote = RECORD
    CASE INTEGER OF
      1: (l              : LONGINT);
      2: (w1, w2         : WORD);
      3: (b1, b2, b3, b4 : BYTE);
  END;

  PModFilePattern = ^TModFilePattern;
  TModFilePattern =
    RECORD
      CASE BYTE OF
        4 : ( Patt4 : ARRAY [0..63] OF ARRAY [1..4] OF TModFileNote );
        5 : ( Patt5 : ARRAY [0..63] OF ARRAY [1..5] OF TModFileNote );
        6 : ( Patt6 : ARRAY [0..63] OF ARRAY [1..6] OF TModFileNote );
        7 : ( Patt7 : ARRAY [0..63] OF ARRAY [1..7] OF TModFileNote );
        8 : ( Patt8 : ARRAY [0..63] OF ARRAY [1..8] OF TModFileNote );
    END;                                                   

  { 15 samples module header format. 600 bytes. }

  PModFile15 = ^TModFile15;
  TModFile15 = RECORD
    Name        : ARRAY [1..20] OF CHAR;               { AsciiZ song name.                   }
    Samples     : ARRAY [1..15] OF TModFileInstrument; { Instruments.                        }
    SongLen     : BYTE;                                { Length of the sequency of the song. }
    SongRep     : BYTE;                                { Song loop start position.           }
    PatternList : ARRAY [0..127] OF BYTE;              { Pattern sequencies.                 }
  END;

  { 31 samples module header format. 1084 bytes. }

  PModFile31 = ^TModFile31;
  TModFile31 = RECORD
    Name        : ARRAY [1..20] OF CHAR;               { AsciiZ song name.                   }
    Samples     : ARRAY [1..31] OF TModFileInstrument; { Instruments.                        }
    SongLen     : BYTE;                                { Length of the sequency of the song. }
    SongRep     : BYTE;                                { Song loop start position.           }
    PatternList : ARRAY [0..127] OF BYTE;              { Pattern sequencies.                 }
    Magic       : TModFileMagic;                       { Magic number ("M.K.", "FLT4", etc.) }
  END;





PROCEDURE ProcessPatterns(VAR Song: TSong; VAR St: TStream; Num: WORD);
  VAR
    Patt      : TModFilePattern;
    FullTrack : TFullTrack;
    Pattern   : PPattern;
    Track     : PTrack;
    i, j      : WORD;
    n, t      : WORD;
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
            NNotes   := 64;
            NChans   := Song.NumChannels;
            Tempo    := 0;
            BPM      := 0;
          END;

        l := St.GetPos;
        St.Read(Patt, 64*4*Song.NumChannels);

        IF St.Status <> stOk THEN
          BEGIN
            Song.Status := msFileTooShort;
            EXIT;
          END;

        CASE Song.NumChannels OF
          4 : FOR i := 63 DOWNTO 0 DO
                FOR j := Song.NumChannels DOWNTO 1 DO
                  Patt.Patt8[i][j] := Patt.Patt4[i][j];
          5 : FOR i := 63 DOWNTO 0 DO
                FOR j := Song.NumChannels DOWNTO 1 DO
                  Patt.Patt8[i][j] := Patt.Patt5[i][j];
          6 : FOR i := 63 DOWNTO 0 DO
                FOR j := Song.NumChannels DOWNTO 1 DO
                  Patt.Patt8[i][j] := Patt.Patt6[i][j];
          7 : FOR i := 63 DOWNTO 0 DO
                FOR j := Song.NumChannels DOWNTO 1 DO
                  Patt.Patt8[i][j] := Patt.Patt7[i][j];
        END;

        FOR j := 1 TO Song.NumChannels DO
          BEGIN
            FillChar(FullTrack, SizeOf(FullTrack), 0);

            FOR i := 0 TO 63 DO
              WITH FullTrack[i], Patt.Patt8[i][j] DO
                BEGIN
                  Command     := TModCommand((b3 AND $F) + 1);
                  IF Command = mcExtended THEN
                    BEGIN
                      Parameter := b4 AND $F;
                      Command   := TModCommand(($11 + (b4 SHR 4)));
                    END
                  ELSE IF (Command = mcArpeggio) AND (b4 = 0) THEN
                    BEGIN
                      Parameter := 0;
                      Command   := mcNone;
                    END
                  ELSE
                    Parameter := b4;

                  Period     := b2 + (WORD(b1 AND $7) SHL 8);
                  Instrument := (b3 SHR 4) + (b1 AND 16);

                  IF ((Command = mcEndPattern) OR (Command = mcJumpPattern)) AND
                     (Pattern^.Patt^.NNotes > i + 1) THEN
                    Pattern^.Patt^.NNotes := i + 1;

                  IF (Command = mcSetVolume) AND (Parameter > $40) THEN
                    Parameter := $40;

                  IF (Command = mcJumpPattern) THEN
                    Parameter := (Parameter AND $0F) +
                                 (Parameter SHR   4)*10 + 1;

                  IF (Command = mcEndPattern) THEN
                    Parameter := (Parameter AND 63) + 1;
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


PROCEDURE ProcessInstruments(VAR Song: TSong; VAR St: TStream; Mod31: TModFile31);
  CONST
    MinLoop = 1024;
    FineTuneTable : ARRAY[0..15] OF WORD = ( $43CD,$444B,$44CA,$454A,
                                             $45CA,$464C,$46CF,$4752,
                                             $4000,$4076,$40EE,$4166,
                                             $41E0,$425A,$42D5,$4351 );

  VAR
    Instrument : TInstrumentRec;
    Instr      : PInstrument;
    i, j, k    : WORD;
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

          Instr^.SetName(StrASCIIZ(Mod31.Samples[i].Name, 22));

          Len  := LONGINT(SWAP(Mod31.Samples[i].Len)      ) SHL 1;

          IF Len > St.GetSize - St.GetPos THEN
            BEGIN
              Len := St.GetSize - St.GetPos;
              Song.Status := msFileTooShort;
            END;

          IF Len > 0 THEN
            BEGIN

              Reps := LONGINT(SWAP(Mod31.Samples[i].LoopStart)) SHL 1;
              Repl := LONGINT(SWAP(Mod31.Samples[i].LoopLen)  ) SHL 1;
              Vol  :=              Mod31.Samples[i].Vol;

              IF Repl        > Len THEN Repl := Len;
              IF Reps + Repl > Len THEN Reps := Len - Repl;

              IF Mod31.Samples[i].Vol > $40 THEN
                Mod31.Samples[i].Vol := $40;

              IF Vol > $40 THEN
                Vol := $40;

              NAdj := FineTuneTable[0];
              DAdj := FineTuneTable[Mod31.Samples[i].FineTune AND $F];

              IF Len <= MaxSample THEN
                BEGIN
                  IF Repl > 4 THEN
                    FullHeap.HGetMem(POINTER(Data), Len+Repl*(MinLoop DIV Repl))
                  ELSE
                    FullHeap.HGetMem(POINTER(Data), Len);

                  IF Data = NIL THEN BEGIN
                    Song.Status := msOutOfMemory;
                    EXIT;
                  END;

                  St.Read(Data^, Len);

                  IF Repl > 4 THEN
                    FOR j := 1 TO MinLoop DIV Repl DO
                      FOR k := 0 TO Repl - 1 DO
                        Data^[Reps + j*Repl + k] := Data^[Reps + k];

                  IF Repl > 4 THEN
                    BEGIN
                      Len  := Len  + Repl*(MinLoop DIV Repl);
                      Repl := Repl + Repl*(MinLoop DIV Repl);
                    END;

                  IF St.Status <> stOk THEN BEGIN
                    Song.Status := msFileDamaged;
                    EXIT;
                  END;

{
                  FOR w := 0 TO Len - 1 DO
                    IF Instruments[i].data^[w] = -128 THEN
                      Instruments[i].data^[w] := -127;
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

              Instr^.Change (@Instrument);
            END;
        END;
  END;


PROCEDURE LoadMod(VAR Song: TSong; VAR St: TStream; VAR Mod31: TModFile31);
  VAR
    j, k,
    i, w       : WORD;
    IsMod31    : BOOLEAN;
    NumberOfPatterns : WORD;

  BEGIN

    { Initial checkings to see if it's a real MOD. }

    Song.Status := msFileDamaged;

    FOR i := 0 TO 127 DO
      IF Mod31.PatternList[i] > 63 THEN EXIT;

    FOR i := 1 TO 20 DO
      IF (Mod31.Name[i] < ' ') AND
         (Mod31.Name[i] <> #0) THEN EXIT;
{
    FOR j := 1 TO 31 DO
      FOR i := 1 TO 21 DO
        IF (Mod31.Samples[j].Name[i] < ' ') AND
           (Mod31.Samples[j].Name[i] <> #0) THEN EXIT;
}
    IF (Mod31.SongLen > 128) OR (Mod31.SongRep > 128) THEN EXIT;


    { Processing of the header }

    Song.Status := msOK;

    Song.Name := FullHeap.HNewStr(StrASCIIZ(Mod31.Name, 20));

    Song.InitialTempo := 6;
    Song.InitialBPM   := 125;
    Song.Volume       := 255;

    FOR i := 0 TO 127 DO
      INC(Mod31.PatternList[i]);
    Move(Mod31.PatternList, Song.PatternSequence^, Mod31.SongLen);
    Song.SequenceLength   := Mod31.SongLen;
    Song.SequenceRepStart := Mod31.SongRep + 1;

    NumberOfPatterns := 0;
    FOR i := 0 TO 127 DO
      IF NumberOfPatterns < Mod31.PatternList[i] THEN
        NumberOfPatterns := Mod31.PatternList[i];


    { Processing of the patterns (the partiture) }

    ProcessPatterns(Song, St, NumberOfPatterns);
    IF Song.Status > msOk THEN EXIT;


    { Processing of the instruments }

    ProcessInstruments(Song, St, Mod31);
    IF Song.Status > msFileTooShort THEN EXIT;
  END;




PROCEDURE LoadMod15(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);
  VAR
    i     : WORD;
    Mod31 : TModFile31 ABSOLUTE Header;
    Mod15 : TModFile15 ABSOLUTE Header;
  BEGIN
    Move(Mod15.SongLen, Mod31.SongLen, 130);
    FOR i := 16 TO 31 DO
      FillChar(Mod31.Samples[i], SizeOf(Mod31.Samples[i]), 0);

    St.Seek(St.GetPos - SizeOf(TModFile31) + SizeOf(TModFile15));

    LoadMod(Song, St, Mod31);
  END;


PROCEDURE LoadModFileFormat  (VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);
  VAR
    Mod31 : TModFile31 ABSOLUTE Header;
  BEGIN
    St.Seek(St.GetPos + SizeOf(TModFile31));

    IF (Mod31.Magic = Mod31MagicM_K_) THEN
      BEGIN
        IF Song.FileExt = '.WOW' THEN
          BEGIN
            Song.NumChannels := 8;
            Song.FileFormat  := mffWow8;
          END
        ELSE
          BEGIN
            Song.NumChannels := 4;
            Song.FileFormat  := mffMod31M_K_;
          END;

        LoadMod(Song, St, Mod31);
      END
    ELSE IF (Mod31.Magic = Mod31MagicFLT4) THEN
      BEGIN
        Song.NumChannels := 4;
        Song.FileFormat  := mffMod31FLT4;
        LoadMod(Song, St, Mod31);
      END
    ELSE IF (Mod31.Magic = Mod31Magic6CHN) THEN
      BEGIN
        Song.NumChannels := 6;
        Song.FileFormat  := mffFastTracker;
        LoadMod(Song, St, Mod31);
      END
    ELSE IF (Mod31.Magic = Mod31Magic8CHN) THEN
      BEGIN
        Song.NumChannels := 8;
        Song.FileFormat  := mffFastTracker;
        LoadMod(Song, St, Mod31);
      END
    ELSE
      BEGIN
        Song.NumChannels := 4;
        Song.FileFormat  := mffMod15;
        LoadMod15(Song, St, Header);
      END

  END;




END.
