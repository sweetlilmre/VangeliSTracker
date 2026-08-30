; ==========================================================================
; DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
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
; are the linker's and not this module's. `blocks.py` therefore tops out at
; 5,958 of 5,968 bytes rather than the whole segment. Segment size is not code
; size; the docs have that as a standing warning and this is a clean instance.
;
; MEASURE THIS FILE WITH demovt/omf.py, NOT verify.py's ZERO RULE. Every
; `OFFSET DumpLoop` and every `CS:[DumpLoop+n]` displacement is a relocation,
; and TASM leaves an ADDEND in the bytes where a .TPU would leave zeros -- which
; is exactly the case verify.py's heuristic gets wrong and cost SOUNDDEV.ASM its
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
;        BX      the interleave stride between output slots
;        CL      the volume
;        DS:SI   the current position in the sample
;        ES:DI   the current position in the output buffer
;        BP      the running fractional position
;
;   MODIFIES AX, CH, SI, DI, BP, and eight immediates INSIDE ITS OWN BODY
;
; **IT MODIFIES ITSELF, AND THAT IS THE FIRST THING TO KNOW.** The fractional
; step is not held in a register during the loop -- there are not enough -- so it
; is written into the eight `ADD BP,imm16` instructions before the loop runs. The
; routine is therefore NOT re-entrant and cannot be in ROM, and the immediate
; sitting in the image, 4321h, is a placeholder that never executes.
;
; The entry computation below runs ceil(n/8) passes and JUMPS INTO the body far
; enough along that the first pass produces only the samples wanted; `NEG AL /
; AND AL,7` turns "how many do I want" into "how many do I skip" without a
; subtraction or a branch. That is also why DumpLoopSize must be an EQU: the
; eight copies have to stay identical in length or the computed entry lands
; mid-instruction.
; ===========================================================================
DumpRaw:
; 148f..14b6 -- write the fractional step into all eight copies of the
; `ADD BP,imm16` in the unrolled body. The immediate left in the image is 4321h,
; which is a placeholder and never executed unpatched.
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*0],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*1],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*2],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*3],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*4],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*5],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*6],DX
                MOV     WORD PTR CS:[DumpLoop+DumpPatchOfs+DumpLoopSize*7],DX

                MOV     DL,CH                   ; 14b7  the integer step
                XOR     DH,DH                   ; 14b9

; 14bb..14d7 -- AL is the sample count. CH becomes the number of whole groups of
; eight, rounded up, and the entry point is displaced into the body by however
; many of the eight are not wanted.
                MOV     CH,AL                   ; 14bb
                ADD     AX,7                    ; 14bd
                SHR     AX,3                    ; 14c0
                XCHG    AL,CH                   ; 14c3
                AND     AL,7                    ; 14c5
                JZ      SHORT DumpLoop          ; 14c7  SHORT: no JUMPS padding
                NEG     AL                      ; 14c9
                AND     AL,7                    ; 14cb
                MOV     AH,DumpLoopSize         ; 14cd
                NOP                             ; 14cf  JUMPS padding
                NOP                             ; 14d0
                MUL     AH                      ; 14d1
                ADD     AX,OFFSET DumpLoop      ; 14d3
                JMP     AX                      ; 14d6

; **THE RELEASE'S OWN ACCOUNT OF THIS LOOP SURVIVES, COMMENTED OUT.**
; LIB/PLAYMOD.PAS carries this same kernel inside `UnCanal` as inline assembler,
; wrapped in a `(* *)` block roughly ten thousand characters long and annotated
; line by line in Spanish. Lines marked [1.39b] below are its author's words in
; translation, not ours.
;
; The register contract it states:
;
;     [1.39b] "The loop. Entered with: DL = volume, BL = fractional part of the
;              increment, BP = integer part of the increment, BH = fractional
;              part of the position within the sample, SI = integer part of the
;              position within the sample, ES = segment of the buffer, DI =
;              offset within the buffer, CX = number of samples to produce."
;
; THE REGISTERS MOVED AND THE SHAPE DID NOT. This kernel keeps the volume in CL
; rather than DL, the step in BP:DX rather than BL:BP, and the stride in BX
; rather than a self-modified immediate -- so the contract is quoted for the
; SEQUENCE it describes rather than for its register names. The body below is
; instruction for instruction what v1.51 has, which is why the same notes fit
; both trees.
;
; ONE OF ITS COMMENTS DELIBERATELY HAS NO HOME HERE. After `ADC SI,BP` the
; release tests `JC` -- "[1.39b] Carry means it has certainly passed the limit"
; -- and then checks the loop-return point. This kernel has no such test:
; UnCanal bounds every call by the distance to the next boundary and subtracts a
; loop length between calls, so the run is straight-line by construction. Placing
; that comment here would read as true and would not be.
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


; --------------------------------------------------------------------------
;  As DumpRaw, but writing silence. AX is still the sample count and the source
;  position is still advanced, eleven bytes per sample instead of fifteen.
; --------------------------------------------------------------------------
                PUBLIC  EmptyRaw
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

                MOV     CH,AL                   ; 1583
                ADD     AX,7                    ; 1585
                SHR     AX,3                    ; 1588
                XCHG    AL,CH                   ; 158b
                AND     AX,7                    ; 158d  a WORD here, a byte at 14c5
                JZ      SHORT EmptyLoop         ; 1590  SHORT: no JUMPS padding
                NEG     AL                      ; 1592
                AND     AL,7                    ; 1594
                MOV     AH,EmptyLoopSize        ; 1596
                NOP                             ; 1598  JUMPS padding
                NOP                             ; 1599
                MUL     AH                      ; 159a
                ADD     AX,OFFSET EmptyLoop     ; 159c

; 159f..15a2 -- the computed jump, done with a PUSH and a RET instead of the
; release's `MOV DX,AX / JMP DX`. One byte shorter, and it clears AX on the way,
; which is the value the loop writes out.
                PUSH    AX                      ; 159f
                XOR     AX,AX                   ; 15a0
                RET                             ; 15a2

EmptyLoop:                                      ; 15a3
                REPT    8
                MOV     WORD PTR ES:[DI],AX
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
                ENTER   0,0                     ; 1600  hand-written, not a PROC
                LES     DI,[BP+16h]             ; 1604  Src

; 1607..163d -- decide whether Max samples will run past the boundary. Three
; cheap escapes to the long path first: a silent call reads nothing, and a zero
; step never moves.
                MOV     CH,[BP+04h]             ; 1607  Silent
                AND     CH,CH                   ; 160a
                JNZ     @@long                  ; 160c
                NOP                             ; 160e  JUMPS padding
                NOP                             ; 160f
                NOP                             ; 1610

                MOV     CX,[BP+0Eh]             ; 1611  Step, high word
                OR      CX,[BP+0Ch]             ; 1614  ... or low word
                JZ      @@long                  ; 1617
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
