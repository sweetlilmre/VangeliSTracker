{$A+,B-,D+,E-,F-,G+,I-,L+,N-,O-,R-,S-,V-,X+}
UNIT Gfx;

   (* Copyright by Jare/Iguana in 1993, but given to the public domain. *)
   (* Want more comments? Write'em!                                     *)

   (*   Several useful VGA routines.                                    *)


INTERFACE

USES Dos;

VAR
   r : Registers;
   ScreenB: ARRAY [0..63999] OF BYTE ABSOLUTE $A000:0;
   ScreenW: ARRAY [0..31999] OF WORD ABSOLUTE $A000:0;


FUNCTION GetKey: WORD;

FUNCTION TestKey: BOOLEAN;

PROCEDURE SetKeyRate(delay: BYTE; rep: BYTE);

PROCEDURE VSync;

PROCEDURE WaitForRetrace;

PROCEDURE WaitForDisplay;

PROCEDURE SetScrStart(s : WORD);

PROCEDURE SetLineCompare(l : WORD);

PROCEDURE PresetRowScan(s : BYTE);


   (* ========================================= *)

IMPLEMENTATION

FUNCTION GetKey: WORD;
  BEGIN
     r.AH := 0;
     Intr($16, r);
     GetKey := r.AX
  END;

FUNCTION TestKey: BOOLEAN;
  BEGIN
     r.AH := 1;
     Intr($16, r);
     TestKey := (r.Flags AND FZero) = 0
  END;

PROCEDURE SetKeyRate(delay: BYTE; rep: BYTE);ASSEMBLER;
  ASM
     MOV  AX,0305h
     MOV  BH,delay
     MOV  BL,rep
     INT  16h
  END;

PROCEDURE VSync;
  BEGIN
     WHILE (Port[$3DA] AND 8) =  8 DO;
     WHILE (Port[$3DA] AND 8) <> 8 DO;
  END;

PROCEDURE WaitForRetrace;
  BEGIN
     WHILE (Port[$3DA] AND 8) <> 8 DO;
  END;

PROCEDURE WaitForDisplay;
  BEGIN
     WHILE (Port[$3DA] AND 8) =  8 DO;
  END;

PROCEDURE SetScrStart(s : WORD);
  BEGIN
     ASM
        CLI
     END;
     Port[$3d4] := $c; Port[$3d5] := HI(s);
     Port[$3d4] := $d; Port[$3d5] := LO(s);
     ASM
        STI
     END
  END;

PROCEDURE SetLineCompare(l : WORD);
  BEGIN
     Port[$3d4] := $18; Port[$3d5] := BYTE(l);
     Port[$3d4] := $7;  Port[$3d5] := (Port[$3d5] AND $EF)
                                      OR BYTE((l AND $100) DIV 2);
     Port[$3d4] := $9;  Port[$3d5] := (Port[$3d5] AND $BF)
                                      OR BYTE((l AND $200) DIV 8)
  END;

PROCEDURE PresetRowScan(s : BYTE);
  BEGIN
     Port[$3d4] := 8; Port[$3d5] := (Port[$3d5] AND $E0) OR (s AND $0F)
  END;

END.
