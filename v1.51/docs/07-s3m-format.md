# The .S3M (Scream Tracker 3 module) file format

## What this document is, and is not

This is a **naming and corroboration aid** for the S3M loader unit being transcribed from the DemoVT v1.51 binary. It exists so that fields recovered from disassembly can be given their conventional names, and so that a guess about a field's width or meaning can be checked against what the format's own documentation says. It is **not** the specification the code is written to.

**Where the binary disagrees with this document, the binary wins.** This repository is a byte-exact reconstruction of one 1994 program. That program may implement the S3M format partially, may implement it idiosyncratically, may rely on invariants that this specification does not guarantee, or may simply be wrong about something and still need to be reproduced exactly. Nothing here licenses "fixing" the reconstruction to match the spec.

**No loader implementation source was consulted.** Not libmodplug, not the OpenMPT repository, not MikMod, DUMB, XMP, or any other player, converter or tracker clone. The reason is licensing: most such projects are GPL or similarly licensed, and this reconstruction's code must be derived from the binary it reconstructs, not from anyone else's loader. Several search results during this research were loader source files (`load_s3m.c` in MikMod/UniMod, `load_s3m.lua` in LoveTracker, `S3MTools.h` in the OpenMPT SVN tree, `s3m.cc` on bisqwit.iki.fi). **These were not opened, read, or used.** Only format documentation — field tables and prose — informed this document.

## Sources actually used

1. **`TECH.DOC` — "Scream Tracker 3.20 File Formats And Mixing Info"**, the official format document distributed with Scream Tracker 3 by Future Crew. This is the primary source and the great majority of what follows comes from it. It was read verbatim as a plain text document. Its own opening disclaimer is worth repeating: *"There might be some errors here, so if something seems weird, don't just blindly believe it. Think first if it could be just a typo or something."*
2. **ModdingWiki (shikadi.net), "S3M Format"** — a well-established format reference collection. Used as corroboration and to resolve two ambiguities in `TECH.DOC` (the channel-byte high bit, and whether the pattern length prefix counts itself).
3. **MultimediaWiki (wiki.multimedia.cx), "Scream Tracker 3 Module"** — corroboration of the header layout and the fixed 80-byte instrument header.
4. **OpenMPT *wiki*, "Development: Formats/S3M"** — the documentation wiki only, not the OpenMPT source repository. Used for tracker-fingerprinting notes on the `Cwt/v` field.
5. **sagamusix.de, "S3M Format Shenanigans" (2021)** — a prose article by the OpenMPT maintainer about real-world S3M quirks. Used only for the note on garbage past sample loop ends.

Everything below is attributed inline where sources differ or where only one source supports a claim.

## 1. The module header (96 bytes, `$00`-`$5F`)

`TECH.DOC` gives the header as a hex-grid table. Rendered as a field list, with all multi-byte integers little-endian:

