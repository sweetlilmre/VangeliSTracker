; ------------------------------ PMODEDVT.ASM--------------------------------
; ASM library file for accessing the DemoVT. For Watcom C and/or Tran's PMode.
; (C) Copyright 1993 by Iguana/VangeliSTeam. However, it is made
; public domain for non-commercial use.

        .386p
        LOCALS @@

INCLUDE PMODEDVT.INC

  MagicAX    = 5654h;  {'VT'}   ; Some constants for the DemoVT detection.
  MagicBX    = 5472h;  {'Tr'}
  MagicCX    = 6163h;  {'ac'}
  MagicXorBX = 6B65h;  {'ke'}
  MagicXorCX = 7220h;  {'r '}

PUBLIC AppIDFound, DVTRunInfo

AppIDFound   DD 0         ; Address inside the DemoVT.
DVTRunInfo   DD 0         ; Address of the VTRunInfo declared above.

; ========================== FUNCTIONS ==========================
; You can count these modify ALL registers except EBX, ESI, EDI.

; -------------------------------- InitMusic
; Call this if you want to mess with the DemoVT. I suppose you want to.
; It detects whether DemoVT is present (DL = 1) or not (DL = 0), and
; initalizes the above pointers.

PUBLIC InitMusic
InitMusic:
                PUSH    ESI EDI EBX
                MOV     [v86r_ax],MagicAX      ; DemoVT's complex detection scheme.
                MOV     [v86r_bx],MagicBX      ; If MicroZooft had been a bit more
                MOV     [v86r_cx],MagicCX      ; precise when creating the INT 2Fh
                XOR     [v86r_di],0            ; maybe this would be more standard.
                MOV     [v86r_es],0            ; Don't try to understand WHY this,
                MOV     AL,2Fh               ; just believe it.
                INT     33h

                MOV     AX,[v86r_ax]
                MOV     BX,[v86r_bx]
                MOV     CX,[v86r_cx]

                XOR     DL,DL
                AND     AX,AX
                JNZ     SHORT @@no
                CMP     BX,MagicBX XOR MagicXorBX
                JNZ     SHORT @@no
                CMP     CX,MagicCX XOR MagicXorCX
                JNZ     SHORT @@no
                                        
                INC     DL              ; Geez, it really IS present!
                                        ; Save pointers.
                MOVZX   EAX,[v86r_es]
                SHL     EAX,4
                MOVZX   EDI,[v86r_di]
                ADD     EDI,EAX
                MOV     [AppIDFound],EDI

                MOV     EAX,GS:[EDI-4]
                MOVZX   EDI,AX
                SHR     EAX,12
                AND     EAX,0FFFF0h
                ADD     EDI,EAX
                MOV     [DVTRunInfo],EDI
        @@no:   MOVZX   EAX,DL
                POP     EBX EDI ESI
                RET



CallDemoVT MACRO num
LOCAL @@bad
                CMP     [DVTRunInfo],0                 ; Check.
                JZ      SHORT @@bad
                 MOV    [v86r_ax],&num                 ; Select CallMusic.
                 MOV    EDX,[DVTRunInfo]
                 MOV    CX,WORD PTR GS:[EDX+RegEntryPoint+2]
                 MOV    DX,WORD PTR GS:[EDX+RegEntryPoint]
                 INT    32h
        @@bad:
ENDM



; -------------------------------- CallMusic
; Calls the player when in polled mode. This means that if you want
; to use the timer (IRQ 0) for your application, you must manually
; call the DemoVT so that it will play the partiture. This routine
; must be called at least at a 50Hz average rate; if you don't, the
; music will jump. You can call it several times before making a
; long process; experiment how many times you need to avoid jumps.

PUBLIC CallMusic
CallMusic:

                CallDemoVT 2
                RET

