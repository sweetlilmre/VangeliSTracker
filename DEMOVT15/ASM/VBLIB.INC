; ------------------------ VBLIB.INC ---------------------

        .CODE


FullFrame   DW ?                ; Total timerticks for a frame.
UsualFrame  DW ?                ; Ticks to program the timer for a frame.
HalfFrame   DW ?                ; ... to reach the midframe point.
SecFrame    DW ?                ; ... from midframe point to retrace.

OldTimerOFF DW ?                ; DOS values.
OldTimerSEG DW ?

VBLCounter   DW ?                ; Frame counter.
VBLVSyncOldV DW ?                ; Alternate frame ctr. for VBLVSync.

SecTimerAct DB ?                ; Indicates the presence of a sec. timer.
WasFullTick DB ?                ; Set to 0 by half frame handler.
VBLActive   DB ?                ; = 0: Ignore the timer INT.

VBLHalfHandler DW OFFSET RetValue ; Routine for the half frame.
VBLFullHandler DW OFFSET RetValue ; Routine for the full frame.


; --------------------------------------------------
; VBL Timer handler. Calls subhandlers and sets
; timers. First, a do-nothing IRQ handler for
; the times when you don't want to relaunch the
; timer (when setting it, for example).

TimerVBLEmpty:
        PUSH    AX
TimerVBLDoNothing:
        MOV     AL,20h                  ; Signal EOI.
        OUT     20h,AL
        POP     AX
        IRET
; --------------------------------------------------
TimerVBL:
        CLI
        PUSH    AX
        MOV     AL,CS:[VBLActive]
        OR      AL,AL
        JZ      TimerVBLDoNothing
        PUSH    ES
        PUSH    DX

        SetBorder 63, 0, 0
        MOV     AL,20h                  ; Signal EOI.
        OUT     20h,AL      
        XOR     AL,AL
        CMP     AL,CS:[SecTimerAct]
        JZ      @@EndFrame              ; JMP if no sec. timer.
        CMP     AL,CS:[WasFullTick]
        JZ      @@EndFrame              ; Or if it's the full timer.
        MOV     CS:[WasFullTick],AL

        MOV     AL,36h
        OUT     43h,AL
        MOV     AX,CS:[SecFrame]
        OUT     40h,AL
        MOV     AL,AH
        OUT     40h,AL

        XOR     AX,AX
        MOV     ES,AX
        MOV     WORD PTR ES:[8*4],OFFSET TimerVBLEmpty
        STI
        ; Way to go!!
        CALL    CS:[VBLHalfHandler]
        SetBorder 0, 0, 0
        CLI
        MOV     WORD PTR ES:[8*4],OFFSET TimerVBL
        POP     DX
        POP     ES
        POP     AX
        IRET         

   @@EndFrame:
        VSync
        INC     CS:[VBLCounter]
        MOV     CS:[WasFullTick],1
        MOV     DX,CS:[HalfFrame]
        CMP     CS:[SecTimerAct],0
        JNZ     @@justfull
         MOV    DX,CS:[UsualFrame]
   @@justfull:
        MOV     AL,36h
        OUT     43h,AL
        MOV     AX,DX
        OUT     40h,AL
        MOV     AL,AH
        OUT     40h,AL

        XOR     AX,AX
        MOV     ES,AX
        MOV     WORD PTR ES:[8*4],OFFSET TimerVBLEmpty
        STI

        ; Way to go!!
        CALL    CS:[VBLFullHandler]
        SetBorder 0, 0, 0
        CLI
        MOV     WORD PTR ES:[8*4],OFFSET TimerVBL
        POP     DX
        POP     ES
        POP     AX
        IRET         


; --------------------------------------------------
; SI = Scan lines till secondary timer.
;      0 means no secondary timer.
;  (still have to test repeated calls to Calculate)

InitializeTimerVBL:
        XOR     AX,AX
        MOV     CS:[VBLCounter],AX
        MOV     CS:[VBLVSyncOldV],AX
        MOV     ES,AX
        MOV     AX,ES:[8*4]
        MOV     WORD PTR CS:[OldTimerOFF],AX
        MOV     AX,ES:[8*4+2]
        MOV     WORD PTR CS:[OldTimerSEG],AX

; --------------------------------------------------

