# Continuation — the DemoVT v1.51 reconstruction

**Start here.** This is the v1.51 handover. It is a *separate* document from `v1.31b/docs/CONTINUATION.md`, deliberately: that one describes a finished reconstruction and is worth reading for METHOD, but every number, address and layout fact in it is v1.31b's and is wrong here. Where this file needs one of its findings, it restates it.

**This directory is its own host root.** `kit.toml` sits beside this `docs/`, so `kit/tools/project.py` resolves v1.51's answers when the working directory is inside it, and the repository root's answers still describe v1.31b. Run every command below from `v1.51/`.

---

## WHERE THIS STANDS — day one, 28 August 2026

    cd v1.51
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\build.py build.toml
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\units.py units.toml

        2 byte-identical, 16 identical but for fixups, 8 mismatched, 0 missing

**Eighteen of twenty-seven units already rebuild their v1.51 segment**, from the v1.31b source with three edits. That is not a surprise so much as the shape of the job: v1.51 is v1.31b plus S3M support, and most units did not change at all.

| | |
|---|---|
| the target | `DEMOVT15/DEMOVT.EXE`, 36,008 bytes, LZEXE 0.91-packed, dated 27 Apr 1994 |
| unpacked | `ref/vt1.51.bin` — 66,448 bytes, a 3,408-byte header and a **63,040-byte load image** |
| v1.31b, for scale | a 55,056-byte load image. v1.51 is **+7,984** |
| segments | **33**, against v1.31b's 31 — see `link.toml` |
| the compiler | **Turbo Pascal 6**, measured, not carried — see below |

### THE COMPILER IS MEASURED

`RTLPROBE.PAS` in `probe/` is a four-line program. Built with each install and searched for in both binaries with relocations masked (`rtl.py match`):

| probe | in vt1.31b.bin | in vt1.51.bin |
|---|---|---|
| TP 6.0 | found at seg 1ba1, 33.1% | **found at seg 1d89, 33.1%** |
| TP 6.01 | found, 33.0% | found, 33.0% |
| TP 7.01 | **NOT FOUND** | **NOT FOUND** |

The *not found* is the useful half. 6.0 and 6.01 are not separable this way — exactly as they are not on v1.31b — so the patch level is open here too. The method is now a wiki observation, `minimal-program-fingerprints-the-compiler`; the trap it cost is in its blind-spot section, and it is worth reading before re-running it: `rtl.py match` resolves the reference segment in the *project's* `first_para` frame, so a probe binary that loads at 0 needs its segment expressed as `0x1003`, not `0x3`. Passing `0x3` computes a negative file offset and reports `RTL prologue NOT FOUND` — an absence that means "I looked outside the file".

### WHAT THE AUTHOR ACTUALLY CHANGED

`WHATSNEW.DOC` in `DEMOVT15/` lists the features; the binary says which units carry them. The instrument is new and is the kit's now:

    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\segpair.py --pair ..\build\VTMAIN.EXE ref\vt1.51.bin
    ..\.venv\Scripts\python.exe ..\kit\tools\pascal\verdiff.py ..\v1.31b\ref\vt1.31b.bin 154d ref\vt1.51.bin 173d

`segpair --pair` pairs the two releases' segments by content; `verdiff` buckets one segment pair's differences by delta, so a shift repeated forty times is one line instead of forty. **Read `verdiff`'s output as three separate things**: a `byte` bucket is a record field that moved, a `word` bucket is DGROUP that moved, and the `REAL CHANGES` list is the only part worth a disassembly.

**Sixteen units have NO real change at all** — every difference is a shift: `FILEUTIL`, `CMDLINE`, `VTCFG`, `VTCTRL`, `FILTERS`, `ASCIIZ`, `VTNOTES`, `UNKLOADER`, `SONGELEMENTS`, `HEAPS`, `VTDOSMEM`, `VTDOSRSZ`, `VTSHELL`, `SOUNDDEVICES`, `HARDWARE`, `VTRESID`, plus the RTL's `DOS` and `OBJECTS`.

**Eight units and the program do have real changes**, and this is the work list, easiest first:

| unit | v1.31b → v1.51 | non-shift sites | what it looks like |
|---|---|---|---|
| `SOUNDBLASTER` | 1904 → 1904 | 2 | already passes `units.py`; the two sites are difflib splitting one data reference |
| `GUS` | 2752 → **2656** | 5 | a block DELETED. WHATSNEW: CallMusic is no longer a no-op under GUS |
| `DEVGUS` | 384 → 384 | 7 | the GUS partiture change's other half |
| `DEVSB` | 1632 → 1632 | 11 | |
| `VTCMD` | 3296 → 3392 | 11 | new switches — `/port:` and `/irq:` |
| `DEMOVT` (program) | 1616 → **1760** | 21 | new init; the "no song" message went from Spanish to English |
| `MODCOMMANDS` | 2176 → **2992** | 24 | "Added some commands" — the largest addition outside the loaders |
| `VTSILENC` | 496 → **576** | 37 | heavily rewritten: the hardcoded COM1 base `$3F8` became a variable |
| `PLAYMOD` | 5968 → **6896** | many | the biggest, and last |

