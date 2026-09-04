# Continuation — the DemoVT reconstruction

**Start here, then `06-transcription.md`.** This is the whole handover in one file: what the work is, how to run it, what is done, what is left, the risks, and the mistakes worth not repeating. Almost none of it is obvious from the code.

It replaces the numbered per-session continuation notes, which are gone. Everything in them that was still true is here; what was superseded is described as superseded rather than deleted, because several of this project's most useful lessons are about conclusions that fell over. **The name is deliberately not numbered** — update this file in place rather than starting a `09-`.

**A NOTE ON SCRIPT NAMES BELOW THE STATUS BLOCK.** The status block, "The three things you need" and "WHERE THINGS LIVE" were brought up to date on 28 Aug 2026 and are the authority on how to run anything. **The narrative sections further down still name the pre-kit scripts** -- `verify.py`, `blocks.py`, `progcmp.py`, `asmcheck.py`, `census.py`, `omf.py`, `probe.py` -- and that is deliberate: they are a record of what was run at the time, and rewriting them would falsify the account. Read those names as history, and take the rename table in "The three things you need" for what to run today.

---

## WHERE THIS STANDS TODAY — read this before anything else

    python ../kit/tools/pascal/build.py build.toml --sw=/GS   compile and link

    python ../kit/tools/pascal/units.py units.toml                2 byte-identical, 24 identical but for fixups, 0 mismatched
    python ../kit/tools/pascal/objcheck.py objmodules.toml        PLAYMOD OK, SOUNDDEV FAILED at one site -- see below
    python ../kit/tools/pascal/linkorder.py link.toml             30 of 30 positions agree
    python ../kit/tools/pascal/mapcmp.py link.toml                30 unit(s) exact; 0 with a live gap, 0 bytes
    python ../kit/tools/pascal/dgroup.py link.toml                initialised DGROUP: 3184 of 3184 -- +0
    python ../kit/tools/pascal/blockcmp.py blocks/1000.toml       1616 of 1616 bytes of segment 1000
    python ../kit/tools/pascal/linkcmp.py linked.toml             27 unit(s) byte-identical in the linked image
    python ../kit/tools/pascal/linkbytes.py link.toml             0 differing byte(s) in the whole linked image
    python ../kit/tools/pascal/coverage.py link.toml units.toml   44,183 of 44,272 in-scope = 99.8%

    python ../kit/tools/substrate/lzpack.py build/VTMAIN.EXE <NEUROSIS.008>   BYTE-IDENTICAL to the packed original

**EVERY ONE OF THOSE COMMANDS IS NOW THE KIT'S**, and none of them lives under `v1.31b/` any more. The migration ran in two waves -- [psycho #36](https://github.com/sweetlilmre/PsychoNeurosis/issues/36) on 23 Aug 2026 took `build.py`, `asmcheck.py`, `progcmp.py`, `linkcmp.py`, `blocks.py` and the four `blockXXXX.py`; [psycho #50](https://github.com/sweetlilmre/PsychoNeurosis/issues/50) took the rest -- each only once its successor had been measured to reproduce it row for row. The pre-kit originals are archived under the `archive/pre-kit-scripts` tag. **Two things changed about how they are CALLED, and a command copied out of an older note will simply not run:**

* **`linkorder.py`, `mapcmp.py` and `dgroup.py` each take `link.toml`.** The local scripts took no argument, because the paths were baked into them; the kit's hold the method only and read the target from the config.
* **`coverage.py` takes TWO configs, `link.toml` then `units.toml`**, and it still shells out to `units.py` and regex-parses the per-unit table. That parse is fragile by nature -- the row shape is the contract and nothing enforces it. If coverage reports a wild figure, suspect the parse before the build.

**`verify.py` IS GONE, and the reason is worth reading, because this file argued twice for keeping it.** It was held back under both #33 and #36 on the grounds that `units.py` reproduced every row while dropping the two views a person reaches for once a unit has actually diverged. Those views are in the kit now, as `align.regions()` and `align.hexpair()` behind **`units.py --detail` and `--all`**. That was verified on a manufactured failure -- with everything passing neither view fires at all, so a `/$R+` rebuild was used to turn 0 mismatched into 19, and across all 19 units the 566 printed regions, the per-unit counts and the hex dump were identical byte for byte. `omf.py` went with it, as its only importer. **So the standing exception this file recorded no longer exists: reach for `units.py --detail`, not for a script that is not there.**

**THE BUILD IS BYTE-IDENTICAL TO THE UNPACKED ORIGINAL — AND SO IS THE PACKED FILE, AS OF 28 Aug 2026.** `kit/tools/substrate/lzpack.py` reproduces LZEXE 0.91 and `NEUROSIS.008` comes back byte for byte, all 31,711 of it. Risk 3 is closed; see its section below.

    load image      55,056 bytes, BYTE-IDENTICAL
    relocations     772 entries, the same 772 linear targets
    EXE header      every field matches

All thirty-one segments are transcribed; every unit and the program reproduce their
segment; the segment order is the original's; both halves of DGROUP are laid out
correctly. **There is no remaining difference between `build/VTMAIN.EXE` and
`v1.31b/ref/vt1.31b.bin` that this tree can measure.** The only thing left
was the PACKED file, and that is CLOSED as of 28 Aug 2026 — `kit/tools/substrate/lzpack.py` is
LZEXE 0.91's packer written out, and it reproduces `NEUROSIS.008` byte for byte.
See risk 3's section below.

**FIRST THING TO DO IN A NEW SESSION: run the nine commands above and check they still say that.** The eight checks take a few seconds together, they are all computed rather than recited, and a disagreement means something has drifted — which is worth knowing before touching anything. `build.py` refuses to compile when its lint fails, but read the build output anyway.

**Pass `--sw=/GS` from POWERSHELL, not Git Bash** — MSYS rewrites the leading slash into a path and the build then silently compiles nothing. This bites every session that starts in a bash shell.

**And check the load image directly while you are there**, because none of the nine commands compares the whole file:

    cmp <(tail -c +3121 build/VTMAIN.EXE) <(tail -c +3121 ref/vt1.31b.bin)

Both files are 58,176 bytes; from 3120 on, the 55,056-byte load image is byte-identical. A bare `cmp` of the two files reports 2,709 differing bytes and **that is expected** — byte 13..14 is `maxalloc`, which our unpacker writes itself, and everything from offset 301 is the relocation table's seg:ofs re-encoding. Both are the measurement caveats below, not build differences; `relmatch.py` is the meaningful relocation test.

Two caveats on the header, and both are about the MEASUREMENT rather than the build:

* **`maxalloc` reads $FFFF in the original and 43140 in ours, and that is OUR unpacker's
  doing.** `tools/unlzexe.py` writes `0xFFFF` into maxalloc itself and RECOMPUTES minalloc
  from SS:SP, because LZEXE preserves neither. So neither field is evidence about the
  original build, and minalloc agreeing is partly circular. SS:SP themselves ARE preserved
  in the packed header, which is what makes the stack finding below real.
* **The relocation table's ORDER and its seg:ofs encoding differ**, while the set of LINEAR targets is identical to the entry. The same linear address can be written as many seg:ofs pairs and LZEXE re-encodes them, so the order is the unpacker's normalisation. Comparing linear addresses is the only meaningful test and it passes.

  **MEASURED, 28 Aug 2026, and it is worth seeing once** because the shape of the difference is what makes it obviously benign. Both tables hold 772 entries at offset 28. **The first 68 entries are byte-identical**; they diverge at index 68, file offset 300, and from there our linker writes a NON-ZERO segment where LZEXE re-encoded everything onto segment 0:

        idx        built     lin           ref     lin
         68   0065:000a    1626    0000:065a    1626
         69   0065:007d    1741    0000:06cd    1741
         70   0065:0084    1748    0000:06d4    1748

  Same linear address, two spellings. TP6's linker emits a fixup relative to the segment the reference sits in; LZEXE flattens each one to `0000:linear` while linear still fits in 16 bits. So the 2,709 bytes are **772 entries re-spelled, not 772 different targets** — and `nreloc`, `hdrsize`, `minalloc`, `ss:sp`, `cs:ip` and both size fields all agree exactly.

### HOW THE LAST FIVE BYTES WENT — three findings, and one of them withdrew a claim

Until the last session five bytes in `PLAYMOD` were the only difference left in any linked
segment: three RTL call targets. They are worth reading even though they are closed,
because two of the three are general.

* **TWO COPY HELPERS, ELEVEN BYTES APART IN BEHAVIOUR.** `1ba1:0fb2` is `Move` -- it
  compares the pointers and copies BACKWARDS when the regions overlap -- and `1ba1:09f7` is
  the same loop with no overlap check, which is what the compiler emits for a whole-array
  ASSIGNMENT, where it knows the operands are distinct. The original calls `09f7`, so
  `12ba:075e` and `12ba:119e` are `Volume := UserVols`, not `Move(...)`. That needs the
  release's NAMED type `TVolumes` on both operands, because Turbo Pascal only allows a
  whole-array assignment between operands of the same named type -- which is exactly why
  both sites read as `Move` for as long as they did.
* **AND OUR RTL IS THE AUTHOR'S, WHICH IS WHAT MADE THAT READABLE.** `OBJECTS`, `DOS` and
  `SYSTEM` are all THREE byte-identical to the original's. **That closes the library half of
  risk 2**, which this file has carried since the release's map showed the author's RTL
  segment sizes differing from this install's -- that finding was about 1.39b's toolchain
  and does not carry to 1.31, exactly as the note there warned. It also turned the `Move`
  difference from a toolchain question into a source one.
* **A SHIFT, NOT A SECOND DIVISION.** `1ba1:0aa8` is the 32-bit shift LEFT
  (`AND CX,1Fh / SHL AX,1 / RCL DX,1 / LOOP`) and `1ba1:0a9c`, twelve bytes earlier, is the
  shift right; `MOV CX,4` in front of it multiplies by sixteen where our source had
  `div 4`. **And the release has the line commented out**, which is where the constant comes
  from: `LIB/PLAYMOD.PAS` line 938 holds a dead `NoteCalcVal := ((65536*13900) DIV NoteHz)
  SHL 8;` above the live line that replaced it, and 65536 * 13900 is $364C0000 exactly. So
  1.31 is the earlier form 1.39b commented out, with a shift of 4 rather than 8. **A
  commented-out line in the release is not a record of what 1.31 did -- except when it is
  the line 1.31 still has**, which is the fifth time that file has decided something here
  and the first time the dead code was the answer.
* **THE STACK IS 20,000 BYTES.** `{$M 20000,0,655360}`. The original's initial SP is $4E20
  and its MINALLOC is 226 paragraphs larger than a default build's, which is 3,616 bytes,
  which is 20000 - 16384 exactly -- two header fields agreeing on one number. HeapMin stays
  0 because MINALLOC would otherwise be out by more than the stack delta.

### ~~WHAT IS ACTUALLY LEFT — risk 3, and it needs a tool that is not here~~ — **CLOSED 28 Aug 2026**

**THE PACKED FILE IS BYTE-IDENTICAL TOO. `kit/tools/substrate/lzpack.py` IS LZEXE 0.91's PACKER, WRITTEN OUT.**

    python ../kit/tools/substrate/lzpack.py build/VTMAIN.EXE $VT_PACKED
        BYTE-IDENTICAL to the original packed file
    python ../kit/tools/substrate/lzpack.py --selftest ../DEMOVT15 ../v1.39b $VT_PACKED
        10 of 11 LZ91 file(s) reproduce exactly

The chain now runs end to end with nothing left over: our Pascal source → TPC 6.0 → `build/VTMAIN.EXE` → packed → **`NEUROSIS.008` itself, all 31,711 bytes, same MD5.** The section below is kept because its reasoning was right — LZEXE is third-party and was not going to be fetched — but the conclusion that this was "a decision for the user" is superseded: the packer was cheaper to derive than to acquire.

**THE ENCODER IS A PORT OF LZEXE'S OWN, as of 28 Aug 2026.** The user found the source — **LZEXE 0.91, MIT licence, © 1989–1990 Fabrice Bellard, published by its author at <https://bellard.org/lzexe/>** — and `tokenize()` is now `lzss.asm`'s `LZCOMP` ported line for line. **Twelve of twelve LZ91 files reproduce token for token**, 4,176 to 63,040 bytes, across three unrelated authors: this target, DemoVT 1.51's own tools, and Borland's `INTRFC.EXE` from the TP 7.01 distribution.

**IT WAS REVERSE-ENGINEERED FIRST, AND THAT IS WORTH READING, because the measurement was honest and still wrong in three places.** The method was to decode the original's 21,020 tokens and score candidate matchers by how long a prefix each reproduced — turning "what would a packer do" into a measurement:

| matcher | tokens reproduced |
|---|---|
| cost-based lazy matching | 198 |
| pure nearest-match | 56 |
| **plain greedy longest, nearest on a tie** | 3,724, then all 21,018 with the right window |

That got **eleven of twelve** files exactly. **Being clever is measurably wrong**, and that part held up: the lazy matcher produces a stream 3,029 bits *smaller* than LZEXE's and reproduces nothing.

**WHAT READING THE SOURCE CORRECTED:**

* **A "no match with fewer than 3 bytes left" rule does not exist.** It had been measured *and bracketed from both sides* — 3 reproduced every file, 4 and 5 broke files that end in short matches — and it was still an invention. What exists is `mov cx,LENMAX-1`: **the compare length is never clamped to the remaining input**, only the emitted length is (`cmp ax,LENREST`). Near the end of a file the compare runs off the data into ring content that was never overwritten, and often lands on a distance too far to encode a 2-byte match. The invented rule described that effect closely enough to pass every test available.
* **The segment step resets its counter to zero**, not to `(DI & 15) + 0x2000`. The reverse-engineered version reasoned that from the decompressor stub and agreed with every file only because none needs more than one step.
* **The 7,939 window is the right number for the wrong reason.** Not "0x2000 less the longest match" as a rule: the first read simply lands at ring offset `BUFSIZE−LENMAX` with the write pointer `LENMAX` ahead of the coding pointer, so that is how much history the ring leaves behind.

**And `BIN2DB.EXE` — the one file no rule of that shape could reach — is fixed.** Its last token is an 11-byte match at distance 254 where every distance from 12 to 3,569 gives the same bytes. Before the source arrived this had been narrowed correctly: established as *output-equivalent* rather than wrong, with the zero-padded-ring hypothesis rejected on three named counter-examples (`CTST`, `MAKESTR`, `INTRFC`). The padding was the right idea; the content is stale ring data, not zeros. The port gets it for nothing.

**LESSON, and it is the transferable one:** measuring against a single artefact gets you a long way and tells you honestly how far, but it cannot tell a rule from a coincidence that fits. **Where the source exists, read the source.**

**WHAT IS COMPUTED AND WHAT IS COPIED.** Computed: the 30,480-byte bitstream and the 855-byte relocation table (linear deltas — it re-encodes byte-identically), plus the header's sizes. Copied: LZEXE's 344-byte decompressor stub, and `ss:sp`, `ip`, `minalloc`, `maxalloc`. **31,335 of 31,711 bytes are ours; 376 are LZEXE's.** `exepack.asm` and `lzexe.pas` in the same archive hold the header arithmetic, so porting that would close the last 376 bytes — not done.

**THE ORIGINAL PACKED FILE IS NOT TRACKED HERE** — only the unpacked image is. Point `VT_PACKED` at a copy of `NEUROSIS.008` or pass `--packed`; the sibling psycho checkout has one at `bin/NEUROSIS.008`. It supplies both the comparison target and the stub.

---

### *(superseded by the section above)* — WHAT WAS LEFT — risk 3, and it needed a tool that was not here

`MAKE.BAT` gives the pipeline as `tpc` -> `tdstrip` -> `lzexe`, and the packed file is the
only thing not yet compared.

* **`TDSTRIP.EXE` IS AVAILABLE** -- `C:\TASM410\BIN\TDSTRIP.EXE` in the DOSBox HDD image --
  and it looks like a no-op here: our EXE is 58,176 bytes, which is 3,120 of header plus
  55,056 of load image and nothing after it, so there is no debug information to strip.
  Worth running once to confirm rather than assuming.
* **LZEXE IS NOT IN THE TREE OR THE IMAGE.** It is a 1989 third-party packer and the
  version matters -- the shipped file is LZEXE 0.91. Without it the packed original cannot
  be reproduced, and **this is a decision for the user rather than something to go and
  fetch.** Until then, 1:1 against the unpacked image is the ceiling.

### THE SEVEN MEASURES, AND WHAT EACH ONE CANNOT SEE

This is the most useful thing to understand coming in cold: **no single tool here measures
the whole thing, and each one is blind to something the next one catches.** Every defect
class this project found late was found because a new tool could see what the old one
could not.

| tool | what it compares | what it CANNOT see |
|---|---|---|
| `units.py` (was `verify.py`) | a `.TPU`'s CODE against its segment | every DGROUP address and inter-unit call — they are pending fixups it excuses. Also cannot see whether a routine is an init section or a named procedure |
| `objcheck.py` (was `asmcheck.py`) | a `{$L}` module's relocations against its `.OBJ` | anything outside the assembled run |
| `linkorder.py` | the `uses` graph against the original's segment ADDRESSES | nothing about contents; it is a constraint check |
| `mapcmp.py` | linked segment LENGTHS, both padded to a paragraph | contents. A unit can be the right length and wrong throughout |
| `dgroup.py` | the INITIALISED DGROUP image, byte for byte | plain `var`s, which are never written to the EXE. **And a boundary inside a run of zeros** — it read 100% identical while `SelfName` was six bytes too long |
| `progcmp.py` | segment `1000`'s code, per routine, shift searched | it is the program only |
| `linkcmp.py` | ALL twenty-seven linked segments, with fixups resolved | needs the order and every size already right, or nothing lines up |

**AND THE ORDER THEY HAD TO BE USED IN WAS FORCED.** `linkcmp.py` is the strongest measure
and it was useless until `mapcmp.py` and `linkorder.py` had made the segments line up; the
variable half of DGROUP could not be touched until the constant half was exact; and the
constant half could not be measured until the program linked at all. **If a measurement
here looks impossible, check whether something upstream of it is still wrong.**

