# DemoVT v1.51 — reading the source

A DOS music player from April 1994. It loads a tracker module, mixes it in software or hands it to a Gravis Ultrasound, and plays it in the background while a demo runs in the foreground — which is the thing it exists for. A demo asks it to start a tune and then forgets about it, and the music keeps time on its own.

**This copy is for reading.** It was generated from the reconstruction's own source by `kit/tools/pascal/clean.py`, which removes the reverse-engineering apparatus — segment addresses, operand deltas, notes on which instrument measured what — and keeps everything that explains the program. **It is never built.** The tree it came from is, and that one reproduces the original `DEMOVT.EXE` byte for byte.

Comments marked `[1.39b]` are the original author's own words, translated where they were Spanish, harvested from the v1.39b release of the same codebase. They are the only comments here that are not written by the reconstruction.

## The shape of it

Four layers, and almost nothing skips one:

```
  VTMAIN          the program: parse the command line, play, install the
                  INT 2Fh interface, exit
      |
  SONGUNIT        a song, and the loaders that build one from a file
  SONGELEM        what a song is made of -- notes, tracks, patterns, samples
  MODLOADE  S3MLOADE  STMLOADE  UNKLOADE
      |
  PLAYMOD         the sequencer and the mixer: what plays, and what it sounds
  MODCOMMA        like. MODCOMMA holds one routine per tracker effect
      |
  SOUNDDEV        a device, in the abstract -- buffers, polling, a driver
  DEVSB  DEVGUS   the two real ones
  SOUNDBLA  GUS   the cards themselves, ports and registers
  HARDWARE        DMA and interrupt controllers
```

`HEAPS` sits beside all of it: every allocation in the program goes through it.

## Where to start

**If you want to know how a note becomes a sound**, read in this order:

1. `SONGELEM.PAS` — the note, the instrument, the pattern. Start at `TFullNote`; the comment above it says what the four fields mean, including the two zeroes that mean "carry the previous value".
2. `PLAYMOD.PAS`, `SeqTick` — one tick of music. It decides what should be playing.
3. `PLAYMOD.PAS`, `UnCanal` — one channel's contribution to the buffer.
4. `PLAYMOD.ASM`, `DumpRaw` — the resampling kernel itself. **Read its header first**; the routine modifies its own instructions and nothing else in the file makes sense until you know that.

**If you want to know how the demo talks to it**, read `VTCTRL.PAS`. The 768-byte control block declared there is the whole public interface, and its field names are the ones the author published in the client bindings shipped with the program. The 256 semaphores at the top are how a tune signals a demo: effect command `8xx` in a pattern increments the semaphore its parameter names, and the demo polls it.

**If you want the hardware**, `SOUNDDEV.PAS` first for the shape of a device, then `GUS.PAS` or `SOUNDBLA.PAS`. Both card units open with the port map they use; read that before the routines.

## Things that will mislead you

Three routines do not do what their names say, and each says so in its header:

* **`TriggerVoice` does not trigger a voice.** It records what a voice should be doing and arms a timer; `RestartChannels` starts it later, so that restarts land on a regular boundary and do not click.
* **`SbReset` is how a SoundBlaster is detected.** There is no identifying register, so presence is established by resetting a card that may not be there and seeing whether anything answers.
* **`DevInitSbDMA` is where the output path is decided.** It writes routine addresses into slots, which is why the code that actually plays a sample contains no tests for card type or stereo.

And two more general traps:

* **Ten tick handlers are empty.** Six have nothing to do — their work happens when the note starts. Four are *not implemented*, and a module using them plays without error and without the effect. `MODCOMMA.PAS` says which are which.
* **A far pointer has 4,096 spellings.** `$1000:$0010` and `$1001:$0000` are the same byte, so pointers cannot be compared as they stand. `HEAPS.PAS` explains the three routines that exist to deal with it.

## What this program assumes about its machine

It was written for a 16-bit real-mode PC and the assumptions are everywhere rather than in one place. A segment addresses 64K, which is why four of the seven channel flags exist. Interrupts arrive at any instruction, which is why two routines keep their guard in the code segment. There is no memory protection, which is why a mixing loop can rewrite its own instructions and why that is a reasonable thing to do rather than a trick.
