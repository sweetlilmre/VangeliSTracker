; ------------------------- VTASM.INC -------------------------
; ASM include file for accessing the DemoVT.
; (C) Copyright 1993-1994 by the VangeliSTeam. However, it is made
; public domain for non-commercial use.

; First we declare the structure that holds the DemoVT variables.
; We will get its address to check semaphores, modify volume, and
; all that.

TChanData STRUC
      Period DW ?
      Ins    DB ?
      Vol    DB ?
ENDS

VTRunInfo SEGMENT AT 0
  ; These are modified by DemoVT, and you can read them.
      Semaphores     DB 256 DUP(?)      ; Array of semaphores. You can read or
                                        ; modify them (usually cleaning them).


      ChansTrig      DB  32 DUP(?)      ; == 1 -> channel retriggered a note.
      NumChannels    DB ?               ; Number of channels in the MOD.

      CtrlEntryPoint DD ?               ; Address of ther DemoVT service proc.
      TickCounter    DD ?               ; This one provides some form for you
                                        ; to do timing, incremented at 50Hz.
      RegEntryPoint  DD ?               ; DVT Service taking parm in AX.
      ChansData      TChanData 32 DUP (<>) ; Per-channel info.
      Pos            DB ?               ; Note in the current pattern.
      Seq            DB ?               ; Number of playing pattern.

                     DB 81 DUP(?)      ; Reserved.

  ; These are supposed to be modified by you to tell DemoVT your intentions. :)
                     DB  ?              ; Reserved.
                     DW  ?              ; Reserved.

      JumpNewPos     DB  ?              ; Indicates that you want to jump to
                                        ; another position inside the MOD.
      JumpPosSeq     DB  ?              ; Sequence position to jump to.
      JumpPosNote    DB  ?              ; Note inside the pattern to jump to.

      SoundVolume    DB  ?              ; Put your favourite volume here.
                                        ; You can perform fades and the like.
                                        ; 0-255.
      Abort          DB ?               ; Set to 1 to force DVT to exit after
                                        ; your program exits.

                     DB 248 DUP(?)      ; Reserved.

ENDS

        .CODE           ; Easy way to make a code segment. U may want to
                        ; modify it if you don't use simplified directives.

  MagicAX    = 5654h;  {'VT'}   ; Some constants for the DemoVT detection.
  MagicBX    = 5472h;  {'Tr'}
  MagicCX    = 6163h;  {'ac'}
  MagicXorBX = 6B65h;  {'ke'}
  MagicXorCX = 7220h;  {'r '}


AppIDFound DD 0         ; Address inside the DemoVT.
DVTRunInfo DD 0         ; Address of the VTRunInfo declared above.

TickVal    DW 0         ; Temporary var used by VTWaitForStart.


; ========================== FUNCTIONS ==========================
; You can count these modify ALL registers.

; -------------------------------- InitMusic
; Call this if you want to mess with the DemoVT. I suppose you want to.
; It detects whether DemoVT is present (DL = 1) or not (DL = 0), and
; initalizes the above pointers.

InitMusic:
                MOV     AX,MagicAX      ; DemoVT's complex detection scheme.
                MOV     BX,MagicBX      ; If MicroZooft had been a bit more
                MOV     CX,MagicCX      ; precise when creating the INT 2Fh
                XOR     DI,DI           ; maybe this would be more standard.
                MOV     ES,DI           ; Don't try to understand WHY this,
                INT     2Fh             ; just believe it.
                XOR     DL,DL
                AND     AX,AX
                JNZ     @@no
                CMP     BX,MagicBX XOR MagicXorBX
                JNZ     @@no
                CMP     CX,MagicCX XOR MagicXorCX
                JNZ     @@no
                                        ; Geez, it really IS present!
                INC     DL              ; Save pointers.
                MOV     WORD PTR CS:[AppIDFound+2],ES
                MOV     WORD PTR CS:[AppIDFound],DI
                LES     DI,ES:[DI-4]
                MOV     WORD PTR CS:[DVTRunInfo+2],ES
                MOV     WORD PTR CS:[DVTRunInfo],DI
        @@no:   MOV     AL,DL
                RET

; -------------------------------- CallMusic
; Calls the player when in polled mode. This means that if you want
; to use the timer (IRQ 0) for your application, you must manually
; call the DemoVT so that it will play the partiture. This routine
; must be called at least at a 50Hz average rate; if you don't, the
; music will jump. You can call it several times before making a
; long process; experiment how many times you need to avoid jumps.

CallMusic:
                CMP     WORD PTR CS:[DVTRunInfo+2],0    ; Check.
                JZ      @@Fin
                LES     SI,CS:[DVTRunInfo]              ; ES:SI = DemoVT info.
                PUSH    2                               ; Select CallMusic.
                CALL    ES:[SI+CtrlEntryPoint]          ; Call the DemoVT.
        @@Fin:
                RET

