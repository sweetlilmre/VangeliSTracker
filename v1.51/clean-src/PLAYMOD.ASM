; ==========================================================================
; DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).
;
; THE RESAMPLING KERNELS: the innermost loop of the whole player, and the one
; Pascal entry that chooses between them.
;
; WHAT RESAMPLING IS, AND WHY IT IS THE HOT LOOP. A module's samples were
; recorded at whatever rate they were recorded at, and each note plays them
; back at a different speed -- that is what pitch IS on an Amiga tracker. The
; output buffer, meanwhile, is filled at one fixed rate. So for every single
; output sample, every channel has to be read at a fractional position that
; advances by a per-channel step: 22,000 times a second, times eight channels.
; Nothing else in the program runs that often, and it is the only reason any
; of this is assembler.
;
; THREE THINGS HAPPEN PER SAMPLE, and the kernels differ only in how:
;
;     step the fractional source position, and take the whole part
;     scale the sample by the channel's volume
;     add it into the buffer, or store it, or skip it entirely
;
; DumpRaw mixes a channel in; EmptyRaw writes silence at the same cost, so a
; silent channel does not need a branch in the caller; DumpInstrument is the
; Pascal-callable entry that sets the registers up and picks one.
;
;       2E 89 16 E3 14     MOV WORD PTR CS:[14E3],DX
;
; a store into the code SEGMENT, patching an immediate inside this same module.
; No Pascal statement produces that. 1.39b builds the same code the same way,
; from LIB/PLAYMOD.ASM under a $L, and this file is its 1.31 counterpart.
;
; Same instruction, same SEGMENT, two different encodings, because two different
; tools emitted them. Likewise AND CH,CH is 22 ED here and SUB AX,CX is 2B C1,
; both the forms Turbo Pascal's own inline assembler does not choose.
;
;
; THE NOPs ARE THE ORIGINAL ASSEMBLER'S PADDING, NOT DEAD CODE.
;
; There are eleven runs of NOPs in this module and every one of them sits
; immediately after a jump. They are TASM's `JUMPS` padding: with JUMPS enabled
; the assembler reserves the long form of a conditional jump on the first pass,
; and when the target turns out to be in short range it fills what it reserved
; with NOPs rather than moving anything.
;
;       reserved 5 for a Jcc, used 2   ->  3 NOPs   (eight sites)
;       reserved 3 for a JMP, used 2   ->  1 NOP    (two sites)
;       reserved 4 for MOV AH,<fwd>    ->  2 NOPs   (two sites)
;
; THE EVIDENCE IS THAT EVERY PADDED JUMP IS A FORWARD REFERENCE AND EVERY
; UNPADDED ONE IS NOT. The three backward jumps -- 1552 and 15fd closing the two
; unrolled loops, and 16fa jumping back to @@nomues -- carry no padding at all,
; because their targets were already known when the assembler reached them. The
; two forward jumps that are also unpadded, 14c7 and 1590, are the two the
; release writes with an explicit `SHORT` override (LIB/PLAYMOD.ASM lines 77 and
; 158), which suppresses JUMPS. Four independent cases, all consistent.
;
; The NOPs are written out EXPLICITLY here rather than left to this TASM's own
; JUMPS handling. Our TASM is a 4.1 from 1996 and its padding decisions are no
; more the author's than TP 7.01's codegen was; explicit NOPs are byte-exact by
; construction, and the mechanism is recorded above instead of relied upon.
; Turning them back into `JUMPS` plus forward references is optional cleanup of
; exactly the kind SOUNDDEV.ASM's header lists -- worth one byte comparison of
; its own, and not worth risking this one on.
;
;
; WHAT THE THREE ROUTINES ARE.
;
; DumpRaw  (148f) resamples eight samples per iteration into a stereo-strided
;          output. It is entered with a computed jump into the middle of the
;          unrolled body so that a partial group of fewer than eight costs
;          nothing extra -- `AND AL,7 / NEG AL / AND AL,7 / MUL DumpLoopSize /
;          ADD AX,OFFSET DumpLoop / JMP AX`.
;
; EmptyRaw (1555) is the same skeleton with the sample fetch and the volume
;          multiply removed: it writes silence and still advances the source
;          position, eleven bytes per sample instead of fifteen.
;
;          IT IS 8-WAY, NOT THE RELEASE'S 16-WAY, AND IT ADVANCES THE SOURCE IN
;          THE LOOP. 1.39b's EmptyRaw unrolls sixteen times, computes the whole
;          source advance once with a MUL before the loop, and writes nothing but
;          `MOV [ES:DI],AX / ADD DI,BX`. 1.31's is DumpRaw with two instructions
;          taken out, which is the earlier and simpler design. `ADD AX,7 /
;          SHR AX,3` against the release's `ADD AX,15 / SHR AX,4` is the byte
;          that fixes the eight.
;
;          It also does `PUSH ES / POP DS`, which the release does not, and it
;          ends its computed-jump sequence with `PUSH AX / XOR AX,AX / RET`
;          where the release uses `MOV DX,AX / XOR AX,AX / JMP DX` -- a
;          push-and-return computed jump, one byte shorter.
;
; DumpInstrument (1600) is the only entry Pascal calls, and 1.31 has ONE where
;          the release has two. 1.39b exports `DumpInstrument` and `DumpEmpty`
;          as separate PROCs that share their bodies through an internal label;
;          1.31 takes a `Silent : Boolean` as an eighth argument and chooses at
;          1675. `RET 22` and `[BP+04]` prove the shape: 22 bytes of arguments
;          and a NEAR return, so the parameters run from [BP+04] to [BP+19].
;
;                [BP+16]  Src       VAR, the channel's SplPosFrac onward
;                [BP+12]  Dest      VAR, the output pointer, ADVANCED by the call
;                [BP+10]  Volume    Byte, 0 for the silent call
;                [BP+0C]  Step      LongInt, StepFrac + StepInt * 65536
;                [BP+0A]  SrcLimit  Word, distance to the next boundary
;                [BP+08]  Max       Word, samples still owed
;                [BP+06]  ChanAdd   Word, NumChannels * 2, the output stride
;                [BP+04]  Silent    Boolean
;
;          NOTE `MUL WORD PTR [BP+0Dh]` AT 161F. That displacement is not the
;          start of any parameter -- it straddles Step's bytes 1 and 2, reading
;          `(Step SHR 8) AND 0FFFFh` in one instruction. The same trick is at
;          16c9. It is only expressible in assembler, and it is a second reason
;          this run was never Pascal.
;

                MODEL   TPASCAL
                P286

