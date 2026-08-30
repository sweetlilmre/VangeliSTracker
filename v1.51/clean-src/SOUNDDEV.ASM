; ==========================================================================
; DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).
;
; 1a17:0746 .. 1a17:10c3 -- the gain ladder, the mixing chain, the shared
; poll and the output selectors: ONE frameless run with three entry points
; and two different returns.
;
; WHY THIS IS AN ASSEMBLER MODULE AND NOT PASCAL. It was transcribed as three
; Pascal `assembler` procedures and cost four bytes that no source shape could
; reach -- an epilogue at 1007 where the original has a 00 pad, another at
; 104d, and a near RET at 10c1 where the original ends RETF 4. A Pascal
; procedure has one entry and one exit; this run has neither. The original
; built it the way the 1.39b release still builds this same unit: an external
; TASM module linked with $L. LIB/SOUNDDEV.PAS line 744 is that $L, and
; LIB/SOUNDDEV.ASM is a 902-line module whose entry points are bare PUBLIC
; labels.
;
; AND THE ENCODINGS SAY SO. TASM and Turbo Pascal's inline assembler disagree
; on the direction bit, and every disputed byte in this run is TASM's:
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
; MASM mode, not IDEAL. The release uses IDEAL; this file keeps MASM mode
; because the transcription was written in Turbo Pascal's asm syntax, which
; MASM mode accepts almost verbatim, and a syntax rewrite of 2,400 verified
; bytes is not something to bundle with a structural change. LOCALS is OFF
; deliberately: @@Name is then an ordinary identifier and every label is
; module-global, which is what lets SharedPoll reference @@Prepare inside the
; ladder. As inline Pascal asm that call had to be a hand-computed literal.
;
; THE BYTES ARE NOT MEANT TO CHANGE by moving here. Instructions transcribed
; as DB stay DB even where TASM would now assemble the mnemonic to the right
; byte -- converting them is a separate step with its own comparison.
; ==========================================================================

                MODEL   TPASCAL
                P286

; ---- DGROUP variables, all declared in SOUNDDEV.PAS -----------------------
; Every one of these is a linker fixup, so units.py cannot check them; they
; are checked by reading, and by risk 1 whenever the link happens.
                .DATA
                EXTRN   ActualBuffer    : DWORD
                EXTRN   BytesPerSample  : BYTE
                EXTRN   ClockAccum      : WORD
; StackSize IS THE RELEASE'S OWN NAME AND ITS OWN VALUE. LIB/SOUNDDEV.ASM
; declares StackSize EQU 1000 and reaches the stack's top with
; MOV SP,OFFSET DevStack + StackSize at all four of its switches. TASM
; cannot see the Pascal DevStkSize, so the constant is declared here as the
; release declares it, with the same name and the same number.
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

; ---- 0746..1007 : the gain ladder, the patcher and the mixing chain ------
; GENERATED. python emit_gain.py > src/VTGAIN.INC
                INCLUDE VTGAIN.INC

; ==========================================================================
; 1a17:1008 -- SharedPoll. The timer callback every driver shares.
;
; A far slot: VTSILENC stores @SoundDevices.SharedPoll in its driver record,
; so it is reached by a far call and returns with the RETF written at 104a.
; The re-entrancy guard at 104b is a byte of DATA INSIDE THE CODE, addressed
; CS-relative, which is why it cannot move to DGROUP.
; ==========================================================================
; 1007 -- ONE BYTE OF PADDING, and it is the byte this whole module was built
; to explain. The ladder's run ends at 1006 on an unconditional JMP; SharedPoll
; begins at 1008, an EVEN address. As three Pascal procedures this byte came out
; as the compiler's epilogue RET and could not be anything else. Here it is what
; the original always was: an assembler aligning its next entry point.
;
; DB 0 AND NOT `EVEN`. TASM pads with 90h, the NOP it would want to be executed
; through; the original's pad is 00, so whatever aligned it filled with zero.
; One byte, and it was the last difference in the whole module.
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
;      all of them -- PUSHA plus the two segment registers -- and not just the
;      ones it happens to touch.
;   2. It cannot assume DS. The interrupted code had its own, so DS is loaded
;      from SEG @DATA before any variable is read.
;   3. It can arrive again before it has finished. That is what the guard is
;      for, and why the guard cannot live in DGROUP.
;
; THE GUARD IS IN THE CODE SEGMENT, WHICH IS THE POINT OF IT. It is read and
; set at 1010 and 101a, before SS and DS are trusted -- CS is the only segment
; register an interrupt can rely on, because the processor set it. A guard in
; DGROUP would need DS to already be right, which is the thing being
; established.
; ===========================================================================
SharedPoll:
        PUSHA                             ; 1008  every general register: this
                                          ;       runs on borrowed time
        PUSH    ES                        ; 1009
        PUSH    DS                        ; 100a
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
        MOV     [SavedSP],SP              ; 1023
        MOV     AX,DS                     ; 1027
        MOV     SS,AX                     ; 1029  ours is in DGROUP
