{****************************************************************************}
{                                                                            }
{ MODULE:         Hardware                                                   }
{                                                                            }
{ DESCRIPTION:    An UNIT that provides general support to generic Hardware, }
{                 like the PIC, the DMA controller, etc...                   }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        18-Nov-1992 Documentation.                                 }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT Hardware;

INTERFACE




PROCEDURE EnableIRQ   (i: WORD);
PROCEDURE DisableIRQ  (i: WORD);
FUNCTION  IRQState    (i: WORD)               : BOOLEAN;
FUNCTION  SetIRQVector(i: WORD; Vec: POINTER) : POINTER;

PROCEDURE DMASet   (Channel, Mode: WORD; Buf: POINTER; Size: WORD);
PROCEDURE DMARawSet(Channel, Mode, Page: BYTE; Offs, Size: WORD);
PROCEDURE DMASetAsm;

PROCEDURE DMAReset(Channel: BYTE);
PROCEDURE DMAResetAsm;

FUNCTION  GetDMACount(Channel: BYTE) : WORD;
FUNCTION  GetDMACountAsm             : WORD; 




IMPLEMENTATION

USES Dos, Debugging;




{----------------------------------------------------------------------------}
{ PIC routines.                                                              }
{____________________________________________________________________________}

PROCEDURE EnableIRQ(i: WORD);
  BEGIN
    IF i < 8 THEN
      PORT[$21] := PORT[$21] AND (NOT (1 SHL i))
    ELSE
      BEGIN
        PORT[$A1] := PORT[$A1] AND (NOT (1 SHL (i-8)));
        PORT[$21] := PORT[$21] AND (NOT (1 SHL 2))
      END;
  END;


PROCEDURE DisableIRQ(i: WORD);
  BEGIN
    IF i < 8 THEN
      PORT[$21] := PORT[$21] OR (1 SHL i)
    ELSE
      BEGIN
        PORT[$A1] := PORT[$A1] OR (1 SHL (i-8))
      END;
  END;


FUNCTION IRQState(i: WORD) : BOOLEAN;
  BEGIN
    IF i < 8 THEN
      IRQState := (PORT[$21] AND (1 SHL i)) = 0
    ELSE
      IRQState := ((PORT[$21] AND 4)             = 0) AND
                  ((PORT[$A1] AND (1 SHL (i-8))) = 0);
  END;


FUNCTION SetIRQVector(i: WORD; Vec: POINTER) : POINTER;
  VAR
    p : POINTER;
    j : WORD;
  BEGIN
    IF i < 8 THEN j := i + $08
             ELSE j := i + $68;

    GetIntVec(j, p);
    SetIntVec(j, Vec);
    SetIRQVector := p;
  END;




{----------------------------------------------------------------------------}
{ DMA routines.                                                              }
{____________________________________________________________________________}

{
  AH = Channel
  CH = Mode
  CL = Page
  BX = Offset
  SI = Size
}

PROCEDURE DMA16Set; ASSEMBLER;
  CONST
    PageRegTable : ARRAY[0..3] OF WORD = ( $00, $8B, $89, $8A );
  ASM

        AND     AH,3

        SHR     CL,1
        RCR     BX,1
        ADD     CL,CL

        MOV  AL,AH;  ADD  AL,$04; OUT $D4,AL     { Disable DMA channel.                         }
        XOR  AL,AL;               OUT $D8,AL     { Clear BYTE POINTER flip-flop to lower byte.  }
        MOV  AL,AH;  ADD  AL,CH;  OUT $D6,AL     { DMA Mode register.                           }
        XOR  DH,DH
        MOV  DL,AH
        ADD  DX,DX                               
        ADD  DX,DX                               { Calculate DMA base port.                     }
        ADD  DX,$C0

        MOV  AL,BL;               OUT  DX,AL     { Offset of the buffer, low & high bytes.      }
        MOV  AL,BH;               OUT  DX,AL             

        PUSH DX

        MOV  DL,AH
        ADD  DX,DX                               
        MOV  BX,OFFSET PageRegTable
        ADD  BX,DX                               { Calculate page register port.                }
        MOV  DX,[BX]
        MOV  AL,CL;               OUT  DX,AL     { Set DMA page.                                }

        POP  DX
        INC  DX
        INC  DX                                  { Calculate DMA counter port.                  }

        MOV  BX,SI
        MOV  AL,BL;               OUT  DX,AL     { Size of the buffer minus 1, low & high byte. }
        MOV  AL,BH;               OUT  DX,AL             
        MOV  AL,AH;               OUT $D4,AL     { Enable DMA channel.                          }

  END;


