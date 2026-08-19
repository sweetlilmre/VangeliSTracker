UNIT VTShell;

INTERFACE




PROCEDURE DoWindowShell;




IMPLEMENTATION

USES Dos, VTGlobal, VTScreens, Heaps, BiosVideo;


VAR
  BiosVMode      : BYTE ABSOLUTE 0:$449;
  BiosVColumns   : WORD ABSOLUTE 0:$44A;
  BiosVScrSize   : WORD ABSOLUTE 0:$44C;
  BiosVScrOffset : WORD ABSOLUTE 0:$44E;
  BiosVPage      : BYTE ABSOLUTE 0:$462;








PROCEDURE MyInt10(_Flags, _CS, _IP, _AX, _BX, _CX, _DX,
                          _SI, _DI, _DS, _ES, _BP: Word); INTERRUPT;

  PROCEDURE CallOldInt10;
    CONST
      R       : Registers = (AX:0);
      SavePtr : POINTER   = NIL;
      Sema    : BYTE      = 0;
    BEGIN

      INC(Sema);

      IF Sema = 1 THEN
        BEGIN
          GetIntVec($10, SavePtr);
          SetIntVec($10, Int10Ptr);
        END;

      R.AX    := _AX;
      R.BX    := _BX;
      R.CX    := _CX;
      R.DX    := _DX;
      R.SI    := _SI;
      R.DI    := _DI;
      R.ES    := _ES;
      R.DS    := _DS;
      R.BP    := _BP;
      R.Flags := _Flags;

      Intr($10, R);

      _AX    := R.AX;
      _BX    := R.BX;
      _CX    := R.CX;
      _DX    := R.DX;
      _SI    := R.SI;
      _DI    := R.DI;
      _ES    := R.ES;
      _DS    := R.DS;
      _BP    := R.BP;
      _Flags := R.Flags;

      IF Sema = 1 THEN
        SetIntVec($10, SavePtr);

      DEC(Sema);

    END;

  BEGIN

    BiosVMode      := 3;
    BiosVColumns   := 80;
    BiosVScrSize   := 80*50;
    BiosVScrOffset := 0;
    BiosVPage      := 0;
{
    CallOldInt10(_Flags, _AX, _BX, _CX, _DX, _SI, _DI, _DS, _ES, _BP);
}
    CASE HI(_AX) OF
       1,
       2,
       3,

       6,
       7,
       8,
       9,
      10,
      15: ;
      14: CallOldInt10;
    ELSE

{      _AX := $ABAB;}

    END;

  END;




PROCEDURE DoWindowShell;
  VAR
    HeapSize      : LONGINT;
    SaveMode      : BYTE;
    SaveColumns   : WORD;
    SaveScrSize   : WORD;
    SaveScrOffset : WORD;
    SavePage      : BYTE;
  BEGIN

    SetUser(F8Demo);

    SaveMode      := BiosVMode;
    SaveColumns   := BiosVColumns;
    SaveScrSize   := BiosVScrSize;
    SaveScrOffset := BiosVScrOffset;
    SavePage      := BiosVPage;

    GetIntVec($10, Int10Ptr);
    SetIntVec($10, @MyInt10);

    SetCursor(0, 0, 0);
    UnderCursor;

    HeapSize := Heap.HTotalAvail;
    ShrinkSystemHeap(0);
    SwapVectors;
    Exec(ShellPath, ShellParam);
    SwapVectors;
    ShrinkSystemHeap(HeapSize);

    SetIntVec($10, Int10Ptr);
    Int10Ptr := NIL;

    BiosVMode      := SaveMode;
    BiosVColumns   := SaveColumns;
    BiosVScrSize   := SaveScrSize;
    BiosVScrOffset := SaveScrOffset;
    BiosVPage      := SavePage;

  END;




END.
