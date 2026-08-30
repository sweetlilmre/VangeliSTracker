; ==========================================================================
; DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).
;
; 12ba:148f .. 12ba:1745 -- the resampling kernels and the one Pascal entry
; that chooses between them. THE WHOLE OF THE SEGMENT THAT IS NOT PASCAL.
;
; WHY THIS IS AN ASSEMBLER MODULE. Turbo Pascal lays a unit's initialisation
; block down as the last PASCAL code in the segment, and that block is at
; 141e..148e. Everything after it came from a `{$L}` object module, and the
; first instruction says so on its own: 148f is
;
;       2E 89 16 E3 14     MOV WORD PTR CS:[14E3],DX
;
; a store into the code segment, patching an immediate inside this same module.
; No Pascal statement produces that. 1.39b builds the same code the same way,
; from LIB/PLAYMOD.ASM under a $L, and this file is its 1.31 counterpart.
;
; AND THE ENCODINGS ARE TASM'S THROUGHOUT, which is the second, independent
; reason. The disputed direction bits all fall the assembler's way, and the
; contrast with the Pascal above is visible in one pair of instructions:
;
;       12ba:1320   31 C0    XOR AX,AX     <- compiled Pascal, in PlayStart
;       12ba:169d   33 C0    XOR AX,AX     <- this module
;
; Same instruction, same segment, two different encodings, because two different
; tools emitted them. Likewise AND CH,CH is 22 ED here and SUB AX,CX is 2B C1,
; both the forms Turbo Pascal's own inline assembler does not choose.
;
; MASM mode, not IDEAL, and `.CODE` with bare PUBLIC labels -- the same
; conventions SOUNDDEV.ASM settled on, for the same reasons.
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
; THE SEGMENT ENDS AT 1745 AND 1746..174F IS PADDING -- ten zero bytes, which
; are the linker's and not this module's. `blockcmp.py` therefore tops out at
; 5,958 of 5,968 bytes rather than the whole segment. Segment size is not code
; size; the docs have that as a standing warning and this is a clean instance.
;
; MEASURE THIS FILE WITH objcheck.py, NOT units.py's ZERO RULE. Every
; `OFFSET DumpLoop` and every `CS:[DumpLoop+n]` displacement is a relocation,
; and TASM leaves an ADDEND in the bytes where a .TPU would leave zeros -- which
; is exactly the case units.py's heuristic gets wrong and cost SOUNDDEV.ASM its
; first honest measurement.
; ==========================================================================

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
;              position within the sample, ES = segment of the buffer, DI =
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
DumpLoop:                                       ; 14d8
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

                DEC     CH                      ; 1550
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
; the buffer, because with no source to read the segment is wanted only for
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

                MOV     DL,CH                   ; 157d
                XOR     DH,DH                   ; 157f

; 1581 -- DS := ES. Nothing is read from the source here, so the segment is only
; wanted for the `ADC SI,DX` to carry into, and the caller's DS is not needed.
                PUSH    ES                      ; 1581
                POP     DS                      ; 1582

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
                NEG     AL                      ; 1592
                AND     AL,7                    ; 1594
                MOV     AH,EmptyLoopSize        ; 1596
                NOP                             ; 1598  JUMPS padding
                NOP                             ; 1599
                MUL     AH                      ; 159a
                ADD     AX,OFFSET EmptyLoop     ; 159c

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

EmptyLoop:                                      ; 15a3
                REPT    8
                MOV     WORD PTR ES:[DI],AX     ; [1.39b] store the zero in the
                                                ;   buffer
                ADD     DI,BX
                ADD     BP,4321h
                ADC     SI,DX
                ENDM

                DEC     CH                      ; 15fb
                JNZ     EmptyLoop               ; 15fd  backwards: no padding
                RET                             ; 15ff


; --------------------------------------------------------------------------
; 12ba:1600 -- the only entry Pascal calls. See the header for the frame.
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
                JNZ     @@long                  ; 160c
                NOP                             ; 160e  JUMPS padding
                NOP                             ; 160f
                NOP                             ; 1610

                MOV     CX,[BP+0Eh]             ; 1611  Step, high word
                OR      CX,[BP+0Ch]             ; 1614  OR'd with the low word:
                                                ;       one test for a 32-bit
                                                ;       zero, and CX is dead
                                                ;       afterwards either way
                JZ      @@long                  ; 1617  a zero step never moves,
                                                ;       so it never runs out
                NOP                             ; 1619
                NOP                             ; 161a
                NOP                             ; 161b

