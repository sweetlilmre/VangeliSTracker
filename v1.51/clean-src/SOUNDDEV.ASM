; ==========================================================================
; DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).
;
; The parts of the sound core that had to be assembler: the gain ladder, the
; mixing chain, the timer poll every driver shares, and the output selectors.
;
; ONE FRAMELESS RUN WITH THREE ENTRY POINTS AND TWO DIFFERENT RETURNS, which is
; the reason it is a separate module at all. A Pascal procedure has one entry
; and one exit; this code is entered at three labels, falls from one section
; into the next, and ends RETF in one place and RETF 4 in another. There is no
; way to say that in Pascal, so it is said in TASM and linked in with $L --
; which is how the 1.39b release builds this same unit too.
;
; WHAT LIVES HERE, in order:
;
;     the gain ladder      256 unrolled scale-and-add steps, generated
;     SharedPoll           the timer callback every driver shares
;     the DSP writers      talking to a Sound Blaster
;     the output selectors mono or stereo, 8-bit or 16-bit
;
;     instruction   original       TASM 4.1   TP6 inline asm
;     AND AL,AL     22 C0 @1014    22 C0      20 C0
;     XOR AL,AL     32 C0 @102e    32 C0      30 C0
;     ADD AX,AX     03 C0 @0a84    03 C0      01 C0
;     RETF 4        CA 04 00       CA 04 00   cannot express
;
; while GetPlayPos, which stays in SOUNDDEV.PAS, has TP's 29 C3 for SUB BX,AX.
; Two assemblers, two regions. See docs/06-transcription.md.
;

                MODEL   TPASCAL
                P286

; ---- DGROUP variables, all declared in SOUNDDEV.PAS -----------------------
; The state this module shares with its Pascal half. Declared there, used here.
;
                .DATA
                EXTRN   ActualBuffer    : DWORD
                EXTRN   BytesPerSample  : BYTE
                EXTRN   ClockAccum      : WORD
StackSize       EQU     1000

                EXTRN   DevStack        : BYTE
                EXTRN   DMABuffer       : DWORD
                EXTRN   DMABufferPtr    : DWORD
                EXTRN   DMABufferSize   : WORD
                EXTRN   DMABufferYet    : BYTE
                EXTRN   DeviceIdling    : BYTE
                EXTRN   DoBassPower     : BYTE
                EXTRN   IsDmaDevice     : BYTE
                EXTRN   MixMethod       : BYTE
                EXTRN   MixRut          : WORD
                EXTRN   NumChannels     : WORD
                EXTRN   OldTimerHandler : DWORD
                EXTRN   OutSlot0        : WORD
                EXTRN   OutSlot1        : WORD
                EXTRN   OutSlot2        : WORD
                EXTRN   OutSlot3        : WORD
                EXTRN   PeriodicCount   : WORD
                EXTRN   PeriodicProc    : DWORD
                EXTRN   PeriodicStart   : WORD
                EXTRN   SoundLeft       : WORD
                EXTRN   Sounding        : DWORD
                EXTRN   SystemClockIncr : WORD
                EXTRN   Volumes         : WORD
                EXTRN   SavedSS         : WORD
                EXTRN   SavedSP         : WORD
                EXTRN   DSPWritePort    : WORD
                EXTRN   DSP8AckPort     : WORD
                EXTRN   DSPLifePort     : WORD
                EXTRN   SbCmdTimeout    : WORD
                EXTRN   SbSplTimeout    : WORD

                .CODE
; ---- the unit's own near routines, called from the chain -----------------
                EXTRN   DoGetBuffer     : NEAR
                EXTRN   GetDMACount     : NEAR

; ---- the gain ladder, the patcher and the mixing chain --------------------
; 256 unrolled steps, one per volume level, so that scaling a sample costs a
; call and an add rather than a multiply. Generated rather than written.
;
                INCLUDE VTGAIN.INC

; ==========================================================================
; SharedPoll -- the timer callback every driver shares.
;
; A driver that has no special timer needs of its own points its record's
; TimerHandler slot straight at this, so it is reached by a far call through a
; pointer and returns RETF.
; ==========================================================================
;
                DB      0
                PUBLIC  SharedPoll
