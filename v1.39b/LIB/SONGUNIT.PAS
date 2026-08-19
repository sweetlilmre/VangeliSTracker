{****************************************************************************}
{                                                                            }
{ MODULE:        SongUnit                                                    }
{                                                                            }
{ DESCRIPTION:   Gives the necessary support for handling the different      }
{                data types and different file formats of a song. Also, it   }
{                implements the base routines for loading the song from many }
{                different file formats and (future) saving them to disk.    }
{                                                                            }
{ AUTHOR:        Juan Carlos Ar‚valo Baeza                                   }
{                                                                            }
{ MODIFICATIONS: Nobody (yet).                                               }
{                                                                            }
{ HISTORY:       xx-May-1992 First implementations (lost in the memory of    }
{                            time O:-).                                      }
{                xx-Jun-1992 Lots of improvements (ditto O;-).               }
{                11-Jul-1992 Started first documented version.               }
{                21-Oct-1992 Rechecking. First remodeling.                   }
{                25-Jan-1993 Created the .OKT and .WOW loader.               }
{                06-Feb-1993 Remodelling. Made the memory-optimized, object- }
{                            oriented interface. Name change from ModUnit.   }
{                                                                            }
{ (C) 1992, 1993 VangeliSTeam                                                }
{____________________________________________________________________________}

UNIT SongUnit;

INTERFACE

USES Dos, Objects,
     HexConversions,
     SongElements;




{----------------------------------------------------------------------------}
{ Song object definition.                                                    }
{____________________________________________________________________________}

