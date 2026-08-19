                IDEAL
                MODEL  TPascal
                LOCALS @@
                JUMPS

                P286

                DATASEG

MACRO SetBorder r,g,b
MASM
COMMENT %
        PUSH    DX AX
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
        POP     AX DX
%
IDEAL
ENDM


StackSize       EQU 1000
DMABufferSize   EQU 2048
FinalBufferSize EQU 4096

GLOBAL DevStack         : BYTE
GLOBAL DevSS            : WORD
GLOBAL DevSP            : WORD

GLOBAL OldTimerHandler  : DWORD

GLOBAL Sounding         : DWORD
GLOBAL SoundLeft        : WORD

GLOBAL SystemClockIncr  : WORD
GLOBAL SystemClockCount : WORD

GLOBAL PeriodicCount    : WORD
GLOBAL PeriodicStart    : WORD
GLOBAL PeriodicProc     : DWORD

GLOBAL DeviceIdling     : BYTE

GLOBAL NumChannels      : WORD
GLOBAL BytesPerSample   : BYTE

GLOBAL DoBassPower      : BYTE
GLOBAL MixMethod        : BYTE

GLOBAL DMABufferPtr     : DWORD
GLOBAL DMABufferEnd     : WORD
GLOBAL DMABuffer        : DWORD
GLOBAL DMABufferYet     : BYTE
GLOBAL DMAStopped       : BYTE
GLOBAL DMAStop          : BYTE
GLOBAL DMAIrqWatch      : BYTE

GLOBAL FinalBufferPos   : WORD
GLOBAL FinalBuffer      : WORD

GLOBAL DeviceStartRut   : WORD
GLOBAL DeviceRut1       : WORD
GLOBAL DeviceRut2       : WORD
GLOBAL DeviceKickRut    : WORD
GLOBAL DeviceFillRut    : WORD

GLOBAL TrebleFilterVal_Left   : WORD
GLOBAL TrebleFilterMult_Left  : WORD
GLOBAL BassFilterVal_Left     : WORD
GLOBAL BassFilterMult_Left    : WORD
GLOBAL TrebleFilterVal_Right  : WORD
GLOBAL TrebleFilterMult_Right : WORD
GLOBAL BassFilterVal_Right    : WORD
GLOBAL BassFilterMult_Right   : WORD

                CODESEG

GLOBAL DoGetBuffer      : FAR
GLOBAL GetDMACount      : NEAR
GLOBAL InitTimer        : FAR




; здддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддд©
; Ё                                                                          Ё
; Ё MACRO: Saturate                                                          Ё
; Ё                                                                          Ё
; Ё Macro that saturates a sample just after an addition.                    Ё
; Ё                                                                          Ё
; Ё IN:  Reg    = Register to be saturated.                                  Ё
; Ё                                                                          Ё
; юдддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддды

MACRO Saturate Reg
LOCAL @@posit, @@nooverf

                JNO     SHORT @@nooverf
                JS      SHORT @@posit
                 MOV    Reg,-32767
                JMP     SHORT @@nooverf
@@posit:         MOV    Reg,32767
@@nooverf:

ENDM Saturate




             INCLUDE "BASSPOW.INC"
             INCLUDE "MIXROUTS.INC"




MACRO DevCall DevRut, Segm

                JMP     [DevRut]  ; Segm:
DevRut&Ret:

ENDM




; здддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддд©
; Ё                                                                          Ё
; Ё ROUTINE: DMAFillBuffer                                                   Ё
; Ё                                                                          Ё
; Ё This routine fills a portion of the DMA buffer with the whole buffer of  Ё
; Ё samples pointed to by Sounding & SoundLeft.                              Ё
; Ё                                                                          Ё
; Ё IN:  nothing                                                             Ё
; Ё                                                                          Ё
; Ё OUT: nothing                                                             Ё
; Ё                                                                          Ё
; Ё MODIFIES: AX, BX, CX, DX, SI, DI, ES                                     Ё
; Ё                                                                          Ё
; юдддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддды

DeviceIdCount   DB 0
TickCnt         DB 0

PUBLIC DMAFillBuffer

