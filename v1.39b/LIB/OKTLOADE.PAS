UNIT OktLoader;

INTERFACE

USES Objects, SongUnit;




PROCEDURE LoadOktFileFormat (VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);




IMPLEMENTATION

USES SongUtils, SongElements, IFF, AsciiZ;




TYPE
  TModOktIdString = ARRAY[1..8] OF CHAR; { Oktalizer Id string (at the start of the file). }

CONST
  ModOktIdString : TModOktIdString = ('O', 'K', 'T', 'A', 'S', 'O', 'N', 'G');

TYPE

  { Note in the file. 4 bytes. }

  POktFileNote = ^TOktFileNote;
  TOktFileNote = RECORD
    CASE INTEGER OF
      1: (l              : LONGINT);
      2: (w1, w2         : WORD);
      3: (b1, b2, b3, b4 : BYTE);
  END;

  POktFilePattern = ^TOktFilePattern;
  TOktFilePattern =
    RECORD
      CASE BYTE OF
        4 : ( Patt4 : ARRAY [0..127] OF ARRAY [1..4] OF TOktFileNote );
        5 : ( Patt5 : ARRAY [0..127] OF ARRAY [1..5] OF TOktFileNote );
        6 : ( Patt6 : ARRAY [0..127] OF ARRAY [1..6] OF TOktFileNote );
        7 : ( Patt7 : ARRAY [0..127] OF ARRAY [1..7] OF TOktFileNote );
        8 : ( Patt8 : ARRAY [0..127] OF ARRAY [1..8] OF TOktFileNote );
    END;





TYPE
  TOktFile =
    OBJECT(TIffFile)
      Song           : PSong;
      OktPBODCount   : WORD;
      OktSBODCount   : WORD;
      OktTrackCount  : WORD;
      OktMaxChannels : WORD;

      CONSTRUCTOR Init(VAR MySong: TSong);
      DESTRUCTOR  Done; VIRTUAL;

      FUNCTION  DoBlock(VAR St: TStream;
                        Id: TIffBlockIdent; Size: LONGINT) : BOOLEAN; VIRTUAL;

      FUNCTION  OktProcCMOD(VAR St: TStream; Size: LONGINT) : BOOLEAN;
      FUNCTION  OktProcSAMP(VAR St: TStream; Size: LONGINT) : BOOLEAN;
      FUNCTION  OktProcSPEE(VAR St: TStream; Size: LONGINT) : BOOLEAN;
      FUNCTION  OktProcSLEN(VAR St: TStream; Size: LONGINT) : BOOLEAN;
      FUNCTION  OktProcPLEN(VAR St: TStream; Size: LONGINT) : BOOLEAN;
      FUNCTION  OktProcPATT(VAR St: TStream; Size: LONGINT) : BOOLEAN;
      FUNCTION  OktProcPBOD(VAR St: TStream; Size: LONGINT) : BOOLEAN;
      FUNCTION  OktProcSBOD(VAR St: TStream; Size: LONGINT) : BOOLEAN;
    END;










FUNCTION TOktFile.OktProcCMOD(VAR St: TStream; Size: LONGINT) : BOOLEAN;
  VAR
    MyBuff :
      RECORD
        w1     : WORD;
        w2     : WORD;
        w3     : WORD;
        w4     : WORD;
      END;
  BEGIN
    OktProcCMOD := FALSE;
    IF Size <> 8 THEN EXIT;

    St.Read(MyBuff, Size);

    { Ignore the words until we know what they mean. I just know they are "channel modes". }

    OktProcCMOD := TRUE;
  END;