| Offset | Width | `TECH.DOC` name | Meaning |
| --- | --- | --- | --- |
| `$00` | 28 | Song name | Module title, NUL-terminated, maximum 28 characters including the NUL. |
| `$1C` | 1 | `1Ah` | Constant `$1A` (DOS end-of-file marker, so `TYPE FILE.S3M` stops at the title). |
| `$1D` | 1 | `Typ` | File type. `TECH.DOC`: *"File type: 16=ST3 module"* — i.e. `$10`. |
| `$1E` | 2 | `x x` | Reserved / unused. |
| `$20` | 2 | `OrdNum` | *"Number of orders in file (should be even!)"* |
| `$22` | 2 | `InsNum` | *"Number of instruments in file"* |
| `$24` | 2 | `PatNum` | *"Number of patterns in file"* |
| `$26` | 2 | `Flags` | Feature flags; see below. Mostly legacy. |
| `$28` | 2 | `Cwt/v` | Created-with tracker / version. *"&0xfff=version, >>12=tracker"*. ST3.00 = `$1300`, ST3.01 = `$1301`, ST3.03 = `$1303`, ST3.20 = `$1320`. |
| `$2A` | 2 | `Ffi` | File format information — the sample signedness field. `1` = *"[VERY OLD] signed samples"*, `2` = *"unsigned samples"*. |
| `$2C` | 4 | `'S','C','R','M'` | Magic. The identifying signature of the format. |
| `$30` | 1 | `g.v` | Global volume. |
| `$31` | 1 | `i.s` | Initial speed — frames (ticks) per row; the `A` command changes it later. |
| `$32` | 1 | `i.t` | Initial tempo; the `T` command changes it later. |
| `$33` | 1 | `m.v` | Master volume. `TECH.DOC`: *"7 lower bits"* are the volume, *"bit 8: stereo(1) / mono(0)"* — in zero-based terms, bit 7. |
| `$34` | 1 | `u.c` | Ultra click removal. *"ST3 uses u.c gus channels to guarantee, that u.c/2 channels run without any clicks."* GUS-specific; the number ST3 displays is `u.c/2`. |
| `$35` | 1 | `d.p` | Default pan flag. *"252 when default channel pan positions are present in the end of the header... If !=252 ST3 doesn't try to load channel pan settings."* |
| `$36` | 8 | `x` x 8 | Reserved / unused. |
| `$3E` | 2 | `Special` | Parapointer to custom data, valid only when `Flags` bit 7 (`+128`) is set. *"not used by ST3.01"*. |
| `$40` | 32 | Channel settings | One byte per channel for 32 channels. See below. |

`Flags` at `$26`, per `TECH.DOC` (the first group is explicitly marked as legacy — *"These are old flags for Ffv1. Not supported in ST3.01"*): `+1` st2vibrato, `+2` st2tempo, `+4` amigaslides, `+32` enable filter/sfx with SB; then the live ones: `+8` zero-volume optimisations (*"Automatically turn off looping notes whose volume is zero for >2 note rows"*), `+16` Amiga limits (*"Disallow any notes that go beond the amiga hardware limits"*), `+64` ST3.00 volume slides (volume slide also performed on the first frame of a row; set by default when `Cwt/v` is `$1300`), `+128` special custom data present in file.

`TECH.DOC` describes the two volume fields' effects: *"Global volume directly divides the volume numbers used"* and affects both GUS and SoundBlaster, whereas *"Master volume only affects the SoundBlaster. It controls the amount of sample multiplication... The bigger the value the bigger the output volume (and thus quality) will be. However if the value is too big, the mixer may have to clip the output."* It also notes that in stereo the master multiplier is internally scaled by 11/8.

### The channel settings table at `$40`

Thirty-two bytes, one per channel. `TECH.DOC` labels the row *"Channel settings for 32 channels, 255=unused,+128=disabled"* and expands it as:

- bits 0-6: channel type
  - `0..7` — Left sample (PCM) channel 1-8
  - `8..15` — Right sample (PCM) channel 1-8
  - `16..31` — Adlib channels (9 melody + 5 drums)
- high bit (`+128`): the channel is **disabled**.
- `$FF` (255): the channel is **unused** — it carries no data and is not part of the module.

**Bit 3** (value `8`) is therefore the **left/right selector for sample channels**: within the `0..15` PCM range, clearing it gives a left channel and setting it gives the corresponding right channel. `0..7` and `8..15` are the same eight channels panned to opposite sides.

ModdingWiki gives the same mapping in expanded form — `0-7` left PCM 1-8, `8-15` right PCM 1-8, `16-24` Adlib melody 1-9, `25` bass drum, `26` snare, `27` tom tom, `28` top cymbal, `29` hi-hat, `30-127` unused/invalid, `128-254` "same as above + 128 (disabled)", `255` channel unused — and states plainly that **when the high bit is set the channel is disabled**.