DMAFillBuffer:
                XOR     AL,AL
                MOV     [CS:DeviceIdCount],AL

                CALL    CalcNewMixData
                MOV     CX,[SoundLeft]
                MOV     AL,[BytesPerSample]
                MOV     DX,CX
                XOR     AH,AH
                MUL     DX
                LES     DI,[DMABufferPtr]
                MOV     BX,[DMABufferEnd]
                LDS     SI,[Sounding]
                CLD

                ADD     AX,DI
                CMP     AX,BX
                JBE     SHORT @@end
                 SUB    BX,DI
                 JZ     SHORT @@skip1st
                  PUSH  CX
                  MOV   AX,BX
                  MOV   CL,[SS:BytesPerSample]
                  XOR   CH,CH
                  XOR   DX,DX
                  DIV   CX
                  MOV   CX,AX
                  PUSH  CX
                  CALL  [SS:DeviceFillRut]
                  POP   BX
                  POP   CX
                  SUB   CX,BX
@@skip1st:       MOV    DI,[WORD PTR SS:DMABuffer]
@@end:          CALL    [SS:DeviceFillRut]

;MOV AL,[CS:TickCnt]
;XOR AL,255
;MOV [CS:TickCnt],AL
;MOV [ES:DI-1],AL

                MOV     AX,SS
                MOV     DS,AX
                MOV     [WORD PTR DMABufferPtr],DI
                RET




; здддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддд©
; Ё                                                                          Ё
; Ё ROUTINE: DMADoGetBuff                                                    Ё
; Ё                                                                          Ё
; Ё This is the main buffer-filling routine for DMA devices. First it calls  Ё
; Ё the buffer grabber. Then, it checks to see if the DMA has advanced       Ё
; Ё enough to leave space for this buffer.                                   Ё
; Ё                                                                          Ё
; Ё IN:  nothing                                                             Ё
; Ё                                                                          Ё
; Ё OUT: nothing                                                             Ё
; Ё                                                                          Ё
; Ё MODIFIES: AX, BX, CX, DX, SI, DI, ES                                     Ё
; Ё                                                                          Ё
; юдддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддды

PUBLIC DMADoGetBuff

DMADoGetBuff:

                MOV     AX,[SoundLeft]
                MOV     BL,[DMABufferYet]
                AND     BL,BL
                JZ      SHORT @@1
                 CALL   DoGetBuffer
@@1:            MOV     BL,1
                MOV     [DMABufferYet],BL

                CMP     AX,10
                JC      SHORT @@end

                MOV     DL,[BytesPerSample]
                XOR     DH,DH
                MUL     DX

                PUSH    AX
                CALL    GetDMACount
                MOV     BX,DMABufferSize
                SUB     BX,AX
                ADD     BX,[WORD PTR DMABuffer]
                MOV     CX,BX
                SUB     BX,[WORD PTR DMABufferPtr]
                JNC     SHORT @@2
                 ADD    BX,DMABufferSize
@@2:            POP     AX
                SUB     BX,AX
                JNC     DMAFillBuffer

                XOR     BL,BL
                MOV     [DMABufferYet],BL
@@end:
                MOV     AL,[CS:DeviceIdCount]
                CMP     AL,20
                JNC     @@end1
                INC     [CS:DeviceIdCount]
@@end1:
                MOV     [DeviceIdling],AL

                RET




;                MOV     [DevSS],SS
;                MOV     [DevSP],SP
;                MOV     DX,DS
;                MOV     SS,DX
;                MOV     SP,OFFSET DevStack + StackSize

;                MOV     SS,[DevSS]
;                MOV     SP,[DevSP]




; здддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддд©
; Ё                                                                          Ё
; Ё ROUTINE: TimerHandler                                                    Ё
; Ё                                                                          Ё
; Ё This is the big routine for non-DMA devices. It is called through        Ё
; Ё interrupts from a timer whose period is the sampling period.             Ё
; Ё                                                                          Ё
; юдддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддды

PUBLIC TimerHandler

