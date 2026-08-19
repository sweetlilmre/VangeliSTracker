{****************************************************************************}
{                                                                            }
{ MODULE:         SwapManager                                                }
{                                                                            }
{ DESCRIPTION:    This UNIT implements a swapping manager. The Swapping is   }
{                 made to a Turbo Vision Stream. Any stream can be used, but }
{                 it's recommended to use the TSwapStream found in the       }
{                 SwapStream UNIT.                                           }
{                                                                            }
{                 The manager works much like a dynamic memory manager, but  }
{                 uses handles instead of pointers. Handles MUST be          }
{                 initialized by calling the Init constructor, and           }
{                 uninitialized by calling the Done destructor. The handle   }
{                 methods provide access to all the swapping services.       }
{                                                                            }
{                 The recommended method of usage is the following:          }
{                                                                            }
{                 (* ---------------------------------------------------- *) }
{                                                                            }
{                 VAR                                                        }
{                   Handle : TSwapHandle;                                    }
{                                                                            }
{                 ...                                                        }
{                                                                            }
{                 Handle.Init;                (* Initialize Handle *)        }
{                                                                            }
{                 ...                                                        }
{                                                                            }
{                 Handle.Write(Buffer, Size); (* Save buffer in swap stream*)}
{                                                                            }
{                 ...                                                        }
{                                                                            }
{                 Handle.Read(Buffer, Size);  (* Retrieve saved buffer *)    }
{                 Handle.Free;                (* If not needed any more *)   }
{                 ...                                                        }
{                                                                            }
{                 Handle.Done;                (* Uninitialize Handle *)      }
{                                                                            }
{                 (* ---------------------------------------------------- *) }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        17-Jan-1993 Definition and implementation.                 }
{                             Including cleanup methods.                     }
{                                                                            }
{ (C) 1993 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT SwapManager;

INTERFACE

USES Objects;




{ Cleanup action needed. }

TYPE
  TClAction = (cluNone, cluFast, cluFull);




{ TSwapHandle object. }

TYPE
  PSwapHandle = ^TSwapHandle;
  TSwapHandle =
    OBJECT
      Pos    : LONGINT;
      Size   : WORD;
      Status : WORD;
      Next   : PSwapHandle;
      Prev   : PSwapHandle;

      CONSTRUCTOR Init;
      DESTRUCTOR  Done;                                     VIRTUAL;
      PROCEDURE   Error ( AStatus: WORD );                  VIRTUAL;

      FUNCTION  Write ( VAR Buf; ASize: WORD ) : BOOLEAN;   VIRTUAL;
      FUNCTION  Read  ( VAR Buf; ASize: WORD ) : BOOLEAN;   VIRTUAL;
      PROCEDURE Free;                                       VIRTUAL;

      PROCEDURE Link;                                       VIRTUAL;
      PROCEDURE Unlink;                                     VIRTUAL;
      PROCEDURE MoveFrom   (OPos: LONGINT);                 VIRTUAL;
      FUNCTION  NeedCleanup                : TClAction;     VIRTUAL;
      PROCEDURE FastCleanup;                                VIRTUAL;
      PROCEDURE FullCleanup;                                VIRTUAL;
      PROCEDURE Shrink;                                     VIRTUAL;

      FUNCTION UsedMem   : LONGINT;                         VIRTUAL;
      FUNCTION UnusedMem : LONGINT;                         VIRTUAL;
      FUNCTION TotalSize : LONGINT;                         VIRTUAL;
    END;




{ Swapper initialization and uninitialization. }

FUNCTION  InitSwapManager(St: PStream) : BOOLEAN;
PROCEDURE DoneSwapManager;




IMPLEMENTATION

USES Heaps;





{----------------------------------------------------------------------------}
{ Swapper variables.                                                         }
{____________________________________________________________________________}

CONST
  HandleListHead : PSwapHandle = NIL;
  HandleListTail : PSwapHandle = NIL;

  SwapFile      : PStream = NIL;
  SwapFileValid : BOOLEAN = FALSE;




{----------------------------------------------------------------------------}
{ Initialization and uninitialization routine.                               }
{____________________________________________________________________________}

FUNCTION InitSwapManager(St: PStream) : BOOLEAN;
  BEGIN
    IF SwapFile <> NIL THEN
      DoneSwapManager;

    HandleListHead := NIL;
    HandleListTail := NIL;

    SwapFile := St;

    SwapFileValid   := (SwapFile <> NIL) AND (SwapFile^.Status = stOk);
    InitSwapManager := SwapFileValid;
  END;


PROCEDURE DoneSwapManager;
  BEGIN

    WHILE HandleListHead <> NIL DO
      HandleListHead^.Done;

    Dispose(SwapFile, Done);
    SwapFile       := NIL;
    HandleListHead := NIL;
    HandleListTail := NIL;

  END;




{----------------------------------------------------------------------------}
{ TSwapHandle.                                                                           }
{____________________________________________________________________________}

CONSTRUCTOR TSwapHandle.Init;
  BEGIN
    Status := stOk;
    Size   := 0;

    Link;
  END;


DESTRUCTOR TSwapHandle.Done;
  BEGIN
    UnLink;

    Pos    := 0;
    Size   := 0;
    Status := stOk;
  END;


PROCEDURE TSwapHandle.Error ( AStatus: WORD );
  BEGIN
    Status := AStatus;
  END;


PROCEDURE TSwapHandle.Link;
  VAR
    p : PSwapHandle;
  BEGIN
    IF Size = 0 THEN
      BEGIN
        Unlink;
        EXIT;
      END;

    p := HandleListHead;

    IF (p = NIL) OR (p^.Pos >= Size) THEN
      BEGIN
        UnLink;

        Pos        := 0;
        Next       := HandleListHead;
        Prev       := NIL;

        IF HandleListHead <> NIL THEN
          HandleListHead^.Prev := @Self;
        IF HandleListTail = NIL THEN
          HandleListTail := @Self;

        HandleListHead := @Self;

        EXIT;
      END;


    WHILE (p <> NIL) AND (p^.Next <> NIL) AND (p <> @Self)
    AND   (p^.Next^.Pos - p^.Pos - p^.Size < Size) DO
      p := p^.Next;

    IF p = @Self THEN EXIT;

    UnLink;

    Pos     := p^.Pos + p^.Size;
    Next    := p^.Next;
    Prev    := p;

    IF Next <> NIL THEN
      Next^.Prev := @Self
    ELSE
      HandleListTail := @Self;

    p^.Next := @Self;
  END;


PROCEDURE TSwapHandle.UnLink;
  VAR
    p : PSwapHandle;
  BEGIN
    p := HandleListHead;

    WHILE (p <> NIL) AND (p <> @Self) DO
      p := p^.Next;

    IF p = @Self THEN
      BEGIN

        IF Prev <> NIL THEN
          Prev^.Next := Next
        ELSE
          HandleListHead := Next;

        IF Next <> NIL THEN
          Next^.Prev := Prev
        ELSE
          BEGIN
            HandleListTail := Prev;
          END;

      END;

    Next   := NIL;
    Prev   := NIL;
  END;



PROCEDURE TSwapHandle.Shrink;
  VAR
    LPos : LONGINT;
  BEGIN
    IF HandleListTail = NIL THEN
      LPos := 0
    ELSE
      LPos := HandleListTail^.Pos + HandleListTail^.Size;

    SwapFile^.Reset;
    SwapFile^.Seek(LPos);
    SwapFile^.Reset;
    SwapFile^.Truncate;
    SwapFile^.Reset;
  END;


PROCEDURE TSwapHandle.Free;
  BEGIN
    Size := 0;
    UnLink;

    CASE NeedCleanup OF
      cluFast: FastCleanup;
      cluFull: FullCleanup;
    END;
  END;


FUNCTION TSwapHandle.Write ( VAR Buf; ASize: WORD ) : BOOLEAN;
  VAR
    f : TClAction;
  BEGIN
    Status := 0;
    Size   := ASize;

    IF ASize = 0 THEN EXIT;

    UnLink;
    Link;
    f := NeedCleanup;
    IF f <> cluNone THEN
      BEGIN
        UnLink;
        CASE f OF
          cluFast: FastCleanup;
          cluFull: FullCleanup;
        END;
        Link;
      END;

    SwapFile^.Reset;
    SwapFile^.Seek(Pos);
    SwapFile^.Reset;
    SwapFile^.Write(Buf, ASize);
    Status := SwapFile^.Status;
    IF Status <> stOk THEN
      Error(Status);
    SwapFile^.Reset;
  END;


FUNCTION TSwapHandle.Read ( VAR Buf; ASize: WORD ) : BOOLEAN;
  BEGIN
    Status := 0;

    IF Size < ASize THEN
      ASize := Size;

    SwapFile^.Reset;
    SwapFile^.Seek(Pos);
    SwapFile^.Reset;
    SwapFile^.Read(Buf, ASize);
    Status := SwapFile^.Status;
    IF Status <> stOk THEN
      Error(Status);
    SwapFile^.Reset;

    IF Status <> stOk THEN
      FillChar(Buf, ASize, 0);
  END;


PROCEDURE TSwapHandle.MoveFrom(OPos: LONGINT);
  VAR
    Buf   : POINTER;
    BSize : WORD;
    TSize : WORD;
    OSize : WORD;
    pos1  : LONGINT;
    pos2  : LONGINT;
  BEGIN
    IF Size = 0 THEN EXIT;

    IF MaxAvail > 65520 THEN
      BSize := 65520
    ELSE
      BSize := MaxAvail;

    IF BSize > Size THEN BSize := Size;

    FullHeap.HGetMem(Buf, BSize);

    pos1 := OPos;
    pos2 := Pos;

    TSize := Size;

    WHILE TSize > 0 DO
      BEGIN
        OSize := TSize;
        IF OSize > BSize THEN
          OSize := BSize;

        SwapFile^.Reset;
        SwapFile^.Seek(pos1);
        SwapFile^.Reset;
        SwapFile^.Read(Buf^, OSize);
        SwapFile^.Reset;
        SwapFile^.Seek(pos2);
        SwapFile^.Reset;
        SwapFile^.Write(Buf^, OSize);
        INC(pos1, OSize);
        INC(pos2, OSize);

        DEC(TSize, OSize);
      END;

    SwapFile^.Reset;
    FullHeap.HFreeMem(Buf, BSize);
  END;


FUNCTION TSwapHandle.NeedCleanup : TClAction;
  VAR
    PCent : LONGINT;
    TS    : LONGINT;
  BEGIN
    TS := TotalSize;
    IF TS > 0 THEN
      PCent := UnusedMem * 100 DIV TS
    ELSE
      PCent := 0;

    IF PCent > 35 THEN
      NeedCleanup := cluFull
    ELSE IF PCent > 10 THEN
      NeedCleanup := cluFast
    ELSE
      NeedCleanup := cluNone;
  END;


PROCEDURE TSwapHandle.FastCleanup;
  VAR
    p    : PSwapHandle;
    q    : PSwapHandle;
    OPos : LONGINT;
  BEGIN
    p := HandleListTail;

    WHILE (p <> NIL) AND (p^.Pos > 0) DO
      BEGIN

        q := p^.Prev;
        OPos := p^.Pos;
        p^.Link;
        IF p^.Pos <> OPos THEN
          p^.MoveFrom(OPos);

        p := q;

      END;

    Shrink;
  END;


PROCEDURE TSwapHandle.FullCleanup;
  VAR
    p    : PSwapHandle;
    q    : PSwapHandle;
    OPos : LONGINT;
  BEGIN
    p := HandleListHead;

    WHILE p <> NIL DO
      BEGIN

        q := p^.Next;

        OPos := p^.Pos;
        p^.Unlink;
        p^.Link;
        IF p^.Pos <> OPos THEN
          p^.MoveFrom(OPos);

        p := q;

      END;

    Shrink;
  END;


FUNCTION TSwapHandle.UsedMem : LONGINT;
  VAR
    p : PSwapHandle;
    l : LONGINT;
  BEGIN
    p := HandleListHead;
    l := 0;
    WHILE p <> NIL DO
      BEGIN
        INC(l, p^.Size);
        p := p^.Next;
      END;

    UsedMem := l;
  END;


FUNCTION TSwapHandle.UnusedMem : LONGINT;
  BEGIN
    UnusedMem := TotalSize - UsedMem;
  END;


FUNCTION TSwapHandle.TotalSize : LONGINT;
  BEGIN
    SwapFile^.Reset;
    TotalSize := SwapFile^.GetSize;
  END;




END.