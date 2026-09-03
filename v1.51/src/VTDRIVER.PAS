{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  The sound-device interface: one record of far pointers that every driver
  fills in and the player core calls through.

  THIS IS HOW THE PLAYER STAYS IGNORANT OF THE HARDWARE. Everything above this
  record -- the mixer, the sequencer, the INT 2Fh interface -- works in terms
  of "open the device", "give me the rate you can really manage", "here is a
  tick". Each driver supplies its own routines for those and links itself into
  a list; the core walks the list, asks each in turn whether its hardware is
  present, and keeps the first that says yes. Adding a card means adding a
  unit that fills in one of these, and changing nothing else.

  The drivers in this build are the Gravis UltraSound, the Sound Blaster, and
  a Silence driver that is always present and plays nothing -- which is what
  makes "no sound card" an ordinary case rather than an error path.

  IT IS A RECORD OF FAR POINTERS, NOT AN OBJECT, so a call goes through one
  indirection and there is no VMT anywhere. A reader expecting Turbo Pascal
  objects here will misread every call site.

  This unit holds no code at all. The layout is shared by every driver and by
  the core that walks them, and Pascal needs one owner for a type.

  [re] No segment of its own. See docs/06-transcription.md, "one DGROUP, many
  units".

  [re] The binary settles the record-not-object reading twice:

    * 1000:024c dispatches function 2 with `LES DI,[0b96h]` then
      `CALL DWORD PTR [DI+2Ah]` -- ONE indirection. A Turbo Pascal object
      would need two, through a VMT.
    * 106e:0101 fills the slots by writing eight far addresses straight into
      DS:$0076..DS:$0095, which is DS:$0060 + $16 .. + $35. No VMT is built
      and none is referenced.

  [re] NAMES. Confirmed against the VangeliSTracker 1.39b source release, which
  ships this record as `TSoundDevice` in LIB/SOUNDDEV.PAS. THE RELEASE IS A
  LATER VERSION AND IS NOT THE SOURCE OF TRUTH -- every field below is also
  checked against the disassembly, and where they disagree the disassembly
  wins. Nothing here rests on the release alone.
  =========================================================================== }

unit VTDriver;

interface

type
  TDevID = String[20];

  PSoundDevice = ^TSoundDevice;
  TSoundDevice = record
    { The driver's name, as it identifies itself -- 'DMA-SB-Mono' for the
      Sound Blaster, 'GUS' for the Gravis. This is what VT.CFG matches against
      when a particular card is asked for by name.

      [re] +$00, 21 bytes. DS:$0060 holds `03 'G' 'U' 'S'` and DS:$001e holds
      the Silence driver's. }
    DevID : TDevID;

    { TRUE if the device plays through the ISA DMA controller. The mixer needs
      to know because a DMA device is handed a buffer and left to drain it,
      while a non-DMA device is fed sample by sample from the timer.

      The GUS sets this FALSE even though it is perfectly capable of playing:
      it has its own on-card DRAM, and the player uploads samples into it
      rather than streaming over DMA.

      [re] +$15. A ONE-BYTE FIELD THAT WAS PREVIOUSLY MISSED. This file used to
      declare the header as String[21], which is 22 bytes and swallowed this
      flag as string padding. The zero at DS:$0075 is not padding: it is FALSE.
      The pointers begin at +$16 either way, so nothing downstream moved. }
    DMA : Boolean;

    { Returns the device's display name -- a longer, friendlier string than
      DevID. The GUS driver returns an empty string, so a caller must be ready
      for one.

      [re] +$16. IT IS A FUNCTION RETURNING A STRING, which is why its
      implementation looks so strange: 106e:0055 clears one byte through a far
      pointer and ends in a plain RETF rather than RETF 4. Turbo Pascal passes
      a hidden pointer to the result buffer, and the CALLER pops it. Writing 0
      to the first byte sets the length to zero. }
    Name : Pointer;

    { "Is this hardware present?" TRUE when it is. The core calls this on each
      driver in turn and keeps the first that answers yes.

      NOTHING IN THE PROGRAM ACTUALLY TESTS THE ANSWER. Both call sites discard
      it, which means the selection is really "the first driver in the list"
      and the Silence driver's position at the end is what makes it the
      fallback. A reader tracing why a particular card was chosen should look
      at the registration order, not at this result.

      [re] A byte-pattern search for `FF 5D 1A` finds only those two:

        1000:0302   CALLF [DI+1a] then immediately CALLF something else.
        1086:0021   CALLF [DI+1a] / OR AL,AL / JNZ ...

      [re] The second one LOOKS like a test and is not. Its bytes are `75 00` -- a
      JNZ with a displacement of ZERO, which falls through to the very next
      instruction. The JZ above it, at 1086:001b, targets that same address.
      Both paths reach the SetDevice call. The source it came from must have
      had an empty statement after the `if`.

      [re] MISREADING THAT ZERO DISPLACEMENT IS WHY AN EARLIER VERSION OF THIS
      FILE CLAIMED THE SENSE WAS INVERTED -- that the result was an error code
      and zero meant success. ~~It is not~~, and the note is withdrawn. The
      sense is settled by the producers, which agree: 1911:04f1 returns 1 when
      its DRAM test passes, and 115e:0039 returns 1 unconditionally -- exactly
      what a fallback that is always available should say. The 1.39b release
      corroborates (`Autodetect : FUNCTION : BOOLEAN`, returning TRUE on
      detection) but is not what settles it. }
    Autodetect : Pointer;

    InitRut         : Pointer;  { +$1e  open the device at a given rate     }
    ChgHzProc       : Pointer;  { +$22  change that rate; GUS's is empty    }
    GetRealFreqProc : Pointer;  { +$26  the nearest rate it can manage      }

    { The timer handler, and everything hangs off it: the INT 1Ch hook calls it
      four times a tick, and INT 2Fh function 2 calls it once. What a driver
      does here is the difference between the two playback models -- the
      Silence driver points it straight at the core's own shared handler,
      while the GUS, playing from its own DRAM, only counts ticks.

      [re] +$2a. The Silence driver's target is 1bff:1008. }
    TimerHandler : Pointer;

    PollRut : Pointer;          { +$2e  hand-made polling; GUS's is empty   }
    EndRut  : Pointer;          { +$32  close the device, release hardware  }

    { The next driver in the chain, or nil at the end. Each driver unit adds
      itself during its initialisation section, so the order is the units'
      link order and not a decision made anywhere in the code. }
    Next    : PSoundDevice;     { +$36 }
  end;

implementation

end.