### THE LAYOUT RULES, all measured and none documented anywhere else

    segment order = reverse DFS post-order over the `uses` graph, clauses in
                    declaration order, interface clause before implementation

    DGROUP        = [ every unit's TYPED CONSTANTS, in link order ]
                    [ every unit's plain VARIABLES,  in link order ]
                    declaration order inside each unit's block

* **Each typed constant is word-aligned**, and each unit's block starts on a word boundary.
* **An unreferenced typed constant is smart-linked away** — so every constant in the
  original's DGROUP is referenced by surviving code, which turns a layout gap into a search
  for a reference rather than a place to invent filler.
* **A VMT is DGROUP data, laid down where the TYPE is declared**, as
  `[size][-size][far pointers]` — and its size word NAMES the type. That is what corrected
  `SongColl` to a `TStringCollection` after a call site had argued the opposite.
* **A base-1 array's "address" in an instruction is one element low.** Ten of them in this
  tree; five in `PLAYMOD`'s variable block alone.
* **A `uses` entry that references nothing is real, in both directions** — `VTCMD` carried
  one, and `SONGUNIT` turned out to NEED two. A clause changes the link, never the code.

### A NOTE ON THE FIGURES FURTHER DOWN

**The per-segment sections below quote the numbers that were true when each was written**,
and several of them say things like "one segment remains" or "96.1%". They are records of
how a segment was taken, not statements about today. **The only current figures are the
ones at the top of this section**, and every one of them is produced by a tool rather than
recited — run the tool if in doubt. Everything below "Where to pick up" is explicitly
history.

### DO NOT READ THIS AS FINISHED

The EXE is not byte-exact yet and nothing about `tdstrip` or `lzexe` has been tried. What
IS true is that the CODE and the DATA LAYOUT are now reproduced, which is what the previous
five phases of this project were working towards.

**And treat the five remaining bytes as suspicious rather than settled.** Every "unfixable"
thing this document has ever recorded turned out to be ours — five compiler differences,
three structural deviations, a patch level, and two conclusions overturned in the last
session alone. The prior on "it is the RTL" should be low until a probe says otherwise.

### HOW `CMDLINE` AND `VTCMD` CAME BACK — 3,328 BYTES FOR ONE STATEMENT

They were 1,200 and 2,128 bytes short, the two largest gaps in the map, and they were **one missing reference between them**. `VTMAIN` declared `Obj0E38 : TObject` and `Var0F82 : TCollection` — placeholders at the two addresses the body constructs — and those are `VTCmd`'s own `Cmd : TVTCmd` and `SongColl`. With nothing calling a virtual method on `Cmd`, `TVTCmd`'s VMT is dead, so the smart linker dropped every method of `VTCmd` AND of `CmdLine`, whose bodies are only reachable through that VMT. `CMDLINE` was down to `GetDOSCmdLine`'s thirty bytes.

**AND THE CALL IS ONE STATEMENT WHERE THE READING HAD TWO.** `1000:05f4` pushes `SS:[BP-0100]` and calls `GetDOSCmdLine`; `05ff` then pushes only `Self` before `CALLF [DI+08]`. A `String` function does not pop its own hidden result pointer — the caller does — so the pointer still on the stack IS `ParseLine`'s argument:

    Cmd.ParseLine(GetDOSCmdLine);

Written as two statements the temporary is discarded and `ParseLine` has nothing to take. **That is the `RETF 4` rule one call further on than this document already had it**: it was recorded for `IPath := GetInsidePath`, where the result pointer becomes an assignment's source. Here it becomes the next call's parameter.

**`SongColl` IS A PLAIN `TCollection`, NOT A `TStringCollection`** — `1000:05cd` far-calls `1891:03a7`, which this tree established as `TCollection.Init` from `14b9`'s three `Init(n,n)` calls. A `TStringCollection`'s constructor is `TSortedCollection`'s, a different routine. Everything `VTCMD` does to it agrees: `AtInsert(Count, NewStr(Token))` is the unsorted idiom, and `DoSongColl` reads it back through an explicit `PString(...)^`. **Eighth interface detail settled by a caller in another segment.**

### TP6'S SEGMENT ORDER IS REVERSE DFS POST-ORDER, AND THAT MAKES THE ORDER SOLVABLE

Undocumented anywhere, and derived here by simulating candidate rules against a real `/GS` map: **TP6 emits segments in reverse DFS post-order over the `uses` graph, walking each unit's clauses in declaration order, interface clause before implementation.** Reverse PRE-order is the plausible wrong answer and it transposes `VTCMD`/`FILEUTIL`/`CMDLINE`, which is the cheapest way to tell the two apart if this needs re-deriving. `SYSTEM` is appended last, never reached by a `uses`.

**SO THE ORIGINAL'S SEGMENT ADDRESSES READ BACKWARDS ARE ITS FINISH ORDER**, which turns a free choice into an equation — and it is one of the very few things about the original's LINK that can simply be measured. `linkorder.py` solves it, and `VTMAIN`'s clause is now the answer rather than a guess:

    Dos, VTResid, DevSB, VTShell, Objects, Heaps, PlayMod, VTCfg, VTCmd, DevGus, VTSilenc

Two entries are worth pointing at because a reader would get them wrong: **SoundDevices, SoundBlaster and Hardware are not listed at all** — they arrive through `DevSB`, and naming any of them earlier pulls it forward and moves three segments — and **SongElements and GUS arrive through PlayMod**, via `SongUnit`. Everything after those eleven is already finished when the walk reaches it, so its position is unobservable.

**AND THE CONSTRAINT CHECK IS WORTH MORE THAN THE PREDICTION.** Every `uses` edge in the tree can be tested against the original's order: if U uses V then V must finish first. Two edges failed, and each was a real defect:

* **`PLAYMOD uses VTSilenc` is impossible** — VTSilenc finishes LAST of the units. It was there for one identifier, `Ticks` at `DS:$0bc8`, which therefore cannot be declared in VTSilenc. The declaring unit has to be one both use, which leaves SoundDevices and Hardware, and the address decides: **SoundDevices already owns `$0bc7` and `$0bce`, so `$0bc8` is inside its block.** Moved there. It also reads better — the core owns the shared poll at `1a17:1008`, and a counter the periodic tick advances and the mixer paces against belongs with it rather than with the one driver that happens to advance it on a machine with no sound card.
* **`VTCMD uses DevGUS` is impossible** — DevGus finishes after VTCmd. Not one identifier from DevGus is named anywhere in `VTCMD.PAS`, so the clause entry was never doing anything. **A `uses` entry that references nothing is a real phenomenon here**, which matters for the next item.

**AND THE ORDER FORCED TWO ENTRIES INTO `SONGUNIT`'s CLAUSE THAT NOTHING IN IT REFERENCES.** Between `HEAPS` and `SONGUNIT` the original's finish order runs GUS, SongElements, **VTNotes**, UnkLoader, AsciiZ, ModLoader, **Filters** — so VTNotes must be reached before UnkLoader and Filters after ModLoader, and `SongUnit` is the only unit positioned to do either. That is a strong claim from one rule, so it wanted corroboration, and **the release supplies it exactly**: `LIB/SONGUNIT.PAS`'s implementation clause is `SongUtils, UnkLoader, ModLoader, OktLoader, S3mLoader, StmLoader, Loader669, ExeLoader, Heaps, StrConst, AsciiZ, Filters`. Remove the six loaders 1.31 has not got and `StrConst`, rename `SongUtils` to what this tree calls `1650`, and what is left IS the clause the link order demanded, in that order. **The order was derived from the addresses first and the release checked after** — nothing was fitted.

That also settles a pending rename from the other direction: `relmatch.py` scored `1650`/`VTNOTES` against `LIB/SONGUTIL.PAS` at 71.1%, and `SongUtils` being first in that clause is what the link order needs. Two independent arguments for the same pairing.

## HOW THE VARIABLE HALF OF DGROUP WAS SORTED

`v1.31b/linkcmp.py` is the instrument and it is the last one this project needed. The
variable half is not in the EXE at all -- a `var` is space the linker never writes -- so
`dgroup.py` is blind to it by construction. **But the CODE records it**: in the LINKED
image every DGROUP fixup is resolved, so a variable in the wrong place shows up as a wrong
operand in every instruction that touches it. The tool compares all twenty-seven linked
code segments against the original's and classifies each difference as a variable address,
a constant address (a regression) or real code.

**IT ONLY BECAME POSSIBLE ONCE THE SEGMENT ORDER AND EVERY SEGMENT SIZE MATCHED**, which
is why this was last. Before that the segments did not line up to compare and every
address was wrong anyway.

### THE LAYOUT RULE IS THE SAME ONE, APPLIED TWICE

    DGROUP = [ every unit's TYPED CONSTANTS, in link order ]
             [ every unit's plain VARIABLES,  in link order ]

with declaration order inside each unit's block. The variable half runs from about $0c70
to $4690. Everything that worked on the constant half worked here: read the step, read the
release's declaration order, lay it between the addresses instructions already name.

### THE BIG ONE WAS A 2,000-BYTE STACK

**`SoundDevices.DevStack` was missing entirely**, and it is most of the 2,350 bytes our
whole DGROUP was short. It is the private stack the shared poll switches to, and
`SavedSS`/`SavedSP` -- the release's `DevSS`/`DevSP` -- are the caller's stack saved
across the switch. Its size came out of two addresses: `SavedSS` is at $4302 and with
everything before this unit accounted for the block had to start at $3b32, and
`$4302 - $3b32` is exactly `$7D0`. **The release has `DevStkSize = 1000`; 1.31's is 2000**
-- a count is data, and the release is worth nothing for data, the same rule that made
`NumBuffers` 1 rather than 3 and `MaxOutputFreq` 44000 rather than 45000.

### AND A 340-BYTE ARRAY THE ARITHMETIC DEMANDED

`VTNOTES`'s variable block ends where GUS's begins at $371a, and `NoteOf` runs
$25c6..$35c5, so there are exactly $154 -- 340 -- bytes after it. 340 is 85 x 4, which is
`array[0..84] of String[3]`; and `LIB/SONGUTIL.PAS`, the release counterpart `relmatch.py`
scored this segment against at 71.1%, declares exactly two variables: `NoteIdx : TNoteSet`
and `NoteStr : TNoteStringSet`, the printed name of each note. `NoteOf` is the first; this
is the second. Nothing in the tree reads it and it holds no data, so `census.py` finding no
printable string in the segment is consistent -- **the arithmetic is the only reason to
believe it exists, and it is enough.**

### SIX MORE UNITS HAD VARIABLES THAT WERE NOT THEIRS

Each was found the same way, and every one had the right ADDRESS in a comment and the
wrong owner:

| was declared in | belongs to | how the layout said so |
|---|---|---|
| `VTSILENC`: `Frac` $0018, `OldVec` $001a | itself, but as TYPED CONSTANTS | both are in the INITIALISED half, and the six bytes were being counted as the tail of the program's `SelfName` -- which is why that was read as `String[25]` and is really `String[19]` |
| `VTSILENC`: four `Flag0Bxx` | `SoundDevices` | the values name them: Start writes 1, 0, 8, 0, which is `IsDmaDevice := True`, `Stereo := False`, `DevBits := 8`, `MixMethod := 0` |
| `VTCFG`: `DACPort`, `LDACPort`, `RDACPort` | `SoundDevices` | $0bf2 is inside its block; VTCfg writes them from `Port`/`LPort`/`RPort` |
| `VTCFG`: `VTDir` | `VTGlobal` | $083a is VTGlobal's FIRST datum, a `DirStr` that closes the gap down to `DevPtr` at $087e |
| `SONGUNIT`: `LowQuality` | `SongElements` | it was a DUPLICATE -- SongElements already declared it correctly -- and two bytes is exactly what `NoteOf` was out by |
| `VTMAIN`: `Str1208`, `VarC76`, `VarC78`, `Var0F3A` | itself at $0cd6, and three FIELDS | `VarC76`/`VarC78` are `Song.SongStart`/`Song.SongLen`; `Var0F3A` is `Cmd.FileDir`, which `109c`'s own `InterpretNoSwitch` passes to the same routine |

**`SelfName` IS THE ONE WORTH REMEMBERING.** `dgroup.py` reported the initialised half
100% identical while that string's declared LENGTH was six bytes too long, because every
byte from $0018 to $001d is zero whichever way the six are divided. **A byte comparison of
initialised data cannot see a boundary inside a run of zeros.** Only an instruction that
names an address can, and that is what `linkcmp.py` reads.

### AND THREE UNITS HAD THEIR VARIABLES IN THE WRONG ORDER

Same class as the constant half, and invisible for the same reason -- the addresses were
all right and the ORDER was not:

* **`PLAYMOD`**, twenty-one variables scattered over fourteen different deltas. The
  release's interface VAR group is the order exactly: SplBuf, ActualHz, NoteHz,
  NoteCalcVal, UserVols, Permisos, TickCount, ModTickProc, MyCanFallBack, FilterVal. Five
  of the addresses in it are BASE-1 BASES rather than the arrays -- $11ee, $1207, $120f,
  $123a, $1384 -- which this file already records as a rule.
* **`SOUNDDEVICES`**, where the buffer-queue group was declared first and belongs last,
  and two pointer pairs were each the wrong way round.
* **`VTSHELL`**, whose order is `ConFile`, `ProgName`, `SavedExit` -- $39de + 256 is $3ade
  and $3ade + 80 is $3b2e, and 256 + 80 + 4 is this unit's whole data size. `ProgName` was
  first, which meant a `Text` file variable has to be exported.

## HOW `DEMOVT` WAS CLOSED — 1,715 BYTES TO 1,604, AND THE LINK IS EXACT

`v1.31b/progcmp.py` is the instrument, and it exists because `verify.py` cannot measure a
PROGRAM: it compares a `.TPU`'s CODE against a segment, and `1000` has no `.TPU`. So the
program was the one segment with no measure at all until the whole thing linked.

**IT COMPARES PER ROUTINE, WITH THE SHIFT SEARCHED RATHER THAN ASSUMED**, exactly as
`blocks.py` and the four `block*.py` scripts do for units — a whole-segment prefix is
useless while a size is wrong, because the first byte that disagrees is a displacement or
an address and everything past it reads as broken. Twelve blocks from the header of
`VTMAIN.PAS`, and watching them go exact one at a time is what made this tractable.

It also classifies the differences, and only the third class is a defect: a SEGMENT word
7 paragraphs low (the program's own overshoot, self-correcting), a DGROUP address in the
VARIABLE region above $0c70 (unmeasurable, and still is), or real code.

### ELEVEN FIXES, AND SEVEN OF THEM ARE RULES THIS FILE ALREADY RECORDED

| bytes | what it was |
|---|---|
| −514 | **`PlayModule`'s parameters are `PathStr`, not `String`.** `ENTER 00a2,0` is 162 = 80 + 80 + the result byte + a pad, and nothing else; declared `String` the two value parameters get 256-byte copies each and the frame is 676. And the two `LEA DI,[BP-52] / PUSH SS / PUSH DI / PUSH 4Fh / CALLF` groups are the COMPILER'S parameter copies, not `N := Name` statements — reading them as assignments is what invented the two locals |
| −10 | **`Ok : Boolean` is the FUNCTION RESULT.** The tail is `MOV AL,[BP-1] / LEAVE / RETF 8`; Borland allocates the result at the top of the frame, ABOVE the parameter copies, so a separate local lands below them at [BP-$a3] and every reference grows two bytes. This file already had the rule as "assign to the function identifier, not to a local" |
| −30 | **Three `WriteLn`s, not six.** Each bare `WriteLn` after a `WriteLn(X)` costs ten bytes and prints a blank line the original does not |
| −18 | **One statement, not two:** `LongInt(DMABufferPtr) := LongInt(GetPlayPos) and $FFFFFFFC`. **The redundant `AND DX,0FFFFh` is the tell** — masking a high word with all-ones does nothing and no programmer writes it, but a 32-bit `and` against a constant emits both halves whatever they hold |
| −13 | **`Self : String` is the compiler's temporary**, and `FSplit(ParamStr(0), Dir, Name, Ext)` is one call: a String function does not pop its result pointer, so it is still on the stack as FSplit's first argument. **Third instance of that rule in this file** |
| −7 | **No explicit `Halt(0)`.** The original ends `CALL ShowBanner / LEAVE / XOR AX,AX / CALLF 1ba1:00e9` — the LEAVE comes BEFORE the halt, which no statement can produce. Those seven bytes are TP's own end-of-program sequence, and writing the call as well emitted it twice |
| −1 | **`TimerChain` is `far`, and the `CB` at $0170 is its EPILOGUE.** It wrote the RETF as `DB 0CBh` and got an epilogue on top |
| +6 | **`MOV SI,0000` and not `XOR SI,SI`**, six times. Same value, three bytes against two. This file records the identical fix in `VTRESID`, where four of them cost four bytes |
| +5 | **The `ES:` prefix on a call through a pointer loaded with `LES`** — `26 FF 5D 2A`, five times |
| −2 | ...**and NOT on a call through `MOV DI, OFFSET <dgroup object>`**, twice, where the VMT fetch and the call are both DS-relative. **Same instruction, two addressing bases, one byte apart** |
| — | fifteen `Var<addr>` placeholders resolved to other units' globals (below) |

### AND FIFTEEN PLACEHOLDERS WERE OTHER UNITS' GLOBALS, WHICH THE LAYOUT NAMED AT ONCE

Every one fell inside a block whose owner the DGROUP work had just settled, so all
fifteen went in a single pass. None of it was visible before: a DGROUP reference is a
linker fixup, so the program compiled and `verify.py` agreed either way.

    Shown      $09e8 -> VTGlobal.NoBanner        Driver    $0b96 -> SoundDevices.ActiveDevice
    Var2CE     $02ce -> PlayMod.MaxOutputFreq    Var1208   $1208 -> PlayMod.UserVols
    AltMode    $02d1 -> PlayMod.AltMode          Var342/4/6 $0342.. -> ModCommands.Req*
    Byte8BA    $08ba -> VTGlobal.VtVolume        Flag8BB   $08bb -> VTGlobal.ShellLoopMod
    Var8BC     $08bc -> VTGlobal.ShellHz         Var8C2/4/6 $08c2.. -> VTGlobal.VT*
    Byte0CCD   $0ccd -> Song.Status              PlayProc  $009a -> VTCmd.OneModPtr

Three of them are worth more than a rename:

* **`Shown` and `NoBanner` were always one byte.** ShowBanner tests $09e8 and `109c`'s
  `nb` switch sets it; the note under `nb` has described it that way all along, and this
  program had a second name for it.
* **`Byte0CCD` is not a variable at all.** `Song` is this program's `TSong` at $0c74 --
  `1000:0322` is `MOV DI,0C74h` and the virtual calls at `038d` and `03fb` go through it
  -- and $0c74 + $59 is $0ccd, the record's `Status`. **A field of a global and a global
  of its own are identical in a `MOV`.**
* **`PlayProc` IS `VTCmd.OneModPtr`, AND IT JOINS UP A MECHANISM FROM BOTH ENDS.** $009a
  is four bytes immediately below `TVTCmd`'s VMT at $009e, inside VTCmd's block, and
  VTCMD.PAS already declared it -- `OneModPtr : Pointer = nil` with `OneMODProc :
  TDoOneProc absolute OneModPtr` laid over it, which is how 1993 Pascal gives a
  procedural variable a default. `1000:05e2` installs this program's `PlayModule` into
  it, `DoSongColl` calls it for every entry the command line collected, and `109c:079f`
  clears it -- which this project had already read as "the caller's hook cannot outlive
  the collection", from the other side, without knowing who installed it.

### ~~WHAT IS LEFT, AND IT IS ONE THING~~ — *(closed in the session after this one)*

    63 differing bytes in DEMOVT, in 38 runs, and all 38 are DGROUP VARIABLE addresses.

That was the uninitialised half of DGROUP, and it is now sorted -- `DEMOVT` is
byte-identical. `dgroup.py` measures the initialised half exactly and is blind to the
other by construction: a plain `var` is reserved space the linker never writes, so nothing
in the EXE records where one went. **What could see it was the CODE**, where every fixup is
resolved; that is `linkcmp.py`, and "HOW THE VARIABLE HALF OF DGROUP WAS SORTED" above is
how it went.

## HOW RISK 1 WAS CLOSED — 848 BYTES TO ZERO

Every block was closed the same way: read the step off `dgroup.py`'s ladder, read the original's bytes in that range, and lay the RELEASE'S DECLARATION ORDER into it between addresses instructions already name. The release supplied the order and the names; the image supplied every value. `verify.py` reported 2 byte-identical / 24 identical-but-for-fixups / 0 mismatched after every single change, which is the whole proof that none of it moved a byte of code.

### THE RULES, all measured, none of them documented anywhere else

* **DGROUP = [every unit's TYPED CONSTANTS in link order][every unit's plain VARIABLES in link order]**, with declaration order inside each unit's block.
* **Each typed constant is WORD-ALIGNED**, and each unit's block starts on a word boundary. Six pads in the image are explained by nothing else.
* **AN UNREFERENCED TYPED CONSTANT IS SMART-LINKED AWAY.** The most useful of the four, and it cost an hour to notice: a 64-byte filler added to `HEAPS` appeared in its `.TPU` (340 bytes of data, up from 276) and produced **nothing** in the linked image. So every typed constant in the original's DGROUP is REFERENCED by surviving code — which turns a layout gap into a search for a reference rather than a guess, and is how `CmdList` was finally found. It also explains DevSB's four `*DevID` constants contributing nothing: the device records use literals instead, so all four are dead.
* **A VMT IS DGROUP DATA, AND ITS SIZE WORD NAMES THE TYPE.** Turbo Pascal lays an object type's virtual method table down as `[size][-size][far pointers]`, positioned where the TYPE is declared rather than where the unit's constants are. `TSong`'s is `005e ffa2 002b 04b9` — SizeOf(TSong) = $5e, its negative, and a far pointer to `TSong.Done` at `14b9:002b`. Moving `ModOffset`'s declaration below the type is what got those two into the right order.

### AND A VMT SIZE WORD OVERTURNED A CONCLUSION THIS FILE HAD ARGUED FOR

**`SongColl` IS A `TStringCollection`, NOT A PLAIN `TCollection`.** The entry above got that wrong, and the refutation is worth more than the error. The argument was that `1000:05cd` far-calls `1891:03a7`, which this tree established as `TCollection.Init`, so the object could not be a sorted collection. **TP6's `Objects` gives `TSortedCollection` no `Init` of its own** — so a TStringCollection INHERITS `TCollection.Init`, and that call is exactly what one produces. The original's image holds THREE `Objects` VMTs, of sizes 8, 12 and 13, where ours held two: size 12 is `TCollection` (VMT 2 + Items 4 + Count 2 + Limit 2 + Delta 2) and 13 is that plus `Duplicates`. Declaring it a TStringCollection recovered all 48 bytes at once.

**A call site cannot name a type and a VMT can** — a new instrument, and it came from the data rather than the code.

### WHAT THE RELEASE NAMED, block by block

Each of these was either missing entirely or was a plain `var`, and in each case the release's declaration order landed on addresses the disassembly already knew:

| block | what the layout found |
|---|---|
| `VTGLOBAL` $083a | the whole unit, 359 bytes. `DevID = 'DMA-SB-Mono'` — **1.31's default device is the Sound Blaster** where 1.39b's is the GUS, which corroborates DevSB registering first in the init chain. `VTDir` gets a measured address again, $083a, and is a `DirStr` |
| `MODCOMMANDS` $0334 | sixteen typed constants on sixteen known addresses, four values non-zero and exact: 125, 125, 6, 1, 1. **Nine had been declared in PLAYMOD**, and interleaved addresses are what proved they could not be |
| `PLAYMOD` $02c4 | the whole block in address order. `MaxOutputFreq` is **44000** where the release has 45000; `MaxSplPerTick` agrees at 880. `Pannings` was `array[0..8]` declared AT ITS BASE-1 BASE — nine bytes where there are eight, invisible because the displacement is identical either way |
| `SOUNDDEVICES` $0b94 | 42 constants. **Eight FILTER coefficients** at $0bd2 (6, 3, 13, 0 per channel, twice), **three DAC ports** at $0bf2 all holding $378 = LPT1, `DMAStop`/`DMAStopped`/`DMAIrqWatch`, and a **fifth** output slot. `TicksPerSecond` = 50, `DMAChannel` = 255, and `DefaultHz` = 16000 read three separate times |
| `GUS` $0582 | four release constants exact — $FFFF, 11, 32, 19293 — and `IrqCode` + 16 = `GUSPorts` closes the block with nothing over |
| `SOUNDBLASTER` $0b1d | four `*Force` flags between `SbHiSpeed` and `SbVersionMin`, which is what the six-byte gap was |
| `DEVSB` $09ea | ten bytes BELOW the four device records: the **four SB Pro mixer bytes** (255, 255, 255, FALSE, which is the image's `ff ff ff 00`), `OldDMAIrq` and `DMAPlacedInBuf`. `OldDMAIrq` had been declared AFTER the records, which put it past the end of the block. The release's seventh, `Old83`, is ABSENT and the arithmetic says so -- consistent with 1.31 having no `DMAPASData` |
| `DEVGUS` $0058 | `LastTick`, four unidentified bytes and `Busy` below `DevData`, moved up out of the implementation because their addresses are below it |
| `SONGUNIT` $03b8 | `TSong`'s VMT, then `ModOffset` -- which had been in VTGLOBAL -- then `SongLoaders` |
| `MODLOADER` $03cc | `DeltaSamples`, whose two bytes are the first of the block |
| `DEMOVT` $0000 | `Guard` is a typed constant; that is the only thing that can put it at $0002 |

### FOUR GLOBALS BELONG TO A UNIT THAT NEITHER OF THEIR DECLARERS WAS

Each was declared in two units at once, and the layout says both were wrong -- every one is inside SoundDevices' block, which runs $0b94..$0c0b unbroken:

    $0bc6  Rut_0bc6        was VTGLOBAL's
    $0bca  TickSnapshot    was PLAYMOD's and VTMAIN's
    $0bcc  TicksPerSecond  was PLAYMOD's and DEVGUS's -- and it holds 50, "50 = Europe"
    $0bd0  DriverTicks     was DEVGUS's `Ticks` and VTMAIN's `WordAtBD0`

`GusStarted` had to be renamed `UsingGUS` to go, because one address cannot carry two names and `UsingGUS` is the release's.

**AND THERE ARE GENUINELY TWO TICK COUNTERS.** `Ticks` at $0bc8 is the one VTSilenc advances and the one `12ba:0c52` gates the mixer on; `DriverTicks` at $0bd0 is the polled driver's, advanced by DevGus and cleared by `1000:02a8`. The gate is guarded by `IsDmaDevice`, so on a GUS -- polled, not DMA -- the mixer never reads $0bc8 and the two never have to agree.

### `CmdList` WAS THE LAST BYTE OF THE LAYOUT, AND THE SOURCE HAD PREDICTED IT

`GUS.PAS` carried `CmdList : array[0..255] of Byte` with a note saying the release has it as `buf : ARRAY[1..64] OF BYTE`, a LOCAL typed constant of `RestartChannels`, that 32 voices need only 64 bytes, and that **"nothing here is settled until the DGROUP layout is ... at 256 bytes this is a guess that will have to be revisited then."** All three parts of that were right.

`1723:08c8` is `MOV SI,06C2h`; $06c2 is the byte after `VolumeTable` ends, and HEAPS' first VMT is at $0702, so the array is bounded at 64 bytes -- two per voice for 32 voices. It is in the initialised region, so it is a typed constant; and declaring it LOCAL to `RestartChannels` is what places it after `VolumeTable`, because DGROUP follows declaration order.

**AND THE ASM READ `OFFSET CmdList+1`, WHICH ONLY REACHES $06c2 IF THE ARRAY STARTS INSIDE `VolumeTable`'s LAST BYTE.** With `array[1..64]` the `+1` comes off. Neither form was measurable before: `OFFSET` of a DGROUP symbol is a linker fixup, so the `.TPU` holds zeros either way.

**FINDING IT NEEDED AN ENCODING-AWARE SCAN, AND TWO NAIVE ONES LIED FIRST.** Searching the code for the address as a byte pattern returned dozens of hits in every segment. Filtering by ModRM form left exactly one, `19a0:02b0`, which looked like `DEC word [06e8]` and is really `PUSH -1 / PUSH CS / CALL` -- a false positive too. Scanning instead for `MOV r16,imm16` found one hit in the whole program and it was the answer. **A byte-pattern hit is a candidate, not a finding**: the third time this file records that rule, and the first time it cost two wrong leads in a row.

### TWO ONE-BYTE DATA ERRORS THE LAYOUT EXPOSED

Neither was findable before, because both sit in data that did not exist in the linked image until its block was laid out:

* **`VTSilenc.Driver.DMA` is TRUE.** $0033 is that record's +$15, which is `DMA`, and the original holds 01. It makes sense of the driver too: a device that produces no output and only paces the tick wants `12ba:0c52`'s gate active. DevGus's record has DMA FALSE at the same offset in both images, so the two are not copies of one default.
* **`NotePeriods[33]` is 254, not 255.** A transcription typo, one byte in a 168-byte table, and the standard ProTracker table agrees with the original.

### THE 88 BYTES THAT STILL DIFFER ARE ALL ONE THING

3,096 of 3,184 bytes are identical. **Every one of the 88 that are not is a SEGMENT byte exactly 7 paragraphs low** -- `cf` against `d6` for HEAPS, `91` against `98` for OBJECTS, and so on -- and 7 paragraphs is 112 bytes, which is exactly how much longer `DEMOVT`'s code still is than the original's. They are the one remaining code gap seen from the data side, and they close when it does. **Nothing else differs at all**: no run in the wrong place, no missing datum, no wrong value.

### *(superseded by the section above, kept for the reasoning)* — THE LADDER AT 848 DOWN TO 272

Five blocks are now byte-for-byte the right size: `DEMOVT`, `VTSILENC`, `DEVGUS`'s record, `VTCMD`, `VTCFG`, `PLAYMOD` and `MODCOMMANDS`. Every one of them was closed the same way — find the region's step, read the original's bytes there, and lay the release's DECLARATION ORDER into it. `verify.py` reported the whole tree unchanged after each, which is the only proof that moving a declaration moves no code.

**`VTGLOBAL` WAS THE BIGGEST SINGLE PIECE, 359 BYTES, AND IT WAS ENTIRELY MISSING.** Every one of its globals was a plain `var`, so none of its data existed. The original's block is simply there in the image, `DMA-SB-Mono` at `$0882` and `VT_Esp.Lng` at `$0948`, and the release declares almost the whole unit in `CONST` sections. Laying the release's order between the measured addresses closed on them three times over: `TDevID` is `String[20]` so `DevID` ends at `$0896` and — with the word-align — `StartupScr` starts at `$0898`; `ShellParam` at `$08c8` + 128 is `StringsFName` at `$0948`; + 80 is `ModPath` at `$0998`; + 80 is `NoBanner` at `$09e8`.

* **1.31's DEFAULT DEVICE IS THE SOUND BLASTER.** `DevID` holds `'DMA-SB-Mono'` where 1.39b has `GUSDevID`. That corroborates something this file already flagged from a completely different direction — `193a`/DevSB registers before `1084`/DevGus in the init chain, so the SB wins the first-to-register rule. **The note that said "a machine with both ends up on the GUS" is now contradicted twice.**
* **`VTDir` HAS A MEASURED ADDRESS AGAIN, `$083a`, AND IT IS A `DirStr`.** This document withdrew one — `VTCFG.PAS` had it at `DS:$09e8`, which turned out to be `NoBanner` — and changed the note to "no measured address". Working back from `DevPtr` at `$087e` puts it at `$083a`, and 68 bytes is what closes the gap where a `PathStr`'s 80 would overrun non-zero data.
* **AND `VTGLOBAL`'s LINK POSITION IS OBSERVABLE AFTER ALL.** It emits no segment, so `linkorder.py` and the map say nothing about it — but it emits DATA, and its block sits between `VTSHELL`'s and `DEVSB`'s. That moved it up `VTMAIN`'s clause, between `DevSB` and `VTShell`. **A declarations-only unit is not invisible; it is invisible to the wrong instrument.**

**NINE GLOBALS MOVED FROM `PLAYMOD` TO `MODCOMMANDS`, AND INTERLEAVED ADDRESSES ARE WHAT FOUND THEM.** `MyLoopMod` `$0334`, `TempoDiv` `$0336`, `TempoAccum` `$033a`, `RangeStart` `$033c`, `RangeEnd` `$033e`, `ReqStart` `$0342`, `ReqEnd` `$0344`, `ReqLen` `$0346` and `TickInRow` `$034e` were PlayMod's, and they interleave with `MySongLen` `$0340` and `FilterIsOn` `$0348`, which were already ModCommands'. Two units' blocks cannot interleave, so all nine belong to the unit PlayMod `uses`. The release then confirmed every one in its own `CONST` section, in exactly that address order, and **four of its initialisers are the original's bytes**: 125, 125, 6, 1 and 1. Sixteen declarations onto sixteen known addresses in one pass.

That is the **third** mechanism this project has used to settle a DGROUP owner, and they are independent: `142f`'s five moved because the CALL GRAPH forbade the other direction, `DEVGUS`'s three because the release named them, and these nine because the LAYOUT leaves no room.

**AND ONE WITHDRAWN CLAIM: THE RELEASE HAS TWO `FilterIsOn` VARIABLES TOO.** This file said "the release has exactly ONE variable of that name; 1.31 has two". It has one in `LIB/PLAYMOD.PAS`'s interface and one in `LIB/MODCOMMA.PAS`'s, at the same two positions ours are. So the duplication is not 1.31's invention. PlayMod's had to be EXPORTED, because `$02cd` sits between two interface globals and a unit's implementation declarations all come after its interface ones — nothing private can land there. The shadowing hazard the old note worried about is real and is now handled where it bites: `VTCFG` writes `$0348` and says so, `GetBool(ModCommands.FilterIsOn)`.

**`Pannings` WAS DECLARED AT ITS OWN BASE-1 BASE, WHICH IS A TRAP THIS FILE ALREADY DOCUMENTS.** It was `array[0..8] of Byte` with its address given as `$02e1` — and `$02e1` is not where it starts. It is the number the compiler subtracts so that `Pannings[Chan]` with `Chan` in 1..8 reaches `$02e2..$02e9`; the image proves it, because `$02e0` holds `03 70`, `MaxSplPerTick`, so `$02e1` is that Word's high byte. Declared `array[1..8]` at `$02e2` **the displacement is identical**, which is exactly why nine bytes where there are eight survived every byte comparison. Same mistake as `RawChannels`, where this document records "`$1384` IS THE BASE-1 BASE, NOT the array's address". It also had no initialiser: the eight pan positions are `$40 $b0 $b0 $40 $40 $b0 $b0 $40`, L R R L L R R L, the Amiga's own channel assignment — and 1.31 keeping pan in the PLAYER rather than the song is why `InitValues` in `14b9` has no trace of the release's `PanPositions := DefPan`, which this project had already found from the other end.

Two values differ from the release and both were read from the image, per the standing rule: `MaxOutputFreq` is **44000** where 1.39b has 45000, and `MaxSplPerTick` **agrees** at 880.

### THE BANNER WAS IN DGROUP, AND THAT IS WHY `DEMOVT` READ "SHORT"

`VTMAIN.PAS` declared `Banner : array[1..4] of String[61] = (...)`. A TYPED constant is initialised DGROUP data; an UNTYPED one is a literal Turbo Pascal lays down in the CODE segment. The original has the four strings in CODE at `1000:0000..00f7`, 248 bytes on a stride of 62, with `ShowBanner`'s own code starting at `00f8` — which is this project's own rule that a routine's literals precede it. Rewritten as four untyped constants with the four `WriteLn`s **unrolled**, and `ShowBanner` now begins at **exactly `0x00f8`**.

Four things agreed before a byte was changed, and the array form contradicted all of them: `1000:0000` is the strings, so `ShowBanner` cannot start at offset 0; the original's initialised DGROUP head is thirty bytes with no room for 248; `ShowBanner`'s prologue is `55 89 E5` with no `ENTER`, so the routine has **no local** and the `for I` the loop form needs is not there; and `1000:0111`, `0127`, `013d`, `0153` are `MOV DI,0000 / 003e / 007c / 00ba` as immediates with a `PUSH CS` each, where a loop would compute the address from an index.

Two smaller things fell out of the same dump. **Banner lines 1 and 4 had two `#196` too many** — 63 characters where the original's length byte says 61 — which no measurement had been able to see while the strings were in DGROUP. And **`SelfName` is a TYPED constant, `String[25]`**: `1000:0599` is `MOV DI,0004 / PUSH DS / PUSH DI`, and `PUSH DS` against `PUSH CS` is the standing test for where a constant lives, while the length follows from the neighbour — `VTSilenc`'s `Driver` is at `$001e`, so `SelfName` occupies `$0004..$001d`, which is 26 bytes.

**THE DIRECTION OF A GAP IS INFORMATION.** `DEMOVT` read 160 bytes short while 240 bytes of it sat in the wrong segment entirely; with the banner moved it reads 112 bytes LONG. A shortfall that is really a misplacement looks exactly like missing code, and only comparing the two segments' CONTENTS tells them apart.

---

## `00-map.md` WAS CORRUPTED AND HAS BEEN REPAIRED — and the cause is still unknown

Repaired 19 Aug 2026 (`3c313c0`). Recorded here because **the cause was never found, so another document could be damaged the same way.** If a doc in this tree suddenly reads as mostly blank lines, this is what happened and `v1.31b/repair_map.py` documents how it was undone.

Two independent corruptions, and separating them is what made the repair provable:

* **22 double-encoded characters** — 17 em dashes, two `ó`, two `á`, one `©` — each read as cp1252 and re-written as UTF-8. Every one reverses exactly. It is why some rows of the segment table showed a mangled dash and others did not.
* **A variable run of blank lines after every line** — 9,759 blank of 10,736. It *looks* like a uniform multiplication, because the head of the file is a clean 16 and 32, and **it is not**: table rows elsewhere sat 16, 5, 12, 7, 4, 9, 1 and 2 apart for what must all have been adjacency. No arithmetic inverts it.

What did work is narrower and worth remembering as a technique: **within a run of consecutive PROSE lines the padding is constant** — 70 of the 71 such runs have gaps that are exact multiples of the run's own minimum, quotient 1 to 3 — so `gap // m` recovers the original spacing there. Tables, fenced blocks and indented code need no multiplier at all, because markdown forbids a blank line inside a table and the rest read as one block. 340 gaps came from a clean multiplier, 616 from structure, and 21 lone prose adjacencies from punctuation, all 21 checked by hand.

**The repair is provable rather than tasteful**: all 978 non-blank lines identical in content and order, and all 39,773 non-whitespace characters identical, after the 22 character fixes. Only blank lines moved.

---

## WHERE THINGS LIVE — the tree moved, so check this before trusting a path

Everything used to sit under `D:\source\psycho`. It is now its own repository:

    D:\source\VangeliSTracker\        <- the git root; ROOT in every script
      .gitignore
      build/                          DOSBox mounts this as D:. Untracked.
      tools/
        (dosbox/vt131.conf)           ARCHIVED -- the build VM's config is generated now
        paslint.py                    build.py refuses to compile when this fails
        unlzexe.py                    unpacks NEUROSIS.008; how ref/ is made
      v1.31b/                         THE RECONSTRUCTION -- our work
        src/                          32 files: the Pascal and the two .ASM modules
        docs/                         this file; 00-map.md is the layout authority
        ref/vt1.31b.bin               the measurement target: the original, unpacked
        refpath.py                    the one place that knows where ref/ is
        *.py                          the measures; run them from THIS directory
      v1.39b/                         the VangeliSTracker 1.39b source release. Tracked.

Two habits that will save you. **Run every script from `v1.31b/`** — `cd v1.31b && python ../kit/tools/pascal/units.py units.toml` — because that directory is this reconstruction's host root: `kit.toml`, `build.toml`, the per-target configs and `build/` all sit in it, and `kit/tools/project.py` finds them by walking UP from the working directory. **This is the reverse of what this file said before 30 Aug 2026**, when the configs lived at the repository root and the scripts computed their root as their own grandparent; a command copied out of an older note will not run. And **mind what Git Bash does to an argument starting with a slash**: MSYS rewrites `/GS` into a Windows path and the build then silently compiles nothing, reporting `0 unit(s) compiled`. Prefix the command with `MSYS_NO_PATHCONV=1`, or run it from PowerShell. Two other traps in the same family cost time on 19 Aug 2026: a `\\` inside a quoted heredoc reaches Python as a single backslash, so build any escape you need with `chr(92)` rather than writing it literally; and `gh api` with a leading-slash path gets rewritten the same way, so call it from Python's `subprocess` or use `gh issue`/`gh label` subcommands instead.

The old psycho tree is still there and still holds the Psycho Neurosis demo work, which is a different job — see the last section of this file.

---

## What this is

`NEUROSIS.008` is **not** Asphyxia code. It is **DemoVT v1.31 (beta)**, "VangeliSTracker's version for demos", © 1992-93 VangeliSTeam (JCAB) — a third-party ProTracker player that Psycho Neurosis ships and shells out to. The user, an original author of the demo, asked for a full reverse of it anyway, then a line-by-line pass, then a byte-exact rebuild.

**The goal now is a byte-exact DemoVT v1.31 built from Turbo Pascal source.** Not "equivalent", not "same size" — the same bytes.

**THIS WORK IS NOW TRACKED, AND IT MOVED.** It used to live in `D:\source\psycho\demovt` and be excluded from source control pending a licence check. It is now its own repository at **`D:\source\VangeliSTracker`** — the user's decision — and essentially all of it is committed: our source, the docs, the measures, the harness, the 1.39b reference release, and **`v1.31b/ref/vt1.31b.bin`, the reference image itself.** Tracking the target alongside the measurements is deliberate: a checkout that cannot measure itself is not much use, and every figure in this file is a claim about that exact file.

The only thing ignored is **`build/`**, DOSBox's scratch area, all of which `build.py` regenerates.

**THIS TREE IS NOW SOURCE MATERIAL FOR A SECOND EFFORT, AND THAT EFFORT MUST NOT EDIT IT.** A reverse-engineering knowledge base is being built from what was learnt here; its map is [The Pascal RE knowledge base](https://github.com/sweetlilmre/PsychoNeurosis/issues/1). Its governing rule is **copy and adjust, never refactor the originals** -- the scripts and docs in this tree stay exactly as they are, and anything generic gets COPIED into the knowledge base and adapted there. So if a session arrives wanting to make `verify.py` or `build.py` generic, that is explicitly out of scope here. Refactoring these to consume the generic tier is a later, separate effort.

**`.gitattributes` disables line-ending conversion outright** rather than negotiating it. The sources are 1990s DOS files staged into a DOSBox build and `v1.39b/` is someone else's shipped archive; in a project whose entire premise is that the bytes match, git rewriting a CRLF is not a convenience. If you add a file type, add it there too.

**The reading pass is finished.** All thirty-one segments have been read line by line — every entry point the prologue scanner found, plus the frameless routines reachable by following calls. There is no outstanding *reading* work on DemoVT's own code. `1891` (`Objects`), `1b6f` (`Dos`) and `1ba1` (`System`) are Borland RTL, about 7.6 KB: identified, entry points named where DemoVT calls them, never in scope to reverse.

---

## THE HEADLINE: the compiler is TURBO PASCAL 6

This was the largest thing not known about the target, carried as risk 2 for several sessions. A TP6 install appeared beside the TP 7.01 one, at `C:\TP6` in the DOSBox HDD image, and the question answered itself in one build. **`build.py` uses TP6 by default; `--tp7` is there for comparison.**

| | TP 7.01 | TP 6.0 |
|---|---|---|
| byte-identical units | 1 | **2** |
| identical but for fixups | 10 | **10** |
| mismatched | 4 | **3** |
| `116a` FILEUTIL | 3 regions | **IDENTICAL** |
| `1a17` SOUNDDEV | 10 regions | **6** |
| `1b54` VTRESID | 24 regions | **21** |
| `1723` GUS | 3 regions | 3 regions |

Measured on the same sources the moment TP6 arrived, before anything was rewritten to suit it. `VTRESID` has since gone from those 21 regions to identical, which is a transcription fix rather than a compiler one, and `GUS`'s three have gone the same way — see the compiler probe. **Both were parked as compiler differences at the time this table was measured.**

**No unit got worse**, and every unit that agreed under TP7 agrees under TP6 with the same pending-fixup count to the byte. Two of the parked divergences — the `LES DI` reload in `116a` and the inlined value-`String` copy at `1a17:024c` — were long-standing, resisted every source rewrite, and closed on their own. `024c` had been recorded in advance as "the best single test of the compiler-identity question"; it was.

**NO divergence survives the compiler any more.** All three that used to sit here were **not compiler differences at all, and a compiler probe is what showed it.** `1723:04b5` was our own source shape; `1723`'s `Port[]` operand order does not reproduce and is withdrawn; and `1a17:070f`, the register allocation that was the strongest evidence of all, is four instructions of hand-written asm — `SUB BX,AX` is `29 C3`, which TP's inline assembler emits and its code generator does not. See "The compiler probe".

So there is now **no measured evidence that the original's compiler differs from this TP6 at all.** That is a stronger claim than the tree has ever supported, and it should be held loosely: 14 of 15 units agree, and the fifteenth's four remaining bytes are the ASSEMBLER, not the compiler — see below.

`188f`'s single unexplained byte turned out not to be a compiler difference at all: it is the `$G` switch. See "What actually causes a divergence".

**TP 6.01 has been tried and it is not the missing patch level.** `C:\TP61` in the HDD image is Turbo Pascal 6.01 (`TPC.EXE` 69,278 bytes, 11-Jun-1991) beside 6.0's 69,214 of 23-Oct-1990. `build.py --tp61` builds the whole tree with it and `verify.py` reports **the same units, the same region counts and the same offsets to the byte** as 6.0. The probe below is stronger still: for the same source the two emit *byte-identical code*. One of risk 2's three candidate explanations is therefore closed — whatever the original's toolchain was, the 6.0-to-6.01 patch level is not what separates it from ours.

---

## The three things you need

**EVERY COMMAND BELOW WAS REWRITTEN ON 28 Aug 2026.** The list used to name `v1.31b/` scripts; all of them are the kit's now, they take a config rather than baked-in paths, and several were renamed on the way. `K` below stands for `../kit/tools/pascal`, purely to keep these lines short -- **every command runs with `v1.31b/` as the working directory**, which is this reconstruction's host root.

    python $K/build.py build.toml                   compile every transcribed unit (TP6)
    python $K/build.py build.toml --compiler tp7    ...with TP 7.01 instead
    python $K/build.py build.toml --compiler tp61   ...with TP 6.01 instead
    python $K/build.py build.toml --sw=/$G-         ...with an extra compiler switch
    python $K/build.py build.toml --sw=/GS          write build/VTMAIN.MAP -- THE LINK MEASURE
    python $K/build.py build.toml --sw=/GD          ...a DETAILED map: adds publics by value

    python $K/units.py units.toml                       how each unit compares
    python $K/units.py units.toml --all --only GUS      EVERY divergent region (use this one)
    python $K/units.py units.toml --detail --only GUS   hex either side of the first divergence
    python $K/coverage.py link.toml units.toml          total coverage, computed not quoted

    python $K/mapcmp.py link.toml            our segment LENGTHS vs the original's
    python $K/linkorder.py link.toml         the link ORDER, and the uses edges it forbids
    python $K/dgroup.py link.toml            the initialised DGROUP image -- RISK 1
    python $K/linkcmp.py linked.toml         EVERY linked segment -- the VARIABLE half
    python $K/blockcmp.py blocks/1000.toml   one segment, block by block
    python $K/objcheck.py objmodules.toml    THE measure for a {$L} module -- strict, not the zero rule

    python $K/survey.py ...    the four cheap measurements on a NEW segment
    python $K/progseg.py ...   the program's per-unit entry-point table
    python $K/codegen.py ...   compile a probe unit with EVERY TPC and diff
    python relmatch.py         which RELEASE unit each segment pairs with, MEASURED

**Renames worth knowing, because the old name tells you nothing about where to look:** `verify.py` -> `units.py --all/--detail`; `asmcheck.py` -> `objcheck.py`; `census.py` -> `survey.py`; `probe.py` -> `codegen.py`; `progcmp.py` -> `progseg.py` and `blockcmp.py` between them; `blocks.py` and the four `blockXXXX.py` -> `blockcmp.py` with a per-segment config under `v1.31b/blocks/`. `omf.py` is **gone**, deleted along with the `verify.py` that was its only importer.

**The last group's arguments are NOT verified here** -- only the twelve commands above them were run on 28 Aug 2026. Every kit script answers `--help`; trust that over this list.

**`relbuild.py` AND `relmatch.py` BOTH RUN, as of 28 Aug 2026, and the second was unverified since #50 until then.** `relmatch.py` needs `build/vt` — a build of the 1.39b RELEASE tree — and nothing in this checkout produced one, so it had never been exercised against the kit's `align` module it was repointed onto. The blocker was NOT what its own comment claimed: the release sources are tracked right here, 107 files under `v1.39b/`. What was missing was the BUILDER, `tools/dosbox/vtbuild.py` — a path that resolved when this tree was `demovt/` inside the psycho checkout and that the split left behind. `v1.31b/relbuild.py` is that script adapted: sources from `v1.39b/` here, every machine path from `kit.local.toml` (the original hardcoded both the DOSBox-X executable and a TP7 `BIN` directory that is not where this machine's install lives), the `/U` unit path derived from `toolchain.tp7`, and the `install()` into psycho's `run/` dropped.

    python relbuild.py   3 program(s) OK, 0 failed, 21,266 lines, 49 .TPU
    python relmatch.py   then this

**RUN ORDER MATTERS AND NOTHING WARNS YOU.** The kit's `build.py` wipes its staging directory at the start of every run, and since #36 that wipe removes SUBDIRECTORIES too — `build/vt` is one. So a 1.31 build destroys the release build silently. Run `relbuild.py` after it.

**AND THE FIRST RUN CORROBORATED THE PAIRINGS, WHICH IS THE REAL RESULT.** Every pairing in this project was found by hand — a role match, a shared string, a record offset — and `relmatch.py` now reproduces all of them by measurement, independently: `12ba`/PLAYMOD, `1a17`/SOUNDDEV, `11bb`/VTCFG, `165a`/SONGELEM, `14b9`/SONGUNIT, `142f`/MODCOMMANDS, `116e`/CMDLINE, `1b24`/HARDWARE at 83.7%, `1642`/ASCIIZ at 100.0%. **Nothing was overturned.** Four segments top-rank against a release unit under a different name, and those are version renames rather than disagreements: `1b54`→VTSPECIA (our VTRESID), `1650`→SONGUTIL (VTNOTES), `1880`→UMBUNIT (VTDOSMEM), `1065`→DEVGUS at only 5.8% (VTSILENC). `1000`→VTSTRCON at 13.9% means nothing — `1000` is the PROGRAM and the release's program is `VT.PAS`. `14b7` and `188f` score nothing above 5%; both are 32 bytes, too small to window. And `relmatch.py`'s own caution held to the letter: `154d` scores 55.4% against MODLOADE and its bodies still do not transfer.

Note the release builds with **TP 7.01**, not the TP6 this project settles on for 1.31, because the release's own `TPC.CFG` is a TP7 configuration. That is right for a similarity RANKING and these `.TPU`s are not evidence about 1.31's toolchain.

**`--keep` is gone too** -- staging is wiped wholesale now, and `build.py --help` is the authority on what replaced it. python v1.31b/repair_map.py          the 00-map.md repair -- ALREADY APPLIED, refuses to re-run

**THE SEVEN MEASURES AND THEIR BLIND SPOTS ARE TABULATED AT THE TOP OF THIS FILE.** Read
that table before running any of them: each one is blind to something the next one catches,
and the order they can be used in is forced by which of them the others depend on.

**`/GD` PUBLISHES CODE SYMBOLS ONLY, NOT DGROUP ONES.** It is worth having — 363
publics by value, which locates every exported routine in the linked image — but a
variable is not a `PUBLIC` in a TP map, so it cannot answer a layout question. Use
`dgroup.py` for that: it reads the initialised DGROUP straight out of both EXEs.

**PER-BLOCK CHECKERS, one per segment that was built incrementally:**

    python v1.31b/block14b9.py   python v1.31b/block154d.py
    python v1.31b/block19a0.py   python v1.31b/block193a.py

**`verify.py`'s PREFIX CANNOT MEASURE A HALF-WRITTEN UNIT** — it stops at the first byte that disagrees, and while routines are still placeholders that byte is always the first of them, however much correct code sits below. The block checkers exist for exactly that: each searches for the shift that aligns a routine and counts only differences where OUR byte is non-zero. **Retargeting one at a new segment takes about two minutes** — copy, change `SEG`/`SEGLEN`/the unit name, and rewrite the `BLOCKS` table from `census.py`'s far returns.

Two traps they taught, both of which cost a wrong answer first:

* **A block must END where the next routine's LITERALS begin, not at its `ENTER`.** Turbo Pascal emits a routine's literals immediately before its code. Getting this wrong reads as a handful of real differences — it did in `154d` and again in `19a0`.
* **The search WINDOW is part of the measurement.** It has to cover the accumulated shortfall of every placeholder above the block, which for a half-written unit is most of the segment. Too narrow does not fail loudly; it returns the best shift it could reach and a plausible-looking difference count.

`C:\TASM410\BIN\TASM.EXE` (Turbo Assembler 4.1) is in the image and **the build drives it**: any `v1.31b/src/*.ASM` is assembled before the Pascal and its `.OBJ` left for a `{$L}` to find. `1a17` and `12ba` both link one. See the TASM module in `06-transcription.md`.

**`--keep` SUPPRESSES BOTH ERASURES AND EXISTS FOR ONE EXPERIMENT.** The `.TPU`s are deleted twice — once by `build.py` in Python and once by the generated `BUILD.BAT`'s own `del *.TPU` — and the first fix for this missed the second. The wipe is normally the point: a stale `.TPU` has produced a confidently wrong claim here twice. **Anything measured under `--keep` is suspect until a clean build agrees.**

**THE BUILD HAS A BOOTSTRAP PASS, and it is not optional.** `SongUnit`'s implementation names both loader units, whose interfaces use `SongUnit`. TP6 refuses that cycle from scratch (`Error 68`) and accepts it once the `.TPU`s exist, so `build.py` compiles `SongUnit` once with `/DBOOTSTRAP` — a conditional that removes the `uses` and the table's initialiser while leaving the INTERFACE unchanged — then the loaders, then `SongUnit` for real. It is emitted inside the per-unit loop, not at the top of the batch, because `SongUnit` needs `Heaps` and `SongElements` first.

**Building one unit only works for a leaf.** `build.py GUS` fails with `File not found (HARDWARE.TPU)` because it does not build dependencies, and it DELETES the stale `.TPU` on the way, so `verify.py` then reports the unit as missing. Just run the whole build; it takes a couple of seconds.

**`build.py` refuses to compile when the lint fails.** If you silence its output you will verify a stale `.TPU` and reach a wrong conclusion — this has happened twice. `units.py` compares the staged source against `v1.31b/src` and reports `STALE` rather than lying, but read the build output anyway.

**`build.py` shares `build/` with `tools/dosbox/dosbuild.py` and both wipe it on entry**, so they cannot run at the same time. Run one, read the result, then run the other.

**In Git Bash, quote `--sw`.** MSYS rewrites an argument that looks like a path, so `--sw=/$G-` reaches the script as `--sw=C:/Program Files/Git/$G-`. Write `'--sw=/$G-'`, or set `MSYS_NO_PATHCONV=1`.

### TP6 needs the source rewritten, and the build does it for you

TP6 has no `far` directive on a unit's exported routines at all — it rejects one on the interface declaration (error 73, `IMPLEMENTATION expected`) *and* on the implementation header of an already-declared routine (error 36, `BEGIN expected`). The calling model comes from `{$F}` at the point of declaration and nowhere else; TP7 relaxed that, and every unit here was written to TP7's rule.

`build.py`'s `tp6_dialect()` therefore rewrites the **staged** copy — `v1.31b/src` is untouched — turning the interface's `far` directives into an `{$F+}` region running from `interface` to `implementation`, where the unit's configured state resumes. That reproduces the TP7 shape exactly. **Whole-unit `{$F+}` would be wrong**: it promotes the private routines the interface never mentions.

Two details that cost time. The declaration has to be matched WHOLE rather than up to its first semicolon, because a parameter list separates its groups with semicolons too. And `verify.py`'s staleness check has to accept the rewritten form as well as the original, or a TP6 build reports the whole tree `STALE` and nothing can be measured.

### How to read `-a` without being fooled

It is trustworthy, but two of its habits have each cost a session:

* **A one- or two-byte region sitting next to a fixup is probably not real.** difflib has to put the boundary somewhere and around a four-byte run of zeros it often lands a byte or two off. Check positionally before believing a small region: compare the block at a fixed offset, allowing runs of up to four zeros, and see whether anything non-zero actually differs.
* **`ours N bytes` where all N are zero is a pending fixup however long N is**, if it lines up with the same number of original bytes. `regions()` knows this now, but any check you write by hand must too — the gain ladder's tables are 32-byte runs of zeros and they are correct.

The recipe that settles real questions, and which the tool does not do for you: take each contiguous transcribed block, SEARCH for the byte shift that minimises differences (never hardcode it — an edit anywhere earlier moves it), then compare positionally at that shift and count only the differences where OUR byte is non-zero.

---

## Getting at the binary

The shipped file is LZEXE 0.91 packed. Unpacking is already done and the output is tracked at **`v1.31b/ref/vt1.31b.bin`**, so a checkout already has it. To rebuild it from the shipped file anyway:

    python tools/unlzexe.py <NEUROSIS.008> v1.31b/ref/vt1.31b.bin

Every script resolves that path through **`v1.31b/refpath.py`**, which also honours a `VT_REFIMG` environment variable, so there is exactly one place to change if you keep the image elsewhere. It checks the size (58,176) and fails with a diagnosis rather than a traceback. See `v1.31b/ref/README.md`.

In Ghidra the program path is **`/NEUROSIS_008_unpacked.exe`** and the load base is **`0x1000`** — the Ghidra project predates the rename, so the name there is still the old one.

**Address conversion.** Ghidra prints every far target as `0x1000:XXXX`, which is a *linear* address of `0x10000 + XXXX`. To get the offset inside segment `S`:

    offset = 0x10000 + XXXX - S*16

The real segment is in the instruction bytes (`9A off off seg seg`) — always read it from there rather than trusting the printed `1000:`. Getting this wrong by one instruction was the dominant error class in the Psycho Neurosis work and the same applies here.

**But you do not need that formula to READ code.** `list_segments` shows a real segment per unit (`CODE_0` .. `CODE_30`), so `disassemble_bytes` accepts `165a:08e2` directly and labels every instruction with the correct `seg:ofs`. The formula is only needed to turn a printed far-call target back into a unit and offset.

**Two traps with `disassemble_bytes`:**

- `disassemble_function` and `create_function` fail on most of this image; `disassemble_bytes` with `restrict_to_execute_memory: false` works.
- It sometimes starts **one byte late** and produces convincing nonsense for the first few instructions before resynchronising. `165a:037a` and `154d:0000` both begin `C8 nn nn 00` (`ENTER`) and were printed as garbage. If the first instructions look wrong, decode the opening bytes by hand from `read_memory` and pick the listing up where it resynchronises.

**Finding routines.** Several segments do not begin on an instruction boundary, so disassembling at `:0000` desyncs. Use

    python v1.31b/scan_funcs.py [seg ...]

which scans for `55 89 E5`, `55 8B EC` and `C8 nn nn 00` prologues. 350 entry points found; the full list is in `02-functions.md`. Frameless routines (the mixing kernels, the chain stubs) do **not** appear and must be reached by following calls.

---

## Where things are

| file | what |
|---|---|
| `v1.31b/docs/CONTINUATION.md` | this file — the entry point |
| `v1.31b/docs/00-map.md` | all 31 segments, with the evidence for each identification |
| `v1.31b/docs/01-int2f.md` | the INT 2Fh interface — the part that bears on Psycho Neurosis |
| `v1.31b/docs/02-functions.md` | the 350-entry inventory and the prologue fingerprint |
| `v1.31b/docs/03-architecture.md` | layer diagram and overview |
| `v1.31b/docs/04-units.md` | per-unit contents from the line-by-line pass |
| `v1.31b/docs/06-transcription.md` | the byte-exact pass in detail: every divergence pattern, every parked difference, the release comparison |
| `v1.31b/src/*.PAS` | the transcribed units |
| `kit/tools/pascal/build.py`, `units.py` | compile, and compare against the original. **Both take a config** — `build.toml` and `units.toml` |
| `v1.31b/emit_gain.py` | the gain-ladder generator. `scan_funcs.py`, the prologue scanner beside it, is GONE — the kit's `prologue.py` is where that lives |
| `v1.31b/probe/PROBE.PAS` | the compiler probe: one routine per claimed compiler difference. Driven by `kit/tools/pascal/codegen.py`; the local `probe.py` is gone |
| `v1.31b/probe/ENCODING.ASM` | the assembler half — TASM against TP's inline asm, with the measured bytes in its header |
| `v1.31b/src/SOUNDDEV.ASM` | `1a17:0746..10c3` as the TASM module the original built it as |
| ~~`v1.31b/omf.py`~~ | GONE. It read an `.OBJ`'s FIXUPP records; deleted with `verify.py`, its only importer. `objcheck.py` reports the fixup breakdown now |
| `kit/tools/pascal/mapcmp.py` | linked segment LENGTHS against the original's, both on the same footing. Takes `v1.31b/link.toml` |
| `kit/tools/pascal/linkorder.py` | TP6's segment-order rule simulated, and every `uses` edge the original's order forbids. Takes `v1.31b/link.toml` |
| `kit/tools/pascal/dgroup.py` | the INITIALISED DGROUP image, block by block, plus the delta ladder. Takes `v1.31b/link.toml` |
| `kit/tools/pascal/progseg.py` | segment `1000`'s per-unit entry-point table. The per-routine shift search that `progcmp.py` did is `blockcmp.py` with `v1.31b/blocks/1000.toml` |
| `kit/tools/pascal/linkcmp.py` | ALL twenty-seven linked segments with fixups resolved — the VARIABLE half of DGROUP. Takes `v1.31b/linked.toml` |
| `kit/tools/pascal/blockcmp.py` | per-block verification of one segment, because a prefix cannot measure a half-written routine. **One config per segment**, and there are six: `v1.31b/blocks/{1000,12ba,14b9,154d,193a,19a0}.toml` |
| `kit/tools/pascal/objcheck.py` | the STRICT measure for a `{$L}` module — checks relocations against the `.OBJ`, where the zero rule cannot. Takes `v1.31b/objmodules.toml` |
| `kit/tools/pascal/survey.py` | **the four cheap scans, in one command — run it FIRST on any new segment.** Far returns (FRAMED ones, which are certain and are NOT a census -- the scan is anchored on a frame teardown, so a frameless routine ending in a bare RETF is invisible to it; survey reports a separate upper bound for those, and the cleanup counts on the framed ones are signatures), printable strings (an absence is evidence), far calls out (a missing call proves a missing routine), virtual call sites (the VMT layout, read off the code). It did nearly all of `165a` without a disassembler. Was `census.py` |
| `v1.31b/src/PLAYMOD.PAS`, `PLAYMOD.ASM` | `12ba`, COMPLETE — nineteen routines, the init section, and the object module |
| `v1.31b/src/MODCOMMA.PAS` | `142f`, COMPLETE — forty-three routines and the dispatch table |
| `v1.31b/src/VTCFG.PAS` | `11bb`, COMPLETE — twenty routines, essentially verbatim from the release |
| `v1.31b/src/HEAPS.PAS` | `17cf`, COMPLETE — forty-three routines, essentially verbatim from the release |
| `v1.31b/src/CMDLINE.PAS` | `116e`, COMPLETE — nine routines, and TWO MORE the original's linker dropped. Read the note at the bottom before moving them |
| `v1.31b/src/SONGELEM.PAS` | `165a`, COMPLETE — fifteen routines: instrument, track, pattern |
| `v1.31b/src/VTCMD.PAS` | `109c`, COMPLETE — twenty-two routines and the twenty-one-entry switch table |
| `v1.31b/src/VTGLOBAL.PAS` | NO SEGMENT, declarations only — the settings `11bb` and `109c` both write |
| `v1.31b/src/SOUNDBLA.PAS` | a declared STUB for `19a0` — its four port variables. **Start `19a0` here** |
| ~~`v1.31b/src/VTSONG.PAS`~~ | GONE, and the question it posed is ANSWERED: `SONGUNIT.PAS` is what grew into `14b9`, and it is complete |
| `v1.31b/src/SONGUNIT.PAS` | `14b9`, COMPLETE — the module object. Needs the `/DBOOTSTRAP` prepass; see `build.toml` |

`00-map.md` is authoritative on the segment layout. This, for orientation only:

```
1000  the program        banner, INT 1Ch hook, the INT 2Fh dispatcher at 024c
1b54  residency          the INT 2Fh server, JMP FAR chain stubs
11bb  config file        VT.CFG / @<name>.cfg, keys -> variables
109c  playlist           a TCollection walked entry by entry
116e  command line       PSP:$0080, tokeniser, 4-char keyword matcher
14b9  module object      constructor, header load, format id at [$59]
154d  ProTracker loader  signature at offset 1080, big-endian word swaps
164b  'JMPLAY' recogniser
165a  sample descriptors 28 bytes, volume clamped to 63
1642  ASCIIZ -> String   fixed width, space padded
142f  notes and effects  period -> note, effect nibbles, volume slide
1650  period->note table 2048 entries, built once
12ba  the mixer          8-way unrolled resampler, tempo engine, event ring
1544  the output filter  three first-order FIRs
1a17  the player core    driver list, buffer queue, start/stop, shared poll,
                         the mono/stereo downmix kernels at 0d7c/0dfc
17cf  memory pool        pointer normalisation, paragraph alignment
1880  DOS memory ($48/$49)      188f  DOS resize ($4A)
1b24  8259 masks, IRQ vectors, 16-bit DMA
1084 -> 1723   Gravis UltraSound
193a -> 19a0   Sound Blaster
1065           a UART on IRQ 4 / port $3F8, used purely as a clock
1caa           constants only, no code
1891 1b6f 1ba1 Borland RTL -- Objects, Dos, System. Not reconstructed.
```

---

## Where it stands

**SUPERSEDED BY "WHERE THIS STANDS TODAY" AT THE TOP OF THIS FILE, which is shorter and
current.** This section was written when the program had just started linking and lengths
were the only thing being compared; everything in it is still true and none of it is the
whole picture any more. Twenty-six of the twenty-seven linked segments are now
byte-identical, both halves of DGROUP are laid out, and five bytes in `PLAYMOD` are all
that is left. Kept for the reasoning.

**EVERY SEGMENT IS TRANSCRIBED AND THE PROGRAM LINKS.** Twenty-eight units compile, twenty-six reproduce their segment exactly, and the twenty-seventh — `1000`, the program — is a building Pascal source rather than a reading. Nothing is stubbed and nothing is blocked. `build/VTMAIN.EXE` is produced on every build; see "WHERE THIS STANDS TODAY" at the top for what that does and does not mean. `12ba` joined them and then `142f` did — the two largest segments after `1a17`. `GUS` joined them when the compiler probe showed its three "parked" regions were ours; `SOUNDDEV` joined when its frameless run moved to a TASM module. **And nothing is open inside what has been transcribed.** `116e`'s two empty overrides were the one loose end and `109c` explained them: Turbo Pascal smart-links per routine and nothing surviving refers to either. No parked divergence, no structural deviation, no unexplained byte.

    2 byte-identical, 24 identical but for fixups, 0 mismatched

That is a change of kind, not degree. Every "unfixable" thing this document has ever recorded turned out to be ours: five compiler differences, three structural deviations and a patch level, all withdrawn within two sessions of being tested rather than argued about.

**Read the region count, not the percentage.** The `%` in `units.py`'s summary is a PREFIX figure — how far in the FIRST divergence is — so a unit that is perfect except for one parked byte early on reports terribly. Use `units.py --all`.

    ASCIIZ    1642      144  IDENTICAL          (no fixups at all)
    FILEUTIL  116a       59  IDENTICAL          (closed by TP6)
    VTDOSRSZ  188f       29  identical, 2 pending fixups   (closed by {$G-})
    FILTERS   1544      144  identical, 6 pending fixups
    VTNOTES   1650      149  identical, 6 pending fixups
    VTCTRL    14b7       25  identical, 8 pending fixups
    UNKLOADE  164b       77  identical, 14 pending fixups
    VTDOSMEM  1880      237  identical, 20 pending fixups
    HARDWARE  1b24      765  identical, 36 pending fixups
    VTSHELL   1931      138  identical, 56 pending fixups
    VTRESID   1b54      432  identical, 87 pending fixups
    VTSILENC  1065      489  identical, 100 pending fixups
    DEVGUS    1084      376  identical, 106 pending fixups

    GUS       1723     2741  identical, 542 pending fixups   (closed by the probe)
    SOUNDDEV  1a17     4303  identical, 1024 pending fixups  (closed by TASM)
    PLAYMOD   12ba     5968  identical, 1187 pending fixups  (closed by TASM)

    MODCOMMA  142f     2176  identical, 99 pending fixups    (the dispatch table)

    VTCFG     11bb     4080  identical, 871 pending fixups   (the config reader)

    HEAPS     17cf     2832  identical, 363 pending fixups   (the memory pool)
    CMDLINE   116e     1232  identical, 158 pending fixups   (see the open question)
    SONGELEM  165a     3216  identical, 207 pending fixups   (instrument, track, pattern)
    VTCMD     109c     3296  identical, 484 pending fixups   (the switch table)

**`12ba` IS DONE, AND IT IS THE LARGEST SEGMENT IN THE PROGRAM.** 5,968 bytes, of
which 5,958 are code and ten are padding; nineteen Pascal routines, the unit's
initialisation section, and a `{$L}` object module holding two resampling kernels
and the single entry that chooses between them. It took the same two instruments
`1a17` did — the release for shapes, TASM for the frameless run — plus one new
one, `asmcheck.py`, because neither `verify.py` nor `blocks.py` can measure an
assembled module honestly.

**`1a17` IS DONE, and it took an assembler.** `0746..10c3` was never compiled from Pascal: it is an external TASM module, as the 1.39b release still builds this same unit. It is now `v1.31b/src/SOUNDDEV.ASM`, assembled by `C:\TASM410\BIN\TASM.EXE` and linked with `{$L SOUNDDEV.OBJ}`, and **all 2,430 of its bytes agree with the original** — every remaining difference is a relocation the assembler recorded, checked field by field. The four "structural" bytes are gone. Full write-up in `06-transcription.md`.

**`1723` CLOSED, and it was not finished after all.** It had been written up here as "3 regions, ALL PARKED -- nothing to fix from source". All three were in `ProbeUltrasound` and all three were ours; the compiler probe found them in one build. See "The compiler probe".

**`1a17` is byte-exact.** Six regions became four bytes when the compiler probe found two of them to be hand-written asm and one a `JMP` the procedure never needed; the four became none when the frameless run moved to the assembler module it was always built as. `1a17` is the big one: 4261 of its 4303 bytes compare with **zero real mismatches** and 847 pending fixups. Its six regions are two parked compiler differences (`0710`/`0716`) and eight structural bytes in four places (`0746`, `1007`, `104d`, `10c1`) where wrapping a frameless run in Pascal procedures forces an entry or an exit the original has not got. The full table is in `06-transcription.md`.

~~Eleven segments are not transcribed at all; `VTMAIN` is written but blocked on seven of them.~~ **LONG SUPERSEDED — every segment is transcribed and `VTMAIN` is byte-identical.** Kept because `06-transcription.md` still has the inventory this sentence pointed at.

### The compiler probe — it closed `GUS`, closed `1a17:070f`, and named the last four bytes

`v1.31b/probe/PROBE.PAS` holds one routine per divergence that had survived both recorded compilers, written to the shape the tree already had, with the original's bytes quoted above each one. `python v1.31b/probe.py` compiles it with every installed TPC and diffs the compiled code. **It is the cheapest instrument in this project** — one build, a few seconds, and it answers "does this construct compile to those bytes?" without the 10 KB of context a unit carries.

It was written to test TP 6.01 and it did that (byte-identical to 6.0, above). What it actually found was that **all three parked divergences were never the compiler**, and then what the four bytes left in `1a17` really are.

**1. `if C then goto L` is NOT folded — and `1723:04b5` was our own source.** The probe's `ProbeGotoFold` compiles under TP6 to `CMP / 74 02 / EB 06`: the original's `JZ +2 / JMP` exactly, un-folded. The claim in the handover was that both compilers fold it and no source shape reaches it. What was actually in `GUS.PAS` was a nested `if ... then begin ... end` — the note said the transcription used the release's `LABEL`/`GOTO` and it did not. Written as the release has it,

    if (GetGusRegister16($02) and $1FFF) <> $16D8 then goto Fin;
    SetGusVoice(1);
    if (GetGusRegister16($02) and $1FFF) <> $0F83 then goto Fin;
    ProbeUltrasound := True;
    Fin:

both branches match and the third region falls out with them. **The doc asserted a source shape that the source did not have**, and the assertion was believed for several sessions because the divergence next to it was real. When a note says "confirmed against the release", check the file still says what the note says it says.

**2. `ProbeUltrasound := ProbeUltrasound;` compiles to a RECURSIVE CALL.** The trailing self-assignment emitted `CALL / MOV [BP-1],AL` where the original has `STI / MOV AL,[BP-1] / LEAVE`. Turbo Pascal reads the function identifier on the RIGHT of an assignment as a CALL, not as the result variable — that is the same rule that makes assigning to the identifier work, seen from the other side. Deleted, and it was worth six bytes of the region at `+04eb`. **Nothing in Pascal reads a function's own result back**; if you want that, use a local, and then you are back to the frame problem.

**3. `1a17:070f` IS HAND-WRITTEN ASM, and that was the strongest divergence in the tree.** `SUB BX,AX` assembles to `29 C3` in TP's INLINE ASSEMBLER and to `2B D8` in TASM; TP's CODE GENERATOR emits neither, because it insists on AX as the accumulator and produces `MOV DX,AX / MOV AX,mem / SUB AX,DX`. The original has `29 C3`. So `Left := DMABufferSize - GetDMACount` was never compiled from that statement — the four instructions are hand-written, continuing the dead `MUL DX / PUSH AX` block that sits immediately above them and was already transcribed as `asm`. Moved into that block verbatim, `0710` and `0716` both closed. **A divergence held for several sessions as a property of a code generator was three lines of assembler nobody had recognised.**

**4. The probe then identified the FOUR BYTES LEFT IN `1a17` as an external TASM module** — the epilogue turns out to be unsuppressable in every arrangement, and the run's encodings are TASM's throughout. That is the section above.

**5. `1723`'s `Port[]` operand order is WITHDRAWN.** The probe emits `MOV AL,0B / MOV DX,[GUSPort] / OUT` in all three contexts — after nothing, after an `OUT`, after a `CALL` — so there is no scheduling effect to reproduce, and `GUS` now compares clean across both `02f4` and `03c4` anyway. Whatever the earlier measurement was, it does not survive re-running. (Mistake pattern: **re-run a cheap test rather than trusting a note about it.**)

### `12ba`'s LAST 707 BYTES WERE AN OBJECT MODULE, AND IT WENT IN ON THE FIRST ASSEMBLY

`v1.31b/src/PLAYMOD.ASM` is now the real thing rather than a stub: `148f..1745`,
three routines, and `python v1.31b/build.py` produced **5,958 bytes of code where
the original has 5,958**, with all eighteen relocations correct, first time. The
transcription took one reading pass because the release's `LIB/PLAYMOD.ASM` is the
same code — but it is NOT the same source, and the differences are the interesting
part.

**How the boundary was found, and it is a one-instruction test.** Turbo Pascal
emits a unit's `BEGIN ... END.` block as the LAST Pascal code in the segment. That
block is at `141e..148e`, so everything after it came from the `{$L}`. The first
instruction confirms it without any inference: `148f` is
`2E 89 16 E3 14`, `MOV WORD PTR CS:[14E3],DX` — a store into the code segment,
patching an immediate inside this same module. No Pascal statement produces that.

**And ONE PAIR OF INSTRUCTIONS DATES THE TOOL CHANGE ACROSS THE BOUNDARY:**

    12ba:1320   31 C0   XOR AX,AX     <- compiled Pascal, inside PlayStart
    12ba:169d   33 C0   XOR AX,AX     <- the object module

Same instruction, same segment, two encodings, because two tools emitted them.
`AND CH,CH` is `22 ED` in the module and `SUB AX,CX` is `2B C1` — both the forms
Turbo Pascal's own inline assembler does not choose. That is the encoding table in
`06-transcription.md` used as a POSITIVE test for once, rather than as a trap.

**THE ELEVEN RUNS OF NOPs ARE THE ORIGINAL ASSEMBLER'S `JUMPS` PADDING.** Every
one sits immediately after a jump: 3 NOPs after a `Jcc` (five reserved, two used),
1 after a `JMP` (three reserved, two used), 2 after `MOV AH,<forward equate>`. The
evidence is that **every padded jump is a FORWARD reference and every unpadded one
is not** — the three backward jumps closing the two unrolled loops and returning
to `@@nomues` carry no padding at all, and the two forward jumps that are also
unpadded are exactly the two the release writes with an explicit `SHORT`, which
suppresses `JUMPS`. Four independent cases, all consistent.

They are written out as explicit `NOP`s rather than left to this TASM's own
`JUMPS` handling, for the same reason `SOUNDDEV.ASM` writes some instructions as
`DB`: our TASM is a 4.1 from 1996 and its padding decisions are no more the
author's than TP 7.01's codegen was. Explicit NOPs are byte-exact by construction
and the mechanism is recorded rather than relied on. **This is the first time a
NOP in this project has had an explanation**, and it is worth carrying: a run of
NOPs after a jump in hand-written asm is an assembler artefact, not dead code and
not padding for alignment.

**WHERE 1.31 AND 1.39b ACTUALLY DIVERGE**, all of it measured:

* **`EmptyRaw` is 8-way here and 16-way in the release**, and 1.31's advances the
  source position INSIDE the loop where 1.39b pre-computes the whole advance with
  a `MUL` before it. `ADD AX,7 / SHR AX,3` against `ADD AX,15 / SHR AX,4` is the
  byte that fixes the eight. 1.31's kernel is `DumpRaw` with the sample fetch and
  the volume multiply removed — eleven bytes per sample against fifteen — which is
  the earlier and simpler design.
* **`EmptyRaw` also does `PUSH ES / POP DS`**, which the release does not, and it
  ends its computed jump with `PUSH AX / XOR AX,AX / RET` where 1.39b uses
  `MOV DX,AX / XOR AX,AX / JMP DX`. A push-and-return computed jump, one byte
  shorter.
* **ONE Pascal entry, not two.** 1.39b exports `DumpInstrument` and `DumpEmpty` as
  separate `PROC`s sharing their bodies through an internal label; 1.31 takes a
  `Silent : Boolean` as an eighth argument and chooses at `1675`. The handover had
  this as "one with a Boolean argument in 1.31" and it is now confirmed from the
  frame: `RET 22` and a reference to `[BP+04]` fix a NEAR return with 22 bytes of
  parameters running `[BP+04]..[BP+19]`.
* **`ENTER 0,0`, hand-written.** TASM's `PROC PASCAL NEAR` emits
  `PUSH BP / MOV BP,SP`; the original has `C8 00 00 00`. So the module does not use
  `PROC` at all, which is also why bare `PUBLIC` labels are the right shape — the
  same conclusion `SOUNDDEV.ASM` reached.
* **`MUL WORD PTR [BP+0Dh]` at `161f` reads ACROSS TWO PARAMETERS.** `0Dh` is not
  the start of anything: it straddles `Step`'s bytes 1 and 2, taking
  `(Step SHR 8) AND 0FFFFh` in one instruction. The same trick is at `16c9`. It is
  not expressible in Pascal, and it is a second independent reason this run was
  never compiled.

### `142f` FOUND A TABLE THE TREE HAD MISREAD FOR ITS WHOLE LIFE

The first routine of `142f` reads `DS:$0414`, and nothing in the tree declared it.
Chasing that turned up something better than a missing declaration.

**`DS:$04bc` IS NOT A PERIOD TABLE. IT IS THE SEARCH THRESHOLDS.** `VTNOTES` had it
as `Periods_`, an uninitialised `array[0..6] of TPeriodRow`, which never explained
why the program would hold two period tables 168 bytes apart. Read out of the
binary, the relation is exact:

    NoteBounds[i] = round(sqrt(NotePeriods[i] * NotePeriods[i+1]))

the GEOMETRIC MIDPOINT between adjacent semitones — **83 of 83 pairs, no
exceptions**. `sqrt(1712*1616)` is 1663.3 and the entry is 1664; `sqrt(1616*1525)`
is 1570.0 and the entry is 1570.

**And that is exactly what `1650`'s search needs.** `1650:0052` compares the period
being looked up against this table and takes the first entry it does not exceed, so
the answer is the NEAREST semitone rather than the next one down — and the midpoint
must be geometric because pitch is logarithmic. A table of periods there would
round the wrong way for every input in the upper half of every semitone. The
reading pass had the mechanism right and the table's identity wrong.

So the two tables are one table's values and the same table's boundaries, adjacent
in DGROUP, each indexed the way its own consumer wants: **flat by `142f`**
(`MOV AX,[DI+0414]`, DI = note*2) and **by octave row by `1650`**
(`IMUL DI,Oct,$18`). Which is why `NoteBounds` keeps its 2-D shape — a flat
declaration would lose that `IMUL`.

**BOTH TABLES NOW HOLD THEIR REAL DATA, and neither did before.** They were
declared as uninitialised `var`s, so `BuildNoteTable` was reading zeros — a
functional gap the byte comparison could never see, because initialised DGROUP data
is not in a `.TPU`'s code. Transcribed from `1caa:0414` and `1caa:04bc` rather than
computed, per the standing rule. `VTNOTES` still verifies identical with the same
six pending fixups: 168 bytes of data changed no code.

`NoteOf` and `NotePeriods` are now exported, because `142f` reads both.

### THE PORTAMENTO STEP IS UNSCALED IN 1.31 — AND ONLY THE PORTAMENTO STEP

`StartTPortUp` stores its parameter unscaled where the release has
`WORD(n.Parameter) SHL 2`; `StartNPortamento` reads `PeriodIncr` without the
release's `SHR 2` and writes it without the `SHL 2`. Two routines, four places, no
shift in any of them — `142f:00d9` is `MOV AL,[DI+5] / XOR AH,AH / MOV [DI+1f],AX`
with nothing between the load and the store. **The same pattern data slides four
times faster in 1.31.**

**IT IS NOT A CHANGE OF UNITS ACROSS THE WHOLE UNIT, though, and the tidier story
was wrong.** `StartVibrato` keeps the release's `SHL 2` on its depth at `02dd`, so
1.31 counts quarter-periods there and whole periods in the portamentos. This was
written up here as "1.31 works in whole periods and 1.39b in quarters" after two
routines agreed; the third disagreed. **Two instances is a pattern and not a rule.**

`StartArpeggio` differs the same way and for the same reason — it is the earlier
design. 1.39b computes `f SHL 14 DIV ArpTable[semitones]`, which works for any
tuning; 1.31 goes period → note → note plus semitones → period through the two
tables above, which only works on the twelve-tone table.

### DEMOVT STOLE PROTRACKER'S NO-OP EFFECT FOR ITS MUSIC-TO-DEMO SYNC

`142f:0622` is the one routine in the segment with no counterpart in the release, and
it is the most interesting thing in it. Two stores:

    Can.RingChan := N.Parameter;      Can.RingNote := 1;

and `12ba` does the rest — `12ba:0a58..0a8d` copies both into
`NoteRing[EventSlot, chan]` and clears `RingNote` again, and `12ba:0187` tallies the
ring into the control block the INT 2Fh interface publishes. So `RingNote` means "an
event is waiting" and `RingChan` is its payload. **This is how a tune signals the
demo**, which is the one thing a demo player needs and a tracker does not.

**AND THE COMMAND IT IMPLEMENTS IS `mcNPI1` — ProTracker's effect `8xx`, the one that
does nothing.** CommandStart's last case arm dispatches command 9 (our `mcNPI1`) to
it, and the release's comment for that value reads *"8 xx  Do Nothing (as far as I
know)"*. 1.39b has no Start routine for it at all. So DemoVT took the single
ProTracker command a composer can write with no audible consequence — costs nothing
to repurpose, and any tracker can author it — and made it the synchronisation
channel. **Its case arm is also LAST in the chain** where the other sixteen run in
the release's own order, which is what an arm added to an existing `case` looks like.

It is named `StartRingEvent` for its role. The release's `mcNPI1` supplies the
COMMAND's name and would be a terrible name for a routine that does something.

**IT IS NOT `StartRetrigNote`, which its position suggests and which I concluded for
one iteration.** The release's StartRetrigNote has one CONDITIONAL store; this has
two unconditional ones, the release's TickRetrigNote needs three fields where 1.31's
record has two, and the dispatch table points `mcRetrigNote` at a do-nothing tick.
Three independent contradictions, and the position was the only thing in favour.

### `142f` MOVED THE SEQUENCER STATE OUT OF PLAYMOD, AND THE CALL GRAPH DECIDED IT

`142f:03ed` reads `DS:$034c`, `$0340` and `$034a`, and all three were declared in
`PLAYMOD.PAS`. That could not stand: PlayMod `uses` ModCommands, so ModCommands
cannot use PlayMod, and the effect routines write the sequencer's position directly.
The release resolves it the same way — `LIB/MODCOMMA.PAS` declares `NextNote`,
`NextSeq` and `MySongLen` in its own interface, with the comment *"Values set from
outside this UNIT ... They both must have been set BEFORE calling this UNIT."*

**This is the first DGROUP ownership question in the project settled by a STRUCTURAL
reason rather than by an address.** Compare `DEVGUS`, where three globals sat in the
wrong unit and nothing could see it; here the compiler simply refuses. Five globals
moved, with the release's names where they were worth taking:

    NextSeq    $034c   was PlayPos     NextNote  $034a   was PlayRow
    MySongLen  $0340   was OrderLen    CurSpeed  $0349   the release's `Tempo`
                                       CurTempo  $0338   ... `BPMIncrement`

**`PLAYMOD` still verifies identical with the same 1,187 pending fixups** after the
move and 37 renames, which is the only proof that a rename moved nothing.

**ONE RENAME IS DECLINED ON PURPOSE and it is the first in the tree.** The release's
`Tempo` is also a FIELD of `TPlayingNote`, which PlayMod reads eleven times as
`NoteProcessed^.Tempo`. A global of that name is legal but makes all eleven lines
ambiguous to a reader, and a word-boundary rename cannot tell `Tempo` from `.Tempo`
without hand-checking each. `CurSpeed`/`CurTempo` also say what they hold, which
`BPMIncrement` does not. **Adopting the release's names is a standing rule, not an
absolute one** — recorded here rather than done.

### TWO `FilterIsOn` VARIABLES, AND ONE OF THEM WOULD HAVE SHADOWED THE OTHER

`142f:04da` writes `DS:$0348` and PlayMod's `FilterIsOn` is at `DS:$02cd`, next to
`FilterOn` and `FilterOff`. The release has exactly ONE variable of that name;
**1.31 has two**, and nothing in the transcribed tree reads `$0348` at all — the
same shape as `LoopMod` at `$02c8`, written once and never read.

So ModCommands keeps its copy in its **implementation** section rather than its
interface. Exporting it would put a second `FilterIsOn` in scope wherever PlayMod is
compiled, and Pascal would silently bind every reference there to PlayMod's own.
**That is a shadowing bug no byte comparison could ever see**, and declining to
export is the least-claim fix. Whether 1.31 meant one variable and ended up with two
is not something the bytes can answer.

### AND 1.31 HAS NO RETRIGGER COMMAND, WHICH EXPLAINS `TCanal`'s TAIL

The release's order puts `StartRetrigNote` and `TickRetrigNote` just before the fine
volume slides. 1.31 goes straight to them: `142f:0584` is `StartVolFineUp`. So the
retrigger command is absent from this version, and with no retrigger routine there
is nothing for the release's `RetrigCt`/`RetrigVal` at `+$24`/`+$25` to hold — which
is exactly why `12ba` is free to use those two bytes as the note ring's `Chan` and
`Note`. The record's tail has been described as "does not carry over" since the
reading pass; **this is why**, and it is now a fact rather than a caution.

### What `142f` is teaching about the two assemblers

* **A FORWARD JUMP IN TURBO PASCAL'S INLINE ASSEMBLER TAKES THE LONG FORM AND IS
  NOT PADDED.** `142f:0352` is `E9 78 00`, a three-byte near jump reaching `03cd` —
  a displacement of `$78`, which fits a short jump twice over. `TickVolSlide` is
  declared `forward`, so the assembler does not yet know the distance and reserves
  three bytes; unlike TASM's `JUMPS` it then simply moves on rather than filling the
  slack with `NOP`s. **So the same cause produces padding in `12ba`'s object module
  and none here**, and the two must not be confused: NOPs after a jump mean TASM,
  a needlessly long jump means TP's inline assembler.
* **A LONG JUMP MEANS ONE OF TWO UNRELATED THINGS — DO NOT READ IT AS EVIDENCE.**
  `142f:0352` is a three-byte `E9` reaching a target 120 bytes away, well inside
  short range, because `TickVolSlide` was a FORWARD reference. `142f:0619` is also a
  three-byte `E9`, to the same routine, because by then it is 591 bytes BEHIND and a
  short jump cannot reach. Same encoding, opposite causes.
* **`XLAT` FIXES WHERE A TABLE LIVES.** `142f:031b` is `MOV BX,0350` followed by
  `XLAT`, which reads `DS:BX+AL` — so `$0350` is a DGROUP offset even though the
  same number is a valid code address in this segment (it is the middle of
  `TickT_VSlide`). A `const` declared inside a procedure is where Turbo Pascal puts
  such a table, and it is where the release declares this one.

### Two small compiler facts, both measured rather than reasoned

* **Turbo Pascal evaluates the RIGHT operand of a 32-bit add FIRST.** `142f:003f`
  sign-extends the semitone count into CX:BX before touching either table, so in
  `NotePeriods[(NoteOf[Period] and $FF) + Semis]` the semitone count is the
  right-hand operand. Written the other way round the two halves swap and nothing
  else changes — which is why it cost a build to find and why the prefix stopped at
  `+0040` until it was swapped.
* **`OR AX,AX` as `09 C0` IS NOT A HAND-ASM TELL ON ITS OWN.** `142f:0206` is
  compiled Pascal — the release writes that statement as
  `IF INTEGER(can.PeriodDest - can.Period) >= 0`, and the explicit `Integer` cast is
  what makes the compiler test the LOW WORD of a 32-bit difference with
  `OR AX,AX / JL`. The encoding table in `06-transcription.md` lists `09 C0` beside
  `21 C9` and `20 C0` as inline-assembler forms; the two `AND`s hold, the `OR` does
  not. Use the `AND` direction bits for that judgement, not the `OR`.

### `asmcheck.py` — because BOTH existing tools are too kind to an object module

`verify.py` and `blocks.py` excuse a byte when OUR side is zero. That is exactly
right for a `.TPU`, where Turbo Pascal emits an unresolved reference as zeros, and
exactly wrong for an assembled module: **TASM writes the offset RELATIVE TO THE
MODULE and leaves the linker to add the base**, so every code self-reference
differs from the original by exactly the module base, in bytes that are not zero.

`12ba` shows both failure directions at once. Of its eighteen relocation fields,
the nine in `DumpRaw` have a zero high byte and read as ONE difference each, and
the nine in `EmptyRaw` have a high byte of `01` and read as TWO. Twenty-seven
"differences" for thirty-six relocation bytes, and not one of them is a defect.

    python v1.31b/asmcheck.py           both modules
    python v1.31b/asmcheck.py PLAYMOD   one of them

It asks the two questions that settle it: does every CODE self-reference hold
exactly ours plus the base, and does every differing byte lie INSIDE a relocation
field. It is STRICTER than the heuristic — it will not excuse a wrong byte for
being zero — and it sorts every field into one of three buckets:

    PLAYMOD   12ba   18 field(s):  18 self-ref,   0 pending,  0 symbol+addend  OK
    SOUNDDEV  1a17  139 field(s):  59 self-ref,  73 pending,  7 symbol+addend  OK

**And running it on `SOUNDDEV` recovered something the doc had recorded and lost.**
The seven `symbol+addend` fields are `OFFSET <something> + 2,4,..,14`; our side
holds the addend alone, so the implied symbol is `orig - ours`, and all seven imply
**the same offset, `0bd2`** — which `SOUNDDEV.PAS` already documents as "eight
per-channel volumes". The tool prints that grouping, so a DGROUP reference that no
byte comparison can settle can at least be read off and checked by hand. That is
risk 1 made visible for the first time.

### `VTRESID` closed on two mistakes, and both are patterns

21 regions, the one unit with no counterpart in `LIB/` to copy shapes from, and the handover predicted it would be "slower per byte than anything in `1a17`". It took two fixes. Both are worth carrying:

**1. An invented `String` local, spotted from the SHAPE of the divergence.** Eleven of the 21 regions were single bytes between `+00c5` and `+00f5` at a four-byte spacing. That pattern — isolated single bytes at a regular stride — is the high byte of a `[BP-nnnn]` displacement, and here every one was off by exactly `$01`, so the whole frame was 256 bytes deeper than the original's. `Install` declared an `S : String` and opened with `S := Name`.

The frame is `ENTER 0206,0` and the declared locals only account for `$106` of it, which is what the `S` had been invented to explain. **The other 256 bytes are a compiler temporary**: the string that `WriteLn(A + B + C)` concatenates into. Two things told them apart. `Name` is a value `String` parameter, so the compiler already copies it to `[BP-$100]` on entry and a second copy into a local would be visible — there is none, `1b54:009a` goes straight to the `INT 2Fh`. And `1b54:0137` copies `[BP-$100]`, the parameter's own slot, into `SelfName`, so the statement is `SelfName := Name` with nothing between.

**A frame larger than the locals explain is a temporary before it is a missing variable**, and a String-sized one means a concatenation or a function returning a string. Same trap as `164b`'s two invented `String` locals — three units now where inventing storage to explain a frame was the error.

**2. Three `Write`s and a `WriteLn` where the original has ONE `WriteLn`.** `WriteLn(A + B + C)` pushes `Output` once and builds the line in that temporary — copy, append, append, write, break. Three separate `Write`s emit three push-and-call groups and no temporary at all. Different shape, different frame, ten regions.

**And the constants are pushed from CS, which is how you know they are literals.** `1b54:00f7` is `MOV DI,0061 / PUSH CS / PUSH DI`: the two strings live at `1b54:0061` and `1b54:007b`, inside the CODE segment, in the gap between `ExitHandler` and `Install`. An untyped Pascal string constant is a literal and Turbo Pascal lays a literal down in the code segment; a TYPED constant lives in DGROUP and gets `PUSH DS`. So `PUSH CS` against `PUSH DS` reads the constant's declaration straight off the binary. (`NoName` is typed and DS-relative precisely because `Install` takes its address.)

Also fixed: four `XOR SI,SI` that the binary has as `MOV SI,0000`. Same value, three bytes against two, and the verbatim rule exists for exactly this.

---

## The method that works

1. **Find the routine in `v1.39b/LIB/` and read it FIRST.** The 1.39b release is a later version of the same codebase. Reading `GUS.PAS` once gave, in a single pass, what byte-chasing had been extracting one divergence at a time — which routines are `ASSEMBLER`, which loops are `FOR`, where the `LABEL`/`GOTO`s are, the real parameter lists.
2. Rewrite the routine to that shape.
3. Compile and run `verify.py -a`.
4. Only then chase what is left, against the disassembly.

**The release is corroboration, never truth.** Where they disagree the disassembly wins. Three concrete cases: `ChangeVol`'s volume table differs in every entry but the first between 1.31 and 1.39b; 1.39b's GUS driver points its `TimerHandler` at the core's shared handler where 1.31 points at its own; and 1.39b's `TSong` was remodelled in February 1993 and its field layout does not fit 1.31's offsets. **The release settles SHAPES and NAMES. It is worth nothing for DATA.**

### The release also BUILDS, and its map has been diffed

    python tools/dosbox/vtbuild.py          compile VT, SHELLVT and MAKESTR
    python tools/dosbox/vtbuild.py VT.PAS   one program

It compiles clean with the same TP 7.01 install — 21,266 lines, 108,208 bytes of code, no errors — and installs `VT.EXE`, `SHELLVT.EXE` and the release's `.CFG`/`.LNG`/`.VTO` data into `run/`, so `run.bat` then `VT` at the `E:` prompt gives a running tracker to compare behaviour against.

The release ships the `VT.MAP` from the author's own build, so it can be compared with ours segment by segment with the sources held constant — **every difference is the toolchain, not the code.** Full write-up in `06-transcription.md`; the short version:

* 57 segments, 21 identical in length, 27 differing, ours smaller in 21 of those and by 1,114 bytes overall.
* **`SYSTEM` (`13CA` shipped, `141A` ours) and `DOS` differ.** Those are RTL segments compiled from no source in the tree, so their sizes fingerprint the runtime library: this TP 7.01's RTL is not the one the author linked. `OBJECTS` differs by 74 bytes and is Turbo Vision's, from whatever `TVISION` the author's `/U` pointed at.
* **`MAKESTR.EXE` is shipped with its source** — the only author-built binary in the release. Unpacked and compared with relocation words blanked, its own code segment is `011A` bytes in both and **instruction-for-instruction identical**; all 34 differing bytes are link-time values plus one VMT offset (`CALL FAR [DI+24]` against `[DI+28]`) that is the `OBJECTS` difference showing through.

So for 1.39b's own code TP 7.01 reproduces the author's codegen and the libraries differ. **Do not carry that back to 1.31**, whose own byte comparison says TP6. The author moving from TP6 to TP7 across a year is the obvious reading and neither finding is evidence about the other.

### BORLAND'S `Objects` IS AVAILABLE TO THIS TP6, AND ASSUMING OTHERWISE WAS COSTING BYTES

`HEAPS.PAS` declared its own `TObject`, `TCollection` and `PString` stand-ins, and the
header justified that as keeping the unit off whichever Turbo Vision the TP6 install
happens to have. **That was never tested and it was wrong.** A one-file probe --
`uses Objects; var C : TCollection; O : TObject;` -- compiles under this TP6 in five
bytes.

**AND IT MATTERED FOR MORE THAN TIDINESS.** A locally declared `TObject` needs its two
method BODIES compiled somewhere, and somewhere is this unit's own code segment --
bytes that in the original live in segment `1891`, Borland's `Objects`. Those phantom
bodies would have displaced everything after them, and the fifteen THeap methods that
went in cleanly afterwards could not have. Importing the real unit puts them where they
belong and makes the VMT layout authoritative instead of reconstructed.

The caution this file already records still applies: the release's own map shows the
author's `OBJECTS` differs from this install's by 74 bytes, so it is not necessarily the
same one. Nothing here depends on more than `TObject`'s VMT link at offset 0 and
`TCollection`'s field layout, both stable across versions. **A "keeps us independent"
justification is worth one probe before it goes in a header.**

### AND `VTDOSMEM` IS `LIB/UMBUNIT.PAS`, CONFIRMED THREE WAYS

The second of the three invented-name units `relmatch.py` flagged, and it is settled:
65.5% by measurement, all five signatures matching one for one, and `17cf` calling two
of them from outside.

    1880:0000  AllocRaw   -> DOSAllocate      1880:0097  Alloc -> UMBAllocate
    1880:005a  FreeRaw    -> DOSFree          1880:00cb  Free  -> UMBFree
    1880:0077  SetUMBLink -> UMBLink

`TUmbHeap.Init` calls `UMBAllocate` and `TUmbHeap.Done` calls `UMBFree`, and `17cf`
calls `1880:0097` and `1880:00cb` exactly once each. Renamed, and **`VTDOSMEM` still
verifies identical with the same 20 pending fixups.** One type is NOT adopted: the
release's `UMBLink` takes and returns a `BOOLEAN` where ours is a `Byte`, because the
code stores the DOS link state as a number and hands the previous value back — the
standing rule is not to change a type to match the release. The filename and unit name
stay for now; nothing else in the tree references those five routines.

**Two of the three flagged renames are done** (`1880`, and `188f`'s `SetMemTop`). Still
pending: `1650`/`VTNOTES` against `LIB/SONGUTIL.PAS` (71.1%) and `1b54`/`VTRESID`
against `VTSPECIA.PAS` (44.3%).

### A PARAMETER LIST CAN BE WRONG IN A WAY ONLY A CALLER IN ANOTHER SEGMENT REVEALS

`VTDOSRSZ` is 29 bytes, has verified IDENTICAL since it was written, and its parameter
list was wrong the whole time.

It was declared `SetBlockTop(TopSeg, ExtraBytes : Word)`. `17cf:01d3` calls it, and
writing that call as `SetBlockTop(Seg(HeapEnd^), Ofs(HeapEnd^))` produces
`LES DI,[..] / PUSH ES / LES DI,[..] / PUSH DI`. The original has
`PUSH [0c4a] / PUSH [0c48]` -- **a pointer variable pushed whole**, two instructions
instead of four. So the routine takes ONE `Pointer`.

**AND NOTHING INSIDE THE UNIT COULD EVER HAVE CAUGHT IT.** A `Pointer` and two `Word`s
occupy the same four bytes of stack, so the callee's own 29 bytes are identical under
either declaration -- it verified before the change and it verifies after. This is a
new failure mode for the tree: the earlier parameter-list lesson (`PlayStart`) was
about a routine's OWN `RETF` disagreeing with its declaration, which is self-evident
once looked at. **This one is invisible from inside the unit entirely.** Whenever a
segment starts calling a unit that was transcribed in isolation, re-read that unit's
signatures against the call sites.

Read as a pointer the arithmetic becomes `(Ofs(P) + 15) shr 4 + Seg(P) - PrefixSeg`,
the paragraph count needed to reach P, which is Turbo Vision's `Memory.SetMemTop`
exactly -- and the release's `HEAPS.PAS` calls `SetMemTop(HeapEnd)` at the very point
`17cf:01d3` calls this. **So segment `188f` is probably Borland's `Memory` unit rather
than DemoVT's own**, smart-linked down to the single routine anything references: 32
bytes is one procedure and TP's linker discards the rest. The unit keeps its invented
filename for now, flagged at the declaration -- renaming touches four other files and
the identification is strong rather than certain.

### `17cf`'s POINTER HELPERS EXPLAIN WHY THE HEAP IS BUILT THE WAY IT IS

Three one-line functions, thirty to fifty bytes each, and between them they are the
reason this unit exists at all.

A far pointer is a segment and an offset, so the same byte has many representations.
NORMALISING one moves as much as possible into the segment so the offset is always
0..15 -- which is what makes two pointers to the same byte compare equal, and what
lets a heap span more than 64K without an offset ever wrapping. `LinealPtr` is the one
that matters: the heap compares and subtracts addresses, and it can only do that on
the 20-bit linear form. **It is called fourteen times from inside the segment, more
than anything else there.**

**AND THE COST IS AN RTL CALL PER SHIFT.** An 8086 has no 32-bit shift, so
`17cf:0016` calls `1ba1:0a9c` for `shr 4` on a LongInt and `17cf:0091` calls
`1ba1:0aa8` for `shl 4`. That is why `IncPtr`'s single line is fifty bytes, and why
`NormalizePtr` -- whose shift is on a WORD and so gets the inline `SHR AX,4` -- is
twenty bytes shorter for what reads like the same expression.

### `14b9` IS SCOUTED, ALL SIXTEEN ROUTINES ARE NAMED, AND **`TSong` IS AN OBJECT**

One `census.py` run and two disassembly reads. Nothing is transcribed yet; everything below is measured.

**THE HEADLINE: 1.31's `TSong` IS `OBJECT(TObject)`, AND THIS DOCUMENT HAS CALLED IT A PLAIN RECORD SINCE THE READING PASS.** Three things settle it, none of them inference:

* `14b9:0005` is `XOR DI,DI / CALLF 1ba1:04f5` with a `JZ` over the whole body — Turbo Pascal's constructor prologue helper, `DI = 0` meaning "do not allocate", the `JZ` taking the failure path. Nothing but a CONSTRUCTOR emits that.
* `14b9:0014` calls `1891:0000` (`TObject.Init`) having pushed a ZERO VMT word and then `Self`, and `14b9:003f` calls `1891:0031` (`TObject.Done`), with `0046` the destructor epilogue helper `1ba1:0539`. That is `TObject.Init;` and `TObject.Done;` written out — which is exactly how the release spells both.
* Both routines are `RETF 6`: `Self` (4) plus the hidden VMT word (2). **A constructor and a destructor are the only routines that carry that word**, so the cleanup count alone separates them from every other routine in the segment.

So the two bytes at `TSong+$00` that `SONGUNIT.PAS` carries as `Fill00` — filler precisely because nothing was ever seen to touch them — are the **VMT link**. `TObject` has no fields, so the link sits at offset 0 and the first declared field is `Speed` at `+$02`. **Every offset already in the tree survives unchanged**, which is why nothing ever contradicted the record reading.

**WHY THE EARLIER READING WENT WRONG, AND IT IS A GENERAL TRAP.** The evidence for "record" was that `154d:0030` far-calls `14b9:04b6` with the Song pushed as a parameter. That is precisely what a **static (non-virtual) method call** looks like: Turbo Pascal pushes the parameters, pushes `Self` LAST, and makes a direct far call. A record's free function and an object's static method are byte-for-byte identical at the call site. **Only the constructor can tell them apart**, and the constructor is in the segment nobody had read.

The same fact is why the `VTSONG.PAS` stub works at all: it declares `var Song : TSong` as the LAST parameter, which puts `Self` at `[BP+06]` exactly where a method finds it. **Converting those five stubs to methods cannot move a byte**, and `PLAYMOD` verifying unchanged is the proof to run.

**ALL SIXTEEN ROUTINES, IN ADDRESS ORDER, AGAINST THE RELEASE'S IMPLEMENTATION ORDER.** Turbo Pascal lays routines out in source order, so this agreement checks all sixteen at once — the same instrument that finished `165a`:

| addr | routine | `RETF` | what fixes it |
|---|---|---|---|
| `0000` | `Init` | 6 | the constructor helper, `TObject.Init`, then `PUSH CS / CALL 072f` = `InitValues` |
| `002b` | `Done` | 6 | `PUSH CS / CALL 0687` = `Free`, then `TObject.Done`, then the destructor helper |
| `004f` | `Load(VAR St : TStream)` | 8 | `ENTER 0806,0` — `TSongHeader` plus `i` and `Pos`, the release's three locals |
| `0100` | `LoadFName(FName : PathStr)` | 8 | the `.MOD` literal at `0102` and the two `1b6f` calls at `0186`/`01b4` (`FSplit`, `FExpand`) |
| `02c2` | `GetName : STRING` | **4** | see below |
| `02f5` | `SetName(S : STRING)` | 8 | `ENTER 0100,0` for the value `String`, then `HDisposeStr` (`[DI+34]`) and `HNewStr` (`[DI+30]`) on `Self+$0a` |
| `0352` | `GetInstrument(i : WORD)` | 6 | already in the stub; `154d:0030`'s target |
| `0404` | `GetTrack(i : WORD)` | 6 | `154d` calls it |
| `04b6` | `GetPattern(i : WORD)` | 6 | `154d` calls it |
| `0575` | `GetPatternSeq(i : WORD)` | 6 | already in the stub |
| `059f` | `GetPatternSequence(Seq : WORD)` | 6 | already in the stub |
| `05d3` | `GetPatternTempo(Seq : WORD)` | 6 | the stub calls it `GetPositionSpeed` |
| `0607` | `GetNote(Seq, Row, Chan; VAR Note)` | 14 | already in the stub: 6 + 4 + `Self` |
| `0687` | `Free` | 4 | called by `Done` |
| `072f` | `InitValues` | 4 | called by `Init` |
| `0897` | `Empty` | 4 | the release's `Free; InitValues;`, and the last routine in both |

**FIVE OF THE RELEASE'S TWENTY-ONE ARE ABSENT, AND 21 - 5 = 16 IS THE FAR-RETURN COUNT EXACTLY.** `Save` and `SaveFName` — a player does not write modules. `GetErrorString` — `census.py` finds **no printable string in 2,224 bytes but `.MOD`**, and that routine is nothing but message literals, so the absence is measured rather than assumed. And `GetInsidePath`/`SetInsidePath`, which leave `GetName`/`SetName` as the only pair of the five accessors that survives.

**A `STRING` FUNCTION IS `RETF 4`, NOT `RETF 8`, AND THAT IS WHAT NAMED `GetName`.** `02c2` reads `[BP+06]` (`Self`) *and* `[BP+0a]`, yet cleans up only four bytes — which looks impossible until you notice **Turbo Pascal does not pop the hidden string-result pointer**; the caller does. `116e`'s `GetToken : STRING` is `RETF 4` for the same reason and had already been read correctly, so the rule was in the tree and not written down. Without it `02c2` has one parameter too many for anything in the release.

**THREE THINGS THIS DOCUMENT CARRIES AS OPEN OR PROVISIONAL CLOSE ON THE ROUTINE MAP ALONE:**

* **`Table3D` at `+$3d` is `PatternTempos`.** `05d3` is `GetPatternTempo`, and the release's body is `IF PatternTempos <> NIL THEN ... := PatternTempos^[Seq]`. The "still deliberately open in the reading" entry — closed from the consumer's side as "a per-order-position SPEED OVERRIDE" — now has the producer's name too, and the two agree: a tempo per order position, zero meaning none.
* **`Order` at `+$39` is `PatternSequence`**, its neighbour and the other half of the same pair. `0575`/`059f` are `GetPatternSeq`/`GetPatternSequence` and read it.
* **`TitleH` at `+$0a` is `Name : PString`.** `SetName` disposes and re-news exactly that field through the heap object at `DS:$39ae`.

**AND `154d`'s THREE ENTRY POINTS ARE NOW NAMED** — `0352 GetInstrument`, `0404 GetTrack`, `04b6 GetPattern` — which is half of what the `154d` scouting note says it is blocked on.

### THE `VTSONG.PAS` / `SONGUNIT.PAS` NAME CLASH IS SETTLED: **`SONGUNIT.PAS` GROWS INTO THE SEGMENT**

The pick-up note said the two files' names are crossed and one has to give. They are, and it is `VTSONG.PAS` that goes.

`SONGUNIT.PAS` already carries the release's unit name, already declares `TSong`, and is already imported by `PLAYMOD`, `UNKLOADE` and `VTCFG` — three units that are byte-exact and whose `uses` clauses would otherwise all have to change. `VTSONG.PAS` is a five-routine stub nothing else names. So the five stubs become methods of `TSong`, `VTSONG.PAS` is deleted, and `PLAYMOD`'s `uses` drops it.

**DONE, AND THE PROOF IS THAT NOTHING MOVED.** `TSong` is now `object(TObject)`, the five
stubs are static methods, `VTSONG.PAS` is deleted, `PLAYMOD` calls them as
`Song.GetPatternSeq(SeqPlaying)` and drops `VTSong` from its `uses`, and `build.py`'s
`ORDER` carries `SONGUNIT.PAS` as segment `14b9`. `PLAYMOD` compiles to **5,958 bytes as
before** and `verify.py` reports **every unit and every fixup count identical to the
baseline** -- 2 byte-identical, 20 identical but for fixups, 0 mismatched. That is the
whole argument that a record-to-object conversion is free: `TObject` has no fields, so the
VMT link lands on the two bytes that were already filler.

`SongUnit` is deliberately NOT in `verify.py`: all ten bodies are still placeholders.
Six more routines exist only as comments in the object declaration (`Load`, `LoadFName`,
`Free`, `InitValues`, `Empty`, and the real `Init`/`Done` bodies) because nothing outside
`14b9` calls them yet.

## `14b9` IS DONE — 2,224 of 2,224, 198 pending fixups

**All sixteen routines, every block at shift +0, zero real differences.** `verify.py` now reports

    SONGUNIT  14b9     2224  identical, 198 pending fixups

and the tree stands at **2 byte-identical, 21 identical but for fixups, 0 mismatched**. `python v1.31b/coverage.py` computes **35,132 of 44,272 in-scope bytes, 79.4%**, up from 74.3%. **Four segments remain, 9,063 bytes**: `154d` (3,920), `19a0` (1,905), `1000` (1,621), `193a` (1,617). None is larger than `154d`, and `154d`'s two blockers are now gone.

It took seven builds. The release's `LIB/SONGUNIT.PAS` supplied every body; what had to be measured was the LAYOUT, the loader count, and five signatures — and `Free` and `InitValues` between them named the record without a guess.

### `Load` WAS LAST, AND ITS ONE REAL DIFFERENCE IS A SINGLE INSTRUCTION

`14b9:00b8` is `CMP WORD PTR [BP-0802],0002`. **1.31 has TWO loaders where 1.39b has eight.** The release recognises `.669`, `.OKT`, `.S2M`, `.S3M`, `.STM` and self-extracting `.EXE`s as well; 1.31 keeps the FIRST and the LAST of its list and drops the middle six — `UnkLoader.LoadJMFileFormat` (segment `164b`) and `ModLoader.LoadModFileFormat` (segment `154d`), which are the only two loader segments anywhere in the program's map. Everything else in the routine is the release's body verbatim, including `SizeOf(TSongHeader)` = `$800`, which `ENTER 0806,0` accounts for exactly.

**AN INDEXED CALL'S DISPLACEMENT LANDED ON A REAL VARIABLE, AND IT IS A COINCIDENCE.** `00ec` is `MOV DI,[i] / SHL DI,2 / CALLF [DI+03c0]` — and `ModOffset` is the LongInt at `DS:$03c0` that `LoadFName` pushes by name eighty bytes earlier. They are not the same object. `SongLoaders` is `array[1..2]` of a four-byte procedure pointer, so its base-1 base is one element low: the array starts at `DS:$03c4` and `$03c0` is what the compiler subtracts to index it. **A displacement that matches a known variable is not evidence that the code touches it — check the index scaling first.** Same rule as 12ba's six base-1 arrays, with a collision on top.

### TP6 REJECTS A CIRCULAR UNIT REFERENCE THAT TP7 ACCEPTS, AND IT COST THE ONLY DEVIATION IN THE SEGMENT

The release declares `SongLoaders` in `SONGUNIT.PAS`'s implementation and reaches the two loader units through an implementation `uses` — the legal direction, since both loaders `uses SongUnit` in their *interface*. **TP6 answers `Error 68: Circular unit reference` anyway**, with or without `/M`, and no linear compile order can help: whichever of the three is compiled first needs one of the others' `.TPU`. `/M` was added to `build.py` to try it and reverted; the attempt is recorded there so it is not repeated.

So `SongLoaders` is an **uninitialised `var`** rather than the original's typed constant, with both real entries named in a comment beside it. TP6 will not even accept `nil` in a procedure-typed constant (`Error 20`), so there is no form of the declaration that omits the unit names.

**AND IT COSTS NOTHING THIS PROJECT CAN MEASURE, WHICH IS EXACTLY WHY IT IS FLAGGED.** A typed constant is initialised DGROUP data and is not in a `.TPU`'s code at all; `Load`'s call through it is `CALLF [DI+03c0]`, a DGROUP offset, which is a linker fixup and therefore zeros. The table's contents cannot move a byte of any measurement made here — **this is risk 1 in its purest form**, and it must be filled in before anything is LINKED. It is the first deliberate data deviation in the tree and the only one in this segment.

### AND `Load` CORRECTED A FOURTH INTERFACE IN A BYTE-EXACT UNIT

`UNKLOADE` declared `LoadJMFileFormat(Song : PSong; St : Pointer; Header : PModJMIdString)` — three pointer VALUE parameters. The release has three VAR parameters, and `14b9:00dc` pushes three far pointers, which is what settles it. The two forms occupy the same twelve bytes of frame, so **`164b`'s own code is identical either way** and nothing inside it could ever have caught this. Changed to the release's declaration, with its `ModJM : TModJMIdString ABSOLUTE Header` alias, and **`UNKLOADE` still verifies identical with the same 14 pending fixups.**

That is the fourth: `VTDOSRSZ`'s `SetMemTop` took two Words instead of a Pointer, `VTDOSMEM`'s five routines carried invented names, `GUS`'s `DumpToUltrasound` took a `Pointer` instead of an untyped `var`, now this. **Every one was found by the first caller in another segment, and never from inside.** Two segments remain that will call into finished units — treat each new caller as a test of what it calls.

**FIFTEEN OF THE SIXTEEN ARE BYTE-EXACT. ONE IS LEFT: `Load`.** `LoadFName` went in whole — 450 bytes, first build, the release's body verbatim — and the whole segment below it now sits at a single shift of −171, which is `Load`'s shortfall exactly. `Load` is 177 bytes at `004f`, and it is the only reason `verify.py` still reports a prefix rather than a result.

**AND `LoadFName` NAMED `Load` AND TWO THINGS BESIDE IT.** `14b9:0299` is `PUSH SS / PUSH DI (St) / PUSH ES / PUSH DI (Self) / PUSH CS / CALL 004f` — so `Rut_004f` is `Load(St)` with the stream by reference, which settles both its name and its signature without reading a byte of it. `14b9:0242` pushes the LongInt at `DS:$03c0` into `St.Seek`, and that is `VTGlobal.ModOffset`, already declared. And **`msFileOpenError` is now SEEN STORED** — the constant list has carried it as "not seen stored yet" since the reading pass; `14b9:025e` writes 3 into `+$59` on the stream-open failure path.

**THE FRAME IS THE RELEASE'S DECLARATION ORDER AND EVERY OFFSET CHECKS**, which is worth having as a worked example because three units have got this wrong:

    [BP-0050]  FName   80 bytes, and 010a's PUSH 004f is String[79] = PathStr
    [BP-0058]  St      8 bytes, TDosStream
    [BP-009c]  Dir     68 bytes, DirStr = String[67] -- 116e's arithmetic again
    [BP-00aa]  IPath   13 bytes, String[12]
    [BP-00ac]  OSongStart     [BP-00ae]  OSongLen
    [BP-01ae]  a 256-byte compiler string TEMPORARY, not a local

**The 256 bytes at the bottom are a temporary**, and inventing a variable to explain them is exactly what `1b54` and `164b` both did. The rule this file already states — *a frame larger than the locals explain is a temporary before it is a missing variable* — held here on the first reading.

**AND A STRING FUNCTION'S RESULT POINTER IS REUSED AS THE FOLLOWING ASSIGNMENT'S SOURCE.** `IPath := GetInsidePath` at `0131` pushes the temporary's address, calls, and then pushes only ONE more pointer before the string-assign helper — because the result pointer is still on the stack. **That is the other half of the `RETF 4` rule**: the callee does not pop it precisely so the caller can use it as the source. Seen again at `017b` for `FName := FExpand(FName)`. A string assignment that looks like it is missing an argument is this, not a mis-read.

Four offsets were confirmed a second time on the way through: `0197` hands `Self+$16` and `Self+$1f` straight to `FSplit` as its `NameStr` and `ExtStr`, `01c6` stores `HNewStr`'s result into `+$12`, and `01ec`'s `PUSH 0004` is `FileExt := '.MOD'` against a `String[4]`.

**FOURTEEN OF THE SIXTEEN ARE BYTE-EXACT. TWO ARE LEFT: `Load` and `LoadFName`.** `InitValues` went in whole — 360 bytes, first build — and everything from `GetInsidePath` to the end of the segment now sits at ONE shift of −593, the exact shortfall of the two remaining placeholders.

### `InitValues` IS WHAT NAMED THE RECORD, AND IT NAMED NINE FIELDS AT ONCE

It initialises every field in the release's order, so its stores **are** the declaration read off the binary. That is a far stronger instrument than any accessor, and it is the lesson `Free` had just taught, applied deliberately:

| offset | was | is | how |
|---|---|---|---|
| `+$16` | `Fill16` | `FileName : String[8]` | a lone zero LENGTH BYTE at `077b` |
| `+$1f` | `Fill16` | `FileExt : String[4]` | the same at `0783`, and the gaps give 9 and 5 bytes |
| `+$24` | `Fill16` | `FirstTick` | `078b`, and **12ba:0d64 reads it** |
| `+$25`/`+$26` | `DefSpeed`/`DefTempo` | `InitialTempo`/`InitialBPM` | the release's names, same values |
| `+$27` | filler | `Volume` | `07a3` |
| `+$28` | `Chans` | `NumChannels` | `07ab` |
| `+$35`/`+$37` | `Len35`/`Len37` | `SequenceLength`/`SequenceRepStart` | `07cb`/`07d4`, in the release's own order |
| `+$5a` | filler | `ErrorCode : Word` | `087f` |
| `+$5c` | filler | `ThereIsMore` | `0886` |

**A LONE ZERO LENGTH BYTE IS HOW A STRING FIELD ANNOUNCES ITSELF.** `MOV byte ES:[DI+16],0` is `FileName := ''` — Turbo Pascal writes only the length. The GAPS then give the declared sizes: `$16..$1e` is nine bytes and `$1f..$23` is five, so `String[8]` and `String[4]` — which is `FSplit`'s `NameStr` and `ExtStr` exactly, and `14b9:0100` is the routine that calls `FSplit`. Same arithmetic that settled `DirStr` as `String[67]` in `116e`. **And `154d` had already confirmed `+$1f` independently**: this file records `154d:0c4d` comparing `'.WOW'` against `TSong+$1f` and calling it "the release's `Song.FileExt`". Two segments, one offset.

**AND THE RECORD'S SIZE IS SETTLED AT LAST: `$5e` bytes.** `InitValues` touches nothing past `+$5d`. The header of `SONGUNIT.PAS` has carried "THE TOTAL SIZE IS NOT SETTLED — 14b9's constructor is what allocates the record and it has not been transcribed yet" since the reading pass; this is the routine it was waiting for.

**THE RELEASE'S LAST STATEMENT IS ABSENT, AND ITS ABSENCE IS CONSISTENT TWICE OVER.** 1.39b ends `InitValues` with `PanPositions := DefPan` and there is no trace of it: `088e` writes `+$5d` and the next instruction is `LEAVE`. 1.31 keeps pan in the player — `12ba:0275` writes it per channel — so the song carries no pan table, and `census.py` finding no typed-constant data in the segment agrees.

**BUT THE THREE COLLECTION LIMITS DID CARRY OVER**, which is worth recording because the standing rule says they might not have: `(32,32)`, `(64,64)` and `(256,256)` are pushed as immediates at `07b0`, `0844` and `085a`, exactly the release's numbers. Compare `NumBuffers`, where the release's 3 was 1.39b's and 1.31's was 1. **The release's DATA is sometimes right; it is still never assumed.**

**TWO TYPES ARE DECLINED, AND 12ba IS WHY.** The release has `FirstTick` and `ThereIsMore` as `BOOLEAN`; both stay `Byte` here, because the standing rule is not to take a type from the release and the code settles it — `12ba:0d64` tests `FirstTick <> 0`, and `14b9` only ever stores a zero byte. Same reasoning as `VoicesChanged`. **PLAYMOD was reading that field as `Song.Fill16[$24]`**, an unnamed byte inside a filler array, which is a third confirmation of what `+$24` is and the reason the rename was worth doing.

Nineteen references in `PLAYMOD` were renamed with the field, and **`PLAYMOD` still verifies identical with the same 1,187 pending fixups** — which is the only proof a rename moved nothing.

**THIRTEEN OF THE SIXTEEN ARE BYTE-EXACT. THREE ARE LEFT: `Load`, `LoadFName`, `InitValues`.** `GetNote` and `Free` joined on the build after the accessors, both first time.

**AND `Free` OVERTURNED A FIELD NAME THAT WAS ONE ACCESSOR OLD.** `+$0a` had been named `Name` on the strength of `14b9:02f5` disposing and re-newing it — which is real evidence, and wrong. `Free`'s eight calls each pass a field ADDRESS (`LES DI,[BP+06] / ADD DI,<offset>`), so the offsets are in the instructions:

    069c  +$06        [DI+34] HDisposeStr   Name
    06b2  +$0e $03d0  [DI+0c] HFreeMem      Comment
    06c5  +$12        [DI+34] HDisposeStr   FileDir
    06d7  +$29        [DI+04] Done          Instruments
    06ed  +$39 $0100  [DI+0c] HFreeMem      PatternSequence
    0703  +$3d $0100  [DI+0c] HFreeMem      PatternTempos
    0715  +$41 / 0727 +$4d                  Patterns, Tracks

**`$03d0` IS WHAT SETTLES IT: `SizeOf(TSongComment)` is `16 * 61` = 976 = `$3d0`**, so `+$0e` is the comment block, and with it pinned the release's three-statement order fixes `Name` at `+$06` and `FileDir` at `+$12`. So **`+$0a` is `InsidePath`**, and the two routines at `02c2`/`02f5` are `GetInsidePath`/`SetInsidePath`, not `GetName`/`SetName`. The five absent routines are therefore `Save`, `SaveFName`, `GetErrorString`, **`GetName` and `SetName`** — 1.31 keeps the path pair and drops the title pair, which is what a player rather than a tracker needs. Two independent confirmations followed: the release's `Free` does not touch `InsidePath` either, and `InitValues` clears `+$06`, `+$0a`, `+$0e`, `+$12` in exactly the release's four `:= NIL` statements.

**ONE ACCESSOR IS NOT ENOUGH TO NAME A FIELD, AND THIS IS THE SECOND TIME.** `Table3D` at `+$3d` kept its address for a name for exactly this reason and was right to. `+$0a` was named from one routine and it took a second routine — one that touches SEVEN fields in the release's order — to correct it. **Prefer the routine that touches many fields at once; its order is the evidence, not any single store.**

The rename also caught itself: renaming the field left `GetInsidePath`'s `if` test reading `Name`, and `block14b9.py` reported the routine going from 0 real differences to 2 — at `+02cb` and `+02cf`, the two operands of `MOV AX,[DI+0a] / OR AX,[DI+0c]`. **A per-block measure catches a half-applied rename that a whole-unit prefix would have buried**, since both routines are past the first placeholder.

**`[DI+04]` IS `TObject.Done`, THE FIRST VIRTUAL SLOT.** A TP VMT holds the positive and negative size words at `+$00`/`+$02` and the first virtual method at `+$04`, so three calls to `[DI+04]` are three collections being destroyed — a fifth independent confirmation that those fields are real `TCollection`s.

**AND `Free` USES `FullHeap` WHERE `GetInstrument` USES `Heap`** — `DS:$39ae` against `DS:$397e`, exactly as the release writes the two routines. Neither can be measured from the bytes, because a DGROUP address is a fixup; this is the release settling something the binary cannot.

**ELEVEN OF THE SIXTEEN ROUTINES ARE NOW BYTE-EXACT, AND `v1.31b/block14b9.py` IS WHAT SAYS SO.** The prefix cannot see them — it stops at `+004f`, the first placeholder — so the segment needed the same instrument `12ba` did. Per block, searching for the alignment rather than assuming one:

    Init 0000  Done 002b  GetName 02c2  SetName 02f5  GetInstrument 0352
    GetTrack 0404  GetPattern 04b6  GetPatternSeq 0575
    GetPatternSequence 059f  GetPatternTempo 05d3  Empty 0897

all with **zero real differences**, and the eight from `GetName` down all at the *same* shift of −593 — which is itself a check, because eight independent blocks agreeing on one displacement means they are in the right order and only the two placeholders above them are short. Five are left: `Rut_004f` (`Load`), `LoadFName`, `GetNote`, `Free`, `InitValues`.

**THE THREE COLLECTION ACCESSORS WENT IN ON THE FIRST BUILD, ALL 547 BYTES OF THEM**, from the release's bodies with no adjustment — the `FOR` from `Count` to `i`, the `GOTO Break` out of it, `HGetMem`, the constructor, `AtInsert`, and the `At` in the `else`. Three things had to be read out of the binary first, and each would have cost a build:

* **`Count` IS AN `Integer`, AND ONE `CWD` FIXES IT.** `14b9:035d` sign-extends `Instruments.Count` to a LongInt and zero-extends the `Word` parameter beside it, so the comparison is 32-bit. Declared a `Word` the whole thing collapses to a 16-bit `CMP` and the routine is fourteen bytes shorter. That is `TCollection`'s own declaration, and it is the fourth independent confirmation that these fields are real `TCollection`s.
* **`MOV AX,0566 / PUSH AX` IS THE VMT OFFSET, NOT A PARAMETER.** `Instrument^.Init` is a CONSTRUCTOR and carries the hidden VMT word — and this one is a real construction, where `TSong.Init`'s own `TObject.Init` at `000c` pushes ZERO because an inherited call must not re-stamp the VMT. Same at `0456` with `$056e` for `TTrack`. **The pushed constant tells you which object is being built**, and a zero there tells you the call is inherited.
* **THE THREE `SizeOf`s NAME THE THREE TYPES.** `PUSH 000a` and `PUSH 000e` are `SizeOf(TInstrument)` and `SizeOf(TTrack)` exactly as `SONGELEM.PAS` already declares them — VMT + `Name` + `Instr`, and VMT + `Name` + `Note` + `Comm`. So `GetInstrument` returns `SongElements.PInstrument`, and 12ba's "reads the returned record's `+$06`" is reading `Instr`. `SongUnit` now `uses SongElements`, which is the release's own layering.

**AND A SEARCH WINDOW IS PART OF THE MEASUREMENT, WHICH COST ONE WRONG ANSWER.** `block14b9.py`'s window was ±600 and it reported `Empty` as five real differences. `Empty` is the last routine in the segment and every placeholder above it is short, so its true alignment is −1,228 — outside the window. **A too-narrow window does not fail loudly; it returns the best shift it could reach and a plausible-looking difference count.** Widened to ±2,400 and `Empty` is clean. Same family as the hardcoded-shift mistake this file already records: search for the shift, and make sure the search can actually reach it.

**FIRST BYTES MEASURED: `SongUnit` AGREES TO `+004f`, WHICH IS `Init` AND `Done` EXACTLY.** Both went in on the first build from the release's bodies — `TObject.Init; InitValues;` and `Free; TObject.Done;` — and `+004f` is the first placeholder's address to the byte. Eight of the sixteen now have real bodies (`Init`, `Done`, `GetName`, `SetName`, `GetPatternSeq`, `GetPatternSequence`, `GetPatternTempo`, `Empty`); the rest are placeholders holding their position, so the prefix stops at the first of them and says nothing about what follows. Every other unit still verifies exactly as before, through a `build.py` `ORDER` reshuffle as well — `SongUnit` needs `Heaps` for `FullHeap`, so it moved below `HEAPS` and `SONGELEM` and took `MODCOMMA`, `UNKLOADE` and `PLAYMOD` down with it.

**AND `+$02`/`+$04` ARE `SongStart`/`SongLen`, WHICH THIS DOCUMENT ARGUED AGAINST.** The note in `SONGUNIT.PAS` used to say the release's first two fields "would map onto 1.31's `+$02` and `+$04`" but that the values 1 and `$100` read as a speed and a tempo rather than a start and a length. `InitValues` opens with `MOV WORD PTR ES:[DI+02],0001` and `MOV WORD PTR ES:[DI+04],0100`; the release's opens with `SongStart := 1;` and `SongLen := MaxSequence;` — **and `MaxSequence` is 256, which is `$100`.** First two statements, first two fields, both values exact. **A constant refuted a reading of the values**: a tempo of 256 is not a tempo, a MOD's BPM runs 32..255. Nothing in the transcribed tree reads either field, which is consistent — a player that always plays the whole module never needs the play range.

**A `.TPU`'s INTRA-UNIT NEAR CALLS ARE RELOCATIONS, WHICH IS WHY `Init` MEASURES CLEAN AT ALL.** `Init` ends with `PUSH CS / CALL 072f` and `Done` with `PUSH CS / CALL 0687`, and both targets are still placeholders sitting at the wrong addresses — yet both routines compare identical. Turbo Pascal leaves a same-unit code reference as zeros with a fixup record, exactly as it does a DGROUP reference, so `verify.py`'s zero rule excuses it. **A call inside the unit is therefore NOT evidence that its target is right**, which is the opposite of the jump-displacement rule: a `JMP`/`Jcc` displacement is resolved at compile time and does encode everything downstream. Two kinds of intra-segment reference, opposite measurement properties.

**AND THE THREE `TColl` FIELDS ARE REAL `Objects.TCollection`s, WHICH THE FILLER PROVES.**
`SONGUNIT.PAS` declares an 8-byte `TColl` (VMT, Items, Count) at `+$29`, `+$41` and `+$4d`,
each followed by exactly four bytes of filler -- `Fill31`, `Fill49`, `Fill55`. TP6's
`TCollection` is `object(TObject)` with `Items`, `Count`, `Limit`, `Delta`: **12 bytes, and
8 + 4 = 12 three times over.** The filler is `Limit` and `Delta`. `census.py` confirms it
from the code: `1891:03a7` is called **exactly three times, all inside `InitValues`**
(`07c1`, `0855`, `086d`) -- the release's `Instruments.Init(32,32)`, `Patterns.Init(64,64)`
and `Tracks.Init(256,256)` -- and `1891:0405`/`047a` three times each from inside
`GetInstrument`/`GetTrack`/`GetPattern`, which is `At` and `AtInsert`, one pair per
accessor, exactly as the release writes them. So `Samples` is the release's `Instruments`.
Not changed yet: it belongs with `InitValues`, which is where it becomes measurable.

**THE DEPENDENCY DIRECTION IS CLEAN, WHICH IS THE THING THAT COULD HAVE BLOCKED IT.** The real unit needs `Objects` (for `TObject` and `TCollection` — `14b9` calls `1891:03a7`, `0405` and `047a` three times each), `Heaps` (the `DS:$39ae` object), and `SongElements` (`14b9` calls `165a` at four entry points). **`SONGELEM.PAS` does not use `SongUnit`**, and it already declares `TFullNote`, `PPattern`, `PInstrument`, `PTrack` and `PPatternSequence` — so the copies of those in `SONGUNIT.PAS` and `VTSONG.PAS` are DELETED rather than moved, and `SongUnit` moves down `build.py`'s `ORDER` to sit after `HEAPS` and `SONGELEM` and before `PLAYMOD`. That is the release's own layering: its `SONGUNIT.PAS` uses `SongElem`, not the other way round.

## THE FIRST MEASUREMENT OF THE LINKED IMAGE, AND IT PRIORITISES EVERYTHING LEFT

    python v1.31b/build.py --sw=/GS   (MSYS_NO_PATHCONV=1 in Git Bash)

produces `build/VTMAIN.MAP`, a segment map of our EXE. Compared against the original's segment layout it says three different things at once, and each is a different kind of work:

**1. FIVE UNITS LINK AT EXACTLY THE ORIGINAL'S SIZE** — `DEVGUS` 376, `SONGUNIT` 2224, `VTNOTES` 149, `VTDOSMEM` 237. For those, our program references the same set of routines the original's does and the linker kept the same code. **That is the first evidence any of this survives linking**, and it is worth more than it looks: a `.TPU` agreeing proves the bodies, and a linked segment agreeing proves the REFERENCES.

### ~~THE `SongLoaders` DEVIATION~~ — GONE. IT WAS A BUILD ORDER PROBLEM, NOT A LANGUAGE ONE

**TP6 accepts the circular reference. It just will not do it from scratch.** `SONGUNIT.PAS` now declares the real typed constant naming `LoadJMFileFormat` and `LoadModFileFormat`, `verify.py` still reports it identical at 2,224 with 198 pending fixups, and the three units that had vanished are back:

    MODLOADER  3908 of 3920      ASCIIZ  141 of 144      UNKLOADER  77  exact

**A NEGATIVE SEARCH IS WHAT FORCED THE ANSWER.** Every segment was scanned for a store to `DS:$03c4`..`$03ca` — the table — in all its forms, and **there is not one anywhere in the program.** So it is initialised data, so the original's `SongUnit` really does name both loaders, so the shape must be expressible under TP6. That turned "we cannot do this" into "we are doing it wrong", and it took one search to get there. **When a deviation looks forced, check whether the ORIGINAL could have had it.**

**AND THE FIX IS A BOOTSTRAP PASS, WHICH IS NOW IN `build.py`.** The unit is compiled once with `/DBOOTSTRAP` — a conditional that removes the implementation `uses` and the table's initialiser while **leaving the INTERFACE byte-for-byte the same** — the two loaders compile against that `.TPU`, and `ORDER` then recompiles `SongUnit` for real. No `--keep`, no manual steps, clean build from an empty directory. The bootstrap line has to be emitted inside the per-unit loop rather than at the top of the batch, because `SongUnit` needs `Heaps` and `SongElements` compiled first.

**THAT IS ALMOST CERTAINLY WHAT THE AUTHOR HIT AND NEVER NOTICED.** `.TPU`s accumulate in a build directory; only a CLEAN build deadlocks. TP7 needs none of it and the 1.39b release does not do it — **which is one more small piece of evidence for TP6**, arrived at from a direction nothing else in this project has used.

`build.py` also gained `--keep`, which suppresses both erasures — the Python-side wipe and `BUILD.BAT`'s own `del *.TPU`. **Two separate erasures, and the first fix missed the second.** Anything measured under `--keep` is suspect until a clean build agrees; it exists for experiments like this one and its docstring says so.

**2. ~~THREE UNITS ARE ABSENT FROM OUR IMAGE ENTIRELY, AND `SongLoaders` IS WHY.~~** *(fixed — see above; kept because the reasoning that led there is the useful part)*

    MODLOADER  3920 bytes   ASCIIZ  144   UNKLOADER  77     = 4,141 bytes missing

`SONGUNIT.PAS` declares `SongLoaders` as an uninitialised `var` with its two real entries recorded only in a comment, because TP6 rejects the circular unit reference that would let them be written. The note there says the contents "cannot move a byte of any measurement this project makes" and that it is risk 1 in its purest form. **The link is the measurement it CAN move.** Nothing references `LoadJMFileFormat` or `LoadModFileFormat`, so Turbo Pascal's smart linker discards both loader units, and `AsciiZ` goes with `ModLoader`. **The deviation was flagged as invisible and has now become the single largest thing wrong with the image.**

**AND A NEGATIVE SEARCH NARROWS IT TO ONE TESTABLE HYPOTHESIS.** Every segment was scanned for a store to `DS:$03c4`..`$03ca` — `MOV [03c4],AX`, `MOV word [03c4],imm`, and the DX and high-word forms — and **there is not one anywhere in the program.** So the table is not filled at run time by anybody: it is INITIALISED DATA, laid down by the linker, which means **the original's `SongUnit` really does name `LoadJMFileFormat` and `LoadModFileFormat` in a typed constant.** That rules out every "register yourself from an initialisation section" design, and it rules out `VTMAIN` filling it — both of which were live possibilities an hour ago.

Which leaves a contradiction worth stating plainly: **TP6 rejects the reference the original must have had.** `SONGUNIT`'s implementation must use `UnkLoader`, whose interface must use `SongUnit` for `TSong`/`TSongHeader`, and TP6 answers `Error 68: Circular unit reference` where TP7 accepts it (which is how the 1.39b release builds). The compiler is settled as TP6 by fifteen units of byte comparison, so the shape must be expressible somehow.

**THE HYPOTHESIS TO TEST NEXT IS A TWO-PASS BOOTSTRAP.** TP6 refuses to compile the cycle from scratch because whichever unit goes first needs the other's `.TPU` — but if `UNKLOADE.TPU` and `MODLOADE.TPU` already exist from an earlier build, compiling `SONGUNIT` against them may simply work. That is how a 1992 developer would have hit it and not noticed: the `.TPU`s accumulate in the build directory and only a clean build deadlocks. `build.py` wipes `build/` on entry, so it has never been in that state. **The experiment is to build once as now, then recompile `SONGUNIT` alone with the real table and the implementation `uses`, without wiping.** If that compiles, the fix is a documented two-pass build rather than a deviation, and 4,141 bytes come back.

It is not trivially fixable and the obvious repairs are all worse. Registering each loader from its own initialisation section would put both units into the init chain, and the original's chain has neither. Assigning the table from `VTMAIN` would emit code the original has not got. Moving `TSong` to a declarations-only unit to break the cycle cannot work either, because its methods are segment `14b9` and a method must be declared with its type. **This needs a real answer before the EXE can be compared.**

**3. FIVE UNITS ARE SMART-LINKED DOWN, WHICH MEANS OUR PROGRAM REFERENCES LESS THAN THE ORIGINAL'S.**

    VTCMD    3296 -> 1157      SONGELEMENTS  3216 -> 1057
    CMDLINE  1232 ->   30      VTSILENC       489 ->   30
    VTCTRL     25 ->    0      GUS           2741 -> 2622

Each gap is a list of routines the original's program reaches and ours does not. **These gaps are a WORK LIST, not a defect**: each one names a reference `VTMAIN` or another unit is still missing, and the smart linker found them for free.

### THREE UNITS ARE ALREADY RECOVERED, AND THEY WERE ALL THE SAME MISTAKE

    VTCTRL     0 -> 25    exact      VTSHELL    0 -> 138  exact
    VTSILENC  30 -> 489   exact

**A UNIT'S INITIALISATION SECTION HAD BEEN TRANSCRIBED AS A NAMED PROCEDURE.** In each case nothing anywhere calls that procedure, so Turbo Pascal's smart linker discarded it and everything it referenced — and in each case the original's init chain calls exactly its address (`14b7:0000`, `1931:0029`, `1065:0172`). Rewritten as `begin ... end.` all three link at the original's size, and **all three still verify identical with their original pending-fixup counts**, because the bytes were never wrong.

**THE `.TPU` COMPARISON COULD NOT HAVE FOUND ANY OF THEM.** `VTCTRL` has verified at 25 of 25 for its whole life. What was wrong was the KIND of thing the bytes are — a procedure nobody calls versus an initialisation section — and that distinction does not exist until something links. **This is a genuinely new class of defect for the project, and it is the answer to "what can the link tell us that the segment comparison cannot".**

`VTSILENC` also needed its `Driver` record turned from a `var` assigned in a second init block into a TYPED CONSTANT, so `'Silence'` is initialised data rather than code. **That is the identical fix `DEVGUS` already carries** — this file records it there, where it took the unit from 402 bytes to 376 — and it had simply not been applied to the second driver.

### AND `VTSHELL`'s THREE "STUBS" WERE IN THE NEXT SEGMENT

`VTSHELL.PAS` carried `Stub90`, `Stub95` and `Stub9A` at `1931:0090`, `0095`, `009a`, described as "kept because they are in the segment". They are in the next one: the unit spans 144 bytes, `193a` follows it, and `0x1931*16 + 0x90` is `0x193a0`, which IS `193a:0000` — **DevSB's first three `Name` functions, five bytes each**, with a fourth at `000f` the original scan stopped short of. Withdrawn.

**A SEGMENT BOUNDARY IS NOT A SUGGESTION.** Check a span against the FOLLOWING segment's address before believing anything near the end of a unit — the same arithmetic that confirmed `116e`'s 1,232 bytes are exact because `11bb` begins at `116e:04d0`.

### THE REMAINING GAPS, LARGEST FIRST

    MODLOADER     3920  ABSENT          SONGELEMENTS  2159  short (1057 of 3216)
    VTCMD         2139  short           CMDLINE       1202  short (30 of 1232)
    ASCIIZ         144  ABSENT          GUS            119  short
    UNKLOADER       77  ABSENT

**Everything below about 15 bytes in that comparison is PADDING, not missing code** — `PLAYMOD`'s 10, `SOUNDBLASTER`'s 7, `MODCOMMANDS`' 1 are all already documented as linker padding, and the comparison puts `verify.py`'s CODE sizes against the map's SEGMENT lengths. Put both sides on the same footing before chasing any small figure.

**`VTCTRL` WENT TO ZERO AND IS ALREADY FIXED, AND THE FIX IS THE POINT.** Its 25 bytes were declared `procedure Reset; far;` in the interface — and nothing anywhere calls `Reset`, so the smart linker discarded the unit whole. The original's init chain calls `14b7:0000`, and a unit's INITIALISATION SECTION is exactly what sits at offset 0 and gets far-called from that chain. Rewritten as `begin ... end.` the unit now links at `00019H` — **25 bytes, the original's exactly** — and still verifies identical with the same 8 pending fixups.

**A `.TPU` COMPARISON COULD NEVER HAVE FOUND IT.** The bytes were already right; `VTCTRL` has verified at 25 of 25 for its whole life. What was wrong was the KIND of thing they are — a procedure nobody calls versus an initialisation section — and that distinction does not exist until something links. **Expect more of this class: `VTSHELL` is the same story (138 bytes, its chain entry at `1931:0029`), and every unit in the chain is a candidate.**

**AND THE LINK ORDER IS NOT THE ORIGINAL'S YET.** Ours runs `DEMOVT VTRESID VTCMD FILEUTIL CMDLINE DEVGUS VTCFG PLAYMOD …`; the original's, read off the segment addresses, is `1000 VTSilenc DevGus VTCmd FileUtil CmdLine VTCfg PlayMod ModCommands VTCtrl SongUnit Filters ModLoader AsciiZ UnkLoader VTNotes SongElements GUS Heaps VTDosMem VTDosRsz Objects DevSB SoundBlaster SoundDevices Hardware VTResid Dos System`. Turbo Pascal links units in the order the `uses` graph reaches them, so this IS controllable from `VTMAIN`'s clause — and it has to be, because getting `1a17` to actually BE segment `1a17` is what risk 3 asks for.

**THE ±2 DIFFERENCES ARE MEASUREMENT, NOT CODE.** `FILEUTIL`, `VTDOSRSZ` and `HARDWARE` each read two bytes larger and `DEVSB` four. Those comparisons use `verify.py`'s CODE sizes on one side and the map's SEGMENT lengths on the other, and several segments are documented as carrying padding the code size excludes. Do not chase them without putting both sides on the same footing first.

## **`VTMAIN` COMPILES, AND THE WHOLE PROGRAM LINKS FOR THE FIRST TIME**

    28 unit(s) compiled -- and VTMAIN.PAS is no longer in BLOCKED
    build/VTMAIN.EXE   45,024 bytes

**No segment is blocked on any other any more.** Twenty-six units are byte-exact and the twenty-seventh — the program — is a compiling Pascal source rather than a reading. `verify.py` still reports **2 byte-identical, 24 identical but for fixups, 0 mismatched**: nothing regressed on the way.

**THIS IS THE POINT THE PROJECT HAS BEEN BUILDING TOWARDS, AND IT OPENS RISKS 1 AND 3 RATHER THAN CLOSING THEM.** Everything measured so far has been a `.TPU`'s code compared against a segment, where every DGROUP address and every inter-unit call is a pending fixup the comparison excuses. A linked EXE has none of that slack: the variable order is fixed, the segment numbers are fixed, and `MAKE.BAT`'s `tpc` → `tdstrip` → `lzexe` pipeline has to match too. **Do not read "it links" as "it is nearly done".**

What is needed to measure the EXE, in order: control the LINK ORDER so that `1a17` really is segment `1a17`; then compare segment by segment; then the DGROUP layout, which is risk 1 and which nothing so far has been able to see.

### GETTING IT TO COMPILE TOOK SIX FIXES AND TWO OF THEM WERE READING ERRORS

* **`PlayStart` was not exported.** `1000:0381` is `CALLF 12ba:10a1`, and until segment `1000` was read nothing outside `PLAYMOD` was known to reach it, so it sat in the implementation. **Seventh interface corrected by a caller in another segment** — after `VTDOSRSZ`, `VTDOSMEM`, `GUS`, `UNKLOADE`, `TSong.Status` and `HARDWARE.DMAReset`. Exporting an already-`far` routine cannot move a byte, and `PLAYMOD` verifying unchanged is the check. (TP6 then rejected the `far` on its implementation header — Error 36, the documented rule — so that came off too.)
* **BOTH `Str(...)` CALLS IN THE FILE WERE `FillChar`.** `census.py` puts `1ba1:0fd5` at `031c` and `03da`, and `14b9` had already established `1ba1:0fd5` as `FillChar`. One fills eight bytes at `DS:$1208`; the other is `FillChar(DMABuffer^, DMABufferSize, $80)` — **and the `$80` says what it is for, because that is SILENCE for unsigned 8-bit audio.** It wipes the DMA buffer after the shell-out so whatever the shelled program left cannot be played back. The reading pass had both as `Str`, one of them as `Str(Buffer^ : -128, ...)`, which is not Pascal at all. **A `PUSH -0x80` is `$80`; read the constant before naming the call.**
* `Copy8C2To342` was a placeholder for three Word assignments, `03df..03f0`.
* `SavedCD2`/`SavedCD4` are one `LongInt` at `DS:$0cd2`, which is what `ShrinkSystemHeap` takes.
* Eight `Var<addr>` placeholders resolved to the units that own them — `LoopMod`, `ForceLoopMod`, `DesiredHz`, `ProgName`, `ShellParam`, `Heap`, `Ticks`, `DMABufferPtr` — each already declared at that address by its owner, independently. **Eight addresses agreeing is a cross-check, not an assumption.**

**AND ABOUT TWENTY DGROUP NAMES ARE STILL DECLARED IN `VTMAIN` THAT SHOULD NOT BE.** Every one is flagged at its declaration. Some almost certainly belong to `VTCmd` or `VTCfg`. A DGROUP reference is a linker fixup, so the byte comparison cannot tell a right home from a wrong one — **that is risk 1, and it now has to be settled rather than flagged, because the link is what will expose it.**

## `1000` IS THE ONLY SEGMENT LEFT, AND IT IS NO LONGER BLOCKED ON ANYTHING

**Every unit `VTMAIN` reaches is transcribed and byte-exact**, so the seventeen `Unit_<seg>_<ofs>` placeholders it carried are gone, replaced by names:

    109c:0000 SetVTDevice     109c:0038 SetVTFreq    109c:0724 DoSongColl
    116e:04b2 GetDOSCmdLine   12ba:10a1 PlayStart    12ba:13d7 PlayStop
    14b9:0000 TSong.Init      14b9:0106 LoadFName    14b9:02f5 SetInsidePath
    17cf:00b5 InitUmbHeap     17cf:01d3 ShrinkSystemHeap
    17cf:0a63 InitHeapVariables
    1891:0000 TObject.Init    1891:03a7 TCollection.Init
    1b6f:00a6 SwapVectors     (twice, bracketing the Exec at 03af)

**`objcheck.py` REPORTS `SOUNDDEV FAILED`, AND THE SOURCE IS RIGHT.** Measured 30 Aug 2026. The one unreconciled field is `1a17:102c`, the operand of `MOV SP,OFFSET DevStack + StackSize`: the tool reports `orig 3f1a, ours 03e8`. Ours is the ADDEND, still waiting on the `OFFSET DevStack` fixup, because `objcheck` compares the UNLINKED `.OBJ`; the original's is already absolute. In the LINKED image both hold `3f1a` -- `1a17:102b` is `BC 1a 3f`, `MOV SP,3f1a`, in the original and in ours alike -- and `linkbytes.py` reports **0 differing bytes over the whole image**. So this is the instrument reaching a form it cannot reconcile at one site, not a defect. It is the third instance in this project of a check that is blind or mute exactly where it is being trusted; see the kit's `break-it-to-learn-what-it-sees`.

**`build.py` STILL REPORTS IT BLOCKED, FOR A DIFFERENT AND HONEST REASON.** `VTMAIN.PAS` was written as a READING of the segment during the line-by-line pass, and parts of the body are notional rather than Pascal — `Str(Buffer^ : -128, ...)` at `1000:03da` is the clearest case. Turning it into something that builds is an ordinary transcription pass; what has changed is that nothing external stands in the way of starting it. The BLOCKED note now says that rather than naming units that no longer exist as gaps.

**THE INIT CHAIN AT `1000:04b3` IS A HARD CONSTRAINT ON THE `uses` CLAUSE**, and it is the first thing to get right. Turbo Pascal emits one call per unit that HAS an initialisation section, in dependency-resolved order, and the original's is

    1ba1:0000 RTL   193a:0488 DevSB   1931:0029 VTShell   17cf:0a93 Heaps
    14b7:0000 VTCtrl   12ba:141e PlayMod   11bb:0f2e VTCfg
    1084:0101 DevGus   1065:0172 VTSilenc   1ba1:1038 RTL exit

Nine calls in a fixed order, and units without an initialisation section never appear however they are listed. **That makes the chain a direct readout of the program's dependency graph** — and it is measurable, unlike almost everything else about a `uses` clause.

**AND `DevSB` REGISTERS BEFORE `DevGus`, WHICH MAY OVERTURN A NOTE.** `DEVGUS.PAS` records that `InitDevice` pushes onto the front of the list but selects only when nothing is selected yet, so the first to register wins — and concludes "a machine with both ends up on the GUS". That was written comparing `DevGus` against `VTSilenc` alone, before `193a` existed. `193a:0488` is called at `04b8` and `1084:0101` at `04d6`, so **the Sound Blaster registers first**. Flagged rather than resolved: the note's mechanism needs re-reading against `InitDevice` now that three drivers are in the chain rather than two.

## `193a` IS DONE — 1,617 of 1,617 bytes, 569 pending fixups

    DEVSB     193a     1617  identical, 569 pending fixups

**2 byte-identical, 24 identical but for fixups, 0 mismatched.** `coverage.py` computed **42,567 of 44,272 in-scope bytes, 96.1%** at the time, and `1000` was the one segment remaining. *(Figures as at that session; the current ones are at the top of this file.)*

Seventeen blocks, fourteen of them exact on the first build, including the 79-byte hand-written `DMAIrq` and the 455-byte initialisation section. Six differences had to be measured, and **five of the six are places where the release's SOURCE COMMENT is not a record of what 1.31 did**:

* **`SbMonoDetect` and `SbStereoDetect` set `Stereo`.** A five-byte store sits between the three inits and the result in both — `MOV byte [0bbd],00` and `,01`, and `$0bbd` is `SoundDevices.Stereo`. The release's detectors do not touch it. **The detectors configure as well as detect.**
* **`DMASBInit` IS GUARDED IN ITS ENTIRETY.** `0322` tests `OldDMAIrq` and `032b` jumps to the epilogue, so opening a second SB device while one is open does nothing at all. The release guards only the `SetIRQVector` pair — **and 1.31 KEPT that inner guard too**, at `0357`, where it can never fail. An outer guard added and the inner one left behind: transcribed as found.
* **`InitTimer` does not exist**, and **`DMASet` runs AFTER `SbPlaySample`** where the release runs it first. Two differences in the same three lines.
* **`SbPlaySample` is called with `DMABufferSize`, not the literal 10.** The release reads `SbPlaySample(10, FALSE)` with `DMABufferSize` commented out beside it — the real argument parked next to a debugging one. 1.31 has the real one.
* **`DMASBEnd` HAS NO WAIT LOOP.** `0458` is `PUSHF/STI` and `045a` is `POPF`, back to back with nothing between them; the release spins on `WHILE NOT DMAStopped AND NOT DeviceIdling AND NOT KbdKeyPressed`. 1.31 does not wait for the DMA to stop. The `STI` is undone one byte later, so the pair is a no-op left behind when the loop went. And `DMAReset` — commented out in the release — **is called**.

**THE LESSON IS ABOUT COMMENTED-OUT CODE.** This file already records that a release comment misled the `154d` delta block. Here it happened three more times in one routine pair: a commented-out `DMAReset` that 1.31 calls, a commented-out `DMABufferSize` that 1.31 passes, and a live wait loop that 1.31 has deleted. **A commented-out line in 1.39b is evidence that the author was editing that spot, and nothing more. Read the bytes.**

### AND `193a` CORRECTED A SIXTH INTERFACE IN A BYTE-EXACT UNIT

`HARDWARE`'s `DMAReset(Channel : Word)` is a `Byte`. `193a:045b` is `MOV AL,[0b18] / PUSH AX` — a byte load — where a `Word` parameter gives the one-instruction `PUSH [0b18]` that `DMASet` gets four lines later **in the same caller**. Two calls to two routines in the same unit from one routine in another, disagreeing, and the widths are why. `HARDWARE` still verifies identical with the same 36 pending fixups.

That is the sixth: `VTDOSRSZ`'s `SetMemTop`, `VTDOSMEM`'s five names, `GUS`'s `DumpToUltrasound`, `UNKLOADE`'s three var parameters, `TSong.Status`'s signedness, now this. **Every one was found by the first caller in another segment and never from inside.**

### `SOUNDDEV.ASM` GAINED A `PUBLIC` LABEL, AND A LABEL EMITS NO BYTES

`193a:0352` calls `1a17:1090`, nine bytes past `SelectOutput` at `1a17:1087` — two entry points into one tail, which the release names `DevInitSbNonDMA` and `DevInitSbDMA` (1087 forces mono and ignores its arguments; a non-DMA device is always mono). The module published only the first label, so the second had no name to call. Adding `PUBLIC DevInitSbDMA` moves nothing, and **`SOUNDDEV` verifying identical with the same 1,024 pending fixups plus a clean `asmcheck.py` is the check** rather than the argument.

## ~~`193a` IS MAPPED AND WRITTEN, AND BLOCKED ON TWO NAMES IN `1a17`~~

`v1.31b/src/DEVSB.PAS` holds all sixteen routines and the initialisation section. **It is deliberately OUT of `build.py`'s `ORDER` so the tree stays green**, and nothing has been measured yet. Two names are missing and both are in `1a17`, not here:

* **`DevInitSbDMA`.** `193a:0352` calls `1a17:1090`, which is nine bytes past `SelectOutput` at `1a17:1087`. `SOUNDDEV.ASM` publishes only the first label, so the second entry point has no name to call. The release has the pair as `DevInitSbNonDMA`/`DevInitSbDMA` — which is precisely what two entries into one routine means. Adding a second `PUBLIC` label moves no byte, but `SOUNDDEV` is byte-exact and that belongs in its own pass with `asmcheck.py` either side.
* **`InitTimer`.** The release's name for whatever `DMASBInit` calls to arm the periodic timer. `SOUNDDEV.PAS` exports `StartSampling` and has a private `InitPeriodic`; which one has not been measured.

**THE INITIALISATION SECTION NAMED ELEVEN OF THE SIXTEEN ROUTINES BEFORE A LINE WAS WRITTEN.** `193a:048a` fills four device records field by field with far addresses, exactly as `1084:0101` does — so the records *are* the routine table. Writing `0000` into record+$16, `02c2` into +$1a, `03c5` into +$1e, `0435` into +$22 and `007f` into +$26 names Name, `SbMonoDetect`, `DMASBMonoInit`, `DMASBChgHz` and `DMASBGetRealFreq` outright, and the second record's `013c` names `DMASBProGetRealFreq`. **This is the third segment running where the routine that touches many things at once did the structural work** — `SbRegDetect` for `19a0`'s ports, `InitValues`/`Free` for `TSong`, and now this.

**ONE `IRET` IN 1,617 BYTES.** A single byte-pattern search for `CF` settled a layout question the far-return census could not: there is exactly one interrupt handler, `DMAIrq` at `0030..007d`, 78 bytes. **`census.py` counts neither `IRET` nor near `RET`**, so a segment with handlers and private helpers needs that sweep as well — `SetVars` at `0014` is near and invisible to it too.

**FOUR DEVICES, NOT THE RELEASE'S SIX**, at `DS:$09f4`, `$0a2e`, `$0a68`, `$0aa2` — **58 bytes apart, which is `SizeOf(TSoundDevice)` exactly** with `Next` at `+$36` included, so `VTDRIVER`'s record is confirmed from a third segment. The release also has `SBData` (non-DMA) and `DMAPASData` (Pro Audio Spectrum); 1.31 has neither, and correspondingly no `SBInit`, `SBChgHz`, `SBEnd`, `DMAPASMonoInit` or `DMAPASEnd`. The four `InitDevice` calls register in REVERSE declaration order, and since `InitDevice` selects only when nothing is selected, **Mix2 is the default Sound Blaster mode**.

**AND ITS `TimerHandler` IS THE CORE'S, WHICH IS THE OPPOSITE OF THE GUS.** Every record gets `1a17:1008` — `SharedPoll`. This file records that "1.39b's GUS driver points its `TimerHandler` at the core's shared handler where 1.31 points at its own"; here 1.31's SB driver points at the core's. A DMA card is driven by its own DMA interrupt and needs only the periodic tick; the GUS is polled.

Its four `Name` functions are empty — five bytes each, no assignment — where `DEVGUS` writes `DevName := ''` and costs twelve. Same `RETF`-with-no-operand shape `14b9`'s `GetInsidePath` established: the caller pops the hidden String result pointer.

## `19a0` IS DONE — 1,898 of 1,898 bytes, 475 pending fixups

**All twenty-three routines, and the last FOURTEEN went in on a single build with no adjustment to any of them.** 1,905 in the segment map; the code ends at `076a` and the last 7 bytes are padding.

    SOUNDBLA  19a0     1898  identical, 475 pending fixups

The tree is **2 byte-identical, 23 identical but for fixups, 0 mismatched**, and coverage is **40,950 of 44,272 bytes, 92.5%**. **Two segments remain, 3,238 bytes**: `1000` (1,621) and `193a` (1,617).

**A HARDWARE UNIT IS THE EASIEST THING IN THIS PROJECT TO TRANSCRIBE, AND THAT IS WORTH KNOWING FOR `193a`.** Nothing here needed a second pass — the release's bodies transferred verbatim, `ASSEMBLER` routines included. The reason is structural: this unit talks to a Sound Blaster, and the Sound Blaster did not change between 1.31 and 1.39b, so there is no version drift to find. Compare `154d`, where three real differences had to be dug out, and `12ba`/`142f`, which drifted heavily. **Rank the remaining work by how much of it is hardware.**

**FIVE OF THE RELEASE'S NINETEEN ARE ABSENT AND THE `RETF` COUNTS ARE WHAT SAY SO.** `MixerSetVolume` (RETF 6) and `MixerGetVolume` (RETF 10) appear nowhere in the segment's return census, and `SbProDone`, `SbProSetFilter` and `Sb16Done` have no room between the returns that bracket them. 19 − 5 = 14 after `SbRegDetect`, which is the far-return count exactly, and the survivors are in the release's own order. **A player sets a sample rate and starts DMA; it never touches a mixer volume, never toggles the output filter, and never tears the card down** — precisely the five that are gone. The routine census predicted the whole shape before a line was written.

### THE TWO DGROUP BLOCKS ARE PINNED BY SPACING, WHICH IS RISK 1 BEING REDUCED

Neither block can be measured byte by byte — every address in both is a fixup. Both are fixed by laying the release's declaration order between addresses the instructions *do* name, and both arrive on their endpoints exactly:

* **The 28 ports, `$0adc..$0b13`.** `SbRegDetect` is the probe loop and rewrites every one of them from the base it is trying, so each store names its variable outright. **`$0adc + 27*2` is `$0b12`, so the next Word is `$0b14` — which is `SbPort`.** Port block and configuration block contiguous, nothing left over.
* **The run-time state, `$0b7e..$0b8e`.** Three known addresses — `SbRegDetected` `$0b7e`, `SbWorksOk` `$0b85`, `DoHiSpeed` `$0b8c` — with seven Booleans and two Words of the release's order between them, landing on both interior endpoints.

**A ROUTINE THAT TOUCHES MANY GLOBALS AT ONCE IS THE INSTRUMENT FOR DGROUP LAYOUT.** Same as `InitValues` and `Free` were for `TSong`'s record, and `142f`'s dispatch table was for its tick routines. When a segment's globals are unknown, look for the routine that initialises or rewrites all of them — it names every address in one pass, and the spacing between the ones you can read fixes the ones you cannot.

Also settled: `SbVersion` is a `Word` laid over two `Byte`s (`026f` compares `$0b22` word-wide where the halves are written separately), and 1.31 keeps the CD-ROM and CM/S ports it never otherwise uses, because the probe loop sets them store for store as the release's does.

### AND A BLOCK BOUNDARY THAT SWALLOWS THE NEXT ROUTINE'S LITERAL READS AS REAL DIFFERENCES

`SbRegInit` measured `** 4 real` until its block was narrowed from `029c` to `0298`. Turbo Pascal emits a routine's literals immediately BEFORE its code, so a block must end where the next routine's LITERALS begin, not at its `ENTER`. Same trap as `154d`'s `LoadModFileFormat`, where the `.WOW` literal sat five bytes ahead of the prologue — **twice in two segments, so check the boundary before believing a small difference count.**

## ~~`19a0` IS STARTED — nine routines, 668 of 1,905 bytes, all exact~~

Nine of the twenty-three, every block at shift +0 with zero real differences, measured by `v1.31b/block19a0.py`. `SbRegDetect` alone is 352 bytes and went in on the first build.

**`SbRegDetect` PINNED THIS UNIT'S ENTIRE DGROUP HEAD, WHICH NO BYTE COMPARISON COULD HAVE DONE.** It is the port-probe loop, and it rewrites all twenty-eight port variables from whatever base it is trying — so every store names its variable's address outright. The block runs `$0adc..$0b13`, and **`$0adc + 27*2` is `$0b12`, so the next Word is `$0b14`, which is `SbPort`** — the port block and the configuration block are contiguous and the arithmetic closes with nothing left over. Every one of those addresses is a fixup; the only reason any of them is known is that one routine writes them all. **A routine that touches many globals at once is the instrument for DGROUP layout**, exactly as `InitValues` and `Free` were for `TSong`'s record — and this is risk 1 being reduced rather than merely flagged.

It also settles two smaller things: `SbVersion` is a `Word` laid over two `Byte`s (`19a0:026f` compares `$0b22` word-wide where the halves are written separately), and 1.31 keeps the CD-ROM and CM/S ports it never otherwise uses, because the probe loop sets them store for store as the release's does.

**`SbRegDone` IS ABSENT.** The release puts it immediately after `SbRegInit`; `0297` is `SbRegInit`'s `RETF`, `0298..029b` is four bytes of literal, and `029c` is `SbGetDSPVersion`'s `ENTER`. No room, and nothing calls it. `SbRegInit` is otherwise the release's body with both of its commented-out blocks — a seven-line DSP handshake and a four-line hi-speed block — leaving no trace.

**A BLOCK BOUNDARY THAT SWALLOWS THE NEXT ROUTINE'S LITERAL READS AS FOUR REAL DIFFERENCES.** `SbRegInit` measured `** 4 real` until its block was narrowed from `029c` to `0298`. Turbo Pascal emits a routine's literals immediately BEFORE its code, so a block must end where the next routine's LITERALS begin, not where its `ENTER` does. Same trap as `154d`'s `LoadModFileFormat`, where the `.WOW` literal sat five bytes ahead of the prologue — **twice in two segments, so it is worth checking the boundary before believing a small difference count.**

## ~~`19a0` IS STARTED — the first seven routines, 249 of 1,905 bytes, all exact~~

`SOUNDBLA.PAS` is no longer a declared stub. Seven routines went in on the first build, every one at shift +0 with zero real differences, and `v1.31b/block19a0.py` measures them (`verify.py` does not list `19a0` yet and must not until the other sixteen are in).

**IT PAIRS WITH `LIB/SOUNDBLA.PAS` AND STANDS TO `193a` AS `1723` STANDS TO `1084`** — a hardware unit called by a device unit. `census.py` counts 23 far returns and **not one printable string in 1,905 bytes**, which by itself says the release's `SbGetCopyrightString` and its `USES Debugging` are absent. The first block confirms it: 1.31's `SbWriteByte` is the release's asm body with the two `WriteSNum`/`WriteChar` debug calls removed, and nothing else changed.

**THE PORT BLOCK IS CONFIRMED BY ITS SPACING, WHICH IS THE ONLY WAY IT COULD BE.** Every port is a typed constant, so its address is a DGROUP fixup and its value never appears in the `.TPU`'s code — nothing about it is measurable. What IS measurable is which addresses the instructions name: `$0afa`, `$0afc`, `$0b02`, `$0b04`. The release declares `DSPResetPort`, `DSPReadPort`, `DSPLifePort`, `DSPWStatPort`, `DSPWritePort`, `DSPRStatPort` consecutively — six Words spanning `$0afa..$0b04`, landing Reset/Read/Write/RStat on exactly the four observed addresses with Life and WStat filling the gap. **Six declarations predicting four addresses is not a coincidence**, and the same argument fixes the four configuration settings the old stub carried (`SbPort $0b14` through `SbHiSpeed $0b1c`, the release's list with no gaps).

**AND A CONDITIONAL JUMP WITH A ZERO DISPLACEMENT IS A DELETED BLOCK.** `19a0:00c7` is `75 00` — a `JNZ` to the very next instruction. The release's `SbReadByte` has five lines COMMENTED OUT between its `JNZ @@ya` and the `@@ya:` label (a second `SbReadLoop` retry after poking `DSPLifePort`), and 1.31 has the same dead branch. This is the second instance in the tree; `109c:0021`'s `75 00` is already recorded, and the note there says "do not re-derive this". **It is a general reading, not a one-off: a `Jcc` that jumps nowhere is source that was commented out, not an optimiser artefact.**

Sixteen routines remain. The release's are heavily `ASSEMBLER`, so they transcribe verbatim per the standing rule and go faster than Pascal — but they must be read one at a time, which is why `19a0` will not go in in a single pass the way `154d` did.

## `154d` IS DONE — 3,920 of 3,920, 302 pending fixups

**The largest remaining segment, transcribed in a single pass.** All five routines byte-exact:

    MODLOADE  154d     3920  identical, 302 pending fixups

The tree is **2 byte-identical, 22 identical but for fixups, 0 mismatched**, and `coverage.py` computes **39,052 of 44,272 in-scope bytes, 88.2%**. **Three segments remain, 5,143 bytes**: `19a0` (1,905), `1000` (1,621), `193a` (1,617).

**THE METHOD THAT DID IT WAS WRITING ALL FIVE BODIES AT ONCE AND LETTING THE PER-BLOCK CHECK SORT THEM.** `ProcessPatterns` (1,250 bytes) and `LoadMod15` landed byte-exact on the first build with no adjustment at all; the other three were then diagnosed *positionally*, which is far cheaper than transcribing one routine per build. `v1.31b/block154d.py` is `block14b9.py` with a different block table and took two minutes to make. **On a segment with a good release counterpart, transcribe the whole unit and measure, rather than top-down one routine at a time** — the top-down rule is about SOURCE ORDER, not about how much to write before building.

Three things had to be measured. Each was found by asking where the divergent RUNS were, not where the first divergent byte was:

**1. NINETY-TWO BYTES OF DELTA DECODING THE RELEASE HAS NOT GOT.** `ProcessInstruments` agreed for its first 660 bytes and then diverged wholesale from `+0778`. What is there is a guarded running sum over the sample, in place — `Acc := 0; for j := 0 to Len-1 do begin Inc(Acc, Data^[j]); Data^[j] := Acc end` — which turns delta-encoded sample bytes into levels. **1.39b has a loop commented out at exactly that point** (a −128→−127 clamp), so the author was editing this region between the versions; the comment is not what 1.31 does and must not be used to guess it. The extra local is one `ShortInt` declared after `k`, and one byte plus alignment is exactly the two-byte frame difference (`ENTER $564` against `$562`).

**2. `TSong.Status` IS SIGNED.** `154d:0b4c` and `0b6a` are `CMP byte ES:[DI+59],n / JLE` — a signed byte comparison, where our `Byte` gave the unsigned `JBE`. Two bytes in `LoadMod`, and changing the field to `ShortInt` fixed both. **`14b9` and `164b` only ever compare it for EQUALITY or store it**, which is sign-independent, so neither could ever have seen it — the fifth interface detail settled only by a caller in another segment. Read from the bytes rather than taken from the release, which is the standing rule working rather than being bent.

**3. EIGHT MAGIC BRANCHES WHERE THE RELEASE HAS FOUR.** 1.31 tests each of `M.K.`, `FLT4`, `6CHN`, `8CHN` twice — once plainly, and once against a second constant that also sets the delta flag. That is the 395-byte tail. **The branch table was read off the stores rather than the disassembly**: one regex sweep for `26 c6 45 5d` (`FileFormat := n`), `26 c6 45 28` (`NumChannels := n`) and `c6 06 cc 03` (the flag) printed all ten arms and their values in one command, which is the same trick as `142f`'s dispatch table and `116e`'s far returns. The four delta magics are `M\0\0\0`, `F\0\0\0`, `6\0\0\0`, `8\0\0\0`, read out of the DATA image at file offset `$00daaa` immediately before `M.K.FLT46CHN8CHN` — and **declared BEFORE the plain four**, because Turbo Pascal lays typed constants down in declaration order and that ordering is what fixes which group is which.

**AND THE FLAG AT `DS:$03cc` IS A NEW GLOBAL WITH NO WRITER OUTSIDE THIS SEGMENT.** `LoadModFileFormat` clears it at `0c19` and four of its arms set it; `ProcessInstruments` is the only reader. It is declared privately in `MODLOADE.PAS` and named `DeltaSamples` for its role, rather than put in `VTGlobal` where it would look established. If `109c`'s switches or `11bb`'s config keys turn out to write it, move it and rename it to whatever sets it.

**TWO KINDS OF EVIDENCE, AND THE SECOND IS RISK 1.** The branch STRUCTURE is measured — every jump and store compares byte for byte. The magic constants' CONTENTS are not: a typed constant is initialised DGROUP data that never appears in a `.TPU`'s code, and each comparison reaches its constant through a fixup. So the four delta magics are read from the image and believed, not verified. Same class as `SongLoaders` in `14b9`.

### ~~`154d` IS NOW THE NEXT SEGMENT, AND ITS SCOUTING NOTE HAS BEEN OVERTAKEN~~ *(done; kept for the reasoning)*

The note below concluded that `154d` needed four kinds of scaffolding before its first byte was measurable — `14b9`, `165a`, a `TStream` stub, and the MOD record types — and that its bodies would not transfer from the release. **Three of the four are gone and the fourth objection was wrong.**

* `14b9` and `165a` are byte-exact, and the three entry points `154d` calls into `14b9` (`0352 GetInstrument`, `0404 GetTrack`, `04b6 GetPattern`) are three of the sixteen routines just finished.
* `TStream` and `TDosStream` came in with `14b9`'s `Load` and `LoadFName`. Objects' streams are proven in use, not stubbed.
* The MOD record types are now in `v1.31b/src/MODLOADE.PAS`. **They are the exception to "the release is worth nothing for DATA"**, because they are not DemoVT's data at all — they are the ProTracker file format, fixed outside both versions. The arithmetic was still checked rather than trusted: `TModFile31` is `20 + 31*30 + 1 + 1 + 128 + 4` = 1084 with `Magic` at 1080, and 1080 is exactly what `154d:0c27` reads as `Header + $438`.
* **And "every `Song.X(...)` in the release is a free function here" was WRONG.** `TSong` turned out to be an OBJECT; `Song.GetPattern(i)`, `Song.GetTrack(t)` and `Song.GetInstrument(i)` all exist and are byte-exact. The release's calls transfer as written. That objection was the whole reason the segment was deferred, and it came from the same mistaken "plain record" reading the `14b9` scouting corrected.

**THE ROUTINE MAP IS SEVEN ROUTINES WHERE THE RELEASE HAS FIVE**, and `census.py` finds exactly ONE far return in 3,920 bytes — `0f40 RETF 12`. So `LoadModFileFormat` is the only routine reachable from outside and every other one is NEAR: a unit with one exported procedure and a pile of implementation helpers, which is the release's shape exactly. `scan_funcs.py` finds five prologues (`0000 ENTER $e20`, `04e2 ENTER $564`, `09d7 ENTER $10c`, `0b72 ENTER $002`, `0bf7 ENTER $1000`) and the near-call targets add `06ae` and `0829` — **read the calls, not just the prologues**, for the third segment running. The release's five are `ProcessPatterns`, `ProcessInstruments`, `LoadMod`, `LoadMod15`, `LoadModFileFormat`; pair them against ADDRESS order before writing anything, and do not assume the two extra are extra rather than one of the release's split in two.

**AND MIND `census.py`'s FAR-CALL FALSE POSITIVES HERE.** Six of its twenty-one "targets" in `154d` decode to nonsense segments (`3bc0:31fb`, `8936:77fb`, `e903:76fb` and three more, all inside `0794..0895`). The scan looks for the `9A` opcode byte and that byte occurs in data and inside other instructions. Same rule as `disassemble_bytes` starting one byte late: **a byte-pattern hit is a candidate, not a finding.**

### `154d` IS SCOUTED AND IT IS *NOT* THE NEXT SEGMENT — *(superseded; see above)*

Scouted rather than started, and the scouting is the result. **The pairing with
`LIB/MODLOADE.PAS` is confirmed and its BODIES still will not transfer.**

**WHAT CONFIRMS THE PAIRING, three ways:**

* `TModFile31` is 1,084 bytes with `Magic` at offset **1080**, and `154d:0c27` reads
  `Header + 0438` — 1080 exactly. The record layout is the release's.
* `154d:0bf7` calls stream methods virtually — `MOV DI,ES:[DI] / CALLF [DI+10]` then
  `[DI+1c]` — so 1.31 loads through `Objects.TStream` just as 1.39b does.
* `.WOW` is a literal in both, and `154d:0c4d` compares it against `TSong+$1f`, which
  is the release's `Song.FileExt`. `SONGUNIT` already cites `154d:0c6d` and `0c7f` for
  `mffWow8` and `mffMod31M_K_`, from an earlier reading pass.

**WHY THE BODIES WILL NOT TRANSFER: 1.31 HAS FREE FUNCTIONS WHERE 1.39b HAS METHODS.**
The release's `ProcessPatterns` is built out of `Song.GetPattern(n)`,
`Song.GetTrack(t)` and `Track^.SetFullTrack(...)`. **CORRECTED: 1.31's `TSong` IS an
`OBJECT(TObject)` after all** -- see the `14b9` scouting note, where the constructor at
`14b9:0000` settles it. The claim that it is a plain record was made from call sites,
and a static method call is byte-for-byte a free-function call. The Feb-1993 remodelling
changed the LAYOUT, which still cannot be taken from the release; it did not introduce
the object. `154d:0030` is `CALLF 14b9:04b6`, a direct far call with
the Song passed as a parameter. **Every `Song.X(...)` in the release is an `X(..., Song)`
here.** The structure of each routine transfers; the code does not.

**AND IT DEPENDS ON TWO SEGMENTS THAT DO NOT EXIST YET.** Scanning every call `154d`
makes:

    14b9:0352, 14b9:0404, 14b9:04b6     three entry points -- VTSONG.PAS has 0352
                                        and does NOT have 0404 or 04b6
    165a:012a, 165a:07c0, 165a:08e2     three entry points -- no stub at all
    1642:0000                           ASCIIZ, which is done
    1ba1:...                            System

So `154d` needs: a `TStream` stub (Objects, which the tree has never needed), the four
MOD file record types, `TSongHeader`, two more entry points in the `VTSONG` stub, and a
new stub for `165a`. Four kinds of scaffolding before the first byte is measurable --
which is why the dependency order in the pick-up list now puts `14b9` and `165a` ahead
of it.

**TWO ENTRY POINTS THE SCANNER MISSED, and it is the same lesson as `142f`.**
`scan_funcs.py` reports five frames in `154d`; the near-call targets include `06ae` and
`0829`, both inside what looked like `ProcessInstruments`'s range. So there are at
least seven routines, not five. `142f` hid two frameless routines the same way. **Read
the calls, not just the prologues.**

### EVERY PAIRING IS NOW MEASURED RATHER THAN ARGUED, AND THREE OF THEM WERE WRONG

**`v1.31b/relmatch.py` compiles the 1.39b release and diffs its COMPILED CODE against
every 1.31 segment.** `tools/dosbox/vtbuild.py` already builds the release cleanly and
leaves 49 `.TPU` files in `build/vt`; this scores each of them against each segment by
how much of the segment is covered by 8-byte runs that appear in the unit. One run
ranks all 23 segments at once, which is what four sessions of hand-matching had been
doing one discovery at a time.

**IT IS CALIBRATED AT BOTH ENDS.** `1642` scores **100.0%** against `ASCIIZ` -- and
`ASCIIZ` is one of the two units that are BYTE-IDENTICAL, so 100% really is identical
code. `11bb` scores 40.4% against `VTCFG` and went in essentially verbatim, so **~40%
is the floor for "transcribe the release's body and it will work"**. Below 20% the
pairing may still be real: `12ba` scores 16.1% against `PLAYMOD` and that pairing is
one of the best-established in the project. **The score measures DIVERGENCE BETWEEN THE
VERSIONS, not whether the pairing is genuine.**

**IT VALIDATES ON ALL EIGHTEEN FINISHED SEGMENTS** -- every one picks its known
counterpart as first place, usually with a 5-10x gap to second. And it corrects the
"eight units with NO counterpart in LIB/" list, which was wrong about three of them:

| segment | ours | the release actually has | score |
|---|---|---|---|
| `1650` | `VTNOTES` | **`LIB/SONGUTIL.PAS`** | 71.1% |
| `1880` | `VTDOSMEM` | **`LIB/UMBUNIT.PAS`** | 65.5% |
| `1b54` | `VTRESID` | **`VTSPECIA.PAS`** (root) | 44.3% |

All three carry INVENTED names on the strength of having no counterpart, and all three
have one. **The standing rule says to adopt the release's names where the pairing is
confirmed by reading both bodies** -- so that is three renames to consider, each needing
the usual before/after check that a rename moves no byte. `1931`/`VTSHELL` and
`1065`/`VTSILENC` score 13% and 6%, which is consistent with them genuinely having none.

**AND THE REMAINING SEGMENTS NOW HAVE A MEASURED ORDER.** Highest score first, which is
the order of decreasing effort per byte:

| segment | bytes | release unit | score | note |
|---|---|---|---|---|
| `165a` | 3216 | **`LIB/SONGELEM.PAS`** | **65.1%** | the doc guessed `SONGUTIL`, which is `1650`. Highest score of anything untranscribed -- above `11bb`'s |
| ~~`116e`~~ | 1232 | `LIB/CMDLINE.PAS` | 59.5% | **DONE -- identical, one build** |
| ~~`165a`~~ | 3216 | `LIB/SONGELEM.PAS` | 65.1% | **DONE -- identical, two builds** |
| ~~`109c`~~ | 3296 | `VTCMD.PAS` | 42.1% | **DONE -- identical, five builds** |
| `154d` | 3920 | `LIB/MODLOADE.PAS` | 55.4% | |
| `17cf` | 2832 | `LIB/HEAPS.PAS` | 50.6% | in progress |
| `109c` | 3296 | `VTCMD.PAS` (root) | 42.1% | confirms the sibling reading |
| `14b9` | 2224 | `LIB/SONGUNIT.PAS` | 38.6% | still the unblocker for `154d` |
| `193a` | 1617 | `LIB/DEVSB.PAS` | 25.1% | |
| `19a0` | 1905 | `LIB/SOUNDBLA.PAS` | 16.6% | |
| `1000` | 1621 | none | 13.9% | noise; DemoVT's own program, as expected |

**THE MISTAKE THIS TOOL MADE FIRST IS THE ONE THIS FILE WARNS ABOUT TWICE.** Its first
version let a zero byte in the `.TPU` wildcard-match anything, the way `verify.py` does
for a pending fixup -- and **every segment scored 100% against every unit**, because a
`.TPU` is full of long runs of zeros. `verify.py`'s own header records that exact
failure twice, in the paragraph explaining why it does not rank by "fewest real
differences". It was made again within an hour of reading it. **A zero rule needs a cap
on the zeros every single time it is used**, and the cheap way out -- which is what
`relmatch.py` does -- is to drop the wildcards and shorten the window instead.

### AND THE `154d` VERDICT WAS OVERSTATED

Last session's note said `154d`'s bodies "cannot be copied from the release". Its 55.4%
is the third-highest score in the table, above `17cf`'s and well above `11bb`'s, so that
was too strong.

What is actually true: **every `Song.X(...)` method call becomes a free far call into
`14b9`**, because `154d` calls `TSong`'s methods STATICALLY -- which is what a
non-virtual method call is, and reads identically to a free-function call. That is ONE
construct repeated several times per routine, not a rewrite -- the pattern-conversion
loops, the note decoding and the magic recognition all transfer. The dependency on
`14b9` and `165a` is real and is why it still is not next; the difficulty of the code
itself is not.

### `11bb` PAID BACK INTO THE REST OF THE TREE, AND CONFIRMED A GUESS MADE BLIND

The config reader writes 34 variables, which makes it the best cross-check in the
program: every one of them is a global whose owner and width were settled elsewhere.

**FOURTEEN LANDED ON VARIABLES ALREADY DECLARED AT EXACTLY THOSE ADDRESSES** —
`GUSPort`/`GUSIrq` in GUS, `DoBassPower`/`DMAOffset`/`DesiredHz`/`SbSplTimeout` in
SoundDevices, `ForceLoopMod`/`CanFallBack`/`FilterOn`/`FilterOff`/`MaxOutputFreq` in
PlayMod, `TicksPerSecond`, `LowQuality`, and `ProgName` in VTShell (which the release
calls `ShellPath`). Fourteen independent addresses agreeing is not something a wrong
reading survives.

**AND `FilterIsOn` AT `$0348` IS A RETROSPECTIVE CONFIRMATION OF A BLIND DECISION.**
When `142f` was transcribed it produced two variables of that name — PlayMod's at
`$02cd` and ModCommands' at `$0348` — with **nothing in the tree reading the second**,
and ModCommands kept its copy in the implementation section so the two could not
shadow each other. That was reasoned from the hazard alone; the note said the
duplication might not even be intentional. `11bb:0b0e`'s `FilterIsOn` key writes
`$0348`. So the config file is what sets it, the duplication is real, and the caution
was right for a reason that had not appeared yet. **The variable then had to become
visible to exactly one more unit, which is safe precisely because PlayMod's stayed
private.**

Five globals moved from PlayMod's implementation to its interface and two from
ModCommands', and **both units still verify identical with the same fixup counts** --
which is the only proof that exporting a declaration moves nothing.

**TEN GLOBALS BELONG TO SEGMENTS THAT DO NOT EXIST YET** (`SbPort`, `SbIrq`,
`SbDMAChan`, `SbHiSpeed` from `19a0`; the four SB Pro mixer bytes from `193a`; the
three DAC ports; and ten tracker-level ones the release keeps in `VTGLOBAL.PAS`).
Those are declared in VTCFG and flagged at the declaration, which is risk 1 done
deliberately instead of by accident -- compare `DEVGUS`, where three globals sat in
the wrong unit and nothing could see it.

### AND THE PAIRING IS NOW PROVED BY COMPILATION, NOT JUST BY STRINGS

`11bb`'s first eight routines are the release's `VTCFG.PAS` body transcribed with no
adjustment, and all 2,170 bytes are byte-exact. The string-literal test said "same
unit"; the compiler has now said it. Three details worth carrying:

* **`11bb:0000..001f` IS A SET CONSTANT, and that is a new rule.** The segment does
  not start on an instruction boundary; the first 32 bytes are
  `01 02 00 00 01 00 ... 00 80`, a `set of Char` whose only members are #0, #9, #32
  and #255 — `KillSpaces`'s `ValidBlanks = [' ', #9, #0, #255]` exactly. `11bb:0035`
  loads it with `MOV DI,0 / PUSH CS / PUSH DI`. **So an untyped SET constant lives in
  the code segment just as a string literal does**, which extends the `PUSH CS` rule
  the docs had only for strings.
* **A ROUTINE'S LITERALS ARE EMITTED IMMEDIATELY BEFORE ITS CODE, IN SOURCE ORDER.**
  `0127..0130` holds the five one-character literals GetString and GetNum need;
  `0407..0442` holds GetBool's sixteen, in the sequence `S Y OUI DA POR TAMB ALSO
  TRUE VERD CIER 1 N PAS TAMP FALS 0` — which is 1.39b's declaration order. **Order
  matching is far stronger evidence than sixteen names matching**, and it is free.
* **GetBool accepts four languages, and GetNum can read arbitrary memory.** The words
  are Spanish, French, German and English (`S`/`N`, `OUI`/`PAS`, `ALSO`, `VERD`,
  `CIER`, `TAMB`, `TAMP`, `FALS`), matched as PREFIXES via the double-negative `not
  NotInStr`, so `Yes` and `Y` both pass. And GetNum's second syntax, `[ssss:oooo]`,
  dereferences that address and returns the LongInt there — a config file that can
  read memory. Harmless in a tracker; in a player embedded in a demo it is a way for
  the host to hand values in.

### THE RELEASE'S ROOT DIRECTORY PAIRS TOO, AND `11bb` IS `VTCFG.PAS`

Every pairing in this project so far came from `v1.39b/LIB/`, and the
working assumption was that the root-level `VT*.PAS` files are the TRACKER
program's own units and would not pair with a demo player. **That assumption was
wrong, and one measurement settles it.**

`VTCFG.PAS` (476 lines, "Implements the reading of the VT.CFG configuration file")
has 52 distinctive string literals. **Forty-one of them appear verbatim in segment
`11bb`, and `11bb` contains essentially nothing else** — its complete string
inventory is `VTCFG`'s keyword list plus `VT.CFG` and `.CFG`:

    nobf-free keys:  Port SbSplTimeout HiSpeedDMA IRQ MasterVol DACVol FMVol Filter
                     LPort RPort PermitFade FadeSpeed LoopMod ForceLoopMod
                     ShellLoopMod SampleFreq TicksPerSec ShellFreq MaxFreq Volume
                     Device FilterOn FilterOff FilterIsOn CanFallBack FilterChange
                     BassFilter DMAOffset LowQuality ShellPath ShellParams Language
                     ModPath
    booleans:        TRUE FALS VERD CIER TAMB TAMP ALSO

Those last five are the Spanish forms — `VERDAD`, `CIERTO`, `TAMBIEN`, `TAMPOCO`,
`FALSO`, truncated to four characters — and they are in `VTCFG.PAS` character for
character. **Only three keys are missing from `11bb`: `ForceEGA`, `Line` and
`TmpPath`**, which are precisely what a headless player drops (a video mode, a mixer
line input, a swap path).

**WHY THIS WORKS AS A TEST, AND WHAT IT CANNOT DO.** Turbo Pascal puts an untyped
string constant in the CODE segment — that is the `PUSH CS` rule `VTRESID` turned up
— so a segment carries its unit's literals verbatim and a string comparison is a
one-way instrument: **a high score is strong evidence of a pairing; a low score is
no evidence at all**, because most units have no literals to share. Run over all ten
untranscribed segments against all 60 release sources, exactly two scored:

    11bb  4080   VTCFG.PAS    41 unique hits of 52 literals   -- the same unit
    109c  3296   VTCMD.PAS     6 unique hits of 11 literals   -- a sibling, see below
    the other eight               no literal from any release source

### SO THE REMAINING TEN HAVE CANDIDATES, AND THEY ARE WORTH READING FIRST

Ranked by how much the pairing rests on measurement rather than role:

| segment | bytes | candidate | strength of the evidence |
|---|---|---|---|
| `11bb` | 4080 | `VTCFG.PAS` | **41 of 52 literals, and nothing else in the segment.** Effectively settled |
| `17cf` | 2832 | `LIB/HEAPS.PAS` | **Already confirmed from the other side**: `12ba:1263` is `CALLF [DI+8]` on the object at `$39ae`, and `MOV DI,[DI]` proved `OBJECT(TObject)`. `HEAPS.PAS` is the stub the tree already carries |
| `116e` | 1232 | `LIB/CMDLINE.PAS` | **MEASURED at 59.5%**, and the role fits precisely: CmdLine is "a workframe for a command line options interpreter" and provides `GetDOSCmdLine`, which is the map's "PSP:$0080, tokeniser, 4-char keyword matcher" |
| `109c` | 3296 | `VTCMD.PAS` (SIBLING) | 6 shared 4-char switch tokens, and `VTCMD` is `OBJECT(TCmdLineInterpreter)` with a chain of `CmpSwitch(Token,'nobf')` tests. DemoVT implements a SUBSET, so expect a design match, not a line-for-line one |
| `193a` → `19a0` | 1617, 1905 | `LIB/DEVSB.PAS` → `LIB/SOUNDBLA.PAS` | Structural, and strong: `1084` → `1723` is confirmed as `DEVGUS` → `GUS`, a device unit calling a hardware unit. `DEVSB` → `SOUNDBLA` is the same pair for the other card and the segment map already records the same call direction |
| `154d` | 3920 | `LIB/MODLOADE.PAS` | **CONFIRMED** — `TModFile31`'s `Magic` at offset 1080 matches `154d:0c27`, both load through `TStream`, `.WOW` shared. But the BODIES do not transfer and it depends on `14b9` and `165a`; see the scouting note |
| `14b9` | 2224 | `LIB/SONGUNIT.PAS` | Role, with a WARNING already in this file: 1.39b's `TSong` was remodelled in Feb 1993 and its LAYOUT must not be taken. Names and shapes only |
| `165a` | 3216 | **`LIB/SONGELEM.PAS`** | **MEASURED at 65.1% by `relmatch.py`** — the highest score of any untranscribed segment. `SONGUTIL` is `1650`, not this |
| `1000` | 1621 | none | DemoVT's own program. `VTMAIN.PAS` is written and blocked; the release ships the TRACKER's `VT.PAS`, which is a different program |

**THE LESSON IS ABOUT WHERE TO LOOK, NOT ABOUT `11bb`.** For four sessions the
search space was `LIB/` because that is where the confirmed pairs were, and
`v1.39b/VTSHELL.PAS` had been checked once, found not to be `1931`, and
written up here as a caution — which quietly hardened into "the root does not pair".
One directory listing and one string comparison overturned that. **A negative result
about one file is not a result about its directory.**

### The file mapping

| release | segment | our unit |
|---|---|---|
| `LIB/SOUNDDEV.PAS` + `.ASM` | `1a17` | `SOUNDDEV` |
| `LIB/GUS.PAS` | `1723` | `GUS` |
| `LIB/DEVGUS.PAS` | `1084` | `DEVGUS` |
| `LIB/HARDWARE.PAS` | `1b24` | `HARDWARE` |
| `LIB/ASCIIZ.PAS` | `1642` | `ASCIIZ` |
| `LIB/FILTERS.PAS` | `1544` | `FILTERS` |
| `LIB/UNKLOADE.PAS` | `164b` | `UNKLOADE` |
| `LIB/FILEUTIL.PAS` | `116a` | `FILEUTIL` |
| `LIB/SONGUNIT.PAS` | — | `SONGUNIT` (the record and both enums) |
| `LIB/PLAYMOD.PAS`/`.ASM`, `MIXROUTS.INC` | `12ba`? | not transcribed |

**THERE IS ONE RENAME SWEEP OUTSTANDING, AND `PlayStart` IS WHAT CONFIRMED IT.** Transcribing `12ba:10a1..132c` put our names and the release's side by side for twelve of `PLAYMOD`'s globals, in the same statements, in the same order — which is the "confirmed by reading both bodies" the rule asks for:

| ours | release | fixed by |
|---|---|---|
| `RangeStart` | `MyFirstPattern` | `10b4` |
| `RangeEnd` | `MyRepStart` | `10ba`, `1117`, `1184` |
| `OrderLen` | `MySongLen` | `10c0`, `10cd` |
| `PlayPos` | `NextSeq` | `10de`, `10e6`, `10ec` |
| `PlayRow` | `NextNote` | `115e` |
| `CurSpeed` | `Tempo` | `1143` |
| `CurTempo` | `BPMIncrement` | `114d` |
| `TickInRow` | `TempoCt` | `113e` |
| `ModFlag` | `DelaySamples` | `1164` |
| `ReqStart` | `FirstPattern` | `10b4` |
| `ReqEnd` | `RepStart` | `10ba` |
| `ReqLen` | `SongLen` | `10c0` |

Two of them collide with names already in the tree — the release's `Tempo` is also a field of `TPlayingNote`, and its `BPMIncrement` sits where our `CurTempo` reads more plainly — so those two need a decision rather than a substitution. **Not done, because a rename must be a change of nothing else**: do it as its own pass with `verify.py` and `blocks.py` before and after, and the check is the same region and difference counts to the byte.

**THE EARLIER RENAME WORK LIST IS FINISHED.** All nine pairings are renamed — file, unit, routines, globals, and parameters and locals where the release's spelling is confirmed. `verify.py` was run after each one and every unit reported exactly what it had before, which is the only proof a rename moved nothing.

The eight units with NO counterpart in `LIB/` keep their invented names, and there is nothing to look up for them: `VTCTRL`, `VTDOSMEM`, `VTDOSRSZ`, `VTSHELL`, `VTSILENC`, `VTRESID`, `VTDRIVER`, `VTMAIN`. (`v1.39b/VTSHELL.PAS` exists but is the tracker's own shell, not `1931`; do not pair them without reading both.)

Renaming a unit means editing `build.py`'s `ORDER`, `verify.py`'s `UNITS`, every `uses` clause and qualified reference in the other units, and the mentions in `06-transcription.md` and this file. Delete the old `.TPU` from `build/` afterwards or the stale one lingers.

### The renames found four things a rename should not have found

None of these are cosmetic, and none would have been noticed by reading our side alone.

**`1084:0101` is the unit's INITIALISATION SECTION, not an exported procedure.** It had been transcribed as `procedure Register; far;` in the interface, with a separate `begin Driver.DevID := 'GUS' end.` init block underneath. The release has no such procedure: it fills the record and calls `InitDevice` in its own `BEGIN ... END.`, and it initialises the ID as part of a typed constant. Nothing in our tree ever called `Register` either. Rewritten that way the unit compiles to **376 bytes instead of 402** — the init block's 26 bytes of code were never in the original — and the comparison is still identical with the same 106 fixups. The unit's code now matches its segment exactly.

**`DEVGUS` declared three globals another unit already owns**, and one was serving TWO different addresses at once. `Callback : Pointer` was commented `DS:$4312` while the assignment through it was commented `-> DS:$058e`; the CALL at `1084:003a` really does reach `SoundDevices.PeriodicProc` at `$4312` and the store at `1084:008a` really does reach `GUS.GUSTimer2RutPtr` at `$058e`. `SavedSS`/`SavedSP` at `$4302`/`$4304` were likewise duplicates of `SoundDevices`'. **Every reference to a global is a linker fixup, so `verify.py` could not see any of it** — the bytes agreed either way. The release settles it, and both are now referenced where they live. This is risk 1 in miniature, and the first evidence of what that risk looks like in practice.

**`FILTERS`' "strength" is an enum of CUT-OFF FREQUENCIES.** The selector tested 3, 2, 1 against three kernels, which reads as a strength running backwards; it is `ORD(fm1_2)`, `ORD(fm3_4)`, `ORD(fm7_8)` of the release's `TFilterMethod`, in the order the kernels sit in the segment, with `fmNone = 0` falling through. Same bytes, and the code now says what the numbers mean.

**`SONGUNIT`'s LAYOUT CANNOT BE TAKEN FROM THE RELEASE, and nearly was.** 1.39b's `TSong` is a `TObject` descendant whose first two fields are `SongStart` and `SongLen`, which would map onto 1.31's `+$02` and `+$04` — the two words a constructor sets to 1 and `$100`, a speed and a tempo. The release's own history block explains why: *"06-Feb-1993 Remodelling. Made the memory-optimized, object-oriented interface."* The unit name, `PSong`, `TSong` and every `ms`/`mff` constant are adopted; the field layout comes from the disassembly. Only `Format` was renamed, to `FileFormat`, and on role rather than position.

---

## What actually causes a divergence

Twenty-four patterns, all in `06-transcription.md` with detail. The ones that recur:

- **`Port[X]` with a computed index is not Pascal.** It compiles to `MOV DX,[X] / OUT` only when X is a bare variable or constant. `GUSPort + $103` goes through AX. **`Port[X + $00]` counts as computed** — the `+ 0` costs three bytes and reorders the instructions.
- **`assembler` vs an `asm` block inside a normal procedure.** An `assembler` procedure naming no parameter gets NO frame. And it always gets an epilogue, so a written `RET` emits a second one.
- **Do not declare locals the original does not have**, and **declaration ORDER sets the frame**. A `Word` declared early shifts every `[BP-n]` below it, and a `Word` is WORD-ALIGNED, so three preceding bytes become four. A larger `ENTER` than your locals explain is usually a compiler temporary, not a missing variable. **The frame SIZE agreeing proves nothing** — four bytes plus a word and three bytes plus a word both `ENTER 8,0`; check the offsets one at a time. Turbo Pascal never reuses a dead local's slot, so two writes to the same `[BP-n]` are the same variable, however unrelated they look.
- **READ THE JUMP TARGET BEFORE DECIDING WHAT A BRANCH ENCLOSES.** This was the single most productive habit in `12ba` — six statements' shapes came from it and nothing else:
  - `0cc9` jumps thirteen bytes, so only the `mod` is guarded and the row test below it is unconditional. Nested, the jump would have to clear both.
  - `0e22` lands ON the volume clamp, not past it, so the clamp is common to both branches rather than part of the second.
  - `0eb3` lands past three more statements, so the `else` silences the channel as well as setting the period.
  - `0d47` jumps BACKWARDS to `0d1a`, so what looked like a tautology (`X := A; if X = A then`) is a `while` head. **A note calling that dead code was written and then withdrawn one iteration later** — read the closing jump before calling anything dead.
  - `1073` is `JNZ +2 / JMP <epilogue>`, an early `Exit`, where a wrapped `if` gives one folded `JZ`.
  - `1125` lands on the second operand's test, so `(True and A) or B` rather than `True and (A or B)`.
- **An IMMEDIATE where you expected a memory read means an UNTYPED constant.** `12ba:1121` is `MOV AL,1`; `ForceLoopMod`'s test eight bytes later is `CMP [02c9],0`. An untyped Pascal `const` folds to a literal, a typed one stays in DGROUP. So the release's `LoopMod : BOOLEAN = TRUE` is not what is being read there.
- **HAND-WRITTEN ASSEMBLER HAS FOUR RELIABLE TELLS in a compiled routine**, and `12ba` has ten such blocks:
  - **The pointer register.** Turbo Pascal's code generator uses DI for every dereference it makes. `LES SI,...` is somebody's hand.
  - **The direction bit.** `21 C9` for `AND CX,CX`, `20 C0` for `AND AL,AL`, `09 C0` for `OR AX,AX` — the inline assembler's encodings, which the code generator does not emit. See the encoding table in `06-transcription.md`.
  - **Instructions the compiler never emits**: `LOOP`, 8-bit `MUL BL` with the high byte taken as a shift, rounding division (`ADD DX,DX / CMP DX,BX / JC / INC AX`).
  - **`MOV DI, WORD PTR Raw`** on a `var` parameter — loads the offset half, so stores through it are DS-relative and correct for a DGROUP argument. Note `MOV DI,Raw` alone is Error 155; the `WORD PTR` is required.
- **A BASE-1 ARRAY SHOWS UP AS A BASE ONE ELEMENT LOW.** `IMUL DI,[idx],$26 / ADD DI,$123a` with the array really at `$1260` is `array[1..8]` of a 38-byte record. Six arrays in `12ba` were identified this way — `Canales`, `RawChannels`, `NoteBuff`, `Buffers`, `UserVols`, `SplBuf`, `Permisos` — and it is now reliable enough to use as a rule rather than a discovery.
- **ARGUMENT WIDTHS AND RESULT WIDTHS COME FROM THE CALL SITE.** `MOV AL,x / XOR AH,AH / PUSH AX` means the parameter is a `Word`; without the zero-extension it is a `Byte`. And `09 C0` (`OR AX,AX`) on a result means the FUNCTION returns a Word even when the value is then stored into a Byte — `08 C0` would be the Byte form. Three stub signatures in `VTSONG.PAS` were corrected this way, each by one or two bytes.
- **`P^.Field` INSIDE `with P^ do` IS NOT THE SAME AS `Field`.** The explicit form reloads the pointer; the short form uses the with-slot. `12ba:0a4d` and `12ba:0abd` are ten instructions apart and the original wrote one each way.
- **A hidden four-byte frame slot plus `LES DI,[BP-n]` on every field access is a `with`.** Turbo Pascal implements `with <indexed record>` by computing the address once — `ADD DI,OFFSET Base / MOV [BP-4],DI / MOV [BP-2],DS`, storing the register it accumulated the offset in and then DS — and reloading it inside the block. Written as a pointer local instead, the same source gives `LEA AX,[DI+Base] / MOV DX,DS / MOV [BP-4],AX / MOV [BP-2],DX`, because an assignment needs a pointer VALUE and a `with` never forms one. Four bytes, and it also explains the frame: the slot is the compiler's, so **the routine declares no local at all**.
- **Assign to the function identifier, not to a local.** Borland allocates the result at the top of the frame; a separate `Ok : Boolean` gets its own slot and everything shifts.
- **`for` vs `while`/`repeat`.** Borland's FOR opens `MOV var,0 / JMP past / INC var / body`.
- **An early `Exit` is the wrong shape** — it gives `JNZ +2 / JMP` where a wrapped `if` gives one `JZ`.
- **`$G` is per-unit.** `188f` needs `{$G-}` and everything else needs `$G+`. One byte, `POP BP` against `LEAVE`, and it cost several sessions because a whole-tree `$G-` test wrecks twelve units and looks like a refutation.
- **A written `RET` in a far `assembler` procedure becomes `RETF`**, and TP picks the other direction for `SUB`/`ADD`/`AND`/`XOR` between registers than 1990s assemblers do. That trap has been hit eight times in three files; it is the single most productive thing to check first when hand assembler will not match.
- **Segment size is not code size.** Several segments end in padding. Check before chasing a tail difference.

### The divergences that were NOT source shape — there are none left

Down from six, then three, then none. **Every one of them was eventually ours or a switch. Assume the same of the next one before parking it.**

- **There is none.** `1a17:070f` was the last, and it fell to the probe: the original's `CALL / MOV BX,DMABufferSize / SUB BX,AX / MOV [BP-6],BX` is not code generation at all. `SUB BX,AX` is `29 C3` there, the direction TP's INLINE ASSEMBLER emits and its code generator does not, so those four instructions are hand-written — as the dead `MUL DX / PUSH AX` immediately above them already was. Transcribed verbatim into the same `asm` block, they match.

  **That was the strongest single argument in the tree that the compiler was not ours, and it was a transcription error.** Four instructions, held for several sessions as a property of a code generator.

---

## `docs/04-units.md` IS WRONG IN SIX PLACES ON `12ba`

The line-by-line pass got the structure of that segment substantially right and
the details wrong in ways only byte comparison caught. **Do not trust its `12ba`
prose over the transcription in `PLAYMOD.PAS`**, and expect the same class of
error in the segments it describes that have not been transcribed yet.

* **`12ba:0187`'s middle is a `for` loop, not a nested `if`.** `MOV [02ee],0 / JMP
  past / INC [02ee]` is Borland's FOR; the note reads the `INC` as an `else`
  branch. So `$02ee` is a loop variable over a row's eight entries, and the rename
  flag is tested unconditionally rather than inside the wrap.
* **`12ba:0275` writes `Pan` UNCONDITIONALLY on the merge path.** The note has it
  inside the `Freq <> $FFFF` test. The `JZ` jumps ten bytes — the `Freq` store
  alone, not the twenty the pair needs. **A caller cannot leave the pan alone by
  passing `$FFFF` for the frequency**, which is a behavioural difference.
* **`DS:$034e` counts TICKS WITHIN A ROW, not rows.** The note calls it "the
  current row". `12ba:0cdf` compares it against `NoteProcessed^.Tempo` — ticks per
  row — and `0cf7` resets it. A row number would not reset.
* **`12ba:0cd8` compares against `NoteProcessed^.Tempo`, not `Pattern^[1]`.** The
  note is wrong on both sides of that comparison.
* **The buffer's first byte means "already produced", and the sense is inverted.**
  The note says `12ba:0b29` "gives up immediately if it is zero"; `0b57` is `74 03`,
  a `JZ` over the exit, so it gives up when NON-zero, and `0bfe` sets it. Confirmed
  twice over: the field is `SoundDevices.TSampleBuffer.InUse`, "set while the
  device is playing it".
* **The 11-byte records at `$1394` are NOT a module table.** They are
  `SoundDevices.TSampleBuffer`, already declared in `SOUNDDEV` with exactly those
  offsets, and the two "enumerator" routines are the driver's buffer callbacks —
  `SoundDevices.TAskBufferProc`. This was transcribed as an invented `TModEntry`
  with the offsets right and every name wrong before `12ba:1049`'s signature gave
  it away. **Before inventing a record, grep the tree for its size and offsets.**

## Still deliberately open in the READING

Four things the line-by-line pass left unnamed rather than guessed. None blocks the byte-exact work.

- ~~**`14b9:+$3d`**~~ — **CLOSED FROM THE CONSUMER'S SIDE: it is a per-order-position SPEED OVERRIDE.** The note said "what it holds is not determined by its accessor", which was true of `14b9:05d3` read alone. `12ba:08ad` calls it and does `if it <> 0 then CurSpeed := it`, choosing between it and the pattern's own speed byte depending on whether this is row 1. The table itself is still called `Table3D` in `SONGUNIT`; rename it when 14b9 is transcribed and the two ends can be read together.
- ~~**The voice record's `+$1d` byte**~~ — **CLOSED: it is the VOLUME.** `LIB/PLAYMOD.PAS`'s `UnCanal` passes `Raw.Volume` in that argument position, and the silent call at `12ba:012c` passes a literal `0` there, which only makes sense for a volume. The same reading corrected `+$19`/`+$1b`, which the pass had called "sample position, low word of a 16.16" and which are the STEP — `StepFrac`/`StepInt`. The position is `+$01`/`+$03`. Same arithmetic either way, which is why reading alone could not separate them.
- **`1891`'s provenance** — that it *is* `Objects` is well supported (`17cf` calls `ForEach` and `FirstThat` with real TP7 nested-procedure closures; `14b9` reads `Count` at `Coll+6` independently confirming the VMT`+0`/Items`+2`/Count`+6` layout). That it is **Borland's** `OBJECTS.PAS` rather than a JCAB work-alike still rests on the `89E5` prologue being explained by the unit shipping as source.
- **`$16..$24` in `TSong`** — written by `14b9:0106` out of `FSplit`, so the path and the file name live there. Naming them needs the declared `String` sizes, and `14b9:0106` is not transcribed. Filler on purpose.

---

## What `12ba` GAVE BACK to the rest of the tree

Transcribing a segment turns out to settle things about its neighbours, which is
an argument for doing them in dependency order rather than size order.

* **The INT 2Fh control block is richer than the unit that publishes it could
  show.** `VTCTRL` owns it and sees almost nothing; `12ba` uses three parts of it.
  `CB+$203/$204/$205` are the seek request (already named); `CB+$125` is a 32-bit
  TICK COUNTER, incremented every tick (`12ba:0c9a`), now `Ticks32`; and `CB+$206`
  is a **MASTER VOLUME** — every channel's volume is multiplied by it and the high
  byte taken (`12ba:0e66`), so `$FF` is unity and a client can attenuate the whole
  mix. `VTCTRL` called it `Mark` because all it could see was `Reset` writing `$FF`.
  Renamed `MasterVol`, and `VTCTRL` still verifies identical.
* **`SONGUNIT` gained confirmed fields**: `Len37` at `+$37` (a Word where there was
  filler), and `TSampleDesc` grew `Volume` at `+$0c`, `PeriodMul` at `+$0e` and
  `PeriodDiv` at `+$10` — all fixed by stores or reads in `12ba`.
* **`FILTERS`' signature was independently corroborated.** `12ba:0be3` passes five
  arguments in the order `FilterChunkWord(var Buf; Len, Offs : Word; Method;
  OldSpl)` expects, with the channel count arriving as `Offs` — the interleave
  stride. That signature was originally derived from `1544`'s own frame, so two
  independent derivations agree.
* **`SOUNDDEV`'s `TSampleBuffer` and `TAskBufferProc` are what `12ba:1049`/`105d`
  are**, which is how an invented record got removed from the tree.
* **`SOUNDDEV`'s `DMAChannel` IS A WORD, and 12ba is what proved it.** It had been
  declared a `Byte` here on the strength of `1a17:06ea`, which loads it with
  `MOV AL,[DMAChannel] / PUSH AX` and no zero-extension. That reading was right
  about the argument and wrong about the variable: `12ba:13ae` is
  `81 3E C4 0B FF 00`, a six-byte WORD compare against `$00FF`, where a Byte gives
  the five-byte `80 3E C4 0B FF`. The truncation is at the call — `GetDMACount`
  takes a Byte — not in the storage. Changed, and `SOUNDDEV` still verifies
  identical with the same 1,024 pending fixups. **A variable's width is settled by
  its widest access, and one unit's call site is not evidence about another's.**
* **`RawChannels` IS AT `$13a6`, NOT `$1384` — `$1384` IS THE BASE-1 BASE.** The
  note here had recorded the base as the array's address. `12ba:12ba` settles it in
  one instruction: `FillChar(RawChannels, SIZEOF(RawChannels), 0)` passes `$13a6`
  and `$0110`, and `$0110` is 272, which is 8 x 34.
* **`MaxChannels` IS 8 AND THE MULTIPLICATION PROVES IT.** `12ba:1224` computes
  `MaxSplPerTick * MaxChannels * 2` as `SHL AX,3 / SHL AX,1`. The PAIR of shifts is
  what fixes the 8; the release's `MaxChannels` is 32.
* **`LoopMod` AND `MyLoopMod` ARE TWO VARIABLES AND THE TREE HAD ONLY ONE.**
  `$0334` is the release's `MyLoopMod`, the working copy — its assignment at
  `1121..113d` is the release's line character for character, including the
  commented-out operand that is why a literal `1` is tested there. The client's
  `LoopMod` is `$02c8`, a typed constant adjacent to `ForceLoopMod` at `$02c9`,
  which is the release's declaration order again. **Nothing in 1.31 reads `$02c8`**:
  the initialisation section clears it and no other instruction touches it, because
  the operand that would have read it is commented out. That is where the stray
  `True and` comes from, and now both halves of the pair are accounted for.

## THE RELEASE PAID FOR ITSELF REPEATEDLY IN `12ba`

Worth stating plainly for whoever does the next segment: **read the counterpart in
`v1.39b/LIB/` before writing a line.** In this segment it supplied

* `TModRawChan`'s eighteen fields, `TCanal`'s head, `TFullNote`, and
  `TPlayingNote`'s complete 63-byte layout — every one landing on offsets the
  binary independently confirms;
* about twenty global names, several of which arrived **in the release's own
  declaration order** (`ActualHz`/`NoteHz`/`NoteCalcVal` at `$1200`/`$1202`/`$1204`;
  `NoteTl`/`NoteHd`/`NoteSound`/`NoteProcessed` at `$02d4`/`$02d6`/`$02d8`/`$02dc`),
  which is far stronger evidence than any single name matching;
* `MyMove` **instruction for instruction** — the closest pairing in the project;
* the CALLING CONVENTION for `142f:063f`, in a Spanish comment: *"En las del tick,
  se entra con SI apuntando al TCanal correspondiente."*

And it was wrong exactly where the standing rule says it will be: `TSong`'s
layout, `TPlayingNote`'s SIZE (32 bytes there, 63 here, because `MaxChannels`
differs), `TCanal`'s tail (it grew S3M fields), and the number of resampling
kernels (two in 1.39b, one with a Boolean argument in 1.31). **Shapes and names,
never data.**

## A SIGNATURE CAN BE WRONG IN A UNIT THAT IS ALREADY BYTE-EXACT, AND ONLY A CALLER FINDS IT

`GUS.PAS` declared `DumpToUltrasound(Src : Pointer; ...)` and verified identical for its whole life. It is wrong: the parameter is an untyped `var Src`, which is also the release's declaration.

**NOTHING INSIDE THE ROUTINE COULD HAVE FOUND IT.** A `Pointer` parameter and an untyped `var` parameter are the same four bytes in the frame, and the body's `LDS SI,Src` loads the same address from either. The two differ only where the argument is *pushed*: `165a:02b0` reads `LES DI,ES:[DI+16] / PUSH ES / PUSH DI`, which is how a var parameter is passed, where a `Pointer` argument compiles to two word pushes and costs two bytes more. Changed, and **`GUS` still verifies identical with the same 542 pending fixups.**

This is the third time. `VTDOSRSZ`'s `SetMemTop` took two Words instead of a Pointer; `VTDOSMEM`'s five routines carried invented names; now this. **A unit measuring perfect says its BODIES are right, not its INTERFACE** — and the interface is only tested when another segment calls it. Expect more of these as the remaining seven segments land, and treat each new caller as a test of what it calls.

## A DISPLACEMENT THAT DISAGREES IS A LENGTH, NOT AN ERROR

`165a`'s first build reported "agrees to +0140 of 0c90 (9%)" and the segment is 3,216 bytes. That reads like a catastrophe and it was nearly finished: `0140` holds the low byte of a `JMP` displacement, `e9 34 02` against our `e9 e1 01`, and the difference is 0x53 — **so the original's routine was 83 bytes longer and every byte after the jump was already correct.**

**A JUMP DISPLACEMENT ENCODES EVERYTHING DOWNSTREAM OF IT**, so it is the first thing to disagree whenever a routine's length is wrong, however far away the real cause is. Two things follow:

* **Subtract the two displacements before reading anything else.** The difference is a byte count, and it tells you how much code is missing or extra without locating it.
* **Diff the routine BACKWARDS from its return with that difference as the alignment.** `165a`'s tail agreed for 189 bytes that way, which put the insertion point within one byte. Forwards, `verify.py` stops at the displacement and shows nothing.

The complementary trap: a forward diff that breaks at the first mismatch reports the displacement and stops. Collect ALL the differences in the routine instead — the ones that are pure displacement changes are noise, and the first one that is not is the answer.

## AND A SCANNER'S OWN BUG READ AS A FINDING: 16-BIT MODRM IS NOT THE REGISTER NUMBER

`census.py`'s virtual-call scan reported ZERO sites in `116e` and in `165a` when both are full of them. The regex looked for `ff 5f` as `CALLF [DI+disp8]`, which is the natural guess from 32-bit encoding and is wrong: in 16-bit ModRM the `rm` field is an addressing MODE, not a register, and `FF /3` gives `0x58 + rm` with `100 = [SI]`, `101 = [DI]`, `110 = [BP]`, `111 = [BX]`. **`ff 5f` is `[BX]`. `[DI]` is `ff 5d`.**

A real virtual call looks like `26 8b 3d ff 5d 14` — `MOV DI,ES:[DI]` to fetch the VMT pointer from the object's offset 0, then `CALLF [DI+slot]` with no prefix because the VMT itself is in DGROUP.

**AN EMPTY RESULT FROM A NEW SCAN IS NOT EVIDENCE OF AN ABSENCE.** It was nearly read as "165a makes no virtual calls", which would have been a finding about the binary rather than about the regex. Validate a new scan against a segment whose answer is already known — `116e` has exactly eight sites and was the test that caught this. And when a scan does return hits, check what precedes each one: all twenty-two of `165a`'s turned out to share the same five-byte preamble, which is what confirmed none was a false positive.

## TWO NEW DECLARATION-ONLY UNITS, BECAUSE A SECOND CALLER EXPOSED A PRIVATE GLOBAL

`VTCFG.PAS` declared fourteen globals privately — it was the only unit that touched them. `109c` writes the same settings from the command line that `11bb` writes from the config file, and a private declaration cannot be shared, so they moved:

| unit | holds | why |
|---|---|---|
| `v1.31b/src/VTGLOBAL.PAS` | `PermitFade`, `VtVolume`, `ShellLoopMod`, `ShellHz`, `FadeIncr`, `VTLoopMod`, `ShellParam`, `DevID`, `StringsFName`, `ModPath`, plus `109c`'s `DevPtr`, `VT1stPattern`, `VTSongLen`, `VTRepStart`, `ModOffset`, `NoBanner`, `Rut_0bc6` | the release has a real `VTGLOBAL.PAS`; no segment of its own, declarations only |
| `v1.31b/src/SOUNDBLA.PAS` | `SbPort`, `SbIrq`, `SbDMAChan`, `SbHiSpeed` | a DECLARED STUB for segment `19a0`. **Start `19a0` from this file** |

**`VTCFG` STILL VERIFIES IDENTICAL WITH THE SAME 871 PENDING FIXUPS**, which is the expected result and worth stating plainly: a DGROUP reference is a linker fixup, so **where a global is declared cannot change a byte of the code that uses it.** That is also exactly what makes the choice dangerous — the byte comparison cannot tell a right home from a wrong one — so every address in both files says how well it is known.

### AND ONE OF THOSE ADDRESSES WAS WRONG: `VTDir` WAS NEVER AT `DS:$09e8`

`VTCFG.PAS` carried `VTDir : PathStr { DS:$09e8 -- provisional }`. The variable is real — the unit's initialisation section fills it with the executable's directory — but that address belongs to `109c`'s no-banner Boolean, which `1000` tests one byte at a time.

**THE `09e8` VTCfg WAS LOOKING AT IS A CODE OFFSET, AND THE `PUSH CS` WAS THE TELL.** `11bb:0a00` reads `MOV DI,09e8 / PUSH CS / PUSH DI` — a far pointer to a string constant in VTCfg's *own code segment*, not a DGROUP address at all. A DGROUP pointer argument is `PUSH DS`; `PUSH CS` means the code segment, which is where untyped string and set constants live. The rule was already written down in this document and still got missed once. **When a scan turns up a DGROUP address, check which segment register is pushed with it before believing it.**

`VTDir` now says "no measured address", which is better than quoting one that belongs to something else.

## ~~The one open question~~ — RESOLVED, AND IT CHANGES HOW `verify.py` SHOULD BE READ

**THE ANSWER IS THE LINKER, NOT THE COMPILER: Turbo Pascal SMART-LINKS at the routine level when it builds the EXE, and `116e`'s two empty methods are the only two routines in the unit that nothing surviving refers to.**

The question was: `ParseLine` calls VMT slots +$24 and +$28 on `Self`, so `TCmdLineInterpreter` declares nine virtual methods, but segment `116e` holds only eight routine bodies and there is no room for more. `109c` settled it.

**FIRST, `109c` CONFIRMS THE BASE REALLY DOES END AT +$28.** The release has TWO descendants, not one — `TVTCmdSwitch` and then `TVTCmd` — and `TVTCmdSwitch`'s first ADDED virtual is `CmdInitShell`. `census.py` finds exactly one `CALLF [DI+2c]`, at `109c:0b7c`, immediately after the `[DI+1c]` (`TokenParam`) at `0b71` — which is `CmdInitShell(TokenParam(Token))` in the `'sh'` branch. **A new virtual at +$2c means the inherited ones stop at +$28**, so nine slots is not a miscount and `InterpretSwitch` is genuinely the base's ninth.

**AND THEN THE TWO OVERRIDES ARE EXACTLY THE TWO MISSING BODIES.** Follow the references:

| base method | slot | referenced by | in the EXE? |
|---|---|---|---|
| ParseLine, ParseFile, `Rut_0110`, GetToken, CmpSwitch, TokenParam, Abort | +$08..+$20 | `TVTCmd`'s VMT — none of them is overridden — and `Rut_0110` also by a direct call at `109c:083d` | kept |
| **InterpretNoSwitch** | +$24 | `TVTCmd` overrides it, so `TVTCmd`'s VMT points into `109c` | **nothing** |
| **InterpretSwitch** | +$28 | `TVTCmdSwitch` overrides it, so the VMT points into `109c` | **nothing** |

`TCmdLineInterpreter` is never instantiated — `109c` declares the objects that are — so **the base's own VMT is dead and gets dropped, and it was the last thing referring to those two bodies.** Every other base method survives because a live descendant VMT names it. The two empty ones are unreferenced from anywhere in the program, and the linker discards them. That is precisely why they leave no trace in 1,232 bytes.

**THE PROBE THAT "FAILED" WAS TESTING THE WRONG STAGE.** It compiled a unit and found TP6 emits both empty bodies — correct, and irrelevant: **the `.TPU` keeps every routine and the LINKER is what removes them.** Smart linking is a link-time, per-routine operation; a `.TPU` is not a linked image. Worth remembering the next time a probe answers a question that was really about the EXE.

### SO `verify.py` COMPARES A `.TPU` AGAINST A LINKED SEGMENT, AND THE TWO NEED NOT HOLD THE SAME ROUTINES

This is a property of the whole method and it had not been articulated before. `verify.py` takes our `.TPU`'s code and looks for it in the original EXE's segment. **Any routine the original's linker dropped is present in our `.TPU` and absent from the segment** — so our code can legitimately be LONGER than the segment, and the difference is not an error.

Two consequences, both practical:

* **A dropped routine must be written LAST in the unit**, because Turbo Pascal lays `.TPU` code out in source order: anywhere else and everything after it shifts and the comparison fails. `CMDLINE.PAS` puts its two empty overrides after `GetDOSCmdLine` for exactly this reason. **That is a property of the measurement, not source-fitting** — the note in that file which called it "a construction" is now wrong and has been corrected.
* **Our code being longer than the segment is a signal worth reading, not a failure.** `CMDLINE` compiles to 1,282 bytes against a 1,232-byte segment and the 50 is the two empty bodies exactly. When a future unit overshoots, ask which routine nothing references before assuming a transcription error.

## Where to pick up

**THE LIVE WORK IS AT THE TOP OF THIS FILE, under "WHERE THIS STANDS TODAY".** Read that
section and start there. In one line: the code and the DGROUP layout are reproduced, five
bytes in `PLAYMOD` are the only difference left in any linked segment, and the next real
piece of work is risk 3 — `tdstrip` and `lzexe`.

**EVERYTHING BELOW THIS LINE IS HISTORY, and it is kept on purpose.** The per-segment notes record how each one was taken and what went wrong on the way; several of the most useful lessons in this project are about conclusions that fell over, and they are written up as superseded rather than deleted. Read a section when you touch the segment it is about, not before. The numbered list that follows was the pick-up order while segments were still being transcribed — **it is finished, and every item in it is struck through or done.**

---

### *(history from here)* — the `116e` virtual-method question, since resolved

**`ParseLine` calls VMT slots +$24 and +$28, so `TCmdLineInterpreter` declares nine virtual methods -- but segment `116e` contains only EIGHT routine bodies.** Every far return is accounted for and none of them is `InterpretNoSwitch` or `InterpretSwitch`:

    01b4 RETF 8   ParseLine     02b9 RETF 4  Rut_0110    045f RETF 12  CmpSwitch    04ae RETF 4  Abort
    02a8 RETF 8   ParseFile     03a5 RETF 4  GetToken    049e RETF 8   TokenParam   04ce RETF    GetDOSCmdLine

`04a2..04b1` is `Abort` -- `MOV byte ES:[DI+0148],1`, confirming the field layout a second time -- and `04b2..04cf` is `GetDOSCmdLine`, whose thirty bytes end on the segment's last byte. **There is no room for the two empty overrides and no trace of them**, yet Pascal will not compile a virtual method whose body is missing from its own unit.

**OUR RESOLUTION IS A CONSTRUCTION, NOT A FINDING.** The two bodies are written after `GetDOSCmdLine`, which puts `GetDOSCmdLine` at `04b2` and makes the unit compare identical over all 1,232 bytes -- the fifty bytes they add fall past the segment's end, where nothing compares them. **That is arranging the source to fit the measurement, which is the one thing this project does not do.** It is flagged in `CMDLINE.PAS` at the two bodies themselves, so nobody meets it by accident.

**TWO EXPLANATIONS ARE NOW ELIMINATED BY MEASUREMENT rather than by argument.**

*The calls are not on some other object.* `116e:0188` is `LES DI,[BP+06] / PUSH ES / PUSH DI / MOV DI,ES:[DI] / CALLF [DI+24]` -- `[BP+06]` is `Self`, so the VMT being indexed is `TCmdLineInterpreter`'s own and the ninth slot is genuinely its own. Same at `0104` for +$28 and at `0284` for +$08.

*And Turbo Pascal does not drop them.* The hypothesis was that TP6's smart linker discards a never-instantiated base type's VMT and, with it, the only references to two empty methods -- nothing in DemoVT instantiates `TCmdLineInterpreter`, since `109c` declares the descendant. **A probe settles it: TP6 emits both empty bodies, twenty-seven bytes each.** Put a claimed compiler behaviour in `v1.31b/probe/` and let a build answer; this is the sixth such claim tested and the sixth to fail.

*The segment extent is not wrong either.* `11bb` begins at paragraph `11bb`, which is `116e:04d0` -- the two segments are contiguous with no gap, so 1,232 is exact and `GetDOSCmdLine`'s thirty bytes really do end on the last one.

**AND THE BODY MAPPING IS CONFIRMED BY THE BYTES, not by inference.** `CMDLINE.PAS` reproduces `0000..04b1` exactly with ParseLine at `0002`, ParseFile at `01b8`, the extra virtual at `02ac`, GetToken at `02dd`, CmpSwitch at `03a9`, TokenParam at `0463` and Abort at `04a2`. Seven own methods filling +$08..+$20, plus `GetDOSCmdLine` which is not a method at all. There is no reordering of the declarations that covers nine slots with seven bodies, so the contradiction is not an artefact of how they were assigned.

**WHAT IS LEFT TO TRY** is `109c` itself -- it is the descendant, and its own overrides' slots must agree with +$24 and +$28. It calls `[DI+18]` and `[DI+1c]` more than twenty times, which is `CmpSwitch` and `TokenParam` and confirms the base's VMT from the outside; it also calls `[DI+10]`, the extra virtual, exactly once, at `109c:083d`. **That one call site is the best remaining chance to name `Rut_0110`.**

In order.

1. **~~`14b9`~~ — DONE at 2,224 of 2,224, 198 pending fixups, in seven builds.** See "`14b9` IS DONE" above; it also settled the `TSong` layout end to end, corrected `UNKLOADE`'s interface, and left exactly one deliberate data deviation (`SongLoaders`).

   **SO `154d` IS NEXT, AND ITS OBJECTIONS HAVE LARGELY DISSOLVED.** The scouting note below says it needs `14b9`, `165a`, a `TStream` stub and four record types before its first byte is measurable. Three of those four are now gone: `14b9` and `165a` are byte-exact, and `TStream`/`TDosStream` came in with `14b9`'s `Load` and `LoadFName`, so `Objects`' streams are already in use and proven. **`MODLOADE.PAS` already exists** as a declared stub with the release's signature confirmed by `14b9:00dc` — start there. What is left of the original objection is the record types (`TModFile31` and friends) and the fact that every `Song.X(...)` in the release is a method call — and that last point is now *easier*, not harder, because `TSong` turned out to be an object whose accessors exist and are byte-exact.

   The order after it: `19a0` (1,905, `LIB/SOUNDBLA.PAS` — and `SOUNDBLA.PAS` is already a declared stub holding its four port variables), `193a` (1,617, `LIB/DEVSB.PAS`), and `1000` last.

   **RUN `python v1.31b/census.py <seg>` FIRST, EVERY TIME.** It has now done most of the structural work on three consecutive segments.

2. *(the note as it stood before `14b9` was scouted, kept for the reasoning)*

   **SCOUTED. All sixteen routines are named, `TSong` turns out to be an OBJECT, and
   the filename question is settled -- see the two `14b9` sections above. What follows
   is the note as it stood before that scouting, kept because it is what the decision
   was made against.**

   **DECIDE THE FILENAME BEFORE WRITING ANYTHING.** The tree already holds TWO files in this area and they are not the same kind of thing: `v1.31b/src/SONGUNIT.PAS` is declarations only with no segment — the shared module record — and `v1.31b/src/VTSONG.PAS` is a declared stub standing in for `14b9` itself. The segment's counterpart is the release's `LIB/SONGUNIT.PAS`, so **the names as they stand are crossed** and one of the two has to give. Read both headers first. The likely shape is that `VTSONG.PAS` grows into the real unit and takes the release's name, with whatever `SONGUNIT.PAS` currently declares folded into it — but check what still depends on each before moving anything, and remember that `12ba`, `164b` and `11bb` all `uses SongUnit` and all three are byte-exact.

   Then `154d` (3,920, `LIB/MODLOADE.PAS`, 55.4%), then `19a0` (1,905, `LIB/SOUNDBLA.PAS` — **and `SOUNDBLA.PAS` is already a declared stub holding its four port variables, so start from that**), `193a` (1,617, `LIB/DEVSB.PAS`), and `1000` last.

   **RUN `python v1.31b/census.py <seg>` FIRST, EVERY TIME.** It has now done most of the structural work on two consecutive segments.

2. **~~`109c`~~ — DONE at 3,296 of 3,296, 484 pending fixups, in five builds. It also resolved `116e`'s open question and named its extra virtual.**

   `census.py` mapped the whole segment before a line was written, and the SWITCH TABLE
   did most of it. `109c:0844..088f` is a solid run of twenty-one length-prefixed Pascal
   strings ending exactly where `InterpretSwitch` begins, and `census.py` counts exactly
   twenty-one `CALLF [DI+18]` — one `CmpSwitch` per name, in table order. **Pairing the
   branch order against the table names every local routine**, because each branch calls
   exactly one and the near-call targets are unambiguous. Frame sizes then confirmed each:
   `ENTER $100` is the one with no locals, `$104` the eight with `i, r`, `$106` the one
   with a `LongInt`.

   THE SWITCH VOCABULARY DIFFERS FROM THE RELEASE'S IN THREE PLACES: `frst` is absent and
   so is `CmdInit1stSong`, the only routine it called; `nx` and `nb` are new, inserted
   after `sh`, each calling a new three-instruction procedure.

   **`nb` IS "NO BANNER", AND `1000` NAMED IT.** `109c:05b2` sets a byte at `DS:$09e8`;
   `1000:00fa` is `CMP byte [09e8],0 / JNZ +$67` and the 103 bytes it skips are four
   `WriteLn`s of four 62-byte code-segment constants — a four-line banner — after which
   `1000:0164` sets the same flag itself so it prints once. **`nx` remains unnamed**: it
   sets `DS:$0bc6` and a scan of every segment finds no reader at all.

   FIVE THINGS HAD TO BE MEASURED, and **every one announced itself as a jump displacement
   before it announced itself as anything else**:

   | what | how |
   |---|---|
   | `SetVTDevice` loses three statements | no `DeviceSet` guard, no `UsingGUS := FALSE`, no GUS fallback — and the `then` branch is EMPTY: the `JZ` at `001b` and the `JNZ` at `0027` both target `0029`, the JNZ with a displacement of literally ZERO |
   | `NumExts` is 7, not 6 | `02e0` is `MOV word [BP-0150],0007`. The eight extensions are at file offset `$00d7b5` in the DATA image: `.123 .MOD .STM .WOW .OKT .S2M .S3M .669` — the release folds `.S2M`/`.S3M` into one `.S?M` and has `.STX` for `.STM` |
   | `DoSongColl` clears `OneModPtr` | eight bytes at `079f`, `XOR AX,AX / MOV [03c0],AX / MOV [03c2],AX`, so the caller's hook cannot outlive the collection |
   | `CmdInitShell` calls `SkipRest` | `0835` is `CALLF [DI+10]` — **the extra virtual's only caller anywhere** |
   | `CmdInitFreq` has one `Val` | `1ba1:0f81` is called nine times for nine parsing routines, so exactly one apiece; the release's duplicated `VAL(s, i, r);` line is not here |

   **`116e`'s EXTRA VIRTUAL IS NOW `SkipRest`, NOT `Rut_0110`.** Its only caller is the
   last statement of `CmdInitShell`, straight after `ShellParam := Copy(Line, Idx, 255)`:
   a method that has just read the rest of the line directly needs the tokeniser to stop
   handing the same text back as switches. The name is ours — the release has no such
   method — and `CMDLINE` still verifies identical after the rename.

   AND THOSE FOUR LINES CONFIRMED THREE ADDRESSES against units already verified:
   `ProgName` at `DS:$3ade` (VTShell), `ShellParam` at `DS:$08c8` with `PUSH 007f`
   confirming `String[127]` again, and **`Idx` at `+$146` — a third independent
   confirmation of `TCmdLineInterpreter`'s field layout.** `ENTER $204` also accounts for
   `CmdInitShell`'s two locals that no instruction touches: 256 + 256 + 4.

3. **~~`165a`~~ — DONE at 3,216 of 3,216, 207 pending fixups, in TWO builds.**

   The release's `LIB/SONGELEM.PAS` bodies went in verbatim: three objects, fifteen
   routines. **The first build came back at 9%, and the 9% was a JUMP DISPLACEMENT.**
   Everything downstream of it was already byte-exact; only `Change`'s total LENGTH was
   wrong. Reading that displacement as a length rather than as an error is what made the
   second build the last one.

   **`census.py` IS NEW AND IT DID ALMOST ALL OF THIS SEGMENT.** One command --
   `python v1.31b/census.py 165a` -- and the four scans between them identified all fifteen
   routines, named the five the release has that 1.31 does not, and confirmed the field
   layout, **without disassembling a single instruction**:

   | scan | what it gave |
   |---|---|
   | 15 far returns | the routine census, and the cleanup count is a signature: `RETF 10` is Self + a Word + a pointer |
   | 0 printable strings | all three `GetName` methods are absent, and so is `Change`'s `IF Debug THEN WriteLn` |
   | 10 far-call targets | `1ba1:0a2e` x5 all in Desample and `1ba1:0a13` x5 all in Resample — **five LongInt divisions and five multiplications, term for term against the release's expressions** |
   | 22 virtual sites | four slots only, and all four are what `17cf` independently says: HGetMem +08, HFreeMem +0c, HNewStr +30, HDisposeStr +34 |

   **AND THE RELEASE'S IMPLEMENTATION ORDER, WITH THE FIVE ABSENT BODIES REMOVED, IS THE
   ORIGINAL'S ADDRESS ORDER EXACTLY.** Turbo Pascal lays routines out in source order, so
   that agreement is itself a check on all fifteen at once.

   THREE THINGS HAD TO BE MEASURED, and one of them reached back into a finished unit:

   | what | how |
   |---|---|
   | `IF Instr^.Repl <= 4 THEN Instr^.Repl := 0` is absent | its 42 bytes were the whole overshoot; `01be` goes straight from the NAdj default to `LowQuality` |
   | 83 bytes at the end of `Change` the release has no trace of | a second sample free, guarded by `DS:$0bc7` where the first tests `DS:$0bce` |
   | `DumpToUltrasound` takes `var Src`, not `Src : Pointer` | `165a:02b0` is `LES DI,ES:[DI+16] / PUSH ES / PUSH DI` — a var parameter — where a Pointer argument is two word pushes |

3. **~~`116e`~~ — DONE at 1,232 of 1,232, 158 pending fixups, and it cost one build.**

   The release's `LIB/CMDLINE.PAS` bodies went in **verbatim, all of them**, and the first
   measurement came back at 97% with the divergence in the last thirty bytes. Nine
   routines: `ParseLine`, `ParseFile`, an extra virtual, `GetToken`, `CmpSwitch`,
   `TokenParam`, `Abort`, `GetDOSCmdLine`, and two empty overrides.

   **TWO STRUCTURAL FACTS WERE READ OUT OF FOURTEEN BYTES.** `116e:02ac` is
   `MOV word ES:[DI+0146],00FF` between `PUSH BP` and `RETF 4` -- `Idx := 255` and nothing
   else:

   | what it fixes | how |
   |---|---|
   | the field layout, exactly the release's | `Idx` at +$146 = 2 + 256 + 68, and 68 is `DirStr` = `String[67]` |
   | 1.31 has ONE MORE VIRTUAL than the release | four `CALLF [DI+14]` sites are `GetToken`, which the release's declaration order would put at +$10 |

   **`DirStr` IS `String[67]`, NOT 80**, and mistaking it cost the only real detour here.
   Turbo Pascal splits a path as 67 + 8 + 4 = 79, so `DirStr` + `NameStr` + `ExtStr` is
   exactly `PathStr`. With 80 the arithmetic misses by twelve and the whole object looks
   wrong; with 68 it lands on the nose and the release's declaration needs no change at
   all.

   The extra virtual sets `Idx` past the end of the line so `GetToken` returns the empty
   string for ever after -- **a softer stop than `Abort`**, which sets `Aborting` and
   unwinds the whole nested `@file` chain. Two ways to stop, and 1.31 wanted both. It is
   `Rut_0110` until a caller names it.

   **COUNTING FAR RETURNS IS THE CHEAPEST ROUTINE CENSUS THERE IS.** One regex sweep for
   `LEAVE` followed by `RETF` found eight, and each return's stack-cleanup count
   identified its owner without disassembling anything: `RETF 12` is `CmpSwitch` (Self, a
   var parameter, a string pointer), `RETF 8` is a one-string-parameter method, `RETF 4`
   is Self alone. **The counts are a signature, and reading all eight took one command.**

   **All 2,832 bytes.** Forty-three routines -- three pointer helpers, three heap
   utilities, fifteen THeap methods, TUmbHeap's two, THeapColl's fourteen, seven nested
   closures and one initialiser -- and **the fifteen THeap methods went in as a single
   pass and landed exact.**

   **FOUR THINGS HAD TO BE MEASURED RATHER THAN COPIED, AND ALL FOUR WERE FOUND BY
   COUNTING:**

   | what | how |
   |---|---|
   | `InitTempHeap`, `DoneTempHeap` absent | `ChangeSystemHeap` has ONE caller here where the release has three |
   | `DoneHeapVariables` absent | no `CALLF [DI+3c]` -- `RemoveHeap`'s slot -- anywhere in the segment |
   | the `WriteLn` in `HFreeMem` absent | not one printable string in 2,832 bytes |
   | `SetMemTop` takes a `Pointer` | `PUSH [0c4a] / PUSH [0c48]` is a pointer pushed whole |

   **COUNTING CALLS AND CALL SITES IS THE CHEAP INSTRUMENT OF THIS SEGMENT**, and it
   settled seven things in all: three absent routines, `THeap`'s method-list length
   (`CALLF [DI+38]` puts `AddHeap` one slot past it), `EndOperation`'s duplicated branch
   (`TransferFromSystem` ×4 against `TransferToSystem` ×2), and which five methods wrap
   themselves in `BeginOperation`/`EndOperation` (×5 each). **A missing call proves a
   missing routine far more cheaply than searching for the routine.**

   **`InitTempHeap` AND `DoneTempHeap` ARE ABSENT FROM 1.31, and a CALL COUNT proved it
   without reading either routine.** Both call `ChangeSystemHeap`, and so does
   `ShrinkSystemHeap`, so the release's has three callers inside its own segment.
   `17cf:010c` has exactly one. A temporary heap is what the tracker's swap system
   carves out of the system heap, and a player that only plays has nothing to swap.
   **Counting callers is a cheap way to detect an ABSENT routine** -- much cheaper than
   looking for it.

   So `01f1` is `THeap.Init`, not `InitTempHeap`: `01f6` calls `1891:0000`, which is
   `TObject.Init`, and a constructor is what calls that.

   **THE NESTED CLOSURES ARE WHY THE SEGMENT HAS MORE FRAMES THAN THE RELEASE HAS
   ROUTINES.** `THeapColl`'s delegating methods each declare a local `far` procedure and
   pass its address to `HeapColl.ForEach` or `.FirstThat`, so each is compiled as a
   routine in its own right. That accounts for the gap between the release's ~41
   top-level routines and `scan_funcs.py`'s 46 frames.

   **WHAT WILL NEED SCAFFOLDING: `TCollection`.** THeapColl keeps its sub-heaps in one
   and the segment calls `Objects` at six entry points (`1891:0000`, `0031`, `03a7`,
   `04ec`, `0520`, `055b`) -- `TCollection` plus its iterators. `TObject` is already
   declared locally in `HEAPS.PAS` for the VMT geometry; `TCollection` will need the
   same treatment, and the ForEach/FirstThat closures are what the extra frames among
   the 46 are. Nothing before `THeapColl.Init` needs it, so it can wait.

2. **THEN `116e` (1,232 bytes, `LIB/CMDLINE.PAS`, measured 59.5%) — the cheapest confident win left**, and then **`165a` (3,216, `LIB/SONGELEM.PAS`, measured 65.1%) — the highest-scoring untranscribed segment in the tree.** Both were promoted by `relmatch.py`; see "Every pairing is now measured" below. `165a` also unblocks half of `154d`.

3. **THEN `14b9` — still the other unblocker for `154d`.**

   `154d` is the largest remaining segment and the obvious next target, and it is the WRONG one. It was scouted properly before any code was written and the scouting is what changed the plan — the findings are in "154d is scouted and it is NOT the next segment" below. In short: it calls three routines in `14b9` and three in `165a`, needs a `TStream` stub, and its bodies cannot be copied from the release. Doing it first means writing four kinds of scaffolding before a single byte can be measured.

   2,224 bytes, and three segments wait on it: `12ba` calls it through the `VTSONG.PAS` stub, and `154d` calls three of its entry points including one (`04b6`) the stub does not have. Doing it turns a stub into a real unit and unblocks `154d`.

   Then `154d`, then `109c` (3,296, `VTCMD.PAS`, measured 42.1%), then `193a`/`19a0`, and `1000` last -- it has no counterpart and `VTMAIN` is blocked on seven others.

   **`154d` STAYS DEFERRED** for the reasons in the scouting note below — it needs `14b9`, `165a`, a `TStream` stub and four record types before its first byte is measurable.

   **AND MIND WHAT `11bb` DID AND DID NOT ESTABLISH.** Twenty routines went in essentially verbatim there, which raised the prior for every remaining pairing — but `154d` is the counter-example, so the rule is "try the release's body first AND measure", not "assume it transfers". The prefix says which within one build.

2. **~~`11bb`~~ — DONE. Twenty routines, essentially verbatim.**

   Only three things had to be measured out of the binary rather than copied: `ShellParam` is a `String[127]` (`11bb:0d5c` pushes `7F`, not `FF`), `TmpPath` is absent from `DoSectMisc`, and `ForceEGA` is absent from `DoSectScreen`, which is a five-byte empty body. **Both absences were PREDICTED from the string table before an instruction was read** — 41 of 52 literals matched and the three that did not were `ForceEGA`, `Line` and `TmpPath`.

   **It will pull DGROUP ownership questions with it**, the way `142f` did. `VTCFG` assigns to variables all over the tree — `SoundDevices`, `PlayMod`, `ModCommands`, `GUS` — so expect the same "which unit owns this global" decisions, and expect the call graph to settle them again.

   Then `154d` (3,920, `LIB/MODLOADE.PAS`), `109c` (3,296, `VTCMD.PAS` as a sibling), and the rest of the table in that section.

2. **~~`142f`~~ — DONE, and here is what finishing it took.**

   Forty-three routines and the dispatch table, all byte-exact. **2,175 bytes of code plus one byte of padding at `087f`.**

   **THE DISPATCH TABLE NAMED SEVENTEEN ROUTINES AT ONCE, and nothing else could have.** Seventeen of this unit's routines are one-byte `RET`s — `035d..035f`, `04e1`, `057c..0583`, `061d..0621` — and every one of them was carried under an address name on purpose, because **an empty body cannot confirm a pairing**: every empty routine matches every other one, so position would have been all there was. The table at `DS:$0370` holds 36 words, one per command, and its INDEX *is* the command number, so reading it against the release's `TickCommOfs` at the same index named each one from the binary.

   **AND THE SIGNATURE IS FAR STRONGER THAN SEVENTEEN SEPARATE MATCHES.** The release doubles two entries — 18/19 share `TickFPortUpDown`, 27/28 share `TickVolFineUpDn`, because E1x/E2x and EAx/EBx share a tick — and 1.31's table doubles at exactly those four indices on exactly those two addresses. Five more point at `TickNone` where a command has no tick at all, at the same five indices. Coincidence is not available.

   `mcLast` IS 35 HERE AND 36 IN THE RELEASE, which is `mcS3mRetrigNote` missing — consistent with `TCanal` having no S3M fields. Indices 33/34 (the Oktalizer arpeggios) point at `TickNone` where 1.39b implements them: the slots exist and the feature does not.

   **THE PROLOGUE SCANNER'S LIST IS NOT COMPLETE, and `142f` proved it twice.** `TickVolSlide` at `03cd` and `TickVolFineUpDn` at `0619` are both frameless, so `scan_funcs.py` found neither; both were located by reading the jumps and calls that reach them. Every tick routine in this unit is `ASSEMBLER` with no named parameters, which is exactly the shape the scanner misses.

   **AND WATCH THE SOURCE ORDER.** Turbo Pascal lays procedures out in source order, so the file must be in ADDRESS order or everything below the first misplacement shifts. One routine pair was written into the stub section by accident and had to be moved; the symptom was `Unknown identifier` on a backward call, which is a cheap way to catch it, but a forward one would have compiled and silently misplaced 300 bytes.

   **THE PROLOGUE SCANNER'S LIST IS NOT COMPLETE, and `142f` proved it.** `TickVolSlide` at `03cd` is frameless, so `scan_funcs.py` never found it; it was located by reading the two jumps at `0352`/`0359` and the call at `03be`, all of which the release spells `TickVolSlide`. Expect more frameless routines in what is left of the segment — the tick routines are all `ASSEMBLER` with no named parameters, which is exactly the shape the scanner misses.

   **AND WATCH THE SOURCE ORDER.** Turbo Pascal lays procedures out in source order, so the file must be in ADDRESS order or everything below the first misplacement shifts. One routine pair was written into the stub section by accident this session and had to be moved; the symptom was `Unknown identifier` on a backward call, which is a cheap way to catch it, but a forward one would have compiled and silently misplaced 300 bytes.

   **Then `14b9` and `17cf`**, the other two declared stubs. All three are the best targets because 12ba constrained them from the outside, which is a position none of the remaining segments starts from:

   * every signature in all three stubs was read off 12ba's call sites and is byte-confirmed by the calls that reach it;
   * `142f` gets `TCanal` with its head confirmed four fields deep by `12ba:11fd..121d`, and the release supplies the calling convention in a Spanish comment (*"En las del tick, se entra con SI apuntando al TCanal correspondiente"*);
   * `14b9` gets `TSong` with `Len35`, `Len37`, `Chans`, `Status` and `DefSpeed`/`DefTempo` all fixed by stores or reads in `12ba`, and `Table3D` at `+$3d` explained from the consumer's side;
   * `17cf` gets `THeap`'s VMT geometry confirmed — `HGetMem` at `+8`, `HFreeMem` at `+0c`, and `OBJECT(TObject)` proved by `MOV DI,[DI]`.

   And `142f` has already paid the whole of that dividend back: **`TCanal` now has NO unanchored fields at all** from `+$00` to `+$23`. Fifteen offsets are fixed by an instruction in this segment rather than copied from the release — `+$0f` and `+$11` fell to `StartNPortamento`, `+$1a..+$1e` to `StartVibrato`, `+$21` and `+$23` to `StartVolSlide` — and only the two bytes at `+$24`/`+$25` keep names taken from what 12ba does with them. Two sessions ago most of that record was the release's layout on trust.

   **A stub becoming real is the moment to add it to `verify.py`**, and not before. All three are deliberately absent from it.

   Then the other seven untranscribed segments; `VTMAIN` is blocked on seven of them. `06-transcription.md` has the inventory.

2. **What `12ba` took, kept because the method is the transferable part.**

   `v1.31b/src/PLAYMOD.PAS` and `PLAYMOD.ASM`, with three stub units beside it and no placeholders left. Nineteen routines, the unit's initialisation section, and the object module — `blocks.py` reports **5,958 of 5,968 bytes**, the missing ten being linker padding, and `asmcheck.py` accounts for all eighteen relocations.

   **THE FIVE "SELF-CLOSING" DIFFERENCES WERE NOT SELF-CLOSING, AND THAT WAS THE LESSON.** `blocks.py`'s header carried them as a prologue that would come right when `PlayStart` reached its locals, plus one jump displacement waiting on code below `11d6`. Both explanations were wrong. The routine had been given a second parameter it does not have and had been left NEAR: `12ba:132c` is `RETF 4`, which is the `var Song` reference alone, and `10a5` reads `Song` at `[BP+6]`. The invented `Arg : Word` was compensating for the missing `far` — two errors that cancelled in the frame size and cancelled nowhere else. **A routine's parameter list is settled by its `RETF` in one instruction; check that before believing any story about a frame.** Predictions in a handover get believed, which is why they must be marked as predictions — this one was, and it still cost several sessions.

       python v1.31b/build.py && python v1.31b/blocks.py && python v1.31b/asmcheck.py

   **THE PREFIX IS NOT THE MEASURE MID-ROUTINE.** While a routine is half-written the first differing byte is always a jump displacement that cannot be right yet, so `verify.py`'s prefix freezes at that routine's start and says nothing about the hundreds of bytes after it that ARE right. That is not a regression and not a plateau. `blocks.py` exists for exactly that, and `asmcheck.py` for the object module the other two cannot measure.

   The method, in the order that worked, and it is the same order to use on the next segment:

   1. `mcp__ghidra__disassemble_bytes` at the address, 90–110 bytes at a time. `12ba` disassembles cleanly, no resync problems.
   2. Read `LIB/PLAYMOD.PAS`, `LIB/MODCOMMA.PAS` and `LIB/SONGELEM.PAS` for the shape and the names before writing anything. The release has paid for itself over and over in this segment — see below.
   3. Write the block, build, and check it with `blocks.py` (add the new block to its list) or the inline positional search.
   4. **Search for the shift PER BLOCK.** One global shift misreports; it did so twice.
   5. **Read the routine's exit before theorising about its entry.** `RETF n` fixes the parameter list and `ENTER n,0` the frame, and both are free. `PlayStart` cost several sessions for want of one glance at `RETF 4`.

   **Transcribe strictly top-down.** Turbo Pascal lays procedures out in source order, so a skipped routine displaces everything below it. `132f`, `13d7` and `141e` are done — `ChangeSamplingRate`, `PlayStop` and the initialisation section — and `1600` is inside the object module. Object-module code lands after ALL Pascal code, so nothing left can displace anything.

   **The scaffolding, all of it deliberate and all of it marked in the source:**

   * `v1.31b/src/VTSONG.PAS` — a STUB for segment `14b9`, five entry points (`0352 GetInstrument`, `0575 GetPatternSeq`, `059f GetPatternSequence`, `05d3 GetPositionSpeed`, `0607 GetNote`). Signatures read off 12ba's call sites, bodies deliberately wrong. NOT in `verify.py` and must not be until 14b9 is really transcribed.
   * `v1.31b/src/MODCOMMA.PAS` — a STUB for segment `142f` (`CommandStart`, `CommandTick`), and the home of `TCanal`, because 142f takes it and 12ba fills it so neither can own it. That is where the release keeps it too.
   * `v1.31b/src/HEAPS.PAS` — a STUB for segment `17cf`, and it exists for ONE construct: `12ba:1263` is `CALLF [DI+8]`, a virtual method call on the heap object at `DS:$39ae`, and no byte placeholder can stand in for a VMT slot. It declares `THeap`'s virtuals in the release's order so `HGetMem` lands at `+8` and `HFreeMem` at `+0c`, and nothing else. **`MOV DI,[DI]` at `1261` confirms the release's `OBJECT(TObject)` from the other side of the program**: Turbo Pascal puts an object's VMT link after the fields it inherits, so a base object with four Pointer fields carries the link at `+$10` and the call site becomes the one-byte-longer `MOV DI,[DI+10]`. That extra byte is what put every block below it at shift +1, and it is how the ancestry was measured rather than assumed.
   * ~~A `ChangeSamplingRate` PLACEHOLDER body~~ — GONE. Both it and the `PlayStop` placeholder that briefly replaced it are real transcriptions now, and both are in their right positions: `132f` follows `PlayStart`'s `RETF 4` at `132c`, and `13d7` follows `132f`.
   * ~~`PLAYMOD.ASM`'s STUB for the `1600` kernel~~ — GONE, and it was never only `1600`: the module is `148f..1745`, three routines, and the scanner had found just the one because the other two are frameless.
   * Types that had to move to `SONGUNIT` so two units could share them: `TFullNote`, `TModCommand`, `TSampleDesc`. The release splits them the same way (`SONGELEM.PAS`).

   **FOUR GLOBALS ARE NOW DECLARED IN TWO UNITS EACH** — `AltMode` (`$02d1`, VTMAIN), `GusStarted` (`$0bce`, DEVGUS), `TicksPerSecond` (`$0bcc`, DEVGUS), `TickSnapshot` (`$0bca`, VTMAIN). All four are flagged at their declarations. A global's address is a linker fixup so the byte comparison cannot see any of it, which is risk 1 exactly. `VTSilenc.Ticks` at `$0bc8` is the counter-example: it is exported, so 12ba uses it directly — and `12ba:0c5c` compares the two halves of that pair in one instruction, one resolved and one duplicated.

   **~~THREE DISABLED ROTATIONS~~ — TWO OF THE THREE ARE NOT DISABLED AT ALL: `NumBuffers` IS 1.** `0c30`'s `Inc(BuffIdx)` then clamp to 1, and `108c`'s same clamp on `BuffGive`, are the release's `IF BuffIdx > NumBuffers THEN BuffIdx := 1` with NumBuffers = 1. With one buffer the clamp IS the arithmetic. The count is measured three ways: `12ba:1232` passes `SIZEOF(Buffers)` to FillChar as an immediate `$0b`, one 11-byte `TSampleBuffer`; `12ba:1299` closes the allocation loop with `CMP [BP-2],1`; and three buffers would run `$1394..$13b6` and swallow `SizeOfABuffer`, `ModFlag` and `MuestrasPerTick` at `$13a0`, `$13a2`, `$13a4`. The declaration had said `array[1..3]`, copied from the release, and the release's 3 is 1.39b's.

   `06c0` is still genuinely disabled — `INC AX / AND AX,0` pins the note buffer to slot zero, and the `MyMove` at `06d8` copies a block onto itself as a result. Transcribed as found.

   *(Historical, kept because it shows the rate: the first increment — `12ba:0000` and `0007`, 391 bytes — went in byte-exact on the first build, and the segment reached 76% in roughly fifty short iterations.)*

   **One debt that was retired rather than carried:** `12ba:0782` was first written as `DB 9Ah / DW 0,0`, a hand-emitted far call, because `14b9` did not exist. That worked only because the result went into a variable — the SECOND call into `14b9`, at `07d1`, branches on its result, and no byte-placeholder can feed an `if`. That is what forced `VTSONG.PAS` into existence, and both calls are now real. If another segment needs the same treatment, go straight to a declared stub unit.

3. **Risk 1, the DGROUP layout**, whenever the goal moves from per-unit `.TPU` agreement toward a linked binary. It is now the largest unknown, and `DEVGUS` showed what it looks like from the inside.
4. **Optional cleanup in `SOUNDDEV.ASM`, now that it is an assembler module.** Nothing depends on it and each step needs its own byte comparison: the `DB`-encoded instructions can become mnemonics again (TASM assembles `22 C0` and `03 C0` correctly, which is why they were `DB` in the first place); the two literal `DB 0E9h,10h,0FFh` jumps at `1060` and `1079` can become symbols now that the whole run shares a scope; and `DW OFFSET SetGains + 0636h` can become a label. Each one makes the source say what it means, and each one can silently move a byte — do them one at a time.
5. **Optional:** diff the release's `SYSTEM`/`OBJECTS` sizes against a TP6 build to see which library the author had. TP6 patch levels are done — 6.01 changes nothing.
6. **Extend the probe.** It cost one file and closed two long-parked divergences in its first run. Anything the docs call a compiler difference is a candidate: put the construct in `PROBE.PAS`, quote the original's bytes above it, and let a build settle it instead of a note.

Two things NOT to spend time on:

* **`1a17` is done — do not re-open it looking for the four bytes.** They are gone, and the way they went is the lesson: not another Pascal shape, but the right TOOL. The probe had established that no arrangement of an `assembler` procedure suppresses the epilogue.
* ~~**Do not try to fix `1a17`'s last four bytes by rearranging Pascal.**~~ The probe has tested it: an `assembler` procedure gets its epilogue after a trailing internal `JMP`, after a written `RET`, after a written `RETF 4` and after pure `DB` data; and declaring the parameters that would make the last one `RETF 4` brings a prologue with it even when the body never names them. The answer is TASM, not another shape. (`GUS` and `SOUNDDEV` were both on this line as "finished"; both were wrong.)
* **The gain ladder's pointer tables.** They look wrong in any tool that counts a long run of zeros as real. They are not.

---

## Risks

None of these are blocking today. All of them can invalidate work already done.

### 1. ~~The DGROUP layout~~ — CLOSED, BOTH HALVES

The reconstruction declares each global in the unit that owns it semantically; the original is **one flat data segment addressed absolutely**, and its variable order is whatever the original link produced. Variable offsets are pending fixups inside a `.TPU`, so `verify.py` cannot see them and every "identical" result above is silent about them. They surface the moment anything is linked.

It may force a structural change — one unit owning DGROUP in the original's order — that touches every file. **Do not treat the passing units as finished work until this is understood.** `DEVGUS`'s three duplicated globals were the first concrete instance: three variables in the wrong unit, one of them standing in for two addresses, and the byte comparison agreed throughout.

**IT IS CLOSED: 3,184 of 3,184 bytes, every block in place, and the only bytes that
differ are one code gap seen from the data side.** See "HOW RISK 1 WAS CLOSED" above for
the four layout rules, the eleven blocks and the two conclusions it overturned.

**AND THE UNINITIALISED HALF IS SORTED TOO.** It is not in the EXE -- a plain `var` is
space the linker never writes -- but the CODE carries every resolved address, so
`v1.31b/linkcmp.py` reads the layout back out of the linked segments. Twenty-six of
twenty-seven units are byte-identical in the linked image, our DGROUP is `0x4684` against
`0x4690` (the same to the paragraph), and every variable-address operand in the program
matches. See "HOW THE VARIABLE HALF WAS SORTED".

**HOW IT WAS MEASURED, AND `v1.31b/dgroup.py` IS THE INSTRUMENT.** The original's initialised DGROUP is segment `1caa`, 3,184 bytes, and it is simply the tail of the image after every CODE segment; ours is the DATA segment, located from the map. Diffing the two block by block says which variables are in the right place, which are shifted and by how much, and which are absent — **the first measurement of risk 1 this project has ever had.** Today: 2,336 bytes against 3,184, 29 blocks in place, 80 moved, 28 absent. Only TYPED CONSTANTS appear there, because a plain `var` is reserved space and is not stored, so it measures the initialised part only — which is still most of what risk 1 is about, since a constant's position pins its neighbours.

**AND THE BETWEEN-UNIT RULE IS SETTLED: DGROUP FOLLOWS THE LINK ORDER.** `VTMAIN` at $0000, `VTSilenc` at $001e, `DevGus` at $0058 — each unit's data starting where the last one's ended, in the same order as the code segments. That is why the link order had to be right first, and it is why nothing about the layout was measurable before it was. **The INTRA-unit rule is not settled** and is the next thing to probe: typed constants come before variables regardless of where the sections sit in the source (measured — moving a `var` section above a `const` one moved nothing), but that is one observation and the remaining two unexplained bytes at `$0002..$0003` want a probe rather than more argument.

Two kinds of progress had already been made against this risk before anyone set out to:

* **Spacing pins a block when the instructions name its ends.** `19a0`'s twenty-eight ports run `$0adc..$0b13` and `$0adc + 27*2` is `$0b12`, so the next Word is `$0b14`, which is `SbPort` — the port block and the configuration block are contiguous with nothing left over. Its run-time state block is pinned the same way between three known addresses. **A routine that touches many globals at once is the instrument**: `SbRegDetect` rewrites every port, `InitValues` and `Free` touch every field of `TSong`, `193a`'s init section fills four device records.
* **Cross-unit agreement is a check.** `193a`'s `SetVars` copies three ports from `SoundBlaster` into `SoundDevices`, and all six addresses were already known independently from the two units. `VTMAIN` resolved eight `Var<addr>` placeholders onto variables their owners had already declared at those exact addresses.

What is left is about twenty names still declared in `VTMAIN` that almost certainly belong to `VTCmd` or `VTCfg`, each flagged at its declaration.

### 2. ~~It is TP6~~ — CLOSED for the COMPILER and the LIBRARY; the ASSEMBLER is still open

**This risk is now UNSUPPORTED BY ANY MEASUREMENT.** All six divergences once carried as evidence for it turned out to be the TP6/TP7 gap, the `$G` switch, or our own source — the last of them, `1a17:070f`'s register allocation, was hand-written asm. Nothing in the tree currently says the compiler differs.

That is not the same as proof it does not. **A linked binary now IS produced**, which is the test this risk was always waiting for; the RTL evidence from the release's map still says the author's `SYSTEM`, `DOS` and `OBJECTS` are not this install's. **The risk is now about the LINK and the LIBRARIES rather than the code generator**, and it will be re-opened by the first divergence that survives a probe. A TP6 patch level is closed outright: 6.01 emits code byte-identical to 6.0's, on the probe and across the whole tree.

**THE LIBRARY HALF IS NOW CLOSED TOO: `OBJECTS`, `DOS` AND `SYSTEM` ARE ALL THREE
BYTE-IDENTICAL TO THE ORIGINAL'S.** So this install's RTL *is* the one the author linked
for 1.31, and the release's map showing different RTL sizes was about 1.39b's toolchain --
which the note there warned must not be carried back, correctly. What is left of risk 2 is
the ASSEMBLER, below.

~~**AND THERE IS NOW ONE MEASUREMENT THAT POINTS AT THE RTL RATHER THAN THE CODE
GENERATOR, WHICH IS NEW.**~~ *(WITHDRAWN within the hour, and it is the same lesson again:
the two `Move` addresses were two DIFFERENT ROUTINES in the SAME library -- `1ba1:0fb2` is
`Move` and `1ba1:09f7` is the compiler's array-assignment copy, eleven bytes apart in
behaviour. The original was making an assignment where our source called `Move`. **Seventh
time "it is the toolchain" has been concluded here, and it has been true twice.**) `12ba:076f` and `12ba:11ab` are `Move` calls: the original goes
to `1ba1:09f7` and ours to `1ba1:0fb2`. That is either a different routine in 1.31's source
or a different `SYSTEM`, and it is the first thing in the whole tree to suggest the second.
Against it: `SYSTEM`'s segment length matches the original's exactly, and so does `DOS`'s,
which a different library would be unlikely to do. **Read the two routines before
concluding**, and note that this file records "it is the compiler" being concluded six times
and true twice.

**The assembler is a separate question and it is OPEN.** `1a17`'s last four bytes need TASM, and the TASM in the image is a 4.1 from 1996. Its encodings match the original's where it matters, but it is no more the original's tool than TP 7.01 was.

The independent measurement from the release points the same way: the author's `SYSTEM`, `DOS` and `OBJECTS` segments are not the ones in this install. Whatever machine JCAB built on had a different library set, and that is measurable rather than speculative. Nobody has tried a TP6 build of the release to see whether its RTL sizes land on the shipped map's.

**Eight bytes in 10,108.** Worth knowing about, not worth chasing yet.

### 2a. The ASSEMBLER is now part of the toolchain question

`1a17` links `v1.31b/src/SOUNDDEV.ASM`, assembled by the image's **TASM 4.1, a 1996 build**. Its encodings match the original's everywhere they were measured, and 2,430 bytes came out byte-exact, which is strong — but it is no more the author's tool than TP 7.01 was, and the same caution applies. If a future module disagrees on an encoding, suspect the assembler version before the transcription.

### 3. Byte-exactness needs more than the compiler — **THE ONLY LIVE RISK, AND IT IS BLOCKED**

`MAKE.BAT` gives the pipeline as `tpc` → `tdstrip` → `lzexe`. The `tpc` step is done: the
build is byte-identical to the unpacked original, and link order has been solved so `1a17`
really is segment `1a17`. What is left is the two post-processors.

* **`TDSTRIP.EXE` is in the image**, at `C:\TASM410\BIN\TDSTRIP.EXE`, and looks like a
  no-op: our EXE is 58,176 bytes = 3,120 of header + 55,056 of load image with nothing
  after it, so there is no debug information to strip. **That is arithmetic, not a run** —
  worth confirming with one invocation.
* **LZEXE IS NOT IN THE TREE OR THE IMAGE, AND THAT IS THE BLOCKER.** The shipped file is
  LZEXE 0.91 and the version matters. **Getting a copy is the user's decision, not
  something to go and fetch** — a 1989 third-party binary from an unvetted source is
  exactly what the organisation's rules say not to download. Ask; do not assume.

**AND MIND WHAT THE UNPACKED FILE CANNOT TELL YOU.** `tools/unlzexe.py` writes `maxalloc`
as `$FFFF` itself and RECOMPUTES `minalloc` from SS:SP, because LZEXE preserves neither, so
those two header fields are the unpacker's rather than the original build's — `minalloc`
agreeing is partly circular. It also re-encodes the relocation table, so only the set of
LINEAR targets is comparable, not the order. Everything else in the header is real.

### 4. Scale

Twenty-six units are in `verify.py` and **all twenty-six reproduce their segment completely**; `progcmp.py` adds the program, which `verify.py` cannot list. `python v1.31b/coverage.py` computes the figure rather than quoting it: **44,171 of 44,272 in-scope bytes, 99.8%**, from 23.7% eight sessions ago. The remaining 101 bytes are segment PADDING — `00-map.md`'s sizes include it and `verify.py`'s code sizes do not — so there is nothing left to transcribe. In scope excludes the three Borland RTL segments (7,600 bytes) and `1caa` (3,184, data only).

`1a17` was the big one and `12ba` the second, and both are the warning as much as the good news: each took several sessions. **But the rate changed completely once the tooling and the method settled.** `154d` (3,920 bytes) went in whole in one pass; `19a0`'s last fourteen routines went in on a single build with no adjustment to any of them. Two things did that: reading the release's counterpart first, and writing the WHOLE unit before measuring rather than one routine per build. The top-down rule is about SOURCE ORDER, not about how much to write between builds — that misreading cost several slow sessions.

**AND A HARDWARE UNIT IS THE CHEAPEST THING HERE TO TRANSCRIBE.** `19a0` needed no second pass on anything, because a Sound Blaster did not change between 1.31 and 1.39b so there is no version drift to find. Compare `154d`, where three real differences had to be dug out, or `12ba` and `142f`, which drifted heavily. **Rank by how much of a segment is hardware.**

---

## Why this pass is worth continuing

**Byte comparison found real bugs, not cosmetic differences**: swapped parameters in `FILTERS.FilterChunkWord` (it would have read the sample count out of the filter selector), an inverted comparison in `VTNOTES` (the octave search ran the wrong way), an off-by-one in `StartUltrasound` that never silenced voice 0, ramp settings outside an `if` that belong inside it, a poll calling a one-byte stub, and `ChangeVol` — wrong in name, signature, register and both call sites.

**And `TriggerVoice`'s whole parameter list, which is the sharpest example yet.** It was transcribed backwards — `(EndA, LoopA, StartA, Mode, Freq, Pan, Voice)` for the original's `(Voice, Vol, Freq, Pan, StartA, LoopA, EndA)`. The reversal happens to total the same 22 bytes, so the routine still emitted a correct `RETF $16` and every size check passed; what was wrong was every frame reference inside it. It also hid a second bug: `1723:095c` reads `[BP+18]`, which is `Vol`, so the store is `LastVolumes[Voice] := Vol` — the backwards list made it read as `:= Pan`, and voice volumes would have been recorded as pan positions.

**Size checks missed every one of them.** So did reading the code carefully. The only thing that caught them was comparing bytes.

---

## Mistakes worth not repeating

Every one of these made the work look better or worse than it was.

- **A BYTE COMPARISON OF INITIALISED DATA CANNOT SEE A BOUNDARY INSIDE A RUN OF ZEROS.**
  `dgroup.py` reported the initialised half of DGROUP 100% identical while `SelfName`'s
  declared length was six bytes too long and VTSILENC's `Frac` and `OldVec` were missing
  from it entirely -- because every byte from $0018 to $001d is zero whichever way the six
  are divided. Only an instruction that NAMES an address can separate them, which is what
  `linkcmp.py` reads out of the linked code. **A measurement being exact does not make
  every declaration behind it right.**
- **A COMMENTED-OUT LINE IN THE RELEASE IS NOT A RECORD OF WHAT 1.31 DID.** It caught this project four times in two segments. `154d`'s ninety-byte delta-decoding block sits exactly where 1.39b has a different loop commented out. `193a` calls a `DMAReset` the release comments out, passes the `DMABufferSize` the release parks beside a debugging literal, and has DELETED a wait loop the release still runs. **A commented-out line means the author was editing that spot, and nothing more. Read the bytes.**
- **AN INTERFACE CAN BE WRONG IN A UNIT THAT IS ALREADY BYTE-EXACT, AND ONLY A CALLER FINDS IT — SEVEN TIMES NOW.** `VTDOSRSZ`'s `SetMemTop` took two Words instead of a Pointer; `VTDOSMEM`'s five routines carried invented names; `GUS`'s `DumpToUltrasound` took a `Pointer` instead of an untyped `var`; `UNKLOADE`'s three parameters were values instead of `var`s; `TSong.Status` was unsigned; `HARDWARE.DMAReset` took a `Word` instead of a `Byte`; `PLAYMOD.PlayStart` was not exported at all. **A unit measuring perfect says its BODIES are right, not its INTERFACE.** Treat every new caller as a test of what it calls.
- **AN UNREFERENCED TYPED CONSTANT IS SMART-LINKED AWAY, AND A FILLER THAT NOBODY READS MEASURES AS NOTHING.** Sixty-four bytes of filler were added to `HEAPS` to close the last gap in the layout; the `.TPU` grew by exactly 64 bytes and the linked image did not change at all. That is not a bug, it is the same routine-level smart linking that dropped three whole units earlier in this project, applied to DATA — and it is a much stronger fact than the failed patch: **every typed constant in the original's DGROUP is referenced by surviving code**, so a gap in the layout is a search for a reference, not a place to invent filler. `CmdList` was found that way within the hour.
- **A BYTE-PATTERN HIT IS A CANDIDATE, NOT A FINDING — AND TWO SCANS IN A ROW SAID SO.** Looking for `$06c2..$0701` as raw bytes across every segment returned dozens of hits. Filtering by 16-bit ModRM form left exactly one, `19a0:02b0`, which decodes as `DEC word [06e8]` and is really the tail of `PUSH -1 / PUSH CS / CALL`. Only scanning for `MOV r16,imm16` — the form that loads an array's BASE — returned a single hit in the whole program, and it was right. Third time this file records the rule; first time it cost two wrong leads before the correct scan.
- **A GAP'S DIRECTION IS INFORMATION, AND A MISPLACEMENT LOOKS EXACTLY LIKE A SHORTFALL.** `DEMOVT` read 160 bytes short of its segment while 240 bytes of it — the banner — sat in DGROUP instead of CODE, because it was declared a TYPED constant. Moved to untyped constants it reads 112 bytes LONG, which is a completely different question. **Comparing LENGTHS cannot tell a misplacement from an absence; only comparing contents can.** Two smaller errors were invisible until the strings reached the segment they belong in: two `#196` too many in two of the four lines, and `SelfName` being untyped when `PUSH DS` says it is not.
- **A `uses` ENTRY THAT REFERENCES NOTHING IS REAL, IN BOTH DIRECTIONS.** `VTCMD` carried a `DevGUS` no line of it names, and the link order is what found it; `SONGUNIT` turned out to NEED a `VTNotes` and a `Filters` that no line of it names either, and the link order is what found that too. **A clause changes the link and never the code**, so nothing but the order can see either case — and the release's own clause corroborated the second.
- **MOVING A DECLARATION ORPHANS ITS COMMENT, AND A COMMENT ABOVE THE WRONG LINE IS WORSE THAN NO COMMENT.** Thirty-nine declarations were lifted out of `PLAYMOD.PAS` into one address-ordered block and their notes stayed where they were, so a `DS:$0bcc` note ended up sitting above `Canales` at `$1260`. This whole project's method rests on a note meaning what it says. Two throwaway scripts found them faster than the compiler did: one listing declarations no longer under a `const`/`var` header, one listing comment blocks whose leading `DS:$addr` disagrees with the declaration below. **Sweep for both after any bulk move**, and beware the reverse error — a de-orphaning pass that deletes a `const`/`var` header whenever the next line is a comment removes five headers that were correct, because a note above a section's first declaration is the normal shape here.
- **CHECK WHETHER A CHANGE DID WHAT YOU MOVED IT TO DO.** `Guard`'s `var` section was moved above the `const` section to put it earlier in DGROUP; `dgroup.py` reported the identical prefix either way. The note in the source now records the negative result rather than the intention, because a comment that asserts an effect it does not have is exactly the failure this file already logs under "a doc asserted a source shape the source did not have".
- **A `.TPU` COMPARISON CANNOT SEE WHAT KIND OF THING THE BYTES ARE.** Three units had their INITIALISATION SECTION transcribed as a named procedure — `VTCTRL`, `VTSHELL`, `VTSILENC`. All three verified identical for their whole lives, because the bytes were right. Nothing calls the procedure, so the smart linker discarded all three the moment anything linked. **Only the link exposes this class, and every unit in the init chain is a candidate.**
- **WHEN A DEVIATION LOOKS FORCED, CHECK WHETHER THE ORIGINAL COULD HAVE HAD IT.** `SongLoaders` was written up here as an unavoidable data deviation because TP6 rejects the circular reference it needs. One search — for any store to the table's address, anywhere in the program — found none, so the table is initialised data, so the original's source must name both loaders, so the shape must be expressible. It was: TP6 accepts the cycle on a second pass. **The deviation was reasoning, not measurement, and a negative search overturned it.**
- **A SEGMENT BOUNDARY IS NOT A SUGGESTION.** `VTSHELL` carried three "stubs at 1931:0090, 0095, 009a" described as "kept because they are in the segment". They are in the next one: `0x1931*16 + 0x90` is `0x193a0`, which is `193a:0000` — DevSB's `Name` functions. Check a span against the FOLLOWING segment's address before believing anything near the end of a unit.
- **A `Jcc` WITH A ZERO DISPLACEMENT IS A DELETED BLOCK.** `19a0:00c7` is `75 00`, jumping to the next instruction, and the release has five lines commented out at exactly that point. `109c:0021` is the same shape and this file already warned not to re-derive it. **It is a general reading, not a one-off.**
- **A `.TPU`'s INTRA-UNIT NEAR CALLS ARE RELOCATIONS, NOT RESOLVED DISPLACEMENTS.** `14b9`'s `Init` and `Done` measured clean while both of their call targets were still placeholders at the wrong addresses, because Turbo Pascal leaves a same-unit code reference as zeros with a fixup record. **A call inside the unit is not evidence its target is right** — which is the exact opposite of the jump-displacement rule, where the displacement encodes everything downstream.

- **A ROUTINE'S PARAMETER LIST IS SETTLED BY ITS `RETF`, AND FIVE DIFFERENCES SAT ON IT FOR SEVERAL SESSIONS.** `PlayStart` had been given a second `Arg : Word` it does not have AND left NEAR when it is FAR. The two errors cancel in the frame size — a near frame plus one extra parameter puts `Song` at `[BP+6]` exactly as a far frame with none does — so nothing about the prologue looked wrong, and the four differences it caused were written up here and in `blocks.py` as "the prologue will come right when the routine reaches its locals". `12ba:132c` is `RETF 4`. One instruction, free to read, and it says four bytes of parameters. **Read the exit before theorising about the entry.**
- **"It will close itself" is a PREDICTION, and this one was marked as one and still believed.** The same five differences were carried as self-closing because four earlier ones genuinely had closed that way, in `03cc`, `0693`, `0b29` and `0c4e`. A mechanism that has worked four times is still not evidence about the fifth. The general rule it came from — a frame larger than the locals explain is a compiler temporary or a `with` slot — turned out to be right about `PlayStart`'s `[BP-8]` and irrelevant to the actual defect.
- **A COUNT COPIED FROM THE RELEASE, THREE TIMES CONTRADICTED BY THE BYTES.** `Buffers` was declared `array[1..3]` because 1.39b's `NumBuffers` is 3. 1.31's is 1, and the binary says so three separate ways: the `SIZEOF` immediate, the loop's terminating compare, and the addresses of the three variables that follow the array. Two of the three "disabled rotations" this document has recorded since early on were never disabled — they are the release's own clamp with the count it really has. **The release settles shapes and names; a COUNT is data.**
- **"It is the compiler" was concluded SIX times and was true twice.** `116a`'s `LES DI` and `1a17:024c` were the TP6/TP7 gap and closed on the compiler. `188f:001b` was the `$G` switch. `1723:04b5`, the self-assignment at `+04eb`, and `1a17:070f` — the register allocation, the strongest of them all — were our own source. `1723`'s `Port[]` order does not reproduce at all. **Parking something as a compiler difference has been the single most reliable way to leave a source bug in place**, and it takes one probe routine to check.
- **"Structural, not fixable from the source" was the same mistake wearing different clothes.** Four bytes in `1a17` were recorded as the unavoidable cost of Pascal's one-entry-one-exit rule, with the reasoning written out and correct — and the conclusion still wrong, because the premise was that the run had to be Pascal. It never was. **When something cannot be fixed from the source, ask whether it should be in that source at all.**
- **THE SAME TOOL LESSON, TWICE, AND THE SECOND TIME IT WAS PREDICTED AND STILL NEEDED A NEW SCRIPT.** `verify.py`'s zero rule was recorded as wrong for an assembled module when `SOUNDDEV.ASM` was written, and `blocks.py` inherited it anyway. `12ba`'s module then produced 27 "differences" for 36 relocation bytes — one per field where the high byte happened to be zero, two where it did not — which is the heuristic being wrong in BOTH directions at once. `asmcheck.py` is that lesson made executable rather than written down again. **When a doc records that a tool cannot measure something, build the tool that can, or the next module will re-learn it.**
- **A tool's model of "acceptable difference" is part of the measurement.** `verify.py` excused a byte only when OUR side was zero, which is exactly right for a `.TPU` and exactly wrong for an assembled module, where TASM leaves an addend. The first honest measurement of `SOUNDDEV.ASM` needed `omf.py` to read the `.OBJ`'s own FIXUPP records — 112 code self-references off by exactly the module base, 7 DGROUP symbols with an addend, 73 left as zero, none unexplained. **Stricter than the heuristic, not looser.**
- **A three-byte deviation hid four wrong pointers that nothing could measure.** The `JMP` at `0746` shifted `OFFSET SetGains`, so four `DW OFFSET SetGains + delta` patch targets aimed three bytes short — and a `DW OFFSET` is a linker fixup, so `verify.py` files it as pending zeros and reports agreement. **A deviation is not just its own bytes; it is everything measured from them.**
- **A doc asserted a source shape the source did not have.** "The source is confirmed correct against the release" was written about `ProbeUltrasound`'s `LABEL`/`GOTO` while the file held a nested `if`. Nobody re-opened the file for several sessions because the sentence sounded checked. **Cite the file, and re-read it when you repeat the citation.**
- **"It is the compiler" was concluded twice, withdrawn twice — and was TRUE.** `164b`'s size gap was blamed on BP6-versus-TP7 and turned out to be two invented `String` locals; the withdrawal was correct. But the mechanism named in it was real, and it is what `116a` and `1a17:024c` were. The lesson is unchanged and is about method, not about the answer: **a plausible mechanism is not evidence even when it later proves true.** What settled it was running the other compiler, and that took one afternoon once the compiler existed.
- **`$G-` "changes nothing" — it changes the one byte the unit was short.** The claim sat in `VTDOSRSZ.PAS` for several sessions and was repeated in the handover, where it was believed. Whatever went wrong with that test, the conclusion did not survive re-running it. **Re-run a cheap test rather than trusting a note about it**, especially a note that leaves something unexplained.
- **Five bugs in `verify.py` itself.** Ranking candidate positions by "fewest real differences" scores a run of zeros as perfect. Ranking by "most exact matches" drifts when sizes differ. Counting any zero as a fixup let long zero runs swallow real divergences — `ASCIIZ` read 68% and was actually 6%, which is why the four-byte cap exists. Requiring the whole segment to fit inside the `.TPU` made a partial unit report `NOT LOCATED` when its opening was perfect. And the four-byte cap itself then reported an unresolved TABLE of `DW OFFSET`s — a 32-byte run of zeros — as 132 real differences in the gain ladder, which the docs carried for several sessions. **The tool has been wrong more often than the transcription has.** Distrust a surprising measurement before distrusting the code.
- **A prediction in a handover, tested and falsified.** An earlier note said the ladder's 132 differences were displaced offsets that would close when `06ff..0745` landed. It landed; they did not close; they had never been differences. Predictions in a handover get believed — mark them as predictions.
- **Stale arithmetic in a hand-rolled check.** The per-block positional comparison uses a shift per block, and after an edit shortened one procedure the hardcoded shifts were one byte out, reporting 73 mismatches where there were none. Search for the shift; never hardcode it.
- **Assuming an encoding trap was fixed everywhere it occurred.** The `SUB`/`ADD`/`RET` direction problem was fixed in the gain ladder's cells and left in its patcher, in `SharedPoll`, and in `GetPlayPos`. Eight instances across three files. When a systematic encoding difference turns up, grep the whole tree for the mnemonic.
- **Reporting on a stale `.TPU`** after a lint failure, which produced a confidently wrong claim that a fix had no effect.
- **A zero in the `.TPU` is only innocent if something is genuinely pending.** `SharedPoll` called a one-byte stub for as long as the unit existed, and the comparison read it as agreement because TP emitted the call's displacement as zero and `verify.py` filed it as a fixup.
- **The probe sense specifically.** `109c:0021` looks like it tests `Autodetect`'s result. Its bytes are `75 00` — a `JNZ` with a **zero displacement**, which falls through to the next instruction. No site in the program tests that result. Do not re-derive this.
- **`165a:037a` is a downsampler**, not a peak scan and not a loop fixup — it averages PAIRS of 8-bit signed samples and writes them back at half the index. The earlier reading ("16-bit samples, high byte taken") was wrong: both bytes are used and both sign-extended, which is why `CBW` appears twice.

---

## Standing rules

**METHOD, learned the expensive way and worth following from the first line of a new segment:**

- **Run `python v1.31b/census.py <seg>` FIRST, every time.** It has now done most of the structural work on five consecutive segments. Its far-return counts are a routine census whose stack-cleanup numbers are a signature; an absence of printable strings is evidence; a missing call proves a missing routine.
- **But census.py counts FAR returns only.** A near routine ends in `RET` and an interrupt handler in `IRET`, and it sees neither. A one-line byte search for `CF` found `193a`'s single interrupt handler and settled a layout question the census could not reach.
- **Read the release's counterpart BEFORE writing a line**, then write the WHOLE unit and measure. **The top-down rule is about SOURCE ORDER, not about how much to write between builds** — misreading it as "one routine per build" cost several slow sessions. `154d` went in whole in one pass; `19a0`'s last fourteen routines went in on a single build.
- **Diagnose by divergent RUNS, not by the first divergent byte.** Ask where the long stretches of disagreement are; a single early difference is nearly always a jump displacement carrying everything downstream. **Subtract two displacements and the difference is a byte count** — it tells you how much code is missing without locating it.
- **A ROUTINE THAT TOUCHES MANY GLOBALS AT ONCE IS THE INSTRUMENT FOR DGROUP LAYOUT.** `SbRegDetect` rewrites twenty-eight ports; `InitValues` and `Free` touch every field of `TSong`; `193a`'s init section fills four device records; `142f`'s dispatch table named seventeen routines. When a segment's globals or routines are unknown, find the routine that initialises or rewrites all of them.
- **Prefer that routine's ORDER over any single store.** `+$0a` was named `Name` from one accessor and was wrong; `Free`, which touches seven fields in the release's order, corrected it. One accessor is not enough to name a field.

Carried from parts 001–008, unchanged:

- Hand-written assembler is transcribed **verbatim**, never re-expressed as Pascal. Every line carries its address; a block comment above holds the equivalent Pascal, labelled reference-only.
- **Never copy an absolute DGROUP address.** `MOV AX,1CAAh` becomes `SEG @DATA`; `MOV DI,432Ch` becomes `OFFSET SelfName`.
- **ADOPT THE RELEASE'S NAMES.** Where a routine, global or file in `v1.39b/LIB/` is the counterpart of one of ours and the two bodies agree, our provisional name is renamed to the release's — including the FILENAME and the unit name.
  - The pairing must be **confirmed by reading both bodies**, not inferred from position or a plausible-sounding name. The release settles shapes and names; the disassembly settles data.
  - Renaming cannot move a byte, so **`verify.py` is the check**: same region count before and after.
  - Two release names corrected misleading ones — `ProbeDram` probes voice registers, not DRAM (`ProbeUltrasound`), and `StopTimers` stops only timer 1 (`GUSStopTimer1`).
  - **Do not change a TYPE to match the release**, and above all **do not take a record LAYOUT from it**. 1.39b's `VoicesChanged` is a `BOOLEAN`; ours stays a `Byte` because the code tests `<> 0` and stores `1`. Rewriting those is a codegen change wearing a rename's clothes.
  - Where the release's parameter name would collide with one of our globals, or would be substituted into prose (`i` for `IRQ`), keep ours and say so in a comment.
- Names are still provisional in ONE respect — the original carries no debug information, so nothing proves 1.31 spelled them as 1.39b does.
- Git commits use the repo's own configured identity (`sweetlilmre <sweetlilmre@gmail.com>`), never `-c user.name` / `-c user.email`, and include `Co-authored-by: Claude <noreply@anthropic.com>`. **Nothing in `v1.31b/` can be committed at all** — only `tools/` scripts about it, like `tools/dosbox/vtbuild.py` and `tools/unlzexe.py`.
- **Do not guess. Read the disassembly.**

---

## The main project, for when this is finished

DemoVT is a separate line of work from the Psycho Neurosis reconstruction, whose entry point is `docs/24-continuation.md`. Do not confuse the two.

Parts 001–007 are reconstructed and build (`python tools/dosbox/dosbuild.py`); `python tools/asmverify.py` reports the locked routines. The user still owes a side-by-side of parts 001–007 against the originals. `NEUROSIS.000` (setup, `STARTUP.PAS`) and `NEUROSIS.009` (end screen, `BYEBYE.PAS`) are **not** reconstructed and both ship with Borland debug info, so their original unit and symbol names are recoverable — the obvious next Asphyxia-side task.
