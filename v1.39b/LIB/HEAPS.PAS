UNIT Heaps;

INTERFACE

USES Memory, Objects;




TYPE
  PFreeListRec = ^TFreeListRec;
  TFreeListRec = ARRAY[1..2] OF LONGINT;

  PHeap = ^THeap;
  THeap =
    OBJECT(TObject)
      HHeapOrg  : POINTER;
      HHeapPtr  : POINTER;
      HHeapEnd  : POINTER;
      HFreeList : PFreeListRec;

      CONSTRUCTOR Init(Buffer: POINTER; Size: LONGINT);
      CONSTRUCTOR EmptyInit;
      DESTRUCTOR  Done; VIRTUAL;

      PROCEDURE HGetMem (VAR Buf: POINTER; Size: WORD); VIRTUAL;
      PROCEDURE HFreeMem(VAR Buf: POINTER; Size: WORD); VIRTUAL;

      FUNCTION HMemAvail   : LONGINT; VIRTUAL;
      FUNCTION HMaxAvail   : LONGINT; VIRTUAL;
      FUNCTION HTotalAvail : LONGINT; VIRTUAL;

      PROCEDURE TransferToSystem;   VIRTUAL;
      PROCEDURE TransferFromSystem; VIRTUAL;
      PROCEDURE BeginOperation;     VIRTUAL;
      PROCEDURE EndOperation;       VIRTUAL;

      FUNCTION InHeap(P: POINTER) : BOOLEAN; VIRTUAL;

      FUNCTION  HNewStr         (S: STRING) : PString; VIRTUAL;
      PROCEDURE HDisposeStr (VAR S: PString);          VIRTUAL;
    END;

  PUmbHeap = ^TUmbHeap;
  TUmbHeap =
    OBJECT(THeap)
      CONSTRUCTOR Init;
      DESTRUCTOR  Done; VIRTUAL;
    END;

  PHeapColl = ^THeapColl;
  THeapColl =
    OBJECT(THeap)
      HeapColl : TCollection;

      CONSTRUCTOR Init;
      DESTRUCTOR  Done;              VIRTUAL;

      PROCEDURE AddHeap   (H: PHeap); VIRTUAL;
      PROCEDURE RemoveHeap(H: PHeap); VIRTUAL;

      PROCEDURE HGetMem (VAR Buf: POINTER; Size: WORD); VIRTUAL;
      PROCEDURE HFreeMem(VAR Buf: POINTER; Size: WORD); VIRTUAL;

      FUNCTION HMemAvail   : LONGINT; VIRTUAL;
      FUNCTION HMaxAvail   : LONGINT; VIRTUAL;
      FUNCTION HTotalAvail : LONGINT; VIRTUAL;

      PROCEDURE TransferToSystem;   VIRTUAL;
      PROCEDURE TransferFromSystem; VIRTUAL;
      PROCEDURE BeginOperation;     VIRTUAL;
      PROCEDURE EndOperation;       VIRTUAL;

      FUNCTION InHeap(P: POINTER) : BOOLEAN; VIRTUAL;
    END;




VAR
  InitialHeapEnd : POINTER;
  Heap           : THeap;
  UmbHeap        : THeapColl;
  FullHeap       : THeapColl;
  TempHeap       : THeap;




PROCEDURE InitHeapVariables;
PROCEDURE DoneHeapVariables;

PROCEDURE InitUmbHeap;
PROCEDURE ChangeSystemHeap (Size: LONGINT);
PROCEDURE ShrinkSystemHeap (Size: LONGINT);
PROCEDURE InitTempHeap     (Size: LONGINT);
PROCEDURE DoneTempHeap;




IMPLEMENTATION

USES UMBUnit, HexConversions;




{----------------------------------------------------------------------------}
{ Functions that handle pointers.                                            }
{____________________________________________________________________________}

FUNCTION IncPtr(P: POINTER; L: LONGINT) : POINTER;
  BEGIN
    IncPtr := Ptr(SEG(P^) + ((OFS(P^) + L) SHR 4), (OFS(P^) + L) AND 15);
  END;


