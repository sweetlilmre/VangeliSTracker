{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  THE CONTROL BLOCK: 768 bytes of shared memory that DemoVT hands out to
  whatever program asked it to play.

  WHY A MUSIC PLAYER PUBLISHES A STRUCT. DemoVT is not meant to be run on its
  own. A demo starts it, then runs its own graphics while the music plays in
  the background off the timer interrupt -- and the two have to stay in step.
  This record is how. The demo finds it once through an INT 2Fh handshake and
  from then on simply reads memory: which pattern is playing, what each channel
  is doing, how many ticks have passed. No calls, no polling protocol.

  IT IS TWO-WAY. Some fields the player writes and the demo reads -- the tick
  counter, the per-channel state, the semaphores. Others the demo writes and
  the player reads: jump to this position, set the volume, stop. A field with
  no writer anywhere in this program is not dead code; it is an INPUT, and its
  writers are in other programs entirely.

  THE SEMAPHORES ARE THE REASON ANY OF THIS EXISTS. See their declaration
  below: they are how a tune tells a demo when to change what it is drawing.

  This unit holds the block and the routine that clears it, and almost nothing
  else. The code is incidental; the layout is the point.}

unit VTCtrl;

interface

const
  CtrlBlockSize = $300;      { what Reset clears }

type

  { One channel's state, as a reader of the block sees it. Updated by the
    player every tick; a demo watching these can draw a VU meter, flash on a
    note, or colour something by which instrument is sounding.

    Period is the pitch -- LOWER MEANS HIGHER, since a period counts ticks
    between samples. Instrument runs 1..31 with 0 meaning "none"; volume runs
    0..63, already scaled by the user's per-channel setting, so it is what is
    actually being heard rather than what the pattern asked for.}
  TChanData  = record
    Period     : Word;          { +$0  the channel's RealPeriod              }
    Instrument : Byte;          { +$2  1..31                                 }
    Volume     : Byte;          { +$3  0..63, scaled by UserVols             }
  end;
  TChansData = array[1..32] of TChanData;    { 128 bytes                     }

  TCtrlBlock = record
    { **CB+$000..$0FF -- 256 SEMAPHORES, AND THEY ARE THE WHOLE POINT OF DEMOVT.**

      THIS IS HOW A TUNE DRIVES A DEMO. Effect command 8 in a module carries a
      parameter; when the player meets it, it increments the semaphore that
      parameter names. So a musician can mark a bar in the tune -- a drop, a
      key change, the start of a section -- and the demo watching this array
      sees it happen, in time, without either side knowing anything about the
      other's schedule.

      A client polls one with VTCheckSemaphore, clears it with VTSetSemaphore,
      and VTMiddleSync makes the MUSIC wait for the demo instead: it jumps the
      module when the semaphore it wants has not arrived yet. Both directions,
      through one array of counters.

      All 256 are set to zero when a module starts.}
    Semaphores : array[0..255] of Byte;   { CB+$000                          }

    { One byte per channel, set when that channel starts a new note. A demo
      watching these gets a per-channel trigger it can flash or bounce on,
      without having to compare periods from one tick to the next.}
    ChansTrig : array[1..32] of Byte;  { CB+$100  1 = channel retriggered    }

    { How many of the thirty-two flags above mean anything. Without it a client
      cannot tell an idle channel from one the module does not have -- one byte
      that makes the array before it interpretable.}
    NumChannels : Byte;      { CB+$120                                      }
    { The bindings' `CtrlEntryPoint`: `void (_pascal _far *)(word command)`, the
      far entry that takes its selector on the stack. }
    CtrlEntryPoint : Pointer;   { CB+$121                                   }
    { Ticks since playback started, at the module's own 50 Hz. A demo animating
      in time with the music reads this rather than keeping its own clock,
      which is what stops the two drifting apart over a long tune.}
    TickCounter : LongInt;   { CB+$125  50 Hz, the module's own timebase   }
    { **A SECOND ENTRY POINT BESIDE THE FIRST**, taking its command in AX
      rather than on the stack. The one above takes a Pascal parameter; this one
      suits a caller writing assembler, and having both means a client written
      for either convention works unchanged.

      CDVT.H describes the stub byte for byte: "Far pointer to the servicing
      routine that gets the parameter in AX. It's just a PUSH AX; CALL FAR
      entryPointSeg:Off; RETF". }
    RegEntryPoint : Pointer; { CB+$129  the AX-in-register entry             }

    { What every channel is doing right now, four bytes each. This is the
      richest thing the block publishes and the reason a demo can draw a real
      VU meter rather than a beat flash.}
    ChansData : TChansData;  { CB+$12D                                      }

    { Where in the module playback has reached: which row of the pattern, and
      which entry of the order list. Together they are the module's playing
      position, and a demo can use them to know how far through a tune it is.}
    Pos : Byte;              { CB+$1AD  the row inside the pattern           }
    Seq : Byte;              { CB+$1AE  the position in the order list       }

    { **CB+$1AF..$202 IS 81 + 3, AND THE SPLIT IS THE DIRECTION OF THE INTERFACE.**
      VTASM.INC puts its comment -- "These are supposed to be modified by you to
      tell DemoVT your intentions" -- exactly here: 81 bytes close the region
      DemoVT writes and the client reads, and 3 open the region the client writes.

      That boundary was reached from this side as "a run of fields with no writer
      is a request block", and it is stated outright over there. Kept as two
      declarations rather than one 84-byte filler because the author's layout says
      they are two different things. }
    Reserved1AF : array[1..81] of Byte;  { CB+$1af  end of the OUT region    }
    Reserved200 : array[1..3] of Byte;   { CB+$200  start of the IN region   }

    JumpNewPos  : Byte;      { CB+$203 -- a jump is pending                 }
    JumpPosSeq  : Byte;      { CB+$204 -- requested order position          }
    JumpPosNote : Byte;      { CB+$205 -- requested row                     }
    { A MASTER VOLUME the client writes. Every channel's volume is multiplied
      by it and the high byte taken, so $FF is unity and anything less
      attenuates the whole mix -- which is how a demo fades the music out under
      a scene change without touching the module.

      [1.39b] The bindings call it `SoundVolume`, 0-255: "Put your favourite
      volume here. You can perform fades and the like."}
    SoundVolume : Byte;      { CB+$206                                      }
    { HOW A CLIENT ASKS THE PLAYER TO STOP. Set it, and the player returns
      from its playlist without playing anything further, abandons the loop
      between modules, and does not complain about it. The demo sets this on
      the way out; the player notices at the next opportunity.

      [1.39b] The bindings: "Set to 1 to force DVT to exit after your program
      exits".}
    Abort : Boolean;         { CB+$207  a client asks the player to stop      }

    { Reserved in all five bindings, to the byte. This one really is empty. }
    Reserved208 : array[1..248] of Byte;   { CB+$208..$2FF                   }
  end;

var
  CtrlBlock : TCtrlBlock;

implementation

{ --------------------------------------------------------------------------
wipe the block and stamp it.

  Plain Pascal in the binary. The whole body is a FillChar and a byte store,
  and the prologue is the compiler's own (`PUSH BP / MOV BP,SP` ... `LEAVE`)
  rather than anything hand-written, so there is no assembler to preserve.

  The $FF at CB+$206 is the only non-zero byte Reset leaves behind. Nothing
  read so far tests it; it is recorded because it is there.

  **A `.TPU` COMPARISON COULD NOT HAVE FOUND THIS.** The bytes were already
  identical either way -- the unit verified at 25 of 25 as a procedure. What was
  wrong was the KIND of thing they are, and only linking exposes it.
  -------------------------------------------------------------------------- }
begin
  FillChar(CtrlBlock, CtrlBlockSize, 0);
  CtrlBlock.SoundVolume := $FF;
end.
