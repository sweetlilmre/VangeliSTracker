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
  else. The code is incidental; the layout is the point.

  [re] Segment 14b7 -- 32 bytes, of which 25 are the one routine and the rest
  is padding. DS:$22c6 is the structure; ES:[DI-4] in the handshake points at
  it. `01-int2f.md` documents the server side.

  [re] **THE CLIENT SIDE IS PUBLISHED, AND IT NAMES THIS RECORD.** The v1.5
  distribution ships bindings for five languages, and each declares this
  structure in full:

       C/CDVT.H            struct sDVT_info, #pragma pack(1)
      ASM/VTASM.INC       VTRunInfo SEGMENT AT 0
      TPAS/PASDVT.PAS     TVTRunInfo = RECORD
      PMODE/PMODEDVT.INC  the same segment, 32-bit
      DEMOVT.DOC          prose, with the ASM layout reprinted

  [re] CDVT.H says "C interface code to DemoVT v1.5 and higher", so it is this
  version. All five agree, field for field, and every name below is theirs --
  NOT ours. This is the one record in the reconstruction where the names are
  documentation rather than inference, and the offsets measured here from
  instructions match the published layout exactly, in both directions.

  [re] THAT IS WHY THE FILLERS ARE GONE. They were the right answer while the
  layout was ours to guess at and the wrong one once the author has published
  it. What stays reserved below is reserved in the bindings TOO -- the
  author's own `_reserved`, not our "we have not looked here yet".

  [re] THE ORIGINAL HAS ONE FLAT DGROUP and every segment reaches into it by
  absolute address. Turbo Pascal has no such thing: a variable belongs to
  exactly one unit and everyone else imports it. The block is declared HERE,
  in the segment that clears it, and VTMAIN imports it -- see
  docs/06-transcription.md, "one DGROUP, many units".

  [re] NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.

  [re] ADDRESS MAP
    CtrlBlock  DS:$22c6        Reset  14b7:0000
  =========================================================================== }

unit VTCtrl;

interface

const
  CtrlBlockSize = $300;      { 14b7:0008 -- what Reset clears }