**Source disagreement, flagged.** `TECH.DOC`'s expansion says *"bit 8: channel enabled"*, which contradicts its own table caption three lines earlier (*"+128=disabled"*) and contradicts ModdingWiki. Read `+128` as **disabled**; the "bit 8: channel enabled" line is best read as "bit 8 governs whether the channel is enabled", with the polarity given by the caption. (`TECH.DOC` numbers bits from 1 throughout — its "bit 8" is bit 7 zero-based, and its "bit 0-7" for the channel type is bits 0-6 zero-based.)

### Optional channel pan table

If `d.p` at `$35` equals 252, a 32-byte channel default pan table follows the pattern parapointers (see next section). Per byte: bits 6-7 reserved; bit 5 = *"1=default pan position specified, 0=use defaults: for mono 7, for stereo 3 or C"*; bits 0-3 = the default pan position.

## 2. The order table and the parapointer arrays

Immediately after the 96-byte header, three (or four) variable-length blocks follow, in this order:

| Block | Start | Length |
| --- | --- | --- |
| Order list | `$60` | `OrdNum` bytes |
| Instrument parapointers | `$60 + OrdNum` | `InsNum` x 2 bytes |
| Pattern parapointers | `$60 + OrdNum + InsNum*2` | `PatNum` x 2 bytes |
| Channel default pan (only if `d.p` = 252) | `$60 + OrdNum + InsNum*2 + PatNum*2` | 32 bytes |

**Typo in `TECH.DOC`, flagged.** `TECH.DOC`'s hex grid unambiguously places the orders at offset `$0060`, but the accompanying formulas read `xxx1=70h+orders`, `xxx2=70h+orders+instruments*2`, `xxx3=70h+orders+instruments*2+patterns*2`. `$70` is inconsistent with the grid — the 32-byte channel settings table occupies `$40`-`$5F`, so the header ends at `$60`. ModdingWiki and MultimediaWiki both give `$60`. Treat `70h` as a typo for `60h`; the *relative* structure of the three formulas is correct.

**Order list.** One byte per entry, each the index of a pattern to play. Two reserved values, per `TECH.DOC`: *"255=-- is the end of tune mark and 254=++ is just a marker that is skipped."* `OrdNum` *"should be even"* — ST3 pads to an even count.

**Parapointers.** Each is a little-endian 16-bit word. `TECH.DOC`: *"Parapointers to file offset Y is (Y-Offset of file header)/16. You could think of parapointers as segments relative to the start of the S3M file."* So to go the other way — the direction a loader cares about — **multiply the word by 16 and add the module's start offset in the file**. ModdingWiki puts it directly: *"Each parapointer is an offset from the start of the file, in units of 16 bytes (a 'paragraph'). To convert this into a normal byte-level file offset, multiply it by 16 (or shift-left by 4.)"*

The "module's start offset" qualifier matters: `TECH.DOC` says pointers are relative to the *offset of the file header*, not to byte 0 of whatever the module may be embedded in. For a standalone `.S3M` file these coincide.

Because everything after the header is reached by parapointer, `TECH.DOC` notes the blocks *"could be anywhere in the file"*, but gives the *"practical standard order"* as: header, instruments in order, patterns in order, samples in order.

## 3. The instrument / sample header (80 bytes, `$50`)

`TECH.DOC` calls this the *"Digiplayer/ST3 samplefileformat"*. The same 80-byte structure appears inline in the S3M for each instrument, and also as the header of standalone sample files saved from ST3. Every parapointer in the instrument array points at one of these.