; The unrolled cells are generated, so their sizes are named rather than
; measured after the fact as the release does it -- a forward `=` is what the
; two-NOP runs came from, and naming the value up front keeps the arithmetic in
; the source where it can be read.
;
;   DumpLoop cell   MOV AL,[SI] 2 / IMUL CL 2 / MOV ES:[DI],AX 3 /
;                   ADD DI,BX 2 / ADD BP,imm16 4 / ADC SI,DX 2   = 15
;   EmptyLoop cell  MOV ES:[DI],AX 3 / ADD DI,BX 2 /
;                   ADD BP,imm16 4 / ADC SI,DX 2                 = 11
;
; and the patched immediate is the last two bytes of the `ADD BP,imm16`, so it
; sits 11 bytes into a Dump cell and 7 into an Empty one.

DumpLoopSize    EQU     15
DumpPatchOfs    EQU     11
EmptyLoopSize   EQU     11
EmptyPatchOfs   EQU     7

                .CODE

; --------------------------------------------------------------------------
;  DS:SI.BP = Src  pos.     -> DS:SI.BP
;  ES:DI    = Dest pos.     -> ES:DI
;  CH.DX    = Src Incr.     -> DX:mem
;  CL       = Volume.       -> CL
;  BX       = Dest Incr.    -> BX
;  AX       = Loop Len.     -> CH*8
;
;  (the register contract is the release's own comment, LIB/PLAYMOD.ASM 49..54)
; --------------------------------------------------------------------------
                PUBLIC  DumpRaw
; ===========================================================================
; DumpRaw -- mix one channel's samples into the buffer, resampling as it goes.
;
;   IN   AL      how many samples to produce
;        CH      the integer part of the step
;        DX      the fractional part of the step (patched into the body)
;        BX      the interleave stride, in bytes, between output slots
;        CL      the volume
;        DS:SI   the current position in the sample
;        ES:DI   the current position in the output buffer
;        BP      the running fractional position
;
;   OUT  SI, DI and BP advanced; the buffer written
;
;   MODIFIES AX, CH, SI, DI, BP, and eight immediates INSIDE ITS OWN BODY
;
; **IT MODIFIES ITSELF, AND THAT IS THE FIRST THING TO KNOW.** The fractional
; step is not held in a register during the loop -- there are not enough -- so it
; is written directly into the eight `ADD BP,imm16` instructions before the loop
; runs. The routine is therefore NOT re-entrant and cannot be in ROM, and the
; immediate sitting in the image, 4321h, is a placeholder that never executes.
; ===========================================================================
DumpRaw:
; Write the fractional step into all eight copies of the `ADD BP,imm16` in the
; unrolled body. Eight separate stores rather than a loop: the loop would cost
; more than the seven extra instructions, and this runs once per channel per
; buffer fill.
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*0],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*1],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*2],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*3],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*4],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*5],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*6],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*7],DX

                MOV     DL,CH                   ; 14b7  DL := integer step
                XOR     DH,DH                   ; 14b9  DX := step, zero-extended
                                                ;       DX is now the whole-sample
                                                ;       part added by ADC SI,DX