FUNCTION NormalizePtr(P: POINTER) : POINTER;
  BEGIN
    NormalizePtr := Ptr(SEG(P^) + (OFS(P^) SHR 4), OFS(P^) AND 15);
  END;


FUNCTION LinealPtr(P: POINTER) : LONGINT;
  BEGIN
    LinealPtr := (LONGINT(SEG(P^)) SHL 4) + OFS(P^);
  END;




{----------------------------------------------------------------------------}
{ Utilities for initialising and managing heaps.                             }
{____________________________________________________________________________}

PROCEDURE InitUmbHeap;
  VAR
    UMB : PUmbHeap;
  BEGIN
    REPEAT
      New(UMB, Init);
      IF UMB^.HTotalAvail <> 0 THEN
        UmbHeap.AddHeap(UMB)
      ELSE
        BEGIN
          Dispose(UMB, Done);
          UMB := NIL;
        END;
    UNTIL UMB = NIL;
  END;


PROCEDURE ChangeSystemHeap(Size: LONGINT);
  BEGIN
    IF Size < LinealPtr(HeapPtr) - LinealPtr(HeapOrg) THEN
      Size := LinealPtr(HeapPtr) - LinealPtr(HeapOrg)
    ELSE IF Size > LinealPtr(InitialHeapEnd) - LinealPtr(HeapOrg) THEN
      Size := LinealPtr(InitialHeapEnd) - LinealPtr(HeapOrg);

    HeapEnd := IncPtr(HeapOrg, Size);
    Heap.TransferFromSystem;
  END;


PROCEDURE ShrinkSystemHeap(Size: LONGINT);
  BEGIN
    ChangeSystemHeap(Size);
    SetMemTop(HeapEnd);
  END;


PROCEDURE InitTempHeap(Size: LONGINT);
  VAR
    SystemTot : LONGINT;
  BEGIN
    TempHeap.Done;

    SystemTot := Heap.HTotalAvail;
    ChangeSystemHeap(SystemTot - Size);
    Size := SystemTot - Heap.HTotalAvail;

    TempHeap.Init(Heap.HHeapEnd, Size);
  END;


PROCEDURE DoneTempHeap;
  VAR
    Size : LONGINT;
  BEGIN
    TempHeap.Done;

    Size := TempHeap.HTotalAvail;
    ChangeSystemHeap(Heap.HTotalAvail+Size);

    TempHeap.EmptyInit;
  END;




{----------------------------------------------------------------------------}
{ THeap object implementation.                                               }
{____________________________________________________________________________}

CONSTRUCTOR THeap.Init(Buffer: POINTER; Size: LONGINT);
  BEGIN
    TObject.Init;
    IF Size > 0 THEN
      BEGIN
        HHeapEnd  := IncPtr(Buffer, Size);
        HHeapEnd  := Ptr(SEG(HHeapEnd^), 0);

        Buffer   := NormalizePtr(Buffer);
        IF OFS(Buffer^) <> 0 THEN
          Buffer := Ptr(SEG(Buffer^) + 1, 0);
        HHeapOrg  := Buffer;
        HHeapPtr  := Buffer;
        HFreeList := Buffer;
        FillChar(HFreeList^, SizeOf(HFreeList^), 0);
      END;
  END;


CONSTRUCTOR THeap.EmptyInit;
  BEGIN
    TObject.Init;
  END;


DESTRUCTOR  THeap.Done; 
  BEGIN
    HHeapOrg  := NIL;
    HHeapPtr  := NIL;
    HHeapEnd  := NIL;
    HFreeList := NIL;
    TObject.Done;
  END;


PROCEDURE THeap.HGetMem (VAR Buf: POINTER; Size: WORD); 
  BEGIN
    BeginOperation;
    IF MaxAvail < Size THEN
      Buf := NIL
    ELSE
      GetMem(Buf, Size);
    EndOperation;
  END;


