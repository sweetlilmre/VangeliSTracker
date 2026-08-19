P386N



MACRO SumRut Operat

RutSum&Operat&_0:
                RET

RutSum&Operat&_1:
                Sum&Operat&_0    3
                Sum&Operat&_Last

RutSum&Operat&_2:
                Sum&Operat&_0    2
                Sum&Operat&_Last

RutSum&Operat&_3:
                Sum&Operat&_0    2
                Sum&Operat&_1
                Sum&Operat&_Last

RutSum&Operat&_4:
                Sum&Operat&_0    1
                Sum&Operat&_Last

RutSum&Operat&_5:
                Sum&Operat&_0    1
                Sum&Operat&_1
                Sum&Operat&_0    1
                Sum&Operat&_Last

RutSum&Operat&_6:
                Sum&Operat&_0    1
                Sum&Operat&_1
                Sum&Operat&_Last

RutSum&Operat&_7:
                Sum&Operat&_0    1
                Sum&Operat&_1
                Sum&Operat&_1
                Sum&Operat&_Last

RutSum&Operat&_8:
                Sum&Operat&_Last

RutSum&Operat&_9:
                Sum&Operat&_1
                Sum&Operat&_0    2
                Sum&Operat&_Last

RutSum&Operat&_10:
                Sum&Operat&_1
                Sum&Operat&_0    1
                Sum&Operat&_Last

RutSum&Operat&_11:
                Sum&Operat&_1
                Sum&Operat&_0    1
                Sum&Operat&_1
                Sum&Operat&_Last

RutSum&Operat&_12:
                Sum&Operat&_1
                Sum&Operat&_Last

RutSum&Operat&_13:
                Sum&Operat&_1
                Sum&Operat&_1
                Sum&Operat&_0    1
                Sum&Operat&_Last

RutSum&Operat&_14:
                Sum&Operat&_1
                Sum&Operat&_1
                Sum&Operat&_Last

RutSum&Operat&_15:
                Sum&Operat&_1
                Sum&Operat&_1
                Sum&Operat&_1
                Sum&Operat&_Last

RutSum&Operat&_List DW OFFSET RutSum&Operat&_0
                    DW OFFSET RutSum&Operat&_1
                    DW OFFSET RutSum&Operat&_2
                    DW OFFSET RutSum&Operat&_3
                    DW OFFSET RutSum&Operat&_4
                    DW OFFSET RutSum&Operat&_5
                    DW OFFSET RutSum&Operat&_6
                    DW OFFSET RutSum&Operat&_7
                    DW OFFSET RutSum&Operat&_8
                    DW OFFSET RutSum&Operat&_9
                    DW OFFSET RutSum&Operat&_10
                    DW OFFSET RutSum&Operat&_11
                    DW OFFSET RutSum&Operat&_12
                    DW OFFSET RutSum&Operat&_13
                    DW OFFSET RutSum&Operat&_14
                    DW OFFSET RutSum&Operat&_15

ENDM




MACRO SumSubR_Last

        SAR     EBX,1
        SUB     EAX,EBX
        RET

ENDM

MACRO SumSubR_1

        SAR     EBX,1
        SUB     EAX,EBX

ENDM

MACRO SumSubR_0 Num

        SAR     EBX,Num

ENDM

                SumRut  SubR




MACRO SumAddR_Last

        SAR     EBX,1
        ADD     EAX,EBX
        RET

ENDM

MACRO SumAddR_1

        SAR     EBX,1
        ADD     EAX,EBX

ENDM

MACRO SumAddR_0 Num

        SAR     EBX,Num

ENDM

                SumRut  AddR




MACRO SumAddL_Last

        ADD     EAX,EBX
        RET

ENDM

MACRO SumAddL_1

        ADD     EAX,EBX
        SHL     EBX,1

ENDM

MACRO SumAddL_0 Num

        SHL     EBX,Num

ENDM

                SumRut  AddL




OfsTrebleFilterVal_Left   DW RutSumSubR_0
OfsTrebleFilterMult_Left  DW RutSumSubR_0
OfsBassFilterVal_Left     DW RutSumSubR_0
OfsBassFilterMult_Left    DW RutSumSubR_0
OfsTrebleFilterVal_Right  DW RutSumSubR_0
OfsTrebleFilterMult_Right DW RutSumSubR_0
OfsBassFilterVal_Right    DW RutSumSubR_0
OfsBassFilterMult_Right   DW RutSumSubR_0




