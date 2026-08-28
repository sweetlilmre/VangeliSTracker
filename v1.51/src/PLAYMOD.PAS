{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  Segment 12ba -- 5,968 bytes, the largest thing in the program after the
  program itself. IN PROGRESS: transcribed from the top of the segment down,
  which is the only order that works, because Turbo Pascal lays procedures out
  in source order and a missing routine displaces everything below it.
  `verify.py` reports it as PARTIAL and measures what is here.

  NAMES ARE THE 1.39b RELEASE'S. `LIB/PLAYMOD.PAS` is the later version of this
  unit and the pairing is confirmed rather than assumed:

    12ba:0007  UnCanal          the release's routine, statement for statement
    12ba:0664  MyMove           a hand-written Move, ASSEMBLER in both
    12ba:1600  DumpInstrument   the resampling kernel, EXTERNAL from PLAYMOD.ASM

  and `TModRawChan`'s FIELD LAYOUT lands on every offset the reading pass had
  already recorded from the disassembly -- `+$0b` the non-looping limit, `+$19`
  and `+$1b` the 16.16 step, `+$1d` the byte handed to the kernel, `+$1e` and
  `+$20` the loop, 34 bytes in total. That is why it is adopted here and
  `TSong`'s was not: this one is CONFIRMED by the binary, field by field, and
  1.39b's `TSong` demonstrably did not fit.

  TWO THINGS THE RELEASE SETTLED THAT THE READING HAD LEFT OPEN.

  `+$1d` IS THE VOLUME. `docs/CONTINUATION.md` carried it as "step or volume,
  the kernel at 12ba:1600 would say" -- the release passes `Raw.Volume` in that
  argument position, and the DumpEmpty call at `12ba:012c` passes a literal 0
  there, which only makes sense for a volume.

  `+$19`/`+$1b` ARE THE STEP, NOT THE POSITION. The reading called them "sample
  position, low word of a 16.16 fixed point". They are `StepFrac`/`StepInt`, the
  per-sample INCREMENT; the position is `SplPosFrac`/`SplPosInt` at `+$01`/`+$03`.
  The arithmetic is the same either way, which is why reading alone could not
  separate them.

  AND ONE THING THE DISASSEMBLY SETTLED AGAINST THE RELEASE. 1.39b has two
  kernels, `DumpInstrument` and `DumpEmpty`. 1.31 has ONE, at `12ba:1600`, with
  a final Boolean argument -- `6a 00` at `009b` and `0111`, `6a 01` at `016f`.
  The release split it in two later. The release settles shapes and names; the
  disassembly settles what is actually there.
  =========================================================================== }
unit PlayMod;

{ $G+ for the 286 instructions, as everywhere else in this tree. }

interface

{ --------------------------------------------------------------------------
  NINE GLOBALS THAT USED TO BE DECLARED HERE ARE NOW IN MODCOMMA.PAS, and the DGROUP
  LAYOUT is what moved them:

      MyLoopMod  $0334    TempoDiv  $0336 (release: BPMDivider)
      TempoAccum $033a    RangeStart $033c   RangeEnd $033e
      ReqStart   $0342    ReqEnd    $0344    ReqLen   $0346    TickInRow $034e

  Their addresses INTERLEAVE with `MySongLen` at $0340, `FilterIsOn` at $0348 and the
  tempo pair, which were already ModCommands' -- and two units' data cannot interleave,
  because the linker lays DGROUP down one unit at a time in link order. So all of them
  belong to the unit this one `uses`, which is also where the release declares them, in
  its own CONST section, in exactly the address order above.

  This unit still reads every one of them; they are just not its own. Nothing about the
  code changes -- a DGROUP reference is a linker fixup either way -- so PLAYMOD still
  verifying identical with the same 1,187 pending fixups is the check.
  -------------------------------------------------------------------------- }

{ ~~VTSilenc~~ IS NOT A DEPENDENCY, AND THE LINK ORDER IS WHAT SAYS SO. It was here
  for one identifier, `Ticks`, which is now declared in SoundDevices -- see the note
  at its declaration there. The original's segment addresses put `1065`/VTSilenc at
  the very END of the unit order and `12ba`/PlayMod in the middle, and TP6's order is
  reverse DFS post-order over the `uses` graph, so a dependency in this direction is
  impossible. `demovt/linkorder.py` checks every edge in the tree against it. }
uses
  SongUnit, SoundDevices, VTCtrl, GUS, ModCommands, Filters,
  Heaps, Hardware;