TYPE
  TSongFileFormat =
    (
      mffUnknown      ,    { Unknown format O:-)                      }
      mffMod31M_K_    ,    { Protracker "M.K.".                       }
      mffMod31FLT4    ,    { Protracker "FLT4".                       }
      mffMod15        ,    { SoundTracker 15-instrument module.       }
      mffJMPlayer     ,    { JMPlayer module.                         }
      mffOktalizer    ,    { 8 voices Oktalizer MOD.           (.OKT) }
      mffComposer669  ,    { 8 voices Composer-669.            (.669) }
      mffWow8         ,    { 8 voices Grave.                   (.WOW) }
      mffFastTracker  ,    { 6 or 8 voices Triton FastTracker. (.MOD) }
      mffS3m          ,    { ScreamTracker 3.0                 (.S3M) }
      mffS2m          ,    { ScreamTracker 3.0 (beta)          (.S2M) }
      mffStm               { ScreamTracker 2.x                 (.STM) }
    );

  TSongStatus =
    (
      { Non fatal states }

      msNotLoaded              ,    { Not yet loaded                                         }
      msOK                     ,    { Everything was Ok.                                     }
      msFileTooShort           ,    { End of file premature (lot's of modules have this).    }

      { Fatal states }

      msFileOpenError          ,    { Could not open the .MOD file.                          }
      msOutOfMemory            ,    { There is not enough memory left. :-( Shouldn't happen. }
      msFileDamaged            ,    { Syntax checking error on module file.                  }
      msFileFormatNotSupported      { JMPlayer or ScreamTracker, for example.                }
    );


TYPE
  TPanPositions = ARRAY[1..32] OF BYTE;

  PSong = ^TSong;
  TSong =
    OBJECT(TObject)

      { Desired data }

      SongStart             : WORD;
      SongLen               : WORD;

      { General song data }

      Name                  : PString;
      InsidePath            : PString;
      Comment               : PSongComment;
      FileDir               : PString;
      FileName              : NameStr;
      FileExt               : ExtStr;
      FirstTick             : BOOLEAN;
      InitialTempo          : BYTE;
      InitialBPM            : BYTE;
      Volume                : BYTE;
      NumChannels           : BYTE;
      PanPositions          : TPanPositions;

      { Instrument data }

      Instruments           : TCollection;

      { Pattern sequence data }

      SequenceLength        : WORD;
      SequenceRepStart      : WORD;
      PatternSequence       : PPatternSequence;
      PatternTempos         : PPatternSequence;

      Patterns              : TCollection;

      { Track data }

      Tracks                : TCollection;

      { State data }

      Status                : TSongStatus;
      ErrorCode             : WORD;
      ThereIsMore           : BOOLEAN;
      FileFormat            : TSongFileFormat;



      { Methods }

      CONSTRUCTOR Init;
      DESTRUCTOR  Done; VIRTUAL;

      PROCEDURE Load(VAR St: TStream);
      PROCEDURE Save(VAR St: TStream);

      PROCEDURE LoadFName(FName: PathStr);
      PROCEDURE SaveFName(FName: PathStr);

      PROCEDURE Free;
      PROCEDURE InitValues;
      PROCEDURE Empty;

      FUNCTION  GetErrorString                            : STRING;

      FUNCTION  GetName                                   : STRING;
      FUNCTION  GetInsidePath                             : STRING;
      FUNCTION  GetInstrument      (i: WORD)              : PInstrument;
      FUNCTION  GetTrack           (i: WORD)              : PTrack;
      FUNCTION  GetPattern         (i: WORD)              : PPattern;
      FUNCTION  GetPatternSeq      (i: WORD)              : PPattern;
      FUNCTION  GetPatternSequence (Seq: WORD)            : WORD;
      FUNCTION  GetPatternTempo    (Seq: WORD)            : WORD;
      PROCEDURE GetNote            (Seq, Row, Chan: WORD; VAR Note: TFullNote);

      PROCEDURE SetName            (S: STRING);
      PROCEDURE SetInsidePath      (S: STRING);
    END;




{----------------------------------------------------------------------------}
{ Header definition for the loaders.                                         }
{____________________________________________________________________________}

TYPE
  PSongHeader = ^TSongHeader;
  TSongHeader = ARRAY[0..2047] OF BYTE;


CONST
  ModOffset : LONGINT = 0;



IMPLEMENTATION

USES SongUtils,
     UnkLoader, ModLoader, OktLoader, S3mLoader, StmLoader, Loader669, ExeLoader,
     Heaps,
     StrConst, AsciiZ, Filters;




{----------------------------------------------------------------------------}
{ Loaders definition.                                                        }
{____________________________________________________________________________}

TYPE
  TSongLoader = PROCEDURE (VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);

CONST
  NumLoaders = 8;

  SongLoaders : ARRAY[1..NumLoaders] OF TSongLoader =
    (
      LoadJMFileFormat,
      Load669FileFormat,
      LoadOktFileFormat,
      LoadS2mFileFormat,
      LoadS3mFileFormat,
      LoadStmFileFormat,
      LoadExeFileFormat,
      LoadModFileFormat
    );




{----------------------------------------------------------------------------}
{ TSong object.                                                              }
{____________________________________________________________________________}

CONSTRUCTOR TSong.Init;
  BEGIN
    TObject.Init;
    InitValues;
  END;


DESTRUCTOR  TSong.Done; 
  BEGIN
    Free;
    TObject.Done;
  END;


PROCEDURE TSong.Load(VAR St: TStream);
  VAR
    Header : TSongHeader;
    i      : WORD;
    Pos    : LONGINT;
  BEGIN
    Pos := St.GetPos;

    ThereIsMore := FALSE;

    St.Read(Header, SIZEOF(TSongHeader));

    IF St.Status <> stOk THEN
      BEGIN
        Status    := msFileDamaged;
        ErrorCode := St.ErrorInfo;
        St.Done;
        EXIT;
      END;

    i := 1;
    WHILE (i     <= NumLoaders)  AND
          (Status = msNotLoaded) DO
      BEGIN
        St.Seek(Pos);
        SongLoaders[i](PSong(@Self)^, St, Header);
        INC(i);
      END;
  END;


PROCEDURE TSong.LoadFName(FName: PathStr);
  VAR
    St         : TDosStream;
    Dir        : DirStr;
    IPath      : STRING[12];
    OSongStart : WORD;
    OSongLen   : WORD;
  BEGIN
    OSongStart := SongStart;
    OSongLen   := SongLen;
    IPath := GetInsidePath;
    Empty;
    SetInsidePath(IPath);
    SongStart := OSongStart;
    SongLen   := OSongLen;

    FName := FExpand(FName);
    FSplit(FName, Dir, FileName, FileExt);
    FileDir := FullHeap.HNewStr(Dir);
    IF FileExt = '' THEN FileExt := '.MOD';
    FName := Dir+FileName+FileExt;

    St.Init(FName, stOpenRead);
    St.Seek(ModOffset);

    IF St.Status <> stOk THEN
      BEGIN
        Status    := msFileOpenError;
        ErrorCode := St.ErrorInfo;
        St.Done;
        EXIT;
      END;

    Status    := msNotLoaded;
    ErrorCode := 0;

    Load(St);

    IF Status <> msOk THEN
      ErrorCode := St.ErrorInfo;

    St.Done;
  END;


PROCEDURE TSong.Save(VAR St: TStream);
  BEGIN
  END;


PROCEDURE TSong.SaveFName(FName: PathStr);
  BEGIN
  END;


FUNCTION TSong.GetErrorString : STRING;
  BEGIN
    CASE Status OF
      msFileOpenError:          GetErrorString := GetString(StrFileOpenError);
      msOutOfMemory:            GetErrorString := GetString(StrOutOfMemory);
      msFileDamaged:            GetErrorString := GetString(StrFileDamaged);
      msFileTooShort:           GetErrorString := GetString(StrFileTooShort);
      msFileFormatNotSupported: GetErrorString := GetString(StrFileFormatNotSupported) +
                                                  GetString(StrFileFormats + BYTE(FileFormat));
      ELSE                      GetErrorString := '';
    END;
  END;


FUNCTION TSong.GetName : STRING;
  BEGIN
    IF Name <> NIL THEN
      GetName := Name^
    ELSE
      GetName := '';
  END;


PROCEDURE TSong.SetName(S: STRING);
  BEGIN
    IF Name <> NIL THEN
      FullHeap.HDisposeStr(Name);

    IF S <> '' THEN
      Name := FullHeap.HNewStr(S);
  END;


FUNCTION TSong.GetInsidePath : STRING;
  BEGIN
    IF InsidePath <> NIL THEN
      GetInsidePath := InsidePath^
    ELSE
      GetInsidePath := '';
  END;


PROCEDURE TSong.SetInsidePath(S: STRING);
  BEGIN
    IF InsidePath <> NIL THEN
      FullHeap.HDisposeStr(InsidePath);

    IF S <> '' THEN
      InsidePath := FullHeap.HNewStr(S);
  END;


FUNCTION TSong.GetInstrument(i: WORD) : PInstrument;
  VAR
    Instrument : PInstrument;
    j          : WORD;
  LABEL
    Break;
  BEGIN
    IF i >= Instruments.Count THEN
      BEGIN
        FOR j := Instruments.Count TO i DO
          BEGIN
            Heap.HGetMem(POINTER(Instrument), SizeOf(TInstrument));
            IF Instrument <> NIL THEN
              BEGIN
                Instrument^.Init;
                Instruments.AtInsert(j, Instrument);
              END
            ELSE
              GOTO Break;
          END;
Break:
        GetInstrument := Instrument;
      END
    ELSE
      GetInstrument := PInstrument(Instruments.At(i));
  END;


FUNCTION TSong.GetTrack(i: WORD) : PTrack;
  VAR
    Track : PTrack;
    j     : WORD;
  LABEL
    Break;
  BEGIN
    IF i >= Tracks.Count THEN
      BEGIN
        FOR j := Tracks.Count TO i DO
          BEGIN
            Heap.HGetMem(POINTER(Track), SizeOf(TTrack));
            IF Track <> NIL THEN
              BEGIN
                Track^.Init;
                Tracks.AtInsert(j, Track);
              END
            ELSE
              GOTO Break;
          END;
Break:
        GetTrack := Track;
      END
    ELSE
      GetTrack := PTrack(Tracks.At(i));
  END;


FUNCTION TSong.GetPattern(i: WORD) : PPattern;
  VAR
    Pattern : PPattern;
    j       : WORD;
  LABEL
    Break;
  BEGIN
    IF i >= Patterns.Count THEN
      BEGIN
        FOR j := Patterns.Count TO i DO
          BEGIN
            Heap.HGetMem(POINTER(Pattern), SizeOf(TPattern));
            IF Pattern <> NIL THEN
              BEGIN
                Pattern^.Init(NumChannels);
                Patterns.AtInsert(j, Pattern);
              END
            ELSE
              GOTO Break;
          END;
Break:
        GetPattern := Pattern;
      END
    ELSE
      GetPattern := PPattern(Patterns.At(i));
  END;


FUNCTION TSong.GetPatternSeq(i: WORD) : PPattern;
  BEGIN
    GetPatternSeq := GetPattern(GetPatternSequence(i));
  END;


FUNCTION TSong.GetPatternSequence(Seq: WORD) : WORD;
  BEGIN
    IF PatternSequence <> NIL THEN
      GetPatternSequence := PatternSequence^[WORD(Seq)]
    ELSE
      GetPatternSequence := 0;
  END;


FUNCTION TSong.GetPatternTempo(Seq: WORD) : WORD;
  BEGIN
    IF PatternTempos <> NIL THEN
      GetPatternTempo := PatternTempos^[WORD(Seq)]
    ELSE
      GetPatternTempo := 0;
  END;


PROCEDURE TSong.GetNote(Seq, Row, Chan: WORD; VAR Note: TFullNote);
  VAR
    Patt  : PPattern;
    Track : PTrack;
    n     : WORD;
    NOffs : WORD;
  BEGIN
    IF PatternSequence <> NIL THEN
      BEGIN
        Patt := GetPatternSeq(Seq);
        IF Patt <> NIL THEN
          BEGIN
            n     := Patt^.Patt^.Channels[Chan];
            Track := GetTrack(n);
            IF Track <> NIL THEN
              BEGIN
                Track^.GetNote(Row, Note);
                EXIT;
              END
          END
      END;

    FillChar(Note, SizeOf(Note), 0);
  END;


PROCEDURE TSong.Free;
  VAR
    i : WORD;
  BEGIN
    ASM CLI END;

    FullHeap.HDisposeStr(Name);
    FullHeap.HFreeMem   (POINTER(Comment), SizeOf(Comment^));
    FullHeap.HDisposeStr(FileDir);

    Instruments.Done;

    FullHeap.HFreeMem(POINTER(PatternSequence), SizeOf(PatternSequence^));
    FullHeap.HFreeMem(POINTER(PatternTempos),   SizeOf(PatternTempos^));
    Patterns.Done;

    Tracks.Done;

    ASM STI END;
  END;



PROCEDURE TSong.InitValues;
  CONST
    DefPan : TPanPositions = ( $40, $B0, $B0, $40, $40, $B0, $B0, $40,
                               $40, $B0, $B0, $40, $40, $B0, $B0, $40,
                               $40, $B0, $B0, $40, $40, $B0, $B0, $40,
                               $40, $B0, $B0, $40, $40, $B0, $B0, $40 );
  BEGIN
    SongStart    := 1;
    SongLen      := MaxSequence;

    Name         := NIL;
    InsidePath   := NIL;
    Comment      := NIL;
    FileDir      := NIL;
    FileName     := '';
    FileExt      := '';
    FirstTick    := FALSE;
    InitialTempo := 1;
    InitialBPM   := 1;
    Volume       := 0;
    NumChannels  := 0;

    Instruments.Init(32, 32);

    SequenceLength   := 0;
    SequenceRepStart := 0;

    FullHeap.HGetMem(POINTER(PatternSequence), SizeOf(PatternSequence^));
    FullHeap.HGetMem(POINTER(PatternTempos),   SizeOf(PatternTempos^));
    IF PatternSequence <> NIL THEN
      FillChar(PatternSequence^, SizeOf(PatternSequence^), 0);
    IF PatternTempos <> NIL THEN
      FillChar(PatternTempos^, SizeOf(PatternTempos^), 0);
    Patterns.Init(64, 64);

    Tracks.Init(256, 256);

    Status      := msNotLoaded;
    ErrorCode   := 0;
    ThereIsMore := FALSE;
    FileFormat  := mffUnknown;

    PanPositions := DefPan;
  END;




PROCEDURE TSong.Empty;
  BEGIN
    Free;
    InitValues;
  END;




END.
