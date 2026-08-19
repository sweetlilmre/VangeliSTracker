# DemoVT — how it fits together

A consolidated view of what the reverse of `NEUROSIS.008` established. The
segment-by-segment evidence is in `00-map.md`; the INT 2Fh interface, which is
the part that matters to Psycho Neurosis itself, is in `01-int2f.md`; the
entry-point inventory is in `02-functions.md`.

**This whole directory is out of source control pending a licence check.**
DemoVT v1.31 (beta) is © 1992-93 VangeliSTeam (JCAB), not Asphyxia's work.

---

## The layers

```
   PSYCHO.EXE
       |  runs NEUROSIS.008 @neurosis.cfg
       v
   1000   the program          banner, timer hook, the INT 2Fh dispatcher
   1b54   residency            the INT 2Fh server, chain stubs
   11bb   config file          VT.CFG / @<name>.cfg, the key list
   109c   playlist             a TCollection walked entry by entry
   116e   command line         the tail from PSP:$0080, tokenised
       |
       v
   14b9   the module object    constructor, header load, format id
   154d   ProTracker loader    the signature at offset 1080
   164b   one more recogniser  'JMPLAY'
   165a   samples, patterns    descriptors, and the pattern and track objects
                               the module is actually built out of
   1642   ASCIIZ -> String     for titles and sample names
       |
       v
   142f   notes and effects    period -> note, effect nibbles
   1650   period->note table   2048 answers, built once at startup
   12ba   mixing AND GUS       8-way unrolled 16.16 resampling for the
          scheduling           software path; a 25-slot voice-command
                               ring for the GUS
   1544   the output filter    three one-pole IIRs
       |
       v
   1a17   the player core      driver list, buffer, start/stop, shared poll
   17cf   memory pool          the audio buffer is carved out of it
   1880   DOS memory           INT 21h $48/$49
   188f   DOS resize           INT 21h $4A
   1b24   PC plumbing          8259 masks, IRQ vectors, 16-bit DMA
       |
       v
   1084 -> 1723   Gravis UltraSound
   193a -> 19a0   Sound Blaster
   1065           something on IRQ 4 / port $3F8
```

Borland's RTL sits underneath all of it: **`1ba1` (System)**, **`1b6f`
(Dos)**, and **`1891` (`Objects`, with the caveat in `02-functions.md`)** —
about 7.6 KB that is not DemoVT's code and was not reconstructed.

`1caa` is 3184 bytes of pure constants and holds no routines at all.

---

## The three things worth remembering

**Functions 0 and 1 are an INT 1Ch hook, not a player.** What every Psycho
Neurosis part calls `MusicStart` and `MusicStop` installs and removes a timer
hook; the music starts because the timer starts feeding the driver. Neither
touches the sound hardware. Both are idempotent, because the chain stub's own
operand doubles as the "are we hooked" flag.

**Everything hangs off one virtual slot.** `+$2a` of the current driver record
is the poll: the timer calls it four times a tick, INT 2Fh function 2 calls it
once. Drivers that need the host to feed them implement it; the GUS, which
plays from its own DRAM, just counts. Two drivers point it at `1a17:1008`,
the core's shared implementation, which switches to a private stack before
doing any work.

**Function 3 is a resync.** `DS:$4306` is the play position — set to the start
of the buffer by `1a17:00a9` (Start), and set to wherever the hardware has
actually reached by function 3, rounded down to a multiple of four. It stops
nothing. Part 001 is its only caller.

---

## The module is stored as tracks, not patterns

The single most important thing the line-by-line pass established, because
nothing about the file format hints at it.

A ProTracker pattern is 64 rows x N channels of 4-byte cells. DemoVT does not
keep it that way. `154d:0000` reads a pattern, widens it to a fixed 32-byte row
stride, converts each cell to a 6-byte event, and then **splits it into one
track per channel**, each stored separately and numbered from 1 across the
whole module. The pattern that remains is just a header — row count, channel
count, and a track number per channel.

```
   module ──▶ order table (256 bytes, one-based)
                    │
                    ▼
              pattern  ──▶  [ rows | chans | track#1 | track#2 | ... ]
                                        │
                                        ▼
                                     track  ──▶  note stream  (4 bytes/row)
                                                 effect stream (2 bytes/row)
```

Each stream carries a `FirstRow` and a `Count` and is **trimmed at both ends**,
independently of the other. A channel that plays one note in row 0 and one
effect in row 60 costs two entries, not sixty-four.

Fetching one event is then `14b9:0607`: order → pattern → track number → track
→ row. Five indirections, every one of them a bounded array lookup, and every
failure path landing on the same `FillChar` so nothing downstream has to check.