TimerHandler:
		CLI   ; Just for safety's sake.

                ; здддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Startup:                                   Ё
                ; Ё                                            Ё
                ; Ё   - Save the registers in the local stack. Ё
                ; Ё   - Set the data segment register.         Ё
                ; юдддддддддддддддддддддддддддддддддддддддддддды

                PUSH    AX
                PUSH    BX
                PUSH    CX
                PUSH    DX
                PUSH    DI
                PUSH    SI
                PUSH    DS

                MOV     AX,SEG Sounding
                MOV     DS,AX

                ; здддддддддддддддддддддддддддддддддддддддддд©
                ; Ё First, we jump to the device start code. Ё
                ; юдддддддддддддддддддддддддддддддддддддддддды

                DevCall DeviceStartRut

                ; зддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Check to see if there are samples to use. Ё
                ; юддддддддддддддддддддддддддддддддддддддддддды
                
                MOV     AX,[SoundLeft]
                AND     AX,AX
                JZ      SHORT thAfterProcessingSample

                ; здддддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Decrement the number of samples left in the  Ё
                ; Ё buffer, do the device initialization if any, Ё
                ; Ё and signal that the device is not idle.      Ё
                ; юдддддддддддддддддддддддддддддддддддддддддддддды

                DEC     AX
                MOV     [SoundLeft],AX

                DevCall DeviceRut1

                XOR     BH,BH
                MOV     [DeviceIdling],BH

                ; зддддддддддддддддддддддддддддддддд©
                ; Ё Load the buffer pointer, do the Ё
                ; Ё mixing and output the sample.   Ё
                ; юддддддддддддддддддддддддддддддддды
                
                LDS     SI,[Sounding]

                CALL    MixChannels

                MOV     DX,SEG Sounding
                MOV     DS,DX
                MOV     [WORD PTR Sounding],SI

                MOV     SI,OFFSET FinalBuffer
                MOV     CX,[FinalBufferPos]
                ADD     SI,CX
                ADD     SI,CX
                MOV     [SI],AX
                INC     CX
                AND     CX,FinalBufferSize - 1
                MOV     [FinalBufferPos],CX

                DevCall DeviceRut2

                ; здддддддддддддддддддд©
                ; Ё Restore the stack. Ё
                ; юдддддддддддддддддддды

thAfterProcessingSample:
sti
                ; здддддддддддддддддддддддддддд©
                ; Ё Check if the old interrupt Ё
                ; Ё routine must be called.    Ё
                ; юдддддддддддддддддддддддддддды

                MOV     AX,[SystemClockIncr]
                ADD     [SystemClockCount],AX
                JC      SHORT @@SystemClock

                ; здддддддддддддддддддддддддддддддддд©
                ; Ё Else, signal the EOI to the PIC. Ё
                ; юдддддддддддддддддддддддддддддддддды

                MOV     AL,20h
                OUT     20h,AL

@@CheckOutProc:
                MOV     CX,[PeriodicCount]
                JCXZ    SHORT @@OutProc
                DEC     CX
                MOV     [PeriodicCount],CX
                JZ      SHORT @@OutProc

                MOV     AX,[SoundLeft]
                AND     AX,AX
                JZ      SHORT @@OutProc

@@exit:
                ; здддддддддддддддддддддддддддддддддддд©
                ; Ё Do the final stuff: Pop registers. Ё
                ; юдддддддддддддддддддддддддддддддддддды

                POP     DS
                POP     SI
                POP     DI
                POP     DX
                POP     CX
                POP     BX
                POP     AX
                IRET

@@SystemClock:
                PUSHF
                CALL    [OldTimerHandler]
                JMP     SHORT @@CheckOutProc

@@OutProc:
                ; здддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Get a new sample buffer. If there is none, Ё
                ; Ё signal that the device is in idle state.   Ё
                ; юдддддддддддддддддддддддддддддддддддддддддддды

                MOV     AL,0
@@outsemaph:
                AND     AL,AL
                JNZ     SHORT @@exit
                INC     AL
                MOV     [BYTE PTR CS:@@outsemaph-1],AL

                MOV     AX,[SoundLeft]
                AND     AX,AX
                JNZ     SHORT @@NoIdle

                CALL    CalcNewMixData

                PUSH    ES
                CALL    DoGetBuffer
                POP     ES

                CALL    CalcNewMixData

                MOV     AX,[SoundLeft]
                AND     AX,AX
                JNZ     SHORT @@NoIdle

                INC     AH
                MOV     [DeviceIdling],AH

