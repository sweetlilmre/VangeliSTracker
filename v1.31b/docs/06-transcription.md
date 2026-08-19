# Transcription — what is Pascal, and what actually builds

**`CONTINUATION.md` is the entry point; read it first.** The reading pass is
finished (`03-architecture.md`); this file tracks the separate job of turning it
into compilable Turbo Pascal, in more detail than the handover carries.

**AND THAT JOB IS DONE.** Every segment compiles, every unit reproduces its segment, and
the linked EXE is byte-identical to the unpacked original. What this file is good for now
is the DETAIL: the divergence patterns, the encoding tables, the release comparison, and
the per-segment records of how each one was taken. **Its status table and its percentages
are historical** — see the banner over each.

**Read this before trusting any claim that a unit is "compilable".** The first
five units were written before a build harness existed and had never been
through a compiler. Two of them did not compile. Nothing here is believed
until `v1.31b/build.py` says so.

---

## How to build

    python v1.31b/build.py            every transcribed unit (TP 6.0)
    python v1.31b/build.py VTCTRL     one unit and its dependencies
    python v1.31b/build.py --tp61     ...with TP 6.01
    python v1.31b/build.py --tp7      ...with TP 7.01
    python v1.31b/probe.py            the compiler probe, under every TPC

Include files (`*.INC`) are staged alongside the units automatically -- they
never appear in `ORDER` because they are not compiled in their own right, but
TP7 looks for them beside the `.PAS`.

It reuses `tools/dosbox/vt131.conf` unchanged, which mounts `D:` on
`<root>/build` and runs `D:\BUILD.BAT`. **It therefore shares the build
directory with `tools/dosbox/dosbuild.py`, and both wipe it on entry** — run
one, read the result, then run the other. Never both at once.

No 8.3 renaming happens, unlike the main project: every DemoVT filename is
already 8.3 and every unit identifier already matches its filename.

The script lints first, using `tools/paslint.py`'s checker imported directly
(paslint's own `main()` hardcodes the main project's `src/`). That lint is not
optional — TP7 reports a nested-comment defect dozens of lines from its cause,
and it has now cost time on this tree twice.

---

## State

**THIS TABLE IS SUPERSEDED AND IS KEPT AS A RECORD OF THE ORDER THINGS LANDED IN.** It was
written while units were still arriving one at a time, and it still calls `PLAYMOD.PAS` "in
progress", `PLAYMOD.ASM` "a STUB" and `VTMAIN.PAS` "blocked". None of that is true: every
segment is transcribed, every unit reproduces its segment, and the whole build is
byte-identical to the unpacked original.

**The current state is computed, never tabulated.** Run the eight commands at the top of
`CONTINUATION.md` — `verify.py`, `asmcheck.py`, `linkorder.py`, `mapcmp.py`, `dgroup.py`,
`progcmp.py`, `linkcmp.py`, `coverage.py`. A table in a document goes stale within a
session; those do not.

| segment | file | bytes | status |
|---|---|---|---|
| — | `SONGUNIT.PAS` | — | **builds** — the shared module record, no code |
| `1642` | `ASCIIZ.PAS` | 144 | **builds, BYTE-IDENTICAL** |
| `1650` | `VTNOTES.PAS` | 160 | **builds** |
| `1544` | `FILTERS.PAS` | 144 | **builds** |
| `14b7` | `VTCTRL.PAS` | 32 | **builds** |
| `188f` | `VTDOSRSZ.PAS` | 32 | **builds** |
| `1880` | `VTDOSMEM.PAS` | 240 | **builds** |
| `116a` | `FILEUTIL.PAS` | 64 | **builds, BYTE-IDENTICAL** |
| `1931` | `VTSHELL.PAS` | 159 | **builds** |
| `1b24` | `HARDWARE.PAS` | 768 | **builds** |
| — | `VTDRIVER.PAS` | — | **builds** — the shared driver record, no code |
| `1084` | `DEVGUS.PAS` | 384 | **builds** -- 376 exactly, see 08 |
| `1723` | `GUS.PAS` | 2752 | **builds, COMPLETE** -- 0 real mismatches |
| `1a17` | `SOUNDDEV.ASM` | 2430 | **assembles, COMPLETE** -- the $L module, 0 real mismatches |
| `1a17` | `SOUNDDEV.PAS` | 4304 | **builds, COMPLETE** -- 0 real mismatches |
| `1065` | `VTSILENC.PAS` | 491 | **builds** |
| `164b` | `UNKLOADE.PAS` | 80 | **builds** |
| `1b54` | `VTRESID.PAS` | 432 | **builds, COMPLETE** -- 0 real mismatches |
| `12ba` | `PLAYMOD.PAS` | 5968 | **IN PROGRESS** -- 0187 of it, byte-exact |
| `12ba` | `PLAYMOD.ASM` | -- | the `1600` kernel: a STUB, not transcribed |
| `1000` | `VTMAIN.PAS` | 1621 | written, **blocked** |

Blocked means transcribed but not compilable yet, for a real reason rather
than a defect, and the build reports it as such rather than as a pass or a
failure.

**Nothing is blocked on a missing unit any more except the program itself.**
`DEVGUS` and `VTSILENC` waited on `1a17` alone -- `02ba` for `RegisterDriver`
and `1008` for the shared poll -- and both now compile against the real
`SOUNDDEV`. `DEVGUS`'s five `Unit_1723_*` placeholders went at the same time;
the hardware layer had been built for some while and nobody had gone back to
wire it up.

### `SOUNDDEV` -- `1a17` IS COMPLETE, with ZERO real mismatches

Every routine in the segment is transcribed. Compared piecewise at the shift
each region sits at:

    lifecycle, device list       588 bytes   155 fixups   0 mismatches
    rate, queue, unit init      1184         285          0
    GetPlayPos prologue           16           4          0
    GetPlayPos body               47           8          0
    the gain ladder              996         168          0
    filter chains + kernels     1245         172          0
    SharedPoll                    69          22          0
    DSP writers + selectors      116          35          0

**4303 of 4303 bytes. IDENTICAL, with 1,024 pending fixups.** It was six
divergent regions at the start of the session: `0710`/`0716` turned out to be
hand-written asm, `0746` a JMP the procedure never needed, and the last four
bytes went when `0746..10c3` moved into an external TASM module. The module's own
comparison is stricter than the `.TPU` one -- 2,430 bytes, every difference a
relocation the assembler recorded, classified field by field. Four more used to be here and TP6 closed them: `024c` and `0255`,
the inlined string copy, which TP6 compiles as the CALL the original makes, and
with them the two difflib artefacts at `03aa`/`03c1` that only existed because
the copy had displaced everything after it.

    NOTHING. Every one of these is closed.

    1007         the epilogue RET where the original    the TASM module
                 has a 00 pad -- now DB 0
    104d         SharedPoll's epilogue RETF             the TASM module
    10c1         RETF 4, now the instruction itself     the TASM module
    0710, 0716   NOT the compiler -- hand-written asm.  8 bytes
    0746         the JMP that gave SetGains a Pascal    3 bytes
                 entry point. It never needed one.

    10c4..10ce   segment padding, not code                            11

**Eight structural bytes, in four places, and they are all the same thing**: a
frameless run wrapped in Pascal procedures, each of which must have exactly one
entry and one exit that the original does not have. Three of the four are
epilogues the original never needed because its code simply continues.

#### The poll was calling a STUB, and the tool could not see it

`SharedPoll`'s `CALL @@Prepare` at `1a17:1033` pointed at a local one-byte stub
for as long as this unit has existed -- `@@Prepare` at `0edf` is inside
`SetGains`, a different procedure, so there was no symbolic way to reach it. The
docs said the poll was non-functional, which was true, but the byte comparison
never showed it: **Turbo Pascal emitted that call's displacement as ZERO in the
.TPU**, so `verify.py` filed it as a pending fixup and it read as agreement.

It is now a literal `DB 0E8h, 0A9h, 0FEh`. The displacement is self-relative and
both ends move together -- `SetGains` ends one byte before `SharedPoll` begins,
in ours as in the original -- so `-0157h` holds, and it is now a real byte that
either matches or does not. It matches, and the poll works.

**The general lesson is about the tool, not the poll**: a zero in the `.TPU` is
only evidence of a pending fixup if something is actually pending. A near call to
a local label is not, and one that comes out zero is a bug wearing a fixup's
clothes.

#### A measurement trap: a data table of OFFSETs is a LONG fixup run

The last hundred "differences" in the gain ladder were not differences at all.
`MAX_FIXUP` caps a pending fixup at four bytes, which is right for a far pointer
-- but the ladder's three pointer tables are sixteen consecutive `DW OFFSET`
entries each, so an unresolved table is a **thirty-two byte run of zeros**, and
the cap counts all of it as real. The docs recorded 132 differences in the
ladder on that basis, and the tables were correct the whole time.

`regions()` now treats an all-zero gap as fixups when it lines up with the same
number of original bytes, which is what an unresolved table looks like, while
keeping the four-byte cap for the case it was added for -- a unit that simply
STOPS, where the lengths do not match. That took the report from 132 phantom
regions to ten real ones.

The test that settles it is not the run length, it is whether OUR byte is zero --
with the caveat the poll stub just taught: zero is only innocent if something is
genuinely pending.
Across all of `1a17` there are 849 differing bytes and every one of them is zero
in the `.TPU`. **When a long run of zeros lines up against plausible data, check
for zero before believing the cap** -- and note that a prediction I made from the
cap ("the ladder's offsets are displaced and will close when `06ff` lands") was
tested when `06ff` landed and was wrong. They were never displaced.

#### `06ff..0745` -- GetPlayPos, and eight bytes of dead code

The last routine, and the call site settled what the bytes could not.
`1000:0288` is a bare `CALLF 1a17:06ff` -- no argument pushed, no register set
up -- so the `MOV DL,BytesPerSample / XOR DH,DH / MUL DX / PUSH AX` that opens
the routine multiplies whatever the demo happened to leave in AX, and the push
is discarded by `LEAVE` rather than popped. **It is dead code in the original**,
the remains of an edit where a statement that consumed `x * BytesPerSample` was
removed and its operand setup was not.