; ===========================================================================
; SharedPoll -- the timer's entry into the player.
;
;   IN   nothing. It is reached from an interrupt, so it may run at ANY point
;        in any other code, including inside this unit.
;   OUT  nothing. Every register is restored.
;
; **THREE THINGS ARE TRUE OF AN INTERRUPT AND OF NOTHING ELSE**, and all three
; shape this routine:
;
;   1. It borrows whatever registers the interrupted code was using, so it saves
;      all of them -- PUSHA plus the two SEGMENT registers -- and not just the
;      ones it happens to touch.
;   2. It cannot assume DS. The interrupted code had its own, so DS is loaded
;      from SEG @DATA before any variable is read.
;   3. It can arrive again before it has finished. That is what the guard is
;      for, and why the guard cannot live in DGROUP.
;
; THE GUARD IS IN THE CODE SEGMENT, WHICH IS THE POINT OF IT. It is read and
; set at 1010 and 101a, before SS and DS are trusted -- CS is the only SEGMENT
; register an interrupt can rely on, because the processor set it. A guard in
; DGROUP would need DS to already be right, which is the thing being
; established.
; ===========================================================================
SharedPoll:
        PUSHA                             ; 1008  every general register: this
                                          ;       runs on borrowed time
        PUSH    ES
        PUSH    DS
        MOV     AX,SEG @DATA              ; 100b  the original: MOV AX,1caa
        MOV     DS,AX                     ; 100e  DS is ours from here on

        MOV     AL,BYTE PTR CS:[@@Guard]  ; 1010  already inside? CS: because
                                          ;       nothing else is safe yet
        DB      22h, 0C0h                 ; 1014  AND AL,AL -- hand-encoded, see
                                          ;       below
        JNZ     @@Out                     ; 1016  re-entered: do nothing at all
        NOP                               ; 1018  jump-sizing padding
        NOP                               ; 1019  ditto
        INC     BYTE PTR CS:[@@Guard]     ; 101a  take the guard

; **AND NOW THE STACK, WHICH IS THE OTHER THING AN INTERRUPT CANNOT TRUST.** The
; interrupted code's stack may have only a few bytes left; the work below calls
; into the driver and the mixer and needs a thousand. So the caller's SS:SP is
; saved and the routine switches to its own -- see DevStack in SOUNDDEV.PAS.
;
; DevGus does the same thing a few instructions differently, behind its own
; guard, on its own stack. Two stacks, two guards, and the pair of them are why
; neither routine may nest inside the other: both save into SavedSS/SavedSP, and
; a second save would overwrite the first.
        MOV     [SavedSS],SS              ; 101f  save the caller's stack
        MOV     [SavedSP],SP
        MOV     AX,DS
        MOV     SS,AX                     ; 1029  ours is in DGROUP
        MOV     SP,OFFSET DevStack + StackSize ; 102b  its top

        DB      32h, 0C0h                 ; 102e  XOR AL,AL
; [1.39b] "Signal that the device is not idling, and fill a bit more of the DMA
; buffer." -- the release's own words for this store and the two calls below it.
;
; ITS IDLE TEST IS NOT HERE, AND IS DISABLED THERE TOO. Just above this point
; 1.39b tests DeviceIdling and would reset the timer, explaining why: "[1.39b]
; If the device is said to be idle, reset the timer. This is to protect the
; timer period from being modified." The CALL InitTimer that would do it is
; commented out in the release, so the reason is recorded and the mechanism was
; already switched off before v1.51 dropped it.
        MOV     [DeviceIdling],AL         ; 1030  clear before the work

        CALL    @@Prepare
        CALL    DWORD PTR [PeriodicProc]  ; 1036  the installed callback

; **THE ORDER OF THESE TWO MATTERS AND THE PROCESSOR HELPS.** Writing SS leaves
; a window in which SS is the caller's and SP is still ours -- an interrupt in
; that gap would push onto an address that is the sum of two different stacks.
; The 8086 and everything after it inhibit interrupts for one instruction after
; a MOV into SS, exactly so that the SP load can follow safely. It only works
; because the two are ADJACENT: put anything between them and the guarantee is
; gone.
        MOV     SS,[SavedSS]              ; 103a  back to the caller's...
        MOV     SP,[SavedSP]              ; 103e  ...and this must come next
        DEC     BYTE PTR CS:[@@Guard]     ; 1042  release the guard, CS: again

; @@Out IS REACHED TWO WAYS and that is why it is here rather than at the end of
; the work. A re-entrant call jumps straight to it from 1016, having taken no
; guard and switched no stack -- so the restore above must NOT run for it, and
; everything below is common to both paths.
@@Out:
        POP     DS                        ; 1047  in reverse order of the pushes
        POP     ES
        POPA
        RETF                              ; 104a  far: the caller reached this
                                          ;       through a pointer, not a name
@@Guard:
        DB      0                         ; 104b  THE GUARD, and it lives in the
                                          ;       CODE SEGMENT on purpose -- see
                                          ;       the routine header
        DB      0C3h                      ; 104c  a trailing byte with no
                                          ;       instruction reaching it,
                                          ;       transcribed because it is
                                          ;       there