FlipTabla DB 0000b, 1000b, 0100b, 1100b, 0010b, 1010b, 0110b, 1110b
          DB 0001b, 1001b, 0101b, 1101b, 0011b, 1011b, 0111b, 1111b

MACRO SetFiltValue Band, Operat_Side, Rut

                MOV     AX,[Band&Filter&Operat_Side]
                ADD     AX,AX
                MOV     BX,OFFSET RutSum&Rut&_List
                ADD     BX,AX
                MOV     AX,[CS:BX]
                MOV     [CS:Ofs&Band&Filter&Operat_Side],AX

ENDM

MACRO SetFiltValueFlip Band, Operat_Side, Rut

                MOV     AX,[Band&Filter&Operat_Side]
                MOV     BX,OFFSET FlipTabla
                ADD     BX,AX
                MOV     AL,[CS:BX]
                ADD     AX,AX
                MOV     BX,OFFSET RutSum&Rut&_List
                ADD     BX,AX
                MOV     AX,[CS:BX]
                MOV     [CS:Ofs&Band&Filter&Operat_Side],AX

ENDM

SetFilterValues:
                SetFiltValue     Treble, Val_Left,   SubR
                SetFiltValueFlip Treble, Mult_Left,  AddL
                SetFiltValue     Bass,   Val_Left,   AddR
                SetFiltValueFlip Bass,   Mult_Left,  AddL
                SetFiltValue     Treble, Val_Right,  SubR
                SetFiltValueFlip Treble, Mult_Right, AddL
                SetFiltValue     Bass,   Val_Right,  AddR
                SetFiltValueFlip Bass,   Mult_Right, AddL

                RET



; ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿
; ³                                                                          ³
; ³ MACRO: BassPower                                                         ³
; ³                                                                          ³
; ³ Macro that implements the bass-power equalicer filter.                   ³
; ³                                                                          ³
; ³ IN:  AX    = 16 bit sample.                                              ³
; ³      Side  = Left or Right. For mono, use Left.                          ³
; ³                                                                          ³
; ³ OUT: idem.                                                               ³
; ³                                                                          ³
; ³ MODIFIES: AX, BX, CX, DX                                                 ³
; ³                                                                          ³
; ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ

MACRO BassPower Side

        CWDE
        MOV     ECX,EAX

        MOV     EBX,0FFFFFFFFh
@@Data11:
        CALL    [CS:OfsTrebleFilterVal_&Side]
        MOV     [DWORD PTR CS:@@Data11-4],EAX
        MOV     EBX,EAX
        CALL    [CS:OfsTrebleFilterMult_&Side]
        
        XCHG    ECX,EAX

        MOV     EBX,0FFFFFFFFh
@@Data21:
        CALL    [CS:OfsBassFilterVal_&Side]
        MOV     [DWORD PTR CS:@@Data21-4],EAX
        MOV     EBX,EAX
        CALL    [CS:OfsBassFilterMult_&Side]

        ADD     EAX,ECX

        SAR     EAX,2

        CMP     EAX,32768
        JNC     SHORT @@satur
@@hecho:

MASM
COMMENT %
        MOV     DX,0FFFFh
@@lastdata:
        MOV     BX,DX
        SUB     DX,AX
        ADD     DX,16
        AND     DX,-32
        JNZ     SHORT @@nonext
         MOV    AX,BX
@@nonext:
        MOV     DX,AX
        MOV     [WORD PTR CS:@@lastdata-2],DX
%
IDEAL
;MOV DX,AX
;        MOV     AX,DX
        RET

@@satur:
        CMP     EAX,-32768
        JNC     SHORT @@hecho
        AND     EAX,EAX
        JS      SHORT @@up
         MOV    EAX,32767
        JMP     SHORT @@hecho
@@up:    MOV    EAX,-32768
        JMP     SHORT @@hecho

ENDM BassPower

; ---------------------------------------------------------------------------

BassPower_Left:  BassPower Left

BassPower_Right: BassPower Right

; ---------------------------------------------------------------------------

BassPowerMono   EQU     BassPower_Left

; ---------------------------------------------------------------------------

BassPowerStereo:
                PUSH    BX
                CALL    BassPower_Left
                POP     BX
                PUSH    AX
                MOV     AX,BX
                CALL    BassPower_Right
                MOV     BX,AX
                POP     AX
                RET



P286N
