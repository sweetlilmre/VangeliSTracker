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
  the core that walks them, and Pascal needs one owner for a type.}

unit VTDriver;

interface

type
  TDevID = String[20];

  PSoundDevice = ^TSoundDevice;
  TSoundDevice = record
    { The driver's name, as it identifies itself -- 'DMA-SB-Mono' for the
      Sound Blaster, 'GUS' for the Gravis. This is what VT.CFG matches against
      when a particular card is asked for by name.}
    DevID : TDevID;

    { TRUE if the device plays through the ISA DMA controller. The mixer needs
      to know because a DMA device is handed a buffer and left to drain it,
      while a non-DMA device is fed sample by sample from the timer.

      The GUS sets this FALSE even though it is perfectly capable of playing:
      it has its own on-card DRAM, and the player uploads samples into it
      rather than streaming over DMA.}
    DMA : Boolean;

    { Returns the device's display name -- a longer, friendlier string than
      DevID. The GUS driver returns an empty string, so a caller must be ready
      for one.}
    Name : Pointer;

    { "Is this hardware present?" TRUE when it is. The core calls this on each
      driver in turn and keeps the first that answers yes.

      NOTHING IN THE PROGRAM ACTUALLY TESTS THE ANSWER. Both call sites discard
      it, which means the selection is really "the first driver in the list"
      and the Silence driver's position at the end is what makes it the
      fallback. A reader tracing why a particular card was chosen should look
      at the registration order, not at this result.}
    Autodetect : Pointer;

    InitRut         : Pointer;  { +$1e  open the device at a given rate     }
    ChgHzProc       : Pointer;  { +$22  change that rate; GUS's is empty    }
    GetRealFreqProc : Pointer;  { +$26  the nearest rate it can manage      }

    { The timer handler, and everything hangs off it: the INT 1Ch hook calls it
      four times a tick, and INT 2Fh function 2 calls it once. What a driver
      does here is the difference between the two playback models -- the
      Silence driver points it straight at the core's own shared handler,
      while the GUS, playing from its own DRAM, only counts ticks.}
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