### AND TWO SEGMENTS ARE ENTIRELY NEW

`segpair --pair` reports them as right-hand segments nothing paired with. They sit adjacent, between `FILTERS` and `MODLOADER`:

    15d0   2368 bytes    LOADER1 in link.toml
    1664   3472 bytes    LOADER2 in link.toml

**They are both song loaders, and the SongLoaders table proves it rather than the shape suggesting it.** `DS:$0430` holds sixteen bytes — four (offset, segment) pairs:

    [1] 1839:0000    UnkLoader.LoadJMFileFormat   the 'JMPLAY' recogniser
    [2] 1664:0a8b    LOADER2
    [3] 15d0:0764    LOADER1
    [4] 173d:0bd4    ModLoader.LoadModFileFormat

v1.31b's table is at `DS:$03c4`, is eight bytes, and holds exactly entries [1] and [4]. So v1.51 inserts two loaders between them, and this is the order `TSong.Load` tries them in.

**`15d0` is the Scream Tracker 2 (`.STM`) loader and `1664` is the `.S3M` loader.** Both are read, both are in Ghidra, and neither is transcribed yet.

### THE TWO LOADERS, AS READ

`ref/vt1.51.bin` is imported into the Ghidra project under `v1.51/ghidra/` (untracked — it is a working artefact with locks in it; the findings belong here). **Ghidra's auto-analysis found ZERO functions on its own**, which is worth knowing before opening it: every entry point has to be created by hand, and the SongLoaders table is where the first four come from. What is named and saved so far:

    15d0:0764  LoadSTMFileFormat          SongLoaders[3]
    15d0:03db  ReadStmInstrumentHeaders
    15d0:0581  ReadStmSampleData
    15d0:0000  DecodeStmPatternEvents
    1664:0a8b  LoadS3MFileFormat          SongLoaders[2]
    1664:06cb  ReadS3mInstrumentBlocks
    1664:002b  ReadS3mPatternBlocks
    1664:0000  not yet read

plus the shared helpers, named once because they appear in every decompile: `1d89:09f7 CopyArrayNoOverlapCheck`, `1d89:0fb2 RtlMoveWithOverlapCheck`, `1d89:0c05 ConvertCharArrayToString`, `1d89:0bc8 CompareStringsForEquality`, `1830:0000 ConvertAsciizToString`, and `153a:0352/0404/04b6` as `GetSongInstrument`/`GetSongTrack`/`GetSongPattern`.

**Both follow `MODLOADE.PAS`'s shape exactly** — a recogniser that sets `FileFormat` before testing, three or four near-local helpers, and one far entry — so that file is the template rather than a reference.

| | `.STM` (`15d0`) | `.S3M` (`1664`) |
|---|---|---|
| `FileFormat` | `$0b` | `$09` |
| magic | `'!Scream!'` at `Header+$14`, `DS:$0460` | `'SCRM'` at `Header+$2c`, `DS:$0468` |
| skips to | `Pos + $490` — 48 header + 31×32 instruments + 128 order | `Pos + $60` — the S3M header |
| channels | fixed 4 | `$10`, then narrowed to what the patterns use |
| tempo | `InitialBPM := 125`, tempo from `Header[$20] shr 4` | `Header[$31]` and `Header[$32]` |
| volume | `Header[$22] shl 2`, `$40` clamped to `$3f` first | `Header[$30]*4 + 3`, same clamp |

**`LoadS3MFileFormat` IS THE CONSUMER OF `ChannelPan`, and it is what confirms that field beyond argument.** For `i := 1 to 32` it reads the S3M channel setting at `Header+$3f+i` and writes `Song+$28+i` — that is `Song+$29..$48`, exactly the inserted range — with `$40` when bit 3 of the setting is clear and `$B0` when it is set. The same two values `DefaultChannelPan` tiles. A field inferred from a size, a VMT word and a copy instruction now has a reader that uses it for the thing its values say it is.

**`DecodeStmPatternEvents` is where the real work is.** It converts STM effect codes to the player's own command set with a fifteen-way case — `1→$10`, `2→$0c`, `3→$0e`, `4→$0b`, `5→$03`, `6→$02`, `7→$04`, `8→$05`, `A→$01`, and anything else to `code + $24` — and looks the period up in `VTNOTES`'s table at `DS:$04bc`. So the STM unit `uses VTNotes`, which nothing else about it would have said.