FUNCTION TOktFile.OktProcSAMP(VAR St: TStream; Size: LONGINT) : BOOLEAN;
  TYPE
    TOktFileInstrument = RECORD
      Name       : ARRAY [1..20] OF CHAR; { AsciiZ string, name of the instrument. }
      Len        : LONGINT;               { Length of the sample DIV.              }
      RepS       : WORD;
      RepL       : WORD;
      fill1      : BYTE;
      Vol        : BYTE;                  { Default volume.                        }
      fill2      : WORD;
    END;
  VAR
    MyBuff     : TOktFileInstrument;
    Instr      : TInstrumentRec;
    Instrument : PInstrument;
    r          : WORD;
    i          : WORD;
    Rest       : LONGINT;
  BEGIN
    OktProcSAMP := FALSE;
    IF Size MOD 32 <> 0 THEN EXIT;

    FillChar(Instr, SizeOf(Instr), 0);

    Instr.Data  := NIL;
    Instr.Xtra  := NIL;
    Instr.FTune := 0;
    Instr.Prop  := 0;

    i := 1;
    WHILE Size >= 32 DO
      BEGIN
        St.Read(MyBuff, 32);
        Instr.len  := SwapLong(MyBuff.Len);
        Instr.reps := SWAP(MyBuff.RepS) SHL 1;
        Instr.repl := SWAP(MyBuff.RepL) SHL 1;
        Instr.vol  := MyBuff.Vol;

        Instrument := Song^.GetInstrument(i);
        IF Instr.Len > 0 THEN
          Instrument^.Change(@Instr)
        ELSE
          Instrument^.Change(NIL);
        Instrument^.SetName(StrASCIIZ(MyBuff.Name, 20) + '  ');

        INC(i);
        DEC(Size, 32);
      END;

    OktProcSAMP := TRUE;
  END;


FUNCTION TOktFile.OktProcSPEE(VAR St: TStream; Size: LONGINT) : BOOLEAN;
  VAR
    Spee : WORD;
  BEGIN
    OktProcSPEE := FALSE;
    IF Size <> 2 THEN EXIT;

    St.Read(Spee, 2);

    Song^.InitialTempo := SWAP(Spee);

    OktProcSPEE := TRUE;
  END;


FUNCTION TOktFile.OktProcSLEN(VAR St: TStream; Size: LONGINT) : BOOLEAN;
  BEGIN
    OktProcSLEN := TRUE;
  END;


FUNCTION TOktFile.OktProcPLEN(VAR St: TStream; Size: LONGINT) : BOOLEAN;
  VAR
    Len  : WORD;
  BEGIN
    OktProcPLEN := FALSE;
    IF Size <> 2 THEN EXIT;

    St.Read(Len, 2);

    Song^.SequenceLength := SWAP(Len);

    OktProcPLEN := TRUE;
  END;


FUNCTION TOktFile.OktProcPATT(VAR St: TStream; Size: LONGINT) : BOOLEAN;
  VAR
    i : WORD;
  BEGIN
    IF Size > MaxSequence THEN
      Size := MaxSequence;

    St.Read(Song^.PatternSequence^, Size);

    FOR i := 1 TO SizeOf(Song^.PatternSequence^) DO
      INC(Song^.PatternSequence^[i]);

    OktProcPATT := TRUE;
  END;