| Offset | Width | `TECH.DOC` name | Meaning |
| --- | --- | --- | --- |
| `$00` | 1 | `[T]` Type | `1` = sample (PCM), `2` = adlib melody, `3`+ = adlib drum. (`0` is conventionally an empty / message slot; MultimediaWiki records `0` as "message".) |
| `$01` | 12 | Dos filename | The original DOS 8.3 filename, e.g. `12345678.ABC`. Not NUL-terminated in the file — but see the MemSeg note below. |
| `$0D` | 3 | `MemSeg` | Parapointer to the sample data. **24 bits wide in the file.** |
| `$10` | 4 | `Length` / `HI:leng` | Sample length in bytes. |
| `$14` | 4 | `LoopBeg` / `HI:LBeg` | Loop begin, in bytes. |
| `$18` | 4 | `LoopEnd` / `HI:Lend` | Loop end, in bytes. |
| `$1C` | 1 | `Vol` | Default volume, `0..64`. |
| `$1D` | 1 | `x` | Unused / reserved. |
| `$1E` | 1 | `[P]` Pack | `0` = unpacked, `1` = DP30ADPCM packing (*"not used by ST3.01"*). |
| `$1F` | 1 | `[F]` Flags | `+1` loop on; `+2` stereo; `+4` 16-bit sample. *"(+2/+4 not supported by ST3.01)"* |
| `$20` | 4 | `C2Spd` / `HI:C2sp` | *"Herz for middle C. ST3 only uses lower 16 bits."* |
| `$24` | 4 | `x` x 4 | Unused. |
| `$28` | 2 | `Int:Gp` | Internal, in-memory only: *"Address of sample in gravis memory /32"*. |
| `$2A` | 2 | `Int:512` | Internal, in-memory only: *"flags for soundblaster loop expansion"*. |
| `$2C` | 4 | `Int:lastused` | Internal, in-memory only: *"last used position (only works with sb)"*. |
| `$30` | 28 | Sample name | *"28 characters max... (incl. NUL)"* |
| `$4C` | 4 | `'S','C','R','S'` | Magic for a PCM instrument. |

Notes drawn directly from `TECH.DOC`:

- **The three 32-bit sizes.** *"Length / LoopBegin / LoopEnd are all 32 bit parameters although ST3 only support file sizes up to 64,000 bytes. Files bigger than that are clipped to 64,000 bytes when loaded to ST3."*
- **Loop end is exclusive.** *"NOTE that LoopEnd points to one byte AFTER the end of the sample, so LoopEnd=100 means that byte 99.9999 (fixed) is the last one played."*
- **`MemSeg` is dual-purpose.** *"Inside a sample or S3M, MemSeg tells the parapointer to the actual sampledata. In files all 24 bits are used. In memory the value points to the actual sample segment or Fxxx if sample is in EMS under handle xxx. In memory the first memseg byte is overwritten with 0 to create the dos filename terminator nul."* That last clause explains the odd 12-byte-filename-then-3-byte-pointer layout: byte `$0D` doubles as the filename's NUL once ST3 has loaded the module.
- **Stereo layout.** Flag `+2`: *"after Length bytes for LEFT channel, another Length bytes for RIGHT channel"* — the channels are stored consecutively, not interleaved.
- **16-bit layout.** Flag `+4`: *"16-bit sample (intel LO-HI byteorder)"*, i.e. little-endian.

ModdingWiki's field table agrees throughout, and splits `MemSeg` explicitly as `$0D` = *"Upper eight bits of parapointer to sample data"* and `$0E` = a 16-bit little-endian *"Lower 16 bits"*. So the 24-bit value is **not** a plain little-endian 24-bit integer: it is high-byte first, then the low 16 bits little-endian. ModdingWiki also gives volume as *"0-63 inclusive"* where `TECH.DOC` says `0..64`; a minor disagreement, and `TECH.DOC` is the primary source.

### Adlib instruments

