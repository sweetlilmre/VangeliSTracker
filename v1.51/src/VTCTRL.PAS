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
    Filler1  : array[$000..$120] of Byte;
    Dispatch : Pointer;      { CB+$121 -- the far entry every client calls  }
    { CB+$125 -- a 32-bit tick counter, incremented by 12ba:0c9a. Live state a
      client can poll; nothing in this unit touches it. }
    Ticks32  : LongInt;      { CB+$125                                      }
    Filler2  : array[$129..$202] of Byte;
    SeekWant : Byte;         { CB+$203 -- a jump is pending                 }
    SeekPos  : Byte;         { CB+$204 -- requested order position          }
    SeekRow  : Byte;         { CB+$205 -- requested row                     }
    { CB+$206 -- A MASTER VOLUME, and 12ba:0e66 is what says so: every channel's
      volume is multiplied by it and the high byte taken, so $FF is unity and a
      client can attenuate the whole mix by writing here. This unit only knows
      that Reset sets it to $FF, which is why it was called `Mark`. }
    MasterVol : Byte;        { CB+$206                                      }
    Filler3  : array[$207..$2FF] of Byte;
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