; -------------------------------- VTConnectTimer
; Turn on timer mode. In this mode the player uses the system timer to
; perform its task, so you don't need to manually call InitMusic. But
; you also can't use the timer for you. Please don't hook to the IRQ0
; and then call the old handler (DemoVT's), if you want to do such a
; thing use the polled mode.

PUBLIC VTConnectTimer
VTConnectTimer:
                CallDemoVT 0
                RET

; -------------------------------- VTDisconnectTimer
; Enter polled mode. From now on, make frequent calls to CallMusic, and
; feel free to do what you desire with the IRQ0 timer.

PUBLIC VTDisconnectTimer
VTDisconnectTimer:
                CallDemoVT 1
                RET


; -------------------------------- VTGetTickCounter
; Reads the internal 50Hz counter of the DemoVT into EAX. Use this to
; synchronize with the music in terms of time played. (For synchronization
; you can also use the semaphores described later.)

PUBLIC VTGetTickCounter
VTGetTickCounter:
                XOR     EAX,EAX                           ; If DemoVT is not present,
                CMP     [DVTRunInfo],0                    ; the value is always zero.
                JZ      SHORT @@Fin                             ; Check.
                 MOV    EDX,[DVTRunInfo]
                 MOV    EAX,GS:[EDX+TickCounter]             ; Now get the real values.
        @@Fin:  RET

; -------------------------------- VTBeginSync
; Performs the usual preparations for calling the next routines. Call
; this when you want to be a bit in sync with the music. If you just
; want a background music you won't need this, but I'd advise you to
; call it anyway 'cause I'm not sure of the behaviour (I ALWAYS call
; it).

PUBLIC VTBeginSync
VTBeginSync:
                CallDemoVT 3
                RET

; -------------------------------- VTWaitForStart
; Performs a half-second wait and initializes the tick counter to
; zero. In the DemoVT, the music always goes half a second behind
; you; this means that, for example, a volume change will take
; effect that half second later. Use this routine to prepare yourself
; for that change.
; Another place where you will want to use this is at the start of a
; song. Right after calling VTBeginSync, there will be no music; call
; VTWaitForStart, and it will return at the precise moment when the
; first note of the song is starting to fill your ears.

PUBLIC VTWaitForStart
VTWaitForStart:
                CMP     [DVTRunInfo],0
                JZ      SHORT @@Fin
                 MOV    EDX,[DVTRunInfo]
                 XOR    EAX,EAX
                 MOV    GS:[EDX+TickCounter],EAX
        @@lp:     CALL  CallMusic
                  CALL  VTGetTickCounter
                  CMP   EAX,25
                  JC    SHORT @@lp
                 MOV    EDX,[DVTRunInfo]
                 XOR    EAX,EAX
                 MOV    GS:[EDX+TickCounter],EAX
        @@Fin:  RET

; -------------------------------- VTJumpPos
; Jump to some precise pattern in the sequence (AH) , and to a note inside
; that pattern (AL). Both values range from 1 to whatever. Remeber this,
; FastTracker musicians!

PUBLIC VTJumpPos
VTJumpPos:
                CMP     [DVTRunInfo],0                  ; Check.
                JZ      SHORT @@Fin
                 MOV    EDX,[DVTRunInfo]                ; Will take place in the
                 MOV    GS:[EDX+JumpNewPos],1               ; next CallMusic or so.
                 MOV    GS:[EDX+JumpPosSeq],AH
                 MOV    GS:[EDX+JumpPosNote],AL
        @@Fin:  RET

; -------------------------------- VTCheckSemaphore
; Compares AL with the value of the semaphore number 'EBX'. Sempahore
; values are incremented by a special command embedded in the MOD:
; Command number 8. The parameter of this command gives the number of
; the semaphore to increment.

PUBLIC VTCheckSemaphore
VTCheckSemaphore:
                CMP     [DVTRunInfo],0
                JZ      SHORT @@Fin
                 MOV    EDX,[DVTRunInfo]
                 CMP    GS:[EDX+Semaphores+EBX],AL
        @@Fin:  RET

; -------------------------------- VTSetSemaphore
; Sets the value of the semaphore # EBX to the value AL. You'll find this
; useful to clear the value of a semaphore that gets set by a command
; in a pattern that repeats several times. Huuhh... when you need this
; you will know, I guess.

PUBLIC VTSetSemaphore
VTSetSemaphore:
                CMP     [DVTRunInfo],0
                JZ      SHORT @@Fin
                 MOV    EDX,[DVTRunInfo]
                 MOV    GS:[EDX+Semaphores+EBX],AL
        @@Fin:  RET

; -------------------------------- VTMiddleSync
; Checks if the sempahore # BX is set. If not, it jumps to the position
; DH, DL (pattern, note) in the MOD. In any case, it waits for the next
; semaphore (BX +1) to activate and exits without jumping.
;
; You can use this to set precise synchronization points, for example,
; when starting some part of a trackmo. If you want the music to start at
; a precise point when you start an effect, you place a pair of semaphores.
; One before the desired synch point, and the next (numerical) one, half a
; second after the synch point. If the song has already reached half a
; second before the first semaphore, then this routine just waits for the
; second, which is set exactly when the synch point is sounding. If the first
; semaphore is not set, it jumps to the position and waits for the second as
; before.
;
; We used this to allow you to skip parts of the Inconexia trackmo and keep
; the music synchronized. It's hard to explain; read the above description
; and keep it in mind when you need something like this.

PUBLIC VTMiddleSync
VTMiddleSync:
                CMP     [DVTRunInfo],0
                JZ      SHORT @@Fin
                 XOR    AL,AL
                 PUSH   EDX
                 CALL   VTCheckSemaphore
                 POP    EAX
                 JNZ    SHORT @@cont
                  CALL  VTJumpPos
        @@cont:  INC    EBX
        @@wlp:    CALL  CallMusic
                  MOV   AL,0
                  CALL  VTCheckSemaphore
                  JZ    SHORT @@wlp
        @@Fin:  DEC     EBX
                RET

; -------------------------------- VTSetSoundVolume
; Changes the sound's volume to AL. It will really change 1/2 second after
; this call.
;
; You don't have to worry about the delay when you use this to fade the music.
; Just wait half a second after you finish fading.

PUBLIC VTSetSoundVolume
VTSetSoundVolume:
                CMP     [DVTRunInfo],0
                JZ      SHORT @@Fin
                 MOV    EDX,[DVTRunInfo]
                 MOV    GS:[EDX+SoundVolume],AL
        @@Fin:  RET

; -------------------------------- VTGetSoundVolume
; Reads the sound's volume into AL. Fairly straightforward, ain't it?

PUBLIC VTGetSoundVolume
VTGetSoundVolume:
                CMP     [DVTRunInfo],0
                JZ      SHORT @@Fin
                 MOV    EDX,[DVTRunInfo]
                 MOV    AL,GS:[EDX+SoundVolume]
        @@Fin:  RET


ENDS
END
; ---------------------------- End of PMODEDVT.ASM ---------------------------