; ==========================================================================
; The DSP writers and the output selectors.
;
; THE WRITERS talk to a SoundBlaster: wait for the DSP to be ready, send a
; command, wait again, send the sample. THE SELECTORS choose which of them the
; mixer will call, by patching a slot -- so the per-sample path costs an
; indirect call rather than a test.
;
; TWO SELECTORS, ONE TAIL. One picks mono or stereo by its argument; the other
; forces mono and ignores both arguments. They share their ending.
;
                PUBLIC  SelectOutput
SelectOutput:
; ===========================================================================
; **THE SOUNDBLASTER WRITE PROTOCOL, WHICH EVERY BLOCK BELOW REPEATS.** The DSP
; is slower than the processor, so a byte may only be written when it says it
; is ready:
;
;   1. read the write port
;   2. if bit 7 is set the DSP is busy -- read again
;   3. when it clears, write the byte
;
; That is the whole handshake, and the three blocks here are that loop with
; different payloads: a command, then a sample, then the next.
;
; **THE WAIT IS BOUNDED AND GIVES UP BY WRITING ANYWAY.** BX is loaded with a
; timeout, decremented each turn, and `JZ` on exhaustion jumps to the SEND, not
; to an error path. That is deliberate: a card that never clears its busy bit
; would otherwise hang the machine inside an interrupt, and one late sample is a
; click where a hung timer is a dead program. The timeout is a variable --
; SbCmdTimeout for a command, SbSplTimeout for a sample -- so the two can differ.
;
; EVERY INSTRUCTION IS WRITTEN AS BYTES because this run has to reproduce the
; original's encodings exactly, and TASM would choose differently for several of
; them. The mnemonic beside each DB is what it assembles to.
; ===========================================================================
; 104d -- wait for the DSP, then send command 10h. Reached from OutSlot1 and
; jumps back into the chain at 0f73.
@@Prim1:
    DB 8Bh, 16h              ; 104d  MOV  DX,[DSPWritePort]
    DW OFFSET DSPWritePort
    DB 8Bh, 1Eh              ; 1051  MOV  BX,[SbCmdTimeout]
    DW OFFSET SbCmdTimeout
@@Wait1:
    DB 4Bh                   ; 1055  DEC  BX -- one turn of the timeout
    JZ      @@Send1          ; 1056  exhausted: send ANYWAY, see above
    DB 0ECh                  ; 1058  IN   AL,DX -- the DSP's status
    DB 0A8h, 80h             ; 1059  TEST AL,80h -- bit 7 set means busy
    JNZ     @@Wait1          ; 105b  still busy: go round again
@@Send1:
    DB 0B0h, 10h             ; 105d  MOV  AL,10h -- DSP command 10h, "direct
                             ;       DAC write": the next byte written is a
                             ;       sample, played immediately
    DB 0EEh                  ; 105f  OUT  DX,AL
    DB 0E9h, 10h, 0FFh       ; 1060  JMP 0f73, the mix step -- kept as a
                             ;       literal for now; in one module it could
                             ;       be a symbol, and that is a byte-comparison
                             ;       step of its own

; 1063 -- wait again, then write the sample byte.
@@Prim3:
; **XOR AH,80h IS A FORMAT CONVERSION, NOT ARITHMETIC.** Everything upstream of
; here carries samples as SIGNED bytes, -128..127, because that is what mixing
; wants: silence is zero and sums cancel. The SoundBlaster's direct DAC wants
; UNSIGNED, 0..255, with silence at 128. Flipping the top bit converts between
; the two in one instruction and in either direction -- it is the same operation
; both ways, which is why there is no matching instruction anywhere to undo it.
;
; This is also why SOUNDDEV.PAS fills the DMA buffer with $80 rather than zero:
; on this side of the conversion, $80 IS silence.
    DB 80h, 0F4h, 80h        ; 1063  XOR  AH,80h -- signed to unsigned
    DB 8Bh, 16h              ; 1066  MOV  DX,[DSPWritePort]
    DW OFFSET DSPWritePort
    DB 8Bh, 1Eh              ; 106a  MOV  BX,[SbSplTimeout]
    DW OFFSET SbSplTimeout
@@Wait3:
    DB 4Bh                   ; 106e  DEC  BX
    JZ      @@Send3
    DB 0ECh                  ; 1071  IN   AL,DX
    DB 0A8h, 80h             ; 1072  TEST AL,80h
    JNZ     @@Wait3