@@NoIdle:
                MOV     [BYTE PTR CS:@@outsemaph-1],0

                ; зддддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё See if the periodic process must be called. Ё
                ; юддддддддддддддддддддддддддддддддддддддддддддды
                
                MOV     AX,[PeriodicCount]
                AND     AX,AX
                JNZ     SHORT @@NoPeriodic

                MOV     AX,[PeriodicStart]
                MOV     [PeriodicCount],AX

                ; здддддддддддддддддддддддддддд©
                ; Ё Call the periodic process. Ё
                ; юдддддддддддддддддддддддддддды

                PUSH    ES
                STI
                CALL    [PeriodicProc]
                POP     ES

@@NoPeriodic:
                JMP     SHORT @@exit




; здддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддд©
; Ё                                                                          Ё
; Ё ROUTINE: DMATimerHandler                                                 Ё
; Ё                                                                          Ё
; Ё This is the big routine for DMA devices. It is called through            Ё
; Ё interrupts from a timer whose period is a few Hertz (100 for example).   Ё
; Ё                                                                          Ё
; юдддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддды

DMASema         DB 0

PUBLIC DMATimerHandler

DMATimerHandler:
                CLI   ; Just for safety's sake.

                ; зддддддддддддддддддддддддд©
                ; Ё Startup:                Ё
                ; Ё                         Ё
                ; Ё   - Save the registers. Ё
                ; юддддддддддддддддддддддддды

                PUSHA
                PUSH    ES
                PUSH    DS

                MOV     AX,SEG Sounding
                MOV     DS,AX

@@DoSystemClock:

                ; здддддддддддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Check if the old interrupt routine must be called. Ё
                ; юдддддддддддддддддддддддддддддддддддддддддддддддддддды

                MOV     AX,[SystemClockIncr]
                ADD     [SystemClockCount],AX
                JNC     SHORT @@NoSysClk

                ; зддддддддддддддд©
                ; Ё If so, do it. Ё
                ; юддддддддддддддды

                PUSHF
                CALL    [OldTimerHandler]
                JMP     SHORT @@SystemClkDone

@@NoSysClk:
                ; здддддддддддддддддддддддддддддддддд©
                ; Ё Else, signal the EOI to the PIC. Ё
                ; юдддддддддддддддддддддддддддддддддды

                MOV     AL,20h
                OUT     20h,AL

@@SystemClkDone:
                CLI

                ; зддддддддддддддддддддддддддддддддддддддддд©
                ; Ё First we check if the DMA operation is  Ё
                ; Ё requested to stop. If so, we signal the Ё
                ; Ё stopping of the DMA and jump to the old Ё
                ; Ё IRQ-checking part.                      Ё
                ; юддддддддддддддддддддддддддддддддддддддддды

                MOV     AL,[DMAStop]
                AND     AL,AL
                JZ      SHORT @@notstop
;                 MOV    [DMAStopped],AL
                 MOV    [DeviceIdling],AL
                 JMP    SHORT @@end
@@notstop:
                ; зддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Now, we check the IRQ watchdog, just in Ё
                ; Ё case we need to kick the card.          Ё
                ; юддддддддддддддддддддддддддддддддддддддддды

MASM
COMMENT #

                MOV     AL,[DMAIrqWatch]
                CMP     AL,200
                JC      SHORT @@notwatch
;                 CALL   [DeviceKickRut]
@@notwatch:
                ; зддддддддддддддддддддддддддддддддддддддддд©
                ; Ё If the device is said to be idle, reset Ё
                ; Ё the timer. This is to protect the timer Ё
                ; Ё period from being modified.             Ё
                ; юддддддддддддддддддддддддддддддддддддддддды

                MOV     AL,[DeviceIdling]
                AND     AL,AL
                JZ      SHORT @@notidling
;                 CALL    InitTimer
@@notidling:
                ; здддддддддддддддддддддддддддддддддддддддд©
                ; Ё Signal that the device is not idling,  Ё
                ; Ё and fill a bit more of the DMA buffer. Ё
                ; юдддддддддддддддддддддддддддддддддддддддды
#
IDEAL
                MOV     AL,[CS:DMASema]
                AND     AL,AL
                JNZ     @@end

                INC     [CS:DMASema]
                STI