{ --------------------------------------------------------------------------
  The raw channel -- 34 bytes, one per voice, DS:$13a6 upward ($1384 is the
  base-1 base the compiler indexes from, not the array's address).

  Names and layout are `LIB/PLAYMOD.PAS`'s. Every offset below was already in
  docs/04-units.md from the disassembly; the release supplied the names and the
  three fields nothing had touched yet.
  -------------------------------------------------------------------------- }
type
  PModRawChan = ^TModRawChan;
  TModRawChan = record
    Flags      : Byte;          { +$00  see the rcf* constants below         }

    SplPosFrac : Word;          { +$01  position, fraction                   }
    SplPosInt  : Word;          { +$03  position, offset                     }
    SplPosSeg  : Word;          { +$05  position, segment                    }

    SplOfs     : Word;          { +$07  the sample part being played         }
    SplSeg     : Word;          { +$09                                       }
    SplLimit   : Word;          { +$0b  its size -- the non-looping limit    }

    SplOfs1    : Word;          { +$0d  first part                           }
    SplSeg1    : Word;          { +$0f                                       }
    SplLimit1  : Word;          { +$11                                       }

    SplOfs2    : Word;          { +$13  second part, for a long sample       }
    SplSeg2    : Word;          { +$15                                       }
    SplLimit2  : Word;          { +$17                                       }

    StepFrac   : Word;          { +$19  the increment, 16.16 with StepInt    }
    StepInt    : Word;          { +$1b                                       }

    Volume     : Byte;          { +$1d                                       }

    LoopEnd    : Word;          { +$1e                                       }
    LoopLen    : Word;          { +$20                                       }
  end;                          { 34 bytes                                   }

{ --------------------------------------------------------------------------
  The event ring -- DS:$14b6, 400 bytes, 25 rows of 8 entries.

  What `12ba:0202` posts and `12ba:0187` consumes. Two bytes per entry, and
  both are read: `+$01` is the marker the consumer tests and `+$00` an index
  into the published control block. No counterpart in the 1.39b release, so
  these names are ours and provisional.
  -------------------------------------------------------------------------- }
type
  { THE RELEASE'S NAMED TYPE, AND IT IS LOAD-BEARING. Turbo Pascal only allows a
    whole-array assignment between operands of the SAME named type, and 12ba:075e and
    12ba:119e are assignments rather than `Move` calls -- see the note at each. Declared
    as two anonymous `array[1..8] of Byte` the assignment does not compile at all, which
    is why both sites were read as `Move`. Eight is written out rather than `MaxChannels`
    because that constant is declared further down, after the records that use it. }
  TVolumes = array[1..8] of Byte;

  PRingEntry = ^TRingEntry;
  TRingEntry = record
    Chan : Byte;                { +$00  indexes CtrlBlock                    }
    Note : Byte;                { +$01  nonzero means the entry is live      }
  end;
  TRingRow = array[0..7] of TRingEntry;      { 16 bytes                      }


  { --- THE SAMPLE BUFFERS, DS:$1394 ----------------------------------------
    NOT A NEW RECORD: this is `SoundDevices.TSampleBuffer`, already declared in
    SOUNDDEV with these exact offsets -- InUse, NSamples, RateHz, Channels,
    DataType, IData, eleven bytes. It was transcribed here first as an invented
    `TModEntry` with the offsets right and every name wrong, and 12ba:1049 is what
    exposed that: a far function returning a pointer to one of these with no
    arguments is `SoundDevices.TAskBufferProc`, the driver's buffer callback.

    The release confirms the rest: `Buffers : ARRAY[1..NumBuffers] OF
    TSampleBuffer` with `NumBuffers = 3`, and `BuffIdx, BuffGive : WORD` -- "Tail
    of the buffer" and "Head of the buffer" -- which are DS:$1390 and DS:$1392.

    AND `InUse` SETTLES THE FLAG SENSE INDEPENDENTLY. 12ba:0b57 exits when it is
    non-zero, which the reading notes had backwards; "set while the device is
    playing it" is exactly that, arrived at from the other direction. }

  { For indexing through TSampleBuffer.IData, which is a Pointer in the record and
    an array of Words in use: 12ba:0b98 dereferences it and adds `(MixChan-1)*2`. }
  PWordArray = ^TWordArray;
  TWordArray = array[0..0] of Word;

  { The row the sequencer hands on, 63 bytes. `EoMod` is the release's name and
    its only confirmed field; see the note beside NoteBuff below. }
  PPlayingNote = ^TPlayingNote;
  { COMPLETE, and every field is confirmed against the binary. The last one to
    fall was `Note`: 12ba:094b computes `ChanIdx*6 + 6` and adds it to the record's
    address, which is Turbo Pascal's base-1 indexing of an `array[1..8] of
    TFullNote` starting at +$0c. That fixes the whole layout, and the total is
    exactly 63 bytes -- the record's real size.

    IT IS THE RELEASE'S FIELD LIST IN THE RELEASE'S ORDER: EoMod, Tempo,
    NotePlaying, SeqPlaying, Volume, Note, NMuestras, fill. 1.39b's record is 32
    bytes because its own `MaxChannels` differs; ours is 63 because 1.31 has
    eight channels. Same shape, different width -- which is why the fields carry
    over and the SIZE does not. }
  TPlayingNote = record
    EoMod       : Boolean;      { +$00                                       }
    Tempo       : Byte;         { +$01                                       }
    NotePlaying : Byte;         { +$02  written from NextNote at 12ba:074a    }
    SeqPlaying  : Byte;         { +$03  written from NextSeq at 12ba:0754    }
    Volume      : TVolumes;                 { +$04  assigned from UserVols   }
    Note        : array[1..8] of TFullNote; { +$0c  see 12ba:094b            }
    NMuestras   : Word;         { +$3c  the release's name; unused so far    }
    Fill        : Byte;         { +$3e                                       }
  end;

{ --------------------------------------------------------------------------
  The GUS event ring -- DS:$1646, 3,200 bytes, the same 25 rows of 8 but with
  a 16-byte entry: one queued voice command per slot per voice.

  THE FIELDS ARE `1723.TriggerVoice`'s PARAMETER LIST, which is what identifies
  them. `12ba:02ea` flushes a slot by passing `+$0c`, `+$08`, `+$06`, `+$04`,
  `+$03`, `+$01`, `+$00` and the voice number straight into
  `TriggerVoice(Voice, Vol : Byte; Freq : LongInt; Pan : Byte; StartA, LoopA,
  EndA : LongInt)`, and every size lines up: a byte, a word, a byte and three
  longs, 16 bytes exactly. `Freq` is a Word here and a LongInt there -- the ring
  stores 16 bits and the flush widens it.

  Names are ours: there is no counterpart in the 1.39b release, whose GUS
  support was rebuilt elsewhere.
  -------------------------------------------------------------------------- }
type
  TGusEvent = record
    Vol    : Byte;              { +$00                                       }
    Freq   : Word;              { +$01                                       }
    Pan    : Byte;              { +$03                                       }
    StartA : LongInt;           { +$04                                       }
    LoopA  : LongInt;           { +$08                                       }
    EndA   : LongInt;           { +$0c  the flush tests this for the long form }
  end;
  TGusEventRow = array[0..7] of TGusEvent;   { 128 bytes                     }

{ --- the channel state, DS:$1260 -----------------------------------------
    `TCanal` and `TFullNote` ARE the release's, head for head, and 12ba:0820
    proves it: the four stores in that loop land on `Note.Period`, `Note.Instrument`,
    `Note.Command` and `Period`, at +$01, +$00, +$04 and +$0b, which is exactly
    where `TFullNote` (Instrument, Period, Volume, Command, Parameter -- six
    bytes) followed by `Instrument : PInstrumentRec`, `Volume` and `Period` puts
    them. And `Period := 800` twice is a ProTracker period, not a coincidence.

    THE TAIL DOES NOT CARRY OVER. 1.31's record is 38 bytes and 1.39b's is far
    larger -- it grew S3M fields (`S3mRetAdd`, `TPortIsFine`, retrigger state) --
    so everything past +$0d is filler here, exactly as with TSong. }



const
  RingRows = 25;


  { The release's names for both. `MaxChannels` is 8 here and not 32 as 1.39b has
    it -- every base-1 array in this segment is eight elements long and
    `TPlayingNote` is 63 bytes rather than the release's 32 for exactly that
    reason. It is used as a MULTIPLIER at 12ba:1224, where `MaxSplPerTick *
    MaxChannels * 2` folds to `SHL AX,3 / SHL AX,1`; a different value would give
    a different pair of shifts, so the byte confirms the 8.

    `NumBuffers` is 1, against the release's 3 -- see the note beside Buffers. }
  MaxChannels = 8;
  NumBuffers  = 1;

  rcfLongSample     = $01;      { over 65,520 bytes, so it is in two parts   }
  rcfActiveChannel  = $02;      { allowed to sound                           }
  rcfDoesLoop       = $04;
  rcfPlaying2nd     = $08;
  rcfLongLoopLen    = $10;
  rcfLongLoopEnd    = $20;
  rcfSampleFinished = $40;

{ ==========================================================================
  THIS UNIT'S WHOLE DGROUP CONST BLOCK, $02c4..$0333, IN ADDRESS ORDER.

  It used to be six separate `const` and `var` sections scattered down the file in no
  particular order, and that was invisible until the program linked. **DGROUP is laid
  out per unit in LINK order and, within a unit, in DECLARATION order**, with a unit's
  TYPED CONSTANTS in one region and its plain vars in another. So the order of these
  lines IS the layout, and a var here is not a slower constant -- it is a variable in a
  different part of DGROUP entirely. `demovt/dgroup.py` measures it.

  EVERY VALUE IS READ OUT OF THE ORIGINAL'S IMAGE, never taken from the release, and
  one of them differs: `MaxOutputFreq` is 44000 here and 45000 in 1.39b. `MaxSplPerTick`
  agrees at 880 and the pan table agrees byte for byte.

  THE RELEASE SETTLED THE ORDER AND THE ADDRESSES CONFIRMED IT, sixteen at a time:
  `LIB/PLAYMOD.PAS`'s interface declares PlayingSong, LoopMod, ForceLoopMod,
  CanFallBack, FilterOn, FilterOff, FilterIsOn, MaxOutputFreq, DontExecute, Playing,
  ModTickProcValid, NoteTl, NoteHd, NoteSound, NoteProcessed, MaxSplPerTick in that
  sequence, and every one lands on an address an instruction in this segment already
  named. `AltMode` at $02d1 is the single insertion 1.31 makes -- it has no counterpart
  in the release, which fits what it is for, the INCONEXI.EXE rename.

  FOUR RUNS ARE UNIDENTIFIED AND ARE DECLARED AS FILLER, NOT INVENTED AS VARIABLES.
  The addresses either side of each are measured and the block is contiguous, so the
  bytes certainly exist; what is not known is what they are called. Filler keeps the
  SIZE honest and says plainly that the name is missing, which is better than either a
  guessed name or a wrong length. $0308 is the interesting one: it is the only non-zero
  pair in the unidentified set, and it holds 1.
  ========================================================================== }
const
  PlayingSong      : PSong         = nil;      { DS:$02c4                      }
  LoopMod          : Boolean       = True;     { DS:$02c8  nothing reads it     }
  ForceLoopMod     : Boolean       = False;    { DS:$02c9  the ForceLoopMod key }
  CanFallBack      : Boolean       = True;     { DS:$02ca  12ba:1325 reads it   }
  FilterOn         : TFilterMethod = fmNone;   { DS:$02cb  the FilterOn key     }
  FilterOff        : TFilterMethod = fmNone;   { DS:$02cc  the FilterOff key    }

  { DS:$02cd -- **NOT** ModCommands' `FilterIsOn`, which is a different variable at
    DS:$0348. 1.31 has two of them; so, it turns out, does the release, which declares
    one in each of the same two interfaces -- this file used to say the release had
    only one, and that was wrong. Both are exported here because the ADDRESS requires
    it: $02cd sits between two interface globals, and a unit's implementation
    declarations all come after its interface ones, so a private declaration cannot
    land there. The shadowing hazard the old note worried about is handled where it
    actually bites -- VTCFG writes ModCommands' and now says so by qualifying it. }
  FilterIsOn       : Boolean       = False;    { DS:$02cd                       }

  MaxOutputFreq    : Word          = 44000;    { DS:$02ce  ab e0; release 45000 }
  DontExecute      : Boolean       = False;    { DS:$02d0                       }
  AltMode          : Boolean       = False;    { DS:$02d1  1.31 only            }
  Playing          : Boolean       = False;    { DS:$02d2                       }
  ModTickProcValid : Boolean       = False;    { DS:$02d3                       }
  NoteTl           : Word          = 0;        { DS:$02d4                       }
  NoteHd           : Word          = 0;        { DS:$02d6                       }
  NoteSound        : PPlayingNote  = nil;      { DS:$02d8                       }
  NoteProcessed    : PPlayingNote  = nil;      { DS:$02dc                       }
  MaxSplPerTick    : Word          = 880;      { DS:$02e0  03 70, the release's }

  { DS:$02e2 -- EIGHT PAN POSITIONS, one per channel, and this unit already had them
    under this name. What it did not have was their VALUES or their BOUNDS.

    **THE BOUNDS WERE THE BASE-1 TRAP, and this file already records the rule under a
    different array.** It was `array[0..8] of Byte` with its address given as $02e1,
    and $02e1 is not where it starts -- it is the BASE-1 BASE, the number the compiler
    subtracts so that `Pannings[Chan]` with Chan running 1..8 reaches $02e2..$02e9.
    The image settles it: $02e0 holds `03 70`, MaxSplPerTick, so $02e1 is that Word's
    high byte and cannot be the array's first element. Declared `array[1..8]` at $02e2
    the displacement is identical -- `[$02e2 - 1 + Chan]` is `[$02e1 + Chan]` -- which
    is why nine bytes where there are eight was invisible to `verify.py`. Exactly the
    mistake recorded for `RawChannels`: "$1384 IS THE BASE-1 BASE, not the address".

    $40 and $b0 are a third of the way in from each side, in the pattern
    L R R L L R R L, which is the Amiga's own channel assignment. The release keeps pan
    in the SONG (`PanPositions`, initialised from its `DefPan`) and 1.31 keeps it in
    the player -- which is why `InitValues` in 14b9 has no trace of the release's last
    statement, a thing this project had already found from the other end. }
  Pannings         : array[1..MaxChannels] of Byte =
                       ($40, $b0, $b0, $40, $40, $b0, $b0, $40);

  Rest             : Word          = 0;        { DS:$02ea                       }
  EventSlot        : Word          = 0;        { DS:$02ec                       }
  EventChan        : Word          = 0;        { DS:$02ee                       }
  RingSlot         : Word          = 0;        { DS:$02f0                       }
  RingVoice        : Word          = 0;        { DS:$02f2                       }
  NewFlags         : Byte          = 0;        { DS:$02f4                       }
  NoLoop           : Byte          = 0;        { DS:$02f5                       }
  NextIdx          : Word          = 0;        { DS:$02f6                       }
  ChanIdx          : Word          = 0;        { DS:$02f8                       }
  { DS:$02fa, six bytes. The initialiser names the FIRST variant's fields, which is
    the only form Turbo Pascal accepts for a variant record's typed constant --
    Instrument, Period, Volume, Command, Parameter is 1 + 2 + 1 + 1 + 1, and $02fa + 6
    is $0300, which is CurCanal. }
  NewNote          : TFullNote     = (Instrument : 0; Period : 0; Volume : 0;
                                      Command    : mcNone; Parameter : 0);
  CurCanal         : PCanal        = nil;      { DS:$0300                       }
  Pattern          : PPattern      = nil;      { DS:$0304                       }

  { DS:$0308 -- UNIDENTIFIED, and the only non-zero one: a Word holding 1. Nothing in
    the transcribed tree reads or writes $0308. Named by address on purpose. }
  Word0308         : Word          = 1;

  MixChan          : Word          = 0;        { DS:$030a                       }
  ChanRec          : PModRawChan   = nil;      { DS:$030c                       }
  OutPtr           : Pointer       = nil;      { DS:$0310                       }
  ModRec           : PSampleBuffer = nil;      { DS:$0314                       }
  Fill0318         : Word          = 0;        { DS:$0318  UNIDENTIFIED         }
  PrevTick         : Word          = 0;        { DS:$031a                       }
  CanalPtr         : PCanal        = nil;      { DS:$031c                       }
  RawPtr           : PModRawChan   = nil;      { DS:$0320                       }
  Fill0324         : LongInt       = 0;        { DS:$0324  UNIDENTIFIED         }
  TmpVal           : Word          = 0;        { DS:$0328                       }
  Fill032A         : Word          = 0;        { DS:$032a  UNIDENTIFIED         }
  StepVal          : Word          = 0;        { DS:$032c                       }
  Fill032E         : LongInt       = 0;        { DS:$032e  UNIDENTIFIED         }
  TickChans        : Byte          = 0;        { DS:$0332                       }

{ THE OLD SCATTERED NOTES FOLLOW, kept for their content only --
  the declarations they described are in the block above.
  DS:$02ca -- the release's `CanFallBack`, "TRUE if fall-back is allowed", and a
  TYPED constant there as it must be here: 12ba:1325 reads it with `MOV AL,[02ca]`
  and an untyped constant would have folded to an immediate. It is the client's
  standing permission; `MyCanFallBack` at $121e is the working copy PlayStart
  clears while it is setting up and restores on the way out. }
{ DS:$02c8 -- the release's `LoopMod`, "TRUE if music CAN be played forever", and
  the client's half of the pair whose working copy is `MyLoopMod` at $0334. Typed,
  and its address proves the release's declaration order again: `LoopMod` then
  `ForceLoopMod` is $02c8 then $02c9, two adjacent bytes.

  NOTHING IN 1.31 READS IT. The initialisation section clears it at 12ba:1426 and
  no other instruction in the segment touches $02c8 -- because the operand that
  would have read it is COMMENTED OUT in the expression at 1121, which is where
  the stray `True and` comes from. The release still carries it the same way.
  Declared for the one store, and to keep the pair together. }
{ --------------------------------------------------------------------------
  EXPORTED BECAUSE 11bb WRITES THEM, and for no other reason. These five were in the
  implementation section until segment 11bb -- the configuration file reader -- turned
  out to set every one of them from a key in VT.CFG:

      ForceLoopMod   $02c9   the `ForceLoopMod` key      11bb:0b0e
      FilterOn       $02cb   the `FilterOn` key
      FilterOff      $02cc   the `FilterOff` key
      MaxOutputFreq  $02ce   the `MaxFreq` key
      TicksPerSecond $0bcc   the `TicksPerSec` key

  Moving a declaration from the implementation section to the interface cannot change
  a byte of either unit: every reference to a global is a linker fixup either way, and
  `verify.py` is the check. What it does change is who may write them, and the answer
  turns out to be "a text file".

  ~~`FilterIsOn` IS NOT IN THIS LIST, deliberately.~~ **IT IS NOW EXPORTED, and the
  DGROUP ADDRESS is what forced it.** $02cd sits between `FilterOff` at $02cb and
  `MaxOutputFreq` at $02ce, both interface globals, and a unit lays its interface
  declarations down before its implementation ones -- so nothing private can land
  there. It is in the ordered block at the top of this file with the rest. The
  shadowing hazard is real and is handled at the one place it bites: VTCFG writes
  ModCommands' `FilterIsOn` at $0348 and now says so by qualifying the reference.
  -------------------------------------------------------------------------- }
{ ~~TicksPerSecond~~ IS GONE FROM HERE. It is SoundDevices' typed constant at $0bcc,
  holding 50 -- see the note there. This unit had it AND DevGus had it, and the DGROUP
  layout says it is neither's: $0bcc sits between `TickSnapshot` at $0bca and `UsingGUS`
  at $0bce, both of which are the core's. Left as a declaration here it would SHADOW the
  real one for every reference in this unit, which is a bug no byte comparison can see. }

  { DS:$1208 -- EXPORTED, because `1000:0311` fills it: the program does
    `FillChar(UserVols, 8, VtVolume)` to set every channel to its master volume before
    a module starts. The release keeps it in its interface too, in the same VAR group as
    ActualHz and Permisos. It was private here, which the program could not reach. }

{ ==========================================================================
  THIS UNIT'S DGROUP VARIABLE BLOCK, $11f0..$1745, IN ADDRESS ORDER.

  The addresses were all correct and the ORDER was not, which is a distinction nothing
  could measure until the program linked: a `var` is space the linker never writes, so
  `dgroup.py` cannot see it, and inside a `.TPU` every reference to one is an unresolved
  fixup that `verify.py` excuses. `demovt/linkcmp.py` compares the LINKED code, where
  each of those fixups is a real address, and it reported this block scattered over
  fourteen different deltas -- +3530, +3976, -428, -700 and the rest -- which is what a
  correctly-sized block in the wrong internal order looks like.

  THE RELEASE'S INTERFACE VAR GROUP IS THIS ORDER EXACTLY: SplBuf, then ActualHz, NoteHz,
  NoteCalcVal, UserVols, Permisos, TickCount, ModTickProc, MyCanFallBack, FilterVal.
  1.31 continues with NoteBuff where 1.39b has `PlayModStack`, and then agrees again on
  Canales, BuffGive, Buffers and SizeOfABuffer.

  FIVE OF THE ADDRESSES BELOW ARE BASE-1 BASES rather than the arrays themselves, and
  this file already records the rule: `$11ee` is SplBuf's, `$1207` UserVols', `$120f`
  Permisos', `$123a` Canales' and `$1384` RawChannels'. An instruction naming one of
  those is indexing the array, not touching the byte.

  Only the first five need to be visible: `UserVols` because 1000:0311 fills it, and the
  four above it because they have to precede it. The rest follow in the implementation,
  which keeps them private without moving them -- a unit's implementation variables come
  after all of its interface ones, so the order is preserved either way.
  ========================================================================== }
var
  SplBuf          : array[1..8] of Word;  { DS:$11f0  base-1 base $11ee }
  ActualHz        : Word;  { DS:$1200 }
  NoteHz          : Word;  { DS:$1202 }
  NoteCalcVal     : LongInt;  { DS:$1204 }
  UserVols        : TVolumes;             { DS:$1208  base-1 base $1207 }

{ 12ba:132f -- negotiate the rate, size the buffers, program the DMA. Declared
  here because 12ba:0d4e calls it and it lives 1,500 bytes further down the
  segment; the release exports it too, as `PROCEDURE ChangeSamplingRate(Hz:
  WORD)`. Its body is a PLACEHOLDER until the transcription reaches 132f. }
procedure ChangeSamplingRate(Hz : Word); far;

{ 12ba:1008 -- the release exports this too. }
{ NEW IN v1.51: EXPORTED, WHICH IS WHAT MAKES IT FAR. v1.31b keeps
  AdvanceEventRow private and near -- 12ba:0187 ends `LEAVE / RET`. v1.51's ends
  `LEAVE / RETF` at 12ce:04b9, and DEVGUS's interrupt handler calls it directly
  at 106e:0019 as `CALLF 12ce:03d9`. One declaration moving from the
  implementation to the interface changes the routine's own linkage AND gives
  another unit the right to call it. }
procedure AdvanceEventRow; far;

procedure ProcessTickEntry; far;

{ 12ba:13d7 -- stop playing and give the buffers back. Declared here because
  12ba:127c calls it from inside PlayStart's out-of-memory path, 1,300 bytes
  above it; the release exports it too, as `PROCEDURE PlayStop`. Its body is a
  PLACEHOLDER until the transcription reaches 13d7. }
procedure PlayStop; far;

{ 12ba:10a1 -- start playing a module. EXPORTED BECAUSE 1000 CALLS IT:
  1000:0381 is `CALLF 12ba:10a1` from inside PlayModule, and until segment 1000
  was read nothing outside this unit was known to reach it, so it was declared
  in the implementation only. The release exports it too, as
  `PROCEDURE PlayStart(VAR Song: TSong)`.

  SEVENTH INTERFACE CORRECTED BY A CALLER IN ANOTHER SEGMENT -- see VTDOSRSZ,
  VTDOSMEM, GUS, UNKLOADE, TSong.Status and HARDWARE.DMAReset. Exporting an
  already-far routine cannot move a byte; PLAYMOD verifying unchanged is the
  check. }
procedure PlayStart(var Song : TSong); far;

implementation

{ ======================= NOTES WITHOUT DECLARATIONS =======================
  Everything from here to the next `type` section describes a global that now
  lives in one of this unit's two ORDERED blocks -- the typed constants at the top
  of the file, $02c4..$0333, or the variables further down, $11f0..$1745. The notes
  are kept because several of them record measurements that are not repeated there;
  what they no longer do is sit next to the declaration they describe, and the
  address each one opens with is how to find it. ======================= }
  { DS:$13a4. The release keeps this in its implementation section too, which
    is where the disassembly puts it -- nothing outside 12ba reads it. }


{ NOTE ON A DECLARATION THAT NOW LIVES IN THE ORDERED CONST BLOCK AT THE TOP
  OF THIS FILE -- it does NOT describe the declaration below it. }
  { DS:$02d1, THE RENAME FLAG, and it is declared in two units. VTMAIN owns it
    as `AltMode` -- set when the executable is called INCONEXI.EXE -- and
    nothing in THAT segment reads it; this is the only reader. A global's
    address is a linker fixup, so the byte comparison cannot see the
    duplication either way, which is exactly the shape of risk 1 and exactly
    what DEVGUS's three duplicated globals looked like. Left declared here,
    flagged rather than resolved: settling it needs the DGROUP layout. }


  { DS:$02f0 -- ONE cursor, shared. 12ba:0202 and 12ba:0275 post into the row
    it names and 12ba:02ea ADVANCES it before flushing, so a post always lands
    in the row the flush has just reached. That is where the ring's look-ahead
    comes from, and it is why neither producer needs a cursor of its own. }

  { DS:$02f4 -- `Raw.Flags` UNDER CONSTRUCTION, and the bit values are what say
    so: 12ba:03cc starts it at 2 and then adds $01, $04, $10 and $20, which are
    exactly rcfActiveChannel, rcfLongSample, rcfDoesLoop, rcfLongLoopLen and
    rcfLongLoopEnd. It was read as "a GUS voice control byte" until the last two
    turned up. Whatever stores it into the record is further down the routine.

    DS:$02f5 is its companion: set to 1 when the sample's loop is shorter than
    four bytes -- treated as no loop at all -- and 0 when it loops, which is why
    every test of it reads `= 0`. }

  { DS:$0bce -- THE SECOND DUPLICATED GLOBAL IN THIS UNIT, and the same shape as
    AltMode above. DevGUS declares it as `Started` in its IMPLEMENTATION section,
    so it is private there and invisible here, yet 12ba:05a8 plainly reads it: the
    routine below posts nothing unless the GUS driver has started. One of the two
    declarations has to go when DGROUP ownership is settled, and the release gives
    no guidance because 1.39b rebuilt its GUS support elsewhere. Flagged, not
    resolved -- and invisible to the byte comparison either way. See risk 1. }

{ NOTE ON A DECLARATION THAT NOW LIVES IN THE ORDERED CONST BLOCK AT THE TOP
  OF THIS FILE -- it does NOT describe the declaration below it. }
  { --- the sequencer's state, DS:$02d6 upward -----------------------------
    The 63-byte record at DS:$1220 is the release's `TPlayingNote` -- ITS FIRST
    FIELD IS CONFIRMED and nothing else is. 1.39b describes `EoMod` as "TRUE if
    it is the note following the last", and 12ba:06fe sets exactly that from a
    row number of $FFFF. The release's record is 32 bytes and this one is 63, so
    the rest of the layout does not carry over and is left as filler.

    The two indices and the pointer follow the release's naming where the role
    matches; they are provisional. }
  { DS:$13a6, AND $1384 IS THE BASE-1 BASE RATHER THAN THE ARRAY. Every access
    is `IMUL DI,i,$22 / ADD DI,$1384`, which for i=1 lands on $13a6 -- one 34-byte
    element above $1384, exactly as the base-1 rule says. 12ba:12ba settles it
    outright: `FillChar(RawChannels, SIZEOF(RawChannels), 0)` passes $13a6 and
    $0110, and $0110 is 272, which is 8 x 34. The earlier comment here gave $1384
    as the array's own address and it was the base. }

  { All four names are the release's, and each is confirmed by what 12ba does
    with it: ActualHz divided by the tick rate gives samples per tick, capped by
    MaxSplPerTick -- whose release comment is literally "Maximum samples in the
    buffer. Means maximum samples per tick." }
  { THE RELEASE'S DECLARATION ORDER, AND THE ADDRESSES CONFIRM IT: `BuffIdx,
    BuffGive : WORD;` then `Buffers` then `SizeOfABuffer` is $1390, $1392, $1394,
    $13a0 -- four consecutive declarations landing on four consecutive addresses,
    which is far stronger than any single name matching.

    BUT `NumBuffers` IS 1 HERE, NOT THE RELEASE'S 3, and that is measured rather
    than inferred. 12ba:1232 passes SIZEOF(Buffers) to FillChar as an immediate
    $0b -- one 11-byte TSampleBuffer, not three -- and 12ba:1299 closes the
    allocation loop with `CMP [BP-2],1`. The addresses agree independently: three
    buffers would run $1394..$13b6 and swallow SizeOfABuffer, ModFlag and
    MuestrasPerTick, which are at $13a0, $13a2 and $13a4.

    AND IT EXPLAINS THE THREE DISABLED ROTATIONS. `Inc(BuffIdx)` then a clamp to
    1 at 0c30, the same clamp on BuffGive at 108c, and the note buffer pinned to
    slot zero at 06c0 are not switched-off features -- with one buffer the clamp
    IS the arithmetic, and `if BuffIdx > NumBuffers` with NumBuffers = 1 is
    exactly what the release writes. 1.31 simply had one. }

  { Both the release's names. `SplBuf` carries each channel's filter state from
    one call to the next -- it is what FilterChunkWord takes as `OldSpl` and
    returns -- and `FilterVal` is the method in force. Base-1 again: the compiler
    addresses SplBuf from $11ee, one element below its real start. }

  { All four the release's names, and each confirmed by its use here: the pair of
    methods and the switch between them at 12ba:0f15, and the per-channel
    permission at 12ba:0f2a -- "permissions for playing the channels", which is
    exactly what it gates. Base-1 again for the array. }
{ NOTE ON A DECLARATION THAT NOW LIVES IN THE ORDERED CONST BLOCK AT THE TOP
  OF THIS FILE -- it does NOT describe the declaration below it. }
  { DS:$02cd -- AND THIS IS NOT ModCommands' `FilterIsOn`, which is at DS:$0348.
    142f:04da writes that one from the E0x command and nothing reads it; this one is
    read by the initialisation section at 12ba:1430 to choose between FilterOn and
    FilterOff. Two variables where the release has one. ModCommands keeps its copy in
    its IMPLEMENTATION section precisely so that this name cannot be shadowed here --
    if both were exported, every reference in this unit would silently bind to this
    one and no byte comparison could see it. }

  { DS:$02ce -- the release's `MaxOutputFreq`, whose comment is "Maximum frequency
    of the output sound. Less means less memory for buffers." Divided by the tick
    rate at 12ba:1174 it gives exactly MaxSplPerTick, which is that sentence. }

  { DS:$0bca -- THE FOURTH DUPLICATED GLOBAL. VTMAIN owns it as `Snapshot` and
    12ba compares it against `VTSilenc.Ticks` at DS:$0bc8, which IS exported and
    is used from here directly. So one of the pair resolves cleanly and the other
    does not, in the same comparison. Risk 1 again. }

  { DS:$034e IS A TICK COUNTER WITHIN THE ROW, not the row number, and
    docs/04-units.md has it as "the current row". 12ba:0cdf compares it against
    `NoteProcessed^.Tempo` -- the release's "number of ticks the note will last"
    -- and 12ba:0cf7 resets it to zero when the pattern advances. A row number
    would be compared against a pattern length and would not reset. }

  { DS:$121e -- the release's `MyCanFallBack`, "actual permission to fall back",
    and the use fits exactly: with permission withheld, SoundDevices' request to
    fall back to a lower rate is simply cleared. }
  { DS:$0328 -- ONE GLOBAL, TWO JOBS, like DS:$02f6 before it. At 12ba:0d14 it
    holds a candidate sample rate while the driver is negotiated; from 12ba:0da1
    it is the control variable of a loop over the channels. The name is neutral
    because neither role owns it. }


type
  { For calling the driver record's +$26 through its Pointer field, the way
    SOUNDDEV already does with `TInitDevProc`. That one is a procedure; this one
    returns the rate the device settled on, which 12ba:0d44 stores. }
  TGetFreqProc = function(Hz : Word) : Word;

  { The release's own type, and 12ba:1032 confirms both arguments: the song by
    reference and a Boolean, computed there as `TickInRow = 0` -- so the flag
    means "this is the row's first tick". }
  TTickProc = procedure(var Song : TSong; Note : Boolean);

{ ...and the rest, private but in the same run -- see the note above. }
var
  Permisos        : array[1..8] of Boolean;  { DS:$1210  base-1 base $120f }
  TickCount       : Word;  { DS:$1218 }
  ModTickProc     : TTickProc;  { DS:$121a }
  MyCanFallBack   : Boolean;  { DS:$121e }
  FilterVal       : TFilterMethod;  { DS:$121f }
  NoteBuff        : array[0..0] of TPlayingNote;  { DS:$1220  63 bytes, then a pad }
  Canales         : array[1..8] of TCanal;  { DS:$1260  base-1 base $123a }
  BuffIdx         : Word;  { DS:$1390 }
  BuffGive        : Word;  { DS:$1392 }
  Buffers         : array[1..NumBuffers] of TSampleBuffer;  { DS:$1394 }
  SizeOfABuffer   : Word;  { DS:$13a0 }
  ModFlag         : Boolean;  { DS:$13a2 }
  MuestrasPerTick : Word;  { DS:$13a4 }
  RawChannels     : array[1..MaxChannels] of TModRawChan;  { DS:$13a6  base-1 base $1384 }
  NoteRing        : array[0..RingRows - 1] of TRingRow;  { DS:$14b6 }
  EventRing       : array[0..RingRows - 1] of TGusEventRow;  { DS:$1646 }

{ ---- MORE NOTES WITHOUT DECLARATIONS ----------------------------------------
  Same as the run above: these described variables that are now in the ordered
  block at $11f0..$1745, a few lines up. ---------------------------------- }
  { The release's name, confirmed by 12ba:1008 along with the guard it returns on,
    the song it plays and the flag that says the procedure has been set up -- the
    other four of that group are typed constants and are in the ordered block at the
    top of this file. }


{ NOTE ON A DECLARATION THAT NOW LIVES IN THE ORDERED CONST BLOCK AT THE TOP
  OF THIS FILE -- it does NOT describe the declaration below it. }
  { DS:$0bcc -- THE THIRD DUPLICATED GLOBAL, after AltMode and UsingGUS. DevGUS
    declares it privately in its implementation section, where a comment already
    records that the release moved it to SoundDevices and that ownership is the
    open question rather than the name. 12ba reads it here. Risk 1 again. }
  { DS:$02f6 -- ONE GLOBAL, TWO JOBS. At 06bc it is the note buffer's next slot;
    from 0802 it is the control variable of a `for` loop over the channels. The
    first use is finished before the second starts, so the reuse is harmless --
    but it is why the name is neutral rather than either role's. }

{ NOTE ON A DECLARATION THAT NOW LIVES IN THE ORDERED CONST BLOCK AT THE TOP
  OF THIS FILE -- it does NOT describe the declaration below it. }
  { DS:$0334 -- THE RELEASE'S `MyLoopMod`, no longer provisional. Its assignment
    at 1121..113d is the release's `(TRUE AND (MyRepStart <> 0)) OR ForceLoopMod`
    character for character, including the commented-out LoopMod operand that is why a
    literal 1 is tested there, and 0717 reads it as the release's line 821 does.
    The client-facing `LoopMod` it was named after is a DIFFERENT variable, at
    $02c8; see its declaration in the interface. }
  { MOVED TO ModCommands as well: `CurSpeed` ($0349) and `CurTempo` ($0338), which
    142f:04a6 and 142f:04bc write from the F-command. Names unchanged; the release
    calls them Tempo and BPMIncrement and the rename is declined there for reasons
    given at the declaration. }

  { MOVED TO ModCommands: `NextSeq` ($034c), `NextNote` ($034a) and `MySongLen`
    ($0340), which this unit knew as NextSeq, NextNote and MySongLen. 142f writes all
    three from its effect routines, and PlayMod uses ModCommands rather than the
    other way round, so ModCommands has to own them. See the note at their
    declaration; the release splits them the same way. }
  { The range a caller ASKS for, copied into the working three at 12ba:10b4.
    Provisional names: nothing outside 12ba has been seen to set them. }
{ NOTE ON A DECLARATION THAT NOW LIVES IN THE ORDERED CONST BLOCK AT THE TOP
  OF THIS FILE -- it does NOT describe the declaration below it. }
  { DS:$02c9 -- the release's `ForceLoopMod`, "TRUE if music must be played
    forever", and 12ba:112e uses it exactly that way: it forces LoopMod on. }


{ --------------------------------------------------------------------------
  12ba:1600 -- the resampling kernel, and the whole reason this unit links an
  object module. `PUSH BP / MOV BP,SP` is not what starts it; the prologue
  scanner found `ENTER $000`, which is the hand-written frame of an assembler
  routine, and 1.39b builds its equivalent from `LIB/PLAYMOD.ASM` under a $L.

  NOT TRANSCRIBED YET. `PLAYMOD.ASM` currently holds a stub so that the link
  resolves and everything above it can be measured; the stub is the LAST thing
  in the segment, so it displaces nothing.

  The signature is read off the call sites at 009b, 0111 and 016f -- eight
  arguments, 22 bytes, so the kernel ends `RET $16`:

    Src        VAR, the channel's SplPosFrac onward -- the kernel's state
    Dest       VAR, the output pointer, ADVANCED by the call
    Volume     Byte, and 0 for the silent call
    Step       LongInt, StepFrac + StepInt * 65536
    SrcLimit   Word, distance to the next boundary -- loop end or sample end
    Max        Word, how many samples are still owed
    ChanAdd    Word, NumChannels * 2, the stride between output samples
    Silent     Boolean, 1.31's single kernel doing 1.39b's two jobs
  -------------------------------------------------------------------------- }
{$L PLAYMOD.OBJ}
function DumpInstrument(var Src; var Dest; Volume : Byte; Step : LongInt;
                        SrcLimit, Max, ChanAdd : Word;
                        Silent : Boolean) : Word; external;

{ --------------------------------------------------------------------------
  12ba:0000 -- takes six bytes of arguments and does nothing with them.

  `PUSH BP / MOV BP,SP / LEAVE / RET 6`, and the RET is NEAR, so this is not a
  procedural-type slot: a `TTickProc` is far. It is the same do-nothing shape as
  the four stubs in `17cf`. Named for the release's `NullProcedure`, which is the
  same idea rather than the same routine -- the pairing is by ROLE only.

  THREE WORDS, NOT A POINTER AND A WORD, and the only call site says so:
  12ba:0697 pushes `6a ff / 6a 00 / 6a 00`, three immediates. A Pointer argument
  would be built and pushed differently. The six bytes are the same either way
  in THIS routine -- `RET 6` regardless -- but the caller's bytes are not, which
  is why the declaration matters. Names are placeholders: nothing reads them.
  -------------------------------------------------------------------------- }
procedure NullProcedure(A, B, C : Word);
begin
end;

{ --------------------------------------------------------------------------
  12ba:0007 -- UnCanal. Mix one channel into its own buffer.

  `Rest` doubles as the argument and the result: the kernel is told how many
  samples are still owed and reports how many are STILL owed after it ran, so
  "did anything happen" and "how much is left" are one value. It is a typed
  constant at DS:$02ea in the release and the disassembly agrees -- `a3 ea 02`.

  THE KERNEL IS NEVER ASKED TO CROSS A LOOP POINT. Each call is bounded by the
  distance to the next boundary and the loop re-enters after subtracting one
  loop length, which is what lets the kernel be a straight-line run with no wrap
  test in it at all.
  -------------------------------------------------------------------------- }
procedure UnCanal(var Raw : TModRawChan; var Buf : Pointer);
begin
  Rest := MuestrasPerTick;                          { 000a..000f              }

  if ((Raw.Flags and rcfActiveChannel) <> 0) and    { 0010..001e              }
     ((Raw.Flags and rcfSampleFinished) = 0) then   { 001f..002d              }
  begin
    if (Raw.Flags and rcfDoesLoop) <> 0 then        { 002e..003c              }
      while Rest <> 0 do                            { 003d..0043              }
      begin
        Rest := DumpInstrument(Raw.SplPosFrac, Buf, Raw.Volume,
                               Raw.StepFrac + LongInt(Raw.StepInt) * 65536,
                               Raw.LoopEnd - Raw.SplPosInt, Rest,
                               NumChannels * 2, False);   { 0044..00a0        }
        if Rest <> 0 then                                 { 00a1..00a7        }
          Dec(Raw.SplPosInt, Raw.LoopLen)                 { 00a8..00b5        }
      end
    else
      Rest := DumpInstrument(Raw.SplPosFrac, Buf, Raw.Volume,
                             Raw.StepFrac + LongInt(Raw.StepInt) * 65536,
                             Raw.SplLimit - Raw.SplPosInt, Rest,
                             NumChannels * 2, False)      { 00ba..0116        }
  end;

  if Rest > 0 then                                        { 0117..011d        }
  begin
    Rest := DumpInstrument(Raw.SplPosFrac, Buf, 0,
                           Raw.StepFrac + LongInt(Raw.StepInt) * 65536,
                           Raw.SplLimit - Raw.SplPosInt, Rest,
                           NumChannels * 2, True);        { 011e..0174        }
    Raw.Flags := Raw.Flags or rcfSampleFinished           { 0175..0182        }
  end
end;

{ --------------------------------------------------------------------------
  12ba:0187 -- step the event ring on by one row and tally what is in it.

  A NEAR procedure taking nothing, with one Pointer local at [BP-4].

  THE SHAPE IS A `FOR`, AND THE READING PASS HAD IT AS A NESTED `IF`.
  docs/04-units.md records this as `if Counter > $18 then begin ... if $02d1
  <> 0 then ... else Inc($02ee) end`, which is what `MOV [02ee],0 / JMP past /
  INC [02ee]` looks like if the loop is not recognised -- Borland's FOR opens
  exactly that way, with the increment sitting ABOVE the body and jumped over
  on entry. The `JNZ` at `01e8` closes it back onto the `INC`, and the `CMP
  [02ee],7` before it is the limit. So `$02ee` is a loop variable over the
  eight entries of a row, not a second counter, and the rename flag is tested
  UNCONDITIONALLY rather than inside the wrap.

  The `CLD` at `018b` is the compiler's, not ours: Turbo Pascal emits it in the
  prologue of any routine whose body uses a string instruction, and the
  `FillChar` at the end is one.

  The counters it bumps live in `VTCtrl.CtrlBlock`, the 768-byte structure
  published over INT 2Fh, so a client can read per-channel activity out of it.
  -------------------------------------------------------------------------- }
procedure AdvanceEventRow;
begin
  { 018b -- a hand-written CLD, and it has to be hand-written: Turbo Pascal
    emits no such prologue byte here, and the FillChar below is a runtime CALL
    rather than an inlined string instruction, so nothing in the body asks the
    compiler for one. Somebody wanted the direction flag known-good on a path
    the timer can reach. }
  asm
    CLD                                             { 018b                   }
  end;

  Inc(EventSlot);                                   { 018c..018f             }
  if EventSlot > RingRows - 1 then                  { 0190..0196             }
    Dec(EventSlot, RingRows);                       { 0197..019b             }
  if AltMode then                                   { 019c..01a2             }
    EventSlot := 0;                                 { 01a3..01a7             }

  for EventChan := 0 to 7 do                        { 01a8..01b2, 01e3..01e9 }
  begin
    { 01b3..01ca -- a WITH, and the frame slot is its doing.
      OLD NOTE, kept because the reasoning is the useful part: `@Ring[..]`
      gets the INDEX computation exactly right, byte for byte, through 01c0:
      `MOV AX,EventChan / SHL AX,1 / MOV DI,EventSlot / SHL DI,4 / ADD DI,AX`.
      What differs is the four instructions after it:

        original   ADD DI,OFFSET Ring / MOV [BP-4],DI / MOV [BP-2],DS
        ours       LEA AX,[DI+Ring] / MOV DX,DS / MOV [BP-4],AX / MOV [BP-2],DX

      Turbo Pascal wants a pointer VALUE in AX:DX to assign; the original never
      forms one, it just stores the offset it already has in DI beside DS.
      `Ptr(Seg(NoteRing), ...+ Ofs(NoteRing))` was tried and is
      WORSE -- it changes the index arithmetic too and the prefix drops from
      01c1 to 01b3. Whatever the original wrote, it is a form that leaves the
      offset in DI.

      IT IS A `with`. Turbo Pascal implements `with <indexed record>` by
      computing the record's address ONCE into a hidden four-byte frame slot,
      stored exactly like that -- offset from the register it was accumulated
      in, then DS -- and every field reference inside the block reloads it with
      `LES DI,[BP-4]`, which is what 01cb and 01d5 do. So the `ENTER 4,0` at
      0187 is the with-slot and this routine declares NO local at all. }
    with NoteRing[EventSlot, EventChan] do              { 01b3..01ca             }
      if Note <> 0 then                             { 01cb..01d4             }
        Inc(CtrlBlock.Filler1[Chan])                { 01d5..01e2             }
  end;

  FillChar(NoteRing[EventSlot], SizeOf(TRingRow), 0)    { 01ea..01ff             }
end;

{ --------------------------------------------------------------------------
  12ba:0202 -- fill one slot of the GUS event ring.

  Near, `RET $14`, and the seven arguments are `TriggerVoice`'s own list minus
  its `Voice`, which is used here to index the row rather than being stored.
  No test of any kind: this is the raw setter, and `12ba:0275` is the one that
  checks whether the slot is free and merges if it is not.

  Another `with` -- `ENTER 4,0`, the address stored as offset-then-DS at
  [BP-4], and `LES DI,[BP-4]` reloaded before every field. Six stores, six
  reloads, which is what makes the shape unmistakable once seen.

  Parameter names avoid the field names deliberately: inside a `with`, an
  unqualified name binds to the record field first, so `Vol := Vol` would
  quietly assign the field to itself.
  -------------------------------------------------------------------------- }
procedure SetEvent(Voice, AVol : Byte; AFreq : Word; APan : Byte;
                   AStart, ALoop, AEnd : LongInt);
begin
  with EventRing[RingSlot, Voice] do             { 0206..0220                }
  begin
    Vol    := AVol;                              { 0221..0229                }
    Freq   := AFreq;                             { 022a..0233                }
    Pan    := APan;                              { 0234..023d                }
    StartA := AStart;                            { 023e..024e                }
    LoopA  := ALoop;                             { 024f..025f                }
    EndA   := AEnd                               { 0260..0270                }
  end
end;

{ --------------------------------------------------------------------------
  12ba:0275 -- post a voice event, merging into whatever is already there.

  Near, `RET 8`, the same `with` on the same slot as 12ba:0202 -- but only the
  first four of the event's fields, so a merge never touches the three sample
  addresses.

  A SLOT IS FREE WHEN ITS `Freq` IS ZERO. There is no separate valid flag and
  none is needed: 12ba:02ea wipes each slot as it flushes it, so a slot is
  always clean by the time the ring comes round again.

  AND $FF / $FFFF MEAN "LEAVE THIS ONE ALONE". On the merge path each field is
  written only if the argument is not its all-ones value, which is how a caller
  changes the pitch of a voice without disturbing its volume, or the reverse.
  `Pan` IS NOT GUARDED AT ALL on the merge path -- it is written every time,
  outside both tests. docs/04-units.md has it inside the `Freq` test
  (`if B <> $FFFF then begin E^[1] := B; E^[3] := C end`) and the byte comparison
  says otherwise: the `JZ` at 02d0 jumps ten bytes, which is the `Freq` store
  alone, not the twenty the pair would need. So a caller CANNOT leave the pan
  alone by passing $FFFF for the frequency.
  -------------------------------------------------------------------------- }
procedure PostEvent(Voice, AVol : Byte; AFreq : Word; APan : Byte);
begin
  with EventRing[RingSlot, Voice] do             { 0279..0293                }
    if Freq = 0 then                             { 0294..029d                }
    begin
      Vol  := AVol;                              { 029e..02a6                }
      Freq := AFreq;                             { 02a7..02b0                }
      Pan  := APan                               { 02b1..02ba                }
    end
    else
    begin
      if AVol <> $FF then                        { 02bd..02c2                }
        Vol := AVol;                             { 02c3..02cb                }
      if AFreq <> $FFFF then                     { 02cc..02d1                }
        Freq := AFreq;                           { 02d2..02db                }
      Pan := APan                                { 02dc..02e5                }
    end
end;

{ --------------------------------------------------------------------------
  12ba:02ea -- advance the event ring by one row, apply it, wipe it.

  Near, no arguments. Advance, apply, then wipe -- so a row is always clean by
  the time the ring comes round to it again, which is exactly why 12ba:0275's
  "is this slot free" test can be a bare `Freq = 0` with no valid flag.

  THE TWO GUS ENTRY POINTS ARE CHOSEN BY `EndA > 0`, on the 32-bit value: the
  `CMP [DI+$0e],0 / JG / JL / CMP [DI+$0c],0 / JBE` at 0330 is Turbo Pascal's
  LongInt comparison, high word first. A voice with loop information gets the
  full `TriggerVoice`; one without gets `ChangeVoiceParams`, which sets pitch,
  volume and pan on a voice that is already running. `Freq` is a Word in the ring
  and a LongInt in both calls, widened here with `XOR DX,DX`.
  -------------------------------------------------------------------------- }
procedure FlushEventRow;
begin
  asm
    CLD                                          { 02ee                      }
  end;

  Inc(RingSlot);                                 { 02ef..02f2                }
  if RingSlot > RingRows - 1 then                { 02f3..02f9                }
    Dec(RingSlot, RingRows);                     { 02fa..02fe                }

  for RingVoice := 0 to 7 do                     { 02ff..0309, 03a9..03b2    }
    with EventRing[RingSlot, RingVoice] do       { 030a..0322                }
      if Freq <> 0 then                          { 0323..032c                }
        if EndA > 0 then                         { 032d..033f                }
          TriggerVoice(RingVoice, Vol, Freq, Pan,
                       StartA, LoopA, EndA)      { 0340..0383                }
        else
          ChangeVoiceParams(RingVoice, Vol, Freq, Pan);   { 0386..03a8       }

  FillChar(EventRing[RingSlot], SizeOf(TGusEventRow), 0)  { 03b3..03c9       }
end;

{ --------------------------------------------------------------------------
  12ba:03cc -- a sample descriptor into GUS voice control. NOT TRANSCRIBED.

  664 bytes, the largest routine in the segment so far, and docs/04-units.md
  covers only its first three statements. What IS established:

  THE SIGNATURE, read off the call site at 12ba:09e3 rather than the callee,
  per the standing rule. It pushes `MOV AL,[02f8] / PUSH AX` (a Byte), then
  `IMUL DI,[02f8],$22 / ADD DI,$1384 / PUSH DS / PUSH DI` (the address of a
  34-byte record), then a four-byte value read out of `[0300]^` at `+6`/`+8`.
  With `RET $0a` and near linkage that gives

      procedure ?(Chan : Byte; var Raw : TModRawChan; Desc : PSampleDesc);

  and it CONFIRMS DS:$1384 as the `RawChannels` array -- `IMUL ..,$22` is the
  34-byte stride of the record already declared above.

  THE OPEN QUESTION, and it is worth being precise about rather than guessing:
  `[BP+8]` -- the `var Raw` parameter -- is used TWO different ways.

      03da  MOV DI,[BP+8]        then MOV [DI+$0d],AX      DS-relative
      044c  LES DI,[BP+8]        then MOV ES:[DI+$17],AX   far, ES reloaded

  Both are correct at runtime, because `RawChannels` is in DGROUP and the
  segment the caller pushed IS DS. But Turbo Pascal emits the far form for a
  `var` parameter, and it emits it at 044c -- so whatever produces the
  DS-relative form at 03da is a different source construct reaching the same
  record, not the same one compiled twice. Resolving that is the next step, and
  it decides the shape of the first statement.

  RESOLVED: THE BODY IS HAND-WRITTEN ASSEMBLER. The tell is `21 C0` at 03f7 --
  `AND AX,AX` in the `r/m,reg` direction, which is what Turbo Pascal's INLINE
  ASSEMBLER emits and what its CODE GENERATOR does not; the compiler tests a
  value with `OR`, as `08 C0` at 12ba:0018 and `0B 46 06` at 03d2 both show. So
  `MOV DI,Raw` inside an `asm` block is the DS-relative form -- in TP's asm a
  `var` parameter names the POINTER, and loading its low word gives the offset,
  which is correct here because RawChannels is in DGROUP. The far accesses lower
  down are the compiled Pascal between the asm blocks.

  Same shape as `1a17`'s GetPlayPos: a compiled routine with hand-written asm
  inside it, and the encodings are what separate the two halves.
  -------------------------------------------------------------------------- }

procedure SetGusVoiceCtl(Chan : Byte; var Raw : TModRawChan; Desc : PSampleDesc);
begin
  { 03cf..03d9 -- compiled: `OR AX,[BP+6]` is the code generator's direction,
    and the `JNZ +3 / JMP` pair is what a large if-body gives when the skip is
    out of short range. }
  if Desc <> nil then
  begin
    { 03da..0413 -- HAND-WRITTEN, transcribed verbatim per the standing rule.
      Equivalent Pascal, REFERENCE ONLY -- the compiler does not produce these
      bytes from it, which is how the block was identified:

          Raw.SplOfs1 := the word at Desc^ + $12
          Raw.SplSeg1 := the word at Desc^ + $14
          VoiceCtl := 2;
          if (WordAt(Desc, 9) = 0) and (ByteAt(Desc, 8) < 4) then
            NoLoop := 1
          else
          begin
            NoLoop := 0;
            NewFlags := NewFlags or rcfDoesLoop
          end;

      `MOV DI,Raw` loads the low word of the `var` parameter -- the offset --
      and the stores through it are DS-relative, which is correct because
      RawChannels lives in DGROUP. }
    asm
      MOV     DI, WORD PTR Raw       { 03da  the offset half of the var param }
      LES     SI, Desc               { 03dd                                   }
      MOV     AX, ES:[SI+$12]        { 03e0  the sample data pointer, offset   }
      MOV     [DI+$0d], AX           { 03e4  -> Raw.SplOfs1                    }
      MOV     AX, ES:[SI+$14]        { 03e7  ... and segment                    }
      MOV     [DI+$0f], AX           { 03eb  -> Raw.SplSeg1                     }

      MOV     BYTE PTR NewFlags, rcfActiveChannel  { 03ee                  }
      MOV     AX, ES:[SI+$09]        { 03f3  loop length, high word            }
      DB      21h, 0C0h              { 03f7  AND AX,AX -- 21 C0 is the inline  }
                                     {       assembler's direction; the code   }
                                     {       generator would emit OR           }
      JNZ     @@Looping              { 03f9                                    }
      MOV     AL, ES:[SI+$08]        { 03fb  loop length, low byte             }
      CMP     AL, 4                  { 03ff  under four bytes is no loop       }
      JNC     @@Looping              { 0401                                    }
      MOV     BYTE PTR NoLoop, 1  { 0403                                    }
      JMP     @@Ctl                  { 0408                                    }
  @@Looping:
      MOV     BYTE PTR NoLoop, 0  { 040a                                    }
      OR      BYTE PTR NewFlags, rcfDoesLoop     { 040f                    }
  @@Ctl:
    end;

    { 0414..042b -- compiled: Turbo Pascal's LongInt comparison, high word
      first, `CMP ES:[DI+2],0 / JG / JGE / CMP ES:[DI],$FFF0 / JA`. $FFF0 is
      65,520, which is what `rcfLongSample` means: a sample too long for one
      64K part. }
    if Desc^.SplLen > $FFF0 then
    begin
      { 042c..0452 -- HAND-WRITTEN again, and the DS-relative store at 0437 is
        what says so. Equivalent Pascal, REFERENCE ONLY:

            NewFlags := NewFlags or rcfLongSample;
            Raw.SplLimit1 := $FFF0;
            Raw.SplLimit2 := Desc^.SplLen - $FFF0;

        so the first part is capped at 65,520 bytes and the remainder becomes
        the second. `SBB DX,0` carries the subtraction into the high word even
        though only the low word is stored -- the compiler's own idiom, kept
        verbatim. }
      asm
        MOV     DI, WORD PTR Raw       { 042c                                }
        LES     SI, Desc               { 042f                                }
        OR      BYTE PTR NewFlags, rcfLongSample   { 0432                    }
        MOV     WORD PTR [DI+$11], $FFF0   { 0437  -> Raw.SplLimit1          }
        LES     DI, Desc               { 043c                                }
        MOV     AX, ES:[DI]            { 043f  SplLen, low word              }
        MOV     DX, ES:[DI+$02]        { 0442  ... and high                   }
        SUB     AX, $FFF0              { 0446                                }
        SBB     DX, 0                  { 0449                                }
        LES     DI, Raw                { 044c                                }
        MOV     ES:[DI+$17], AX        { 044f  -> Raw.SplLimit2              }
      end;

    { 0453..0472 -- compiled, and the shape names the field: `LES DI,ES:[DI+$16]`
      loads a FAR POINTER out of the descriptor and then `MOV AX,DI` / `MOV AX,ES`
      take its halves, which is `Ofs(P^)` and `Seg(P^)` -- an Ofs of a
      dereference, not of the field. }
    Raw.SplOfs2 := Ofs(Desc^.Data2^);
    Raw.SplSeg2 := Seg(Desc^.Data2^);

    if NoLoop = 0 then                              { 0473..047c            }
    begin
      { 047d..04b1 -- two LongInt comparisons with short-circuit `or`. The loop
        needs no splitting if it lies wholly inside one 64K part: either it
        starts beyond the boundary, or it starts and ends below it. `$FFF0` is
        the same 65,520 as above. }
      if (Desc^.LoopStart > $FFF0) or
         (Desc^.LoopStart + Desc^.LoopLen <= $FFF0) then
        { 04b2..04c1 -- the low word only, which is what makes the LongInt
          field assignable to a Word without a cast. }
        Raw.LoopLen := Desc^.LoopLen
      else
      begin
        { 04c2..04de -- the loop STRADDLES the 64K boundary, so its length is
          measured from the start of the second part and the flag says so.
          `ADD byte,$10` rather than `OR`, which is what `Inc` gives. }
        Raw.LoopLen := Desc^.LoopLen - $FFF0;
        Inc(NewFlags, rcfLongLoopLen)
      end;

      { 04df..0547 -- and the same question again for the loop's END. The sum is
        recomputed in the test and in both branches, three times over, which is
        Turbo Pascal re-evaluating rather than anything in the source. }
      if Desc^.LoopStart + Desc^.LoopLen <= $FFF0 then
        Raw.LoopEnd := Desc^.LoopStart + Desc^.LoopLen
      else
      begin
        Raw.LoopEnd := Desc^.LoopStart + Desc^.LoopLen - $FFF0;
        Inc(NewFlags, rcfLongLoopEnd)
      end
      end
    end
  else
    { 054a..056a -- HAND-WRITTEN, the short-sample path. `AND AL,AL` at 0559 is
      `20 C0`, the inline assembler's direction; the compiler's own test is
      `08 C0`, which is what 05ba has twelve bytes later. Everything here is
      16-bit because a sample under 64K needs no splitting at all.

      Equivalent Pascal, REFERENCE ONLY:

          Raw.SplLimit1 := Desc^.SplLen;
          if NoLoop = 0 then
          begin
            Raw.LoopLen := Desc^.LoopLen;
            Raw.LoopEnd := Desc^.LoopLen + Desc^.LoopStart
          end }
    asm
      MOV     DI, WORD PTR Raw       { 054a                                   }
      LES     SI, Desc               { 054d                                   }
      MOV     AX, ES:[SI]            { 0550  SplLen, low word                 }
      MOV     [DI+$11], AX           { 0553  -> Raw.SplLimit1                 }
      MOV     AL, NoLoop             { 0556                                   }
      DB      20h, 0C0h              { 0559  AND AL,AL -- inline asm direction }
      JNZ     @@NoLoop               { 055b                                   }
      MOV     AX, ES:[SI+$08]        { 055d  LoopLen                          }
      MOV     [DI+$20], AX           { 0561  -> Raw.LoopLen                   }
      ADD     AX, ES:[SI+$04]        { 0564  + LoopStart                      }
      MOV     [DI+$1e], AX           { 0568  -> Raw.LoopEnd                   }
  @@NoLoop:
    end;

  { 056b..05a7 -- HAND-WRITTEN, and common to both paths. It turns the LENGTHS
    gathered above into absolute offsets by adding each part's own base, points
    the play position at the start of the sample, and finally stores the flags.

    THE LAST TWO INSTRUCTIONS ARE WHY $02f4 IS `Raw.Flags`: `MOV AL,NewFlags /
    MOV [DI],AL`. Everything the routine has been accumulating since 03ee lands
    in the record's first byte.

    Equivalent Pascal, REFERENCE ONLY:

        Raw.SplPosFrac := 0;
        Raw.SplPosInt  := Raw.SplOfs1;   Raw.SplOfs := Raw.SplOfs1;
        Raw.SplPosSeg  := Raw.SplSeg1;   Raw.SplSeg := Raw.SplSeg1;
        Inc(Raw.LoopEnd,   Raw.SplOfs1);
        Inc(Raw.SplLimit2, Raw.SplOfs2);
        Inc(Raw.SplLimit1, Raw.SplOfs1);
        Raw.SplLimit := Raw.SplLimit1;
        Raw.Flags := NewFlags }
  asm
    MOV     DI, WORD PTR Raw         { 056b                                   }
    MOV     WORD PTR [DI+$01], 0     { 056e  SplPosFrac                       }
    MOV     AX, [DI+$0d]             { 0573  SplOfs1                          }
    MOV     [DI+$03], AX             { 0576  -> SplPosInt                     }
    MOV     [DI+$07], AX             { 0579  -> SplOfs                        }
    MOV     AX, [DI+$0f]             { 057c  SplSeg1                          }
    MOV     [DI+$05], AX             { 057f  -> SplPosSeg                     }
    MOV     [DI+$09], AX             { 0582  -> SplSeg                        }
    MOV     AX, [DI+$1e]             { 0585  LoopEnd                          }
    ADD     AX, [DI+$0d]             { 0588  + SplOfs1                        }
    MOV     [DI+$1e], AX             { 058b                                   }
    MOV     AX, [DI+$17]             { 058e  SplLimit2                        }
    ADD     AX, [DI+$13]             { 0591  + SplOfs2                        }
    MOV     [DI+$17], AX             { 0594                                   }
    MOV     AX, [DI+$11]             { 0597  SplLimit1                        }
    ADD     AX, [DI+$0d]             { 059a  + SplOfs1                        }
    MOV     [DI+$11], AX             { 059d                                   }
    MOV     [DI+$0b], AX             { 05a0  -> SplLimit                      }
    MOV     AL, NewFlags             { 05a3                                   }
    MOV     [DI], AL                 { 05a6  -> Raw.Flags                     }
  end;

  { 05a8..065f -- compiled, and back to the event ring. `DS:$0bce` is
    `DevGUS.Started`, so nothing is posted unless the GUS driver is running --
    which is the clearest statement yet that this whole routine is the GUS path.

    Both arms call 12ba:0202, and both pass $FF and $FFFF for the volume and the
    frequency: the sentinels that mean "leave those alone", so the event carries
    only a pan position and the three DRAM addresses. A looping sample gets
    LoopA and EndA measured from the loop; a one-shot gets LoopA = -1 and EndA at
    the end of the sample. }
  if UsingGUS then                             { 05a8..05b1             }
    if (Raw.Flags and rcfDoesLoop) <> 0 then         { 05b2..05bd             }
      SetEvent(Chan - 1, $FF, $FFFF, Pannings[Chan],
               Desc^.Data1,
               Desc^.Data1 + Desc^.LoopStart,
               Desc^.Data1 + Desc^.LoopStart + Desc^.LoopLen)  { 05be..061d   }
    else
      SetEvent(Chan - 1, $FF, $FFFF, Pannings[Chan],
               Desc^.Data1, -1,
               Desc^.Data1 + Desc^.SplLen)           { 0620..065f             }
  end
end;

{ --------------------------------------------------------------------------
  12ba:0664 -- MyMove. A hand-written Move, and the 1.39b release has it
  INSTRUCTION FOR INSTRUCTION: `LIB/PLAYMOD.PAS` line 701 declares
  `PROCEDURE MyMove(VAR Src, Dest; Bytes: WORD); ASSEMBLER` with exactly this
  body, down to the label names. The closest pairing found in this segment, and
  the source below is the release's with our address comments added.

  WHY IT EXISTS. Word moves are twice the speed of byte moves on an 8086 but
  want alignment, so it copies one leading byte when the source is odd, runs
  `REP MOVSW`, and mops up a trailing byte. It aligns on the SOURCE offset --
  `TEST SI,1` -- not the destination.

  The parameters are NAMED, so Turbo Pascal gives the `assembler` procedure a
  frame: `PUSH BP / MOV BP,SP` at 0664 and `LEAVE / RET $0a` at 068f are the
  compiler's, not ours, which is why no RET is written below.
  -------------------------------------------------------------------------- }
procedure MyMove(var Src, Dest; Bytes : Word); assembler;
asm
        PUSH    DS                     { 0667                                }

        LDS     SI, Src                { 0668                                }
        LES     DI, Dest               { 066b                                }
        MOV     CX, Bytes              { 066e                                }

        CLD                            { 0671                                }

        AND     CX, CX                 { 0672  21 C9 -- the inline assembler's }
                                       {       direction, as everywhere here   }
        JZ      @@Fin                  { 0674                                }

        TEST    SI, 1                  { 0676  align on the SOURCE            }
        JZ      @@NoBeg                { 067a                                }
        MOVSB                          { 067c  one leading byte               }
        DEC     CX                     { 067d                                }
        JZ      @@Fin                  { 067e                                }

@@NoBeg:
        MOV     BX, CX                 { 0680                                }
        SHR     CX, 1                  { 0682                                }
        REP     MOVSW                  { 0684                                }
        MOV     CX, BX                 { 0686                                }
        AND     CL, 1                  { 0688                                }
        JZ      @@Fin                  { 068b                                }

        MOVSB                          { 068d  and the trailing byte          }
@@Fin:
        POP     DS                     { 068e                                }
end;

{ --------------------------------------------------------------------------
  12ba:0693 -- advance to the next pattern, and honour a seek request.
  IN PROGRESS: transcribed as far as 070d.

  THE SEEK INTERFACE. `DS:$24c9`, `$24ca` and `$24cb` are `CtrlBlock + $203`,
  `+$204` and `+$205` -- inside the 768-byte structure published over INT 2Fh,
  and `VTCtrl` already names them `SeekWant`, `SeekPos` and `SeekRow`. So a
  resident client can ask the player to jump: set the position and row, raise the
  flag, and the next time the sequencer crosses a pattern boundary it honours the
  request and clears the flag. It is the only part of the control block a client
  WRITES rather than reads. Psycho Neurosis never uses it.

  AND THE ROTATION IS DISABLED. `INC AX` at 06bf is immediately followed by
  `AND AX,0`, so the next slot is always slot zero: the two-slot rotation of
  63-byte rows is there and switched off by one instruction. Transcribed as
  found -- `and 0` and all -- because tidying it would change the bytes. It also
  makes the MyMove below copy slot zero onto itself.
  -------------------------------------------------------------------------- }
procedure NextPattern(var Song : TSong);
begin
  NullProcedure($FFFF, 0, 0);                        { 0697..069f            }

  if CtrlBlock.SeekWant <> 0 then                    { 06a0..06a6            }
  begin
    CtrlBlock.SeekWant := 0;                         { 06a7..06ab            }
    NextSeq := CtrlBlock.SeekPos;                    { 06ac..06b3            }
    NextNote := CtrlBlock.SeekRow                     { 06b4..06bb            }
  end;

  NextIdx := (NoteHd + 1) and 0;                  { 06bc..06c5            }
  NoteProcessed := @NoteBuff[NextIdx];                 { 06c6..06d7            }
  MyMove(NoteBuff[NoteHd], NoteProcessed^, SizeOf(TPlayingNote));  { 06d8..06ed   }
  NoteHd := NextIdx;                              { 06ee..06f3            }

  with NoteProcessed^ do
  begin                                              { 06f4..06fd            }
    EoMod := NextNote = $FFFF;                        { 06fe..070d            }

    if EoMod then                                    { 070e..0716            }
      if MyLoopMod then                              { 0717..071d            }
      begin
        { The module wraps. Jump to the end position, clamped up to the start,
          and take it from row 1 -- then clear the marker so the row is played
          rather than treated as past the end. }
        NextSeq := RangeEnd;                         { 071e..0723            }
        if NextSeq < RangeStart then                 { 0724..072c            }
          NextSeq := RangeStart;                     { 072d..0732            }
        NextNote := 1;                                { 0733..0738            }
        EoMod := False                               { 0739..073f            }
      end
      else
      begin
        { No looping permission: stop, and leave. The JMP at 0747 goes to the
          routine's own exit, which is what `Exit` compiles to. }
        Playing := False;                            { 0742..0746            }
        Exit                                         { 0747                  }
      end;

    NotePlaying := NextNote;                          { 074a..0753            }
    SeqPlaying  := NextSeq;                          { 0754..075d            }
    { AN ARRAY ASSIGNMENT, NOT A `Move`, AND THE RTL ROUTINE IS WHAT SAYS SO. There are
      TWO copy helpers in Turbo Pascal's SYSTEM with identical signatures, and they are
      eleven bytes apart in behaviour: `1ba1:0fb2` is `Move`, which compares the pointers
      and copies BACKWARDS when the regions overlap, and `1ba1:09f7` is the same loop with
      no overlap check at all -- the helper the compiler uses for a whole-array or
      whole-record assignment, where it knows the operands are distinct. The original calls
      `09f7`; a written `Move` gets `0fb2`.

      **AND OUR `SYSTEM` IS THE AUTHOR'S, WHICH IS WHAT MADE THIS READABLE.** All three RTL
      segments -- OBJECTS, DOS and SYSTEM -- are byte-identical to the original's, so the
      two addresses are two routines in the SAME library rather than evidence of a
      different one. That closes the RTL half of risk 2 and turns this from a toolchain
      question into a source one. }
    Volume := UserVols;                              { 075e..0772            }

    { 0773..078d -- `Pattern := Song.GetPatternSeq(SeqPlaying)`, a far call into
      14b9. THAT UNIT IS A STUB -- see demovt/src/VTSONG.PAS -- but the call site
      is real: the arguments, their order and the far linkage are read off these
      bytes, and the target is a pending fixup exactly as the linker would leave
      it. The position is pushed FIRST, so it is the first declared parameter and
      `Song` the second; 1.39b calls the equivalent as a method, which its own
      history block explains -- `TSong` became an object in February 1993. }
    Pattern := Song.GetPatternSeq(SeqPlaying);       { 0773..078d            }

    { 078e..07c1 -- advance one row, or fall off the end of the pattern and
      advance the order position instead. `Pattern^.Rows^` is a byte reached
      through a far pointer at the pattern's +$06; a position past the last one
      sets the row to $FFFF, which is the marker 06fe tests on the next call. }
    if Pattern^.Rows^.RowCount > NextNote then        { 078e..07a0            }
      Inc(NextNote)                                   { 07a1..07a4            }
    else
    begin
      Inc(NextSeq);                                  { 07a7..07aa            }
      if NextSeq > MySongLen then                     { 07ab..07b3            }
        NextNote := $FFFF                             { 07b4..07b9            }
      else
        NextNote := 1;                                { 07bc..07c1            }
    end;

    { 07c2..0893 -- an EMPTY order position. `GetPatternSequence` returning zero
      means there is no pattern here, so the module's own defaults come back, every
      channel is wiped and given a silent note, and the sequencer walks forward
      until it finds a position that does have one -- or runs off the end.

      This block was blocked until 14b9 could be declared: the call's result drives
      the branch, which a byte placeholder cannot do. See demovt/src/VTSONG.PAS. }
    if Song.GetPatternSequence(SeqPlaying) = 0 then   { 07c2..07dc            }
    begin
      CurSpeed := Song.InitialTempo;                       { 07dd..07e6            }
      CurTempo := Song.InitialBPM;                       { 07e7..07f2            }
      FillChar(Canales, SizeOf(Canales), 0);           { 07f3..0801            }

      { A silent note at period 800 in every channel. }
      for NextIdx := 1 to 8 do                         { 0802..080d, 083e..0844 }
        with Canales[NextIdx] do
        begin
          Note.Period     := 800;                      { 081d..0825            }
          Note.Instrument := 1;                        { 0826..082c            }
          Note.Command    := 0;                        { 082d..0834            }
          Period          := 800                       { 0835..083d            }
        end;

      { 0845..0887 -- walk forward. A position past the last sets the row to
        $FFFF, which both ends this loop and marks the module as finished for the
        next call. }
      repeat
        Inc(SeqPlaying);                               { 0845..084b            }
        if SeqPlaying > MySongLen then                  { 084c..085a            }
          NextNote := $FFFF                             { 085b..0862            }
        else
          NextNote := 2                                 { 0863..0868            }
      until (NextNote = $FFFF) or                        { 0869..086f            }
            (Song.GetPatternSequence(SeqPlaying) <> 0);  { 0870..0887          }

      NextSeq := SeqPlaying                            { 0888..0893            }
    end;

    { 0894..08ec -- the SPEED for this row, if anything overrides it. Two sources,
      and the row number picks between them: on row 1 a per-position byte out of
      14b9's second table, otherwise the pattern's own. Zero means "no override"
      in both cases, so the speed set at 07dd stands.

      Turbo Pascal evaluates `GetPatternTempo` TWICE here, once for the test and
      once for the value, which is what the two identical CALLFs at 08ad and 08c5
      are -- not a source that calls it twice deliberately. }
    if NotePlaying = 1 then                            { 0894..089d            }
      if Song.GetPatternTempo(SeqPlaying) <> 0 then  { 089e..08b5            }
        CurSpeed := Song.GetPatternTempo(SeqPlaying) { 08b6..08cc            }
      else
      begin
        if Pattern^.Rows^.Speed <> 0 then              { 08cf..08dd            }
          CurSpeed := Pattern^.Rows^.Speed             { 08de..08ec            }
      end;

    { 08ed..0965 -- once per channel: fetch this row's note out of the song and
      keep a copy in the row being handed on.

      `Song.NumChannels` is not a constant, so Turbo Pascal evaluates the limit into a
      temporary at [BP-6] before the loop -- the same four bytes the `with` above
      used, reused now that the `with` is finished. That is a compiler temporary
      sharing a slot, not a variable being reused.

      The copy at 0946 goes through MyMove rather than an assignment, and the
      address it builds -- `ChanIdx*6 + 6` from the record's base -- is what
      fixed TPlayingNote's layout: base-1 indexing of the Note array at +$0c. }
    for ChanIdx := 1 to Song.NumChannels do                  { 08ed..090c            }
    begin
      CurCanal := @Canales[ChanIdx];                   { 090d..091e            }
      Song.GetNote(SeqPlaying, NotePlaying, ChanIdx,
                   NewNote);                          { 091f..0945            }
      MyMove(NewNote, Note[ChanIdx], SizeOf(TFullNote));  { 0946..0965         }

      { 0966..098e -- DOES THIS ROW RETRIGGER THE CHANNEL? Two groups joined by
        `or`, each short-circuited, and the jump targets read straight off:

          a new instrument number that differs from the one playing, OR
          a period with a command that is not 4 or 6

        Commands 4 and 6 are ProTracker's vibrato and vibrato-plus-volume-slide:
        they carry a period for the vibrato to work from and must NOT restart the
        sample. That is the whole point of the second group. }
      if ((NewNote.Instrument <> 0) and
          (CurCanal^.Note.Instrument <> NewNote.Instrument)) or
         ((NewNote.Period <> 0) and
          (NewNote.Command <> 4) and (NewNote.Command <> 6)) then
      begin
        { 098f..09c7 -- a new instrument: remember it and fetch its sample data. }
        if NewNote.Instrument <> 0 then                { 098f..0995            }
        begin
          CurCanal^.Note.Instrument := NewNote.Instrument;      { 0996..099f   }
          CurCanal^.Instrument :=
            Song.GetInstrument(NewNote.Instrument)^.Data       { 09a0..09c7   }
        end;

        { 09c8..09e5 -- and hand the sample to the GUS voice. This is the call
          site that gave SetGusVoiceCtl its signature back when 03cc was
          transcribed: the channel number as a Byte, the raw channel by
          reference, the descriptor by value. }
        SetGusVoiceCtl(ChanIdx, RawChannels[ChanIdx],
                       CurCanal^.Instrument)           { 09c8..09e5            }
      end;

      { 09e6..0a0e -- a new instrument also resets the channel's volume to that
        instrument's own default, which lives at the descriptor's +$0c. The nil
        test is `MOV AX,[DI+6] / OR AX,[DI+8]`, both halves of the pointer, which
        is how Turbo Pascal compares a Pointer against nil. }
      if (NewNote.Instrument <> 0) and
         (CurCanal^.Instrument <> nil) then            { 09e6..09fa            }
        CurCanal^.Volume := CurCanal^.Instrument^.Volume;   { 09fb..0a0e       }

      { 0a0f..0a37 -- the note's own volume overrides it, stored one lower than
        written, and clamped to 64 whichever way it arrived. }
      if NewNote.Volume <> 0 then                    { 0a0f..0a15            }
        CurCanal^.Volume := NewNote.Volume - 1;      { 0a16..0a23            }
      if CurCanal^.Volume > 64 then                  { 0a24..0a2e            }
        CurCanal^.Volume := 64;                      { 0a2f..0a37            }

      { 0a38..0a4c -- hand the note to the effects unit. `CommandStart` is the
        release's name and the argument order is its own; see MODCOMMA.PAS. }
      CommandStart(Song, CurCanal^, NewNote);        { 0a38..0a4c            }

      { 0a4d..0a57 -- and NOT `Tempo := CurSpeed`, which is what the enclosing
        `with` would give. The original reloads the pointer from DS:$02dc, so the
        source names it: inside a `with P^ do`, writing `P^.Field` explicitly
        makes Turbo Pascal reload P instead of using the with-slot. Two different
        instruction sequences for the same assignment. }
      NoteProcessed^.Tempo := CurSpeed;                   { 0a4d..0a57            }

      { 0a58..0a72 -- publish the channel's event into the note ring, where
        12ba:0187 will tally it into the control block. The ring is indexed by
        the CONSUMER's slot, DS:$02ec, not the event ring's. }
      NoteRing[EventSlot, ChanIdx - 1].Note :=
        CurCanal^.RingNote;                          { 0a58..0a72            }
      NoteRing[EventSlot, ChanIdx - 1].Chan :=
        CurCanal^.RingChan;                          { 0a73..0a8d            }
      CurCanal^.RingNote := 0                        { 0a8e..0a96            }
    end;                                             { 0a97..0aa1  for end   }

    { 0aa2..0ad6 -- how many samples this row is worth.

      `ActualHz div TicksPerSecond` is samples per tick, capped by MaxSplPerTick;
      multiplied by the row's tick count it gives `NMuestras`, which the release
      documents as "Number of samples processed for each note". `NoteHz` starts
      the row at the same rate and is floored at 1 -- a zero would divide by zero
      in the tick arithmetic that follows. }
    MuestrasPerTick := ActualHz div TicksPerSecond;   { 0aa2..0aad            }
    if MuestrasPerTick > MaxSplPerTick then           { 0aae..0ab6            }
      MuestrasPerTick := MaxSplPerTick;               { 0ab7..0abc            }

    { UNQUALIFIED here, where 0a4d was explicit -- and the bytes are what say
      so: this one is `LES DI,[BP-4]`, the with-slot, where 0a4d reloads from
      DS:$02dc. The author wrote one of these two the long way and not the other,
      in the same routine, ten instructions apart. }
    NMuestras := Tempo * MuestrasPerTick;             { 0abd..0ad0            }

    NoteHz := ActualHz;                               { 0ad1..0ad6            }
    if NoteHz = 0 then                                { 0ad7..0add            }
      NoteHz := 1;                                    { 0ade..0ae3            }

    { 0ae4..0b07 -- A DIVISION AND THEN A SHIFT, NOT TWO DIVISIONS. `1ba1:0a2e` is the
      32-bit divide and `1ba1:0aa8` is the 32-bit SHIFT LEFT -- `AND CX,1Fh / SHL AX,1 /
      RCL DX,1 / LOOP` -- with `MOV CX,4` in front of it, so the second operation
      multiplies by sixteen where this read `div 4`. `1ba1:0a9c`, twelve bytes earlier, is
      the shift RIGHT; the two are easy to confuse and this file already cites 0aa8 as
      `shl` from 17cf:0091.

      **AND THE RELEASE HAS THIS LINE COMMENTED OUT, WHICH IS WHERE THE CONSTANT COMES
      FROM.** `LIB/PLAYMOD.PAS` line 938 holds a commented-out
      `NoteCalcVal := ((65536*13900) DIV NoteHz) SHL 8;` above the live line that replaced
      it, and 65536 * 13900 is $364C0000
      exactly. So 1.31 is the earlier form the release commented out, with a shift of 4
      rather than 8 -- 1.39b's live line reworks both the constant and the shift
      (`(LONGINT(13900) SHL 12) DIV NoteHz SHL 11`).

      Written as the literal rather than as `65536 * 13900` so the dividend cannot depend
      on how TP folds a constant expression that overflows an Integer; the loaded bytes
      are `XOR AX,AX / MOV DX,364C` either way. }
    NoteCalcVal := ($364C0000 div NoteHz) shl 4;      { 0ae4..0b07            }

    { 0b08..0b24 -- publish the row. The tail index catches up with the head and
      the sounding pointer with the processed one, so whatever reads `NoteSound`
      now sees the row this call built. Then the same do-nothing call the routine
      opened with, this time with zeros. }
    NoteTl := NoteHd;                                 { 0b08..0b0d            }
    NoteSound := NoteProcessed;                       { 0b0e..0b1b            }
    NullProcedure(0, 0, 0)                            { 0b1c..0b24            }
  end
end;

{ --------------------------------------------------------------------------
  12ba:0b29 -- the software mixing path, once per tick. IN PROGRESS.

  This is what drives `UnCanal` and the filters, per channel, and it is the
  other half of the unit: 12ba holds two independent output paths and the driver
  decides which runs. `IsDmaDevice` is the switch -- on a DMA device the mixing
  happens elsewhere and this routine does almost nothing.
  -------------------------------------------------------------------------- }
procedure MixTick(var Song : TSong);
begin
  NullProcedure($FFFF, $FFFF, $FFFF);                { 0b2d..0b35            }

  ModRec  := @Buffers[BuffIdx];                      { 0b36..0b47            }
  ModFlag := ModRec^.InUse;                          { 0b48..0b51            }
  if ModFlag then                                    { 0b52..0b58            }
    Exit;                                            { 0b59                  }

  { 0b66..0bf9 -- mix every channel, unless the device does its own DMA mixing.
    Each channel writes into its own slice of the module's buffer, interleaved by
    the channel count, and is then filtered in place with the state carried in
    SplBuf. `FilterChunkWord`'s `Offs` is that interleave stride, which is why the
    channel count is passed there. }
  if not IsDmaDevice then                            { 0b5c..0b65            }
    for MixChan := 1 to Song.NumChannels do                { 0b66..0b85            }
    begin
      ChanRec := @RawChannels[MixChan];              { 0b86..0b97            }
      OutPtr  := @PWordArray(ModRec^.IData)^[MixChan - 1]; { 0b98..0bb2       }
      UnCanal(ChanRec^, OutPtr);                     { 0bb3..0bc0            }
      SplBuf[MixChan] := FilterChunkWord(OutPtr^, MuestrasPerTick,
                                         Song.NumChannels, FilterVal,
                                         SplBuf[MixChan])   { 0bc1..0bf1     }
    end;

  { 0bfa..0c0c -- and mark the entry played, with the sample count it produced.
    Both paths reach here: the DMA one jumps straight to it from 0b63. }
  ModRec^.InUse    := True;                          { 0bfa..0c01            }
  ModRec^.NSamples := MuestrasPerTick;               { 0c02..0c0c            }
  ModRec^.RateHz   := NoteHz;                        { 0c0d..0c17            }
  ModRec^.DataType := 1;                             { 0c18..0c20            }
  ModRec^.Channels := Song.NumChannels;                    { 0c21..0c2f            }

  { 0c30..0c40 -- AND THE SECOND DISABLED ROTATION IN THIS UNIT. `Inc(ModIdx)`
    followed by a clamp to 1 means the index is 1 from the first call onward, so
    only one entry of the module table is ever used -- exactly like the `and 0` at
    12ba:06c0 pinning the note buffer to slot zero. Two independent pieces of
    machinery for handling more than one of something, both switched off by their
    own next instruction. Transcribed as found. }
  Inc(BuffIdx);                                       { 0c30..0c33            }
  if BuffIdx > 1 then                                 { 0c34..0c3a            }
    BuffIdx := 1;                                     { 0c3b..0c40            }

  NullProcedure(0, $FFFF, 0)                         { 0c41..0c49            }
end;

{ --------------------------------------------------------------------------
  12ba:0c4e -- the sequencer tick, and the tempo engine. IN PROGRESS.

  THE HANDSHAKE. `ModFlag` non-zero means the module buffer still holds samples
  nobody has taken, so the tick cannot advance: MixTick is called, and if the flag
  is STILL set afterwards this routine gives up for now. That is why 12ba:0b57
  reads the way it does, and it is the same protocol seen from the other side.

  On a DMA device the tick is also gated on the timer: `VTSilenc.Ticks` is what
  the interrupt increments and DS:$0bca is this side's snapshot of it, so equal
  counters mean nothing new has happened yet.
  -------------------------------------------------------------------------- }
procedure SeqTick(var Song : TSong);
begin
  if IsDmaDevice and (TickSnapshot = Ticks) then     { 0c52..0c64            }
    Exit;
  Inc(TickSnapshot);                                 { 0c65..0c68            }

  if ModFlag and not UsingGUS then                 { 0c69..0c76            }
  begin
    MixTick(Song);                                   { 0c77..0c7e            }
    if ModFlag then                                  { 0c7f..0c85            }
      Exit                                           { 0c86                  }
  end;

  if UsingGUS then                                 { 0c89..0c8f            }
    FlushEventRow;                                   { 0c90..0c92            }
  AdvanceEventRow;                                   { 0c93..0c95            }

  Inc(TickCount);                                    { 0c96..0c99            }

  { 0c9a..0ca3 -- a 32-bit counter INSIDE the published control block, at
    CtrlBlock + $125, immediately after the dispatch pointer. Together with the
    per-channel counters 12ba:0187 bumps, that is live state any INT 2Fh client
    can read. Psycho Neurosis never does. }
  Inc(CtrlBlock.Ticks32);                            { 0c9a..0ca3            }

  { 0ca4..0cf6 -- THE TEMPO ENGINE, and it divides nothing per row. `TempoAccum`
    is a running fractional accumulator, `CurTempo` the amount added each tick and
    `TempoDiv` the divisor: the tick counter advances by the whole part and the
    remainder is carried. That is how a tracker gets a non-integer ticks-per-row
    ratio -- arbitrary BPM -- out of integer arithmetic alone. }
  PrevTick := TickInRow;                             { 0ca4..0cab            }
  Inc(TempoAccum, CurTempo);                         { 0cac..0cb2            }
  Inc(TickInRow, TempoAccum div TempoDiv);           { 0cb3..0cbf            }

  { ONLY THE `mod` IS GUARDED. The `JZ` at 0cc9 jumps thirteen bytes, which is the
    remainder statement alone -- the row test below is reached either way. Written
    with the second `if` nested, the jump would have to clear both. }
  if TickInRow <> PrevTick then                      { 0cc0..0cca            }
    TempoAccum := TempoAccum mod TempoDiv;           { 0ccb..0cd7            }

  { The row is over when its tick count is reached. `Tempo` is the release's name
    and its comment is "Number of ticks the note will last". }
  if TickInRow >= NoteProcessed^.Tempo then          { 0cd8..0ce4            }
  begin
    NextPattern(Song);                               { 0ce5..0cec            }
    if not Playing then                              { 0ced..0cf3            }
      Exit;                                          { 0cf4                  }
    TickInRow := 0                                   { 0cf7..0cfb            }
  end;

  { 0cfc..0d22 -- the fall-back request. `PleaseFallback` is SoundDevices' way of
    saying it could not get a buffer at the current rate; permission to act on it
    is MyCanFallBack's, and without it the request is just dropped.

    THE SECOND `if` IS A TAUTOLOGY as it stands -- `NewHz` is assigned from
    `ActualHz` on the line before and then compared against it, with nothing in
    between that could change either. Transcribed as found: the bytes at 0d1a are
    a real load, compare and branch, and removing them would shift everything
    after. It reads like a check that lost whatever used to sit between the two
    statements -- the same shape as the dead operand setup in 1a17's GetPlayPos. }
  if not MyCanFallBack then                          { 0cfc..0d02            }
    PleaseFallback := 0;                             { 0d03..0d07            }

  if PleaseFallback > 0 then                         { 0d08..0d0e            }
  begin
    PleaseFallback := 0;                             { 0d0f..0d13            }
    TmpVal := ActualHz;                              { 0d14..0d19            }

    { 0d1a..0d48 -- NEGOTIATE A RATE THE DEVICE WILL ACCEPT. Ask what it can
      really manage; while that differs from what we want, drop the request by
      100 Hz and ask again.

      AND 0d1a IS THE HEAD OF THIS `while`, NOT A TAUTOLOGY. The note written a
      moment ago called it dead code -- `NewHz := ActualHz` followed by
      `if NewHz = ActualHz` -- because the loop's closing `JMP` at 0d47 had not
      been read yet. It jumps BACK to 0d1a, so the comparison is a loop condition
      that the body can falsify. Read the jumps out before calling anything
      dead. }
    while (TmpVal = ActualHz) and
          (TGetFreqProc(ActiveDevice^.GetRealFreqProc)(0) <> TmpVal) do
    begin                                            { 0d1a..0d32            }
      Dec(DesiredHz, 100);                           { 0d33..0d37            }
      TmpVal := TGetFreqProc(ActiveDevice^.GetRealFreqProc)(DesiredHz)
                                                     { 0d38..0d48            }
    end;

    { 0d49..0d50 -- and act on it. `PUSH CS / CALL near` is how Turbo Pascal
      calls a FAR routine that lives in the same segment, which is what
      ChangeSamplingRate is. }
    ChangeSamplingRate(DesiredHz)                    { 0d49..0d50            }
  end;

  TickChans := Song.NumChannels;                           { 0d51..0d5a            }
  NullProcedure($FFFF, 0, 0);                        { 0d5b..0d63            }

  { 0d64..0d97 -- run every channel's effect for this tick, unless this is the
    row's first tick and the song has nothing at Fill16[$24].

    THE LOOP IS HAND-WRITTEN. `LOOP` and `MUL BL` are not Turbo Pascal's output,
    and the callee takes its arguments in REGISTERS -- SI pointing at the channel,
    BX the command number doubled into a jump-table index. The release documents
    exactly that: "En las del tick, se entra con SI apuntando al TCanal
    correspondiente."

    Equivalent Pascal, REFERENCE ONLY -- there is none that produces these bytes:

        for i := TickChans downto 1 do
          CommandTick(Canales[i], Canales[i].Note.Command * 2) }
  if (TickInRow > 0) or (Song.FirstTick <> 0) then  { 0d64..0d74            }
    asm
      XOR     CH, CH                 { 0d75                                   }
      MOV     CL, TickChans          { 0d77                                   }
  @@Chan:
      PUSH    CX                     { 0d7b                                   }
      MOV     AL, CL                 { 0d7c                                   }
      DEC     AL                     { 0d7e                                   }
      MOV     BL, $26                { 0d80  the TCanal stride                }
      MUL     BL                     { 0d82                                   }
      MOV     SI, OFFSET Canales     { 0d84                                   }
      ADD     SI, AX                 { 0d87                                   }
      MOV     BL, [SI+$04]           { 0d89  Note.Command                     }
      ADD     BL, BL                 { 0d8c  doubled -- a word index          }
      XOR     BH, BH                 { 0d8e                                   }
      CALL    FAR PTR CommandTick    { 0d90                                   }
      POP     CX                     { 0d95                                   }
      LOOP    @@Chan                 { 0d96                                   }
    end;

  NullProcedure($FFFF, $FFFF, 0);                    { 0d98..0da0            }

  { 0da1..0e23 -- turn each channel's own volume into the mixing volume the
    resampler will use. The divisor is the channel count rounded UP to an even
    number, so the summed output cannot clip; the `shr 4` is the fixed-point
    scale on UserVols. }
  for TmpVal := 1 to Song.NumChannels do                   { 0da1..0dbc            }
  begin
    CanalPtr := @Canales[TmpVal];                    { 0dbd..0dd2            }
    RawPtr   := @RawChannels[TmpVal];                { 0dd3..0de4            }
    if not UsingGUS then
      { 0dec..0e23 -- the software path: divide the sum down so it cannot clip. }
      RawPtr^.Volume := CanalPtr^.Volume * UserVols[TmpVal] shr 4
                        div ((Song.NumChannels + 1) and $FFFE)
    else
      { 0e24..0e49 -- the GUS path needs no headroom, because the card mixes: the
        scale is `shr 6` with a rounding `+1` before the final halving. }
      RawPtr^.Volume := (CanalPtr^.Volume * UserVols[TmpVal] shr 6 + 1) shr 1;

    { 0e4a..0e6f -- AND THESE TWO ARE COMMON TO BOTH PATHS. The software branch's
      `JMP` at 0e22 lands on 0e4a, not past it, which is what says so; written
      inside the GUS branch they would be jumped over. }
    if RawPtr^.Volume >= $80 then                    { 0e4a..0e54            }
      RawPtr^.Volume := $80;                         { 0e55..0e5d            }

    { 0e5e..0e6f -- the master volume, and HAND-WRITTEN. Two tells: the pointer
      goes into SI, where Turbo Pascal's code generator always uses DI, and the
      multiply is the 8-bit `MUL BL` with the product's high byte stored straight
      back -- Pascal promotes `Byte * Byte` to a word and would emit `MUL DX`
      followed by a shift.

      Equivalent Pascal, REFERENCE ONLY:

          RawPtr^.Volume := RawPtr^.Volume * CtrlBlock.MasterVol shr 8 }
    asm
      LES     SI, RawPtr                 { 0e5e                              }
      MOV     AL, ES:[SI+$1d]            { 0e62  Volume                      }
      MOV     BL, CtrlBlock.MasterVol    { 0e66                              }
      MUL     BL                         { 0e6a                              }
      MOV     ES:[SI+$1d], AH            { 0e6c  the high byte = shr 8        }
    end;

    { 0e70..0e84 -- a period of zero would divide by zero downstream. }
    if CanalPtr^.Period = 0 then                     { 0e70..0e7a            }
      CanalPtr^.Period := 1;

    { 0e85..0ec4 -- turn the channel's period into the one the hardware wants,
      scaled by the instrument's own ratio when there is an instrument.

      THE ARITHMETIC IS HAND-WRITTEN: the pointer goes into SI throughout, and
      Turbo Pascal's code generator uses DI for every dereference it makes. Same
      tell as 0e5e, twelve instructions earlier.

      Equivalent Pascal, REFERENCE ONLY:

          CanalPtr^.RealPeriod := CanalPtr^.Period * Instrument^.PeriodMul
                                  div Instrument^.PeriodDiv }
    if CanalPtr^.Instrument <> nil then              { 0e85..0e92            }
      asm
        LES     SI, CanalPtr               { 0e93                            }
        MOV     AX, ES:[SI+$0b]            { 0e97  Period                    }
        LES     SI, ES:[SI+$06]            { 0e9b  -> the instrument         }
        MOV     DX, ES:[SI+$0e]            { 0e9f  PeriodMul                 }
        MUL     DX                         { 0ea3                            }
        MOV     BX, ES:[SI+$10]            { 0ea5  PeriodDiv                 }
        DIV     BX                         { 0ea9                            }
        LES     SI, CanalPtr               { 0eab                            }
        MOV     ES:[SI+$0d], AX            { 0eaf  -> RealPeriod             }
      end
    else
    begin
      { 0eb5..0edd -- no instrument, so there is nothing to play: the period is
        used unchanged and the channel is silenced outright. The `JMP` at 0eb3
        clears all of this, which is how the branch's real extent was found. }
      CanalPtr^.RealPeriod := CanalPtr^.Period;      { 0eb5..0ec4            }
      RawPtr^.Volume := 0;                           { 0ec5..0ecd            }
      RawPtr^.Flags := RawPtr^.Flags and not rcfActiveChannel   { 0ece..0edd }
    end;

    { 0ede..0f14 -- the resampling STEP for this channel: NoteCalcVal over the
      real period, rounded, then spread across the two words of a 16.16-ish
      fixed point -- `shl 4` into StepFrac and `shr 12` into StepInt.

      HAND-WRITTEN, and twice over: the pointer is in SI again, and the rounding
      (`ADD DX,DX / CMP DX,BX / JC / INC AX` -- double the remainder and compare
      against the divisor) is not something Turbo Pascal emits for `div`.

      Equivalent Pascal, REFERENCE ONLY:

          StepVal := round(NoteCalcVal / CanalPtr^.RealPeriod) }
    asm
      MOV     AX, WORD PTR NoteCalcVal      { 0ede                           }
      MOV     DX, WORD PTR NoteCalcVal+2    { 0ee1                           }
      LES     SI, CanalPtr                  { 0ee5                           }
      MOV     BX, ES:[SI+$0d]               { 0ee9  RealPeriod                }
      DIV     BX                            { 0eed                           }
      ADD     DX, DX                        { 0eef  twice the remainder       }
      CMP     DX, BX                        { 0ef1  ... at least the divisor? }
      JC      @@NoRound                     { 0ef3                           }
      INC     AX                            { 0ef5  then round up             }
  @@NoRound:
      MOV     StepVal, AX                   { 0ef6                           }
    end;

    RawPtr^.StepFrac := StepVal shl 4;               { 0ef9..0f06            }
    RawPtr^.StepInt  := StepVal shr 12;              { 0f07..0f14            }

    { 0f15..0f29 -- which filter is in force. }
    if FilterIsOn then                               { 0f15..0f1b            }
      FilterVal := FilterOn                          { 0f1c..0f23            }
    else
      FilterVal := FilterOff;                        { 0f24..0f29            }

    { 0f2a..0f56 -- and whether this channel is allowed to sound at all.

      WRITTEN AS A NEGATIVE. The test emits `JNZ` to the branch that SETS the
      bit, which is what `if not Permisos[..] then <clear> else <set>` gives; the
      positive form would put the setting branch first and jump on zero. One
      instruction decides which way round the source reads. }
    if not Permisos[TmpVal] then                     { 0f2a..0f34            }
      RawPtr^.Flags := RawPtr^.Flags and not rcfActiveChannel  { 0f35..0f46   }
    else
      RawPtr^.Flags := RawPtr^.Flags or rcfActiveChannel;      { 0f47..0f56   }

    { 0f57..0fb3 -- on the GUS, tell the card. A permitted channel gets its
      volume and a frequency derived from the real period; a muted one gets volume
      zero and $FFFF for the frequency, which is 12ba:0275's "leave that field
      alone" sentinel. Same constant family as NoteCalcVal's $364C0000. }
    if UsingGUS then                               { 0f57..0f5d            }
      if Permisos[TmpVal] then                       { 0f5e..0f68            }
        PostEvent(TmpVal - 1, RawPtr^.Volume,
                  $364C00 div CanalPtr^.RealPeriod,
                  Pannings[TmpVal])                  { 0f69..0f9c            }
      else
        PostEvent(TmpVal - 1, 0, $FFFF, Pannings[TmpVal]);  { 0f9f..0fb3     }

    { 0fb4..0fe0 -- and hold the period inside ProTracker's range, 57 to 1712. }
    if CanalPtr^.Period < $39 then                   { 0fb4..0fbe            }
      CanalPtr^.Period := $39                        { 0fbf..0fca            }
    else if CanalPtr^.Period > $6B0 then             { 0fcb..0fd6            }
      CanalPtr^.Period := $6B0                       { 0fd7..0fe0            }
  end;                                               { 0fe1..0feb  for end   }

  NullProcedure(0, 0, 0);                            { 0fec..0ff4            }

  { 0ff5..1003 -- and on a non-GUS device, mix this tick's samples now that every
    channel's step and volume are set. This is the second call to MixTick in the
    routine: the first, at 0c77, runs BEFORE the row is processed and only when the
    buffer still holds samples. }
  if not UsingGUS then                             { 0ff5..0ffb            }
    MixTick(Song)                                    { 0ffc..1003            }
end;

{ --------------------------------------------------------------------------
  12ba:1008 -- ProcessTickEntry. FAR, and the release exports it under that name.

  The whole tick, from the outside: unless execution is suppressed, either run the
  sequencer or -- if nothing is playing -- park the tick counter at 1, and then
  hand control to whatever tick procedure has been installed.

  `ModTickProc` is told whether this is the row's FIRST tick, computed as
  `TickInRow = 0` with the `MOV AL,0 / JNZ / INC AX` that Turbo Pascal emits for a
  Boolean expression.
  -------------------------------------------------------------------------- }
procedure ProcessTickEntry;
begin
  if DontExecute then                                { 100b..1013            }
    Exit;

  if not Playing then                                { 1014..101a            }
    TickInRow := 1                                   { 101b..1021            }
  else
    SeqTick(PlayingSong^);                           { 1022..102a            }

  if ModTickProcValid then                           { 102b..1031            }
    ModTickProc(PlayingSong^, TickInRow = 0)         { 1032..1046            }
end;

{ --------------------------------------------------------------------------
  12ba:1049 and 12ba:105d -- the two buffer callbacks the sound device asks
  through. Both are FAR functions of no arguments returning a PSampleBuffer,
  which is `SoundDevices.TAskBufferProc`, and both are the release's: it declares
  `FUNCTION IdleGiver : PSampleBuffer; FAR` and `FUNCTION BufferGiver :
  PSampleBuffer; FAR` in its implementation section, exactly here.

  `IdleGiver` NEVER GIVES ANYTHING. It sets the result to nil and returns -- the
  callback a driver gets while there is nothing to play.

  `BufferGiver` hands over the head buffer if it holds samples, then advances the
  head. `InUse` reads as "filled and owned by the device": the mixer at 12ba:0bfa
  SETS it when it finishes filling and refuses to refill while it is set, and this
  is the routine that passes it on.

  AND THE HEAD IS CLAMPED TO 1, so at most two of the three buffers are ever
  handed out and in practice only one. That is the third rotation in this unit
  disabled by its own next instruction -- see 06c0 and 0c30.
  -------------------------------------------------------------------------- }
function IdleGiver : PSampleBuffer; far;
begin
  IdleGiver := nil                                   { 104d..105a            }
end;

function BufferGiver : PSampleBuffer; far;
begin
  BufferGiver := nil;                                { 1061..1068            }

  { AN EARLY `Exit`, NOT A WRAPPED `if`. The test emits `JNZ +2 / JMP` with the
    jump landing on the epilogue at 1099 -- the un-folded pair this project's own
    notes list as the tell. Written as `if InUse then begin ... end` the compiler
    folds it into a single `JZ`, because the body is only 34 bytes and well within
    short range. }
  if not Buffers[BuffGive].InUse then                { 1069..1076            }
    Exit;

  BufferGiver := @Buffers[BuffGive];                 { 1077..1087            }
  Inc(BuffGive);                                     { 1088..108b            }
  if BuffGive > 1 then                               { 108c..1092            }
    BuffGive := 1                                    { 1093..1098            }
end;

{ --------------------------------------------------------------------------
  12ba:10a1 -- start playing a module. IN PROGRESS.

  `CLI`-guarded from its first instruction to each of its exits, because it
  rewrites the state the timer handler reads. The release exports the equivalent as
  `PROCEDURE PlayStart(VAR Song: TSong)` and 1.31 TAKES THE SAME ONE ARGUMENT --
  an earlier reading here gave it a second Word, which the exit disproves: 132c is
  `RETF 4`, four bytes of parameters, which is the `var` reference alone, and 10a5
  reads `Song` at [BP+6] rather than [BP+8]. That invented argument was the four
  real differences in this routine's first block and the one-byte shift under all
  of them.

  The three requested range values are copied into the working ones, each with a
  fallback: an unset length comes from the song, an unset start means position 1.
  A start beyond the end gives up -- with `STI` first, which is why the guard has
  to be released on every path.
  -------------------------------------------------------------------------- }
{ The `far` is gone from this header: TP6 rejects it on the implementation
  header of a routine the interface already declares (Error 36), and PlayStart
  is now declared there. The calling model comes from the interface. }
procedure PlayStart(var Song : TSong);
  { THE FRAME SETTLES BOTH OF THESE. `ENTER 8,0` at 10a1, and only three things
    can be in those eight bytes: the loop variable at [BP-2], a second Word at
    [BP-4] that nothing in the routine ever touches, and the four-byte `with`
    slot at [BP-8]/[BP-6] that 11f7..11fa fills. Declaring `i` alone would put
    the with-slot at [BP-6]/[BP-4] and give `ENTER 6,0`, so the unused Word is
    real -- and the release declares exactly `i, j : WORD` here, with `j` unused
    in this routine too. A larger frame than the locals explain is usually a
    compiler temporary; this is the other case, where it is a declaration. }
var
  i, j : Word;
begin
  asm
    CLI                                            { 10a5                    }
  end;

  PlayingSong := @Song;                            { 10a6..10b3              }

  RangeStart := ReqStart;                          { 10b4..10b9              }
  RangeEnd   := ReqEnd;                            { 10ba..10bf              }
  MySongLen   := ReqLen;                            { 10c0..10c5              }

  if MySongLen = 0 then                             { 10c6..10cc              }
    MySongLen := Song.SequenceLength;                        { 10cd..10d6              }

  if RangeStart = 0 then                           { 10d7..10dd              }
    NextSeq := 1                                   { 10de..10e5              }
  else
    NextSeq := RangeStart;                         { 10e6..10eb              }

  if NextSeq > MySongLen then                       { 10ec..10f4              }
  begin
    asm
      STI                                          { 10f5                    }
    end;
    Exit                                           { 10f6                    }
  end;

  { 10f9..1120 -- an unset END comes from the song too, but only if the song's own
    figure is set AND fits inside the length. Three tests, short-circuited. }
  if (RangeEnd = 0) and (Song.SequenceRepStart <= MySongLen) and
     (Song.SequenceRepStart <> 0) then                        { 10f9..111c              }
    RangeEnd := Song.SequenceRepStart;                        { 1117..1120              }

  { 1121..113d -- whether the module may loop.

    THE `True and` IS IN THE ORIGINAL. 1121 loads an IMMEDIATE 1 and tests it, so
    the first operand is the literal, not a variable -- a typed constant would be
    `MOV AL,[addr]` as ForceLoopMod's own test is at 112e -- so what is folded here
    is an UNTYPED Pascal constant, which becomes a literal, where a typed one stays
    a memory read. That distinction is what the immediate proves.

    AND THE GROUPING IS `(True and A) or B`, not `True and (A or B)`. The `JZ` at
    1125 lands on B's test at 112e rather than on the false path, so a failing
    first operand still tries B. Written the other way round the jump would clear
    both tests -- seven bytes against fourteen, which is how it was caught. }
  MyLoopMod := (True and (RangeEnd <> 0)) or ForceLoopMod; { 1121..113d       }

  { 113e..116e -- and reset the playing state. `TickInRow := $FE` is a sentinel:
    two short of zero, so the first two ticks pass before a row is due. }
  TickInRow  := $FE;                               { 113e..1142              }
  CurSpeed   := Song.InitialTempo;                     { 1143..114c              }
  CurTempo   := Song.InitialBPM;                     { 114d..1158              }
  TickCount  := 0;                                 { 1159..115d              }
  NextNote    := 1;                                 { 115e..1163              }
  ModFlag    := False;                             { 1164..1168              }
  MuestrasPerTick := 1;                            { 1169..116e              }

  MaxSplPerTick := MaxOutputFreq div TicksPerSecond;   { 116f..117a          }

  if RangeEnd < NextSeq then                       { 117b..1183              }
    RangeEnd := NextSeq;                           { 1184..1189              }

  { 118a..11d5 -- prime the first row and the queue that hands it on. The stores
    land on $1220, $1221, $1222, $1223 and then an 8-byte Move to $1224, which is
    NoteBuff[0]'s EoMod, Tempo, NotePlaying, SeqPlaying and Volume -- the layout
    fixed at 12ba:094b, confirming itself from a different routine. `$125c` is its
    NMuestras at +$3c. Tempo starts at 6, ProTracker's default. }
  NoteBuff[0].EoMod       := False;                { 118a..118e              }
  NoteBuff[0].Tempo       := 6;                    { 118f..1193              }
  NoteBuff[0].NotePlaying := 0;                    { 1194..1198              }
  NoteBuff[0].SeqPlaying  := 0;                    { 1199..119d              }
  NoteBuff[0].Volume := UserVols;                  { 119e..11ae  see 075e    }
  NoteBuff[0].NMuestras   := 0;                    { 11af..11b3              }

  NoteHd        := 0;                              { 11b4..11b8              }
  NoteTl        := 0;                              { 11b9..11bd              }
  NoteSound     := @NoteBuff[0];                   { 11be..11c9              }
  NoteProcessed := @NoteBuff[0];                   { 11ca..11d5              }

  { 11d6..1223 -- clear the channels, then give each one a starting note.

    THE `with` IS THE ORIGINAL'S, not a convenience. 11f7..11fa is
    `MOV [BP-8],DI / MOV [BP-6],DS` -- the register the offset was accumulated in,
    then DS -- and every field store below reloads it with `LES DI,[BP-8]`. A
    pointer local instead would need a pointer VALUE and give
    `LEA AX,[DI+123a] / MOV DX,DS / MOV [BP-8],AX / MOV [BP-6],DX`. The slot is
    the compiler's, which is why the frame has four bytes this routine never
    declares.

    AND `ADD DI,123A` IS BASE-1: the array really starts at $1260, one 38-byte
    element above the base the compiler indexes from. }
  FillChar(Canales, SizeOf(Canales), 0);           { 11d6..11e4              }

  for i := 1 to MaxChannels do                     { 11e5..11fa, 121e..1223  }
    with Canales[i] do
    begin
      Note.Period     := 800;                      { 11fd..1205              }
      Note.Instrument := 1;                        { 1206..120c              }
      Note.Command    := mcNone;                   { 120d..1214              }
      Period          := 800                       { 1215..121d              }
    end;

  { 1224..122e -- and size a buffer. `SHL AX,3 / SHL AX,1` is `* MaxChannels * 2`
    with MaxChannels folded to 8; the compiler reaches for shifts because both
    factors are powers of two, and the PAIR of them is what fixes the 8. }
  SizeOfABuffer := MaxSplPerTick * MaxChannels * 2;   { 1224..122e            }

  FillChar(Buffers, SizeOf(Buffers), 0);           { 122f..123c              }

  { 123d..1298 -- claim the mixing buffers, but only when the GUS is not driving.
    The GUS plays out of its own on-card memory and never asks for one.

    THE FILL VALUE IS 0 AND THE RELEASE'S IS $7F. Both are silence for their own
    sample format -- $7F is mid-scale for unsigned 8-bit, 0 for signed 16-bit --
    so this is 1.31 filling a Word buffer where 1.39b fills a byte one. The
    immediate at 1292 is `6A 00`; there is nothing to interpret. }
  if not UsingGUS then                           { 123d..1243              }
    for i := 1 to NumBuffers do                    { 1244..124d, 1299..129e  }
    begin
      { 124e..1265 -- a VIRTUAL call on the heap object at DS:$39ae, through
        `[DI+8]`, which is virtual method number two. See HEAPS.PAS, which is a
        stub for segment 17cf and exists to put HGetMem in that slot.

        `ADD DI,1390` is base-1 AND field-folded: $1394 - 11 + 7 is $1390, so the
        one expression carries the array's base and `IData`'s offset inside the
        record together. }
      FullHeap.HGetMem(Buffers[i].IData, SizeOfABuffer);   { 124e..1265       }

      if Buffers[i].IData = nil then               { 1266..1273              }
      begin
        Song.Status := msOutOfMemory;              { 1274..127b              }
        PlayStop;                                  { 127c..127f              }
        asm
          STI                                      { 1280                    }
        end;
        Exit                                       { 1281                    }
      end;

      FillChar(Buffers[i].IData^, SizeOfABuffer, 0)      { 1284..1298        }
    end;

  BuffIdx  := 1;                                   { 129f..12a4              }
  BuffGive := 1;                                   { 12a5..12aa              }

  { 12ab..12c8 -- and clear both per-channel tables. The EventRing clear is
    1.31's own; the release only clears RawChannels here. }
  FillChar(EventRing, SizeOf(EventRing), 0);       { 12ab..12b9              }
  FillChar(RawChannels, SizeOf(RawChannels), 0);   { 12ba..12c8              }

  { 12c9..12d0 -- program the hardware for the rate that was asked for, and only
    then let the timer back in. Everything above this point runs under the `CLI`
    from 10a5. }
  ChangeSamplingRate(DesiredHz);                   { 12c9..12d0              }

  asm
    STI                                            { 12d1                    }
  end;

  { 12d2..132a -- hand the device a buffer source and start it.

    THE ASKER IS SWAPPED TWICE ON PURPOSE. `IdleGiver` returns nil, so while the
    device is starting up it is told there is nothing to play; `BufferGiver` at
    1313 is the real one, installed once `StartSampling` has returned. In between,
    `DontExecute` blocks the tick handler on the GUS path -- which is the path
    where the device starts producing immediately.

    AND THE RELEASE'S PRIMING LOOP IS NOT HERE. 1.39b runs
    `IF NOT UsingGUS THEN FOR i := 1 TO NumBuffers DO ProcessTickEntry` between
    the asker and the GUS test; 12ba goes straight from 12de to 12df. With one
    buffer there is nothing to prime. }
  SetBufferAsker(IdleGiver);                       { 12d2..12de              }

  if UsingGUS then                               { 12df..12e5              }
    DontExecute := True;                           { 12e6..12ea              }

  MyCanFallBack := False;                          { 12eb..12ef              }
  Playing       := True;                           { 12f0..12f4              }

  if UsingGUS then                               { 12f5..12fb              }
    SetGusChannels(Song.NumChannels);                    { 12fc..1308              }

  StartSampling;                                   { 1309..130d              }
  DontExecute := False;                            { 130e..1312              }

  SetBufferAsker(BufferGiver);                     { 1313..131f              }

  PleaseFallback := 0;                             { 1320..1324              }
  MyCanFallBack  := CanFallBack                    { 1325..132a              }
end;

{ --------------------------------------------------------------------------
  12ba:132f -- ask the device for a rate it can really manage, and if what comes
  back is unusable, ask again for a different one.

  THE `goto` IS THE ORIGINAL'S AND SO IS THE LABEL'S POSITION. 1357 and 1364 both
  jump BACKWARDS to 1333, which is the first statement of the body -- not to the
  test above them -- so this is a retry loop written as two `goto`s, and the
  release writes it exactly that way with the label spelled `Otra`. A `repeat`
  would put its test at the bottom and could not express two different
  adjustments; a `while` would need a flag. Read the jump target: it is what says
  the label is above `DesiredHz := Hz` rather than beside either test.

  IT WALKS THE RATE IN STEPS OF 100 Hz, down when the device offers more than a
  tick can carry and up when it offers less than 1000, and it re-asks after every
  step. Nothing bounds the loop except the device eventually answering inside the
  window.

  1.31 DOES MORE THAN THE RELEASE HERE. 1.39b stops after SetPeriodicProc; from
  138e this one also sizes the DMA buffer and reprograms the 8237. The `JZ` at
  136d lands on the epilogue at 13d3, so ALL of it is inside the
  `MyHz <> ActualHz` test -- the DMA is only touched when the rate actually
  changed.
  -------------------------------------------------------------------------- }
procedure ChangeSamplingRate(Hz : Word);
label
  Otra;
var
  MyHz : Word;                    { [BP-2], and the whole of `ENTER 2,0`       }
begin
Otra:
  DesiredHz := Hz;                                 { 1333..1338              }
  MyHz := TGetFreqProc(ActiveDevice^.GetRealFreqProc)(Hz);  { 1339..1346      }

  { 1347..1352 -- more samples per second than a tick can hold. The product is
    computed into AX and compared against MyHz, which is why it reads as the
    right-hand side here. }
  if MyHz > MaxSplPerTick * TicksPerSecond then     { 1347..1352             }
  begin
    Dec(Hz, 100);                                  { 1353..1356              }
    goto Otra                                      { 1357..1358              }
  end;

  if MyHz < 1000 then                              { 1359..135f              }
  begin
    Inc(Hz, 100);                                  { 1360..1363              }
    goto Otra                                      { 1364..1365              }
  end;

  if MyHz <> ActualHz then                         { 1366..136e              }
  begin
    ActualHz := MyHz;                              { 136f..1374              }

    { 1375..138d -- `MOV SI,AX / SHL AX,1 / ADD AX,SI / SHR AX,1` is
      `TicksPerSecond * 3 div 2` and nothing else: AX becomes T, 2T, 3T, then 3T
      div 2. The release's line carries two commented-out alternative divisors
      beside it, an 8 and a DIV 3, so the ratio was tuned by hand; 1.31's shifts
      fix it at three halves. }
    SetPeriodicProc(ProcessTickEntry, TicksPerSecond * 3 div 2);  { 1375..138d }

    { 138e..13ad -- and size the DMA buffer from the rate. Stereo gets the whole
      figure and mono half of it, then the result is rounded DOWN to a multiple of
      four by `AND AX,FFFC` -- four bytes being one stereo 16-bit frame, which is
      the smallest unit the 8237 may stop on. }
    if Stereo then                                 { 138e..1394              }
      DMABufferSize := ActualHz                    { 1395..139c              }
    else
      DMABufferSize := ActualHz div 2;             { 139d..13a4              }

    DMABufferSize := DMABufferSize and $FFFC;      { 13a5..13ad              }

    { 13ae..13cc -- reprogram the controller, unless there is no channel to
      program. `$FF` IS THE "NO DMA" SENTINEL, and it is compared as a WORD
      (`81 3E C4 0B FF 00`, six bytes) rather than a byte, which is what settles
      DMAChannel's width -- see the note beside its declaration in SOUNDDEV.

      Mode $58 is single-mode, address-increment, auto-initialise, read (the
      8237 reading memory to feed the card), which is what a continuously
      circling playback buffer needs. }
    if DMAChannel <> $FF then                      { 13ae..13b5              }
      DMASet(DMAChannel, $58, DMABuffer, DMABufferSize);   { 13b6..13cc       }

    { 13cd..13d2 -- and resynchronise the tick gate, because the rate the mixer
      is paced against has just moved. `Ticks` is VTSilenc's and exported;
      TickSnapshot is the copy SeqTick compares it with at 0c52. }
    TickSnapshot := Ticks                          { 13cd..13d2              }
  end
end;

{ --------------------------------------------------------------------------
  12ba:13d7 -- stop playing and give the mixing buffers back.

  PlayStart's mirror image, and shorter than the release's by one statement and
  one local. 1.39b saves `UsingGUS` into a Boolean, calls `EndSampling`, and then
  tests the SAVED copy -- which is the careful order, because EndSampling can
  change it. 1.31 has neither: `ENTER 2,0` leaves room for the loop variable
  alone, and 13ed tests `UsingGUS` straight out of DGROUP with no call between
  it and the decision. The tear-down of the device itself happens elsewhere.

  `[DI+0c]` IS HFreeMem, the third virtual, one slot past the HGetMem PlayStart
  calls. See HEAPS.PAS.
  -------------------------------------------------------------------------- }
procedure PlayStop;
var
  i : Word;                       { [BP-2], and the whole of `ENTER 2,0`       }
begin
  Playing := False;                                { 13db..13df              }

  { The idle asker returns nil, so anything still asking for a buffer while this
    unwinds is told there is nothing to play. }
  SetBufferAsker(IdleGiver);                       { 13e0..13ec              }

  if not UsingGUS then                           { 13ed..13f3              }
    for i := 1 to NumBuffers do                    { 13f4..13fd, 1416..141b  }
      FullHeap.HFreeMem(Buffers[i].IData, SizeOfABuffer)   { 13fe..1415      }
end;

{ --------------------------------------------------------------------------
  12ba:141e -- THE UNIT'S INITIALISATION SECTION, not a procedure.

  `PUSH BP / MOV BP,SP` rather than `ENTER`, no parameters, `RETF` with no count,
  and Turbo Pascal emits a unit's `BEGIN ... END.` block as the last Pascal code
  in the segment -- which this is, with only the object module's kernel at 1600
  after it. The same shape was mistaken for an exported `Register` procedure in
  DEVGUS once, and cost that unit 26 bytes of code the original has not got.

  It is the release's block plus two more FillChars: 1.39b clears UserVols,
  Permisos and SplBuf, and 1.31 clears both event rings as well.

  `PUSH -1` at 144c IS 255. FillChar's value is a byte, and $FF as a sign-extended
  byte immediate is `6A FF`; writing 255 is what produces it.
  -------------------------------------------------------------------------- }
begin
  Playing   := False;                              { 1421..1425              }
  LoopMod   := False;                              { 1426..142a              }
  ActualHz  := 0;                                  { 142b..142f              }

  if FilterIsOn then                               { 1430..1436              }
    FilterVal := FilterOn                          { 1437..143e              }
  else
    FilterVal := FilterOff;                        { 143f..1444              }

  { Every voice at full volume, every channel permitted, no filter history. }
  FillChar(UserVols, SizeOf(UserVols), 255);       { 1445..1452              }
  FillChar(Permisos, SizeOf(Permisos), True);      { 1453..1460              }
  FillChar(SplBuf,   SizeOf(SplBuf),   0);         { 1461..146e              }

  FillChar(EventRing, SizeOf(EventRing), 0);       { 146f..147d              }
  FillChar(NoteRing,  SizeOf(NoteRing),  0)        { 147e..148c              }
end.