; **ENTERING AN UNROLLED LOOP PART-WAY THROUGH, WHICH IS THE TRICK OF THIS
; ROUTINE.** The body does eight samples per pass and the caller asks for any
; count at all. Rather than test for the remainder each time round, the code
; runs ceil(n/8) passes and JUMPS INTO the body far enough along that the first
; pass does only the samples that are wanted. Every later pass starts at the top
; and does all eight.
;
; It works because the eight copies are identical and equally sized, so the
; address of copy k is DumpLoop + k * DumpLoopSize -- which is why DumpLoopSize
; is an EQU rather than a number, and why any change to the body must keep the
; eight copies the same length.
;
; On entry AL is the sample count. Worked, with AL = 11:
;
;   MOV   CH,AL      CH := 11              keep the count
;   ADD   AX,7       AX := 18              round up before dividing
;   SHR   AX,3       AX := 2               two passes: 8 + 3
;   XCHG  AL,CH      AL := 11, CH := 2     CH is the pass count for DEC CH
;   AND   AL,7       AL := 3               samples wanted in the FIRST pass
;   JZ    DumpLoop                         a multiple of 8 needs no displacement
;   NEG   AL         AL := -3
;   AND   AL,7       AL := 5               copies to SKIP, which is 8 - 3
;   MOV   AH,DumpLoopSize
;   MUL   AH         AX := 5 * DumpLoopSize
;   ADD   AX,OFFSET DumpLoop               the address of copy 5
;   JMP   AX                               enter there; copies 5,6,7 run
;
; NEG then AND 7 is the whole idea in two instructions: it turns "how many do I
; want" into "how many do I skip" without a subtraction or a branch.
                MOV     CH,AL                   ; 14bb  CH := count
                ADD     AX,7                    ; 14bd  round up...
                SHR     AX,3                    ; 14c0  ...then divide by 8
                XCHG    AL,CH                   ; 14c3  CH := passes, AL := count
                AND     AL,7                    ; 14c5  AL := count mod 8
                JZ      SHORT DumpLoop          ; 14c7  exact multiple: start at
                                                ;       the top. SHORT keeps
                                                ;       JUMPS from padding it
                NEG     AL                      ; 14c9  -k
                AND     AL,7                    ; 14cb  8-k, the copies to skip
                MOV     AH,DumpLoopSize         ; 14cd  each copy's byte length
                NOP                             ; 14cf  JUMPS padding, both of
                NOP                             ; 14d0  these; not our choice
                MUL     AH                      ; 14d1  AX := skip * size
                ADD     AX,OFFSET DumpLoop      ; 14d3  AX := the copy's address
                JMP     AX                      ; 14d6  enter the body mid-way