; -------------------------------- VTConnectTimer
; Turn on timer mode. In this mode the player uses the system timer to
; perform its task, so you don't need to manually call InitMusic. But
; you also can't use the timer for you. Please don't hook to the IRQ0
; and then call the old handler (DemoVT's), if you want to do such a
; thing use the polled mode.

VTConnectTimer:
                CMP     WORD PTR CS:[DVTRunInfo+2],0    ; Check.
                JZ      @@Fin
                LES     SI,CS:[DVTRunInfo]              ; ES:SI = DemoVT info.
                PUSH    0                               ; Select VTConnectTimer.
                CALL    ES:[SI+CtrlEntryPoint]          ; Call the DemoVT.
        @@Fin:
                RET

; -------------------------------- VTDisconnectTimer
; Enter polled mode. From now on, make frequent calls to CallMusic, and
; feel free to do what you desire with the IRQ0 timer.

VTDisconnectTimer:
                CMP     WORD PTR CS:[DVTRunInfo+2],0    ; Check.
                JZ      @@Fin
                LES     SI,CS:[DVTRunInfo]              ; ES:SI = DemoVT info.
                PUSH    1                               ; Select VTDisconnectTimer.
                CALL    ES:[SI+CtrlEntryPoint]          ; Call the DemoVT.
        @@Fin:
                RET

; -------------------------------- VTGetTickCounter
; Reads the internal 50Hz counter of the DemoVT into DX:AX. Use this to
; synchronize with the music in terms of time played. (For synchronization
; you can also use the semaphores described later.)

VTGetTickCounter:
                XOR     AX,AX                             ; If DemoVT is not present,
                XOR     DX,DX                             ; the value is always zero.
                CMP     WORD PTR CS:[DVTRunInfo+2],0      ; Check.
                JZ      @@Fin

                LES     SI,CS:[DVTRunInfo]
                MOV     AX,WORD PTR ES:[SI+TickCounter]   ; Now get the real values.
                MOV     DX,WORD PTR ES:[SI+TickCounter+2]

        @@Fin:  RET

; -------------------------------- VTBeginSync
; Performs the usual preparations for calling the next routines. Call
; this when you want to be a bit in sync with the music. If you just
; want a background music you won't need this, but I'd advise you to
; call it anyway 'cause I'm not sure of the behaviour (I ALWAYS call
; it).

VTBeginSync:
                CMP     WORD PTR CS:[DVTRunInfo+2],0
                JZ      @@Fin

                LES     SI,CS:[DVTRunInfo]
                PUSH    3
                CALL    ES:[SI+CtrlEntryPoint]

        @@Fin:  RET

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

VTWaitForStart:
                CMP     WORD PTR CS:[DVTRunInfo+2],0
                JZ      @@Fin

                CALL    VTGetTickCounter
                XOR     AX,AX
                MOV     WORD PTR ES:[SI+TickCounter],AX
                MOV     WORD PTR ES:[SI+TickCounter+2],AX

                MOV     CS:[TickVal],AX
        @@lp:    CALL   CallMusic
                 CALL   VTGetTickCounter
                 SUB    AX,25
                 CMP    AX,CS:[TickVal]
                 JNZ    @@lp

                XOR     AX,AX
                MOV     WORD PTR ES:[SI+TickCounter],AX
                MOV     WORD PTR ES:[SI+TickCounter+2],AX

        @@Fin:  RET

; -------------------------------- VTJumpPos
; Jump to some precise pattern in the sequence (AH) , and to a note inside
; that pattern (AL). Both values range from 1 to whatever. Remeber this,
; FastTracker musicians!

VTJumpPos:
                CMP     WORD PTR CS:[DVTRunInfo+2],0    ; Check.
                JZ      @@Fin

                LES     SI,CS:[DVTRunInfo]              ; Will take place in the
                MOV     ES:[SI+JumpNewPos],1            ; next CallMusic or so.
                MOV     ES:[SI+JumpPosSeq],AH
                MOV     ES:[SI+JumpPosNote],AL

        @@Fin:  RET

; -------------------------------- VTCheckSemaphore
; Compares AL with the value of the semaphore number 'BX'. Sempahore
; values are incremented by a special command embedded in the MOD:
; Command number 8. The parameter of this command gives the number of
; the semaphore to increment.

VTCheckSemaphore:
                CMP     WORD PTR CS:[DVTRunInfo+2],0
                JZ      @@Fin

                LES     SI,CS:[DVTRunInfo]
                CMP     ES:[SI+Semaphores+BX],AL

        @@Fin:  RET

; -------------------------------- VTSetSemaphore
; Sets the value of the semaphore # BX to the value AL. You'll find this
; useful to clear the value of a semaphore that gets set by a command
; in a pattern that repeats several times. Huuhh... when you need this
; you will know, I guess.

VTSetSemaphore:
                CMP     WORD PTR CS:[DVTRunInfo+2],0
                JZ      @@Fin

                LES     SI,CS:[DVTRunInfo]
                MOV     ES:[SI+Semaphores+BX],AL

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

VTMiddleSync:
                CMP     WORD PTR CS:[DVTRunInfo+2],0
                JZ      @@Fin

                XOR     AL,AL
                CALL    VTCheckSemaphore
                JNZ     @@cont
                 MOV    AX,DX
                 CALL   VTJumpPos
        @@cont: INC     BX
        @@wlp:   CALL   CallMusic
                 MOV    AL,0
                 CALL   VTCheckSemaphore
                 JZ     @@wlp

        @@Fin:  RET

; -------------------------------- VTSetSoundVolume
; Changes the sound's volume to AL. It will really change 1/2 second after
; this call.
;
; You don't have to worry about the delay when you use this to fade the music.
; Just wait half a second after you finish fading.

VTSetSoundVolume:
                CMP     WORD PTR CS:[DVTRunInfo+2],0
                JZ      @@Fin
                 LES    SI,CS:[DVTRunInfo]
                 MOV    ES:[SI+SoundVolume],AL
        @@Fin:  RET

; -------------------------------- VTGetSoundVolume
; Reads the sound's volume into AL. Fairly straightforward, ain't it?

VTGetSoundVolume:
                CMP     WORD PTR CS:[DVTRunInfo+2],0
                JZ      @@Fin
                 LES    SI,CS:[DVTRunInfo]
                 MOV    AL,ES:[SI+SoundVolume]
        @@Fin:  RET

; --------------------- End of VTASM.INC ------------------
