; ------------------------------ LAND.ASM ---------------------
; Landscape bye Jare/Iguana. Want more comments? Write'em. O:-)
; -------------------------------------------------------------
;  Well, I promised to release this routine. I feel it could be
; used for a better purpose than this, but that little fire was
; also released as an example of the ShellVT, and now everybody
; has done his own flames. That was kinda funny.
; -------------------------------------------------------------
;  Use this source as you like. The only price you must pay for
; it is mentioning us in you own work. The conditions for using
; the DemoVT are cointained elsewhere.
;
;  Greetings JMP to:  David 'Deadly' Hedley, Tran, Josh Jensen,
; Mark Morley, Draeden and all  in VLA, and everybody else  who
; has ever released some of his own sources.  The center of the
; demo world is undoubtedly Europe, but  most sources I've seen
; come from America. That's a point we will have to correct. :)

TRACE  = 0

        .MODEL SMALL
        .STACK 400
        .386P
        DOSSEG
        LOCALS


INCLUDE VGASM.INC
INCLUDE VTASM.INC
INCLUDE VBLIB.INC

SCRW = 80
INITIAL_HEIGHT = 0 ;8000h; 8000h

;===================================================

        .CODE

; ---------------------
; This is the table for the Anti-Tlink Protection System by Freston & JCAB.
; One shouldn't really need something like this, but I've seen my system
; crash because of this, and I felt quite pissed off. Don't want Iguana's
; demos to crash in any circumstances.

A_GDT   label   byte
	NullDes	dw	0, 0, 0, 0
	CodeDes	dw	0ffffh		; limit (bits 24-31)
		db	0, 0, 0		; base (bits 0-23)
		db	10011011B	; present / DPL 0 / code / non conforming / readable
		db	11001111B	; size 4Gb / 32 bits / limit
		db	0		; base
	DataDes	dw	0ffffh		; limit (bits 24-31)
		db	0, 0, 0		; base (bits 0-23)
		db	10010011B	; present / DPL 0 / data / writeable
		db	10001111B	; size 4Gb / 32 bits / limit
		db	0		; base

A_GDT_PTR       dw      17h             ; gdt size
                dd      0               ; gdt linear base

; -----------------------------------------------

        .STARTUP       
        CLD

; Protected mode fixup. Some programs like TLink from Borland leave the
; 386 segment registers unusable. This is to get them back.
; Anyone who has used Real-Flat mode knows how to fuck things up with
; the segment registers, don't you?

        SMSW    AX
        TEST    AX,1
        JNZ     @@alreadyPM     ; Do not fix if we are already in PM.

        PUSH    CS
        SUB     EAX,EAX
        POP     AX
        SHL     EAX,4
        ADD     EAX,LARGE OFFSET A_GDT
        MOV     DWORD PTR CS:[A_GDT_PTR].2,EAX

        LGDT    QWORD PTR CS:A_GDT_PTR

        SMSW    AX
        OR      AX,1
        LMSW    AX                      ; now running on protected mode

        JMP     @@ll1                   ; clear prefetch queue
@@ll1:

        MOV     AX,10h                 ; adjust data selectors
        MOV     GS,AX
        MOV     FS,AX

        MOV     EAX,CR0
        AND     EAX,0FFFFFFFEh
        MOV     CR0,EAX                ; now running on real mode

        JMP     @@ll2                  ; clear prefetch queue
@@ll2:
                       
        XOR     AX,AX
        MOV     FS,AX
        MOV     GS,AX

@@alreadyPM:

; ------------------------ End of PM fixup.


        CALL    InitMusic               ; Initialize DemoVT lib.
        MOV     [DemoVTPresent],AL      ; Store it
        OR      AL,AL
        JZ      @@nop
         CALL   VTDisconnectTimer       ; Poll mode is the default, but
                                        ; it's no big deal to make sure
                                        ; anyway. Better do this always.
        CALL    VTBeginSync
        CALL    VTWaitForStart
   @@nop:
        CALL    SetupLandVideo
        CALL    InitLand
        ;MOV     CS:[VBLFullHandler],OFFSET LandVBLHandler
        XOR     SI,SI
        CALL    InitializeTimerVBL