; THE RELEASE'S OWN ACCOUNT OF THIS LOOP SURVIVES, and lines marked [1.39b]
; below are its author's words in translation, not ours. LIB/PLAYMOD.PAS carries
; the same kernel as `UnCanal`'s inline `@@dlLoop` -- commented out with (* *)
; and preserved, annotated line by line in Spanish. See docs/08-release-comments.md.
;
; The register contract it states for the loop:
;
;     [1.39b] "The loop. Entered with: DL = volume, BL = fractional part of the
;              increment, BP = integer part of the increment, BH = fractional
;              part of the position within the sample, SI = integer part of the
;              position within the sample, ES = SEGMENT of the buffer, DI =
;              offset within the buffer, CX = number of samples to produce."
;
; **THE REGISTERS MOVED AND THE SHAPE DID NOT.** v1.51 keeps the volume in CL
; rather than DL, the step in BP:DX rather than BL:BP, and the stride in BX
; rather than in a self-modified immediate -- so the contract above is the
; earlier version's, and it is quoted for the SEQUENCE it describes rather than
; for the register names.
;
; ONE OF ITS COMMENTS DELIBERATELY HAS NO HOME HERE. After `ADC SI,BP` the
; release tests `JC @@dlSplLoop` -- "[1.39b] Carry means it has certainly passed
; the limit" -- and then checks the loop-return point. This kernel has no such
; test: `UnCanal` bounds every call by the distance to the next boundary and
; subtracts a loop length between calls, so the run is straight-line by
; construction. The release's carry and loop-wrap notes describe a routine v1.51
; does not have, and they are left out rather than placed where they would read
; as true.
DumpLoop:
                REPT    8
                MOV     AL,[SI]                 ; [1.39b] read the sample for
                                                ;   this position
                IMUL    CL                      ; [1.39b] multiply by the volume
                MOV     WORD PTR ES:[DI],AX     ; [1.39b] store it in the buffer
                ADD     DI,BX                   ; on to the next slot; BX is the
                                                ;   interleave stride
                ADD     BP,4321h                ; [1.39b] add the fractional
                                                ;   increment. 4321h IS A
                                                ;   PLACEHOLDER -- DumpRaw
                                                ;   patches all eight copies
                ADC     SI,DX                   ; [1.39b] add the integer
                                                ;   increment, carrying the
                                                ;   fraction into it
                ENDM

                DEC     CH
                JNZ     DumpLoop                ; 1552  backwards: no padding
                RET                             ; 1554  NEAR -- an internal call


; ===========================================================================
; EmptyRaw -- as DumpRaw, but writing silence.
;
;   IN   AL      how many samples to produce
;        CH      the integer part of the step
;        DX      the fractional part of the step (patched into the body)
;        BX      the interleave stride
;        ES:DI   the current position in the output buffer
;        BP      the running fractional position
;
;   OUT  DI and BP advanced; SI advanced as if a sample had been read
;
;   MODIFIES AX, CH, DS, SI, DI, BP, and its own eight immediates
;
; **IT STILL ADVANCES THE SOURCE POSITION**, which is the only surprising thing
; about it. Nothing is read -- there is no `MOV AL,[SI]` in the body -- but the
; `ADD BP / ADC SI` pair is kept, so a channel that goes quiet and comes back
; resumes where it would have been rather than where it stopped. Eleven bytes
; per sample instead of fifteen.
;
; DS IS OVERWRITTEN AND THAT IS SAFE HERE. `PUSH ES / POP DS` below points DS at
; the buffer, because with no source to read the SEGMENT is wanted only for
; `ADC SI,DX` to carry into. DumpRaw could not do this.
; ============================================================================
                PUBLIC  EmptyRaw
; [1.39b] "The loop for an empty sample. It cannot be removed, because it has
;          to at least fill the buffer with zeros."
;
; That is the whole reason this routine exists, and it is not deducible from the
; bytes: a silent channel still has to WRITE its silence, because the buffer is
; summed rather than cleared.
;
; **IT ADVANCES THE POSITION TOO, WHERE THE RELEASE'S DOES NOT.** 1.39b's
; `@@Desactivado` is three instructions -- store the zero, step the buffer
; pointer, `LOOP` -- and keeps no sample position at all. This one carries the
; same `ADD BP / ADC SI` pair as DumpLoop, so a channel that falls silent and
; resumes comes back where it would have been rather than where it stopped.
EmptyRaw:
                MOV     WORD PTR CS:[EmptyLoop+EmptyPatchOfs+EmptyLoopSize*0],DX
                MOV     WORD PTR CS:[EmptyLoop+EmptyPatchOfs+EmptyLoopSize*1],DX
                MOV     WORD PTR CS:[EmptyLoop+EmptyPatchOfs+EmptyLoopSize*2],DX
                MOV     WORD PTR CS:[EmptyLoop+EmptyPatchOfs+EmptyLoopSize*3],DX
                MOV     WORD PTR CS:[EmptyLoop+EmptyPatchOfs+EmptyLoopSize*4],DX
                MOV     WORD PTR CS:[EmptyLoop+EmptyPatchOfs+EmptyLoopSize*5],DX
                MOV     WORD PTR CS:[EmptyLoop+EmptyPatchOfs+EmptyLoopSize*6],DX
                MOV     WORD PTR CS:[EmptyLoop+EmptyPatchOfs+EmptyLoopSize*7],DX

                MOV     DL,CH
                XOR     DH,DH