PROCEDURE DMA8Set; ASSEMBLER;
  CONST
    PageRegTable : ARRAY[0..3] OF WORD = ( $87, $83, $81, $82 );
  ASM

        MOV  AL,AH;  ADD  AL,$04; OUT  $A,AL     { Disable DMA channel.                         }
        XOR  AL,AL;               OUT  $C,AL     { Clear BYTE POINTER flip-flop to lower byte.  }
        MOV  AL,AH;  ADD  AL,CH;  OUT  $B,AL     { DMA Mode register.                           }
        XOR  DH,DH
        MOV  DL,AH
        ADD  DX,DX                               { Calculate DMA base port.                     }

        MOV  AL,BL;               OUT  DX,AL     { Offset of the buffer, low & high bytes.      }
        MOV  AL,BH;               OUT  DX,AL             

        PUSH DX

        MOV  BX,OFFSET PageRegTable
        ADD  BX,DX                               { Calculate page register port.                }
        MOV  DX,[BX]
        MOV  AL,CL;               OUT  DX,AL     { Set DMA page.                                }

        POP  DX
        INC  DX                                  { Calculate DMA counter port.                  }

        MOV  BX,SI
        MOV  AL,BL;               OUT  DX,AL     { Size of the buffer minus 1, low & high byte. }
        MOV  AL,BH;               OUT  DX,AL             
        MOV  AL,AH;               OUT  $A,AL     { Enable DMA channel.                          }

  END;


PROCEDURE DMA16Reset; ASSEMBLER;
  ASM

        AND     AH,3

        MOV  AL,AH;  ADD  AL,$04; OUT $D4,AL     { Disable DMA channel.                         }

  END;


PROCEDURE DMA8Reset; ASSEMBLER;
  ASM

        MOV  AL,AH;  ADD  AL,$04; OUT  $A,AL     { Disable DMA channel.                         }

  END;


FUNCTION GetDMA16Count : WORD; ASSEMBLER;
  ASM

        AND     AH,3

        XOR  AL,AL;               OUT $D8,AL     { Clear BYTE POINTER flip-flop to lower byte.  }

        XOR  DH,DH
        MOV  DL,AH
        ADD  DX,DX                               
        ADD  DX,DX                               { Calculate DMA base port.                     }
        ADD  DX,$C2

        IN   AL,DX;               MOV  BL,AL     { Size of the buffer minus 1, low & high byte. }
        IN   AL,DX;               MOV  BH,AL

        MOV  AX,BX

  END;


FUNCTION GetDMA8Count : WORD; ASSEMBLER;
  ASM

        XOR  AL,AL;               OUT  $C,AL     { Clear BYTE POINTER flip-flop to lower byte.  }

        XOR  DH,DH
        MOV  DL,AH
        ADD  DX,DX                               { Calculate DMA base port.                     }
        INC  DX

        IN   AL,DX;               MOV  BL,AL     { Size of the buffer minus 1, low & high byte. }
        IN   AL,DX;               MOV  BH,AL
        MOV  CX,BX

        IN   AL,DX;               MOV  BL,AL     { Size of the buffer minus 1, low & high byte. }
        IN   AL,DX;               MOV  BH,AL

        MOV  AX,BX

        MOV  SI,CX
        SUB  SI,BX
        CMP  SI,5
        JC   @@ya
        MOV  AX,CX
        CMP  SI,260
        JC   @@ya
        MOV  AX,BX
        CMP  SI,$FF01
        JNC  @@ya

        MOV  AX,$FFFF