FUNCTION TOktFile.OktProcPBOD(VAR St: TStream; Size: LONGINT) : BOOLEAN;
  CONST
    FreqTable : ARRAY[0..35] OF WORD =
      (
        $0358,$0328,$02FB,$02D0,$02A7,$0281,$025D,$023B,$021B,$01FD,$01E0,$01C5,
        $01AC,$0194,$017D,$0168,$0154,$0141,$012F,$011E,$010E,$00FE,$00F0,$00E3,
        $00D6,$00CA,$00BF,$00B4,$00AA,$00A0,$0097,$008F,$0087,$007F,$0078,$0071
      );
  VAR
    i, j        : WORD;
    Length      : WORD;
    NumChannels : WORD;
    Patt        : TOktFilePattern;
    Pattern     : PPattern;
    FullTrack   : TFullTrack;
    Track       : PTrack;
  BEGIN
    OktProcPBOD := FALSE;
    IF Size < 6 THEN EXIT;
    IF Size > SizeOf(TOktFilePattern) + 2 THEN EXIT;

    St.Read(Length, 2);
    Length := SWAP(Length);
    IF Length > 128 THEN EXIT;
    NumChannels := (Size - 2) DIV (Length * 4);
    IF NumChannels > 8 THEN EXIT;
    IF NumChannels > OktMaxChannels THEN
      OktMaxChannels := NumChannels;

    Pattern := Song^.GetPattern(OktPBODCount);
    WITH Pattern^.Patt^ DO
      BEGIN
        NNotes := Length;
        Tempo  := 0;
        BPM    := 0;
      END;

    St.Read(Patt, Size-2);

    CASE NumChannels OF
      4 : FOR i := 63 DOWNTO 0 DO
            FOR j := NumChannels DOWNTO 1 DO
              Patt.Patt8[i][j] := Patt.Patt4[i][j];
      5 : FOR i := 63 DOWNTO 0 DO
            FOR j := NumChannels DOWNTO 1 DO
              Patt.Patt8[i][j] := Patt.Patt5[i][j];
      6 : FOR i := 63 DOWNTO 0 DO
            FOR j := NumChannels DOWNTO 1 DO
              Patt.Patt8[i][j] := Patt.Patt6[i][j];
      7 : FOR i := 63 DOWNTO 0 DO
            FOR j := NumChannels DOWNTO 1 DO
              Patt.Patt8[i][j] := Patt.Patt7[i][j];
    END;

    FillChar(FullTrack, SizeOf(FullTrack), 0);

    FOR j := 1 TO NumChannels DO
      BEGIN
        FOR i := 0 TO Length - 1 DO
          WITH FullTrack[i], Patt.Patt8[i][j] DO
            BEGIN
              Command := mcNone;
              Parameter := b4;
              
              CASE b3 OF
{ rs_portd-p   } $1 : Command := mcTPortDown;
{ rs_portu-p   } $2 : Command := mcTPortUp; 
{ rs_arp-p     } $A : Command := mcOktArp;
{ rs_arp2-p    } $B : Command := mcOktArp2;
                 $D : Command := mcNone; { rs_slided-p  }
{ p-rs_filt    } $F : Command := mcSetFilter;
                $11 : Command := mcNone; { p-rs_slideu  }
                $15 : Command := mcNone; { p-rs_slided  }
{ p-rs_posjmp  }$19 : BEGIN
                        Command   := mcJumpPattern;
                        Parameter := (Parameter AND $F) + (Parameter SHR 4)*10 + 1;
                      END;
{ p-rs_release }$1B : Command := mcRetrigNote;
{ p-rs_cspeed  }$1C : Command := mcSetTempo;
                $1E : Command := mcNone; { rs_slideu-p  }
{ rs_volume-p  }$1F : BEGIN
                        IF Parameter <= 64 THEN
                          BEGIN
                            Command := mcSetVolume;
                          END
                        ELSE IF Parameter < $50 THEN
                          BEGIN
                            Command   := mcVolSlide;
                            Parameter := Parameter - $40;
                          END
                        ELSE IF Parameter < $60 THEN
                          BEGIN
                            Command   := mcVolFineDown;
                            Parameter := Parameter - $50;
                          END
                        ELSE IF Parameter < $70 THEN
                          BEGIN
                            Command   := mcVolSlide;
                            Parameter := (Parameter - $60) SHL 4;
                          END
                        ELSE IF Parameter < $80 THEN
                          BEGIN
                            Command   := mcVolFineUp;
                            Parameter := Parameter - $70;
                          END
                      END;
                ELSE  Command := mcNone;
              END;

              IF b1 = 0 THEN
                BEGIN
                  Period     := 0;
                  Instrument := 0;
                END
              ELSE
                BEGIN
                  Period     := FreqTable[b1-1];
                  Instrument := b2 + 1;
                END;

              IF ((Command = mcEndPattern) OR (Command = mcJumpPattern)) AND
                 (Pattern^.Patt^.NNotes > i + 1) THEN
                Pattern^.Patt^.NNotes := i + 1;
            END;

        Track := Song^.GetTrack(OktTrackCount);
        IF Track = NIL THEN
          BEGIN
            Song^.Status := msOutOfMemory;
            EXIT;
          END;

        Track^.SetFullTrack(FullTrack);

        Pattern^.Patt^.Channels[j] := OktTrackCount;

        INC(OktTrackCount);
      END;

    INC(OktPBODCount);
    OktProcPBOD := TRUE;
  END;