PROCEDURE THeap.HFreeMem(VAR Buf: POINTER; Size: WORD); 
  BEGIN
    IF Buf = NIL THEN EXIT;
    IF NOT InHeap(Buf) THEN
      BEGIN
        WriteLn('Bad FreeMem: ', HexPtr(Buf));
        EXIT;
      END;
    BeginOperation;
    FreeMem(Buf, Size);
    Buf := NIL;
    EndOperation;
  END;


FUNCTION THeap.HMemAvail : LONGINT; 
  BEGIN
    BeginOperation;
    HMemAvail := MemAvail;
    EndOperation;
  END;


FUNCTION THeap.HMaxAvail : LONGINT; 
  BEGIN
    BeginOperation;
    HMaxAvail := MaxAvail;
    EndOperation;
  END;


FUNCTION THeap.HTotalAvail : LONGINT;
  BEGIN
    BeginOperation;
    HTotalAvail := LinealPtr(HHeapEnd) - LinealPtr(HHeapOrg);
    EndOperation;
  END;


PROCEDURE THeap.TransferToSystem;
  BEGIN
    HeapOrg  := HHeapOrg;
    HeapPtr  := HHeapPtr;
    HeapEnd  := HHeapEnd;
    FreeList := HFreeList;
  END;


PROCEDURE THeap.TransferFromSystem;
  BEGIN
    HHeapOrg  := HeapOrg;
    HHeapPtr  := HeapPtr;
    HHeapEnd  := HeapEnd;
    HFreeList := FreeList;
  END;


PROCEDURE THeap.BeginOperation;
  BEGIN
    IF @Self <> @Heap THEN
      BEGIN
        Heap.TransferFromSystem;
        TransferToSystem;
      END;
  END;


PROCEDURE THeap.EndOperation;
  BEGIN
    IF @Self <> @Heap THEN
      BEGIN
        TransferFromSystem;
        Heap.TransferToSystem;
      END
    ELSE
      BEGIN
        TransferFromSystem;
      END;
  END;


FUNCTION THeap.InHeap(P: POINTER) : BOOLEAN;
  BEGIN
    InHeap := (LinealPtr(P) >= LinealPtr(HHeapOrg)) AND
              (LinealPtr(P) <  LinealPtr(HHeapPtr));
  END;


FUNCTION THeap.HNewStr(S: STRING) : PString;
  VAR
    NS : PString;
  BEGIN
    HGetMem(POINTER(NS), Length(S) + 1);
    IF NS <> NIL THEN
      NS^ := S;
    HNewStr := NS;
  END;


PROCEDURE THeap.HDisposeStr(VAR S: PString);
  BEGIN
    HFreeMem(POINTER(S), Length(S^) + 1);
  END;




{----------------------------------------------------------------------------}
{ TUmbHeap object implementation.                                            }
{____________________________________________________________________________}

CONSTRUCTOR TUmbHeap.Init;
  VAR
    L   : LONGINT;
    Buf : POINTER;
  BEGIN
    L := UMBAllocate(Buf, 1000000);
    IF Buf <> NIL THEN
      THeap.Init(Buf, L)
    ELSE
      EmptyInit;
  END;


DESTRUCTOR TUmbHeap.Done;
  BEGIN
    IF HHeapOrg <> NIL THEN
      UMBFree(HHeapOrg);
  END;




{----------------------------------------------------------------------------}
{ THeapColl object implementation.                                           }
{____________________________________________________________________________}

CONSTRUCTOR THeapColl.Init;
  BEGIN
    EmptyInit;
    HeapColl.Init(3, 2);
  END;


DESTRUCTOR THeapColl.Done;

  PROCEDURE DoFree(H: PHeap); FAR;
    BEGIN
      HeapColl.Delete(H);
      IF SEG(H^) <> SEG(Heap) THEN
        Dispose(H, Done);
    END;
  
  BEGIN
    HeapColl.ForEach(@DoFree);
  END;


PROCEDURE THeapColl.AddHeap(H: PHeap);
  BEGIN
    HeapColl.Insert(H);
  END;