type
  { [re] **DECLARED HERE AND NOT IN PLAYMOD, BECAUSE THE COPY HAS TO BE AN
    ASSIGNMENT.**
    12ce:022b calls SYSTEM's $09f7 -- the whole-array copy the code generator emits
    for `A := B` -- where a written `Move` gets $0fb2, the overlap-checking one. The
    two helpers are eleven bytes apart in behaviour and identical in signature, so
    only the CALL TARGET tells them apart.

    An assignment needs one type on both sides. PlayMod uses VTCtrl and not the other
    way round, so the type has to live here for the ring and the published row to be
    the same thing. }
  { One channel's state, as a reader of the block sees it. Updated by the
    player every tick; a demo watching these can draw a VU meter, flash on a
    note, or colour something by which instrument is sounding.

    Period is the pitch -- LOWER MEANS HIGHER, since a period counts ticks
    between samples. Instrument runs 1..31 with 0 meaning "none"; volume runs
    0..63, already scaled by the user's per-channel setting, so it is what is
    actually being heard rather than what the pattern asked for.

    [re] The published name is `TChanData`, and PASDVT.PAS declares it
    identically -- field order, widths, and the base-1 array. `Ins` and `Vol`
    are spelt out here because nothing in this source is short of room; the
    ranges are the bindings'. }
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

      All 256 are set to zero when a module starts.

      [re] Held as filler through the entire reconstruction on the reading that
      this was 1.31b's per-channel tally: wrong about what it holds, and right
      about not inventing a name for it.

      [re] DEMOVT.DOC: "There's an array of 256 semaphores; each of them gets
      incremented whenever a command number 8 is found in any channel of the MOD.
      The parameter of this command tells which one of the 256 semaphores gets
      incremented ... When DemoVT is started, all semaphores are set to zero."

      [re] EVERY PART OF THAT WAS ALREADY IN THIS RECONSTRUCTION, TRANSCRIBED
      AND UNRECOGNISED. `ModCommands.StartRingEvent` is command 8's handler -- the one
      routine in its segment with no counterpart in the release -- and it stores
      the parameter. 12ba:0187 increments this array by that parameter. 1000:03e4
      clears all 256 bytes when a module starts. Three sites, correct to the
      byte, none of them able to say WHY, because the reason is on the client
      side. }
    Semaphores : array[0..255] of Byte;   { CB+$000                          }

    { One byte per channel, set when that channel starts a new note. A demo
      watching these gets a per-channel trigger it can flash or bounce on,
      without having to compare periods from one tick to the next.

      [re] CB+$100..$11F, NEW IN v1.51. 12ce:0253 stores 1 into `[DI+4719]`
      with DI running 1 to 32, and $4719 is CtrlBlock + $0FF, so the array is
      base-1 and its first element is at CB+$100. The 8-channel tally 1.31b had
      is still there and still at CB+$000 -- a second, wider publication beside
      it, not a replacement. }
    ChansTrig : array[1..32] of Byte;  { CB+$100  1 = channel retriggered    }

    { How many of the thirty-two flags above mean anything. Without it a client
      cannot tell an idle channel from one the module does not have -- one byte
      that makes the array before it interpretable.

      [re] CB+$120, NEW IN v1.51, declared as one byte of filler until 12ce:140f
      was read. `PlayStart` stores `Song.NumChannels` here. }
    NumChannels : Byte;      { CB+$120                                      }
    { The bindings' `CtrlEntryPoint`: `void (_pascal _far *)(word command)`, the
      far entry that takes its selector on the stack. }
    CtrlEntryPoint : Pointer;   { CB+$121                                   }
    { Ticks since playback started, at the module's own 50 Hz. A demo animating
      in time with the music reads this rather than keeping its own clock,
      which is what stops the two drifting apart over a long tune.

      [re] CB+$125, incremented by 12ba:0c9a. Nothing in this unit touches it. }
    TickCounter : LongInt;   { CB+$125  50 Hz, the module's own timebase   }
    { **A SECOND ENTRY POINT BESIDE THE FIRST**, taking its command in AX
      rather than on the stack. The one above takes a Pascal parameter; this one
      suits a caller writing assembler, and having both means a client written
      for either convention works unchanged.

      [re] CB+$129, NEW IN v1.51, and the four bytes were declared as filler
      until 1000:0601 was read. CB+$121 holds @Dispatch; this one holds
      @DispatchEntry, the seven-byte stub that pushes AX first. $129..$12C is
      exactly four bytes, so the filler it replaces was the right size and the
      wrong name.

      CDVT.H describes the stub byte for byte: "Far pointer to the servicing
      routine that gets the parameter in AX. It's just a PUSH AX; CALL FAR
      entryPointSeg:Off; RETF". }
    RegEntryPoint : Pointer; { CB+$129  the AX-in-register entry             }

    { What every channel is doing right now, four bytes each. This is the
      richest thing the block publishes and the reason a demo can draw a real
      VU meter rather than a beat flash.

      [re] CB+$12D..$1AC, NEW IN v1.51 -- 128 bytes, published whole by a single
      Move at 12ce:022b. The four are `TChanData`, which the bindings name and
      whose shape had already been measured to match. }
    ChansData : TChansData;  { CB+$12D                                      }

    { Where in the module playback has reached: which row of the pattern, and
      which entry of the order list. Together they are the module's playing
      position, and a demo can use them to know how far through a tune it is.

      [re] CB+$1AD and CB+$1AE carry `TPlayingNote`'s own two indices under the
      release's names. 12ce:090e stores `NotePlaying` into the ring the first is
      published from, and 091d stores `SeqPlaying`. The transcription had the
      pair the other way round before 12ce:090b was read; the ring alone could
      not say which byte was which, because it only ever moves them. The
      bindings call them `Pos` and `Seq`, in that order -- a third witness. }
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
      volume here. You can perform fades and the like."

      [re] CB+$206, and 12ba:0e66 is what says so. This unit only knows that
      Reset sets it to $FF, which is why it was called `Mark`. }
    SoundVolume : Byte;      { CB+$206                                      }
    { HOW A CLIENT ASKS THE PLAYER TO STOP. Set it, and the player returns
      from its playlist without playing anything further, abandons the loop
      between modules, and does not complain about it. The demo sets this on
      the way out; the player notices at the next opportunity.

      [1.39b] The bindings: "Set to 1 to force DVT to exit after your program
      exits".

      [re] **CB+$207, AND IT IS WRITTEN BY THE CLIENT, NOT BY THIS PROGRAM.** DS:$4821 is
      read in three places -- 1000:069a beside the banner test, and twice inside
      109c's DoSongColl -- and written NOWHERE in the image. That was recorded as "a
      switch wired up and never given a way to be turned on", declared as a loose var
      in VTGlobal, and it was wrong: $4821 minus CtrlBlock's $461a is $207, which puts
      it in this record, four bytes after SeekWant and one after MasterVol.

      [re] A CONTROL-BLOCK FIELD WITH NO WRITER IS AN INPUT. Everything in this run is:
      SeekWant, SeekPos and SeekRow are set by a client and consumed by the player,
      and this is the fourth. Set, it makes DoSongColl return True without playing
      anything, aborts the loop between modules, and suppresses the complaint -- so a
      client asks the player to stop by writing here.

      [re] IT WAS THE LAST TWO BYTES OF DGROUP, TOO. Declared as a var in VTGlobal it sat
      between VTShell's block and SoundDevices', which put every SoundDevices and
      VTResid variable two bytes high -- 53 operands in one unit, 13 in another.

      [re] AND THE BINDINGS CONFIRM IT WORD FOR WORD: "Set to 1 to force DVT to exit
      after your program exits". The reading here was reached from three reads and
      no writes, and the record of that is worth keeping -- the shape argued the
      conclusion correctly before any documentation for it was found. }
    Abort : Boolean;         { CB+$207  a client asks the player to stop      }

    { Reserved in all five bindings, to the byte. This one really is empty. }
    Reserved208 : array[1..248] of Byte;   { CB+$208..$2FF                   }
  end;

var
  CtrlBlock : TCtrlBlock;    { DS:$461a }

implementation

{ --------------------------------------------------------------------------
  14b7:0000 -- wipe the block and stamp it.

  Plain Pascal in the binary. The whole body is a FillChar and a byte store,
  and the prologue is the compiler's own (`PUSH BP / MOV BP,SP` ... `LEAVE`)
  rather than anything hand-written, so there is no assembler to preserve.

  [re] Note it clears $300 bytes but the dispatcher pointer at CB+$121 is written
  afterwards by the main body (1000:058c), NOT here -- so Reset must run
  before Install, and it does: 1000 calls it during startup.

  The $FF at CB+$206 is the only non-zero byte Reset leaves behind. Nothing
  read so far tests it; it is recorded because it is there.

  [re] **IT IS THE UNIT'S INITIALISATION SECTION, NOT A PROCEDURE**, and the LINK is
  what settled that. It used to be declared `procedure Reset; far;` in the
  interface, and nothing anywhere calls it -- so Turbo Pascal's smart linker
  discarded the whole unit and our image had VTCTRL at ZERO bytes where the
  original has 25. The original's init chain calls `14b7:0000`, which is this
  code, and a unit's initialisation section is emitted at offset 0 and far-called
  from that chain. Written as `begin ... end.` the linker keeps it, because an
  initialisation section is never discardable.

  **A `.TPU` COMPARISON COULD NOT HAVE FOUND THIS.** The bytes were already
  identical either way -- the unit verified at 25 of 25 as a procedure. What was
  wrong was the KIND of thing they are, and only linking exposes it.
  -------------------------------------------------------------------------- }
begin
  FillChar(CtrlBlock, CtrlBlockSize, 0);          { 14b7:0008 .. 14b7:000d }
  CtrlBlock.SoundVolume := $FF;                     { 14b7:0012  DS:$24cc    }
end.