FUNCTION TOktFile.OktProcSBOD(VAR St: TStream; Size: LONGINT) : BOOLEAN;
  VAR
    Instrument  : TInstrumentRec;
    Instr       : PInstrument;
  BEGIN
    OktProcSBOD := FALSE;

    WHILE (OktSBODCount <= 256) AND
          ((Song^.GetInstrument(OktSBODCount)^.Instr      = NIL)  OR
           (Song^.GetInstrument(OktSBODCount)^.Instr^.Len = 0)  ) DO
      INC(OktSBODCount);

    Instr := Song^.GetInstrument(OktSBODCount);
    IF Instr^.Instr = NIL THEN EXIT;

    Move(Instr^.Instr^, Instrument, SizeOf(Instrument));

    Instrument.Len := Size;
    GetMem(Instrument.Data, Size);
    St.Read(Instrument.Data^, Size);

    Instr^.Change(@Instrument);

    INC(OktSBODCount);
    OktProcSBOD := TRUE;
  END;




FUNCTION TOktFile.DoBlock(VAR St: TStream;
                          Id: TIffBlockIdent; Size: LONGINT) : BOOLEAN; 
  BEGIN
    DoBlock := FALSE;

    IF      (Id = 'CMOD') AND NOT OktProcCMOD(St, Size) THEN EXIT
    ELSE IF (Id = 'SAMP') AND NOT OktProcSAMP(St, Size) THEN EXIT
    ELSE IF (Id = 'SPEE') AND NOT OktProcSPEE(St, Size) THEN EXIT
    ELSE IF (Id = 'SLEN') AND NOT OktProcSLEN(St, Size) THEN EXIT
    ELSE IF (Id = 'PLEN') AND NOT OktProcPLEN(St, Size) THEN EXIT
    ELSE IF (Id = 'PATT') AND NOT OktProcPATT(St, Size) THEN EXIT
    ELSE IF (Id = 'PBOD') AND NOT OktProcPBOD(St, Size) THEN EXIT
    ELSE IF (Id = 'SBOD') AND NOT OktProcSBOD(St, Size) THEN EXIT;

    DoBlock := TRUE;
  END;




CONSTRUCTOR TOktFile.Init(VAR MySong: TSong);
  BEGIN
    TIffFile.Init;

    OktPBODCount   := 1;
    OktSBODCount   := 1;
    OktTrackCount  := 1;
    OktMaxChannels := 0;

    MySong.SetName(MySong.FileName);
    MySong.InitialTempo := 6;
    MySong.InitialBPM   := 125;
    MySong.Volume       := 255;
    MySong.NumChannels  := 8;

    Song := @MySong;
  END;




DESTRUCTOR TOktFile.Done;
  BEGIN
    Song^.NumChannels := OktMaxChannels;
    TIffFile.Done;
  END;




PROCEDURE LoadOktFileFormat (VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);
  VAR
    f : TOktFile;
    ModOkt : TModOktIdString ABSOLUTE Header;
  BEGIN
    Song.FileFormat := mffOktalizer;

    IF ModOkt <> ModOktIdString THEN
      BEGIN
        Song.Status := msNotLoaded;
        EXIT;
      END;

    Song.Status := msFileDamaged;

    St.Seek(St.GetPos + SizeOf(TModOktIdString));

    f.Init(Song);
    f.Parse(St);
    f.Done;

    IF Song.Status = msFileDamaged THEN
      Song.Status := msOk;
  END;




END.