; A HARDCODED ADDRESS COPIED FROM v1.31b, AND RIGHT THERE BY COINCIDENCE ONLY.
; 3F1Ah was where that build's stack ended; this build's is elsewhere, and the
; instruction assembles identically either way. Computed from the symbol now --
; see `transcribe-the-meaning-not-the-constant` in the kit.
        MOV     SP,OFFSET DevStack + StackSize ; 102b  its top

; TWO INSTRUCTIONS ARE WRITTEN AS BYTES, AND THE REASON IS THE DIRECTION BIT.
; `AND AL,AL` and `XOR AL,AL` can each be encoded two ways -- register-to-
; register operations carry a bit saying which operand the assembler treats as
; the destination, and both encodings do the same thing. The original used one;
; TASM emits the other. DB is the only way to keep the byte. See
; `direction-bit-names-basm` in the kit, which is the same fact used in reverse
; to tell hand-written assembler from compiler output.
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

; 1033 -- THE CALL TO @@Prepare AT 1a17:0edf. As inline Pascal asm this had to
; be DB 0E8h, 0A9h, 0FEh, a hand-computed literal, because @@Prepare is a label
; in a different procedure. In one module it is a symbol again.
        CALL    @@Prepare                 ; 1033
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
        POP     ES                        ; 1048
        POPA                              ; 1049
        RETF                              ; 104a  far: the caller reached this
                                          ;       through a pointer, not a name
@@Guard:
        DB      0                         ; 104b  THE GUARD, and it lives in the
                                          ;       CODE segment on purpose -- see
                                          ;       the routine header
        DB      0C3h                      ; 104c  a trailing byte with no
                                          ;       instruction reaching it,
                                          ;       transcribed because it is
                                          ;       there

; ==========================================================================
; 1a17:104d .. 1a17:10c3 -- the DSP writers and the output selectors.
;
; 1087 and 1090 SHARE A TAIL and both open with a hand-written ENTER 0,0 and
; close LEAVE / RETF 4 -- which no two Pascal procedures can do, and which is
; the clearest single sign that this run was never compiled.
;
; 1090 picks by its FIRST argument; 1087 forces mono and ignores both. The
; four bytes of arguments are what the RETF 4 removes.
; ==========================================================================
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
    JZ      @@Send3          ; 106f
    DB 0ECh                  ; 1071  IN   AL,DX
    DB 0A8h, 80h             ; 1072  TEST AL,80h
    JNZ     @@Wait3          ; 1074
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
    JMP     @@Install        ; 108e

; 1090 -- mono or stereo, by the FIRST argument.
;
; IT NEEDED A NAME OF ITS OWN, and 193a is what asked for it: 193a:0352 calls
; 1a17:1090 directly, so the second entry point has to be PUBLIC. The release
; calls this pair DevInitSbNonDMA (1087) and DevInitSbDMA (1090), which is
; exactly what "1087 forces mono and ignores both arguments" means -- a
; non-DMA device is always mono.
;
; A LABEL EMITS NO BYTES. SOUNDDEV verified identical before this and must
; after; that is the check, not an argument.
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
    JNZ     @@Stereo         ; 1099
    DB 0B8h                  ; 109b  MOV  AX,imm16 ...
    DW OFFSET SetGains + 0636h    ;     ... 0d7c, mono
    JMP     @@Install        ; 109e
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
    DB 0A3h                  ; 10b1
    DW OFFSET OutSlot1
    DB 0B8h                  ; 10b4  MOV  AX,imm16 ...
    DW OFFSET @@Prim3             ;     ... 1063
    DB 0A3h                  ; 10b7  MOV  [OutSlot2],AX
    DW OFFSET OutSlot2
    DB 0B8h                  ; 10ba  MOV  AX,imm16 ...
    DW OFFSET @@Prim4             ;     ... 107c
    DB 0A3h                  ; 10bd  MOV  [OutSlot3],AX
    DW OFFSET OutSlot3
    LEAVE                    ; 10c0
    RETF    4                ; 10c1  and THIS is why the module exists

                END