; 161c..1624 -- Max * (Step SHR 8), taken 16 bits at a time. The displacement
; 0Dh straddles Step's bytes 1 and 2; see the header.
                MOV     AX,[BP+08h]             ; 161c  Max
                MUL     WORD PTR [BP+0Dh]       ; 161f
                AND     DH,DH                   ; 1622  overflowed 24 bits?
                JNZ     @@long                  ; 1624
                NOP                             ; 1626
                NOP                             ; 1627
                NOP                             ; 1628

; 1629..163d -- fold in the low byte of the step and compare the total advance
; with the boundary.
                MOV     AL,AH                   ; 1629
                MOV     AH,DL                   ; 162b
                PUSH    AX                      ; 162d
                MOV     AL,[BP+0Ch]             ; 162e  Step, low byte
                XOR     AH,AH                   ; 1631
                MUL     WORD PTR [BP+08h]       ; 1633  * Max
                POP     AX                      ; 1636
                ADD     AX,DX                   ; 1637
                CMP     AX,[BP+0Ah]             ; 1639  SrcLimit
                JNC     @@short                 ; 163c
                NOP                             ; 163e
                NOP                             ; 163f
                NOP                             ; 1640

; 1641..1660 -- the whole of Max fits. Load the kernels' register contract and
; hand over. `PUSH AX / POP BP` at 164a and 167e is how the fractional part of
; the source position gets into BP, which is where the kernels keep it -- so BP
; stops being a frame pointer for the duration of the call.
@@long:
                PUSH    DS                      ; 1641
                PUSH    BP                      ; 1642
                LDS     SI,ES:[DI+02h]           ; 1643  Src, integer part
                MOV     AX,ES:[DI]              ; 1647  Src, fraction
                PUSH    AX                      ; 164a
                LES     DI,[BP+12h]             ; 164b  Dest
                LES     DI,ES:[DI]              ; 164e  ... dereferenced
                MOV     CL,[BP+10h]             ; 1651  Volume
                MOV     CH,[BP+0Eh]             ; 1654  Step, integer
                MOV     DX,[BP+0Ch]             ; 1657  Step, fraction
                MOV     AX,[BP+08h]             ; 165a  Max
                MOV     BX,[BP+06h]             ; 165d  ChanAdd

; 1660..167d -- and choose the kernel. Silence for no volume, for a zero step,
; or because the caller asked.
                AND     CL,CL                   ; 1660
                JZ      @@empty                 ; 1662
                NOP                             ; 1664
                NOP                             ; 1665
                NOP                             ; 1666
                AND     CH,CH                   ; 1667
                JNZ     @@chksilent             ; 1669
                NOP                             ; 166b
                NOP                             ; 166c
                NOP                             ; 166d
                AND     DX,DX                   ; 166e
                JZ      @@empty                 ; 1670
                NOP                             ; 1672
                NOP                             ; 1673
                NOP                             ; 1674
@@chksilent:
                CMP     BYTE PTR [BP+04h],0     ; 1675  Silent
                JNZ     @@empty                 ; 1679
                NOP                             ; 167b
                NOP                             ; 167c
                NOP                             ; 167d

                POP     BP                      ; 167e  the source fraction
                CALL    DumpRaw                 ; 167f
                JMP     @@stored                ; 1682
                NOP                             ; 1684  JUMPS padding
@@empty:
                POP     BP                      ; 1685
                CALL    EmptyRaw                ; 1686

; 1689..16a2 -- write the advanced positions back through both VAR parameters and
; report that nothing is still owed.
@@stored:
                MOV     DX,BP                   ; 1689  the new fraction
                POP     BP                      ; 168b
                POP     DS                      ; 168c
                LES     BX,[BP+16h]             ; 168d
                MOV     WORD PTR ES:[BX],DX     ; 1690
                MOV     WORD PTR ES:[BX+02h],SI ; 1693
                LES     BX,[BP+12h]             ; 1697
                MOV     WORD PTR ES:[BX],DI     ; 169a
                XOR     AX,AX                   ; 169d
                LEAVE                           ; 169f
                RET     22                      ; 16a0

; 16a3..16c8 -- Max would run past the boundary, so work out how many samples
; there is room for: (SrcLimit - Src) DIV Step, in 8.8 fixed point.
@@short:
                MOV     DX,[BP+0Ah]             ; 16a3  SrcLimit
                AND     DX,DX                   ; 16a6
                JZ      @@nomues                ; 16a8
                NOP                             ; 16aa
                NOP                             ; 16ab
                NOP                             ; 16ac

