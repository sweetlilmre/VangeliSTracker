{$A+,B-,D+,E-,F-,G+,I-,L+,N-,O-,R-,S-,V-,X+}
UNIT Menus;

   (* Copyright by Jare/Iguana in 1993, but given to the public domain. *)
   (* Want more comments? Write'em!                                     *)

   (*   Nice simple menus. Nothing impressive here.                     *)

   (*   Modified in XMas'93 by Cesar Alba so that options not available *)
   (* are shown in grey and the cursor skips them. Thank you Cesar!     *)

INTERFACE

TYPE
   TMenuIt = RECORD
      Text : STRING[60];
      Val  : WORD;
   END;

   PMenu = ^TMenu;
   TMenu = RECORD
      mi : ARRAY [1..20] OF TMenuIt;
      util : ARRAY [1..20] OF BOOLEAN;
      ni : WORD;
   END;


FUNCTION DoMenu(VAR m : TMenu; def: WORD): WORD;

PROCEDURE ClearMenu(VAR m : TMenu);

PROCEDURE AddItem(VAR m : TMenu; it : TMenuIt; outil: BOOLEAN);

VAR
   mm : PMenu;   (* Menu var provided. Another quick hack. *)



   (* ========================================= *)

IMPLEMENTATION

USES
   Output, Gfx;

FUNCTION DoMenu(VAR m : TMenu; def: WORD): WORD;
  VAR
     k : WORD;
     pos, i: INTEGER;
  BEGIN
     pos := 1;
        FOR i := 1 TO m.ni DO
           IF (m.mi[i].Val = def) THEN
              Pos := i;
     REPEAT
        FOR i := 1 TO m.ni DO
           IF i = Pos THEN
              DumpLine('         '+m.mi[i].Text, 0*16+15, i-1)
           ELSE
              IF m.util[i] THEN
                DumpLine('         '+m.mi[i].Text, 6*16+15, i-1)
              ELSE
                DumpLine('         '+m.mi[i].Text, 6*16+8, i-1);
        k := GetKey;
        CASE CHAR(k) OF
           #0 : CASE HI(k) OF
                   72 : DEC(Pos);
                   80 : INC(Pos);
                   79 : Pos := m.ni;
                   71 : Pos := 1;
                   81 : IF (Pos <= (m.ni-5)) THEN INC(Pos, 5) ELSE Pos := m.ni;
                   73 : IF (Pos > 5)         THEN DEC(Pos, 5) ELSE Pos := 1;
                END;

           #27 : BEGIN DoMenu := $FFFF; EXIT; END;
           ' ', #13, #10 : BEGIN DoMenu := m.mi[Pos].Val; EXIT; END;
           '8': DEC(Pos);
           '2': INC(Pos);
           '1': Pos := m.ni;
           '7': Pos := 1;
           '3': IF (Pos <= (m.ni-5)) THEN INC(Pos, 5) ELSE Pos := m.ni;
           '9': IF (Pos > 5)         THEN DEC(Pos, 5) ELSE Pos := 1;
        END;
        IF (Pos > m.ni) THEN
           Pos := 1
        ELSE IF (Pos < 1) THEN
           Pos := m.ni;
        IF NOT (m.util[Pos]) THEN
          CASE CHAR(k) OF
             #0 : CASE HI(k) OF
                   72,73,79 : REPEAT
                                  DEC(Pos);
                                  IF Pos<1 THEN
                                    Pos := m.ni
                                UNTIL m.util[Pos];
                   80,81,71 : REPEAT
                                  INC(Pos);
                                  IF Pos>m.ni THEN
                                    Pos := 1;
                                UNTIL m.util[Pos];
                  END;
             '8','1','9': REPEAT
                              DEC(Pos);
                              IF Pos<1 THEN
                                Pos := m.ni;
                          UNTIL m.util[Pos];
             '2','7','3': REPEAT
                              INC(Pos);
                              IF Pos>m.ni THEN
                                Pos := 1;
                          UNTIL m.util[Pos];
           END;
     UNTIL FALSE;
  END;


PROCEDURE ClearMenu(VAR m : TMenu);
  BEGIN
     m.ni := 0;
  END;

PROCEDURE AddItem(VAR m : TMenu; it : TMenuIt; outil : BOOLEAN);
  BEGIN
     IF (m.ni < 20) THEN BEGIN
        INC(m.ni);
        m.mi[m.ni] := it;
        m.util[m.ni] := outil
     END;
  END;


BEGIN
   New(mm);
   ClearMenu(mm^)
END.
