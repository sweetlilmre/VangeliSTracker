# Continuation — the DemoVT v1.51 reconstruction

**Start here.** This is the v1.51 handover. It is a *separate* document from `v1.31b/docs/CONTINUATION.md`, deliberately: that one describes the first reconstruction and is worth reading for METHOD, but every number, address and layout fact in it is v1.31b's and is wrong here. Where this file needs one of its findings, it restates it.

**This directory is its own host root.** `kit.toml` sits beside this `docs/`, so `kit/tools/project.py` resolves v1.51's answers when the working directory is inside it. `v1.31b/` is the same shape, with its own `kit.toml`; the repository root has none. Run every command below from `v1.51/`.

---

## WHERE THIS STANDS — DONE, 29 August 2026

**`DEMOVT.EXE` rebuilds from source, all 36,008 bytes, byte for byte.** Not the load image only — the packed file that actually shipped.

    cd v1.51
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\units.py units.toml
        2 byte-identical, 26 identical but for fixups, 0 mismatched, 0 missing

    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\linkbytes.py link.toml
        0 differing byte(s) in the linked image

    ..\.venv\Scripts\python.exe ..\kit\tools\substrate\lzpack.py build\VTMAIN.EXE ..\DEMOVT15\DEMOVT.EXE
        round trip: our packed file decodes back to the input image exactly
        packed 36008 bytes / original 36008 bytes
        BYTE-IDENTICAL to the original packed file.

The 63,040-byte load image matches in every byte: all thirty-two code segments, the whole initialised DGROUP, and a relocation set that is identical linearly — 843 entries at the same 843 addresses. `status.toml` records the claim as **R7** against `sha256 6b536880…`, and `artefact.py status.toml --check` re-measures it rather than trusting the row.

**Two residuals in the UNPACKED comparison are not defects.** The relocation table's segment:offset split and a `$FFFF` maxalloc are LZEXE's own conventions, reconstructed by `unlzexe.py` rather than emitted by the linker. The packed file is the artefact that shipped, and it is the one that matches.

### The target, in numbers

| | |
|---|---|
| the target | `DEMOVT15/DEMOVT.EXE`, 36,008 bytes, LZEXE 0.91-packed, dated 27 Apr 1994 |
| unpacked | `ref/vt1.51.bin` — 66,448 bytes, a 3,408-byte header and a **63,040-byte load image** |
| v1.31b, for scale | a 55,056-byte load image. v1.51 is **+7,984** |
| segments | **33** — 32 code and data segments, then DGROUP at `1e92` — against v1.31b's 31 |
| units | **28** rows in `units.toml`, against v1.31b's 27; the program segment is measured by `linkbytes`/`blockcmp`, not by a unit row |
| the compiler | **Turbo Pascal 6**, measured, not carried — see below |

### The routine gate

    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\build.py build.toml       32 target(s) compiled
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\linkbytes.py link.toml    0 differing byte(s)
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\build.py cleanbuild.toml  32 target(s) compiled
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\linkbytes.py link.toml    0 differing byte(s)
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\objcheck.py objmodules.toml
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\tagcheck.py              0 untagged apparatus comments
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\braces.py src\*.PAS      0

**Both trees means `src` and `clean-src`.** The documentation copy compiles to the same bytes as the program it documents, which is the check the transform exists to keep true — see `09-documentation-transform.md` and `adr/0001-documented-source.md`.

### THE COMPILER IS MEASURED

`RTLPROBE.PAS` in `probe/` is a four-line program. Built with each install and searched for in both binaries with relocations masked (`rtl.py match`):

| probe | in vt1.31b.bin | in vt1.51.bin |
|---|---|---|
| TP 6.0 | found at seg 1ba1, 33.1% | **found at seg 1d89, 33.1%** |
| TP 6.01 | found, 33.0% | found, 33.0% |
| TP 7.01 | **NOT FOUND** | **NOT FOUND** |