Included only because the type byte selects between them. Type `2` = adlib melody, `3` = bass drum, `4` = snare, `5` = tom, `6` = cymbal, `7` = hi-hat. Layout: type at `$00`, DOS filename at `$01` (12 bytes), three `$00` bytes at `$0D`, twelve OPL register bytes `D00`-`D0B` at `$10`, `Vol` at `$1C`, `Dsk` at `$1D`, unused at `$1E`, `C2Spd` at `$20` (*"Actually this is a modifier since there is no clear frequency for adlib instruments. It scales the note freq sent to adlib."*), unused through `$2F`, sample name at `$30` (28 bytes), magic `'SCRI'` at `$4C`. The `D00`-`D0B` packing per `TECH.DOC`, modulator byte then carrier byte: `D00`/`D01` = freq. multiplier + scale-env*16 + sustain*32 + pitch-vib*64 + vol-vib*128; `D02`/`D03` = (63-volume) + (levelscale&1)*128 + (levelscale&2)*64; `D04`/`D05` = attack*16 + decay; `D06`/`D07` = (15-sustain)*16 + release; `D08`/`D09` = wave select; `D0A` = modulation feedback*2 + additive synthesis; `D0B` unused.

## 4. The packed pattern encoding

Each pattern parapointer points at a packed pattern block:

```
offset $00: WORD  Length   -- length of the packed pattern
offset $02: ...   packed data
```

**Does the length include itself?** `TECH.DOC` says only *"Length = length of packed pattern"*, which is ambiguous. ModdingWiki resolves it: *"packed_len includes its own length, so as it is two bytes long, the length of the packed data will be two bytes less than this value."* It further states *"After the 64th row has been reached, the pattern ends and packed_len bytes will have been read."* This is a single-source claim; the binary is the authority for what DemoVT actually does with the word.

**Shape of the unpacked pattern.** *"Unpacked pattern is always 32 channels by 64 rows."* `TECH.DOC` gives ST3's internal in-memory layout for reference — *"each channel takes 320 bytes, rows for each channel are sequential, so one unpacked pattern takes 10K"* — with five bytes per cell:

```
byte 0 - Note; hi=oct, lo=note, 255=empty note,
         254=key off (used with adlib, with samples stops smp)
byte 1 - Instrument      ;0=..
byte 2 - Volume          ;255=..
byte 3 - Special command ;255=..
byte 4 - Command info    ;
```

**The packed stream.** `TECH.DOC`, quoted in full:

```
Packed data consits of following entries:
BYTE:what  0=end of row
           &31=channel
           &32=follows;  BYTE:note, BYTE:instrument
           &64=follows;  BYTE:volume
           &128=follows; BYTE:command, BYTE:info

So to unpack, first read one byte. If it's zero, this row is
done (64 rows in entire pattern). If nonzero, the channel
this entry belongs to is in BYTE AND 31. Then if bit 32
is set, read NOTE and INSTRUMENT (2 bytes). Then if bit
64 is set read VOLUME (1 byte). Then if bit 128 is set
read COMMAND and INFO (2 bytes).
```

Restated as a bit layout of the `what` byte:

| Bits | Meaning |
| --- | --- |
| 0-4 (`and 31`) | Channel number, 0-31 |
| 5 (`and 32`) | Note **and** instrument present — two bytes follow, note first |
| 6 (`and 64`) | Volume present — one byte follows |
| 7 (`and 128`) | Effect present — two bytes follow, command then info |

The whole byte being `$00` terminates the row. Note that **bit 5 is a single present-bit covering both note and instrument** — they are not independently optional. The three optional groups are read in bit order 5, 6, 7: note/instrument, then volume, then command/info. A row with no data at all is a single `$00` byte; a full pattern is 64 such rows, so the decoder loop terminates after the 64th zero byte, and (per ModdingWiki) that coincides with having consumed `Length` bytes.

**Note byte packing.** *"hi=oct, lo=note"* — the high nibble is the octave, the low nibble the semitone within the octave. ModdingWiki spells out the semitone numbering: *"The upper four bits of note store the octave, and the lower four bits store the semitone (with 0=C, 1=C#, up to 11=B)"*. So a note byte of `$4A` is octave 4, semitone 10 = A-4.

**Special note values.** `$FF` (255) = empty, no note. `$FE` (254) = key off — *"used with adlib, with samples stops smp"*.