It is transcribed as an `asm` block because no Pascal produces it: any
expression the compiler accepts would also load AX first. Verbatim rather than
dropped -- dropping it would shift every byte after it. Prologue and body are
both byte-exact.

What it computes, once past that:

    Left := DMABufferSize - GetDMACount
    Result := Ptr(Seg(DMABuffer^),
                  Ofs(DMABuffer^) +
                  (DMABufferSize + Left - 100) mod DMABufferSize)

The `+ DMABufferSize` before the `mod` keeps the `- 100` from going negative on
an unsigned word; the modulo folds it back into the buffer. A hundred samples of
margin behind the play position, so the caller's mark is safely inside what has
already been played.

#### Three procedures, not one, and why that forced a compromise

`0746..10c1` is one contiguous frameless run in the original, but it has to be
THREE Pascal procedures: `SetGains` (`0746..1007`), `SharedPoll`
(`1008..104c`) and `SelectOutput` (`104d..10c1`). `SharedPoll` cannot be a label
inside the first because `VTSILENC` takes its address
(`@SoundDevices.SharedPoll`), and that splits the run.

The cost lands on `SelectOutput`, which stores six code addresses that live in
`SetGains` and so cannot reference them as labels. They are
`OFFSET SetGains + delta` instead -- a symbol plus a distance measured inside the
run, which still moves when the unit moves, so it keeps the property the
standing rule protects. The two near jumps at `1060` and `1079` that cross back
into `SetGains` have no symbolic form at all and are literal self-relative
displacements.

**AND THOSE DELTAS WERE THREE BYTES SHORT, INVISIBLY, FOR AS LONG AS THE JMP
EXISTED.** `OFFSET SetGains` was the address of the `JMP @@Patcher` that opened
the procedure, while every delta is measured from the first gain cell -- `0d7c`
is written `+0636`, which is `0d7c - 0746`. All four pointers therefore aimed
three bytes before their targets. **`verify.py` could not see it**: a `DW OFFSET`
is a linker fixup and sits in the `.TPU` as zeros, which the tool files as
pending. Removing the JMP fixed the three code bytes and four wrong pointers at
once, and only the code bytes were measurable. Risk 1, in miniature, for the
second time.

**The split itself is an artefact of the transcription, not of the original.**
The run was an external TASM module, where `SharedPoll` is a `PUBLIC` label and
no split is needed at all -- see below.

#### `0e75` -- the fill driver#### `0e75` -- the fill driver, and why it is full of SS: overrides

`LDS SI,Sounding` at `0e97` points DS at the **sample data** so the output loops
can walk it with plain `[SI]` -- which costs nothing in the inner loop and is the
whole point of doing it. But DGROUP is then unreachable through DS, so every
global touched after that line is read through `SS:` instead. SS and DS are the
same segment in a Pascal program, so the override is free. **Miss one and it
reads the sample buffer as if it were the data segment.**

The circular buffer is handled as two calls rather than a modulo: if the batch
would run past the end, `0eb6` divides the remaining bytes by `BytesPerSample`
to get how many whole samples fit, calls the loop for those, resets DI to the
start and calls again for the rest. Note the `JC` at `0e9e` -- the end-of-write
address is `AX+DI` and can carry out of sixteen bits, which is also a wrap, and
it has to be tested BEFORE the ordinary `CMP` because `CMP` would compare the
wrapped value and get it wrong.

**`0eda` answers the question DoGetBuffer left open.** 1.39b clears
`ActualBuffer^.InUse` when it RETIRES a block and 1.31's `DoGetBuffer` does not
(see the note there) -- because 1.31 clears it here instead, when the mixer has
actually finished reading the block rather than when the queue moves on. Not the
leak it looked like.

#### The direct-DAC path is a chain through the dispatch table

Worth knowing before `0edf..1007` and `104d..10c1` are written, because it is
why they interleave. `0f53` is the interrupt-time entry: it saves registers, sets
DS, and `JMP WORD PTR [0bf8]`. From there each step jumps through the next slot
of the four-entry table that `1087`/`1090` fills:

    0f53  entry            JMP [0bf8] -> 0f64
    0f64  count a sample   JMP [0bfa] -> 104d
    104d  wait, cmd 10h    JMP           0f73
    0f73  mix one sample   JMP [0bfc] -> 1063
    1063  wait, write it   JMP           0f8d
    0f8d  ...

So the path alternates between the two blocks. `104d..10c1` cannot be written
before `0edf..1007`, and neither can be verified without the other.

#### The three other mixing methods, and one piece of real cleverness

`@@MethodJmp` selects between four continuations by displacement: 0 falls through
to the mono path, and `12h`/`30h`/`5Ah` land at `0cfa`, `0d18`, `0d42`. All three
end at `@@FilterSwitch2`, which tail-calls the filter PAIR where the mono path
calls the single chain. Every arithmetic step is followed by the same 12-byte
saturating clamp -- generated by `satclamp()` rather than typed, since it occurs
seven times.

* **`0cfa`** doubles each side independently.
* **`0d18` cross-feeds by an EXACT 17-BIT AVERAGE.** This is the one worth
  stopping on: `ADD DX,BX / JNO +4 / RCR DX,1 / JMP +2 / SAR DX,1`. A signed
  16-bit sum of two 16-bit values needs seventeen bits, and when it overflows the
  seventeenth is in CF -- so `RCR` rotates it back in as the new top bit and the
  halved result is **exact rather than clamped**. Where there was no overflow,
  `SAR` halves and preserves the sign. A correct average with no widening.
* **`0d42`** halves both sides first, then cross-feeds 1.5x of their sum
  (`DX + DX shr 1`); the pre-halving is what buys room for the 1.5.

#### `0d7c` -- the mono output loop, and the loop instruction IS the channel count

What `1087`/`1090` install at `DS:$0c00`. Per sample: sum 32 channels into two
accumulators, add, saturate, convert, store one byte, advance; CX is the sample
count and `LOOP` drives it.

**It is entered at the bottom.** The `JMP` at `0d7d` goes to `@@MonoPrime`, which
loads channels 0 and 1 into the accumulators before any `ADD` runs -- so its
unrolled run is channels 31 down to **2**, thirty adds rather than the downmix's
thirty-one. Priming instead of zeroing saves two instructions per sample.

Two more patch sites, and the second is the good one:

    @@Stride2   0ddb  the row stride, as in the downmix
    @@MonoLoop  0dee  THE DISPLACEMENT OF THE LOOP INSTRUCTION. The configurator
                      writes 3 * (32 - Channels) - 70h, so the backward jump
                      lands partway INTO the unrolled run and absent channels
                      are never touched. The loop's own branch target is the
                      channel count.

**The output conversion is one instruction.** `XOR AH,80h` flips the sign bit of
the high byte, turning a signed 16-bit sample into the unsigned 8-bit one a DAC
wants -- taking the high byte IS the downshift, so there is no shift at all.

#### `0b2a..0c00` is done, and how

Byte-exact, 0 of 215, after two failed attempts. What worked: **emit every
prefixed and every register-to-register form as explicit `DB`, with the mnemonic
in the comment.** Only the jumps and the two near calls keep their labels,
because those displacements are self-relative and therefore the assembler's to
compute. Absolute operands -- the eight patch slots and the four state
immediates -- are `DW OFFSET`, per the standing rule.

It also needed one more instance of the RET problem, and this one is subtler
than the cells: the last byte, at `0c00`, is Pascal's OWN epilogue rather than a
written instruction, and an INTERFACE procedure is far, so the epilogue emitted
`CB` where the original has a near `C3`. `SetGains` came out of the interface --
nothing outside the unit calls it, and `1a17:0c7a` reaches the patcher by a near
`CALL` from inside the same run -- which makes it near and fixes the byte. **If a
frameless run's last byte is a near RET, the Pascal procedure wrapping it has to
be near too.**

#### Three encoding traps in the 66h-prefixed forms

A first attempt at `0b2a` got two of these wrong, so they are worth writing down
before the next one:

* **A `66h` prefix WIDENS THE IMMEDIATE, and the ladder's `DB 66h; MNEMONIC`
  style silently breaks on immediate forms.** `DB 66h; MOV BX,-1` assembles as
  `66 BB FF FF` -- four bytes where `MOV EBX,imm32` needs six, and the two
  bytes that follow get eaten as the rest of the immediate. Register-only forms
  like `DB 66h; SAR BX,3` are fine, which is why the gain ladder gets away with
  the style throughout. Immediate forms need the opcode as `DB` and the value as
  `DD`/`DW`, which also puts the patch label exactly on the immediate:

      DB 66h, 0BBh          { 0b2f  MOV EBX,imm32 }
    @@PrevA1:
      DD -1                 { 0b31  the immediate IS the state }

* **`CWDE` is not a Turbo Pascal 7 mnemonic.** `DB 66h; CBW` gives it -- both
  are opcode `98`.
* **The two `CS:`-override forms here do not carry the same prefixes.**
  `CALL WORD PTR CS:[@@Patch]` is `2E FF 16 nn nn` with NO `66h` -- it is a
  16-bit indirect call, only its target is 32-bit code. But
  `MOV CS:[@@PrevA1],EAX` is `66 2E A3 nn nn`, with both. Do not assume the
  prefix pattern carries across a block.

#### The remaining blocks are NOT independent, and one ordering is wrong

`104d..10c1` looked like the easy one -- 117 bytes, three short frameless
routines and two Pascal ones -- and it cannot be written on its own. `104d` and
`1063` both END in a `JMP` back into the mixing kernels, at `0f73` and `0f8d`,
so they are continuations of code in `0c7e..1007` rather than routines in their
own right. **`104d..10c1` has to follow `0c7e..1007`, not precede it.**

Two more things found while reading it, both worth knowing before starting:

* **`1087` and `1090` share a tail.** Both set up the four-entry output jump
  table at `10a5..10bf` and both end on the same `RETF 4`; `1087` forces mono
  and `1090` picks by its first parameter. Two Pascal procedures cannot share
  an epilogue, so this is either one routine with two entry points or hand
  assembler, and it needs settling before either is written.