The *not found* is the useful half. 6.0 and 6.01 are not separable this way — exactly as they are not on v1.31b — so the patch level is open here too. The method is a wiki observation, `minimal-program-fingerprints-the-compiler`; the trap it cost is in its blind-spot section, and it is worth reading before re-running it: `rtl.py match` resolves the reference segment in the *project's* `first_para` frame, so a probe binary that loads at 0 needs its segment expressed as `0x1003`, not `0x3`. Passing `0x3` computes a negative file offset and reports `RTL prologue NOT FOUND` — an absence that means "I looked outside the file".

---

## WHAT THE AUTHOR ACTUALLY CHANGED

v1.51 is v1.31b plus S3M support, and that shape is what made the job tractable: most units did not change at all, so eighteen of twenty-seven rebuilt their v1.51 segment on day one from the v1.31b source with three edits. `WHATSNEW.DOC` in `DEMOVT15/` lists the features; the binary said which units carried them, through two instruments that are the kit's now:

    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\segpair.py --pair ..\build\VTMAIN.EXE ref\vt1.51.bin
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\verdiff.py ..\v1.31b\ref\vt1.31b.bin 154d ref\vt1.51.bin 173d

`segpair --pair` pairs the two releases' segments by content; `verdiff` buckets one segment pair's differences by delta, so a shift repeated forty times is one line instead of forty. **Read `verdiff`'s output as three separate things**: a `byte` bucket is a record field that moved, a `word` bucket is DGROUP that moved, and the `REAL CHANGES` list is the only part worth a disassembly.

**Sixteen units had NO real change at all** — every difference was a shift: `FILEUTIL`, `CMDLINE`, `VTCFG`, `VTCTRL`, `FILTERS`, `ASCIIZ`, `VTNOTES`, `UNKLOADER`, `SONGELEMENTS`, `HEAPS`, `VTDOSMEM`, `VTDOSRSZ`, `VTSHELL`, `SOUNDDEVICES`, `HARDWARE`, `VTRESID`, plus the RTL's `DOS` and `OBJECTS`.

**Eight units and the program did have real changes.** This was the work list, and it was worked easiest first:

| unit | v1.31b → v1.51 | what it was |
|---|---|---|
| `SOUNDBLASTER` | 1904 → 1904 | no real change; difflib splitting one data reference |
| `GUS` | 2752 → **2656** | a block DELETED. CallMusic is no longer a no-op under GUS |
| `DEVGUS` | 384 → 384 | the GUS partiture change's other half |
| `DEVSB` | 1632 → 1632 | byte-exact from one instruction |
| `VTCMD` | 3296 → 3392 | new switches — `/port:` and `/irq:` |
| `DEMOVT` (program) | 1616 → **1760** | new init; the "no song" message went from Spanish to English |
| `MODCOMMANDS` | 2176 → **2992** | "Added some commands" — the largest addition outside the loaders |
| `VTSILENC` | 496 → **576** | heavily rewritten: the hardcoded COM1 base `$3F8` became a variable |
| `PLAYMOD` | 5968 → **6896** | the biggest, and last |

### And two segments were entirely new

`segpair --pair` reported them as right-hand segments nothing paired with. They sit adjacent, between `FILTERS` and `MODLOADER`, and they are **`STMLOADE.PAS`** (2,368 bytes at `15d0`, Scream Tracker 2 `.STM`) and **`S3MLOADE.PAS`** (3,472 bytes at `1664`, `.S3M`). Both are transcribed, both are byte-exact, and both have rows in `units.toml`.

The `SongLoaders` table proved what they were rather than the shape suggesting it. `DS:$0430` holds sixteen bytes — four (offset, segment) pairs:

    [1] 1839:0000    UnkLoader.LoadJMFileFormat   the 'JMPLAY' recogniser
    [2] 1664:0a8b    S3MLOADE.LoadS3MFileFormat
    [3] 15d0:0764    STMLOADE.LoadSTMFileFormat
    [4] 173d:0bd4    ModLoader.LoadModFileFormat