; 1581 -- DS := ES. Nothing is read from the source here, so the SEGMENT is only
; wanted for the `ADC SI,DX` to carry into, and the caller's DS is not needed.
                PUSH    ES
                POP     DS

; The same part-way entry as DumpRaw -- see the worked example there. Only two
; things differ, and both are the original's own inconsistency rather than a
; design: the mask below is a WORD where DumpRaw's is a byte, and the jump at
; the end is a PUSH/RET where DumpRaw's is a JMP.
                MOV     CH,AL                   ; 1583  CH := count
                ADD     AX,7                    ; 1585  round up...
                SHR     AX,3                    ; 1588  ...then divide by 8
                XCHG    AL,CH                   ; 158b  CH := passes
                AND     AX,7                    ; 158d  A WORD HERE, a byte at
                                                ;       14c5. AH is already zero
                                                ;       so both give the same
                                                ;       answer -- one byte apart
                                                ;       in encoding and no
                                                ;       difference in effect
                JZ      SHORT EmptyLoop         ; 1590  SHORT: no JUMPS padding
                NEG     AL
                AND     AL,7
                MOV     AH,EmptyLoopSize
                NOP                             ; 1598  JUMPS padding
                NOP
                MUL     AH
                ADD     AX,OFFSET EmptyLoop

; **A COMPUTED JUMP WRITTEN AS A RETURN.** `PUSH AX / RET` goes wherever AX
; says, exactly as `JMP AX` would -- RET pops an address and jumps to it, and it
; does not care that nothing called it. This costs one byte less than the
; release's `MOV DX,AX / JMP DX`.
;
; AND THE BYTE SAVED IS NOT THE POINT. Once the address is on the stack, AX is
; free, so the XOR between the push and the return is not a spare instruction --
; it loads the silence this routine is about to write. `MOV WORD PTR ES:[DI],AX`
; in the body is storing that zero. One register, used for the jump target and
; then for the payload, with the stack holding the target across the change.
;
; A reader who takes this for a return will look for the call that matched it
; and not find one.
                PUSH    AX                      ; 159f  the entry address...
                XOR     AX,AX                   ; 15a0  ...frees AX for the zero
                RET                             ; 15a2  "return" INTO the body

EmptyLoop:
                REPT    8
                MOV     WORD PTR ES:[DI],AX     ; [1.39b] store the zero in the
                                                ;   buffer
                ADD     DI,BX
                ADD     BP,4321h
                ADC     SI,DX
                ENDM

                DEC     CH
                JNZ     EmptyLoop               ; 15fd  backwards: no padding
                RET


; --------------------------------------------------------------------------
; DumpInstrument -- the only entry Pascal calls: set the registers up from the
; stack frame, pick a kernel, run it.
;
;   FUNCTION DumpInstrument(VAR Src; VAR Dest; Volume : Byte; Step : LongInt;
;                           SrcLimit, Max, ChanAdd : Word;
;                           Silent : Boolean) : Word;
;
; Three ways out, and the result means a different thing on each:
;   @@long   the whole of Max fits before the boundary   -> 0, nothing owed
;   @@short  it does not, so only part is produced       -> Max minus what was
;   @@nomues nothing can be produced at all              -> Max, all still owed
; --------------------------------------------------------------------------
                PUBLIC  DumpInstrument
