{****************************************************************************}
{                                                                            }
{ MODULE:         BiosVideo                                                  }
{                                                                            }
{ DESCRIPTION:    Provides access to all the BIOS video services.            }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        19-Dec-1992 Creation.                                      }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}


UNIT BiosVideo;

INTERFACE

TYPE
  TVideoStateSaved =
    RECORD
      Mode     : BYTE;
      FontSize : BYTE;
      Buffer   : POINTER;
    END;

CONST
  Int10Ptr : POINTER = NIL;




PROCEDURE SaveVideoState      (VAR Buffer: TVideoStateSaved);
PROCEDURE RestoreVideoState   (VAR Buffer: TVideoStateSaved);
PROCEDURE SetVideoMode        (Mode: BYTE);
FUNCTION  GetVideoMode                      : BYTE;
PROCEDURE ForceEGAMode;
                             
PROCEDURE SelectFont8x8       (Font: BYTE);         
PROCEDURE SelectFont8x14      (Font: BYTE);         
PROCEDURE SelectFont8x16      (Font: BYTE);         
PROCEDURE SelectFontQuiet8x8  (Font: BYTE);         
PROCEDURE SelectFontQuiet8x14 (Font: BYTE);         
PROCEDURE SelectFontQuiet8x16 (Font: BYTE);         
PROCEDURE FillFont            (Font: BYTE; First: CHAR; NChars: WORD;
                               Size: BYTE; Data: POINTER); 
PROCEDURE SelectFonts         (FontDim, FontBright: BYTE); 

PROCEDURE NoCursor;                                        
PROCEDURE UnderCursor;                                     
PROCEDURE BlockCursor;                                     
PROCEDURE SetCursor           (x, y: BYTE; Page: BYTE); 

PROCEDURE BlinkOff;                                        
PROCEDURE SetPalette          (Palette: POINTER);

PROCEDURE SetVideoPage        (Page: BYTE);             

PROCEDURE FillVideoMemory     (Chr: CHAR; Attr: BYTE);  




IMPLEMENTATION




PROCEDURE CallInt10; ASSEMBLER;
  ASM
        PUSH    AX
        MOV     AX,[WORD PTR Int10Ptr]
        AND     AX,AX
        POP     AX
        JZ      @@noptr
         PUSHF
         CALL   [Int10Ptr]
        JMP     @@Fin
@@noptr: INT    10h
@@Fin:
  END;



{----------------------------------------------------------------------------}
{ Video mode services.                                                       }
{____________________________________________________________________________}


PROCEDURE SaveVideoState(VAR Buffer: TVideoStateSaved);
  VAR
    FSize : WORD ABSOLUTE 0:$485;
  BEGIN

    Buffer.FontSize := FSize;
    Buffer.Mode     := GetVideoMode;

    ASM

        MOV     CX,$07
        LES     BX,[Buffer]
        LES     BX,TVideoStateSaved([ES:BX]).Buffer

        MOV     AX,$1C01
        CALL    CallInt10

    END;

  END;


PROCEDURE RestoreVideoState(VAR Buffer: TVideoStateSaved);
  BEGIN

    SetVideoMode(Buffer.Mode);
    CASE Buffer.FontSize OF
       8 : SelectFont8x8(0);
      14 : SelectFont8x14(0);
      16 : SelectFont8x16(0);
    ELSE
      SelectFont8x16(0);
    END;

    ASM

        MOV     CX,$07
        LES     BX,[Buffer]
        LES     BX,TVideoStateSaved([ES:BX]).Buffer

        MOV     AX,$1C02
        CALL    CallInt10

    END;

  END;


PROCEDURE SetVideoMode(Mode: BYTE); ASSEMBLER;
  ASM

        MOV     AL,Mode

        XOR     AH,AH
        CALL    CallInt10

  END;


FUNCTION GetVideoMode : BYTE; ASSEMBLER;
  ASM

        MOV     AH,$F
        CALL    CallInt10

        AND     AL,$7F

  END;


PROCEDURE ForceEGAMode; ASSEMBLER;
  ASM

        MOV     BL,$30   { en vez de 9x8, que no sirve para hacer gr ficos bien. }

        MOV     AX,$1201 { 350 l¡neas (EGA) para que los caracteres tengan 8X8   }
        CALL    CallInt10

  END;




{----------------------------------------------------------------------------}
{ Font services.                                                             }
{____________________________________________________________________________}


PROCEDURE SelectFont8x8(Font: BYTE); ASSEMBLER;
  ASM

        MOV     BL,Font

        MOV     AX,$1112 
        CALL    CallInt10

  END;