MainLoop:
        SetBorder 43, 43, 43

        ; Right before waiting for the retrace, we have much time left. This is
        ; the correct place to call the DemoVT.

        CMP     [DemoVTPresent],0
        JZ      @@nop
         CALL   CallMusic
    @@nop:

        ; Now we exercise the synchronization primitives. In channel #2 of the
        ; MOD file I have put a semaphore 0 INC command (8h, 00h) with each
        ; drum. I will now read it.

        XOR     BX,BX
        XOR     AL,AL
        CALL    VTCheckSemaphore
        JZ      @@nosem
         XOR    BX,BX
         XOR    AL,AL
         CALL   VTSetSemaphore          ; The semaphore is used repeatedly,
                                        ; so we clear it when it is triggered.
         MOV    AL,63
         MOV    [BoumRed],AL
         MOV    [BoumGreen],AL
         MOV    [BoumBlue],AL
;COMMENT #
     @@getr:
         CALL   GetRandomNumber
         AND    AX,7
         JZ     @@getr
         SHR    AL,1
         JC     @@sc1
          MOV   [BoumRed],AH
      @@sc1:
         SHR    AL,1
         JC     @@sc2
          MOV   [BoumGreen],AH
      @@sc2:
         SHR    AL,1
         JC     @@sc3
          MOV   [BoumBlue],AH
      @@sc3:
;#

     @@nosem:
        MOV     DX,3DAh   ; Set overscan color = 255 for the drum color.
        IN      AL,DX
        MOV     DX,3C0h
        MOV     AL,31h
        OUT     DX,AL
        MOV     AL,255
        OUT     DX,AL

        MOV     DX,3C8h
        OUT     DX,AL
        INC     DX
        MOV     AL,[BoumRed]
        OUT     DX,AL
        MOV     AL,[BoumGreen]
        OUT     DX,AL
        MOV     AL,[BoumBlue]
        OUT     DX,AL

        CMP     [BoumRed],0
        JZ      @@bc1
         DEC    [BoumRed]
     @@bc1:
        CMP     [BoumGreen],0
        JZ      @@bc2
         DEC    [BoumGreen]
     @@bc2:
        CMP     [BoumBlue],0
        JZ      @@bc3
         DEC    [BoumBlue]
     @@bc3:

        SetBorder 0, 0, 0

        CALL    VBLVSync

 IF TRACE
        MOV     DX,3DAh    ; Set overscan color = 0 for SetBorder to work.
        IN      AL,DX
        MOV     DX,3C0h
        MOV     AL,31h
        OUT     DX,AL
        MOV     AL,0
        OUT     DX,AL
 ENDIF
        SetBorder 0,63,63
        CALL    DumpLandLine

        INC     [DWORD PTR FrameNumber]
        CMP     [DWORD PTR FrameNumber],250
        JC      @@c2
         ADD    [WORD PTR HLimit],50h
         CMP    [WORd PTR HLimit],0A000h
         JC     @@c3
          MOV   [WORD PTR HLimit],0A000h
          JMP   @@c3
     @@c2:
         ADD    [WORD PTR HLimit],1000h/250
     @@c3:

        CLI
        MOV     BX,[ScrollPos]
        MOV     DX,3D4h
        MOV     AL,0Ch
        MOV     AH,BH
        OUT     DX,AX
        INC     AL
        MOV     AH,BL
        OUT     DX,AX
        STI

        MOV     BX,[ScrollPos]
        SUB     [ScrShown],SCRW
        SUB     [ScrNext],SCRW
        SUB     BX,SCRW
        JNC     @@ok
         ADD    BX,201*SCRW
         ADD    [ScrShown],201*SCRW
         ADD    [ScrNext],201*SCRW
     @@ok:
        MOV     [ScrollPos],BX

        SetBorder 0,63,0
        CALL    GenerateLand
        SetBorder 63,0,0
        
        MOV     AX,[FadeCounter]   ; Let's do the exit procedures.
        AND     AX,AX
        JZ      @@faded
        CMP     AX,256
        JNC     @@key
         CALL   VTSetSoundVolume
         DEC    [FadeCounter]
         JZ     @@starths          ; Fading done, start the half-second wait.
          JMP   MainLoop
   @@starths:
         CALL   VTGetTickCounter
         MOV    [WORD PTR HalfSecondWait],AX
         MOV    [WORD PTR HalfSecondWait+2],DX
         JMP    MainLoop
   @@faded:
        CALL    VTGetTickCounter
        SHL     EDX,16
        MOV     DX,AX
        MOV     EAX,[HalfSecondWait]
        SUB     EDX,EAX
        CMP     EDX,25
        JNC     ByeBye                   ; Could be Z, but WTH!
        JMP     MainLoop
   @@key:
        MOV     AH,1
        INT     16h
        JNZ     @@Read
        JMP     MainLoop
   @@Read:
        XOR     AX,AX
        INT     16h
        CMP     AL,27
        JZ      @@Bye
        JMP     MainLoop
   @@Bye:
        MOV     AL,[DemoVTPresent]
        OR      AL,AL
        JZ      ByeBye
         DEC    [FadeCounter]
         JMP    MainLoop