* **`1090` tests its FIRST parameter for stereo** and ignores its second.
  docs/04-units.md records the call as `1a17:1090(8, stereo)`, which would put
  `8` in the first position and select stereo unconditionally -- so either that
  reading has the arguments the wrong way round, or the routine does. Not
  resolved.

`1a17:06ff` is also unread: it opens `ENTER 6,0 / MOV DL,[0bbe] / XOR DH,DH /
MUL DX`, and nothing has loaded AX by the time the MUL runs. Either the
instruction stream is not what it looks like or the routine is entered with a
value already in AX. Left alone rather than guessed at.

~~`VTMAIN` is the program and still reaches into eight segments through 19
`Unit_<seg>_<ofs>` placeholders:~~ **ALL NINETEEN ARE GONE** -- every segment they named is
transcribed and byte-exact, and `VTMAIN.PAS` is byte-identical. The list is kept because it
is a useful index of which entry points the program actually calls:

    109C:0000 0038 0724   116E:04B2   12BA:10A1 13D7
    14B9:0000 0106 02F5   17CF:00B5 01D3 0A63
    1891:0000 03A7        1A17:00A9 013E 053C 06FF
    1B6F:00A6

Three came out when `VTNotes`, `Dos.Exec` and `Dos.FSplit` became available.
`1891` (`Objects`) and the last `1B6F` (`Dos`) will resolve to the real
Borland units rather than to transcribed code.

~~**Not started:** `12ba` (5968), `11bb` (4080), `154d` (3920), `109c` (3296),
`165a` (3216), `17cf` (2832), `14b9` (2224), `142f` (2176), `19a0` (1905),
`193a` (1617), `116e` (1232).~~ **ALL ELEVEN ARE DONE**, and so is everything else:
`coverage.py` computes 99.8% and the remaining 101 bytes are segment padding.

    transcribed   8,709 bytes   19.7%      <- as at that session
    remaining    35,563 bytes   80.3%

Kept because the SIZES are a useful index and because the order they were taken in is
recorded per segment further down. The paragraph that followed -- "the drivers and the
hardware layers are done; what is left is the player itself" -- turned out to be the right
reading of the difficulty: `12ba` and `142f` took several sessions each, and the hardware
units went in almost verbatim from the release.

---

## `12ba` -- the mixer, in progress

The largest untranscribed segment, and the first increment went in byte-exact:

    python v1.31b/blocks.py     -- and NOT verify.py, while 12ba is unfinished

    fourteen complete routines   4,257 bytes   0 real differences
    PlayStart, part-written        309 bytes   5 (its ENTER 8,0 and one jump)
    TOTAL                        4,566 of 5,968 bytes, 76%

**FOURTEEN routines are complete and byte-exact**, through `10a1`'s first blocks --
no divergent region before where the transcription stops. `0693` is the biggest
routine in the segment at 1,173 bytes and `0b29` is the software mixer.

**BOTH OF THIS UNIT'S ROTATIONS ARE DISABLED IN THE ORIGINAL.** `12ba:06c0` is
`INC AX / AND AX,0`, pinning the note buffer to slot zero; `12ba:0c30` is
`Inc(ModIdx)` followed by a clamp to 1, pinning the module table to entry one.
Two independent multi-slot mechanisms, each switched off by its own next
instruction, and the second `MyMove` copies a block onto itself as a result.
Transcribed as found -- tidying either changes the bytes.

**`0187` closed on the `with` statement.** Its address computation matched
byte for byte and the four instructions after it did not: the original stores
the offset it had accumulated in DI beside DS, where a pointer local gives
`LEA AX,[DI+Base] / MOV DX,DS` and two stores from AX/DX. That store shape,
followed by `LES DI,[BP-4]` at every field access, is Turbo Pascal's `with` --
it computes an indexed record's address once into a hidden frame slot. Which
also means the `ENTER 4,0` is the compiler's slot and the routine declares no
local. `Ptr(Seg(X), Ofs(X[i,j]))` was tried first and emits exactly what `@X[i,j]`
does, so the two are not the answer.

**And `0187`'s middle is a `for`, which the reading pass had as a nested `if`.**
`MOV [02ee],0 / JMP past / INC [02ee] / body` is Borland's FOR, so the `INC` that
looked like an `else` branch is the loop increment, `$02ee` is a loop variable
over a row's eight entries rather than a second counter, and the rename flag at
`$02d1` is tested unconditionally rather than inside the wrap. The `CLD` at
`018b` is hand-written: `FillChar` here is a runtime CALL, not an inlined string
instruction, so nothing in the body asks the compiler for one.

**Transcribe top-down and only top-down.** Turbo Pascal lays procedures out in
source order, so a routine written out of order displaces everything below it
and the prefix stops dead. The entry points in order are `0000 0007 0187 0202
0275 02ea 03cc 0664 0693 0b29 0c4e 1008 1049 105d 10a1 132f 13d7 141e 1600`, and
`0187` is next.

**The unit is the same shape as `1a17`:** Pascal down to `15ff`, then an
assembler module for the kernel at `1600`. 1.39b builds its two successors,
`DumpInstrument` and `DumpEmpty`, out of `LIB/PLAYMOD.ASM` under a `$L`, and the
prologue scanner's `ENTER $000` at `1600` is a hand-written frame rather than a
compiled one. `PLAYMOD.ASM` currently holds a **stub** so the unit links --
harmless because object-module code lands after all Pascal code and `1600` is the
end of the segment, so it displaces nothing.

### What the release settled, and what it did not

Reading `LIB/PLAYMOD.PAS` before touching the disassembly is what made the first
increment land first time, and it is worth being specific about which half did
what.

**`TModRawChan`'s layout is adopted, and this time that is legitimate.** Every
field lands on an offset the reading pass had already recorded from the binary:
`+$0b` the non-looping limit, `+$19`/`+$1b` the 16.16 step, `+$1d` the byte
handed to the kernel, `+$1e`/`+$20` the loop, 34 bytes in total. Contrast
`TSong`, where the same move was nearly made and the release's remodelled layout
did not fit 1.31's offsets at all. **The rule is not "never take a layout from
the release" but "take it only when the binary confirms it field by field."**

**Two things the reading had left open closed on one page of the release.**
`+$1d` is the VOLUME -- `UnCanal` passes `Raw.Volume` there and the silent call
at `012c` passes a literal `0`, which is only a volume. And `+$19`/`+$1b` are the
STEP, not the position, which the reading had recorded the other way round; the
position is `+$01`/`+$03`. The arithmetic is identical either way, which is
exactly why reading alone could not separate them.

**And the disassembly overruled the release once, immediately.** 1.39b has two
kernels, `DumpInstrument` and `DumpEmpty`. 1.31 has ONE, at `1600`, with a final
Boolean argument: `6a 00` at `009b` and `0111`, `6a 01` at `016f`. The split came
later. Same lesson as always -- shapes and names from the release, contents from
the binary.

**One 1.31-specific detail worth keeping.** The step is assembled with a runtime
LongInt multiply, `1ba1:0a13` with `BX:CX = 1:0`, not a shift: the source is
literally `Raw.StepFrac + LongInt(Raw.StepInt) * 65536`. 1.39b writes the same
value as `(StepFrac SHR 4) + (StepInt SHL 12)`. Writing 1.39b's form here would
compile to different bytes.

## Byte comparison against the original

    python v1.31b/build.py && python v1.31b/verify.py
    python v1.31b/verify.py UNKLOADE        one unit

**Size equality is a weak check** -- two different routines can be the same
length -- and this file relied on it for too long. `verify.py` compares the
compiled `.TPU`'s code against the original segment byte for byte.

A `.TPU` is not linked, so every reference the linker still has to resolve --
far calls into other units, offsets of DGROUP variables -- sits there as
**zero** where the original has the resolved value. So the rule is: a
differing byte is acceptable only where the `.TPU` byte is `0x00`. A wrong
branch direction, a swapped operand or a different instruction will not
coincidentally emit zero.

    python v1.31b/verify.py -a GUS         every divergent region
    python v1.31b/verify.py -d GUS         bytes around the first one

**`-a` is the one to use on a unit that is far from matching.** A single
two-byte codegen difference early on displaces everything after it, so the
first-divergence figure says nothing about the remaining 2,600 bytes. `-a`
aligns with difflib and lists every gap, which is the actual work list;
regions before the verified prefix are dropped because difflib produces
alignment noise around the fixup zeros there.

It reports how far each unit agrees **from the start**, which is the only
alignment-independent measure: once the code diverges, everything after it
shifts and any overall percentage is noise.

    unit      seg     bytes  result
    ASCIIZ    1642      144  IDENTICAL
    FILEUTIL  116a       59  IDENTICAL
    VTDOSRSZ  188f       29  identical, 2 pending fixups
    FILTERS   1544      144  identical, 6 pending fixups
    VTNOTES   1650      149  identical, 6 pending fixups
    VTCTRL    14b7       25  identical, 8 pending fixups
    UNKLOADE  164b       77  identical, 14 pending fixups
    VTDOSMEM  1880      237  identical, 20 pending fixups
    HARDWARE  1b24      765  identical, 36 pending fixups
    VTSHELL   1931      138  identical, 56 pending fixups
    VTSILENC  1065      489  identical, 100 pending fixups
    DEVGUS    1084      376  identical, 106 pending fixups
    VTRESID   1b54      432  identical, 87 pending fixups
    GUS       1723     2741  identical, 542 pending fixups
    SOUNDDEV  1a17     4303  identical, 1024 pending fixups

**ALL FIFTEEN UNITS REPRODUCE THE ORIGINAL.** `GUS` closed on the compiler
probe; `SOUNDDEV` closed when its frameless run moved out of Pascal and into the
TASM module it was always built as. Nothing inside what has been transcribed is
open -- no parked divergence, no structural deviation, no unexplained byte.

## THE COMPILER IS TURBO PASCAL 6

Not 7. This was the tree's largest open question for several sessions -- filed
as risk 2 in `CONTINUATION.md` -- and it was settled the moment a TP6
install appeared beside the TP 7.01 one. `build.py` now uses TP6 by default;
`--tp7` builds with the other for comparison.