PROCEDURE SelectFont8x14(Font: BYTE); ASSEMBLER;
  ASM

        MOV     BL,Font

        MOV     AX,$1111
        CALL    CallInt10

  END;


PROCEDURE SelectFont8x16(Font: BYTE); ASSEMBLER;
  ASM

        MOV     BL,Font

        MOV     AX,$1114
        CALL    CallInt10

  END;


PROCEDURE SelectFontQuiet8x8(Font: BYTE); ASSEMBLER;
  ASM

        MOV     BL,Font

        MOV     AX,$1102
        CALL    CallInt10

  END;


PROCEDURE SelectFontQuiet8x14(Font: BYTE); ASSEMBLER;
  ASM

        MOV     BL,Font

        MOV     AX,$1101
        CALL    CallInt10

  END;


PROCEDURE SelectFontQuiet8x16(Font: BYTE); ASSEMBLER;
  ASM

        MOV     BL,Font

        MOV     AX,$1104
        CALL    CallInt10

  END;


PROCEDURE FillFont(Font: BYTE; First: CHAR; NChars: WORD;
                   Size: BYTE; Data: POINTER); ASSEMBLER;
  ASM

        PUSH    BP       { Rellena el segundo font }

        MOV     BL,Font
        MOV     BH,Size
        MOV     CX,NChars
        MOV     DL,First
        XOR     DH,DH
        LES     BP,Data

        MOV     AX,$1110
        CALL    CallInt10

        POP     BP

  END;


PROCEDURE SelectFonts(FontDim, FontBright: BYTE); ASSEMBLER;
  ASM

        MOV     AL,FontDim
        MOV     BL,AL
        AND     AL,100b
        SHL     AL,2
        AND     BL,11b
        OR      BL,AL
        MOV     AL,FontBright
        MOV     AH,AL
        AND     AL,100b
        SHL     AL,3
        OR      BL,AL
        AND     AH,11b
        SHL     AH,2
        OR      BL,AH

        MOV     AX,$1103     { Activa los dos fonts }
        CALL    CallInt10

  END;




{----------------------------------------------------------------------------}
{ Text cursor services.                                                      }
{____________________________________________________________________________}


PROCEDURE NoCursor; ASSEMBLER;
  ASM

        MOV     CX,$700

        MOV     AH,1     
        CALL    CallInt10

  END;


PROCEDURE UnderCursor; ASSEMBLER;
  ASM

        MOV     CX,$607

        MOV     AH,1     
        CALL    CallInt10

  END;


PROCEDURE BlockCursor; ASSEMBLER;
  ASM

        MOV     CX,$007

        MOV     AH,1     
        CALL    CallInt10

  END;


PROCEDURE SetCursor(x, y: BYTE; Page: BYTE); ASSEMBLER;
  ASM

        MOV     DH,y
        MOV     DL,x
        MOV     BH,Page

        MOV     AH,2
        CALL    CallInt10

  END;




{----------------------------------------------------------------------------}
{ Attribute services.                                                        }
{____________________________________________________________________________}


PROCEDURE BlinkOff; ASSEMBLER;
  ASM

        MOV     DX,$3C0
        MOV     AL,$30
        OUT     DX,AL
        INC     DX
        IN      AL,DX
        DEC     DX
        MOV     AH,AL
        MOV     AL,$30
        OUT     DX,AL
        MOV     AL,AH
        AND     AL,11110111b
        OUT     DX,AL
(*
        MOV     AX,$1003 { Quita parpadeo }

        MOV     BH,1
        CALL    CallInt10
*)
  END;


PROCEDURE SetPalette(Palette: POINTER); ASSEMBLER;
  ASM

        LES     DX,Palette 

        MOV     AX,$1002
        CALL    CallInt10

  END;




{----------------------------------------------------------------------------}
{ Miscellaneous services.                                                    }
{____________________________________________________________________________}


PROCEDURE SetVideoPage(Page: BYTE); ASSEMBLER;
  ASM

        MOV     AL,Page

        MOV     AH,$05
        CALL    CallInt10

  END;




{----------------------------------------------------------------------------}
{ Miscellaneous routines.                                                    }
{____________________________________________________________________________}


PROCEDURE FillVideoMemory(Chr: CHAR; Attr: BYTE); ASSEMBLER;
  ASM

        CLD
        MOV     DI,0  
        MOV     AX,$B800
        MOV     ES,AX
        MOV     CX,$4000
        MOV     AH,Attr
        MOV     AL,Chr
        REP STOSW

  END;




END.