@@loop:

                PUSH    DS
                MOV     AX,0B800h
                MOV     DS,AX
                INC     [WORD PTR DS:90*4];
                POP     DS

                MOV     [DevSS],SS
                MOV     [DevSP],SP
                MOV     DX,DS
                MOV     SS,DX
                MOV     SP,OFFSET DevStack + StackSize

                XOR     AL,AL
                MOV     [DeviceIdling],AL

;SetBorder 0, 63, 63

                STI
                CALL    DMADoGetBuff
                CLI

;SetBorder 0, 0, 63

                ; зддддддддддддддддддддддддддддддддддддд©
                ; Ё Call the periodic process and exit. Ё
                ; юддддддддддддддддддддддддддддддддддддды

                STI
                CALL    [PeriodicProc]
                CLI

                MOV     SS,[DevSS]
                MOV     SP,[DevSP]

                MOV     AL,[CS:DeviceIdCount]
                AND     AL,AL
;                JZ      @@loop

                DEC     [CS:DMASema]

@@end:
                ; здддддддддддддддддддддддддддддддддддддддд©
                ; Ё Increment the watchdog, but don't let  Ё
                ; Ё it wrap around.                        Ё
                ; юдддддддддддддддддддддддддддддддддддддддды

                MOV     AL,[DMAIrqWatch]
                CMP     AL,250
                JNC     SHORT @@noinc
                 INC    [DMAIrqWatch]
@@noinc:

                ; здддддддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Do the final stuff: Pop registers, restore the Ё
                ; Ё stack, and exit.                               Ё
                ; юдддддддддддддддддддддддддддддддддддддддддддддддды

                POP     DS
                POP     ES
                POPA
                IRET





MASM
COMMENT ~

kk:

                CLI   ; Just for safety's sake.

                ; зддддддддддддддддддддддддд©
                ; Ё Startup:                Ё
                ; Ё                         Ё
                ; Ё   - Save the registers. Ё
                ; юддддддддддддддддддддддддды

                PUSHA
                PUSH    ES
                PUSH    DS

                MOV     AX,SEG Sounding
                MOV     DS,AX

@@DoSystemClock:

                ; здддддддддддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Check if the old interrupt routine must be called. Ё
                ; юдддддддддддддддддддддддддддддддддддддддддддддддддддды

                MOV     AX,[SystemClockIncr]
                ADD     [SystemClockCount],AX
                JNC     SHORT @@NoSysClk

                ; зддддддддддддддд©
                ; Ё If so, do it. Ё
                ; юддддддддддддддды

                PUSHF
                CALL    [OldTimerHandler]
                JMP     SHORT @@SystemClkDone

@@NoSysClk:
                ; здддддддддддддддддддддддддддддддддд©
                ; Ё Else, signal the EOI to the PIC. Ё
                ; юдддддддддддддддддддддддддддддддддды

                MOV     AL,20h
                OUT     20h,AL

@@SystemClkDone:
                CLI

                ; зддддддддддддддддддддддддддддддддддддддддд©
                ; Ё First we check if the DMA operation is  Ё
                ; Ё requested to stop. If so, we signal the Ё
                ; Ё stopping of the DMA and jump to the old Ё
                ; Ё IRQ-checking part.                      Ё
                ; юддддддддддддддддддддддддддддддддддддддддды

                MOV     AL,[DMAStop]
                AND     AL,AL
                JZ      SHORT @@notstop
;                 MOV    [DMAStopped],AL
                 MOV    [DeviceIdling],AL
                 JMP    SHORT @@end
@@notstop:
                ; зддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Now, we check the IRQ watchdog, just in Ё
                ; Ё case we need to kick the card.          Ё
                ; юддддддддддддддддддддддддддддддддддддддддды

                MOV     AL,[DMAIrqWatch]
                CMP     AL,200
                JC      SHORT @@notwatch
;                 CALL   [DeviceKickRut]
@@notwatch:
                ; зддддддддддддддддддддддддддддддддддддддддд©
                ; Ё If the device is said to be idle, reset Ё
                ; Ё the timer. This is to protect the timer Ё
                ; Ё period from being modified.             Ё
                ; юддддддддддддддддддддддддддддддддддддддддды

                MOV     AL,[DeviceIdling]
                AND     AL,AL
                JZ      SHORT @@notidling
