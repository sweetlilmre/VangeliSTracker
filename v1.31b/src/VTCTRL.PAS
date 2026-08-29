{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  Segment 14b7 -- the control block and its reset. 32 bytes, of which 25 are
  the one routine and the rest is padding.

  This unit exists because of the control block, not because of the code.
  DS:$22c6 is the 768-byte structure that INT 2Fh hands out to any client
  that asks -- ES:[DI-4] in the handshake points at it -- so it is the whole
  of DemoVT's published interface. `01-int2f.md` documents the fields.

  THE ORIGINAL HAS ONE FLAT DGROUP and every segment reaches into it by
  absolute address. Turbo Pascal has no such thing: a variable belongs to
  exactly one unit and everyone else imports it. The block is declared HERE,
  in the segment that clears it, and VTMAIN imports it -- see
  docs/06-transcription.md, "one DGROUP, many units".

  NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.

  ADDRESS MAP
    CtrlBlock  DS:$22c6        Reset  14b7:0000
  =========================================================================== }

unit VTCtrl;

interface

const
  CtrlBlockSize = $300;      { 14b7:0008 -- what Reset clears }

type
  { Only the fields that are established are named. The rest is deliberately
    left as filler: guessing at 768 bytes of layout would put invented names
    into the one part of DemoVT that other programs actually depend on. }
  TCtrlBlock = record
    { **CB+$000..$0FF -- 256 SEMAPHORES, AND THEY ARE THE POINT OF THE PROGRAM.**
      Named from the client bindings the v1.5 distribution ships -- C/CDVT.H,
      ASM/VTASM.INC, TPAS/PASDVT.PAS, PMODE/PMODEDVT.INC and DEMOVT.DOC, which
      all declare this structure field for field in the author's own names.

      THOSE BINDINGS ARE FOR v1.5 AND HIGHER, SO THE EXTENT IS CHECKED HERE
      RATHER THAN COPIED. This filler ran $000..$120, which is 289 bytes, and the
      bindings' first three fields are 256 + 32 + 1 = 289. It closes exactly, and
      the field after it -- the dispatcher at $121 -- was already measured in this
      tree. Two independent ends agreeing is what makes the middle safe.

      DEMOVT.DOC: "There's an array of 256 semaphores; each of them gets
      incremented whenever a command number 8 is found in any channel of the MOD.
      The parameter of this command tells which one of the 256 semaphores gets
      incremented."

      AND THIS VERSION ALREADY DOES ALL OF IT. ModCommands stores command 8's
      parameter into the channel; 12ba:0187 increments this array by it. Both
      were transcribed correctly here long before anything said why. }
    Semaphores : array[0..255] of Byte;   { CB+$000                          }

    { CB+$100 -- one byte per channel, set when a channel retriggers a note.
      [1.39b bindings] "== 1 -> channel retriggered a note", and DEMOVT.DOC adds
      what for: a VU meter. }
    ChansTrig  : array[1..32] of Byte;    { CB+$100                          }

    { CB+$120 -- how many of the flags above mean anything. Without it a client
      cannot tell an idle channel from one the song does not have. }
    NumChannels : Byte;                   { CB+$120                          }
    Dispatch : Pointer;      { CB+$121 -- the far entry every client calls  }
    { CB+$125 -- a 32-bit tick counter, incremented by 12ba:0c9a. Live state a
      client can poll; nothing in this unit touches it. }
    Ticks32  : LongInt;      { CB+$125                                      }
    { CB+$129..$202 -- 218 bytes, and RESERVED IN THIS VERSION. v1.51 fills the
      first 134 of them with a second dispatch entry, a 32-channel note row and
      the playing position; none of that exists here, and the bindings that name
      those fields are for that version. The remaining 84 are reserved there too,
      split 81 and 3 by the boundary between what DemoVT writes and what a client
      writes -- see VTASM.INC. Left whole here because this version has nothing
      in the first part to divide it. }
    Filler2  : array[$129..$202] of Byte;
    SeekWant : Byte;         { CB+$203 -- a jump is pending                 }
    SeekPos  : Byte;         { CB+$204 -- requested order position          }
    SeekRow  : Byte;         { CB+$205 -- requested row                     }
    { CB+$206 -- A MASTER VOLUME, and 12ba:0e66 is what says so: every channel's
      volume is multiplied by it and the high byte taken, so $FF is unity and a
      client can attenuate the whole mix by writing here. This unit only knows
      that Reset sets it to $FF, which is why it was called `Mark`. }
    MasterVol : Byte;        { CB+$206                                      }
    { **CB+$207 IS AN INPUT, WRITTEN BY THE CLIENT AND NEVER BY THIS PROGRAM.**
      The bindings call it `Abort` and describe it exactly: "Set to 1 to force
      DVT to exit after your program exits". It sits in the run of fields a
      client writes -- the seek trio above, the volume, and this -- which is why
      nothing here stores to it.

      In v1.51 the same byte is read in three places and written in none, and was
      recorded there as a switch nobody could turn on before the bindings were
      found. A control-block field with no writer inside the image is an input;
      the writers are in other programs. }
    Abort    : Boolean;                   { CB+$207                          }

    { Reserved in all five bindings, to the byte. }
    Filler3  : array[$208..$2FF] of Byte;
  end;

var
  CtrlBlock : TCtrlBlock;    { DS:$22c6 }

implementation

{ --------------------------------------------------------------------------
  14b7:0000 -- wipe the block and stamp it.

  Plain Pascal in the binary. The whole body is a FillChar and a byte store,
  and the prologue is the compiler's own (`PUSH BP / MOV BP,SP` ... `LEAVE`)
  rather than anything hand-written, so there is no assembler to preserve.

  Note it clears $300 bytes but the dispatcher pointer at CB+$121 is written
  afterwards by the main body (1000:058c), NOT here -- so Reset must run
  before Install, and it does: 1000 calls it during startup.

  The $FF at CB+$206 is the only non-zero byte Reset leaves behind. Nothing
  read so far tests it; it is recorded because it is there.

  **IT IS THE UNIT'S INITIALISATION SECTION, NOT A PROCEDURE**, and the LINK is
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
  CtrlBlock.MasterVol := $FF;                     { 14b7:0012  DS:$24cc    }
end.
