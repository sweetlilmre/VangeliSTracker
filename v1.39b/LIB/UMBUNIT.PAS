{****************************************************************************}
{                                                                            }
{ MODULE:         UMBUnit                                                    }
{                                                                            }
{ DESCRIPTION:    Unit that handles dynamic UMB (above the 640 Kb). It uses  }
{                 the MS-DOS 5.0 LINK/UNLINK interface, so it works only     }
{                 with MS-DOS compatible UMB managers (QEMM and the like).   }
{                 It doesn't really manage UMB's by themselves, but links    }
{                 them to the normal DOS MCB chain, and then uses the normal }
{                 48h/49h INT 21 calls, so lost low-memory fragments are     }
{                 also used (that's a bonus, eh? ;-). Care must be taken if  }
{                 a small TP heap is used, as the unused DOS memory can (and }
{                 will) be mistaken as a UMB, when it's not.                 }
{                                                                            }
{                 Also, an advice: never use a DMA buffer in the UMB space,  }
{                 because it must be virtualized and that slows down the     }
{                 response, and the autoinitialized mode will NEVER work at  }
{                 all.                                                       }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        12-Feb-1993 Design and implementation.                     }
{                                                                            }
{ (C) 1992, 1993 VangeliSTeam                                                }
{____________________________________________________________________________}

UNIT UMBUnit;

INTERFACE




FUNCTION  DOSAllocate (VAR Buf: POINTER; Size: LONGINT) : LONGINT;
PROCEDURE DOSFree     (VAR Buf: POINTER);

FUNCTION  UMBLink     (DoLink: BOOLEAN)                 : BOOLEAN;
FUNCTION  UMBAllocate (VAR Buf: POINTER; Size: LONGINT) : LONGINT;
PROCEDURE UMBFree     (VAR Buf: POINTER);




IMPLEMENTATION




FUNCTION DOSAllocate(VAR Buf: POINTER; Size: LONGINT) : LONGINT;
  VAR
    SizeP    : WORD;
  BEGIN
    SizeP := Size SHR 4;

    ASM

        MOV	BX,SizeP
        MOV	AH,$48
        INT	21H
        JNC     @@Ok
        MOV	SizeP,BX
        MOV	AH,$48
        INT	21H
        JNC	@@Ok
        MOV     AX,0
        MOV     SizeP,AX
@@Ok:   LES     DI,Buf
        MOV     [ES:DI+2],AX
        XOR     AX,AX
        MOV     [ES:DI],AX
    END;

    DOSAllocate := LONGINT(SizeP) SHL 4;
  END;


PROCEDURE DOSFree(VAR Buf: POINTER); ASSEMBLER;
  ASM
        LES     DI,Buf
        MOV     AX,[ES:DI+2]
        XOR     BX,BX
        MOV     [ES:DI+2],BX
        MOV     [ES:DI],BX
        MOV     ES,AX
        MOV     AH,$49
        INT     $21
  END;




FUNCTION UMBLink(DoLink: BOOLEAN) : BOOLEAN; ASSEMBLER;
  ASM
        MOV	AX,$5802
        INT	21H
        MOV	AH,0
        JC	@@Fin
        MOV     AH,AL
        PUSH    AX
        MOV	AX,5803H
        XOR	BH,BH			
        MOV     BL,DoLink
        INT	21H			
        POP     AX
@@Fin:
        MOV     AL,AH
  END;


FUNCTION UMBAllocate(VAR Buf: POINTER; Size: LONGINT) : LONGINT;
  VAR
    SaveLink : BOOLEAN;
  BEGIN
    SaveLink    := UMBLink(TRUE);
    UMBAllocate := DOSAllocate(Buf, Size);
    UMBLink(SaveLink);
  END;


PROCEDURE UMBFree(VAR Buf: POINTER);
  VAR
    SaveLink : BOOLEAN;
  BEGIN
    SaveLink := UMBLink(TRUE);
    DOSFree(Buf);
    UMBLink(SaveLink);
  END;




END.