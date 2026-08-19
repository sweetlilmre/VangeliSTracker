{****************************************************************************}
{                                                                            }
{ MODULE:         Filters                                                    }
{                                                                            }
{ DESCRIPTION:    Implements several kinds of fast digital filters.          }
{                 They all are 1st order FIR filters (in case you know what  }
{                 I mean ;-).                                                }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        21-Oct-1992 Documentation                                  }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT Filters;

{$G+}

INTERFACE

TYPE
  { NOTE: A cut-off frequency of PI*X means that the cut-off frequency is
          at f*X/2 where f is the sampling rate. For example, with a
          sampling rate of 20000 Hz, a PI*3/4 means a cut-off frequency of
          7500 Hz.                                                         }

  TFilterMethod = (fmNone, { No filtering.                           }
                   fm7_8,  { Filter with a PI*7/8 cut-off frequency. }
                   fm3_4,  { Filter with a PI*3/4 cut-off frequency. }
                   fm1_2   { Filter with a PI*1/2 cut-off frequency. }
  );

CONST
  FilterMod = ORD(fm1_2) + 1;




FUNCTION FilterChunkWord(VAR Buf; Len, Offs: WORD; Method: TFilterMethod; OldSpl: WORD) : WORD; { Word-sized filter. }
FUNCTION FilterChunkByte(VAR Buf; Len, Offs: WORD; Method: TFilterMethod; OldSpl: WORD) : WORD; { Byte-sized filter. }




IMPLEMENTATION

VAR
  LastSamplesByte : INTEGER;




{----------------------------------------------------------------------------}
{ Word size filters.                                                         }
{____________________________________________________________________________}

PROCEDURE Filter1_2Word; ASSEMBLER;
  ASM
@@lp:    MOV    AX,[ES:DI]
         ADD    BX,AX
         XCHG   BX,AX
         SAR    AX,1
         MOV    [ES:DI],AX
         ADD    DI,SI
         LOOP   @@lp
  END;

PROCEDURE Filter3_4Word; ASSEMBLER;
  ASM
@@lp:    MOV    AX,[ES:DI]
         SAR    BX,1
         ADD    BX,AX
         XCHG   BX,AX

         SAR    AX,1
         MOV    DX,AX
         SAR    AX,2
         ADC    DX,AX
         SAR    AX,2
         ADC    AX,DX

         MOV    [ES:DI],AX
         ADD    DI,SI
         LOOP   @@lp
  END;

PROCEDURE Filter7_8Word; ASSEMBLER;
  ASM
@@lp:    MOV    AX,[ES:DI]
         SAR    BX,2
         ADD    BX,AX
         XCHG   BX,AX

         SAR    AX,1
         MOV    DX,AX
         SAR    AX,1
         ADC    DX,AX
         SAR    AX,3
         ADC    AX,DX

         MOV    [ES:DI],AX
         ADD    DI,SI
         LOOP   @@lp
  END;


FUNCTION FilterChunkWord(VAR Buf; Len, Offs: WORD; Method: TFilterMethod; OldSpl: WORD) : WORD; ASSEMBLER;
  ASM
        MOV     SI,[Offs]
        ADD     SI,SI
        LES     DI,[Buf]
        MOV     BX,[OldSpl]
        MOV     CX,[Len]
        JCXZ    @@Fin
        MOV     AL,[Method]
        CMP     AL,fm1_2
        JNZ     @@1
         CALL   Filter1_2Word
         JMP    @@Fin
@@1:    CMP     AL,fm3_4
        JNZ     @@2
         CALL   Filter3_4Word
         JMP    @@Fin
@@2:    CMP     AL,fm7_8
        JNZ     @@Fin
         CALL   Filter7_8Word
@@Fin:
        MOV     AX,BX
  END;




{----------------------------------------------------------------------------}
{ Byte size filters.                                                         }
{____________________________________________________________________________}

PROCEDURE Filter1_2Byte; ASSEMBLER;
  ASM
@@lp:    MOV    AH,[ES:DI]
         XOR    AL,AL
         SAR    AX,2
         ADD    BX,AX
         XCHG   BX,AX
         SHL    AX,1
         MOV    [ES:DI],AH
         ADD    DI,SI
         LOOP   @@lp
  END;

PROCEDURE Filter3_4Byte; ASSEMBLER;
  ASM
@@lp:    MOV    AL,[ES:DI]
         SAR    BL,1
         ADD    BL,AL
         XCHG   BL,AL

         SAR    AL,1
         MOV    DL,AL
         SAR    AL,2
         ADC    DL,AL
         SAR    AL,2
         ADC    AL,DL

         MOV    [ES:DI],AL
         ADD    DI,SI
         LOOP   @@lp
  END;

PROCEDURE Filter7_8Byte; ASSEMBLER;
  ASM
@@lp:    MOV    AH,[ES:DI]
         XOR    AL,AL
         SAR    AX,2
         SAR    BX,2
         ADD    BX,AX
         XCHG   BX,AX

         SAR    AX,1
         MOV    DX,AX
         SAR    AX,1
         ADC    DX,AX
         SAR    AX,3
         ADC    AX,DX

         SHL    AX,2
         MOV    [ES:DI],AH
         ADD    DI,SI
         LOOP   @@lp
  END;


FUNCTION FilterChunkByte(VAR Buf; Len, Offs: WORD; Method: TFilterMethod; OldSpl: WORD) : WORD; ASSEMBLER;
  ASM
        MOV     SI,[Offs]
        LES     DI,[Buf]
        MOV     BX,[OldSpl]
        MOV     CX,[Len]
        JCXZ    @@Fin
        MOV     AL,[Method]
        CMP     AL,fm1_2
        JNZ     @@1
         CALL   Filter1_2Byte
         JMP    @@Fin
@@1:    CMP     AL,fm3_4
        JNZ     @@2
         CALL   Filter3_4Byte
         JMP    @@Fin
@@2:    CMP     AL,fm7_8
        JNZ     @@Fin
         CALL   Filter7_8Byte
@@Fin:
        MOV     AX,BX
  END;




END.