ByeBye:
        CALL    EndTimerVBL
        CMP     [DemoVTPresent],0
        JZ      @@nop
         CALL   VTConnectTimer
    @@nop:

        CALL    ZeroPalette
        MOV     AX,3
        INT     10h

        CALL    RestoreSystemTime

        MOV     AX,4C00h
        INT     21h


; =======================================

SetupLandVideo:
        CALL    ZeroPalette
        MOV     AX,13h
        INT     10h
        CALL    ZeroPalette

        VSync
        MOV     DX,3C0h
        MOV     AL,30h
        OUT     DX,AL
        MOV     AL,01100001b
        OUT     DX,AL 

        MOV     DX,3c4h
        MOV     AX,604h                 ; "Unchain my heart". And my VGA...
        OUT     DX,AX

        MOV     DX,3D4h
        MOV     AX,14h                  ; Disable dword mode
        OUT     DX,AX
        MOV     AX,0E317h               ; Enable byte mode.
        OUT     DX,AX

        MOV     DX,3C4h
        MOV     AX,0F02h                ; All planes
        OUT     DX,AX

        MOV     DX,3CEh                 ; Bitmask...
        MOV     AX,0FF08h               ; 11111111b
        OUT     DX,AX
        
        XOR     DI,DI                   ; Clear the screen. All planes.
        MOV     ES,[VGASeg]
        XOR     AX,AX
        MOV     CX,8000h
        REP STOSW

        MOV     SI,OFFSET NormalPalette
        MOV     CX,256
        XOR     AL,AL
        CALL    DumpPalette
        RET

; =======================================
; Arrrrgghhhhhhh!!! So many comments!! %-P
; Can't bear it: I know how it works, I intended
; to do it just this way, messy as it looks.

GenerateLand:
        MOV     CX,320                  ; This many points to generate.
        MOV     SI,OFFSET LastLine      ; Last line is in SI.
        MOV     DI,OFFSET ThisLine      ; New values in DI.

        MOV     DX,[SI+319*2]   ; DX will mean height of the (X-1) point.
                                ; We need a starting value for it, so...
    @@l1:
        PUSH    CX
        CALL    GetRandomNumber
        AND     AX,4*1024-1     ; 0 <= AX <= 4*1024-1
        ADD     AX,AX           ; 0 <= AX <= 8*1024-2

        MOV     BX,[DI]
        SUB     BX,[DI-2]       ; Get horiz. slope of prev. line.
        JNC     @@up            ; If it was negative ( -> down) we'll go up.
     @@dn:                      ; -3*1024 < AX < 5*1024. A neat trick here:
         SUB    AX,3*1024-3     ; -3 => A global tendency upwards.
         JMP    @@put           ;   The top limit will do the rest. It works!
     @@up:
         SUB    AX,5*1024-1     ; If it was positive ( -> up) we'll go down.
                                ; -5*1024 < AX < 3*1024. No tricks now.
     @@put:                             
         MOV    BP,DX           ; DX is (X-1) height. Save in BP.
                                ; AX is horiz. slope.
         ADD    AX,DX           ; Create new height.
         
         CMP    BP,8000         ; Detect overflow. Quite shitty, but works.
         JNC    @@chk0          ; If height of X-1 was below 8000 and
          CMP   AX,65536-8000   ; new height is above 65536-8000 (or
          JC    @@ok0           ; viceversa), there has been a rollover.
           MOV  AX,BP           ; In that case, stick to height of X-1.
           JMP  @@ok0
    @@chk0:
         CMP    BP,65536-8000   ; Here comes the viceversa. ;-)
         JC     @@ok0
          CMP   AX,8000
          JNC   @@ok0
           MOV  AX,BP           ; In that case, stick to height of X-1.
      @@ok0:

         MOV    BX,[SI+2]       ; Now average height with previous line.
         ADD    BX,[SI+4]       ; X+1 & X+2 seem to avoid diagonals.
         RCR    BX,1
         ADD    AX,BX
         RCR    AX,1
         
         CMP    AX,[HLimit]     ; Absolute maximum.
         JC     @@notop
          MOV   AX,BP ;[HLimit]
     @@notop:

         MOV    [DI],AX         ; Store new height, and save in DX for X+1.
         MOV    BP,DX
         MOV    DX,AX

           ;;;;;;;;;;;;;;;;;,
         CMP    AX,5000h
         JC     @@dofilter

         MOV    BX,AX                   ; Let's give those mountains a shade!
         MOV    CX,AX
         SUB    AX,7800h
         SAR    AX,2
         ADD    AX,7800h

         SUB    BX,BP

         JS     @@jc2
          SUB   AX,0A000h
          NEG   AX
          SHR   AX,1
          ADD   AX,5000h
         JMP    @@jc3
    @@jc2:SUB   AX,5000h
          SHR   AX,1
          ADD   AX,7800h
    @@jc3:

    @@dofilter:
         ADD    AX,[DI+320*2*2] ; Filter height value for screen color.
         RCR    AX,1
         MOV    BX,[LastValue]  ; This will make the landscape look nicer.
         ADD    AX,BX
         RCR    AX,1

   @@setval:
         MOV    [DI+320*2*2],AX ; Store the screen values, at last...
         MOV    [LastValue],AX

         ADD    DI,2            ; Now, do the usual loop arrangements.
         ADD    SI,2
         POP    CX
         DEC    CX
         JNZ    SMALL @@l1

        SetBorder 0, 0,63

        MOV     AX,DS           ; Now copy buffers to nice positions.
        MOV     ES,AX           ; No more comments from now on.

        MOV     DI,OFFSET LastLine
        MOV     SI,OFFSET ThisLine
        MOV     CX,320/2
        REP MOVSD

        MOV     DI,OFFSET LastLine-160*2
        MOV     SI,OFFSET LastLine+160*2
        MOV     CX,160/2
        REP MOVSD
        MOV     DI,OFFSET LastLine+320*2
        MOV     SI,OFFSET LastLine
        MOV     CX,160/2
        REP MOVSD

        RET

