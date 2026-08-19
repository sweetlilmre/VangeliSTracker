{****************************************************************************}
{                                                                            }
{ MODULE:         Debugging                                                  }
{                                                                            }
{ DESCRIPTION:    Provides a set of procedures useful for debugging. Uses    }
{                 the Output43 routines for output.                          }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        17-Oct-1992 Documentation                                  }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT Debugging;

INTERFACE

CONST
  Debug : BOOLEAN = TRUE; { Set to FALSE to deactivate the debugging output. }




PROCEDURE SetOffs  (MyOffs: WORD);
PROCEDURE SetBorder(R, G, B: BYTE);          { Set the overscan DAC register.              }
PROCEDURE WriteNum (Offs, w: WORD; a: BYTE); { Write a number at a position of the screen. }
PROCEDURE WriteChar(c: CHAR; a: BYTE);       { Write a character and attr sequentially.    }
PROCEDURE WriteSNum(w: WORD; a: BYTE);       { Write a number and attr sequentially.       }




IMPLEMENTATION

USES Output43, HexConversions;

CONST
  Offs : WORD = 0;




PROCEDURE SetOffs(MyOffs: WORD);
  BEGIN
    Offs := MyOffs;
  END;


PROCEDURE SetBorder(R, G, B: BYTE); ASSEMBLER;
  ASM
        MOV     AL,Debug
        AND     AL,AL
        JZ      @@End

        MOV     DX,$3C8
        MOV     AL,0
        OUT     DX,AL    { Set overscan register for writing. }
        INC     DX

        MOV     AL,R
        JMP     @@0
@@0:    OUT     DX,AL
        MOV     AL,G
        JMP     @@1
@@1:    OUT     DX,AL
        MOV     AL,B
        JMP     @@2
@@2:    OUT     DX,AL

@@End:
  END;


PROCEDURE WriteNum(Offs, w: WORD; a: BYTE);
  VAR
    s : STRING[6];
  BEGIN
    IF Debug THEN
      BEGIN
        STR(w : 6, s);
        DirectWriteAttr(Offs, s, a);
      END;
  END;


PROCEDURE WriteChar(c: CHAR; a: BYTE);
  BEGIN
    IF Debug THEN
      BEGIN
        Offs := Offs AND 8191;
        DirectWriteAttr(Offs, c, a);
        INC(Offs, 2);
      END;
  END;


PROCEDURE WriteSNum(w: WORD; a: BYTE);
  VAR
    s : STRING[4];
    i : WORD;
  BEGIN
    IF Debug THEN
      BEGIN
        s := HexWord(w);
        FOR i := 1 TO 4 DO WriteChar(s[i], a);
      END;
  END;




END.