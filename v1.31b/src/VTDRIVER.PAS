{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).

  THE SOUND DEVICE RECORD -- no segment of its own.

  Like SongUnit, this unit holds no code. The layout is shared by every driver
  (1065, 1084, 193a) and by the player core that walks them (1a17), and Pascal
  needs one owner for it. See docs/06-transcription.md, "one DGROUP, many
  units".

  IT IS A RECORD OF FAR POINTERS, NOT AN OBJECT. The binary settles it twice:

    * 1000:024c dispatches function 2 with `LES DI,[0b96h]` then
      `CALL DWORD PTR [DI+2Ah]` -- ONE indirection. A Turbo Pascal object
      would need two, through a VMT.
    * 1084:0101 fills the slots by writing eight far addresses straight into
      DS:$0076..DS:$0095, which is DS:$0060 + $16 .. + $35. No VMT is built
      and none is referenced.

  NAMES. Confirmed against the VangeliSTracker 1.39b source release, which
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
    { +$00 -- the identification string, 21 bytes. DS:$0060 holds
      `03 'G' 'U' 'S'` and DS:$001e holds the Silence driver's. }
    DevID : TDevID;

    { +$15 -- TRUE if the device plays through DMA.

      A ONE-BYTE FIELD THAT WAS PREVIOUSLY MISSED. This file used to declare
      the header as String[21], which is 22 bytes and swallowed this flag as
      string padding. The zero at DS:$0075 is not padding: it is FALSE, and
      correctly so, because the GUS plays out of its own DRAM rather than
      over the ISA DMA channel.

      The pointers begin at +$16 either way, so nothing downstream moved. }
    DMA : Boolean;

    { +$16 -- returns the device's display name.

      IT IS A FUNCTION RETURNING A STRING, which is why its implementation
      looks so strange: 1084:0055 clears one byte through a far pointer and
      ends in a plain RETF rather than RETF 4. Turbo Pascal passes a hidden
      pointer to the result buffer, and the CALLER pops it. Writing 0 to the
      first byte sets the length to zero -- the GUS driver returns ''. }
    Name : Pointer;

    { +$1a -- "is this hardware present?" TRUE when it is.

      NO CONSUMER IN THE PROGRAM TESTS THE RESULT. Both call sites discard
      it, and a byte-pattern search for `FF 5D 1A` finds only those two:

        1000:0302   CALLF [DI+1a] then immediately CALLF something else.
        109c:0021   CALLF [DI+1a] / OR AL,AL / JNZ ...

      The second one LOOKS like a test and is not. Its bytes are `75 00` --
      a JNZ with a displacement of ZERO, which falls through to the very
      next instruction. The JZ above it, at 109c:001b, targets that same
      address. Both paths reach the SetDevice call, so the answer changes
      nothing. The source it came from must have had an empty statement
      after the `if`.

      MISREADING THAT ZERO DISPLACEMENT IS WHY AN EARLIER VERSION OF THIS
      FILE CLAIMED THE SENSE WAS INVERTED -- that the result was an error
      code and zero meant success. It is not, and the note is withdrawn.

      The sense is settled by the producers, which agree with each other:
      1723:04f1 returns 1 when its DRAM test passes, and 1065:0039 returns 1
      unconditionally -- which is exactly what a fallback that is always
      available should say. The 1.39b release corroborates
      (`Autodetect : FUNCTION : BOOLEAN`, returning TRUE on detection) but
      is not what settles it. }
    Autodetect : Pointer;

    InitRut         : Pointer;  { +$1e  open the device at a given rate     }
    ChgHzProc       : Pointer;  { +$22  change rate; GUS's is empty         }
    GetRealFreqProc : Pointer;  { +$26  the rate it can really manage       }

    { +$2a -- the timer handler. Everything hangs off this one: the INT 1Ch
      hook calls it four times a tick and INT 2Fh function 2 calls it once.
      The Silence driver points it straight at the core's own shared handler
      at 1a17:1008; the GUS, which plays out of its own DRAM, only counts. }
    TimerHandler : Pointer;

    PollRut : Pointer;          { +$2e  hand-made polling; GUS's is empty   }
    EndRut  : Pointer;          { +$32  close the device                    }
    Next    : PSoundDevice;          { +$36  the linked list                     }
  end;

implementation

end.