@@Send3:
    DB 8Ah, 0C4h             ; 1076  MOV  AL,AH
    DB 0EEh                  ; 1078  OUT  DX,AL -- the sample
    DB 0E9h, 11h, 0FFh       ; 1079  JMP 0f8d, the timer tail

; 107c -- the acknowledge pair. Two reads, both discarded.
@@Prim4:
    DB 8Bh, 16h              ; 107c  MOV  DX,[DSP8AckPort]
    DW OFFSET DSP8AckPort
    DB 0ECh                  ; 1080  IN   AL,DX
    DB 8Bh, 16h              ; 1081  MOV  DX,[DSPLifePort]
    DW OFFSET DSPLifePort
    DB 0ECh                  ; 1085  IN   AL,DX
    DB 0C3h                  ; 1086  RET -- NEAR

; 1087 -- mono, unconditionally. Ignores both arguments.
    DB 0C8h, 00h, 00h, 00h   ; 1087  ENTER 0,0 -- by hand
    DB 0B8h                  ; 108b  MOV  AX,imm16 ...
    DW OFFSET SetGains + 0636h    ;     ... 0d7c, the mono loop
    JMP     @@Install

; Mono or stereo, by the first argument. The DMA path, where the card is fed a
; buffer and can therefore afford stereo; the entry above is the non-DMA path,
; fed sample by sample from the timer, and a non-DMA device is always mono.
;
                PUBLIC  DevInitSbDMA
; ===========================================================================
; DevInitSbDMA -- choose the output path once, by writing addresses into slots.
;
;   IN   [BP+8]  stereo flag; [BP+6] is present and ignored
;   OUT  nothing. MixRut and OutSlot0..2 hold routine addresses afterwards.
;
; **THIS IS A DISPATCH TABLE BEING FILLED IN, AND IT IS WHY THE OUTPUT PATH HAS
; NO TESTS IN IT.** The alternative would be to ask "stereo or mono?" and
; "which card?" on every sample, inside an interrupt, thousands of times a
; second. Instead the question is answered once here and the ANSWERS ARE
; ADDRESSES: each slot is a variable holding the entry point of the routine that
; step should use, and the chain simply calls through them.
;
; So a reader looking for the code that decides how a sample is written will not
; find it in the output path. It is here, and it ran at initialisation.
;
; The addresses are written as OFFSET SetGains + a displacement because the
; targets are labels inside another routine, which an assembler will not let
; this one name directly.
; ===========================================================================
DevInitSbDMA:
    DB 0C8h, 00h, 00h, 00h   ; 1090  ENTER 0,0 -- hand-written; a PROC would
                             ;       emit its own and the bytes must match
    DB 8Ah, 46h, 08h         ; 1094  MOV  AL,[BP+8] -- the first argument
    DB 22h, 0C0h             ; 1097  AND  AL,AL
    JNZ     @@Stereo
    DB 0B8h                  ; 109b  MOV  AX,imm16 ...
    DW OFFSET SetGains + 0636h    ;     ... 0d7c, mono
    JMP     @@Install
@@Stereo:
    DB 0B8h                  ; 10a0  MOV  AX,imm16 ...
    DW OFFSET SetGains + 06B6h    ;     ... 0dfc, stereo
    JMP     @@Install        ; 10a3  EB 00 -- A JUMP TO THE NEXT INSTRUCTION.
                             ;       It does nothing and it is in the original,
                             ;       so it is here. Almost certainly the mono
                             ;       arm above and this one were once further
                             ;       apart and the assembler still emitted the
                             ;       branch after they were brought together
@@Install:
    DB 0A3h                  ; 10a5  MOV  [MixRut],AX
    DW OFFSET MixRut
    DB 0B8h                  ; 10a8  MOV  AX,imm16 ...
    DW OFFSET SetGains + 081Eh    ;     ... 0f64, the chain's first step
    DB 0A3h                  ; 10ab  MOV  [OutSlot0],AX
    DW OFFSET OutSlot0
    DB 0B8h                  ; 10ae  MOV  AX,imm16 ...
    DW OFFSET @@Prim1             ;     ... 104d
    DB 0A3h
    DW OFFSET OutSlot1
    DB 0B8h                  ; 10b4  MOV  AX,imm16 ...
    DW OFFSET @@Prim3             ;     ... 1063
    DB 0A3h                  ; 10b7  MOV  [OutSlot2],AX
    DW OFFSET OutSlot2
    DB 0B8h                  ; 10ba  MOV  AX,imm16 ...
    DW OFFSET @@Prim4             ;     ... 107c
    DB 0A3h                  ; 10bd  MOV  [OutSlot3],AX
    DW OFFSET OutSlot3
    LEAVE
    RETF    4                ; 10c1  and THIS is why the module exists

                END