;                 CALL    InitTimer
@@notidling:
                ; здддддддддддддддддддддддддддддддддддддддд©
                ; Ё Signal that the device is not idling,  Ё
                ; Ё and fill a bit more of the DMA buffer. Ё
                ; юдддддддддддддддддддддддддддддддддддддддды

                MOV     AL,[CS:DMASema]
                AND     AL,AL
                JNZ     @@end

                INC     [CS:DMASema]
                STI

@@loop:

                PUSH    DS
                MOV     AX,0B800h
                MOV     DS,AX
                INC     [WORD PTR DS:90*4];
                POP     DS

                MOV     [DevSS],SS
                MOV     [DevSP],SP
                MOV     DX,DS
                MOV     SS,DX
                MOV     SP,OFFSET DevStack + StackSize

                XOR     AL,AL
                MOV     [DeviceIdling],AL

;SetBorder 0, 63, 63

                STI
                CALL    DMADoGetBuff
                CLI

;SetBorder 0, 0, 63

                ; зддддддддддддддддддддддддддддддддддддд©
                ; Ё Call the periodic process and exit. Ё
                ; юддддддддддддддддддддддддддддддддддддды

                STI
                CALL    [PeriodicProc]
                CLI

                MOV     SS,[DevSS]
                MOV     SP,[DevSP]

                MOV     AL,[CS:DeviceIdCount]
                AND     AL,AL
;                JZ      @@loop

                DEC     [CS:DMASema]

@@end:
                ; здддддддддддддддддддддддддддддддддддддддд©
                ; Ё Increment the watchdog, but don't let  Ё
                ; Ё it wrap around.                        Ё
                ; юдддддддддддддддддддддддддддддддддддддддды

                MOV     AL,[DMAIrqWatch]
                CMP     AL,250
                JNC     SHORT @@noinc
                 INC    [DMAIrqWatch]
@@noinc:

                ; здддддддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Do the final stuff: Pop registers, restore the Ё
                ; Ё stack, and exit.                               Ё
                ; юдддддддддддддддддддддддддддддддддддддддддддддддды

                POP     DS
                POP     ES
                POPA
                IRET

~
IDEAL





PUBLIC NullTimerHandler
NullTimerHandler:
                PUSHA
                PUSH    DS
                PUSH    ES

                MOV     AX,SEG Sounding
                MOV     DS,AX

                MOV     [DevSS],SS
                MOV     [DevSP],SP
                MOV     DX,DS
                MOV     SS,DX
                MOV     SP,OFFSET DevStack + StackSize

@@DoSystemClock:

                ; здддддддддддддддддддддддддддддддддддддддддддддддддддд©
                ; Ё Check if the old interrupt routine must be called. Ё
                ; юдддддддддддддддддддддддддддддддддддддддддддддддддддды

                MOV     AX,[SystemClockIncr]
                ADD     [SystemClockCount],AX
                JNC     SHORT @@NoSysClk

                ; зддддддддддддддд©
                ; Ё If so, do it. Ё
                ; юддддддддддддддды

                PUSHF
                CALL    [OldTimerHandler]
                JMP     SHORT @@SystemClkDone

@@NoSysClk:
                ; здддддддддддддддддддддддддддддддддд©
                ; Ё Else, signal the EOI to the PIC. Ё
                ; юдддддддддддддддддддддддддддддддддды

                MOV     AL,20h
                OUT     20h,AL

@@SystemClkDone:
                CALL    [PeriodicProc]

                MOV     SS,[DevSS]
                MOV     SP,[DevSP]

                POP     ES
                POP     DS
                POPA
                IRET






; здддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддд©
; Ё                                                                          Ё
; Ё ROUTINE: NullDevRut                                                      Ё
; Ё                                                                          Ё
; Ё Do-nothing routine for the unused device services.                       Ё
; Ё                                                                          Ё
; юдддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддддды

NullDevRut:
                RET




                INCLUDE "DEVSB.INC"
                INCLUDE "DEVSPKR.INC"
                INCLUDE "DEVDAC.INC"




END