The payoff is memory. The cost is that loading is a conversion rather than a
read, which is why `154d:0000` is the largest routine in the loader.

## Two conditioning passes over every sample

`165a:0583` and `165a:037a` partition the samples between them on exactly
complementary guards, and each spends memory or bandwidth to buy the mixer a
tighter inner loop:

| | short and looped | long, or long-looped |
|---|---|---|
| routine | `165a:0583` | `165a:037a` |
| guard | length `< $80`, loop `> 0` | length `> $80`, loop `= 0` or `>= $7d0` |
| what it does | writes the loop body **three times** | **halves** the sample, 2-tap average |
| why | the resampler can run past the loop end without a wrap test | reclaims half the memory; costs an octave |

## Two output paths, not one

`12ba` is not just "the mixer". Which half of it runs depends on the driver,
and the two halves share almost nothing:

```
  software mixing (SB and the rest)        GUS
  ---------------------------------        --------------------------------
  12ba:0b29  per tick, per channel         12ba:0275  post a voice event
  12ba:0007  mix one voice                            into a 25-slot ring
  12ba:1600  the frameless kernel          12ba:02ea  flush one slot
  1544:004c  the one-pole filters          1723:08e6 / 1723:0980
```

The GUS plays from its own DRAM, so there is nothing to mix for it. DemoVT
queues voice commands into a ring of **25 slots x 8 voices x 16 bytes** and
flushes one slot per tick, which is where the GUS path gets its look-ahead.

The ring's nicest detail is its merge rule: `$FF` and `$FFFF` mean "leave this
field alone", so two effect handlers writing to the same voice in the same
tick combine instead of overwriting, and neither needs to know about the
other. Each slot is wiped after it is flushed, so "is this entry free" needs
no separate valid flag.

## Things the binary does that are worth stealing

- **A patched `JMP FAR` as vector storage.** Both chain stubs keep the
  displaced vector inside the jump instruction's own operand bytes, so there
  is no variable to get out of step and the "am I installed" test is free.
- **A computed jump into an unrolled loop.** The mixer enters its eight-way
  block N-mod-8 bodies from the end, so a run of any length costs one `MUL`
  and one indirect jump of setup and no per-sample loop overhead.
- **Self-patching the step into the instruction stream**, because every
  register is already in use.
- **`SAR`/`ADC` instead of `IMUL`** in the filter: `ADC` picks up the bit
  `SAR` shifted out, so it rounds rather than truncates, for a fraction of the
  cost on an 8086.
- **Falling back to the largest available block** when a DOS allocation fails,
  rather than giving up.
- **Two rename-sensitive checks** — `INCONEXI` in the main body, `VT` in the
  config unit — so the same executable behaves differently under different
  names.

---

## What is not done

**Nothing, on DemoVT's own code.** All 31 segments have an established
identity and the line-by-line pass is complete: every entry point the prologue
scanner found has been read, plus the frameless routines reachable by
following calls.

What remains is deliberate and recorded in `CONTINUATION.md`:

- Three details left unnamed rather than guessed at — `14b9`'s second
  256-byte table at `+$3d`, the voice record's `+$1d` byte, and whether
  `1891` is Borland's `OBJECTS.PAS` or a work-alike.
- **`1ba1` (System), `1b6f` (Dos) and `1891` (`Objects`)** — about 7.6 KB of
  Borland RTL that is not DemoVT's code and was never in scope.
- Eleven segments are not transcribed to compilable Pascal at all. The rest
  is documented, which is what was asked for.

**Sixteen units are transcribed to Pascal in `../src`, and thirteen of the
fifteen measured ones reproduce the original byte for byte.** `CONTINUATION.md`
carries the current table and `06-transcription.md` the detail; do not take a
list of filenames from this file, because the whole tree has since been renamed
to the 1.39b release's names. Until a unit is listed there as building, treat it
as untested — the first five were written before any build harness existed and
had never been through a compiler.

The 1.39b source release turned out to cover far more than the GUS, and the two
things flagged here as highest-value were both worth it. The **driver record
layout** — the `$16`-byte header, eight far method pointers from `+$16` to
`+$35`, and `Next` at `+$36` — is `TSoundDevice` in `LIB/SOUNDDEV.PAS`, and it
named all eight slots plus a one-byte `DMA` flag this tree had swallowed into
the ID string. The **track data model** is still the place to look next: its
loader lives in `LIB/PLAYMOD.PAS` and `MIXROUTS.INC`, against our untranscribed
`12ba`.