DumpInstrument:
; **THE FRAME IS THE THING TO GET RIGHT HERE**, because every `[BP+n]` below is
; a parameter and nothing in the instruction says which. Turbo Pascal pushes
; left to right and the callee cleans up, so the FIRST parameter is at the
; HIGHEST offset and the last is nearest BP. With a far call the return address
; and the saved BP occupy [BP] to [BP+3], so parameters start at [BP+4]:
;
;     [BP+16h]  Src        var, 4 bytes   the sample
;     [BP+12h]  Dest       var, 4 bytes   the buffer
;     [BP+10h]  Volume     byte, pushed as a word
;     [BP+0Ch]  Step       longint, 4 bytes -- low word at 0Ch, high at 0Eh
;     [BP+0Ah]  SrcLimit   word
;     [BP+08h]  Max        word
;     [BP+06h]  ChanAdd    word
;     [BP+04h]  Silent     boolean, pushed as a word
;
; ENTER 0,0 RATHER THAN A PROC DIRECTIVE. Written as a TASM PROC the assembler
; would generate its own prologue and its own parameter names; hand-writing it
; keeps the bytes the compiler's own frame produces, which is what this has to
; match. The cost is that the offsets above are a comment and not a symbol, so
; they are worth checking against this table rather than trusted line by line.
                ENTER   0,0                     ; 1600  hand-written, not a PROC
                LES     DI,[BP+16h]             ; 1604  ES:DI := Src

; 1607..163d -- decide whether Max samples will run past the boundary. Three
; cheap escapes to the long path first: a silent call reads nothing, and a zero
; step never moves.
                MOV     CH,[BP+04h]             ; 1607  Silent
                AND     CH,CH                   ; 160a  a silent call reads no
                                                ;       source, so no boundary
                                                ;       can be crossed
                JNZ     @@long
                NOP                             ; 160e  JUMPS padding
                NOP
                NOP

                MOV     CX,[BP+0Eh]             ; 1611  Step, high word
                OR      CX,[BP+0Ch]             ; 1614  OR'd with the low word:
                                                ;       one test for a 32-bit
                                                ;       zero, and CX is dead
                                                ;       afterwards either way
                JZ      @@long                  ; 1617  a zero step never moves,
                                                ;       so it never runs out
                NOP
                NOP
                NOP

; 161c..1624 -- Max * (Step SHR 8), taken 16 bits at a time. The displacement
; 0Dh straddles Step's bytes 1 and 2; see the header.
                MOV     AX,[BP+08h]             ; 161c  Max
                MUL     WORD PTR [BP+0Dh]
                AND     DH,DH                   ; 1622  overflowed 24 bits?
                JNZ     @@long
                NOP
                NOP
                NOP

; 1629..163d -- fold in the low byte of the step and compare the total advance
; with the boundary.
                MOV     AL,AH
                MOV     AH,DL
                PUSH    AX
                MOV     AL,[BP+0Ch]             ; 162e  Step, low byte
                XOR     AH,AH
                MUL     WORD PTR [BP+08h]       ; 1633  * Max
                POP     AX
                ADD     AX,DX
                CMP     AX,[BP+0Ah]             ; 1639  SrcLimit
                JNC     @@short
                NOP
                NOP
                NOP

; 1641..1660 -- the whole of Max fits. Load the kernels' register contract and
; hand over. `PUSH AX / POP BP` at 164a and 167e is how the fractional part of
; the source position gets into BP, which is where the kernels keep it -- so BP
; stops being a frame pointer for the duration of the call.
@@long:
                PUSH    DS
                PUSH    BP
                LDS     SI,ES:[DI+02h]           ; 1643  Src, integer part
                MOV     AX,ES:[DI]              ; 1647  Src, fraction
                PUSH    AX
                LES     DI,[BP+12h]             ; 164b  Dest
                LES     DI,ES:[DI]              ; 164e  ... dereferenced
                MOV     CL,[BP+10h]             ; 1651  Volume
                MOV     CH,[BP+0Eh]             ; 1654  Step, integer
                MOV     DX,[BP+0Ch]             ; 1657  Step, fraction
                MOV     AX,[BP+08h]             ; 165a  Max
                MOV     BX,[BP+06h]             ; 165d  ChanAdd

; 1660..167d -- and choose the kernel. Silence for no volume, for a zero step,
; or because the caller asked.
                AND     CL,CL
                JZ      @@empty
                NOP
                NOP
                NOP
                AND     CH,CH
                JNZ     @@chksilent
                NOP
                NOP
                NOP
                AND     DX,DX
                JZ      @@empty
                NOP
                NOP
                NOP