The evidence is not an argument, it is a measurement. Same sources, two
compilers:

| | TP 7.01 | TP 6.0 |
|---|---|---|
| byte-identical units | 1 | **2** |
| identical but for fixups | 10 | **10** |
| mismatched | 4 | **3** |
| `116a` FILEUTIL | 3 regions | **IDENTICAL** |
| `1a17` SOUNDDEV | 10 regions | **6** |
| `1723` GUS | 3 regions | 3 regions |
| `1b54` VTRESID | 24 regions | **21** |

**No unit got worse.** Every unit that agreed under TP7 agrees under TP6 with the
same pending-fixup count, to the byte.

The single cleanest result is `116a`: three divergent regions became none. One of
those three was the parked `LES DI,[BP+6]` reload -- the original loads a string
pointer afresh before indexing it, TP7 keeps it in a register, and **TP6 reloads
it**. That divergence had survived every source rewriting anyone tried, because
there was nothing wrong with the source.

The most predictive result is `1a17:024c`. It was recorded as the best single
test of the compiler question, on the reasoning that a value-`String` parameter's
copy is a compiler decision no source shape can reach and that it recurs
program-wide. TP6 makes the runtime CALL the original makes. Its two regions
closed, and the two difflib artefacts they had been displacing went with them.

**What it does NOT settle.** ONE divergence survives every compiler in the
image: `1a17`'s register allocation at `070f`. TP6, TP 6.01 and TP 7.01 emit the
same ten bytes. So the original's toolchain is TP6-like and is not this exact
TP6 -- a switch not in the recorded set, or something else in the pipeline. The
compiler-identity question is narrowed, not closed.

**Two of the three that used to be listed here were never the compiler.**
`1723:04b5` was our own nested `if` where the release has a `GOTO`, and `1723`'s
`Port[]` operand order does not reproduce at all. Both fell to the compiler
probe, below, on its first run. **A TP6 PATCH LEVEL IS ALSO CLOSED:** `C:\TP61`
is Turbo Pascal 6.01 (`TPC.EXE` 69,278 bytes, 11-Jun-1991, against 6.0's 69,214
of 23-Oct-1990), `build.py --tp61` builds the tree with it, and the result is the
same units, region counts and offsets to the byte. On the probe's source the two
compilers emit byte-identical code.

### THE RUN AT 0746..10c3 WAS AN EXTERNAL TASM MODULE

This is what the last four bytes in `1a17` are, and it is corroborated three
ways. They had been written up as structural deviations that "a Pascal procedure
must have one entry and one exit" makes unavoidable. That is true of a Pascal
procedure and false of the original, which did not use one.

**1. The release builds this very unit that way.** `LIB/SOUNDDEV.PAS` line 744
is `{$L SOUNDDEV}`, and seven routines below it are declared `EXTERNAL`:
`MixChannels`, `DMAFillBuffer`, `DMADoGetBuff`, `NullTimerHandler`,
`TimerHandler`, `DMATimerHandler`, and the four `DevInit*`. `LIB/SOUNDDEV.ASM`
is a 902-line TASM module, `IDEAL` / `MODEL TPascal` / `LOCALS @@`, whose entry
points are bare `PUBLIC` labels -- `TimerHandler:` with no `PROC`, no prologue,
no epilogue, and nothing forcing one entry or one exit.

**2. The ENCODINGS in the run are TASM's and are not TP's.** The two assemblers
disagree on the direction bit for same-register arithmetic, and each matches a
different part of this segment exactly:

| instruction | original | TASM 4.1 | TP6 inline `asm` |
|---|---|---|---|
| `AND AL,AL` | `22 C0` at `1014` | `22 C0` | `20 C0` |
| `XOR AL,AL` | `32 C0` at `102e` | `32 C0` | `30 C0` |
| `ADD AX,AX` | `03 C0` at `0a84` | `03 C0` | `01 C0` |
| `RETF 4`    | `CA 04 00` at `10c1` | `CA 04 00` | cannot express |
| `SUB BX,AX` | `29 C3` at `0713` | `2B D8` | `29 C3` |

The first four are inside `0746..10c3` and all four are TASM's. The fifth is
inside `GetPlayPos`, a compiled Pascal function with an inline `asm` block, and
is TP's. **Two assemblers, two regions, no exceptions** -- which is also the
explanation for something that had been treated as a nuisance: the run is full
of `DB 22h, 0C0h`-style byte encodings and the rest of the unit has none. Every
one of them is TASM output being spelled out because TP's inline assembler will
not produce it.

(Measured, not assumed: `C:\TASM\BIN\TASM.EXE` is Turbo Assembler 4.1 and
assembles a six-instruction `IDEAL`/`MODEL TPascal` probe to those bytes. It is
a 1996 build and certainly not the original's TASM, so treat it the way TP6 is
treated -- close on the encodings it explains, open on anything it does not.)

**3. The epilogue cannot be suppressed any other way.** The probe emits one
after a trailing internal near `JMP`, after a written `RET`, after a written
`RETF 4` and after a body of pure `DB` data, near and far alike. And declaring
the parameters that would turn the last one into `RETF 4` brings a prologue with
it -- `55 89 E5 ... C9 CA 04 00` -- even when the body names neither parameter
and reads them through a DB-encoded `[BP+8]`. So there is no arrangement of
Pascal `asm` that produces the original's boundaries.

#### The mechanism is PROVEN — three spikes, all green

Before any of the conversion below is worth starting, four things had to be true.
All four were measured with throwaway units, not assumed:

1. **TASM assembles `MODEL TPASCAL` and TP6 links the `.OBJ`.** `{$L SPIKE.OBJ}`
   with `procedure SpikeCode; external;` compiles clean on TP6 and the code lands
   in the `.TPU` verbatim, where `verify.py` can see it.
2. **The encodings survive, and no epilogue is added.** The spike's code is
   `22 C0 32 C0 03 C0 8B 1E 00 00 EB 00 CA 04 00` — TASM's direction bits, and
   `RETF 4` as the last instruction with nothing after it. That is `10c1` solved.
3. **TP6 places `$L` object code AFTER all of the unit's Pascal code**, wherever
   the `$L` directive itself sits. A spike with a Pascal procedure on either side
   of the directive puts both procedures first and the object code last. `1a17`
   needs exactly that: `GetPlayPos` ends at `0745` and the run is the last thing
   in the segment.
4. **The module can reference Pascal by name.** `EXTRN SpikeVar : WORD`,
   `EXTRN NearThing : NEAR` and `EXTRN FarThing : FAR` all resolve to fixups
   (`8B 1E 00 00`, `E8 00 00`, `0E E8 00 00`), and `OFFSET NearThing` works.
   Note the third: TASM turns a `CALL` of a far external in the same module into
   `PUSH CS / CALL near`, so a site that needs `9A` wants `CALL FAR PTR`.

`build.py` now assembles any `v1.31b/src/*.ASM` with `C:\TASM\BIN\TASM.EXE /la
/m2` before running TPC, and leaves the listing in `build/` — the listing is the
fastest way to see what byte a line assembled to.

#### DONE, and what it took

`v1.31b/src/SOUNDDEV.ASM` now holds `0746..10c3`: a MASM-mode TASM module that
INCLUDEs the generated `VTGAIN.INC` and carries `SharedPoll` and `SelectOutput`
by hand. `SOUNDDEV.PAS` ends with `{$L SOUNDDEV.OBJ}` and three `external`
declarations; `build.py` assembles any `v1.31b/src/*.ASM` before running TPC.
**2,430 bytes, and every difference against the original is a relocation.**

Four things cost a build each, and all four are worth carrying:

* **Turbo Pascal's statement separator is TASM's comment.** The gain cells are
  generated as `DB 66h; SAR BX,3` -- two statements on one line in Pascal asm.
  In TASM everything after the `;` is a comment, so every cell lost its shift
  and the ladder came out as runs of bare `66h` prefixes: **188 divergent
  regions from one character.** The converter now splits them onto their own
  lines.
* **Pascal hex is not TASM hex.** `$00` is `Undefined symbol: $00`. And the
  leading zero on `0Ch` is not optional -- `Ch` is an identifier.
* **The pad at `1007` is `DB 0`, not `EVEN`.** TASM's `EVEN` fills with `90h`,
  the NOP it expects to be executed through; the original's pad is `00`. One
  byte, and it was the last difference in the module.
* **`build.py` reported a clean build as a failure**, because TASM prints
  "Error messages:    None" on success and the check was a substring test.

And the two encodings the module gets for free: `RETF 4` at `10c1` is now the
instruction rather than an epilogue that could not be spelled, and the `CALL
@@Prepare` at `1033` is a symbol rather than the hand-computed `DB 0E8h, 0A9h,
0FEh` it had to be across a procedure boundary. That call's displacement is not
a fixup, so it had to come out right on its own -- and it did.

#### Measuring a module needs the .OBJ, not a heuristic

`verify.py` excuses a differing byte only where OUR side is `00`, which is what a
`.TPU` looks like and is not what an assembled module looks like: TASM resolves
what it can and leaves an **addend**. `DW OFFSET @@G1Table` becomes the offset
from the module's own start; `Volumes[2]` becomes the displacement `2`. Against
a linked binary both are flat mismatches, and no rule about the bytes can tell
them from real ones.

So `v1.31b/omf.py` reads the `.OBJ`'s FIXUPP records and returns the exact set of
relocated byte positions, which `verify.py` now uses for any unit with an `.OBJ`
beside it. **That is stricter than the zeros heuristic, not looser** -- a byte is
excused because the assembler recorded a relocation there, not because it happens
to be zero.

The mask was then checked a second way, per the standing rule, by classifying
every one of the 192 word fields it covers:

    code self-reference, exactly +0746   112
    DGROUP symbol + small addend           7
    left as zero                          73
    UNEXPLAINED                            0

### The compiler probe

