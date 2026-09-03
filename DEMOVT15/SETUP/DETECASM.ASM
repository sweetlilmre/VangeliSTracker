        IDEAL
        MODEL TPASCAL
        P386

        CODESEG
        PUBLIC Is386, IsProtMode, HasMouse

PROC Is386
        PUSHF
        MOV     AX,7000h
        PUSH    AX
        POPF
        PUSHF
        POP     AX
        AND     AX,7000h
        JZ      @@ok
         MOV    AX,1
    @@ok:
        POPF
        RET
ENDP

PROC IsProtMode
        SMSW    AX
        AND     AX,1
        RET
ENDP

PROC HasMouse
        XOR     AX,AX
        MOV     ES,AX
        MOV     AX,[ES:33h*4]
        OR      AX,[ES:33h*4+2]
        JZ      @@ret
        XOR     AX,AX
        INT     33h
@@ret:  RET
ENDP

END