CalculateTimerVBL:
        IN      AL,21h
        PUSH    AX
        OR      AL,1
        OUT     21h,AL
        CLI
        MOV     AL,36h
        OUT     43h,AL
        XOR     AL,AL
        OUT     40h,AL
        XOR     AL,AL
        OUT     40h,AL
        MOV     CS:[SecTimerAct],AL
        MOV     CS:[VBLActive],AL
        MOV     CS:[WasFullTick],AL

        XOR     AX,AX
        MOV     ES,AX
        MOV     AX,OFFSET TimerVBL
        MOV     ES:[8*4],AX
        MOV     ES:[8*4+2],CS
        VSync

        MOV     AL,36h
        OUT     43h,AL
        XOR     AL,AL
        OUT     40h,AL
        XOR     AL,AL
        OUT     40h,AL
        VSync
        XOR     AL,AL
        OUT     43h,AL
        IN      AL,40h
        MOV     AH,AL
        IN      AL,40h
        XCHG    AL,AH
        NEG     AX
        SHR     AX,1
        MOV     CS:[FullFrame],AX
        DEC     AH
        MOV     CS:[UsualFrame],AX
        MOV     BX,AX
        OR      SI,SI
        JZ      @@nohalf

        MOV     AX,CS:[FullFrame]
        MOV     CX,SI
        ADD     CX,35                  ; >>>> Value Warning <<<<
        MUL     CX                     ; Might change with the videomode.
        MOV     CX,449                 ; >>>> Value Warning <<<<
        DIV     CX
        MOV     DX,BX
        SUB     DX,AX
        MOV     CS:[HalfFrame],AX
        MOV     CS:[SecFrame],DX
        MOV     CS:[SecTimerAct],1
   @@nohalf:
        MOV     AL,36h
        OUT     43h,AL
        MOV     AL,BL
        OUT     40h,AL
        MOV     AL,BH
        OUT     40h,AL
        POP     AX
        OUT     21h,AL
        MOV     CS:[VBLActive],1
        STI
RetValue:
        RET


; --------------------------------------------------
; When going back to DOS.
; To switch timer off w/o reseting OldTimer,
; just mask off bit #0 of port 21h.


EndTimerVBL:
        CLI
        XOR     AX,AX
        MOV     ES,AX
        MOV     AX,WORD PTR CS:[OldTimerOFF]
        MOV     ES:[8*4],AX
        MOV     AX,WORD PTR CS:[OldTimerSEG]
        MOV     ES:[8*4+2],AX
        STI
        MOV     AL,36h
        OUT     43h,AL
        XOR     AL,AL
        OUT     40h,AL
        XOR     AL,AL
        OUT     40h,AL
        RET


; ------------------------
; Special VSync that waits until a frame (at least) has
; occured since you last called it.
; I.e. if you call it every other frame, it won't wait. :-)
                                                          
VBLVSync:
        MOV     DX,CS:[VBLVSyncOldV]
    @@w:
        CMP     DX,CS:[VBLCounter]
        JZ      @@w
        MOV     AX,CS:[VBLCounter]
        SUB     AX,DX
        MOV     DX,CS:[VBLCounter]
        MOV     CS:[VBLVSyncOldV],DX
        RET


; ------------------------
; Special VSync that waits until two frames (at least) have
; occured since you last called it.
; I.e. if you call it every three frames, it won't wait. :-)
                                                          
VBLVSync2:
    @@w:
        MOV     DX,CS:[VBLCounter]
        SUB     DX,CS:[VBLVSyncOldV]
        CMP     DX,2
        JC      @@w
        MOV     AX,DX
        MOV     DX,CS:[VBLCounter]
        MOV     CS:[VBLVSyncOldV],DX
        RET


; ------------------------
; Special VSync that waits until AX frames (at least) have
; occured since you last called it.
; I.e. if you call it every AX+1 frames, it won't wait. :-)
                                                          
VBLVSyncAX:
    @@w:
        MOV     DX,CS:[VBLCounter]
        SUB     DX,CS:[VBLVSyncOldV]
        CMP     DX,AX
        JC      @@w
        MOV     AX,DX
        MOV     DX,CS:[VBLCounter]
        MOV     CS:[VBLVSyncOldV],DX
        RET


; -----------------------
; Restore system time from CMOS registers.
; Just to be nice.

RestoreSystemTime:
       XOR     AL,AL
       OUT     70h,AL
       IN      AL,71h
       MOV     DH,AL
       AND     DH,15
       SHR     AL,4
       MOV     DL,10
       MUL     DL
       ADD     DH,AL

       MOV     AL,2
       OUT     70h,AL
       IN      AL,71h
       MOV     CL,AL
       AND     CL,15
       SHR     AL,4
       MOV     DL,10
       MUL     DL
       ADD     CL,AL

       MOV     AL,4
       OUT     70h,AL
       IN      AL,71h
       MOV     CH,AL
       AND     CH,15
       SHR     AL,4
       MOV     DL,10
       MUL     DL
       ADD     CH,AL

       XOR     DL,DL
       MOV     AH,2Dh
       INT     21h

       MOV     AL,7
       OUT     70h,AL
       IN      AL,71h
       MOV     DL,AL
       AND     DL,15
       SHR     AL,4
       MOV     CH,10
       MUL     CH
       ADD     DL,AL

       MOV     AL,8
       OUT     70h,AL
       IN      AL,71h
       MOV     DH,AL
       AND     DH,15
       SHR     AL,4
       MOV     CH,10
       MUL     CH
       ADD     DH,AL

       MOV     AL,4
       OUT     70h,AL
       IN      AL,71h
       MOV     CL,AL
       AND     CL,15
       SHR     AL,4
       MOV     CH,10
       MUL     CH
       ADD     CL,AL

       XOR     CH,CH
       ADD     CX,1900
       MOV     AH,2Bh
       INT     21h
       RET


; --------------------- Fin de VBLIB.INC -------------------