@@ya:
(*
        PUSH    AX

        MOV  DL,[Debug]
        PUSH DX
        MOV  DL,1
        MOV  [Debug],DL

        PUSH AX
        PUSH BX

        PUSH CX
        PUSH $7
        CALL WriteSNum

        POP  BX

        PUSH BX
        PUSH $6
        CALL WriteSNum

        POP  AX

        PUSH AX
        PUSH $4
        CALL WriteSNum

        POP  DX
        MOV  [Debug],DL

        POP     AX
*)
(*
        CMP  SI,DI    { Get the value that repeats. }
        JZ   @@ya

        MOV  AL,[Debug]
        PUSH AX
        MOV  AL,1
        MOV  [Debug],AL

        PUSH BX
        PUSH DI

        PUSH SI
        PUSH $7
        CALL WriteSNum

        POP  DI

        PUSH DI
        PUSH $6
        CALL WriteSNum

        POP  BX
        PUSH BX

        PUSH BX
        PUSH $5
        CALL WriteSNum

        POP  BX

        POP  AX
        MOV  [Debug],AL

        MOV  SI,BX

@@ya:   MOV  AX,SI
*)
  END;



FUNCTION GetDMACountAsm : WORD; ASSEMBLER;
  ASM

                CMP     AH,2
                JZ      @@Fin
                CMP     AH,4
                JZ      @@Fin
                JB      @@8bit
                 CALL   GetDMA16Count
                JMP    @@Fin
@@8bit:          CALL   GetDMA8Count

@@Fin:

  END;


PROCEDURE DMASetAsm; ASSEMBLER;
  ASM

                CMP     AH,2
                JZ      @@Fin
                CMP     AH,4
                JZ      @@Fin
                JB      @@8bit
                 CALL   DMA16Set
                JMP    @@Fin
@@8bit:          CALL   DMA8Set

@@Fin:

  END;


PROCEDURE DMAResetAsm; ASSEMBLER;
  ASM

                CMP     AH,2
                JZ      @@Fin
                CMP     AH,4
                JZ      @@Fin
                JB      @@8bit
                 CALL   DMA16Reset
                JMP    @@Fin
@@8bit:          CALL   DMA8Reset

@@Fin:

  END;


PROCEDURE DMARawSet(Channel, Mode, Page: BYTE; Offs, Size: WORD); ASSEMBLER;
  ASM

        MOV     AH,[Channel]
        MOV     CH,[Mode]
        MOV     CL,[Page]
        MOV     BX,[Offs]
        MOV     SI,[Size]

        CALL    DMASetAsm

  END;


FUNCTION GetDMACount(Channel: BYTE) : WORD; ASSEMBLER;
  ASM

        MOV     AH,[Channel]

        CALL    GetDMACountAsm

  END;


PROCEDURE DMASet(Channel, Mode: WORD ; Buf: POINTER; Size: WORD);
  VAR
    Segm : WORD;
    Offs : WORD;
  BEGIN

    Segm := SEG(Buf^) AND $F000;
    Offs := SEG(Buf^) AND $0FFF;

    IF Offs > 65535 - OFS(Buf^) THEN
      BEGIN
        INC(Segm, $1000);
        Offs := WORD(Offs - 65536 + OFS(Buf^));
      END
    ELSE
      BEGIN
        Offs := Offs + OFS(Buf^);
      END;

    DEC(Size);

    DMARawSet(Channel, Mode, Segm SHR 12, Offs, Size);

  END;


PROCEDURE DMAReset(Channel: BYTE); ASSEMBLER;
  ASM

        MOV     AH,[Channel]

        CALL    DMAResetAsm

  END;




END.