`v1.31b/probe/PROBE.PAS` is not part of the reconstruction. It holds one routine
per divergence this document had recorded as a compiler difference, written to
the shape the tree already used, with the original's bytes quoted above each one.
`python v1.31b/probe.py` compiles it with every `TPC.EXE` in the image, locates
the code in each `.TPU` by its first prologue, and diffs.

    python v1.31b/probe.py            tp6, tp61 and tp7
    python v1.31b/probe.py tp6 tp61   two of them

    === tp6   C:\TP6\TPC.EXE    1232 bytes, code found at +03d0
    === tp61  C:\TP61\TPC.EXE   1232 bytes, code found at +03d0
    === tp7   C:\TP\BIN\TPC.EXE 1312 bytes, code found at +0410
    tp6   vs tp61  : IDENTICAL CODE
    tp6   vs tp7   : DIFFERS  (first difference at code offset +0064)

The compiled probe is around 256 bytes, so the whole comparison fits on a screen
and a claim about a construct is settled in one build of a few seconds -- against
the 10 KB of context a real unit drags in. **It has been the cheapest instrument
in this project and it found more in its first run than the previous three
sessions of byte-chasing.**

It was written to answer one question -- does TP 6.01 differ from 6.0? -- and the
answer is no, byte for byte. What it actually found was that two of the three
divergences parked as "not source shape" were **our own source**.

**Its four routines and what each one says.**

    ProbeRegAlloc     Left := DMABufferSize - GetDMACount
                      1a17:070f. All three compilers emit
                        CALL / MOV DX,AX / MOV AX,mem / SUB AX,DX / MOV [BP-6],AX
                      against the original's
                        CALL / MOV BX,mem / SUB BX,AX / MOV [BP-6],BX
                      STILL OPEN, and now the only one.

    ProbeGotoFold     if C then goto L
                      Compiles to CMP / 74 02 / EB 06 -- the original's
                      JZ +2 / JMP, UN-folded. So 1723:04b5 was never the
                      compiler. CLOSED GUS.

    ProbePortOrder    Port[GUSPort] := $0B, three times: after nothing,
                      after an OUT, after a CALL. Value-first every time.
                      The 02f4/03c4 operand-order difference does not
                      reproduce. WITHDRAWN.

    ProbeValueString  procedure P(ID : String) -- the copy onto the frame.
                      TP6 and TP 6.01 CALL the RTL helper; TP7 inlines
                      LDS SI / LODSB. This is the 1a17:024c discriminator
                      and it is the ONLY thing the probe finds between TP6
                      and TP7. Kept as a REGRESSION check: a compiler that
                      inlines it is not the original's.