; =======================================

DumpLandLine:
        MOV     DX,3CEh                 ; Bitmask...
        MOV     AX,0FF08h               ; 11111111b
        OUT     DX,AX

        MOV     ES,[VGASeg]
        MOV     SI,OFFSET  DrawLine+1  ; ThisLine+1
        MOV     AX,102h
    @@l1:
        PUSH    AX
        MOV     DX,3C4h
        OUT     DX,AX

        MOV     DI,[ScrollPos]
        MOV     CX,SCRW/2
    @@l2:
         MOV    AL,[SI]
         MOV    AH,[SI+8]
         MOV    ES:[DI+201*SCRW],AX
         MOV    ES:[DI+402*SCRW],AX
         STOSW
         ADD    SI,16
         LOOP   @@l2

        SUB     SI,16*SCRW/2-2
        POP     AX
        SHL     AH,1
        JNC     @@l1

        RET

; =======================================

InitLand:
        MOV     AX,DS
        MOV     ES,AX
        MOV     AX,INITIAL_HEIGHT
        MOV     DI,OFFSET InitInitial
        MOV     CX,(OFFSET EndInitial - OFFSET InitInitial) / 2
        REP STOSW
        XOR     AX,AX
        MOV     DI,OFFSET InitZero
        MOV     CX,(OFFSET EndZero - OFFSET InitZero) / 2
        REP STOSW
        RET

; =======================================
             
GetRandomNumber:
        MOV     AX,[RandSeed]
        MOV     BX,[RandSeed2]
        ADD     AX,0a137h
        ADD     BX,63f7h
        ROL     AX,2
        MOV     [RandSeed],AX
        ADD     BX,AX
        ROR     BX,1
        MOV     [RandSeed2],BX
        ADD     AX,BX
        RET

; -------------------=======================================------------------

        .DATA

RandSeed     DW 348Bh
RandSeed2    DW 7F34h
VGASeg       DW 0A000h

ScrollPos   DW 0            ; Memory offset of upper line.
ScrShown    DW 0            ; Base offset of currently shown screen.
ScrNext     DW 201*SCRW     ;   "    "       updating screen.

FadeCounter DW 256

BoumRed   DB 63
BoumGreen DB 63
BoumBlue  DB 63
                
NormalPalette LABEL BYTE
        INCLUDE LANDPAL.INC

; =======================================

        UDATASEG

InitInitial LABEL WORD

LastValue  DW ?
LastValue2 DW ?

         DW 160 DUP (?)
LastLine DW 320 DUP (?)
         DW 160 DUP (?)

EndInitial LABEL WORD
InitZero   LABEL WORD

ThisLine DW 320 DUP (?)
Slopes   DW 320 DUP (?)
DrawLine DW 320 DUP (?)

UpdateScr   DW ?

HalfSecondWait DD ?

FrameNumber DD ?
HLimit      DW ?
LastSlope   DW ?

EndZero    LABEL WORD

DemoVTPresent DB ?
        END
; ------------------------ End of LAND.ASM ---------------------------