; 16ad..16b8 -- SrcLimit minus the source position, borrowing by hand: the
; subtraction is done on one byte and DX is decremented only if it borrowed.
                XOR     AL,AL                   ; 16ad
                SUB     AL,ES:[DI+01h]          ; 16af
                JZ      @@noborrow              ; 16b3
                NOP                             ; 16b5
                NOP                             ; 16b6
                NOP                             ; 16b7
                DEC     DX                      ; 16b8
@@noborrow:
                MOV     AH,DL                   ; 16b9  DX:AX right by eight
                MOV     DL,DH                   ; 16bb
                XOR     DH,DH                   ; 16bd
                JMP     @@divide                ; 16bf
                NOP                             ; 16c1  JUMPS padding

; 16c2..16c8 -- there is room for nothing at all. Every sample is still owed.
@@nomues:
                MOV     AX,[BP+08h]             ; 16c2  Max
                LEAVE                           ; 16c5
                RET     22                      ; 16c6

; 16c9..16f7 -- divide by the step, which is itself reassembled SHR 4 from the
; same straddling displacement trick. Two DIVs because the dividend is 32 bits
; and the quotient will not fit in one.
@@divide:
                MOV     CX,[BP+0Dh]             ; 16c9
                SHL     CX,4                    ; 16cc
                MOV     BL,[BP+0Ch]             ; 16cf
                SHR     BL,4                    ; 16d2
                OR      CL,BL                   ; 16d5
                DIV     CX                      ; 16d7
                SHL     AX,4                    ; 16d9
                PUSH    AX                      ; 16dc
                MOV     AL,DL                   ; 16dd
                SHL     AL,4                    ; 16df
                SHR     DX,4                    ; 16e2
                MOV     AH,DL                   ; 16e5
                MOV     DL,DH                   ; 16e7
                XOR     DH,DH                   ; 16e9
                DIV     CX                      ; 16eb
                POP     CX                      ; 16ed
                ADD     AX,CX                   ; 16ee

; 16f0..16f7 -- round up on any remainder: a partial sample still needs its slot.
                AND     DX,DX                   ; 16f0
                JZ      @@rounded               ; 16f2
                NOP                             ; 16f4
                NOP                             ; 16f5
                NOP                             ; 16f6
                INC     AX                      ; 16f7
@@rounded:
                AND     AX,AX                   ; 16f8
                JZ      @@nomues                ; 16fa  backwards: no padding
                CMP     AX,[BP+08h]             ; 16fc
                JC      @@clamped               ; 16ff
                NOP                             ; 1701
                NOP                             ; 1702
                NOP                             ; 1703
                MOV     AX,[BP+08h]             ; 1704  clamp to Max
@@clamped:

; 1707..1745 -- the same hand-over as @@long, but the count is on the stack so
; that what was NOT produced can be returned. Only DumpRaw is reachable here:
; every silent case left through @@long at 160c.
                PUSH    AX                      ; 1707
                PUSH    DS                      ; 1708
                PUSH    BP                      ; 1709
                LDS     SI,ES:[DI+02h]           ; 170a
                MOV     BX,ES:[DI]              ; 170e
                PUSH    BX                      ; 1711
                LES     DI,[BP+12h]             ; 1712
                LES     DI,ES:[DI]              ; 1715
                MOV     CL,[BP+10h]             ; 1718
                MOV     CH,[BP+0Eh]             ; 171b
                MOV     DX,[BP+0Ch]             ; 171e
                MOV     BX,[BP+06h]             ; 1721
                POP     BP                      ; 1724
                CALL    DumpRaw                 ; 1725

                MOV     DX,BP                   ; 1728
                POP     BP                      ; 172a
                POP     DS                      ; 172b
                LES     BX,[BP+16h]             ; 172c
                MOV     WORD PTR ES:[BX],DX     ; 172f
                MOV     WORD PTR ES:[BX+02h],SI ; 1732
                LES     BX,[BP+12h]             ; 1736
                MOV     WORD PTR ES:[BX],DI     ; 1739
                POP     CX                      ; 173c  what was produced
                MOV     AX,[BP+08h]             ; 173d
                SUB     AX,CX                   ; 1740  ... so this is what is owed
                LEAVE                           ; 1742
                RET     22                      ; 1743

                END
