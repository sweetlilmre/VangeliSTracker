UNIT IFF;

INTERFACE

USES Objects;




TYPE
  TIffBlockIdent = STRING[4];

  PIffFile = ^TIffFile;
  TIffFile =
    OBJECT(TObject)
      CONSTRUCTOR Init;
      DESTRUCTOR  Done; VIRTUAL;

      PROCEDURE Parse  (VAR St: TStream);                             VIRTUAL;
      FUNCTION  DoBlock(VAR St: TStream;
                        Id: TIffBlockIdent; Size: LONGINT) : BOOLEAN; VIRTUAL;
    END;




IMPLEMENTATION




CONSTRUCTOR TIffFile.Init;
  BEGIN
    TObject.Init;
  END;


DESTRUCTOR TIffFile.Done;
  BEGIN
    TObject.Done;
  END;


FUNCTION SwapLong(l: LONGINT) : LONGINT;
  VAR
    w : ARRAY[0..1] OF WORD ABSOLUTE l;
    r : WORD;
  BEGIN
    r    := SWAP(w[0]);
    w[0] := SWAP(w[1]);
    w[1] := r;
    SwapLong := l;
  END;


PROCEDURE TIffFile.Parse(VAR St: TStream);
  VAR
    Id   : TIffBlockIdent;
    l    : LONGINT;
    Size : LONGINT;
  BEGIN
    Id[0] := #4;

    REPEAT
      l := St.GetSize - St.GetPos;
      IF l < 8 THEN EXIT;
      St.Read(Id[1], 4);
      St.Read(Size,  4);

      Size := SwapLong(Size);

      l := St.GetSize - St.GetPos;
      IF l < Size THEN EXIT;
      l := St.GetPos + Size;
      IF NOT DoBlock(St, Id, Size) THEN EXIT;
      St.Seek(l);
    UNTIL FALSE;
  END;


FUNCTION TIffFile.DoBlock(VAR St: TStream; Id: TIffBlockIdent; Size: LONGINT) : BOOLEAN;
  BEGIN
    DoBlock := FALSE;
  END;




END.