---

## THE ONE STRUCTURAL CHANGE THAT MATTERED — `TSong` GREW 32 BYTES

Three independent readings agree, which is what made it safe to insert a field into a record eight other units index:

* `verdiff 14b9 -> 153a` buckets **51 displacement changes at exactly +$20**, and the smallest old displacement in the bucket is **$29**. A field below an insertion does not move, so the insertion is *at* +$29.
* `TSong`'s VMT size word reads **$7e** at `DS:$0424`, where v1.31b's reads `$5e` at `DS:$03b8`. $5e + $20.
* `InitValues` gained exactly one statement, and it copies **32 bytes from `DS:$0440` into `Self+$29`**.

The constant at `DS:$0440` is `40 B0 B0 40` repeated eight times — L-R-R-L panning, symmetric about 128, tiled across 32 channels. Thirty-two is S3M's channel count. So the field is `ChannelPan : TChannelPan`, and the constant is `DefaultChannelPan`.

**It must be a NAMED type on both sides.** The new statement compiles to `1d89:09f7`, the copy helper *without* the overlap check, which Turbo Pascal emits for a whole-array assignment between operands of the same named type. `Move` compiles to `1d89:0fb2`, eleven bytes away. An anonymous `array[0..31] of Byte` forces the site to be `Move` and picks up the wrong helper — the same distinction that cost v1.31b two of its last five divergent bytes.

**That one change fixed three units at once**: `SONGUNIT`, `MODLOADER` and `UNKLOADER` all went from mismatched to matching, and `units.py` went 15 → 18.

### AND `MODLOADER`'S ONLY REAL CHANGE IS A DELETION

35 bytes at `154d:09e3`, the whole of

    for i := 0 to 127 do
      if Mod31.PatternList[i] > 63 then Exit;

`WHATSNEW.DOC` lists "Now it can play MODs with more than 64 different patterns" under v1.50, credited to Jare. Every other byte of a 3,920-byte unit is a displacement or a DGROUP address. The name and sequence-length checks stay — the loader did not stop validating, it stopped enforcing a limit the player outgrew.

---

## WHAT IS NOT MEASURED YET, AND MUST NOT BE READ AS PASSING

* **`SongLoaders` entries 2 and 3 point at the WRONG ROUTINE.** `nil` is the honest placeholder and TP6 refuses it — `Error 20: Variable identifier expected`, because a procedural typed constant takes an identifier, not a pointer expression. So they repeat `LoadJMFileFormat`. This costs no code: the table is initialised DGROUP data and `Load`'s call through it is a linker fixup either way. **That is exactly what makes it invisible** — only `dgimage.py` can see it, and it will report eight wrong bytes at `DS:$0434` and `DS:$0438` until the loader units exist. A green `units.py` says nothing about this.
* **DGROUP is not laid out yet, and cannot be.** The two loader units' typed constants occupy `DS:$0460..$0485` in the original, so every constant after them is at the wrong address in our build. Most of the remaining absolute-address differences are downstream of that one absence, and chasing them before the loaders exist is chasing an artefact.
* **`units.toml` has no row for `LOADER1`, `LOADER2` or the program.** An absent row is not a pass.
* **`link.toml`'s ADDRESSES are measured; its NAMES are carried.** Every address is a distinct relocation target read out of the image. The names come from the content pairing, which is a claim — strong where the paired sizes are equal and the score is high, weak on the small segments where a 32-byte unit has too few windows to score. Ghidra's own MZ loader independently derived the same 33 segments at the same addresses, which corroborates the addresses and says nothing about the names.
* **`length` in `units.toml`** is the segment extent less trailing zero padding. v1.31b's equivalent figures were arrived at differently and differ by a few bytes on some units; treat these as an upper bound rather than as a measured code length.

## WHERE TO PICK UP

1. **The two loaders.** They gate the DGROUP layout, and the DGROUP layout gates most of what is still red. Both are READ now (see above) and neither is WRITTEN. `MODLOADE.PAS` is the template. Start with `.STM` -- it is 1,100 bytes smaller, has four routines to S3M's four-or-more, and its pattern decoder is the only hard part.
2. Then the eight units above, easiest first.
3. `PLAYMOD` last, as in v1.31b.

## THE PACKED FILE

Not attempted. `kit/tools/substrate/lzpack.py` already reproduces LZEXE 0.91 exactly and `--selftest` includes **this very release's** own tools, so the packing step is expected to be free once the load image is right. It is the last thing to do, not a risk.