**What it found on its second run**, when it was pointed at `1a17`:

    ProbeAsmEncoding   SUB BX,AX assembles to 29 C3 in TP's INLINE
                       ASSEMBLER and 2B D8 in TASM. The original has 29 C3
                       at 0713, so GetPlayPos's `Left := DMABufferSize -
                       GetDMACount` is four instructions of HAND-WRITTEN asm,
                       not compiler output, and the last "compiler
                       divergence" in the tree was a transcription error.
                       Transcribed verbatim into the asm block that already
                       sat above it, 0710 and 0716 both CLOSED.

    ProbeEpilogue*     An `assembler` procedure gets its epilogue after a
                       trailing internal JMP, after a written RET, after a
                       written RETF 4 and after pure DB data -- always.
                       CONFIRMS the note that 1007, 104d and 10c1 cannot be
                       fixed by rearranging the asm.

    ProbeUnnamedParams A far `assembler` procedure with parameters it never
                       names still gets 55 89 E5 / C9 CA 04 00 -- prologue
                       and all. So the "assembler naming no parameter gets no
                       frame" rule does NOT extend to this case, and the
                       obvious fix for 10c1 is closed off.

Those three results together are what identified the TASM module above: the
encodings say TASM, and the epilogues say the boundaries are not Pascal's.

**Two things about writing the probe itself**, both of which cost a build:

* A directive LIST carries one dollar sign for the whole list. `{$A+,B-,D+}` is
  right; `{$A+,$B-,$D+}` is Error 17, `Invalid compiler directive`, on both
  compilers. The probe sets nothing in the source and takes `build.py`'s
  `SWITCHES` from the command line, exactly as the units do -- `$G+` in
  particular decides whether 286 instructions are emitted at all.
* **Do not write a directive-shaped thing inside a comment.** `{ ... {$A+,B-} ...
  }` ends the comment at the inner `}`, and the error lands on the prose.

**And `build.py`'s TP6 rewrite is keyed on the compiler name**, which `--tp61`
broke: `compiler == "tp6"` skipped `tp6_dialect()` and every unit failed with
Error 73. It now tests `startswith("tp6")`. Any further TP6 install has to keep
that prefix.

### `GUS` closed on the probe -- two source bugs, both invisible to reading

`1723` had been written up as "3 regions, ALL PARKED -- nothing to fix from
source". All three were inside `ProbeUltrasound` and all three were ours.

**1. The nested `if` where the release has a GOTO.** The original's

    3d d8 16     CMP AX,16D8
    74 02        JZ  +2
    eb 18        JMP Fin

is what `if (...) <> $16D8 then goto Fin` compiles to: Turbo Pascal evaluates the
condition, branches over the `goto` when it is false, and emits the `goto` as an
independent `JMP`. Our nested `if ... then begin ... end` folded to one `JNZ +16`,
two bytes shorter, displacing the rest of the routine. Both of the routine's tests
are like this and the source is now

    if (GetGusRegister16($02) and $1FFF) <> $16D8 then goto Fin;
    SetGusVoice(1);
    if (GetGusRegister16($02) and $1FFF) <> $0F83 then goto Fin;
    ProbeUltrasound := True;
    Fin:

with both `goto`s reaching the same label -- which is what the original's two
`JMP`s do, one to `+18` and one to `+04`, both landing on the register restore.
The `label Fin` declaration was already in the file, unused, left from whenever
this was tried and reverted.

**2. `ProbeUltrasound := ProbeUltrasound;` compiles to a RECURSIVE CALL.** The
trailing self-assignment emitted `CALL / MOV [BP-1],AL` where the original has

    fb           STI
    8a 46 ff     MOV AL,[BP-1]
    c9 c3        LEAVE / RET

Turbo Pascal reads the function identifier on the RIGHT of an assignment as a
CALL of the function, not as its result variable. That is the same rule that makes
assigning TO the identifier work, seen from the other side, and **nothing in
Pascal reads a function's own result back.** The line had presumably been written
to force the result load that the compiler emits anyway. Six bytes, and it was
hiding under the region the branch fold displaced.

Result: `GUS  1723  2741  identical, 542 pending fixups`.

### TP6 needs the source rewritten, and `build.py` does it

TP6 has **no `far` directive on a unit's exported routines at all**. It rejects
one on the interface declaration (error 73, `IMPLEMENTATION expected`) and it
rejects one on the implementation header of a routine the interface has already
declared (error 36, `BEGIN expected`). The calling model comes from `{$F}` at the
point of declaration and nowhere else. TP7 relaxed that, and every unit here was
written to TP7's rule.

So `build.py`'s `tp6_dialect()` rewrites the STAGED copy -- `v1.31b/src` is not
touched -- turning the interface's `far` directives into an `{$F+}` region that
runs from the `interface` keyword to the `implementation` keyword, where the
unit's configured state resumes. That reproduces the TP7 shape exactly: exported
routines far because they are declared under `$F+`, private routines near because
they are declared after it goes off again. **Turning `$F+` on for the whole unit
instead is wrong** -- it promotes the private routines the interface never
mentions.

Two details that cost time. The declaration has to be matched WHOLE rather than
up to its first semicolon, because a parameter list separates its groups with
semicolons too and `[^;]*` stops short on every routine taking more than one
group. And `verify.py`'s staleness check compares the staged source against the
original: it has to accept the rewritten form as well, or a TP6 build reports the
whole tree `STALE` and nothing can be measured.

### What actually causes a divergence

Twenty-four patterns so far, none of them a compiler-generation gap, and all of
them worth checking FIRST on the twelve segments still to be transcribed.

**1. `Port[]` with a computed index is not what it looks like.** Turbo
Pascal's port pseudo-array compiles to a bare `MOV DX,imm / OUT DX,AL` only
when the index is CONSTANT. With `GUSPort + $102` it evaluates the address as
an ordinary expression, through AX:

    Port[GUSPort + $102] := N        the original
    -----------------------------     ------------
    MOV AX,[GUSPort]                 MOV DX,[GUSPort]
    ADD AX,0102                       ADD DX,0102
    MOV DX,AX
    MOV AL,[BP+4]                     MOV AL,[BP+4]
    OUT DX,AL                         OUT DX,AL

**Identical length**, so every size-based check missed it. The original keeps
the port in DX and walks it with `ADD DX,2` / `INC DX` instead of
recomputing -- an assembler block, which is what `1723`'s five register
routines are. This corrects the rule recorded under "Rules being followed":
port code is faithfully Pascal only when the port number is a constant.

**2. An early `Exit` is the wrong shape.** `if P = nil then Exit` compiles to
`JNZ +2 / JMP end` -- a conditional jump around an unconditional one. The
original wraps the body instead and gets a single `JZ end`. Two bytes and a
different shape. Fixing this one line took `1065` from 57% to 99%.

**3. Do not declare locals the original did not have.** A `Char` local makes
the compiler spill to `[BP-1]` and compare against memory where the original
keeps the value in AL (`116a`); two `String` locals add a copy each where the
original used compiler temporaries (`164b`). Both were invented by this
transcription, not read from the binary.

**4. Operand order in an expression.** `1065`'s divisor read is
`Port[$3f8] + (Port[$3f9] shl 8)`; written the natural way round it emits the
two `IN`s in the wrong order.

**5. Parameter ORDER, read off the frame.** `1544`'s `Apply` had `Strength`
second and `Count` fourth; the body's own offsets say
`Buf($0e) Count($0c) Stride($0a) Strength($08) State($06)`, and since Turbo
Pascal puts the first declared parameter at the HIGHEST `[BP+n]` that fixes
the order. The wrong order compiled cleanly and would have read the sample
count out of the filter strength at run time. **This is the strongest
argument for byte verification in the whole file: it was a real bug, not a
cosmetic difference, and nothing else would have found it.**

**6. Parameters that exist but are never used.** `1084`'s `Start` ends
`RETF 2` while its body takes the rate from DGROUP. Declared without the
parameter it compiles to a plain `RETF` and every caller's stack is two bytes
out. The 1.39b release confirms it: `PROCEDURE DevInit(Hz: WORD)`.

**7. `assembler` versus an `asm` block inside a normal procedure.** An
`assembler` procedure that names no parameter gets NO frame; the original's
`1084:0000` opens `PUSH BP / MOV BP,SP` and closes `LEAVE / RETF`, so it is
an ordinary procedure with a hand-written body. Related: an `assembler`
procedure always gets an epilogue, so a written `RET` at the end emits a
SECOND one -- that alone was the whole of `1544`'s and part of `1b54`'s
divergence.

**8. Integer width in an expression.** `1084`'s divisor is
`IMUL AX,[Rate],$140` -- one 286 instruction on a WORD -- then `XOR DX,DX` to
widen. `LongInt(Rate) * $140` widens first and calls the 32-bit runtime
multiply instead. It also settles what the variable is: a 16-bit product only
stays in range for a tick rate, not a sample rate.

**9. Near versus far jumps.** `1b54`'s handler chains with `E9 D2FF`, a NEAR
jump back to offset 0000, because the chain target is its own `JMP FAR` stub
whose operand holds the displaced vector. `JMP FAR PTR` assembles five bytes
and misses the idiom.

**10. Procedure ORDER must match the segment map.** A `.TPU` lays procedures
out in implementation order, so one swapped pair displaces everything after
it. `1b24` had `Mask` and `Setup` the wrong way round.

**11. `while` versus `for`.** Borland's FOR opens
`MOV <var>,0 / JMP past / INC <var> / body`; a WHILE puts the test at the top
with no jump past an increment. `1650` has three FOR loops and two `goto`s
out of them, and was written here as `repeat` and `while` -- every branch
after each loop head was displaced.

**12. `Seg(P^)` is not a record cast.** `LES DI,[BP+8] / MOV AX,ES` is what
`Seg` and `Ofs` compile to when applied to what a pointer POINTS AT. Reading
the halves through a `TPtrRec` cast fetches them off the frame instead --
same values, different instructions. (The warning about `Seg(P)` giving the
address OF the pointer still stands; `Seg(P^)` is the dereferencing one.)

**13. `Port[]` with a CONSTANT index really is Pascal.** Three routines in
`1b24` carried the note "IN and OUT are not expressible in Pascal" and were
hand-written. They are expressible, and the hand-written versions had the
right instructions with the wrong ENCODINGS -- TP7's assembler picks `89 C2`
for `MOV DX,AX` and `21 D0` for `AND AX,DX` where the compiler emits `8B D0`
and `23 C2`. Combined with pattern 1 the rule is: **constant port -> Pascal,
computed port -> assembler.**

**14. Declaration ORDER of locals, and unused frame space.** `1b24`'s
`SetIRQVector` needed its Pointer declared before its Word; `1650` has four
bytes at the top of its frame that nothing references and had to be declared
to reproduce it. Turbo Pascal also reserves temporaries at the top of a
frame, so a larger `ENTER` than the declared locals explain is not
automatically a missing variable -- check before declaring padding.

**15. A constant can be there to force a wider type.** `1b24`'s `Setup` does
a 32-bit `SUB AX,0 / SBB DX,1` -- subtracting 65536 -- and then stores the
result as a WORD, throwing the borrow away. The answer is identical to a
plain 16-bit add, so the subtraction looks like decoration. It is not:
writing `- $10000` is what makes the expression LongInt, and without it Turbo
Pascal emits two bytes where the original has fourteen.

**16. Byte parameters passed as words.** `MOV AL,[BP+0e] / PUSH AX` means the
callee's parameter is a BYTE even though the push is a word. `1b24`'s
`SetupRaw` takes three of them, as the release's `DMARawSet` confirms.

**17. `Port[X + $00]` is not `Port[X]`.** Writing the zero makes Turbo Pascal
evaluate an address expression -- `MOV AX,[X] / ADD AX,0 / MOV DX,AX` -- where
a bare `Port[X]` loads the port straight into DX with `MOV DX,[X]` and loads
the VALUE first. Three bytes and a different instruction order, from a `+ 0`
that reads as harmless. Four occurrences in `1723`.

**18. Assign to the function identifier, not to a local.** `1723`'s
`ProbeDram` writes its Boolean to `[BP-1]`, an ODD offset Turbo Pascal will
not give a declared variable -- it word-aligns locals to `[BP-2]`. That byte
is the function RESULT, which Borland allocates at the top of the frame. A
separate `Ok : Boolean` gets one of its own and everything below shifts. Not
the `$A` switch: compiling `$A-` changes nothing.

**21. Declaration ORDER of locals sets the frame.** `1723`'s
`RestartChannels` had a `Word` declared second and a spare `Last : Byte` that
the original does not have; both shift every `[BP-n]` below them by a byte, and
the unit came back with thirty single-byte differences that looked like noise
and were not. The release declares `i, k, Vol : BYTE; j : WORD; ...` and that
order reproduces the offsets. A larger `ENTER` than the declared locals explain
is a compiler temporary, not a missing variable -- `[BP-7]` here is the FOR
limit.

Reading that order off the release was not enough on its own, and the reason is
worth keeping: the fix kept a FOURTH byte local as well, and four bytes plus a
word still `ENTER 8,0`, so the frame size went on agreeing while eleven
references stayed one slot out. See 23 for what settled it. **Getting the local
COUNT right matters as much as the order, and the frame size will not tell
you** -- only the individual offsets will.

**20. A routine can be wrong in EVERY respect and still compile.** `1723`'s
`ChangeVol` was transcribed as a seven-line `SetPan` against the original's
253 bytes: wrong name, wrong parameter order, wrong register, and both call
sites passing their arguments reversed. Nothing but the byte comparison would
have found it, and reading the release's `ChangeVol` gave the whole shape in
one pass. Removing it closed a 69-byte gap and two others.

Its volume table had to come from the IMAGE, not the release -- only entry 0
agrees between 1.31 and 1.39b. The release settles shapes; it is worth
nothing for data.

`ChangeVoiceParams` was the same story: transcribed as
`StartVoice(Freq, Pan, Voice)` with the VOLUME and the PAN sharing one
argument. The frame says `RETF $0A` with four parameters, and its opening
test is not an early exit -- both arms do work. Fixing it took the unit from
76 divergent regions to 42 in one edit.

**19. Read the release's source for the routine BEFORE chasing bytes.**
Every shape above was recoverable from `LIB/GUS.PAS` in one read --
`assembler` versus Pascal for all five register routines, the `FOR i := 0 TO
31`, all four writes inside the `IF`, the `LABEL Fin` with inverted gotos,
`SwapGusAddress` as a single masked shift. Chasing them one divergence at a
time cost several rounds each and found the same answers.

**22. A reversed parameter list can pass every size check.** `TriggerVoice`
was transcribed as `(EndA, LoopA, StartA, Mode, Freq, Pan, Voice)` where the
frame says `(Voice, Vol, Freq, Pan, StartA, LoopA, EndA)`. The reversal totals
the same 22 bytes, so the routine still emitted the right `RETF $16` and the
unit still compiled to the right length -- what was wrong was every `[BP+n]`
inside it. Read the frame offsets, in order, and match them to a parameter
list whose sizes account for each one; do not check only the total.

**23. Turbo Pascal never reuses a dead local's slot, so the same offset means
the same variable.** `RestartChannels` writes the kicked voice to `[BP-1]` at
`1723:0856`, which is the FOR variable's slot -- so the original has no
separate variable there, it reuses the counter it has finished with. This was
transcribed as a fourth byte local and that pushed the two below it down one
each, for eleven divergences from one spurious declaration. The related trap:
a `Word` local is WORD-ALIGNED, so three preceding bytes become four and the
Word lands at `[BP-6]`, not `[BP-5]` -- `[BP-4]` is padding, not a variable.

**24. `<= 0` and `= 0` are the same test on a Word and different bytes.**
`1723:0847` is `JA +3` over a `JMP`; Turbo Pascal branches on the condition
being FALSE, so `if N <= 0 then Exit` gives `JA` and `if N = 0 then Exit`
gives `JNZ`. One byte. When a comparison against zero is one byte out, try the
other spellings of the same condition before looking for anything structural.

### The divergences that are NOT source shape -- and THE COMPILER WAS TURBO PASCAL 6

**Read `THE COMPILER IS TURBO PASCAL 6` below before this list.** Most of what
follows was written while TP7 was the only compiler available, and TP6 closed
four of the seven entries outright. They are kept, marked, because the reasoning
that identified them as "not source shape" was right and is what made the
compiler test worth running.

**CLOSED by Turbo Pascal 6:**

- `116a` -- `S[Length(S)]` loads the string pointer once under TP7; the original
  reloads `LES DI,[BP+6]` before indexing, and **so does TP6**. The unit is now
  byte-identical, all 59 bytes.
- `1a17:024c`/`0255` -- the inlined copy of a value-`String` parameter. TP6 CALLs
  the same runtime helper the original does. See below.
- `1b54` -- `S := Name` between two `String`s was recorded here as the same
  mechanism, inlined by TP7 and called out to by the original. **There was no
  `S`.** The local had been invented to explain a frame 256 bytes larger than the
  declared locals, and the extra 256 bytes are the temporary
  `WriteLn(A + B + C)` concatenates into. `VTRESID` is byte-identical, and this
  entry was a real divergence with the wrong cause attached.
- `188f:001b` -- `POP BP` against `LEAVE`, which turned out not to be a compiler
  difference at all but **the `$G` switch**, on either compiler. See the work
  list below.

**STILL OPEN under both compilers:** `1a17:070f` (register allocation), `1723`'s
`JZ +2 / JMP` (branch folding) and `1723`'s `Port[]` operand order. TP6 emits
exactly what TP7 does at all three. Whatever they are, they are not the
TP6-versus-TP7 gap.

- **A `Word` parameter that should be a `Byte` shows up in the CALLER, not the
  callee.** `1a17:06ea` loads its argument with `MOV AL,[DMAChannel] / PUSH AX`
  and NO zero-extension, which Turbo Pascal emits only when the parameter is
  byte-sized -- so `1b24`'s `GetCount(Channel)` takes a Byte, and it had been
  transcribed as a Word. Declared Word, the caller gains a `XOR AH,AH` the
  original does not have. Nothing changed inside `1b24` (a byte argument still
  occupies a word on the stack, so the `BYTE PTR Channel` load and the RETF 2
  are unaffected), which is exactly why the wrong declaration survived there
  unnoticed until something called it. **Check argument widths from the call
  site; the callee cannot tell you.**

- `1a17:070f` -- **REGISTER ALLOCATION, and it SURVIVES TP6.** This was the
  strongest single piece of evidence that the compiler was not TP7, and it was
  right about that -- but TP6 emits the same ten bytes TP7 does, so it is not
  what separated them. It is now the oldest unexplained divergence in the tree.
  `Left := DMABufferSize - GetDMACount` compiles to nine bytes in the
  original and ten for us, because of which register holds what:

      original   CALL / MOV BX,DMABufferSize / SUB BX,AX / MOV [BP-6],BX
      TP7        CALL / MOV DX,AX / MOV AX,DMABufferSize / SUB AX,DX / MOV [BP-6],AX

  Both are correct code for the same statement. The original's compiler left the
  call's result in AX and allocated BX for the memory operand; TP7 insists on AX
  as its accumulator, so it moves the result out of the way first. No source
  rewriting reaches it -- there is nothing in the statement to rearrange.

  **The other parked divergences are instruction SELECTION; this one is register
  ALLOCATION**, which is a deeper property of a code generator. That is why it
  carried so much weight in the compiler argument, and it is why its survival
  under TP6 is worth keeping in view: some part of the toolchain is still not
  the original's.

- `1a17:024c` -- **CLOSED. This was the test, and it is what settled it.**
  `LocateDevice(ID : String)` takes its string BY VALUE, so the compiler copies
  256 bytes onto the frame before the body runs. The original CALLs a helper at
  `1ba1:0add`; TP7 inlines `LDS SI / LODSB`; **TP6 makes the call.** It was
  flagged here as "the most likely of the parked five to be worth resolving, and
  the best single test of the compiler-identity question" because it recurs on
  every value-`String` parameter in the program. Both halves held.
- `1723:04b5` -- **WITHDRAWN, AND IT WAS OUR SOURCE.** This entry used to read
  "`if C then goto L` is folded by Turbo Pascal into one inverted branch ...
  confirmed against the release's `ProbeUltrasound`, which has exactly the
  LABEL/GOTO the transcription now uses -- so the SOURCE is right and the
  compiler still will not match." **Both halves were wrong.** TP6 does not fold
  it -- the probe's `ProbeGotoFold` compiles to `CMP / 74 02 / EB 06`, the
  original's shape exactly -- and the transcription did NOT use the release's
  LABEL/GOTO; it had a nested `if ... then begin ... end`. Written as the release
  has it, both branches match. See "The compiler probe".
- `1723` -- for `Port[GUSPort] := $0B` the original was recorded as emitting the
  value first at `1723:02f4` and the PORT first at `1723:03c4`. **WITHDRAWN: it
  does not reproduce.** The probe emits `MOV AL,0B / MOV DX,[GUSPort] / OUT` in
  all three contexts -- after nothing, after an `OUT`, after a `CALL` -- and
  `GUS` now compares clean at both addresses. There is no scheduling effect here.

**One is left**, `1a17:070f`, and it is recorded rather than explained. Of the
six divergences this section has carried, two were the TP6/TP7 gap, one was the
`$G` switch, and two were our own source. **A one-site case that the compiler
differs is a weak case.** Treat the last one as ours until a probe says otherwise.

**And segment sizes are not code sizes.** `1931` is 138 bytes of code plus 3
of padding, `1065` is 489 plus 2, `1084` is 376 plus 8, `1650` is 149 plus 11. Both only passed once the figure in
`verify.py` was corrected. Check this before chasing a tail difference.

### Three bugs in the tool itself, worth remembering

Each one made the reconstruction look better than it was, which is the
direction of error that matters here.

1. **Ranking candidate positions by "fewest real differences"** scores a run
   of zero bytes as perfect, because against zeros every difference looks
   like a pending fixup. Two units passed that should not have.
2. **Ranking by "most exact matches"** is not fooled that way but drifts when
   the unit and the segment are different lengths, sliding to whatever
   alignment shares the most bytes and reporting a meaningless divergence
   offset. It now anchors on the procedure prologue.
3. **Reporting on a stale `.TPU`.** `build.py` refuses to compile at all when
   the lint fails, so one bad comment left the whole tree stale while
   `verify.py` cheerfully reported on the previous build. That produced a
   wrong conclusion -- an operand-order fix was recorded as having no effect
   when it had in fact worked. `verify.py` now refuses to report on a `.TPU`
   older than its source.
4. **Counting any zero as a fixup** let long zero runs swallow the real
   divergence: `ASCIIZ` read 68% and is actually 6%. A fixup is at most four
   bytes -- a far pointer -- so runs longer than that end the comparison.

`VTSHELL` only passed once its size was corrected from 141 to 138; the last
three bytes of that segment are padding, not code.

### The work list

**Every entry that has ever been here is DONE.**

`GUS` is **byte-identical** -- the last unit to close, and it closed on two source
bugs after being written up as unfixable. The compiler probe is what found them;
see "The compiler probe" above.

`VTDOSRSZ` was 28 of 29 bytes -- `+$1b` is `POP BP` in the original and `LEAVE`
from the compiler. **It is the `$G` switch after all.** `LEAVE` is an 80286
instruction, so `$G-` cannot emit it, and with a `{$G-}` at the top of the unit
it is byte-identical on TP6 and TP7 alike. The note here previously said `$G-`
changed nothing; it does. It has to stay local to that one unit -- building the
whole tree `$G-` wrecks twelve of the fifteen, `164b` and `1650` included,
because they genuinely use 286 instructions.

`FILEUTIL` is **byte-identical**. Rewriting its `if` chain as the `case` the
original actually used produced the exact `CMP AL,x / JE` sequence, and the two
elided `LES DI,[BP+6]` reloads that remained after that closed under TP6 -- TP6
reloads the pointer exactly where the original does.

---

## Code size as a check on faithfulness

**Historical, and every figure in it is a TP7 figure.** Kept because the
reasoning about what a size ratio does and does not tell you is still worth
having, and because the two sections below record conclusions that were drawn
from this table and then fell. Do not use the numbers: size equality is the weak
check this whole file exists to replace, and `verify.py` under TP6 is the real
measure.

| unit | original | TP7 | ratio | |
|---|---|---|---|---|
| `14b7` | 25 | **25** | **1.00** | exact |
| `1880` | 237 | **237** | **1.00** | exact |
| `1544` | 144 | 132 | 0.92 | original figure includes segment padding |
| `1b24` | ~765 | 723 | 0.95 | mostly verbatim assembler |
| `1723` | ~2739 | 2675 | 0.98 | |
| `1a17` | 1206 | 1219 | 1.01 | of the part transcribed |
| `1065` | 491 | 521 | 1.06 | |
| `188f` | 29 | 31 | 1.07 | |
| `116a` | 59 | 63 | 1.07 | |
| `1931` | ~141 | 153 | 1.09 | |
| `1084` | 384 | 422 | 1.10 | |
| `1b54` | 432 | 474 | 1.10 | |
| `1642` | 144 | 167 | 1.16 | the local-String copy, see deviations |
| `1650` | 160 | 200 | 1.25 | a `for` loop nest |
| `164b` | 77 | 117 | 1.52 | **the old explanation is withdrawn, see below** |

### The switches were wrong, and it mattered

Every figure above moved when `build.py` adopted the switch set from the
1.39b release's `TPC.CFG`. Before that this script passed only `/$S-` and let
everything else default, which meant **every unit except `VTPLAYER` was being
compiled as plain 8086** -- `$G+` was never set.

Two units now land on the original's byte count exactly. That is the first
hard evidence that the target is reachable at all.

larger, which is the expected BP6-versus-TP7 codegen gap.

`1650` at 1.44 is a `for` loop nest, where TP7's range handling is wordier
than BP6's. Noted, not chased.

### `164b` — the "it is the compiler" explanation is WITHDRAWN

**Kept as a record of a conclusion that did not survive.** The measurement
below is still correct: TP7 spends 41 bytes where the original spends 18 on
`String := array of Char`, and the cost does not depend on the array length.

What does not follow is what was concluded from it — that the difference is
Borland Pascal 6 codegen versus Turbo Pascal 7, and therefore unreachable.
Two units now compile to the original's exact size under TP7. So TP7 *can*
reproduce this binary, and the remaining 40 bytes in `164b` are something
else: a different construct in the original source, or a switch still
unmatched. It needs re-chasing, not explaining away.

**A postscript, and it is an awkward one.** `164b` has since compiled to the
original's exact bytes -- the 40 were two invented `String` locals, not the
compiler -- so the withdrawal was correct on that unit. But the *mechanism* named
here, BP6 codegen against TP7, turned out to be real elsewhere: it is what `116a`
and `1a17:024c` were, and TP6 closed them. The lesson survives anyway, because it
is about method and not about the answer: a plausible mechanism is not evidence
even when it later proves true, and what settled this was running the other
compiler rather than arguing about it.

This is the second conclusion in this tree to fall to the same mistake —
reasoning from a plausible mechanism instead of finding the decisive
evidence. The other was the probe sense; see VTDRIVER.PAS.

Accounting, original against TP7:

| part | original | TP7 | |
|---|---|---|---|
| frame, `Format` store, `Status` store | 24 | 23 | matches |
| **`String := array of Char`, twice** | **36** | **76** | **+40** |
| string compare, branch, two stores | 17 | 29 | +12 |
| | 77 | 128 | |

Borland Pascal 6 compiles `Found := Hdr^` to eighteen bytes: push the
destination, push the source, push the length as a literal, and call a runtime
helper (`1ba1:0c05`). Turbo Pascal 7.0 spends **forty-one bytes** on the same
line.

The decisive measurement is that the cost **does not depend on the array
length** — a `array[1..60] of Char` source compiles to exactly the same 41
bytes as `array[1..6] of Char`. So TP7 is not inlining a copy sized to the
array; it emits a fixed, larger calling sequence for a conversion BP6 did with
three pushes and a call.

**The source construct is right and stays as it is.** Rewriting it as, say,
`Found[0] := #6; Move(Hdr^, Found[1], 6)` would get closer to 77 bytes while
being a *less* faithful transcription — the original plainly used the
array-to-string assignment, which is exactly what the helper call with an
explicit length argument is. Fitting the source to the byte count would mean
reconstructing for the wrong compiler.