@@chksilent:
                CMP     BYTE PTR [BP+04h],0     ; 1675  Silent
                JNZ     @@empty
                NOP
                NOP
                NOP

                POP     BP                      ; 167e  the source fraction
                CALL    DumpRaw
                JMP     @@stored
                NOP                             ; 1684  JUMPS padding
@@empty:
                POP     BP
                CALL    EmptyRaw

; 1689..16a2 -- write the advanced positions back through both VAR parameters and
; report that nothing is still owed.
@@stored:
                MOV     DX,BP                   ; 1689  the new fraction
                POP     BP
                POP     DS
                LES     BX,[BP+16h]
                MOV     WORD PTR ES:[BX],DX
                MOV     WORD PTR ES:[BX+02h],SI
                LES     BX,[BP+12h]
                MOV     WORD PTR ES:[BX],DI
                XOR     AX,AX
                LEAVE
                RET     22

; 16a3..16c8 -- Max would run past the boundary, so work out how many samples
; there is room for: (SrcLimit - Src) DIV Step, in 8.8 fixed point.
@@short:
                MOV     DX,[BP+0Ah]             ; 16a3  SrcLimit
                AND     DX,DX
                JZ      @@nomues
                NOP
                NOP
                NOP

; 16ad..16b8 -- SrcLimit minus the source position, borrowing by hand: the
; subtraction is done on one byte and DX is decremented only if it borrowed.
                XOR     AL,AL
                SUB     AL,ES:[DI+01h]
                JZ      @@noborrow
                NOP
                NOP
                NOP
                DEC     DX
@@noborrow:
                MOV     AH,DL                   ; 16b9  DX:AX right by eight
                MOV     DL,DH
                XOR     DH,DH
                JMP     @@divide
                NOP                             ; 16c1  JUMPS padding

; 16c2..16c8 -- there is room for nothing at all. Every sample is still owed.
@@nomues:
                MOV     AX,[BP+08h]             ; 16c2  Max
                LEAVE
                RET     22

; 16c9..16f7 -- divide by the step, which is itself reassembled SHR 4 from the
; same straddling displacement trick. Two DIVs because the dividend is 32 bits
; and the quotient will not fit in one.
@@divide:
                MOV     CX,[BP+0Dh]
                SHL     CX,4
                MOV     BL,[BP+0Ch]
                SHR     BL,4
                OR      CL,BL
                DIV     CX
                SHL     AX,4
                PUSH    AX
                MOV     AL,DL
                SHL     AL,4
                SHR     DX,4
                MOV     AH,DL
                MOV     DL,DH
                XOR     DH,DH
                DIV     CX
                POP     CX
                ADD     AX,CX

; 16f0..16f7 -- round up on any remainder: a partial sample still needs its slot.
                AND     DX,DX
                JZ      @@rounded
                NOP
                NOP
                NOP
                INC     AX
@@rounded:
                AND     AX,AX
                JZ      @@nomues                ; 16fa  backwards: no padding
                CMP     AX,[BP+08h]
                JC      @@clamped
                NOP
                NOP
                NOP
                MOV     AX,[BP+08h]             ; 1704  clamp to Max
@@clamped:

; 1707..1745 -- the same hand-over as @@long, but the count is on the stack so
; that what was NOT produced can be returned. Only DumpRaw is reachable here:
; every silent case left through @@long at 160c.
                PUSH    AX
                PUSH    DS
                PUSH    BP
                LDS     SI,ES:[DI+02h]
                MOV     BX,ES:[DI]
                PUSH    BX
                LES     DI,[BP+12h]
                LES     DI,ES:[DI]
                MOV     CL,[BP+10h]
                MOV     CH,[BP+0Eh]
                MOV     DX,[BP+0Ch]
                MOV     BX,[BP+06h]
                POP     BP
                CALL    DumpRaw

                MOV     DX,BP
                POP     BP
                POP     DS
                LES     BX,[BP+16h]
                MOV     WORD PTR ES:[BX],DX
                MOV     WORD PTR ES:[BX+02h],SI
                LES     BX,[BP+12h]
                MOV     WORD PTR ES:[BX],DI
                POP     CX                      ; 173c  what was produced
                MOV     AX,[BP+08h]
                SUB     AX,CX                   ; 1740  ... so this is what is owed
                LEAVE
                RET     22

                END
