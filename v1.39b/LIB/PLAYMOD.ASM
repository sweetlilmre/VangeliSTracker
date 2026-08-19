                IDEAL
                MODEL  COMPACT
                LOCALS @@
                JUMPS

                P386

MACRO SetBorder r,g,b
MASM
COMMENT %
        PUSH    AX DX

        MOV     DX,3C8h
        XOR     AL,AL
        OUT     DX,AL
        INC     DX
      IFDIF <&r>,<0>
        MOV     AL,&r
      ENDIF
        OUT     DX,AL
      IFDIF <&g>,<&r>
        MOV     AL,&g
      ENDIF
        OUT     DX,AL
      IFDIF <&b>,<&g>
        MOV     AL,&b
      ENDIF
        OUT     DX,AL

        POP     DX AX
%
IDEAL
ENDM



MACRO DefLabel Name, Num
Name&Num:
ENDM



                CODESEG




;
;  DS:SI.BP = Src  pos.     -> DS:SI.BP
;  ES:DI    = Dest pos.     -> ES:DI
;  CH.DX    = Src Incr.     -> DX:mem
;  CL       = Volume.       -> CL
;  BX       = Dest Incr.    -> BX
;  AX       = Loop Len.     -> CH*8
;

DumpRaw:
;SetBorder 64, 64, 64

                MOV     [WORD PTR CS:dl_data_0-2],DX
                MOV     [WORD PTR CS:dl_data_1-2],DX
                MOV     [WORD PTR CS:dl_data_2-2],DX
                MOV     [WORD PTR CS:dl_data_3-2],DX
                MOV     [WORD PTR CS:dl_data_4-2],DX
                MOV     [WORD PTR CS:dl_data_5-2],DX
                MOV     [WORD PTR CS:dl_data_6-2],DX
                MOV     [WORD PTR CS:dl_data_7-2],DX

                MOV     DL,CH
                XOR     DH,DH

                MOV     CH,AL
                ADD     AX,7
                SHR     AX,3
                XCHG    AL,CH
                AND     AL,7
                JZ      SHORT DumpLoop
                NEG     AL
                AND     AL,7
                MOV     AH,DumpLoopSize
                MUL     AH
                ADD     AX,OFFSET DumpLoop

;                MOV     CX,1000
;                LOOP    $

;SetBorder 0, 0, 0
;RET

                JMP     AX

DumpLoop:

count = 0

        REPT 8

                MOV     AL,[SI]
                IMUL    CL
                MOV     [WORD PTR ES:DI],AX
                ADD     DI,BX
                ADD     BP,4321h
            DefLabel    dl_data_, %count
                ADC     SI,DX

count = count + 1

        ENDM

DumpLoopSize = ($ - DumpLoop) / 8

                DEC     CH
                JNZ     SMALL DumpLoop

                RETN




;
;  DS:SI.BP = Src  pos.     -> DS:SI.BP
;  ES:DI    = Dest pos.     -> ES:DI
;  CH.DX    = Src Incr.     -> DX:mem
;  CL       = Volume.       -> CL
;  BX       = Dest Incr.    -> BX
;  AX       = Loop Len.     -> CH*16
;

EmptyRaw:
                PUSH    AX
                SHR     CH,1
                RCR     DX,1
                SHR     CH,1
                RCR     DX,1
                SHR     CH,1
                RCR     DX,1
                SHR     CH,1
                RCR     DX,1
                MUL     DX
                SHL     AX,1
                RCL     DX,1
                SHL     AX,1
                RCL     DX,1
                SHL     AX,1
                RCL     DX,1
                SHL     AX,1
                RCL     DX,1
                ADD     BP,AX
                ADC     SI,DX

                POP     AX

                MOV     CH,AL
                ADD     AX,15
                SHR     AX,4
                XCHG    AL,CH
                AND     AL,15
                JZ      SHORT EmptyLoop
                NEG     AL
                AND     AL,15
                MOV     AH,EmptyLoopSize
                MUL     AH
                ADD     AX,OFFSET EmptyLoop

                MOV     DX,AX

                XOR     AX,AX
                JMP     DX

EmptyLoop:
                REPT 16
                 MOV    [ES:DI],AX
                 ADD    DI,BX
                ENDM

EmptyLoopSize = ($ - EmptyLoop) / 16

                DEC     CH
                JNZ     SHORT EmptyLoop

                RETN




; FUNCTION DumpInstrument(VAR {Pointer} Src; VAR {Pointer} Dest; Volume: BYTE;
;                         Step: WORD; SrcLimit, Max, ChanAdd: WORD) : WORD;

PUBLIC DumpInstrument
PROC   DumpInstrument PASCAL FAR Src: DWORD, Dest: DWORD, Volume: BYTE, Step: WORD, SrcLimit: WORD, Max: WORD, ChanAdd: WORD

                MOV     CH,[Volume]
                AND     CH,CH
                JZ      DumpEmptyIn

                MOV     CX,[Step]
                AND     CX,CX
                JZ      DumpEmptyIn
DumpInsIn:
                PUSH    SI
                PUSH    DI

                LES     DI,[Src]

                MOV     AX,[Step]
                AND     AX,AX
                JZ      SHORT @@long

                MOV     DX,[Max]
                SHL     DX,4
                MUL     DX

                ADD     AX,[ES:DI]
                ADC     DX,[ES:DI+2]
                JC      @@short
                CMP     DX,[SrcLimit]
                JNC     @@short

@@long:
                PUSH    DS
                PUSH    BP

                LDS     SI,[ES:DI+2]
                MOV     AX,[ES:DI]
                PUSH    AX
                LES     DI,[Dest]
                LES     DI,[ES:DI]

                MOV     CL,[Volume]
                MOV     DX,[Step]
                MOV     CH,DH
                SHR     CH,4
                SHL     DX,4
                MOV     AX,[Max]
                MOV     BX,[ChanAdd]