**What this means for the table above.** Any unit that assigns arrays of Char
to Strings will read high, and the ratio is not evidence of a mistake there.
Units that do not should still stay near 1.2, and one that does not needs
explaining.

A unit that comes out at half or twice the original's size has almost
certainly lost something. This table is the cheapest check there is on whether
a transcription is honest, so keep it up as units land.

---

## Generated source

`1a17:0746..0b29` -- the gain ladder, its three pointer tables, the eight-slot
patch area, the bit-reversal permutation and the code that patches them -- is
**generated**, not typed:

    python v1.31b/emit_gain.py > v1.31b/src/VTGAIN.INC

Same reasoning as `tools/emit_p6text.py` in the main project. It is 315 bytes
of 48 near routines drawn from a five-instruction vocabulary, plus three
tables whose every entry must land exactly on a routine's first byte. Typed
out of a hex dump that is a hundred chances to be quietly wrong, and one wrong
entry sends the mixer into the middle of an instruction.

The generator refuses to emit anything it cannot account for:

- every byte decodes, or it stops -- there is no best-effort path;
- all 48 gains are computed as exact fractions and checked against a closed
  form (`(16-k)/16`, `(16+k)/16`, `bitrev4(k)+1`);
- all 48 table entries are checked against decoded cell boundaries;
- the patcher's instruction lengths are accumulated from `0a81` and checked
  to land on `0b29`.