v1.31b's table is at `DS:$03c4`, is eight bytes, and holds exactly entries [1] and [4]. So v1.51 inserts two loaders between them, and this is the order `TSong.Load` tries them in.

**Both follow `MODLOADE.PAS`'s shape exactly** — a recogniser that sets `FileFormat` before testing, three or four near-local helpers, and one far entry — so that file was the template rather than a reference.

| | `.STM` (`15d0`) | `.S3M` (`1664`) |
|---|---|---|
| `FileFormat` | `$0b` | `$09` |
| magic | `'!Scream!'` at `Header+$14`, `DS:$0460` | `'SCRM'` at `Header+$2c`, `DS:$0468` |
| skips to | `Pos + $490` — 48 header + 31×32 instruments + 128 order | `Pos + $60` — the S3M header |
| channels | fixed 4 | `$10`, then narrowed to what the patterns use |
| tempo | `InitialBPM := 125`, tempo from `Header[$20] shr 4` | `Header[$31]` and `Header[$32]` |
| volume | `Header[$22] shl 2`, `$40` clamped to `$3f` first | `Header[$30]*4 + 3`, same clamp |

`DecodeStmPatternEvents` was the hard part: it converts STM effect codes to the player's own command set with a fifteen-way case — `1→$10`, `2→$0c`, `3→$0e`, `4→$0b`, `5→$03`, `6→$02`, `7→$04`, `8→$05`, `A→$01`, and anything else to `code + $24` — and looks the period up in `VTNOTES`'s table at `DS:$04bc`. So the STM unit `uses VTNotes`, which nothing else about it would have said.

`ref/vt1.51.bin` is imported into the Ghidra project under `v1.51/ghidra/` (untracked — it is a working artefact with locks in it; the findings belong here). **Ghidra's auto-analysis finds ZERO functions on its own**, which is worth knowing before opening it: every entry point has to be created by hand, and the `SongLoaders` table is where the first four come from.

---

## THE FINDINGS WORTH CARRYING FORWARD

### `TSong` grew 32 bytes — `ChannelPan`

Three independent readings agreed, which is what made it safe to insert a field into a record eight other units index:

* `verdiff 14b9 -> 153a` buckets **51 displacement changes at exactly +$20**, and the smallest old displacement in the bucket is **$29**. A field below an insertion does not move, so the insertion is *at* +$29.
* `TSong`'s VMT size word reads **$7e** at `DS:$0424`, where v1.31b's reads `$5e` at `DS:$03b8`. $5e + $20.
* `InitValues` gained exactly one statement, and it copies **32 bytes from `DS:$0440` into `Self+$29`**.

The constant at `DS:$0440` is `40 B0 B0 40` repeated eight times — L-R-R-L panning, symmetric about 128, tiled across 32 channels. Thirty-two is S3M's channel count. So the field is `ChannelPan : TChannelPan`, and the constant is `DefaultChannelPan`. `LoadS3MFileFormat` is its consumer and is what confirms it beyond argument: for `i := 1 to 32` it reads the S3M channel setting at `Header+$3f+i` and writes `Song+$28+i` — exactly the inserted range — with `$40` when bit 3 of the setting is clear and `$B0` when it is set.

**It must be a NAMED type on both sides.** The new statement compiles to `1d89:09f7`, the copy helper *without* the overlap check, which Turbo Pascal emits for a whole-array assignment between operands of the same named type. `Move` compiles to `1d89:0fb2`, eleven bytes away. An anonymous `array[0..31] of Byte` forces the site to be `Move` and picks up the wrong helper — the same distinction that cost v1.31b two of its last five divergent bytes, and the wiki's `two-helpers-one-signature`.

That one change fixed three units at once: `SONGUNIT`, `MODLOADER` and `UNKLOADER`.

### DATA TRANSCRIBED FROM ONE VERSION IS A MEASUREMENT OF *THAT* VERSION