;SetBorder 63, 0, 63

                POP     BP
                CALL    DumpRaw

;SetBorder 63, 32, 0

                MOV     DX,BP

                POP     BP
                POP     DS

                LES     BX,[Src]
                MOV     [ES:BX],DX
                MOV     [ES:BX+2],SI

                LES     BX,[Dest]
                MOV     [ES:BX],DI

                XOR     AX,AX

                POP     DI
                POP     SI
                RET


@@short:
                MOV     DX,[SrcLimit]
                XOR     AX,AX
                SUB     AX,[ES:DI]
                SBB     DX,[ES:DI+2]
                JC      @@nomues

                SHR     DX,1
                RCR     AX,1
                SHR     DX,1
                RCR     AX,1
                SHR     DX,1
                RCR     AX,1
                SHR     DX,1
                RCR     AX,1

                DIV     [Step]
                AND     DX,DX
                JZ      SHORT @@cc
                 INC    AX
@@cc:
                AND     AX,AX
                JNZ     @@c6

@@nomues:
                MOV     AX,[Max]

                POP     DI
                POP     SI
                RET
@@c6:
                CMP     AX,[Max]
                JC      SHORT @@c5
                 MOV    AX,[Max]
@@c5:

                PUSH    AX

                PUSH    DS
                PUSH    BP

                LDS     SI,[ES:DI+2]
                MOV     BX,[ES:DI]
                PUSH    BX
                LES     DI,[Dest]
                LES     DI,[ES:DI]

                MOV     CL,[Volume]
                MOV     DX,[Step]
                MOV     CH,DH
                SHR     CH,4
                SHL     DX,4
                MOV     BX,[ChanAdd]

                POP     BP

SetBorder 63, 63, 63

                CALL    DumpRaw

SetBorder 0, 0, 0

                MOV     DX,BP

                POP     BP
                POP     DS

                LES     BX,[Src]
                MOV     [ES:BX],DX
                MOV     [ES:BX+2],SI

                LES     BX,[Dest]
                MOV     [ES:BX],DI

                POP     CX

                MOV     AX,[Max]
                SUB     AX,CX

                POP     DI
                POP     SI
                RET

ENDP




; FUNCTION DumpEmpty(VAR {Pointer} Src; VAR {Pointer} Dest; Volume: BYTE;
;                    Step: WORD; SrcLimit, Max, ChanAdd: WORD) : WORD;

PUBLIC DumpEmpty
PROC   DumpEmpty PASCAL FAR Src: DWORD, Dest: DWORD, Volume: BYTE, Step: WORD, SrcLimit: WORD, Max: WORD, ChanAdd: WORD

DumpEmptyIn:

                PUSH    SI
                PUSH    DI

                LES     DI,[Src]

                MOV     AX,[Step]
                AND     AX,AX
                JZ      SHORT @@long

                MOV     DX,[Max]
                SHL     DX,4
                MUL     DX

                ADD     AX,[ES:DI]
                ADC     DX,[ES:DI+2]
                JC      @@short
                CMP     DX,[SrcLimit]
                JNC     @@short

@@long:
                PUSH    DS
                PUSH    BP

                LDS     SI,[ES:DI+2]
                MOV     AX,[ES:DI]
                PUSH    AX
                LES     DI,[Dest]
                LES     DI,[ES:DI]

                MOV     CL,[Volume]
                MOV     DX,[Step]
                MOV     CH,DH
                SHR     CH,4
                SHL     DX,4
                MOV     AX,[Max]
                MOV     BX,[ChanAdd]

                POP     BP
                CALL    EmptyRaw

;SetBorder 63, 32, 0

                MOV     DX,BP

                POP     BP
                POP     DS

                LES     BX,[Src]
                MOV     [ES:BX],DX
                MOV     [ES:BX+2],SI

                LES     BX,[Dest]
                MOV     [ES:BX],DI

                XOR     AX,AX

                POP     DI
                POP     SI
                RET


@@short:
                MOV     DX,[SrcLimit]
                XOR     AX,AX
                SUB     AX,[ES:DI]
                SBB     DX,[ES:DI+2]
                JC      @@nomues

                SHR     DX,1
                RCR     AX,1
                SHR     DX,1
                RCR     AX,1
                SHR     DX,1
                RCR     AX,1
                SHR     DX,1
                RCR     AX,1

                DIV     [Step]
                AND     DX,DX
                JZ      SHORT @@cc
                 INC    AX
@@cc:
                AND     AX,AX
                JNZ     @@c6

@@nomues:
                MOV     AX,[Max]

                POP     DI
                POP     SI
                RET
@@c6:
                CMP     AX,[Max]
                JC      SHORT @@c5
                 MOV    AX,[Max]
@@c5:

                PUSH    AX

                PUSH    DS
                PUSH    BP

                LDS     SI,[ES:DI+2]
                MOV     BX,[ES:DI]
                PUSH    BX
                LES     DI,[Dest]
                LES     DI,[ES:DI]

                MOV     CL,[Volume]
                MOV     DX,[Step]
                MOV     CH,DH
                SHR     CH,4
                SHL     DX,4
                MOV     BX,[ChanAdd]

                POP     BP

SetBorder 63, 63, 63

                CALL    EmptyRaw

SetBorder 0, 0, 0

                MOV     DX,BP

                POP     BP
                POP     DS

                LES     BX,[Src]
                MOV     [ES:BX],DX
                MOV     [ES:BX+2],SI

                LES     BX,[Dest]
                MOV     [ES:BX],DI

                POP     CX

                MOV     AX,[Max]
                SUB     AX,CX

                POP     DI
                POP     SI
                RET

ENDP




END