### What the ladder turned out to be

Worth recording, because it is the whole reason the mixer has no multiply.
Each cell applies one gain to `EAX` in shifts and adds and returns; changing
a channel's volume means overwriting the address the mixer `CALL`s. Cell 0 of
each family is a bare `RET` -- unity.

| family | at | form | gains |
|---|---|---|---|
| 1 | `0746` | `SAR EBX,n` / `SUB EAX,EBX` | `(16-k)/16` -- 1, 15/16 … 1/16 |
| 2 | `085e` | `SAR EBX,n` / `ADD EAX,EBX` | `(16+k)/16` -- 1, 17/16 … 31/16 |
| 3 | `0976` | `SHL EBX,n` / `ADD EAX,EBX` | `bitrev4(k)+1` -- 1, 9, 5, 13 … |

**The bit reversal cancels.** Family 3's gains are stored permuted, and
`SetGains` looks that table up *through* the permutation at `0a71`. Bit
reversal is an involution, so `T3[bitrev(v)]` is gain `v+1`: a clean integer
ladder 1..16. The cells sit in memory in the order the shift-and-add
construction emits them, which is bit-reversed by gain; rather than reorder
two hundred bytes of code, the author permuted the index instead.

Which table each channel uses is fixed in the code, not computed: channels 0
and 4 attenuate, 2 and 6 boost, and the four odd channels take the integer
ladder. That asymmetry is real and is transcribed as found.

---

## Deviations forced by Turbo Pascal

Recorded here rather than in the main project's `docs/23-deviations.md`,
because this tree is out of source control.

**One DGROUP, many units.** The original is one flat data segment that every
code segment reaches into by absolute address. Pascal has no such thing: a
variable belongs to one unit and everyone else imports it. So each shared
global is declared in the unit that owns it semantically —
`VTCtrl.CtrlBlock` for `DS:$22c6`, for instance — and the others `use` it.
This is the single largest structural difference between the reconstruction
and the binary, and it is unavoidable.

**No absolute DGROUP addresses cross over.** Standing rule from the main
project. `MOV DI,22C6h` becomes `OFFSET CtrlBlock`; `MOV AX,[0C62h]` in
`188f` becomes `PrefixSeg`, identified from the DOS API contract rather than
from the address — INT 21h $4A requires `ES` to hold an MCB-owned block
segment, which for a running program is the PSP.

**~~`ASCIIZ` builds its result in a local.~~ WITHDRAWN.** This claimed Turbo
Pascal would not let a function alias its own result. It will: inside the
body the function identifier denotes the result variable and can be indexed,
so `ZToStr[I + 1] := ...` is ordinary Pascal and is what the original does.
The 1.39b release writes exactly that (`LIB/ASCIIZ.PAS`, `StrAsciiZ[i+1] :=
z[i]`). With the local removed the unit is **byte-identical to the original,
with no fixups at all** -- the first exact match in the tree.

**`NoName` is a typed constant.** `Install` takes its address, and an untyped
Pascal constant has no storage for `@` to take. A typed constant produces
exactly what the original has — a string sitting in DGROUP at `$0c20`.

**The gain ladder gains a `JMP` at its front.** The original falls into the
patcher at `0a81` from outside; Pascal enters a procedure at its first byte,
which here is the ladder. So `SetGains` starts with a `JMP` over the data --
three bytes that are not in the original. The alternative was to address every
patch target by literal address, which the standing rule forbids and which
would break the moment the compiler moved anything.

**The include carries a whole procedure, not just data.** TP7 rejects an
include directive inside an `asm` block (error 118), and the patcher has to
share a scope with the labels it patches. So `VTGAIN.INC` holds the entire
`procedure SetGains` and is included at declaration level.

**`PByte` does not exist in TP7** -- it is a Delphi type. `DEVGUS` declares its
own `PByteVal = ^Byte` for `Slot16`'s parameter.

**Sized operands on `CS:` self-patches.** TP7's assembler takes
`MOV WORD PTR CS:[@@Patch],AX` and `MOV AL,BYTE PTR CS:[@@Guard]` but rejects
the same thing without the size, because the target is a code label rather
than a typed variable. Same instruction, same bytes.

**`CALLF [mem]` is spelled `CALL DWORD PTR [mem]`.** TP7's built-in assembler
has no `CALLF` mnemonic for an indirect far call. Same instruction, and the
main project's `src/DEMOVT.PAS` already uses this spelling.

---

## What the VangeliSTracker 1.39b release is good for

`v1.39b/` holds a source release of a LATER version (1.39b, Jan 1994,
GUS-only beta) of the same codebase. **It is corroboration, never truth.** The
disassembly settles every question; the release is used to check a reading
already made, and to supply names.

It has earned its place three times so far:

- **`TPC.CFG`** gave the real compiler switches. See above — two exact
  matches followed immediately.
- **`LIB/SOUNDDEV.PAS`** ships the driver record as `TSoundDevice`, which
  named the three slots that had been `Slot16`/`Slot22`/`Slot2E` and revealed
  the one-byte `DMA` field this tree had swallowed into the ID string.
- **`LIB/DEVGUS.PAS`** contains
  `GUSInitTimer2($100 - ((2000000 DIV (TicksPerSecond*320) + 1) SHR 1))`,
  character for character the divisor derived from `1084:0091..00c6`.

**`MAKE.BAT` gives the build pipeline**, which matters for the byte-exact
target: `tpc X` then `tdstrip X` then `lzexe X`. That is why the shipped
binaries are LZEXE-packed and carry no debug information, and it means a
byte-exact result has to reproduce all three steps, not just the compile.

Where the two disagree, the disassembly wins and the difference is recorded
as version drift. One is already known: in 1.39b the GUS driver points its
`TimerHandler` at the core's shared handler, while in 1.31 it points at its
own counting routine.

### The release's own linker map, diffed against ours

`tools/dosbox/vtbuild.py` compiles the release, and the release ships the `VT.MAP`
from the author's own build, so the two can be compared segment by segment with
the sources held constant. **Every difference is attributable to the toolchain,
not to the code.** 57 segments; 21 come out to the same length and 27 differ, ours
smaller in 21 of those, for 1,114 bytes less code overall. Ours smaller is the
direction to expect if the author's compiler were the older one.

Three things in it are worth more than the totals:

- **`SYSTEM` differs**, `13CA` shipped against `141A` here, and `DOS` by one
  byte. Those are runtime library segments -- not compiled from any source in the
  tree -- so their sizes are a fingerprint of the RTL, and this TP 7.01's RTL is
  not the one the author linked.
- **`OBJECTS` differs** by 74 bytes, and it is Turbo Vision's, from whatever
  `TVISION` directory the author's `/U` line pointed at. Different library, not
  different source.
- **`MAKESTR.EXE` is shipped, and its source with it** -- the only author-built
  binary in the release. Unpacked (it is LZEXE'd) and compared against ours with
  the relocation words blanked, its own `MakeStr` code segment is `011A` bytes in
  both and **instruction-for-instruction identical**: all 34 differing bytes are
  link-time values -- DGROUP offsets, far-call targets -- plus one virtual method
  call, `CALL FAR [DI+24]` against our `[DI+28]`, which is the `OBJECTS` VMT
  layout difference showing through. So for 1.39b's own code, TP 7.01 is
  reproducing the author's codegen; what differs is the libraries around it.

**Do not carry that back to 1.31.** 1.39b is a year later, and the DemoVT
reconstruction's own byte comparison says its compiler was TP6. The two findings
sit together comfortably -- the author moved to TP7 between the two -- and
neither is evidence about the other.

---

## Rules being followed

Carried over from parts 001–007, unchanged:

- Hand-written assembler is transcribed **verbatim**, never re-expressed as
  Pascal. Every line carries a comment giving its address; a block comment
  above holds the equivalent Pascal, labelled reference-only.
- Where the binary is plainly **compiler output**, Pascal is the faithful
  transcription and inventing assembler would be the deviation. `14b7` is
  Pascal for this reason; `188f` is assembler for the opposite one.
- Names are provisional throughout — Borland Pascal 6, no debug information.
  Every routine is named for what it does and followed by the address it came
  from.
- **Do not guess — read the disassembly.**