PROCEDURE THeapColl.RemoveHeap(H: PHeap);
  BEGIN
    HeapColl.Delete(H);
  END;


PROCEDURE THeapColl.HGetMem (VAR Buf: POINTER; Size: WORD);

  FUNCTION Get(VAR H: THeap) : BOOLEAN; FAR;
    BEGIN
      H.HGetMem(Buf, Size);
      Get := Buf <> NIL;
    END;

  BEGIN { HGetMem }
    Buf := NIL;
    HeapColl.FirstThat(@Get);
  END;


PROCEDURE THeapColl.HFreeMem(VAR Buf: POINTER; Size: WORD);

  FUNCTION DoFree(VAR H: THeap) : BOOLEAN; FAR;
    BEGIN
      IF H.InHeap(Buf) THEN
        BEGIN
          DoFree := TRUE;
          H.HFreeMem(Buf, Size);
        END
      ELSE
        DoFree := FALSE;
    END;

  BEGIN { HFreeMem }
    IF Buf = NIL THEN EXIT;
    HeapColl.FirstThat(@DoFree);
    Buf := NIL;
  END;


FUNCTION THeapColl.HMemAvail : LONGINT; 
  VAR
    Sum : LONGINT;

  PROCEDURE Add(VAR H: THeap); FAR;
    BEGIN
      INC(Sum, H.HMemAvail);
    END;

  BEGIN { HMemAvail }
    Sum := 0;
    HeapColl.ForEach(@Add);
    HMemAvail := Sum;
  END;


FUNCTION THeapColl.HMaxAvail : LONGINT; 
  VAR
    Sum : LONGINT;

  PROCEDURE FindMax(VAR H: THeap); FAR;
    VAR
      Max : LONGINT;
    BEGIN
      Max := H.HMaxAvail;
      IF Max > Sum THEN
        Sum := Max;
    END;

  BEGIN { HMaxAvail }
    Sum := 0;
    HeapColl.ForEach(@FindMax);
    HMaxAvail := Sum;
  END;


FUNCTION THeapColl.HTotalAvail : LONGINT;
  VAR
    Sum : LONGINT;

  PROCEDURE Add(VAR H: THeap); FAR;
    BEGIN
      INC(Sum, H.HTotalAvail);
    END;

  BEGIN { HTotalAvail }
    Sum := 0;
    HeapColl.ForEach(@Add);
    HTotalAvail := Sum;
  END;


PROCEDURE THeapColl.TransferToSystem;
  BEGIN
  END;


PROCEDURE THeapColl.TransferFromSystem; 
  BEGIN
  END;


PROCEDURE THeapColl.BeginOperation;
  BEGIN
  END;


PROCEDURE THeapColl.EndOperation;
  BEGIN
  END;


FUNCTION THeapColl.InHeap(P: POINTER) : BOOLEAN;

  FUNCTION IsIn(VAR H: THeap) : BOOLEAN; FAR;
    BEGIN
      IsIn := H.InHeap(P);
    END;

  BEGIN { InHeap }
    InHeap := TRUE;
    InHeap := HeapColl.FirstThat(@IsIn) <> NIL;
  END;




{----------------------------------------------------------------------------}
{ Normal Heap variables initialisation and deinitialisation. Looking for     }
{ every tiny bit of memory available.                                        }
{____________________________________________________________________________}

PROCEDURE InitHeapVariables;
  BEGIN
    UmbHeap.Init;
    FullHeap.AddHeap(@UmbHeap);
    FullHeap.AddHeap(@Heap);

  END;


PROCEDURE DoneHeapVariables;
  BEGIN
    FullHeap.RemoveHeap(@Heap);
    FullHeap.Done;
    TempHeap.Done;
  END;


BEGIN
  InitialHeapEnd := HeapEnd;

  Heap.EmptyInit;
  Heap.HHeapOrg  := HeapOrg;
  Heap.HHeapPtr  := HeapPtr;
  Heap.HHeapEnd  := HeapEnd;
  Heap.HFreeList := FreeList;

  FullHeap.Init;
  TempHeap.EmptyInit;
END.