**Volume.** `$FF` (255) means "no volume column entry", so the instrument's default volume applies. ModdingWiki: *"The volume field is 0 for silent, 64 for full volume (note this is 65 unique values), or 255 for 'ignore'... If the value is 255 or missing entirely, the instrument's default volume is used."*

**Effect command.** `$FF` (255) means no command, per `TECH.DOC`'s unpacked layout comment (*"Special command ;255=.."*). `TECH.DOC` does not enumerate the effect letters; it says *"For information on commands / how st3 plays them, see the manual"*, meaning the Scream Tracker 3 user manual, which was not consulted for this document.

## 5. Sample data

Sample data lives wherever the instrument header's `MemSeg` parapointer points. For an 8-bit mono unpacked sample it is `Length` bytes of raw PCM. For stereo (flag `+2`) it is `Length` bytes of left followed by `Length` bytes of right. For 16-bit (flag `+4`) the samples are little-endian 16-bit words. Flags `+2` and `+4` are *"not supported by ST3.01"*.

**Signed versus unsigned.** The header's `Ffi` word at `$2A` declares it, and `TECH.DOC` gives exactly two values:

```
Ffi     = File format information
                1=[VERY OLD] signed samples
                2=unsigned samples
```

ModdingWiki records the same two values, annotating `1` as *"[deprecated]"*. MultimediaWiki phrases them as *"signed samples (horribly, horribly old)"* and *"unsigned samples"*, and adds *"anything else is invalid and ST3 will not load the file(?)"* — the question mark is theirs, so that last clause is not firm.

So: **ST3-era files are overwhelmingly `Ffi = 2`, unsigned**, and `Ffi = 1` (signed) marks pre-release and very early files. The 8-bit unsigned convention is the DOS SoundBlaster-native one; the signed convention is the Amiga / ProTracker one, which is why the earliest Scream Tracker generation used it.

**On detecting signedness at load time — what I could and could not establish.** The mechanical fact that a loader must branch on `Ffi` (or else assume one convention) is well documented and is stated above. The stronger claim in the research brief — that a loader may need to *detect* the signedness rather than trust the field, because trackers wrote the field inconsistently — **I could not establish from any primary format source.** None of `TECH.DOC`, ModdingWiki, MultimediaWiki, the OpenMPT wiki's S3M development page, or the "S3M Format Shenanigans" article documents `Ffi` being written incorrectly, nor offers any heuristic for recovering the true convention. The OpenMPT wiki's S3M page does not discuss sample signedness at all. I have deliberately not filled this in from memory, and the only places such a heuristic surfaced in search results were loader source files, excluded by the terms of this research. **Treat the "detect at load time" rationale as unverified.** If the DemoVT binary does anything other than switch on `Ffi`, the binary is the evidence, and this document has nothing to corroborate it with.

One related real-world hazard *is* documented, and is worth knowing while reading sample data in the wild: the "S3M Format Shenanigans" article reports that ST3's SoundBlaster driver had a buggy loop-unrolling routine which copied a block that extended 512 bytes past the actual sample end, so *"seemingly random crap past the sample loop end"* is common in S3M files. That is garbage data in the file rather than a signedness question, but it explains sample tails that look like noise.

## Loose ends and caveats

- `TECH.DOC`'s `70h` versus its own grid's `$60` for the start of the order list (section 2) — treated as a typo, on the strength of two secondary sources.
- `TECH.DOC`'s *"bit 8: channel enabled"* versus its own *"+128=disabled"* (section 1) — treated as `+128` meaning disabled, per ModdingWiki.
- Default sample volume range: `TECH.DOC` says `0..64`, ModdingWiki says `0-63`. `TECH.DOC` is primary.
- Whether the pattern length word counts itself rests on ModdingWiki alone; `TECH.DOC` is silent.
- Effect commands are not enumerated here — `TECH.DOC` defers to the ST3 user manual, which was outside the scope of this research.
- The signedness-detection rationale is unverified; see section 5.
