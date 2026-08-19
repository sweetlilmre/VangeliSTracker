{****************************************************************************}
{                                                                            }
{ MODULE:         SwapStream                                                 }
{                                                                            }
{ DESCRIPTION:    This UNIT implements a multi-stream Turbo Vision Stream.   }
{                 TSwapStream is a stream that is constructed out of several }
{                 other streams. It's primery and intended use consists in   }
{                 providing a large platform for the swap-manager found in   }
{                 the SwapManager UNIT.                                      }
{                                                                            }
{                 By default, this stream maps onto EMS and all hard drives  }
{                 available, beginning with the TMP, TEMP and TMPDIR         }
{                 environment variables, following with all drives from C:   }
{                 to Z:, and finally the current drive. If a different       }
{                 mapping is required, the InitStreams method should be      }
{                 derived.                                                   }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        17-Jan-1993 Definition and implementation.                 }
{                                                                            }
{ (C) 1993 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT SwapStream;

{$I-}

INTERFACE

USES Dos, Objects, FileUtil, HexConversions;




{ Configuration. }

CONST
  SwapUseEms   : BOOLEAN   = TRUE;
  SwapQuanto   : WORD      = 4096;
  SwapFName    : STRING[6] = 'VTSWAP';
  SwapPrimPath : PathStr   = '';




{ New TDosStream. Stores the filename. }

TYPE
  PMyDosStream = ^TMyDosStream;
  TMyDosStream =
    OBJECT(TDosStream)
      FName : PathStr;

      CONSTRUCTOR Init(FileName: FNameStr; Mode: WORD);
    END;




{ New TEmsStream. Fixes a bug in Truncate. }

TYPE
  PMyEmsStream = ^TMyEmsStream;
  TMyEmsStream =
    OBJECT(TEmsStream)
      MinSize : LONGINT;

      CONSTRUCTOR Init(AMinSize, AMaxSize : LONGINT);
      PROCEDURE   Truncate;                         VIRTUAL;
    END;




{ TSwapStream. Stream that maps onto a collection of streams. }

TYPE
  PSwapStream = ^TSwapStream;
  TSwapStream =
    OBJECT(TStream)
      StreamColl    : TCollection;
      CurrentStream : INTEGER;
      LastStream    : INTEGER;


      CONSTRUCTOR Init;
      DESTRUCTOR  Done; VIRTUAL;
      PROCEDURE   InsertPath(p: PathStr);                 VIRTUAL;
      PROCEDURE   InitStreams;                            VIRTUAL;

      FUNCTION  GetPos                         : LONGINT; VIRTUAL;
      FUNCTION  GetSize                        : LONGINT; VIRTUAL;
      PROCEDURE Seek    (SPos: LONGINT);                  VIRTUAL;
      PROCEDURE Truncate;                                 VIRTUAL;
      PROCEDURE Reset;                                    VIRTUAL;
      PROCEDURE Read    (VAR Buf; Count: WORD);           VIRTUAL;
      PROCEDURE Write   (VAR Buf; Count: WORD);           VIRTUAL;
    END;




IMPLEMENTATION




{----------------------------------------------------------------------------}
{ Utility function. Shouldn't belong here. :-(                               }
{____________________________________________________________________________}

PROCEDURE IncPtr(VAR p: POINTER; Count: WORD);
  BEGIN
    p := Ptr(Seg(p^), Ofs(P^) + Count);
  END;




{----------------------------------------------------------------------------}
{ TMyDosStream.                                                              }
{____________________________________________________________________________}

CONSTRUCTOR TMyDosStream.Init(FileName: FNameStr; Mode: WORD);
  BEGIN
    TDosStream.Init(FileName, Mode);
    FName := FileName;
  END;




{----------------------------------------------------------------------------}
{ TMyEmsStream.                                                              }
{____________________________________________________________________________}

CONSTRUCTOR TMyEmsStream.Init(AMinSize, AMaxSize : LONGINT);
  BEGIN
    TEmsStream.Init(AMinSize, AMaxSize);
    MinSize := AMinSize;
  END;


PROCEDURE TMyEmsStream.Truncate;                         
  VAR
    TPos : LONGINT;
  BEGIN
    IF Status = stOk THEN
      BEGIN
        TPos := GetPos;
        IF TPos < MinSize THEN
          BEGIN
            Seek(MinSize);
            TEmsStream.Truncate;
            Seek(TPos);
            Size := TPos;
          END
        ELSE
          TEmsStream.Truncate;
      END;
  END;




{----------------------------------------------------------------------------}
{ TSwapStream.                                                               }
{____________________________________________________________________________}

CONSTRUCTOR TSwapStream.Init;
  BEGIN
    TStream.Init;
    StreamColl.Init(3, 2);

    InitStreams;

    IF StreamColl.Count = 0 THEN
      Error(stInitError, 0);

    CurrentStream := 0;
    LastStream    := 0;
  END;


PROCEDURE TSwapStream.InitStreams;
  VAR
    Str     : PStream;
    MyPath  : PathStr;
    MyDrive : CHAR;
    ch      : CHAR;
  BEGIN
    MyPath := ParamStr(0);
    IF (Length(MyPath) >= 2) AND (MyPath[2] = ':') THEN
      MyDrive := UpCase(MyPath[1])
    ELSE
      MyDrive := #0;

    IF SwapUseEms THEN
      BEGIN
        Str := New(PMyEmsStream, Init(16384, $7FFFFFFF));
        IF Str^.Status <> stOk THEN
          Dispose(Str, Done)
        ELSE
          StreamColl.Insert(Str);
      END;

    IF SwapPrimPath <> '' THEN
      InsertPath(SwapPrimPath);

    InsertPath(GetEnv('TMP'));
    InsertPath(GetEnv('TEMP'));
    InsertPath(GetEnv('TMPDIR'));
    InsertPath(GetEnv('TEMPDIR'));

    FOR ch := 'C' TO 'Z' DO
      IF ch <> MyDrive THEN
        InsertPath(ch+':\');

    IF MyDrive > 'C' THEN
      InsertPath(MyDrive+':\');
  END;


PROCEDURE TSwapStream.InsertPath(p: PathStr);
  VAR
    d   : DirStr;
    i   : WORD;
    r   : WORD;
    fil : FILE;
    Str : PStream;
  BEGIN
    KillBar2Path(p);
    p := FExpand(p);

    FOR i := 1 TO StreamColl.Count DO
      BEGIN
        Str := PStream(StreamColl.At(i-1));
        IF (TypeOf(Str^) = TypeOf(TMyDosStream))                AND
           (UpCase(PMyDosStream(Str)^.FName[1]) = UpCase(p[1])) THEN
          EXIT;
      END;

    MakePath(p);
    AddBar2Path(p);
    d := p;
    i := 0;
    REPEAT

      p := d + SwapFName + HexByte(i)+'.$$$';
      Assign(fil, p);
      Erase(fil);
      r := IOResult;
      INC(i);

    UNTIL NOT FileExists(p);

    Str := New(PMyDosStream, Init(p, stCreate));

    IF Str^.Status <> stOk THEN
      Dispose(Str, Done)
    ELSE
      StreamColl.Insert(Str);
  END;


DESTRUCTOR TSwapStream.Done; 

  PROCEDURE DeleteStream(Str: PStream); FAR;
    VAR
      f : File;
    BEGIN
      Str^.Seek(0);
      Str^.Truncate;  { It's faster this way 8-O (DOS-Specific, of course) }

      IF TypeOf(Str^) = TypeOf(TMyDosStream) THEN
        BEGIN
          Assign(f, PMyDosStream(Str)^.FName);
          Dispose(Str, Done);
          Erase(f);
        END
      ELSE
        Dispose(Str, Done);
    END;

  BEGIN { Done }
    StreamColl.ForEach(@DeleteStream);
    TStream.Done;
  END;


FUNCTION TSwapStream.GetPos : LONGINT; 
  VAR
    i   : INTEGER;
    Pos : LONGINT;
  BEGIN
    GetPos := -1;

    IF Status <> stOk THEN EXIT;
    Reset;

    Pos := 0;
    FOR i := 0 TO CurrentStream - 1 DO
      BEGIN
        INC(Pos, PStream(StreamColl.At(i))^.GetSize);
      END;

    INC(Pos, PStream(StreamColl.At(CurrentStream))^.GetPos);

    GetPos := Pos;
  END;


FUNCTION TSwapStream.GetSize : LONGINT; 
  VAR
    i    : INTEGER;
    Size : LONGINT;
  BEGIN
    GetSize := -1;

    IF Status <> stOk THEN EXIT;
    Reset;

    Size := 0;
    FOR i := 0 TO LastStream DO
      BEGIN
        INC(Size, PStream(StreamColl.At(i))^.GetSize);
      END;

    GetSize := Size;
  END;


PROCEDURE TSwapStream.Seek (SPos: LONGINT);
  VAR
    Junk : BYTE ABSOLUTE 0:0;
    Pos  : LONGINT;
    Last : LONGINT;
    Size : LONGINT;
    i    : INTEGER;
  BEGIN
    IF Status <> stOk THEN EXIT;
    Reset;

    Size := GetSize;
    IF Size >= SPos THEN
      BEGIN

        Pos  := 0;
        Last := 0;
        i    := 0;
        WHILE (i <= LastStream) AND (Pos < SPos) DO
          BEGIN
            Last := PStream(StreamColl.At(i))^.GetSize;
            IF Pos + Last < SPos THEN
              BEGIN
                INC(i);
                INC(Pos, Last);
              END
            ELSE
              BEGIN
                Last := SPos - Pos;
                Pos  := SPos;
              END;
          END;

        CurrentStream := i;
        PStream(StreamColl.At(i))^.Seek(Last);

        IF PStream(StreamColl.At(i))^.Status <> stOk THEN
          BEGIN
            Error(PStream(StreamColl.At(i))^.Status, i);
            EXIT;
          END;

      END
    ELSE
      BEGIN
        Pos := SPos - Size;
        Seek(Size);
        IF Status <> stOk THEN EXIT;

        FOR Last := 1 TO Pos DIV 32768 DO
          BEGIN
            Write(Junk, 32768);
            IF Status <> stOk THEN EXIT;
          END;

        IF (Pos MOD 32768) > 0 THEN 
          Write(Junk, Pos MOD 32768);

        IF Status <> stOk THEN EXIT;
      END;
  END;


PROCEDURE TSwapStream.Truncate;                              
  VAR
    i : INTEGER;
  BEGIN
    IF Status <> stOk THEN EXIT;
    Reset;

    FOR i := LastStream DOWNTO CurrentStream + 1 DO
      BEGIN
        PStream(StreamColl.At(i))^.Seek(0);
        PStream(StreamColl.At(i))^.Truncate;

        IF PStream(StreamColl.At(i))^.Status <> stOk THEN
          BEGIN
            LastStream := CurrentStream;
            Error(PStream(StreamColl.At(i))^.Status, i);
            EXIT;
          END;

      END;

    PStream(StreamColl.At(CurrentStream))^.Truncate;

    IF PStream(StreamColl.At(CurrentStream))^.Status <> stOk THEN
      Error(PStream(StreamColl.At(CurrentStream))^.Status, CurrentStream);

    LastStream := CurrentStream;
  END;


PROCEDURE TSwapStream.Reset;
  VAR
    i : INTEGER;
  BEGIN
    FOR i := 0 TO StreamColl.Count - 1 DO
      PStream(StreamColl.At(i))^.Reset;

    TStream.Reset;
  END;


PROCEDURE TSwapStream.Read (VAR Buf; Count: WORD);
  VAR
    p : POINTER;
    c : LONGINT;
  BEGIN
    IF Status <> stOk THEN EXIT;
    Reset;

    p := @Buf;
    WHILE (Count > 0) AND (Status = stOk) DO
      BEGIN

        c := 0;
        WHILE c = 0 DO
          BEGIN

            c := PStream(StreamColl.At(CurrentStream))^.GetSize;
            c := c -
                 PStream(StreamColl.At(CurrentStream))^.GetPos;

            IF c = 0 THEN
              BEGIN
                INC(CurrentStream);
                IF CurrentStream > LastStream THEN
                  BEGIN
                    Error(stReadError, CurrentStream);
                    DEC(CurrentStream);
                    EXIT;
                  END
                ELSE
                  PStream(StreamColl.At(CurrentStream))^.Seek(0);
              END;

          END;

        IF c > Count THEN c := Count;

        PStream(StreamColl.At(CurrentStream))^.Read(p^, c);

        IF PStream(StreamColl.At(CurrentStream))^.Status <> stOk THEN
          BEGIN
            Error(PStream(StreamColl.At(CurrentStream))^.Status, CurrentStream);
            EXIT;
          END;

        DEC(Count, c);
        IncPtr(p, c);

      END;
  END;


PROCEDURE TSwapStream.Write (VAR Buf; Count: WORD);
  VAR
    p : POINTER;
    c : LONGINT;
    Pos  : LONGINT;
    Size : LONGINT;
    PleaseQuanto : BOOLEAN;
  BEGIN
    IF Status <> stOk THEN EXIT;

    Reset;

    p            := @Buf;
    PleaseQuanto := FALSE;

    WHILE (Count > 0) AND (Status = stOk) DO
      BEGIN

        c := 0;
        WHILE c = 0 DO
          BEGIN

            c := PStream(StreamColl.At(CurrentStream))^.GetSize -
                 PStream(StreamColl.At(CurrentStream))^.GetPos;

            IF c = 0 THEN
              BEGIN
                IF CurrentStream = LastStream THEN
                  BEGIN
                    IF PleaseQuanto THEN
                      c := SwapQuanto
                    ELSE
                      c := Count;
                  END
                ELSE
                  BEGIN
                    INC(CurrentStream);
                    PStream(StreamColl.At(CurrentStream))^.Seek(0);
                  END;
              END;

          END;

        IF c > Count THEN c := Count;

        Pos  := PStream(StreamColl.At(CurrentStream))^.GetPos;
        Size := PStream(StreamColl.At(CurrentStream))^.GetSize;

        PStream(StreamColl.At(CurrentStream))^.Write(p^, c);

        IF PStream(StreamColl.At(CurrentStream))^.Status <> stOk THEN
          BEGIN
            PStream(StreamColl.At(CurrentStream))^.Reset;
            PStream(StreamColl.At(CurrentStream))^.Seek(Size);
            PStream(StreamColl.At(CurrentStream))^.Reset;
            PStream(StreamColl.At(CurrentStream))^.Truncate;
            PStream(StreamColl.At(CurrentStream))^.Reset;
            PStream(StreamColl.At(CurrentStream))^.Seek(Pos);
            PStream(StreamColl.At(CurrentStream))^.Reset;
            IF NOT PleaseQuanto THEN
              BEGIN
                PleaseQuanto := TRUE;
                Reset;
                c := 0;
              END
            ELSE
              BEGIN
                PleaseQuanto := FALSE;
                INC(LastStream);
                IF LastStream < StreamColl.Count THEN
                  BEGIN
                    Reset;
                    c := 0;
                  END
                ELSE
                  BEGIN
                    Error(PStream(StreamColl.At(CurrentStream))^.Status, CurrentStream);
                    EXIT;
                  END;
              END;
          END;

        DEC(Count, c);
        IncPtr(p, c);

      END;
  END;




END.