**The last 253 differing bytes in the whole reconstruction were a table carried forward from v1.31b.** `VolumeTable` in `GUS` is 128 words of logarithmic volume ramp, and 1.51 retuned it: only entry 0 survives, `$1800`, which is also the only value that ever agreed with the 1.39b release. The routine that reads the table is identical in all three builds, **so no comparison of code could ever have said the numbers were stale** — the unit verified byte-for-byte throughout while 253 of its 256 table bytes were wrong. The wiki carries it as `data-measures-one-version`.

Two bytes said COM1 where 1.51 defaults to **COM2** — `$02F8` and IRQ 3. No instruction names either value; a command-line switch overwrites them, so only the image says what the default is.

### `MODLOADER`'s only real change is a DELETION

35 bytes at `154d:09e3`, the whole of

    for i := 0 to 127 do
      if Mod31.PatternList[i] > 63 then Exit;

`WHATSNEW.DOC` lists "Now it can play MODs with more than 64 different patterns" under v1.50, credited to Jare. Every other byte of a 3,920-byte unit is a displacement or a DGROUP address. The name and sequence-length checks stay — the loader did not stop validating, it stopped enforcing a limit the player outgrew.

### Three more that the wiki now carries

* `no-writer-means-input` — a flag with no writer in this image is an INPUT, not dead state. Correcting that took the reconstruction to 28 of 32 units exact in the linked image.
* `constant-only-half-applied` — one literal `8` was the whole DGROUP deficit at the point twenty units were byte-identical.
* `unpacked-is-a-reconstruction` — `ref/vt1.51.bin` is `unlzexe.py`'s output, not a shipped file, which is why the two header residuals above are conventions rather than defects.

---

## WHAT IS CLAIMED, AND WHAT IS NOT

**Byte-identity is not correctness.** It says this source compiles to the bytes the author shipped. It does not say the names are the author's, that a routine's purpose is what the comment claims, or that a reading of an instruction is right. Those are separate claims, and this tree marks them separately: a `[reading]` paragraph is an inference resting on somebody's reading, and it is kept in `clean-src` precisely so it can be counted and disputed.

Specifically still open:

* **`link.toml`'s ADDRESSES are measured; its NAMES were carried.** Every address is a distinct relocation target read out of the image, and Ghidra's own MZ loader independently derived the same 33 segments at the same addresses. The names came from the content pairing, which is a claim — strong where the paired sizes are equal and the score is high, weaker on the small segments where a 32-byte unit has too few windows to score. Byte-identity does not settle a name.
* **`length` in `units.toml`** is the segment extent less trailing zero padding. v1.31b's equivalent figures were arrived at differently and differ by a few bytes on some units; treat these as an upper bound rather than as a measured code length.
* **The compiler's patch level.** TP 6.0 and 6.01 are not separable by the probe, so "Turbo Pascal 6" is the honest statement.
* **`units.toml`'s own header is stale** — it still says the two loader segments have no source file. They do. It is a comment, not a measurement, and nothing reads it.

---

## IF YOU PICK THIS UP

There is no work list left. What is left is keeping the result true:

1. **Re-measure before believing anything here.** `build.py build.toml`, then `linkbytes.py link.toml`, then `lzpack.py build/VTMAIN.EXE ../DEMOVT15/DEMOVT.EXE`. A build product older than the sources is a trap the kit's tools refuse, but a stale *document* is not.
2. **Run the gate on both trees, not one.** `clean-src` is derived; if `src` moves and the transform is not re-run, the documented copy stops being a copy. `linkbytes` on `cleanbuild.toml` is what catches it.
3. **`artefact.py status.toml --check` is the R7 claim's only witness.** It has survived three rebuilds from source under DOSBox; keep it that way rather than trusting the recorded hash.
4. **Turbo Pascal refuses a source line over 127 characters — in a COMMENT exactly as in code.** Error 11, and the 18 missing-`.TPU` errors that cascade after it. Nothing else in the gate measures line length; the compiler is the only reader that does.
