UNIT VTBitmaps;

INTERFACE

PROCEDURE WriteVTLogo     (Offs: WORD);
PROCEDURE WriteVTNoPartAct(Offs: WORD);




IMPLEMENTATION

USES Output43, Vid43;




PROCEDURE WriteVTLogo     (Offs: WORD);
  CONST
    VTLogo : ARRAY[1..4] OF ARRAY[1..16] OF BYTE = (

      {[---1---][---2----][---3----][---4----][---5----][---6----][---7----][---8----]}

      ( 95, $35, 132, $35, 133, $35,  95, $35,  95, $35,  95, $35,  95, $35,  95, $35),
      (136, $35, 137, $37, 138, $35, 133, $37,  95, $37,  32, $35, 133, $37, 134, $37),
      (139, $35, 140, $37, 141, $35, 142, $37, 143, $35,  32, $35, 131, $37,  32, $37),
      (144, $35,  95, $37,  95, $37, 145, $37, 143, $35,  95, $37, 146, $37,  32, $37)
    );
  VAR
    i : WORD;
  BEGIN
    FOR i := 1 TO 4 DO Move(VTLogo[i], Ptr(ScrSegment, Offs + ScreenBytesX*(i-1))^, 16);
  END;


PROCEDURE WriteVTNoPartAct(Offs: WORD);
  CONST
    VTNoPartAct : ARRAY[1..2] OF ARRAY[1..32] OF BYTE = (

      {[---1---][---2----][---3----][---4----][---5----][---6----][---7----][---8----]}

      (147, $35, 148, $35, 148, $35, 148, $35, 148, $35, 148, $35, 148, $35, 148, $35,
       148, $35, 148, $35, 148, $35, 148, $35, 148, $35, 148, $35, 148, $35, 149, $37),
      (150, $35, 148, $37, 148, $37, 148, $37, 148, $37, 148, $37, 148, $37, 148, $37,
       148, $37, 148, $37, 148, $37, 148, $37, 148, $37, 148, $37, 148, $37, 151, $37)
    );
  VAR
    i : WORD;
  BEGIN
    FOR i := 1 TO 2 DO Move(VTNoPartAct[i], Ptr(ScrSegment, Offs + ScreenBytesX*(i-1))^, 32);
  END;




END.