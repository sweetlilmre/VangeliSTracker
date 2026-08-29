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
  SongUnit, SongElements, SoundDevices, VTCtrl, GUS, ModCommands, Filters,
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
const
  { **SIXTEEN IN v1.51, EIGHT IN 1.31b, AND `TPlayingNote`'s SIZE IS THE PROOF.**
    12ce:07e9 is `IMUL DI,[02fc],77h` where 1.31b has `IMUL DI,..,3Fh`, and 0807
    pushes `6A 77` where 1.31b pushes `6A 3F` -- so the record is 119 bytes against
    63. 1.39b's field list makes that arithmetic decisive: four fixed bytes, then
    `Volume : TVolumes` which is one byte a channel, then `Note` which is a 6-byte
    TFullNote a channel, then a Word and a filler. 119 - 7 is 112, and 112 divided by
    seven is 16. No other channel count gives 119.

    SIXTEEN AND NOT THE RELEASE'S THIRTY-TWO. 1.39b's SOUNDDEV says
    `MaxChannels = 32`; DemoVT 1.51 went half way. It agrees with the GUS event row,
    which is also sixteen, and it does NOT agree with the wide note ring, which is
    thirty-two -- so the published row can describe more channels than the player can
    sound. Three different widths live in this build at once and each one is
    measured separately. }
  MaxChannels = 16;

type
  { THE RELEASE'S NAMED TYPE, AND IT IS LOAD-BEARING. Turbo Pascal only allows a
    whole-array assignment between operands of the SAME named type, and 12ba:075e and
    12ba:119e are assignments rather than `Move` calls -- see the note at each. Declared
    as two anonymous `array[1..8] of Byte` the assignment does not compile at all, which
    is why both sites were read as `Move`. Eight is written out rather than `MaxChannels`
    because that constant is declared further down, after the records that use it. }
  TVolumes = array[1..MaxChannels] of Byte;

  PRingEntry = ^TRingEntry;
  { **THE TWO FIELDS ARE A SEMAPHORE NUMBER AND A PENDING FLAG**, and they were
    `Chan`/`Note` until DEMOVT.DOC named what they feed. Command 8's parameter
    selects one of 256 semaphores; this carries it from the pattern row to
    12ba:0187, which increments `CtrlBlock.Semaphores[Sem]`. Nothing here is a
    channel -- `Chan` indexing a 256-entry array should have been the tell. }
  TRingEntry = record
    Sem     : Byte;             { +$00  which semaphore command 8 asked for  }
    Pending : Byte;             { +$01  nonzero means the entry is live      }
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
    Note        : array[1..MaxChannels] of TFullNote;   { +$14 in v1.51      }
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
  { EIGHTEEN BYTES IN v1.51, SIXTEEN IN 1.31b, AND `Freq` IS WHERE THE TWO WENT.
    12ce:02de is `IMUL AX,AX,12h` where 1.31b has `SHL AX,4`, so the record is 18;
    and 12ce:0305/0309 store a WORD PAIR into +$1 and +$3 from [BP+12] and [BP+14],
    which is a LongInt where 1.31b stored one word. Every field after it moves up
    two, and FlushEventRow's "is this slot free" test at 12ce:0413 is
    `MOV AX,ES:[DI+1] / OR AX,ES:[DI+3]` -- a 32-bit zero test, which it could not
    have been while Freq was a Word.

    IT ALSO REMOVES A WIDENING. 1.31b's flush had to `XOR DX,DX` before passing Freq
    to TriggerVoice, which takes a LongInt; 12ce:043e pushes +$3 and +$1 straight
    through. The ring now carries what the driver wants. }
  TGusEvent = record
    Vol    : Byte;              { +$00                                       }
    Freq   : LongInt;           { +$01  a Word in 1.31b                      }
    Pan    : Byte;              { +$05                                       }
    StartA : LongInt;           { +$06                                       }
    LoopA  : LongInt;           { +$0a                                       }
    EndA   : LongInt;           { +$0e  the flush tests this for the long form }
  end;
const
  { The GUS event ring's width. 12ce:02e1 multiplies the row index by $120, and $120
    divided by the 18-byte event is 16 -- the same number `MaxChannels` turned out to
    be, and kept separate because the two were measured from different instructions
    and nothing says the author had to keep them equal. }
  GusVoices = 16;

type
  { SIXTEEN VOICES IN v1.51 AND EIGHT IN 1.31b. 12ce:02e1 multiplies the row index
    by $120 -- 288, which is 16 x 18 -- and FlushEventRow's loop closes on
    `CMP [02f8],0Fh`, so the last voice is 15. }
  TGusEventRow = array[0..GusVoices - 1] of TGusEvent;   { 288 bytes            }

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

  { NEW IN v1.51. 12ce:0243's `SHL DI,5` fixes the flag grid at 32 bytes a row and
    12ce:0258 stops the loop at 20h, so the wide ring carries thirty-two channels
    where `MaxChannels` below still says eight. Both numbers are live at once: the
    8-channel ring at 0183 and the 32-channel one at 0202 run back to back. }
  WideChans = 32;



  { The release's names for both. `MaxChannels` is 8 here and not 32 as 1.39b has
    it -- every base-1 array in this segment is eight elements long and
    `TPlayingNote` is 63 bytes rather than the release's 32 for exactly that
    reason. It is used as a MULTIPLIER at 12ba:1224, where `MaxSplPerTick *
    MaxChannels * 2` folds to `SHL AX,3 / SHL AX,1`; a different value would give
    a different pair of shifts, so the byte confirms the 8.

    `NumBuffers` is 1, against the release's 3 -- see the note beside Buffers. }
  NumBuffers  = 1;

{ **THE CHANNEL FLAGS, AND FOUR OF THE SEVEN EXIST ONLY BECAUSE OF 64K.** A
  real-mode segment addresses 65,536 bytes and a sample may be longer, so a long
  sample is held in two blocks and every position in it needs to say which block
  it means. That is what rcfLongSample, rcfPlaying2nd, rcfLongLoopLen and
  rcfLongLoopEnd are between them: one says the sample is split at all, one says
  which half is playing now, and two say that a loop bound landed in the second
  half rather than the first.

  Take away the 64K limit and four of these seven disappear. They are not
  describing the music; they are describing the address space. }
  rcfLongSample     = $01;      { over 65,520 bytes, so it is in two parts   }
  rcfActiveChannel  = $02;      { allowed to sound                           }
  rcfDoesLoop       = $04;      { the sample repeats rather than ending      }
  rcfPlaying2nd     = $08;      { the position is in the SECOND block        }
  rcfLongLoopLen    = $10;      { the loop length crosses into the second    }
  rcfLongLoopEnd    = $20;      { and so does its end point                  }
  rcfSampleFinished = $40;      { ran off the end; the channel is silent
                                  until something retriggers it              }

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
  PlayingSong      : PSong         = nil;
  LoopMod          : Boolean       = True;     { DS:$02ce  nothing reads it     }
  ForceLoopMod     : Boolean       = False;    { DS:$02cf  the ForceLoopMod key }
  CanFallBack      : Boolean       = True;     { DS:$02d0  12ba:1325 reads it   }
  FilterOn         : TFilterMethod = fmNone;   { DS:$02d1  the FilterOn key     }
  FilterOff        : TFilterMethod = fmNone;   { DS:$02d2  the FilterOff key    }

  {**NOT** ModCommands' `FilterIsOn`, which is a different variable at
    DS:$0348. 1.31 has two of them; so, it turns out, does the release, which declares
    one in each of the same two interfaces -- this file used to say the release had
    only one, and that was wrong. Both are exported here because the ADDRESS requires
    it: $02d3 sits between two interface globals, and a unit's implementation
    declarations all come after its interface ones, so a private declaration cannot
    land there.

    THE ADDRESS IN THAT ARGUMENT WAS $02cd UNTIL THE LINKER WAS ASKED. It is $02d3 --
    `MaxOutputFreq` is the next declaration and the map puts it at $02d4, one byte
    on. The reasoning was right and the number it was built on was v1.31b's, which
    is the whole hazard: prose that argues FROM an address reads as corroboration
    for it. The shadowing hazard the old note worried about is handled where it
    actually bites -- VTCFG writes ModCommands' and now says so by qualifying it. }
  FilterIsOn       : Boolean       = False;

  MaxOutputFreq    : Word          = 44000;    { DS:$02d4  ab e0; release 45000 }
  DontExecute      : Boolean       = False;
  AltMode          : Boolean       = False;    { DS:$02d7  1.31 only            }
  Playing          : Boolean       = False;
  ModTickProcValid : Boolean       = False;
  NoteTl           : Word          = 0;
  NoteHd           : Word          = 0;
  NoteSound        : PPlayingNote  = nil;
  NoteProcessed    : PPlayingNote  = nil;
  MaxSplPerTick    : Word          = 880;      { DS:$02e6  03 70, the release's }

  {EIGHT PAN POSITIONS, one per channel, and this unit already had them
    under this name. What it did not have was their VALUES or their BOUNDS.

    **THE BOUNDS WERE THE BASE-1 TRAP, and this file already records the rule under a
    different array.** It was `array[0..8] of Byte` with its address given as $02e1,
    and $02e1 is not where it starts -- it is the BASE-1 BASE, the number the compiler
    subtracts so that `Pannings[Chan]` with Chan running 1..8 reaches $02e2..$02e9.
    The image settles it: $02e0 holds `03 70`, MaxSplPerTick, so $02e1 is that Word's
    high byte and cannot be the array's first element. Declared `array[1..8]` at $02e2
    the displacement is identical -- `[$02e2 - 1 + Chan]` is `[$02e1 + Chan]` -- which
    is why nine bytes where there are eight was invisible to `verify.py`. Exactly the
    mistake recorded for `RawChannels`: "$13A6 IS THE BASE-1 BASE, not the address".

    $40 and $b0 are a third of the way in from each side, in the pattern
    L R R L L R R L, which is the Amiga's own channel assignment. The release keeps pan
    in the SONG (`PanPositions`, initialised from its `DefPan`) and 1.31 keeps it in
    the player -- which is why `InitValues` in 14b9 has no trace of the release's last
    statement, a thing this project had already found from the other end. }
  { ~~Pannings~~ **IS GONE IN v1.51, AND THE PREVIOUS COMMIT'S GUESS NEVER HAD TO BE
    RESOLVED.** Last time round this array needed sixteen entries where only eight
    were measured, and the second eight went in as the Amiga L R R L pattern repeated
    with a note saying it was a guess. It is not needed: the original's DGROUP has
    `00 00 01 00` at $02e8 where ours had the table, and MODCOMMANDS' block starts 20
    bytes lower than ours -- sixteen of which are exactly this.

    NOTHING REFERENCES IT ANY MORE. All three readers moved to
    `PlayingSong^.ChannelPan` over the last few commits -- SetNewSample's two
    SetEvent calls and both PostEvent calls -- so the declaration was the only thing
    keeping it alive, and Turbo Pascal emits a typed constant whether or not anything
    reads it. **A dead typed constant is invisible to every code comparison and
    sixteen bytes wide in the layout.**

    THE VALUES ARE KEPT IN THIS NOTE because they are 1.31b's and measured: $40, $b0,
    $b0, $40, $40, $b0, $b0, $40 -- a third of the way in from each side, in the
    L R R L L R R L pattern the Amiga uses. 1.51 gets the same effect from the song's
    own per-channel pan, which is where the release always had it. }

  { **THE ORDER OF THIS RUN IS MEASURED, AND IT IS NOT 1.31b's.** Every address below
    is named by an instruction in 12ce, and the declaration order is the only thing
    that can put them there -- a typed constant lands where the ones before it leave
    off. 1.31b runs Rest, EventSlot, EventChan, then the ring pair; 1.51 puts the ring
    pair FIRST, moves the wide ring's three in ahead of RingVoice, and leaves
    RingVoice where FlushEventRow's loop names it.

    THE INITIALISER ON FlushSlot IS WHY THIS WAS NOTICED. Setting it to 1 changed no
    byte of the image, because the declaration sat at the wrong address -- `dgroup.py`
    went from 164 blocks in place to 163 and one MOVED, which is the only reading
    that says "right content, wrong place". }
  RingSlot         : Word          = 0;        { DS:$02e8  the PRODUCER's cursor }

  { **IT STARTS AT ONE, NOT ZERO,** and two independent places say so: DGROUP holds
    `01 00` at $02ea in the original's initialised image, and 1000:02b0 sets it again
    at run time with `MOV word [02ea],1` beside `RingSlot := 0`. One slot of daylight
    between producer and consumer is what stops the full test firing on the first
    tick. }
  FlushSlot        : Word          = 1;        { DS:$02ea  the CONSUMER's        }

  Rest             : Word          = 0;
  EventSlot        : Word          = 0;        { DS:$02ee  AdvanceEventRow's    }
  EventChan        : Word          = 0;

  { NEW IN v1.51 -- the wide ring's own three, named by 12ce:0206, 023c and 02cd. }
  WideSlot         : Word          = 0;
  WideChan         : Word          = 0;
  WidePrev         : Word          = 0;

  RingVoice        : Word          = 0;        { DS:$02f8  FlushEventRow's loop }
  NewFlags         : Byte          = 0;
  NoLoop           : Byte          = 0;
  NextIdx          : Word          = 0;
  ChanIdx          : Word          = 0;

  { DS:$02fa, six bytes. The initialiser names the FIRST variant's fields, which is
    the only form Turbo Pascal accepts for a variant record's typed constant --
    Instrument, Period, Volume, Command, Parameter is 1 + 2 + 1 + 1 + 1, and $02fa + 6
    is $0300, which is CurCanal. }
  NewNote          : TFullNote     = (Instrument : 0; Period : 0; Volume : 0;
                                      Command    : mcNone; Parameter : 0);
  CurCanal         : PCanal        = nil;
  Pattern          : PPattern      = nil;      { DS:$030a in v1.51             }

  { NEW IN v1.51, DS:$030e -- and it is the release's, carried since 1993. 1.39b
    declares `NewSample : BOOLEAN = FALSE` among ProcessNewNote's own typed
    constants and uses it for exactly one thing: to know, after CommandStart has
    run, whether this row started a sample that a 9xx could still be moved. }
  NewSample        : Boolean       = False;

  { **`FirstTick`, AND THE RELEASE NEVER READS IT EITHER.** This was the only non-zero
    unknown left -- a Word holding 1 that nothing in the transcribed tree touches --
    and 1.39b names it: `FirstTick : BOOLEAN = TRUE`, the first of FillChannels' own
    typed constants, declared at LIB/PLAYMOD.PAS:954 and read at NO line in that file.
    The one apparent use, `Song.FirstTick` at 1072, is the song object's field and a
    different thing entirely.

    SO THE PUZZLE WAS NEVER "WHAT READS THIS" -- nothing does, in either version, and
    a typed constant is emitted whether or not it is read. What identified it was the
    ORDER: five of FillChannels' constants in a row, in the release's declaration
    order, and this is the first of them.

    THE WIDTH IS OURS AND THE RELEASE'S IS A BOOLEAN. Two bytes here hold `01 00`
    where a Boolean would hold `01`, and the DGROUP layout check covers this address,
    so v1.51 really does spend two bytes. Whether it widened the constant or pads
    after it cannot be told apart with no reader, and the note says so rather than
    picking. }
  FirstTick        : Word          = 1;

  MixChan          : Word          = 0;
  ChanRec          : PModRawChan   = nil;
  OutPtr           : Pointer       = nil;
  ModRec           : PSampleBuffer = nil;
  { **THE WHOLE OF ProcessTick's CONSTANT BLOCK IS HERE, IN THE RELEASE'S ORDER**,
    and matching it end to end is what named the four unknowns in this run. 1.39b's
    LIB/PLAYMOD.PAS:1024 declares, after an untyped SizeOf:

        incr : INTEGER   OTempoCt : WORD   Can : PCanal   Raw : PModRawChan
        NoteHzFreq : LONGINT   i : WORD   j : WORD   t : WORD   step : LONGINT
        FBCount : WORD   NumChannels : BYTE

    Every width matches ours, in sequence, with no slack -- and FOUR OF THEM ARE
    DEAD IN THE RELEASE TOO. `incr`, `NoteHzFreq`, `FBCount` and `j` occur exactly
    once each in the whole of 1.39b's PlayMod: their own declarations. They are
    leftovers of an earlier ProcessTick, and they were leftovers in 1993.

    THAT IS WHY NO AMOUNT OF READING THIS IMAGE COULD NAME THEM. A variable nothing
    reads has no witness in the code, and these have none in either version. The
    sequence is the only evidence there is, and it is enough because it is exact. }
  Incr             : Integer       = 0;        { the release's `incr`, unread    }
  PrevTick         : Word          = 0;        { the release's `OTempoCt`        }

  CanalPtr         : PCanal        = nil;
  RawPtr           : PModRawChan   = nil;
  NoteHzFreq       : LongInt       = 0;        { unread here and in 1.39b       }
  { **DS:$0330 IN v1.51, AND IT DOES TWO JOBS** -- which the layout is what forced.
    A separate `TickSpan` was declared for the tempo loop's span last commit and it
    put this unit's block four bytes over; the original has only six bytes between
    `NoteHzFreq` and `StepVal`, not eight. The same address serves both: 12ce:0f2f stores
    the span into [0330] and 12ce:11b1 reads [0330] as the channel index in the
    volume pass. The first use is finished before the second begins.

    THAT IS THE THIRD TIME THIS UNIT REUSES ONE GLOBAL FOR TWO ROLES -- the notes at
    $02f6 and $0328 record the other two, both found the same way. It is the
    release's habit, not an accident, and it is why neutral names are right here. }
  TmpVal           : Word          = 0;        { DS:$0330 in v1.51  TWO JOBS    }
  { The release's `j`, the second of ProcessTick's two Word indices -- `TmpVal` above
    is its `i`. Neither version reads it, so there is no role to name it for and it
    keeps a name that claims only what the sequence shows. }
  UnusedIdx        : Word          = 0;

  { 1.39b's `t`, the tempo loop's counter. It IS its own variable -- 12ce:0f45's
    `DEC word [0334]` and 0fa5's `CMP [0334],1` are two bytes the span's address
    cannot account for. }
  TickIter         : Word          = 0;
  { A LONGINT IN v1.51, A WORD IN 1.31b, AND THE ZERO STORE IS WHAT SETTLES IT.
    12ce:11a5 is `MOV word [0336],1000 / MOV word [0338],0` -- two immediate stores.
    Written as two separate Word variables the second would be `XOR AX,AX /
    MOV [x],AX`, because Turbo Pascal special-cases assigning zero and five bytes
    beat six; it only emits the immediate form for BOTH halves when they are one
    32-bit assignment. Our build proved that by emitting the XOR when it was tried
    the other way.

    AND THE SHIFTS BELOW ARE CAST BACK DOWN. 121d and 122b are `SHL AX,4` and
    `SHR AX,0Ch` on the low word alone; a LongInt shift would be an RTL call, so the
    source has to narrow it first. }
  StepVal          : LongInt       = 0;        { DS:$0336 in v1.51              }
  { A WORD IN v1.51 WHERE 1.31b HAS A LONGINT, and the two ends pinned it before the
    release confirmed it: StepVal occupies four bytes and TickChans follows two later,
    not four. 1.39b calls it `FBCount` -- a fall-back counter, beside `CanFallBack`
    and `FBTicks` elsewhere in the unit -- and never reads it. }
  FBCount          : Word          = 0;
  TickChans        : Byte          = 0;

{ THE OLD SCATTERED NOTES FOLLOW, kept for their content only --
  the declarations they described are in the block above.
the release's `CanFallBack`, "TRUE if fall-back is allowed", and a
  TYPED constant there as it must be here: 12ba:1325 reads it with `MOV AL,[02ca]`
  and an untyped constant would have folded to an immediate. It is the client's
  standing permission; `MyCanFallBack` at $121e is the working copy PlayStart
  clears while it is setting up and restores on the way out. }
{the release's `LoopMod`, "TRUE if music CAN be played forever", and
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
      MaxOutputFreq  $02d4   the `MaxFreq` key
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

  {EXPORTED, because `1000:0311` fills it: the program does
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
  this file already records the rule: `$11ee` is SplBuf's, `$12E0` UserVols', `$12e0`
  Permisos', `$1260` Canales' and `$13A6` RawChannels'. An instruction naming one of
  those is indexing the array, not touching the byte.

  Only the first five need to be visible: `UserVols` because 1000:0311 fills it, and the
  four above it because they have to precede it. The rest follow in the implementation,
  which keeps them private without moving them -- a unit's implementation variables come
  after all of its interface ones, so the order is preserved either way.
  ========================================================================== }
var
  { **THE THIRD LITERAL EIGHT IN THIS FILE, AND THE LAYOUT IS WHAT FOUND IT.**
    1.39b declares this `ARRAY[1..MaxChannels] OF WORD` and so does the original;
    written as `array[1..8]` it is sixteen bytes where the original has thirty-two,
    and every PLAYMOD variable after it -- and every unit's block after PLAYMOD --
    sits sixteen bytes low. Our UserVols came out at $12D0 against the original's
    $12E0, measured from the linker map.

    NO INSTRUCTION COULD HAVE CAUGHT IT. An indexed read with range checking off
    emits the same bytes whatever the declared bound is, so this unit compared
    identical while its data was short. See `constant-only-half-applied` and
    `dead-data-has-no-witness` in the kit. }
  SplBuf          : array[1..MaxChannels] of Word;
  ActualHz        : Word;
  NoteHz          : Word;
  NoteCalcVal     : LongInt;
  UserVols        : TVolumes;             { DS:$12E0  base-1 base $1207 }

{negotiate the rate, size the buffers, program the DMA. Declared
  here because 12ba:0d4e calls it and it lives 1,500 bytes further down the
  segment; the release exports it too, as `PROCEDURE ChangeSamplingRate(Hz:
  WORD)`. Its body is a PLACEHOLDER until the transcription reaches 132f. }
procedure ChangeSamplingRate(Hz : Word); far;

{the release exports this too. }
{ ~~NEW IN v1.51: AdvanceEventRow IS EXPORTED~~ **WITHDRAWN. IT IS
  `FlushEventRow`, AND THE EVIDENCE WAS RIGHT WHILE THE NAME WAS WRONG.**

  The note said "v1.51's ends `LEAVE / RETF` at 12ce:04b9, and DEVGUS's interrupt
  handler calls it at 106e:0019 as `CALLF 12ce:03d9`". Both facts hold. What does
  not is that 03d9..04b9 is AdvanceEventRow: 03d9 is `ENTER 4,0 / CLD /
  INC [02ea]`, then `IMUL DI,[02ea],0120` into a ring at $29fa, and it walks the
  row calling two FAR routines in 1a?? before FillChar-ing the row -- that is
  `FlushEventRow`, instruction for instruction. AdvanceEventRow is still at 0183
  and still ends `LEAVE / RET` at 0201, near, exactly as 1.31b has it.

  **NOTHING IN DEVGUS COULD HAVE CAUGHT THIS.** The call is `9A` plus a segment
  fixup and an offset the linker supplies, so DEVGUS assembles to the same bytes
  whichever PlayMod routine the name resolves to, and it verified byte-exact under
  the wrong one. The same shape as SOUNDDEV's unlinked fixups and MODCOMMA's
  shadowed `mcLast`: a cross-unit reference that only the CALLEE's own bytes can
  check. Look at what is AT the address, not at what you expected to be. }
procedure FlushEventRow; far;

procedure ProcessTickEntry; far;

{stop playing and give the buffers back. Declared here because
  12ba:127c calls it from inside PlayStart's out-of-memory path, 1,300 bytes
  above it; the release exports it too, as `PROCEDURE PlayStop`. Its body is a
  PLACEHOLDER until the transcription reaches 13d7. }
procedure PlayStop; far;

{start playing a module. EXPORTED BECAUSE 1000 CALLS IT:
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


  { ~~ONE cursor, shared~~ -- **v1.51 SPLITS IT, AND ADDS THE FULL TEST THAT GOES
    WITH A REAL RING.** 1.31b had SetEvent, PostEvent and FlushEventRow all indexing
    by DS:$02f0. In 1.51 the two producers use $02e8 and the flush uses $02ea, and
    12ce:0e78 is what makes the pair mean something:

        MOV AX,[02e8] / INC AX / XOR DX,DX / MOV CX,19 / DIV CX / XCHG AX,DX
        CMP AX,[02ea] / JNZ advance / JMP away

    which is `if (RingSlot + 1) mod RingRows = FlushSlot then` -- the producer
    refusing to advance onto the row the consumer has not drained. A `mod` by a
    non-power-of-two is a DIV, which is why the sequence is six instructions for one
    expression.

    The 1.31b note said the shared cursor "is why neither producer needs a cursor of
    its own". That was true of 1.31b and is the thing 1.51 changed. }

  {`Raw.Flags` UNDER CONSTRUCTION, and the bit values are what say
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
  {AND THIS IS NOT ModCommands' `FilterIsOn`, which is at DS:$0348.
    142f:04da writes that one from the E0x command and nothing reads it; this one is
    read by the initialisation section at 12ba:1430 to choose between FilterOn and
    FilterOff. Two variables where the release has one. ModCommands keeps its copy in
    its IMPLEMENTATION section precisely so that this name cannot be shadowed here --
    if both were exported, every reference in this unit would silently bind to this
    one and no byte comparison could see it. }

  {the release's `MaxOutputFreq`, whose comment is "Maximum frequency
    of the output sound. Less means less memory for buffers." Divided by the tick
    rate at 12ba:1174 it gives exactly MaxSplPerTick, which is that sentence. }

  {THE FOURTH DUPLICATED GLOBAL. VTMAIN owns it as `Snapshot` and
    12ba compares it against `VTSilenc.Ticks` at DS:$0bc8, which IS exported and
    is used from here directly. So one of the pair resolves cleanly and the other
    does not, in the same comparison. Risk 1 again. }

  { DS:$034e IS A TICK COUNTER WITHIN THE ROW, not the row number, and
    docs/04-units.md has it as "the current row". 12ba:0cdf compares it against
    `NoteProcessed^.Tempo` -- the release's "number of ticks the note will last"
    -- and 12ba:0cf7 resets it to zero when the pattern advances. A row number
    would be compared against a pattern length and would not reset. }

  {the release's `MyCanFallBack`, "actual permission to fall back",
    and the use fits exactly: with permission withheld, SoundDevices' request to
    fall back to a lower rate is simply cleared. }
  {ONE GLOBAL, TWO JOBS, like DS:$02f6 before it. At 12ba:0d14 it
    holds a candidate sample rate while the driver is negotiated; from 12ba:0da1
    it is the control variable of a loop over the channels. The name is neutral
    because neither role owns it. }


type
  { For calling the driver record's +$26 through its Pointer field, the way
    SOUNDDEV already does with `TInitDevProc`. That one is a procedure; this one
    returns the rate the device settled on, which 12ba:0d44 stores. }
  { ~~TChanData AND TChansData ARE DECLARED HERE~~ -- they are VTCtrl's now, because
    the published row and this ring have to be one type for the copies below to be
    ASSIGNMENTS rather than Move calls. See the declaration there. }


  TGetFreqProc = function(Hz : Word) : Word;

  { The release's own type, and 12ba:1032 confirms both arguments: the song by
    reference and a Boolean, computed there as `TickInRow = 0` -- so the flag
    means "this is the row's first tick". }
  TTickProc = procedure(var Song : TSong; Note : Boolean);

{ ...and the rest, private but in the same run -- see the note above. }
var
  Permisos        : array[1..MaxChannels] of Boolean;  { DS:$1210  base-1 base $120f }
  TickCount       : Word;
  ModTickProc     : TTickProc;
  MyCanFallBack   : Boolean;
  FilterVal       : TFilterMethod;
  NoteBuff        : array[0..0] of TPlayingNote;  { DS:$1220  63 bytes, then a pad }
  Canales         : array[1..MaxChannels] of TCanal;  { DS:$1260  base-1 base $123a }
  BuffIdx         : Word;
  BuffGive        : Word;
  Buffers         : array[1..NumBuffers] of TSampleBuffer;
  SizeOfABuffer   : Word;
  ModFlag         : Boolean;
  MuestrasPerTick : Word;
  RawChannels     : array[1..MaxChannels] of TModRawChan;  { DS:$13a6  base-1 base $1384 }
  NoteRing        : array[0..RingRows - 1] of TRingRow;

  { NEW IN v1.51 -- THE WIDE RING, and its shape is read off three multipliers.
    12ce:021a is `SHL DI,7`, so a row is 128 bytes; 0243 is `SHL DI,5`, so the
    flag grid is 32 bytes a row; and 0206..0211 is `INC / CMP 18 / SUB 19`, so
    there are 25 rows exactly as the narrow ring has. }
  WideRing        : array[0..RingRows - 1] of TChansData;
  WideHit         : array[0..RingRows - 1, 1..WideChans] of Byte;

  { One byte each per row, and they are TWO arrays and not a record of two: 12ce:0263
    and 026e index them separately, 26 apart. They ride the ring with the row and are
    published to CB+$1AD and CB+$1AE.

    WHAT THEY HOLD CAME FROM THE WRITER, NOT THE READER. PublishWideRow only moves
    them, so nothing there says which is which; 12ce:090b does, storing
    `NoteProcessed^.NotePlaying` into the first and `SeqPlaying` into the second. The
    transcription had the pair swapped until that was read. }
  WideNoteRing     : array[0..RingRows - 1] of Byte;
  WideSeqRing    : array[0..RingRows - 1] of Byte;
  EventRing       : array[0..RingRows - 1] of TGusEventRow;

{ ---- MORE NOTES WITHOUT DECLARATIONS ----------------------------------------
  Same as the run above: these described variables that are now in the ordered
  block at $11f0..$1745, a few lines up. ---------------------------------- }
  { The release's name, confirmed by 12ba:1008 along with the guard it returns on,
    the song it plays and the flag that says the procedure has been set up -- the
    other four of that group are typed constants and are in the ordered block at the
    top of this file. }


{ NOTE ON A DECLARATION THAT NOW LIVES IN THE ORDERED CONST BLOCK AT THE TOP
  OF THIS FILE -- it does NOT describe the declaration below it. }
  { DS:$0c74 `TicksPerSecond` -- THE THIRD DUPLICATED GLOBAL, after AltMode and
    UsingGUS. DevGUS
    declares it privately in its implementation section, where a comment already
    records that the release moved it to SoundDevices and that ownership is the
    open question rather than the name. 12ba reads it here. Risk 1 again. }
  {ONE GLOBAL, TWO JOBS. At 06bc it is the note buffer's next slot;
    from 0802 it is the control variable of a `for` loop over the channels. The
    first use is finished before the second starts, so the reuse is harmless --
    but it is why the name is neutral rather than either role's. }

{ NOTE ON A DECLARATION THAT NOW LIVES IN THE ORDERED CONST BLOCK AT THE TOP
  OF THIS FILE -- it does NOT describe the declaration below it. }
  {THE RELEASE'S `MyLoopMod`, no longer provisional. Its assignment
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
  {the release's `ForceLoopMod`, "TRUE if music must be played
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
takes six bytes of arguments and does nothing with them.

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
UnCanal. Mix one channel into its own buffer.

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
  Rest := MuestrasPerTick;

  if ((Raw.Flags and rcfActiveChannel) <> 0) and
     ((Raw.Flags and rcfSampleFinished) = 0) then
  begin
    if (Raw.Flags and rcfDoesLoop) <> 0 then
      while Rest <> 0 do
      begin
        Rest := DumpInstrument(Raw.SplPosFrac, Buf, Raw.Volume,
                               Raw.StepFrac + LongInt(Raw.StepInt) * 65536,
                               Raw.LoopEnd - Raw.SplPosInt, Rest,
                               NumChannels * 2, False);
        if Rest <> 0 then
          Dec(Raw.SplPosInt, Raw.LoopLen)
      end
    else
      Rest := DumpInstrument(Raw.SplPosFrac, Buf, Raw.Volume,
                             Raw.StepFrac + LongInt(Raw.StepInt) * 65536,
                             Raw.SplLimit - Raw.SplPosInt, Rest,
                             NumChannels * 2, False)
  end;

  if Rest > 0 then
  begin
    Rest := DumpInstrument(Raw.SplPosFrac, Buf, 0,
                           Raw.StepFrac + LongInt(Raw.StepInt) * 65536,
                           Raw.SplLimit - Raw.SplPosInt, Rest,
                           NumChannels * 2, True);
    Raw.Flags := Raw.Flags or rcfSampleFinished
  end
end;

{ --------------------------------------------------------------------------
step the event ring on by one row and tally what is in it.

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
  {a hand-written CLD, and it has to be hand-written: Turbo Pascal
    emits no such prologue byte here, and the FillChar below is a runtime CALL
    rather than an inlined string instruction, so nothing in the body asks the
    compiler for one. Somebody wanted the direction flag known-good on a path
    the timer can reach. }
  asm
    CLD
  end;

  Inc(EventSlot);
  if EventSlot > RingRows - 1 then
    Dec(EventSlot, RingRows);
  if AltMode then
    EventSlot := 0;

  for EventChan := 0 to 7 do
  begin
    {a WITH, and the frame slot is its doing.
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
    with NoteRing[EventSlot, EventChan] do
      if Pending <> 0 then
        Inc(CtrlBlock.Semaphores[Sem])
  end;

  FillChar(NoteRing[EventSlot], SizeOf(TRingRow), 0)
end;

{ --------------------------------------------------------------------------
THE WIDE ROW, NEW IN v1.51, and it is the 8-channel ring above it
  done again for thirty-two.

  IT IS A SECOND RING AND NOT A REPLACEMENT. 0183 and 0202 sit back to back and
  neither touches the other's variables: the narrow one advances [02ee] and tallies
  into CtrlBlock+$000, this one advances [02f2] and publishes to CtrlBlock+$100 and
  CtrlBlock+$12D. Both are live. A client written for 1.31b keeps reading the block
  it knows and a client that wants all thirty-two channels reads the new one.

  THREE MULTIPLIERS FIX THE WHOLE SHAPE, and none of them had to be guessed:
  `SHL DI,7` at 021a makes a row 128 bytes, `SHL DI,5` at 0243 makes the flag grid
  32 bytes a row, and `INC / CMP 18h / SUB 19h` at 0206 makes it twenty-five rows --
  the same depth the narrow ring has.

  **THE ROW INHERITS FROM THE ONE BEFORE IT.** 0275 moves the PREVIOUS row over the
  one just advanced to, and 02ad and 02bd carry the two loose bytes across the same
  way, and only then is the flag grid cleared. So the ring holds STATE rather than
  events: every row starts as a copy of its predecessor, whatever the tick writes
  changes some of it, and the flag grid records which channels were touched. The
  narrow ring works the other way -- 01ea clears the row outright.

  `WidePrev` IS WHAT MAKES THAT WORK and it is why there is a third variable. 02cd
  copies the slot into it as the last statement, so the next call inherits from this
  one. Written with `WideSlot - 1` it would need a wrap test the original has not
  got.

  THE FOR LOOP HAS NO ENTRY GUARD. `MOV [02f4],1 / JMP test` -- Turbo Pascal omits
  the `1 <= 32` test when both bounds are constants and the range is not empty,
  which is why the body is reached by a jump forward rather than by falling in. }
procedure PublishWideRow;
begin
  {the same hand-written CLD as AdvanceEventRow's, and for the same
    reason: two `Move`s and a `FillChar` on a path the timer can reach. }
  asm
    CLD
  end;

  Inc(WideSlot);
  if WideSlot > RingRows - 1 then
    Dec(WideSlot, RingRows);

  { AN ASSIGNMENT, NOT A `Move`, AND THE HELPER IS WHAT SAYS SO -- 022b calls SYSTEM's
    $09f7 where a written `Move` gets $0fb2. Same rule this file already records for
    `Volume := UserVols`. }
  CtrlBlock.ChansData := WideRing[WideSlot];

  for WideChan := 1 to WideChans do
    if WideHit[WideSlot, WideChan] <> 0 then
      CtrlBlock.ChansTrig[WideChan] := 1;

  CtrlBlock.Pos := WideNoteRing[WideSlot];
  CtrlBlock.Seq  := WideSeqRing[WideSlot];

  WideRing[WideSlot] := WideRing[WidePrev];

  FillChar(WideHit[WideSlot], WideChans, 0);

  WideNoteRing[WideSlot]  := WideNoteRing[WidePrev];
  WideSeqRing[WideSlot] := WideSeqRing[WidePrev];

  WidePrev := WideSlot
end;


{ --------------------------------------------------------------------------
fill one slot of the GUS event ring.

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
{ `RET 16h` IN v1.51 AGAINST 1.31b's `RET 14h`, and the two bytes are AFreq going
  from Word to LongInt -- the same change the record made. }
procedure SetEvent(Voice, AVol : Byte; AFreq : LongInt; APan : Byte;
                   AStart, ALoop, AEnd : LongInt);
begin
  with EventRing[RingSlot, Voice] do
  begin
    Vol    := AVol;
    Freq   := AFreq;
    Pan    := APan;
    StartA := AStart;
    LoopA  := ALoop;
    EndA   := AEnd
  end
end;

{ --------------------------------------------------------------------------
post a voice event, merging into whatever is already there.

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
{ AFreq IS A LONGINT HERE TOO, and the sentinel test is what shows it most plainly:
  12ce:03ae is `CMP [BP+8],-1 / JNZ / CMP [BP+6],-1 / JZ`, Turbo Pascal's 32-bit
  compare done high word first. 1.31b had one `CMP ...,$FFFF`. Written as `-1` and
  not `$FFFFFFFF` because that is what gives the sign-extended byte immediate the
  original has -- the full constant would need four bytes of operand. }
procedure PostEvent(Voice, AVol : Byte; AFreq : LongInt; APan : Byte);
begin
  with EventRing[RingSlot, Voice] do
    if Freq = 0 then
    begin
      Vol  := AVol;
      Freq := AFreq;
      Pan  := APan
    end
    else
    begin
      if AVol <> $FF then
        Vol := AVol;
      if AFreq <> -1 then
        Freq := AFreq;
      Pan := APan
    end
end;

{ --------------------------------------------------------------------------
advance the event ring by one row, apply it, wipe it.

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
    CLD
  end;

  Inc(FlushSlot);
  if FlushSlot > RingRows - 1 then
    Dec(FlushSlot, RingRows);

  for RingVoice := 0 to GusVoices - 1 do
    with EventRing[FlushSlot, RingVoice] do
      if Freq <> 0 then
        if EndA > 0 then
          TriggerVoice(RingVoice, Vol, Freq, Pan,
                       StartA, LoopA, EndA)
        else
          ChangeVoiceParams(RingVoice, Vol, Freq, Pan);

  FillChar(EventRing[FlushSlot], SizeOf(TGusEventRow), 0)
end;

{ --------------------------------------------------------------------------
a sample descriptor into GUS voice control. NOT TRANSCRIBED.

  664 bytes, the largest routine in the segment so far, and docs/04-units.md
  covers only its first three statements. What IS established:

  THE SIGNATURE, read off the call site at 12ba:09e3 rather than the callee,
  per the standing rule. It pushes `MOV AL,[02f8] / PUSH AX` (a Byte), then
  `IMUL DI,[02f8],$22 / ADD DI,$1384 / PUSH DS / PUSH DI` (the address of a
  34-byte record), then a four-byte value read out of `[0300]^` at `+6`/`+8`.
  With `RET $0a` and near linkage that gives

      procedure ?(Chan : Byte; var Raw : TModRawChan; Desc : PInstrumentRec);

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

{ **A FOURTH PARAMETER, AND IT IS THE 9xx SAMPLE OFFSET ARRIVING IN THE PLAYER.**
  `RET 0Ch` in v1.51 against 1.31b's `RET 0Ah`, and everything the routine already
  did moved up two: Desc from [BP+4] to [BP+6], Raw from [BP+8] to [BP+0a]. The two
  spare bytes are at [BP+4], read twice -- 12ce:06cd and 073c -- as
  `MOV AX,[BP+4] / XOR DX,DX / ADD AX,ES:[DI+12] / ADC DX,ES:[DI+14]`, so a Word
  widened and added to the sample's start address. That is an offset into the sample
  and nothing else.

  1.39b NAMES IT, AND THE ROUTINE. LIB/PLAYMOD.PAS line 532 is
  `SetNewSample(i: BYTE; VAR Raw: TModRawChan; Spl: PInstrumentRec; Offs: WORD)`,
  and its two call sites inside ProcessNewNote pass `0` and `can^.SOffsVal` -- the
  same field 147d:0369 sets from command $0a. The whole 9xx path, from the effect to
  the voice, is one feature crossing two units, and both halves were found
  independently before either name was read.

  ~~SetGusVoiceCtl~~ takes the release's name. It was never GUS-specific: 1.39b has
  no GUS support in this unit at all and still has this routine. }
{ [1.39b] "Start a new sample on one of the channels."

  The release's own one-line description of this routine, in translation. Its
  section header for the group this belongs to reads "[1.39b] Routines that
  interpret the score." }
procedure SetNewSample(Chan : Byte; var Raw : TModRawChan; Desc : PInstrumentRec;
                       Offs : Word);
begin
  {compiled: `OR AX,[BP+6]` is the code generator's direction,
    and the `JNZ +3 / JMP` pair is what a large if-body gives when the skip is
    out of short range. }
  if Desc <> nil then
  begin
    { 03da..0413 -- HAND-WRITTEN, transcribed verbatim per the standing rule.
      Equivalent Pascal, REFERENCE ONLY -- the compiler does not produce these
      bytes from it, which is how the block was identified:

      **THE RELEASE DOUBTS THE LOOP TEST IN WRITING**, and the doubt is worth
      more than the test. At this point its own source says "[1.39b] If it has
      a loop (not sure this test is a good one" -- the author was unsure whether
      the condition below correctly decides that a sample loops. It is
      transcribed as measured either way, but a reader who finds this behaving
      oddly should know it was already suspected when it was written.

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
      LES     SI, Desc
      MOV     AX, ES:[SI+$12]        { 03e0  the sample data pointer, offset   }
      MOV     [DI+$0d], AX           { 03e4  -> Raw.SplOfs1                    }
      MOV     AX, ES:[SI+$14]        { 03e7  ... and segment                    }
      MOV     [DI+$0f], AX           { 03eb  -> Raw.SplSeg1                     }

      MOV     BYTE PTR NewFlags, rcfActiveChannel
      MOV     AX, ES:[SI+$09]        { 03f3  loop length, high word            }
      DB      21h, 0C0h              { 03f7  AND AX,AX -- 21 C0 is the inline  }
                                     {       assembler's direction; the code   }
                                     {       generator would emit OR           }
      JNZ     @@Looping
      MOV     AL, ES:[SI+$08]        { 03fb  loop length, low byte             }
      CMP     AL, 4                  { 03ff  under four bytes is no loop       }
      JNC     @@Looping
      MOV     BYTE PTR NoLoop, 1
      JMP     @@Ctl
  @@Looping:
      MOV     BYTE PTR NoLoop, 0
      OR      BYTE PTR NewFlags, rcfDoesLoop
  @@Ctl:
    end;

    { 0414..042b -- compiled: Turbo Pascal's LongInt comparison, high word
      first, `CMP ES:[DI+2],0 / JG / JGE / CMP ES:[DI],$FFF0 / JA`. $FFF0 is
      [1.39b] "Comes here if it is a long sample (more than 65520 bytes)", and
      on the other arm "Comes here if it is a short sample (less than 65520
      bytes)" -- the release's own words for the two branches below.

      65,520, which is what `rcfLongSample` means: a sample too long for one
      64K part. }
    if Desc^.Len > MaxSample then
    begin
      { 042c..0452 -- HAND-WRITTEN again, and the DS-relative store at 0437 is
        what says so. Equivalent Pascal, REFERENCE ONLY:

            NewFlags := NewFlags or rcfLongSample;
            Raw.SplLimit1 := $FFF0;
            Raw.SplLimit2 := Desc^.Len - $FFF0;

        [1.39b] "Set up the values for the long sample" -- the release's own
        note on this pair. So the first part is capped at 65,520 bytes and the remainder becomes
        the second. `SBB DX,0` carries the subtraction into the high word even
        though only the low word is stored -- the compiler's own idiom, kept
        verbatim. }
      asm
        MOV     DI, WORD PTR Raw
        LES     SI, Desc
        OR      BYTE PTR NewFlags, rcfLongSample
        MOV     WORD PTR [DI+$11], MaxSample   { 0437  -> Raw.SplLimit1          }
        LES     DI, Desc
        MOV     AX, ES:[DI]            { 043f  SplLen, low word              }
        MOV     DX, ES:[DI+$02]        { 0442  ... and high                   }
        SUB     AX, MaxSample
        SBB     DX, 0
        LES     DI, Raw
        MOV     ES:[DI+$17], AX        { 044f  -> Raw.SplLimit2              }
      end;

    {compiled, and the shape names the field: `LES DI,ES:[DI+$16]`
      loads a FAR POINTER out of the descriptor and then `MOV AX,DI` / `MOV AX,ES`
      take its halves, which is `Ofs(P^)` and `Seg(P^)` -- an Ofs of a
      dereference, not of the field. }
    Raw.SplOfs2 := Ofs(Desc^.Xtra^);
    Raw.SplSeg2 := Seg(Desc^.Xtra^);

    { [1.39b] "If there is a loop, a small mess :-)" -- the author's own
      assessment of the arithmetic below, and a fair one. A loop inside a sample
      that spans two 64K parts has to be expressed in whichever part it lands
      in, so each of the three quantities gets a test and a subtraction. }
    if NoLoop = 0 then
    begin
      {two LongInt comparisons with short-circuit `or`. The loop
        needs no splitting if it lies wholly inside one 64K part: either it
        starts beyond the boundary, or it starts and ends below it. `$FFF0` is
        the same 65,520 as above. }
      if (Desc^.Reps > MaxSample) or
         (Desc^.Reps + Desc^.Repl <= MaxSample) then
        {the low word only, which is what makes the LongInt
          field assignable to a Word without a cast. }
        Raw.LoopLen := Desc^.Repl
      else
      begin
        {the loop STRADDLES the 64K boundary, so its length is
          measured from the start of the second part and the flag says so.
          `ADD byte,$10` rather than `OR`, which is what `Inc` gives. }
        Raw.LoopLen := Desc^.Repl - MaxSample;
        Inc(NewFlags, rcfLongLoopLen)
      end;

      {and the same question again for the loop's END. The sum is
        recomputed in the test and in both branches, three times over, which is
        Turbo Pascal re-evaluating rather than anything in the source. }
      if Desc^.Reps + Desc^.Repl <= MaxSample then
        Raw.LoopEnd := Desc^.Reps + Desc^.Repl
      else
      begin
        Raw.LoopEnd := Desc^.Reps + Desc^.Repl - MaxSample;
        Inc(NewFlags, rcfLongLoopEnd)
      end
      end
    end
  else
    {HAND-WRITTEN, the short-sample path. `AND AL,AL` at 0559 is
      `20 C0`, the inline assembler's direction; the compiler's own test is
      `08 C0`, which is what 05ba has twelve bytes later. Everything here is
      16-bit because a sample under 64K needs no splitting at all.

      Equivalent Pascal, REFERENCE ONLY:

          Raw.SplLimit1 := Desc^.Len;
          if NoLoop = 0 then
          begin
            Raw.LoopLen := Desc^.Repl;
            Raw.LoopEnd := Desc^.Repl + Desc^.Reps
          end }
    asm
      MOV     DI, WORD PTR Raw
      LES     SI, Desc
      MOV     AX, ES:[SI]            { 0550  SplLen, low word                 }
      MOV     [DI+$11], AX           { 0553  -> Raw.SplLimit1                 }
      MOV     AL, NoLoop
      DB      20h, 0C0h              { 0559  AND AL,AL -- inline asm direction }
      JNZ     @@NoLoop
      MOV     AX, ES:[SI+$08]        { 055d  LoopLen                          }
      MOV     [DI+$20], AX           { 0561  -> Raw.LoopLen                   }
      ADD     AX, ES:[SI+$04]        { 0564  + LoopStart                      }
      MOV     [DI+$1e], AX           { 0568  -> Raw.LoopEnd                   }
  @@NoLoop:
    end;

  {HAND-WRITTEN, and common to both paths. It turns the LENGTHS
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
    MOV     DI, WORD PTR Raw
    MOV     WORD PTR [DI+$01], 0     { 056e  SplPosFrac                       }
    { THE TWO STORES SWAP AND AN `ADD` GOES BETWEEN THEM, which is where `Offs`
      reaches the playing position. 1.31b writes SplPosInt and SplOfs from the same
      AX; 1.51 writes SplOfs FIRST, adds the offset, and only then writes SplPosInt --
      so playback starts `Offs` bytes in while the channel's base pointer stays where
      the sample really is. Everything downstream measures from SplOfs, which is why
      the order had to change rather than just the arithmetic. }
    MOV     AX, [DI+$0d]             { 0662  SplOfs1                          }
    MOV     [DI+$07], AX             { 0665  -> SplOfs, unshifted             }
    ADD     AX, WORD PTR Offs        { 0668  + the 9xx offset                 }
    MOV     [DI+$03], AX             { 066b  -> SplPosInt                     }
    MOV     AX, [DI+$0f]             { 057c  SplSeg1                          }
    MOV     [DI+$05], AX             { 057f  -> SplPosSeg                     }
    MOV     [DI+$09], AX             { 0582  -> SplSeg                        }
    MOV     AX, [DI+$1e]             { 0585  LoopEnd                          }
    ADD     AX, [DI+$0d]             { 0588  + SplOfs1                        }
    MOV     [DI+$1e], AX
    MOV     AX, [DI+$17]             { 058e  SplLimit2                        }
    ADD     AX, [DI+$13]             { 0591  + SplOfs2                        }
    MOV     [DI+$17], AX
    MOV     AX, [DI+$11]             { 0597  SplLimit1                        }
    ADD     AX, [DI+$0d]             { 059a  + SplOfs1                        }
    MOV     [DI+$11], AX
    MOV     [DI+$0b], AX             { 05a0  -> SplLimit                      }
    MOV     AL, NewFlags
    MOV     [DI], AL                 { 05a6  -> Raw.Flags                     }
  end;

  {compiled, and back to the event ring. `DS:$0bce` is
    `DevGUS.Started`, so nothing is posted unless the GUS driver is running --
    which is the clearest statement yet that this whole routine is the GUS path.

    Both arms call 12ba:0202, and both pass $FF and $FFFF for the volume and the
    frequency: the sentinels that mean "leave those alone", so the event carries
    only a pan position and the three DRAM addresses. A looping sample gets
    LoopA and EndA measured from the loop; a one-shot gets LoopA = -1 and EndA at
    the end of the sample. }
  { THREE CHANGES IN BOTH ARMS, and the third is the one that matters.

    `$FFFF` BECOMES `-1` because AFreq is a LongInt now: 12ce:0728 and 072a are
    `PUSH -1 / PUSH -1`, two words where 1.31b pushed one.

    `Offs` IS ADDED TO THE START ADDRESS and to that alone -- 073c is
    `MOV AX,[BP+4] / XOR DX,DX / ADD AX,ES:[DI+12] / ADC DX,ES:[DI+14]`, and the loop
    and end addresses are still measured from the unshifted sample. Which is right: a
    9xx starts playback part-way in without moving where the loop is.

    **AND THE PAN COMES FROM THE SONG, WHICH IS THE 1.31b NOTE COMING TRUE.** The note
    at `Pannings` said "The release keeps pan in the SONG (`PanPositions`, initialised
    from its `DefPan`) and 1.31 keeps it in the player -- which is why `InitValues` in
    14b9 has no trace of the release's last statement, a thing this project had
    already found from the other end." 12ce:0731 is `LES DI,[02ca] / ADD DI,AX /
    MOV AL,ES:[DI+28]`, and $02ca is `PlayingSong` after this block's +$6 shift, and
    +$28 plus a base-1 index is `TSong.ChannelPan` -- the field SONGUNIT measured from
    the S3M loader's own `ES:[DI+28]`. Two units, two independent measurements, one
    field. 1.51 is where DemoVT catches up with the release. }
  if UsingGUS then
    if (Raw.Flags and rcfDoesLoop) <> 0 then
      SetEvent(Chan - 1, $FF, -1, PlayingSong^.ChannelPan[Chan],
               { **`Data` IS A POINTER IN SongElements AND THIS IS A GUS DRAM ADDRESS**, so
        every use of it here is cast. The SongUnit copy declared the field a
        LongInt outright, which made the arithmetic read naturally and was the one
        thing that copy got MORE right than the release -- 12ba:05e0 adds a loop
        offset to it, and you cannot add to a `^TSample`. The cast reinterprets
        and emits nothing; the byte count is the check. }
      Offs + LongInt(Desc^.Data),
               LongInt(Desc^.Data) + Desc^.Reps,
               LongInt(Desc^.Data) + Desc^.Reps + Desc^.Repl)
    else
      SetEvent(Chan - 1, $FF, -1, PlayingSong^.ChannelPan[Chan],
               Offs + LongInt(Desc^.Data), -1,
               LongInt(Desc^.Data) + Desc^.Len);

  { NEW IN v1.51, AND IT IS OUTSIDE THE `UsingGUS` TEST. The false path at 06a1 jumps
    to 076c, which is this store -- so a channel is marked in the wide ring whatever
    the output device is, while the event ring above it is GUS-only. That is what
    makes the published row a description of the SONG rather than of the hardware. }
    WideHit[WideSlot, Chan] := 1
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
        PUSH    DS

        LDS     SI, Src
        LES     DI, Dest
        MOV     CX, Bytes

        CLD

        AND     CX, CX                 { 0672  21 C9 -- the inline assembler's }
                                       {       direction, as everywhere here   }
        JZ      @@Fin

        TEST    SI, 1                  { 0676  align on the SOURCE            }
        JZ      @@NoBeg
        MOVSB                          { 067c  one leading byte               }
        DEC     CX
        JZ      @@Fin

@@NoBeg:
        MOV     BX, CX
        SHR     CX, 1
        REP     MOVSW
        MOV     CX, BX
        AND     CL, 1
        JZ      @@Fin

        MOVSB                          { 068d  and the trailing byte          }
@@Fin:
        POP     DS
end;

{ --------------------------------------------------------------------------
  12ba:0693 -- advance to the next pattern, and honour a seek request.
  IN PROGRESS: transcribed as far as 070d.

  THE SEEK INTERFACE. `DS:$24c9`, `$24ca` and `$24cb` are `CtrlBlock + $203`,
  `+$204` and `+$205` -- inside the 768-byte structure published over INT 2Fh,
  and `VTCtrl` names them `JumpNewPos`, `JumpPosSeq` and `JumpPosNote`, which are
  the client bindings' own names for them. So a resident client can ask the player
  to jump: set the position and row, raise the flag, and the next time the
  sequencer crosses a pattern boundary it honours the request and clears the flag.

  IT IS NOT THE ONLY FIELD A CLIENT WRITES, which is what stood here. The
  bindings mark a whole region as the client's -- these three, `SoundVolume` and
  `Abort` -- and the demo documentation adds that a client may write the
  semaphores too, "usually cleaning them". Psycho Neurosis never uses any of it.

  AND THE ROTATION IS DISABLED. `INC AX` at 06bf is immediately followed by
  `AND AX,0`, so the next slot is always slot zero: the two-slot rotation of
  63-byte rows is there and switched off by one instruction. Transcribed as
  found -- `and 0` and all -- because tidying it would change the bytes. It also
  makes the MyMove below copy slot zero onto itself.
  **THIS IS THE RELEASE'S `ProcessNewNote`**, identified the same way: its
  constants -- `i`, `j`, `n`, `can`, `Patt`, `NewSample` -- are this routine's
  `NextIdx`, `ChanIdx`, `NewNote`, `CurCanal`, `Pattern` and `NewSample`, in
  order, and none of them is touched anywhere else.

  [1.39b] "Work out and process the next note of the score."

  The release groups it under a section headed "[1.39b] Routines that interpret
  the score", which is the same group `SetNewSample` belongs to.
  -------------------------------------------------------------------------- }
procedure NextPattern(var Song : TSong);
begin
  NullProcedure($FFFF, 0, 0);

  if CtrlBlock.JumpNewPos <> 0 then
  begin
    CtrlBlock.JumpNewPos := 0;
    NextSeq := CtrlBlock.JumpPosSeq;
    NextNote := CtrlBlock.JumpPosNote
  end;

  NextIdx := (NoteHd + 1) and 0;
  NoteProcessed := @NoteBuff[NextIdx];
  MyMove(NoteBuff[NoteHd], NoteProcessed^, SizeOf(TPlayingNote));
  NoteHd := NextIdx;

  with NoteProcessed^ do
  begin

    { **NEW IN v1.51: THE WHOLE HEAD OF THIS ROUTINE IS NOW A `repeat`,** and it is
      1.39b's, which has carried it since 1993. The loop skips ORDER POSITIONS THAT
      NAME A PATTERN THE SONG HAS NOT GOT -- `GetPatternSequence` returning an index
      at or past `Patterns.Count` -- by advancing the position and going round again.
      1.31b has no such test and would have indexed off the end.

      `Song.Patterns.Count` IS AT +$67 AND THAT IS THE +$20 SHIFT SHOWING. SONGUNIT
      measures the collection at Song+$41 with its count at +$47; TSong gained 32
      bytes in 1.51 when `ChannelPan` went in, so everything past the insertion moves
      by $20 and $47 + $20 is $67. A field offset confirming a record change measured
      in a different unit, from the other side.

      THE COMPARISON IS 32-BIT AND MIXED-SIGN, which is what the two widenings say:
      12ce:08a6 is `XOR DX,DX` on the call's result -- a Word, unsigned -- and 08b3 is
      `CWD` on `Patterns.Count`, which TCollection declares as an Integer. Turbo
      Pascal promotes both to LongInt so the signed and unsigned halves can meet. }
    repeat
    EoMod := NextNote = $FFFF;

    if EoMod then
      if MyLoopMod then
      begin
        { The module wraps. Jump to the end position, clamped up to the start,
          and take it from row 1 -- then clear the marker so the row is played
          rather than treated as past the end. }
        NextSeq := RangeEnd;
        if NextSeq < RangeStart then
          NextSeq := RangeStart;
        NextNote := 1;
        EoMod := False
      end
      else
      begin
        { No looping permission: stop, and leave. The JMP at 0747 goes to the
          routine's own exit, which is what `Exit` compiles to. }
        Playing := False;
        Exit
      end;

    NotePlaying := NextNote;
    SeqPlaying  := NextSeq;
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
    Volume := UserVols;

      if Song.GetPatternSequence(SeqPlaying) >=
         Song.Patterns.Count then
      begin
        Inc(NextSeq);
        if NextSeq > MySongLen then
          NextNote := $FFFF
        else
          NextNote := 1
      end
    until Song.GetPatternSequence(SeqPlaying) <
          Song.Patterns.Count;

    { NEW IN v1.51 -- the wide ring learns where the song is. These are the two loose
      bytes PublishWideRow later hands to CB+$1AD and CB+$1AE, and this is the writer
      that says which is which. }
    WideNoteRing[WideSlot] := NotePlaying;
    WideSeqRing[WideSlot]  := SeqPlaying;

    { 0773..078d -- `Pattern := Song.GetPatternSeq(SeqPlaying)`, a far call into
      14b9. THAT UNIT IS A STUB -- see demovt/src/VTSONG.PAS -- but the call site
      is real: the arguments, their order and the far linkage are read off these
      bytes, and the target is a pending fixup exactly as the linker would leave
      it. The position is pushed FIRST, so it is the first declared parameter and
      `Song` the second; 1.39b calls the equivalent as a method, which its own
      history block explains -- `TSong` became an object in February 1993. }
    Pattern := Song.GetPatternSeq(SeqPlaying);

    {advance one row, or fall off the end of the pattern and
      advance the order position instead. `Pattern^.Patt^` is a byte reached
      through a far pointer at the pattern's +$06; a position past the last one
      sets the row to $FFFF, which is the marker 06fe tests on the next call. }
    { **`NNotes` AND `Patt` ARE SongElements' NAMES FOR THE SAME TWO BYTES.** The
      operand ORDER stays as it is: 1.39b writes `IF NextNote < Patt^.Patt^.NNotes`
      and the original's codegen here puts the field first. A field rename is free
      and flipping a comparison is not. }
    if Pattern^.Patt^.NNotes > NextNote then
      Inc(NextNote)
    else
    begin
      Inc(NextSeq);
      if NextSeq > MySongLen then
        NextNote := $FFFF
      else
        NextNote := 1;
    end;

    {an EMPTY order position. `GetPatternSequence` returning zero
      means there is no pattern here, so the module's own defaults come back, every
      channel is wiped and given a silent note, and the sequencer walks forward
      until it finds a position that does have one -- or runs off the end.

      This block was blocked until 14b9 could be declared: the call's result drives
      the branch, which a byte placeholder cannot do. See demovt/src/VTSONG.PAS. }
    if Song.GetPatternSequence(SeqPlaying) = 0 then
    begin
      CurSpeed := Song.InitialTempo;
      CurTempo := Song.InitialBPM;
      FillChar(Canales, SizeOf(Canales), 0);

      { A silent note at period 800 in every channel. }
      { `CMP [02fc],10h` in v1.51 against 1.31b's `CMP ..,08` -- the literal follows
        the channel count, so it goes through the constant now. }
      for NextIdx := 1 to MaxChannels do
        with Canales[NextIdx] do
        begin
          Note.Period     := 800;
          Note.Instrument := 1;
          Note.Command    := mcNone;
          Period          := 800
        end;

      {walk forward. A position past the last sets the row to
        $FFFF, which both ends this loop and marks the module as finished for the
        next call. }
      repeat
        Inc(SeqPlaying);
        if SeqPlaying > MySongLen then
          NextNote := $FFFF
        else
          NextNote := 2
      until (NextNote = $FFFF) or
            (Song.GetPatternSequence(SeqPlaying) <> 0);

      NextSeq := SeqPlaying
    end;

    {the SPEED for this row, if anything overrides it. Two sources,
      and the row number picks between them: on row 1 a per-position byte out of
      14b9's second table, otherwise the pattern's own. Zero means "no override"
      in both cases, so the speed set at 07dd stands.

      Turbo Pascal evaluates `GetPatternTempo` TWICE here, once for the test and
      once for the value, which is what the two identical CALLFs at 08ad and 08c5
      are -- not a source that calls it twice deliberately. }
    if NotePlaying = 1 then
      if Song.GetPatternTempo(SeqPlaying) <> 0 then
        CurSpeed := Song.GetPatternTempo(SeqPlaying)
      else
      begin
        if Pattern^.Patt^.Tempo <> 0 then
          CurSpeed := Pattern^.Patt^.Tempo
      end;

    {once per channel: fetch this row's note out of the song and
      keep a copy in the row being handed on.

      `Song.NumChannels` is not a constant, so Turbo Pascal evaluates the limit into a
      temporary at [BP-6] before the loop -- the same four bytes the `with` above
      used, reused now that the `with` is finished. That is a compiler temporary
      sharing a slot, not a variable being reused.

      The copy at 0946 goes through MyMove rather than an assignment, and the
      address it builds -- `ChanIdx*6 + 6` from the record's base -- is what
      fixed TPlayingNote's layout: base-1 indexing of the Note array at +$0c. }
    for ChanIdx := 1 to Song.NumChannels do
    begin
      CurCanal := @Canales[ChanIdx];
      Song.GetNote(SeqPlaying, NotePlaying, ChanIdx,
                   NewNote);
      MyMove(NewNote, Note[ChanIdx], SizeOf(TFullNote));

      { NEW IN v1.51 -- A CHANGE OF INSTRUMENT MARKS THE CHANNEL IN THE WIDE RING,
        and it is a narrower test than the retrigger below: only the instrument
        number, not the period. 12ce:0b2a compares the channel's current instrument
        against the new note's and sets the flag when they differ. }
      if (NewNote.Instrument <> 0) and
         (CurCanal^.Note.Instrument <> NewNote.Instrument) then
        WideHit[WideSlot, ChanIdx] := 1;

      NewSample := False;

      {DOES THIS ROW RETRIGGER THE CHANNEL? Two groups joined by
        `or`, each short-circuited, and the jump targets read straight off:

          a new instrument number that differs from the one playing, OR
          a period with a command that is not 4 or 6

        Commands 4 and 6 are ProTracker's vibrato and vibrato-plus-volume-slide:
        they carry a period for the vibrato to work from and must NOT restart the
        sample. That is the whole point of the second group. }
      if ((NewNote.Instrument <> 0) and
          (CurCanal^.Note.Instrument <> NewNote.Instrument)) or
         ((NewNote.Period <> 0) and
          (NewNote.Command <> mcNPortamento) and
          (NewNote.Command <> mcT_VSlide)) then
      begin
        {a new instrument: remember it and fetch its sample data. }
        if NewNote.Instrument <> 0 then
        begin
          CurCanal^.Note.Instrument := NewNote.Instrument;
          { `Instr`, and the rename is the proof the six bytes ahead of it were a
            VMT word and a name: GetInstrument returns a `PInstrument` OBJECT, and
            the pointer at +$06 is its `Instr` field. The local copy called the
            object a record and the field `Data`. }
          CurCanal^.Instrument :=
            Song.GetInstrument(NewNote.Instrument)^.Instr
        end;

        {and hand the sample to the GUS voice. This is the call
          site that gave SetNewSample its signature back when 03cc was
          transcribed: the channel number as a Byte, the raw channel by
          reference, the descriptor by value. }
        SetNewSample(ChanIdx, RawChannels[ChanIdx],
                     CurCanal^.Instrument, 0);
        NewSample := True
      end;

      {a new instrument also resets the channel's volume to that
        instrument's own default, which lives at the descriptor's +$0c. The nil
        test is `MOV AX,[DI+6] / OR AX,[DI+8]`, both halves of the pointer, which
        is how Turbo Pascal compares a Pointer against nil. }
      if (NewNote.Instrument <> 0) and
         (CurCanal^.Instrument <> nil) then
        CurCanal^.Volume := CurCanal^.Instrument^.Vol;

      {the note's own volume overrides it, stored one lower than
        written, and clamped to 64 whichever way it arrived. }
      if NewNote.Volume <> 0 then
        CurCanal^.Volume := NewNote.Volume - 1;
      if CurCanal^.Volume > 64 then
        CurCanal^.Volume := 64;

      {hand the note to the effects unit. `CommandStart` is the
        release's name and the argument order is its own; see MODCOMMA.PAS. }
      CommandStart(Song, CurCanal^, NewNote);

      { NEW IN v1.51 -- THE SAMPLE IS HANDED OVER A SECOND TIME, and this is the far
        end of the 9xx path. `CommandStart` has just run, so if the row carried a
        sample-offset command `StartSampleOffs` has set `SOffs` and `SOffsVal` by
        now; re-issuing the sample with the offset is what makes the effect audible.
        `NewSample` is what stops it firing on a row that did not start a sample at
        all -- the offset would then apply to a note already part-way through.

        BOTH HALVES OF THIS FEATURE WERE MEASURED BEFORE EITHER WAS NAMED. 147d:0369
        set the two fields, 12ce:04bb grew the parameter that carries the value, and
        only 1.39b's own call site joined them up. }
      if NewSample and CurCanal^.SOffs then
        SetNewSample(ChanIdx, RawChannels[ChanIdx],
                     CurCanal^.Instrument,
                     CurCanal^.SOffsVal);

      {and NOT `Tempo := CurSpeed`, which is what the enclosing
        `with` would give. The original reloads the pointer from DS:$02dc, so the
        source names it: inside a `with P^ do`, writing `P^.Field` explicitly
        makes Turbo Pascal reload P instead of using the with-slot. Two different
        instruction sequences for the same assignment. }
      NoteProcessed^.Tempo := CurSpeed;

      {publish the channel's event into the note ring, where
        12ba:0187 will increment the semaphore it names. The ring is indexed by
        the CONSUMER's slot, DS:$02ec, not the event ring's. }
      NoteRing[EventSlot, ChanIdx - 1].Pending :=
        CurCanal^.RingPending;
      NoteRing[EventSlot, ChanIdx - 1].Sem :=
        CurCanal^.RingSem;
      CurCanal^.RingPending := 0
    end;                                             { 0a97..0aa1  for end   }

    {how many samples this row is worth.

      `ActualHz div TicksPerSecond` is samples per tick, capped by MaxSplPerTick;
      multiplied by the row's tick count it gives `NMuestras`, which the release
      documents as "Number of samples processed for each note". `NoteHz` starts
      the row at the same rate and is floored at 1 -- a zero would divide by zero
      in the tick arithmetic that follows. }
    MuestrasPerTick := ActualHz div TicksPerSecond;
    if MuestrasPerTick > MaxSplPerTick then
      MuestrasPerTick := MaxSplPerTick;

    { UNQUALIFIED here, where 0a4d was explicit -- and the bytes are what say
      so: this one is `LES DI,[BP-4]`, the with-slot, where 0a4d reloads from
      DS:$02dc. The author wrote one of these two the long way and not the other,
      in the same routine, ten instructions apart. }
    NMuestras := Tempo * MuestrasPerTick;

    NoteHz := ActualHz;
    if NoteHz = 0 then
      NoteHz := 1;

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
    NoteCalcVal := ($364C0000 div NoteHz) shl 4;

    {publish the row. The tail index catches up with the head and
      the sounding pointer with the processed one, so whatever reads `NoteSound`
      now sees the row this call built. Then the same do-nothing call the routine
      opened with, this time with zeros. }
    NoteTl := NoteHd;
    NoteSound := NoteProcessed;
    NullProcedure(0, 0, 0)
  end
end;

{ --------------------------------------------------------------------------
the software mixing path, once per tick. IN PROGRESS.

  This is what drives `UnCanal` and the filters, per channel, and it is the
  other half of the unit: 12ba holds two independent output paths and the driver
  decides which runs. `IsDmaDevice` is the switch -- on a DMA device the mixing
  happens elsewhere and this routine does almost nothing.
  -------------------------------------------------------------------------- }
procedure MixTick(var Song : TSong);
begin
  NullProcedure($FFFF, $FFFF, $FFFF);

  ModRec  := @Buffers[BuffIdx];
  ModFlag := ModRec^.InUse;
  if ModFlag then
    Exit;

  {mix every channel, unless the device does its own DMA mixing.
    Each channel writes into its own slice of the module's buffer, interleaved by
    the channel count, and is then filtered in place with the state carried in
    SplBuf. `FilterChunkWord`'s `Offs` is that interleave stride, which is why the
    channel count is passed there. }
  if not IsDmaDevice then
    for MixChan := 1 to Song.NumChannels do
    begin
      ChanRec := @RawChannels[MixChan];
      OutPtr  := @PWordArray(ModRec^.IData)^[MixChan - 1];
      UnCanal(ChanRec^, OutPtr);
      SplBuf[MixChan] := FilterChunkWord(OutPtr^, MuestrasPerTick,
                                         Song.NumChannels, FilterVal,
                                         SplBuf[MixChan])
    end;

  {and mark the entry played, with the sample count it produced.
    Both paths reach here: the DMA one jumps straight to it from 0b63. }
  ModRec^.InUse    := True;
  ModRec^.NSamples := MuestrasPerTick;
  ModRec^.RateHz   := NoteHz;
  ModRec^.DataType := 1;
  ModRec^.Channels := Song.NumChannels;

  {AND THE SECOND DISABLED ROTATION IN THIS UNIT. `Inc(ModIdx)`
    followed by a clamp to 1 means the index is 1 from the first call onward, so
    only one entry of the module table is ever used -- exactly like the `and 0` at
    12ba:06c0 pinning the note buffer to slot zero. Two independent pieces of
    machinery for handling more than one of something, both switched off by their
    own next instruction. Transcribed as found. }
  Inc(BuffIdx);
  if BuffIdx > 1 then
    BuffIdx := 1;

  NullProcedure(0, $FFFF, 0)
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
  **THIS IS THE RELEASE'S `ProcessTick`**, and the identification is measured
  rather than guessed from the name. Its typed-constant block -- `incr`,
  `OTempoCt`, `Can`, `Raw`, `NoteHzFreq`, `i`, `j`, `t`, `step`, `FBCount`,
  `NumChannels` -- is this routine's block, in that order and those widths, and
  the constants live in this routine and nowhere else. The names diverged; the
  storage did not.

  [1.39b] "Process one tick of the music. Normally 50 ticks per second are used,
          but that can be changed."
  -------------------------------------------------------------------------- }
procedure SeqTick(var Song : TSong);
begin
  { **NEW IN v1.51: THE PRODUCER ADVANCES HERE, AND IT CAN REFUSE TO.** 1.31b had one
    shared ring cursor and no way to run out of room; 1.51 splits the cursors and puts
    the producer's advance at the top of the tick, guarded by the full test.

    `(RingSlot + 1) mod RingRows` IS SIX INSTRUCTIONS BECAUSE 25 IS NOT A POWER OF
    TWO. 12ce:0e78 is `MOV AX,[02e8] / INC AX / XOR DX,DX / MOV CX,19 / DIV CX /
    XCHG AX,DX` -- Turbo Pascal's Word `mod`, with the remainder swapped out of DX.
    Then `CMP AX,[02ea] / JNZ +3 / JMP exit`: if the next row is the one the consumer
    is still on, the ring is full and the whole tick is abandoned.

    ABANDONING THE TICK IS THE POINT. The rest of this routine is what advances the
    song, so declining to run it is how the sequencer waits for the mixer -- back
    pressure, not a dropped event. }
  if UsingGUS then
  begin
    if (RingSlot + 1) mod RingRows = FlushSlot then
      Exit;
    Inc(RingSlot);
    if RingSlot > RingRows - 1 then
      Dec(RingSlot, RingRows)
  end;

  if IsDmaDevice and (TickSnapshot = Ticks) then
    Exit;
  Inc(TickSnapshot);

  if ModFlag and not UsingGUS then
  begin
    MixTick(Song);
    if ModFlag then
      Exit
  end;

  { ~~if UsingGUS then FlushEventRow~~ -- **GONE IN v1.51, AND DEVGUS IS WHY.** The
    consumer now runs from the timer interrupt: 106e:0019 is `CALLF FlushEventRow`,
    so draining the ring is no longer the sequencer's job. What replaces the call
    here is the wide ring's own advance, which IS the sequencer's. 12ce:0ed4 and 0ed7
    are two bare near CALLs with nothing between them. }
  AdvanceEventRow;
  PublishWideRow;

  Inc(TickCount);

  {a 32-bit counter INSIDE the published control block, at
    CtrlBlock + $125, immediately after the dispatch pointer. Together with the
    per-channel counters 12ba:0187 bumps, that is live state any INT 2Fh client
    can read. Psycho Neurosis never does. }
  Inc(CtrlBlock.TickCounter);

  { **MOVED UP IN v1.51** -- 1.31b assigns this 170 bytes further down, immediately
    before the hand-written loop that reads it. Nothing between the two positions
    touches it, so the move changes no behaviour and it is transcribed where the
    original puts it. }
  TickChans := Song.NumChannels;

  {THE TEMPO ENGINE, and it divides nothing per row. `TempoAccum`
    is a running fractional accumulator, `CurTempo` the amount added each tick and
    `TempoDiv` the divisor: the tick counter advances by the whole part and the
    remainder is carried. That is how a tracker gets a non-integer ticks-per-row
    ratio -- arbitrary BPM -- out of integer arithmetic alone. }
  PrevTick := TickInRow;
  Inc(TempoAccum, CurTempo);
  Inc(TickInRow, TempoAccum div TempoDiv);

  { ONLY THE `mod` IS GUARDED. The `JZ` at 0cc9 jumps thirteen bytes, which is the
    remainder statement alone -- the row test below is reached either way. Written
    with the second `if` nested, the jump would have to clear both. }
  if TickInRow <> PrevTick then
    TempoAccum := TempoAccum mod TempoDiv;

  { **NEW IN v1.51: THE ROW ADVANCE IS A LOOP, AND IT IS 1.39b's.** 1.31b takes the
    accumulator's whole part, applies it to `TickInRow` in one go, and processes ONE
    row boundary; if the tempo is high enough for two ticks to fall in a single call,
    the second is simply lost. 1.51 winds `TickInRow` back to where it started and
    walks forward one tick at a time, so every boundary in the span gets its row
    change and its effect pass.

    `i := TickInRow - PrevTick` IS WHAT MAKES THAT POSSIBLE and it has to be computed
    BEFORE the wind-back -- 12ce:0f26 subtracts, 0f32 restores. Two statements that
    look redundant together and are not: the first captures the span the accumulator
    produced, the second undoes the advance so the loop can redo it in steps.

    `downto` AND NOT `to`, which the loop shape says outright: 0f3b is `CMP AX,1 /
    JC` on the span, 0f40 seeds the counter with it, and 0fa5 closes on `CMP [0334],1
    / JNZ` with a `DEC` at the top. Counting down needs no limit temporary. }
  TmpVal := TickInRow - PrevTick;
  TickInRow := PrevTick;

  for TickIter := TmpVal downto 1 do
  begin
    Inc(TickInRow);

    { The row is over when its tick count is reached. `Tempo` is the release's name
      and its comment is "Number of ticks the note will last". }
    if TickInRow >= NoteProcessed^.Tempo then
    begin
      NextPattern(Song);
      if not Playing then
        Exit;
      TickInRow := 0
    end;

  { ~~TWO `NullProcedure` CALLS STOOD HERE~~ AND v1.51 HAS NEITHER. 1.31b brackets
    the effect loop with `NullProcedure($FFFF, 0, 0)` before it and
    `NullProcedure($FFFF, $FFFF, 0)` after; 12ce:0ffc runs from the tempo loop's last
    instruction straight into `LES DI,[BP+4]`, with no `PUSH -1` anywhere between.
    They were debugging colour-bar markers -- 1.39b's equivalent is a commented-out
    `SetBorder` -- and the release took them out. }

  {run every channel's effect for this tick, unless this is the
    row's first tick and the song has nothing at Fill16[$24].

    THE LOOP IS HAND-WRITTEN. `LOOP` and `MUL BL` are not Turbo Pascal's output,
    and the callee takes its arguments in REGISTERS -- SI pointing at the channel,
    BX the command number doubled into a jump-table index. The release documents
    exactly that: "En las del tick, se entra con SI apuntando al TCanal
    correspondiente."

    Equivalent Pascal, REFERENCE ONLY -- there is none that produces these bytes:

        for i := TickChans downto 1 do
          CommandTick(Canales[i], Canales[i].Note.Command * 2) }
    if (TickInRow > 0) or (Song.FirstTick <> 0) then
      asm
      XOR     CH, CH
      MOV     CL, TickChans
  @@Chan:
      PUSH    CX
      MOV     AL, CL
      DEC     AL
      { `$2E` IN v1.51 AND `$26` IN 1.31b -- the stride is SizeOf(TCanal), and the
        record grew eight bytes when the retrigger, the sample offset and the S3M
        volume fields went in. Written through SizeOf so the two cannot drift; the
        original has the literal, and a literal is what a hand-written loop would
        have, but a wrong literal here would silently index into the wrong channel. }
      MOV     BL, $2E                { 0f8d  46 in v1.51, 38 in 1.31b         }
      MUL     BL
      MOV     SI, OFFSET Canales
      ADD     SI, AX
      MOV     BL, [SI+$04]           { 0d89  Note.Command                     }
      ADD     BL, BL                 { 0d8c  doubled -- a word index          }
      XOR     BH, BH
      CALL    FAR PTR CommandTick
      POP     CX
      LOOP    @@Chan
      end
  end;

  {the fall-back request. `PleaseFallback` is SoundDevices' way of
    saying it could not get a buffer at the current rate; permission to act on it
    is MyCanFallBack's, and without it the request is just dropped.

    THE SECOND `if` IS A TAUTOLOGY as it stands -- `NewHz` is assigned from
    `ActualHz` on the line before and then compared against it, with nothing in
    between that could change either. Transcribed as found: the bytes at 0d1a are
    a real load, compare and branch, and removing them would shift everything
    after. It reads like a check that lost whatever used to sit between the two
    statements -- the same shape as the dead operand setup in 1a17's GetPlayPos. }
  if not MyCanFallBack then
    PleaseFallback := 0;

  if PleaseFallback > 0 then
  begin
    PleaseFallback := 0;
    TmpVal := ActualHz;

    {NEGOTIATE A RATE THE DEVICE WILL ACCEPT. Ask what it can
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
    begin
      Dec(DesiredHz, 100);
      TmpVal := TGetFreqProc(ActiveDevice^.GetRealFreqProc)(DesiredHz)
    end;

    {and act on it. `PUSH CS / CALL near` is how Turbo Pascal
      calls a FAR routine that lives in the same segment, which is what
      ChangeSamplingRate is. }
    ChangeSamplingRate(DesiredHz)
  end;




  {turn each channel's own volume into the mixing volume the
    resampler will use. The divisor is the channel count rounded UP to an even
    number, so the summed output cannot clip; the `shr 4` is the fixed-point
    scale on UserVols. }
  for TmpVal := 1 to Song.NumChannels do
  begin
    CanalPtr := @Canales[TmpVal];
    RawPtr   := @RawChannels[TmpVal];
    if not UsingGUS then
      {the software path: divide the sum down so it cannot clip. }
      RawPtr^.Volume := CanalPtr^.Volume * UserVols[TmpVal] shr 4
                        div ((Song.NumChannels + 1) and $FFFE)
    else
      {the GUS path needs no headroom, because the card mixes: the
        scale is `shr 6` with a rounding `+1` before the final halving. }
      RawPtr^.Volume := (CanalPtr^.Volume * UserVols[TmpVal] shr 6 + 1) shr 1;

    {AND THESE TWO ARE COMMON TO BOTH PATHS. The software branch's
      `JMP` at 0e22 lands on 0e4a, not past it, which is what says so; written
      inside the GUS branch they would be jumped over. }
    { **$7F IN v1.51, $80 IN 1.31b** -- 12ce:10bd stores 7F. One less than the power
      of two, which is what a clamp to "the largest value that fits" looks like when
      the consumer treats the top bit as a sign. }
    { **THE TEST IS $80 AND THE STORE IS $7F**, which is not a slip: the clamp admits
      everything below $80 and pins the rest at the largest value that is not $80. }
    if RawPtr^.Volume >= $80 then
      RawPtr^.Volume := $7F;

    {the master volume, and HAND-WRITTEN. Two tells: the pointer
      goes into SI, where Turbo Pascal's code generator always uses DI, and the
      multiply is the 8-bit `MUL BL` with the product's high byte stored straight
      back -- Pascal promotes `Byte * Byte` to a word and would emit `MUL DX`
      followed by a shift.

      Equivalent Pascal, REFERENCE ONLY:

          RawPtr^.Volume := RawPtr^.Volume * CtrlBlock.SoundVolume shr 8 }
    asm
      LES     SI, RawPtr
      MOV     AL, ES:[SI+$1d]            { 0e62  Volume                      }
      MOV     BL, CtrlBlock.SoundVolume
      MUL     BL
      MOV     ES:[SI+$1d], AH            { 0e6c  the high byte = shr 8        }
    end;

    {a period of zero would divide by zero downstream. }
    if CanalPtr^.Period = 0 then
      CanalPtr^.Period := 1;

    { **AND A CEILING TO GO WITH THE FLOOR, NEW IN v1.51.** 12ce:10e9 clamps `Period`
      at $1FFF, the same bound the RealPeriod clamp further down uses. 1.31b guards
      only against zero here; 1.51 guards both ends, for the same reason the other
      clamp exists -- the rewritten arpeggio and the S3M loader can both produce
      periods no note table would ever hold.

      IT IS A SEPARATE `if`, NOT AN ELSE. 10ef's `JBE` skips only the assignment and
      falls into the same continuation the zero test does; written as
      `else if` the zero case would jump past this test entirely, and a period of
      1 does not need testing against $1FFF. Two independent guards on one value. }
    if CanalPtr^.Period > $1FFF then
      CanalPtr^.Period := $1FFF;

    {turn the channel's period into the one the hardware wants,
      scaled by the instrument's own ratio when there is an instrument.

      THE ARITHMETIC IS HAND-WRITTEN: the pointer goes into SI throughout, and
      Turbo Pascal's code generator uses DI for every dereference it makes. Same
      tell as 0e5e, twelve instructions earlier.

      Equivalent Pascal, REFERENCE ONLY:

          CanalPtr^.RealPeriod := CanalPtr^.Period * Instrument^.NAdj
                                  div Instrument^.DAdj }
    if CanalPtr^.Instrument <> nil then
      asm
        LES     SI, CanalPtr
        MOV     AX, ES:[SI+$0b]            { 0e97  Period                    }
        LES     SI, ES:[SI+$06]            { 0e9b  -> the instrument         }
        MOV     DX, ES:[SI+$0e]            { 0e9f  PeriodMul                 }
        MUL     DX
        MOV     BX, ES:[SI+$10]            { 0ea5  PeriodDiv                 }
        DIV     BX
        LES     SI, CanalPtr
        MOV     ES:[SI+$0d], AX            { 0eaf  -> RealPeriod             }
      end
    else
    begin
      {no instrument, so there is nothing to play: the period is
        used unchanged and the channel is silenced outright. The `JMP` at 0eb3
        clears all of this, which is how the branch's real extent was found. }
      CanalPtr^.RealPeriod := CanalPtr^.Period;
      RawPtr^.Volume := 0;
      RawPtr^.Flags := RawPtr^.Flags and not rcfActiveChannel
    end;

    { **NEW IN v1.51: THE PERIOD IS CLAMPED, AND THE ARPEGGIO IS WHY IT HAS TO BE.**
      1.31b divides `NoteCalcVal` by whatever `RealPeriod` holds; 1.51 first bounds it
      to $1F..$1FFF. Nothing in 1.31b could produce a period outside the note table's
      own range, because every period came FROM the table -- but 147d:0000's rewritten
      arpeggio computes periods by dividing a 14-bit fixed point by a semitone ratio,
      and 1.51 loads S3M, whose periods are arbitrary. A `RealPeriod` of zero would
      make the `DIV BX` below fault outright.

      THE TWO BOUNDS ARE AN if/else-if AND NOT TWO if's: 12ce:115d is `JNC` past the
      low clamp to the HIGH test, and 1169 jumps over the high test entirely once the
      low one has fired. Two separate `if`s would test both every time. }
    if CanalPtr^.RealPeriod < $1F then
      CanalPtr^.RealPeriod := $1F
    else if CanalPtr^.RealPeriod > $1FFF then
      CanalPtr^.RealPeriod := $1FFF;

    {the resampling STEP for this channel: NoteCalcVal over the
      real period, rounded, then spread across the two words of a 16.16-ish
      fixed point -- `shl 4` into StepFrac and `shr 12` into StepInt.

      HAND-WRITTEN, and twice over: the pointer is in SI again, and the rounding
      (`ADD DX,DX / CMP DX,BX / JC / INC AX` -- double the remainder and compare
      against the divisor) is not something Turbo Pascal emits for `div`.

      Equivalent Pascal, REFERENCE ONLY:

          StepVal := round(NoteCalcVal / CanalPtr^.RealPeriod) }
    if not UsingGUS then
      asm
      MOV     AX, WORD PTR NoteCalcVal
      MOV     DX, WORD PTR NoteCalcVal+2
      LES     SI, CanalPtr
      MOV     BX, ES:[SI+$0d]               { 0ee9  RealPeriod                }
      DIV     BX
      ADD     DX, DX                        { 0eef  twice the remainder       }
      CMP     DX, BX                        { 0ef1  ... at least the divisor? }
      JC      @@NoRound
      INC     AX                            { 0ef5  then round up             }
  @@NoRound:
      MOV     WORD PTR StepVal, AX          { 11a0  the low half; see decl   }
      end
    else
    begin
      { **THE GUS DOES ITS OWN RESAMPLING, SO THERE IS NOTHING TO STEP.** 1.31b runs
        the divide unconditionally and throws the answer away on the GUS path; 1.51
        skips it and plants unity instead. $1000 is 1.0 in the 12-bit fixed point the
        step is kept in -- the same 4096 that `shl 4` and `shr 12` split it around
        below. }
      StepVal := $1000
    end;

    { **NEW IN v1.51 -- THE WIDE RING'S ROW IS FILLED HERE, ONE CHANNEL AT A TIME.**
      This is the producer PublishWideRow later moves whole, and it is what finally
      names the four bytes: a Word period, an instrument number, and a volume.

      IT IS A `with` AND THE FRAME PROVES IT. SeqTick is `ENTER 6` in v1.51 against
      1.31b's `ENTER 2`; two of the four extra bytes are the hidden pointer at
      [BP-6]/[BP-4] that 12ce:11c4 builds and every field store reloads with
      `LES DI,[BP-6]`. That is Turbo Pascal's `with` on an indexed record and nothing
      else looks like it.

      THE VOLUME IS SCALED BY UserVols, so what a client reads is what it would HEAR
      rather than what the tune asked for. `MUL DX` with DX loaded first puts
      UserVols on the right of the multiply. }
    { `TmpVal` AND NOT `ChanIdx` -- 12ce:11b1 loads [0330], which is this loop's own
      control variable, not ProcessNewNote's. Two Word globals a few bytes apart doing
      the same job in different routines. }
    with WideRing[WideSlot, TmpVal] do
    begin
      Period     := CanalPtr^.RealPeriod;
      Instrument := CanalPtr^.Note.Instrument;
      Volume     := CanalPtr^.Volume * UserVols[TmpVal] shr 7;

      { AND CLAMPED, STILL INSIDE THE `with` -- 12ce:1208 reloads [BP-6] rather than
        the channel pointer, so the test is on the entry just written and not on the
        channel it came from. Two 6-bit volumes multiplied give thirteen bits and the
        shift takes back only seven, so the product can exceed $3F whenever both are
        near full. }
      if Volume > $3F then
        Volume := $3F
    end;

    { `Word(StepVal)` AND NOT `StepVal` -- see the declaration. 121a and 1228 load the
      low word and shift it sixteen bits wide; the LongInt itself would go through the
      RTL and cost a CALLF apiece. }
    RawPtr^.StepFrac := Word(StepVal) shl 4;
    RawPtr^.StepInt  := Word(StepVal) shr 12;

    {which filter is in force. }
    if FilterIsOn then
      FilterVal := FilterOn
    else
      FilterVal := FilterOff;

    { **NEW IN v1.51 -- THIS IS WHERE THE RETRIGGER ACTUALLY RETRIGGERS.** MODCOMMA
      only ever sets a flag: 147d:05d8 counts ticks and raises `DoRetrig`, and
      147d:087a clears it again on the next dispatch, so it is true for exactly one
      tick. Nothing in that segment restarts a sample -- it cannot, because the sample
      machinery lives here. 12ce:124f is the reader, and `SetNewSample(.., 0)` is the
      restart.

      THE NIL TEST IS ON A POINTER AND SAYS SO: `MOV AX,ES:[DI+6] / OR AX,ES:[DI+8]`,
      both halves. A channel with no instrument has nothing to retrigger.

      OFFSET ZERO, NOT `SOffsVal`. A retrigger restarts the sample from its beginning
      even when the row also carried a 9xx -- the two commands do not compose, and
      the literal `PUSH 0` at 127a is what says so rather than anything in the docs. }
    if CanalPtr^.DoRetrig then
      if CanalPtr^.Instrument <> nil then
        { `TmpVal` again -- 12ce:1265 loads [0330], the volume loop's own counter. }
        SetNewSample(TmpVal, RawPtr^,
                     CanalPtr^.Instrument, 0);

    {and whether this channel is allowed to sound at all.

      WRITTEN AS A NEGATIVE. The test emits `JNZ` to the branch that SETS the
      bit, which is what `if not Permisos[..] then <clear> else <set>` gives; the
      positive form would put the setting branch first and jump on zero. One
      instruction decides which way round the source reads. }
    if not Permisos[TmpVal] then
      RawPtr^.Flags := RawPtr^.Flags and not rcfActiveChannel
    else
      RawPtr^.Flags := RawPtr^.Flags or rcfActiveChannel;

    {on the GUS, tell the card. A permitted channel gets its
      volume and a frequency derived from the real period; a muted one gets volume
      zero and $FFFF for the frequency, which is 12ba:0275's "leave that field
      alone" sentinel. Same constant family as NoteCalcVal's $364C0000. }
    if UsingGUS then
      if Permisos[TmpVal] then
        PostEvent(TmpVal - 1, RawPtr^.Volume,
                  $364C00 div CanalPtr^.RealPeriod,
                  PlayingSong^.ChannelPan[TmpVal])
      else
        { `-1` AND NOT `$FFFF`, for the same reason SetNewSample's calls changed:
          PostEvent's AFreq is a LongInt in 1.51, so the sentinel is two words. }
        PostEvent(TmpVal - 1, 0, -1,
                  PlayingSong^.ChannelPan[TmpVal]);

    {and hold the period inside ProTracker's range, 57 to 1712. }
    { **$1F AND $1FFF IN v1.51, WHERE 1.31b HAS PROTRACKER'S 57 AND 1712.** The
      widened bounds are the same pair the RealPeriod clamp uses and are there for the
      same reason: an arpeggio that divides and an S3M loader that supplies arbitrary
      periods both produce values ProTracker's range would reject. 1.31b could afford
      the tight bounds because every period came out of a note table. }
    if CanalPtr^.Period < $1F then
      CanalPtr^.Period := $1F
    else if CanalPtr^.Period > $1FFF then
      CanalPtr^.Period := $1FFF
  end;                                               { 0fe1..0feb  for end   }

  NullProcedure(0, 0, 0);

  {and on a non-GUS device, mix this tick's samples now that every
    channel's step and volume are set. This is the second call to MixTick in the
    routine: the first, at 0c77, runs BEFORE the row is processed and only when the
    buffer still holds samples. }
  if not UsingGUS then
    MixTick(Song)
end;

{ --------------------------------------------------------------------------
ProcessTickEntry. FAR, and the release exports it under that name.

  The whole tick, from the outside: unless execution is suppressed, either run the
  sequencer or -- if nothing is playing -- park the tick counter at 1, and then
  hand control to whatever tick procedure has been installed.

  `ModTickProc` is told whether this is the row's FIRST tick, computed as
  `TickInRow = 0` with the `MOV AL,0 / JNZ / INC AX` that Turbo Pascal emits for a
  Boolean expression.
  -------------------------------------------------------------------------- }
procedure ProcessTickEntry;
begin
  if DontExecute then
    Exit;

  if not Playing then
    TickInRow := 1
  else
    SeqTick(PlayingSong^);

  if ModTickProcValid then
    ModTickProc(PlayingSong^, TickInRow = 0)
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
  IdleGiver := nil
end;

function BufferGiver : PSampleBuffer; far;
begin
  BufferGiver := nil;

  { AN EARLY `Exit`, NOT A WRAPPED `if`. The test emits `JNZ +2 / JMP` with the
    jump landing on the epilogue at 1099 -- the un-folded pair this project's own
    notes list as the tell. Written as `if InUse then begin ... end` the compiler
    folds it into a single `JZ`, because the body is only 34 bytes and well within
    short range. }
  if not Buffers[BuffGive].InUse then
    Exit;

  BufferGiver := @Buffers[BuffGive];
  Inc(BuffGive);
  if BuffGive > 1 then
    BuffGive := 1
end;

{ --------------------------------------------------------------------------
start playing a module. IN PROGRESS.

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
    CLI
  end;

  { NEW IN v1.51, and it is the first thing PlayStart does after the CLI. Publishing
    the channel count is what makes the thirty-two `ChansTrig` flags above it
    readable -- without it a client cannot tell an idle channel from one the song
    does not have. The bindings describe them as being for VU meters, which is
    exactly what needs to know how many bars to draw. }
  CtrlBlock.NumChannels := Song.NumChannels;

  PlayingSong := @Song;

  RangeStart := ReqStart;
  RangeEnd   := ReqEnd;
  MySongLen   := ReqLen;

  if MySongLen = 0 then
    MySongLen := Song.SequenceLength;

  if RangeStart = 0 then
    NextSeq := 1
  else
    NextSeq := RangeStart;

  if NextSeq > MySongLen then
  begin
    asm
      STI
    end;
    Exit
  end;

  {an unset END comes from the song too, but only if the song's own
    figure is set AND fits inside the length. Three tests, short-circuited. }
  if (RangeEnd = 0) and (Song.SequenceRepStart <= MySongLen) and
     (Song.SequenceRepStart <> 0) then
    RangeEnd := Song.SequenceRepStart;

  {whether the module may loop.

    THE `True and` IS IN THE ORIGINAL. 1121 loads an IMMEDIATE 1 and tests it, so
    the first operand is the literal, not a variable -- a typed constant would be
    `MOV AL,[addr]` as ForceLoopMod's own test is at 112e -- so what is folded here
    is an UNTYPED Pascal constant, which becomes a literal, where a typed one stays
    a memory read. That distinction is what the immediate proves.

    AND THE GROUPING IS `(True and A) or B`, not `True and (A or B)`. The `JZ` at
    1125 lands on B's test at 112e rather than on the false path, so a failing
    first operand still tries B. Written the other way round the jump would clear
    both tests -- seven bytes against fourteen, which is how it was caught. }
  MyLoopMod := (True and (RangeEnd <> 0)) or ForceLoopMod;

  {and reset the playing state. `TickInRow := $FE` is a sentinel:
    two short of zero, so the first two ticks pass before a row is due. }
  TickInRow  := $FE;
  CurSpeed   := Song.InitialTempo;
  CurTempo   := Song.InitialBPM;
  TickCount  := 0;
  NextNote    := 1;
  ModFlag    := False;
  MuestrasPerTick := 1;

  MaxSplPerTick := MaxOutputFreq div TicksPerSecond;

  if RangeEnd < NextSeq then
    RangeEnd := NextSeq;

  {prime the first row and the queue that hands it on. The stores
    land on $1220, $1221, $1222, $1223 and then an 8-byte Move to $1224, which is
    NoteBuff[0]'s EoMod, Tempo, NotePlaying, SeqPlaying and Volume -- the layout
    fixed at 12ba:094b, confirming itself from a different routine. `$125c` is its
    NMuestras at +$3c. Tempo starts at 6, ProTracker's default. }
  NoteBuff[0].EoMod       := False;
  NoteBuff[0].Tempo       := 6;
  NoteBuff[0].NotePlaying := 0;
  NoteBuff[0].SeqPlaying  := 0;
  NoteBuff[0].Volume := UserVols;                  { 119e..11ae  see 075e    }
  NoteBuff[0].NMuestras   := 0;

  NoteHd        := 0;
  NoteTl        := 0;
  NoteSound     := @NoteBuff[0];
  NoteProcessed := @NoteBuff[0];

  {clear the channels, then give each one a starting note.

    THE `with` IS THE ORIGINAL'S, not a convenience. 11f7..11fa is
    `MOV [BP-8],DI / MOV [BP-6],DS` -- the register the offset was accumulated in,
    then DS -- and every field store below reloads it with `LES DI,[BP-8]`. A
    pointer local instead would need a pointer VALUE and give
    `LEA AX,[DI+123a] / MOV DX,DS / MOV [BP-8],AX / MOV [BP-6],DX`. The slot is
    the compiler's, which is why the frame has four bytes this routine never
    declares.

    AND `ADD DI,123A` IS BASE-1: the array really starts at $1260, one 38-byte
    element above the base the compiler indexes from. }
  FillChar(Canales, SizeOf(Canales), 0);

  for i := 1 to MaxChannels do
    with Canales[i] do
    begin
      Note.Period     := 800;
      Note.Instrument := 1;
      Note.Command    := mcNone;
      Period          := 800
    end;

  {and size a buffer. `SHL AX,3 / SHL AX,1` is `* MaxChannels * 2`
    with MaxChannels folded to 8; the compiler reaches for shifts because both
    factors are powers of two, and the PAIR of them is what fixes the 8. }
  SizeOfABuffer := MaxSplPerTick * MaxChannels * 2;

  FillChar(Buffers, SizeOf(Buffers), 0);

  { 123d..1298 -- claim the mixing buffers, but only when the GUS is not driving.
    The GUS plays out of its own on-card memory and never asks for one.

    THE FILL VALUE IS 0 AND THE RELEASE'S IS $7F. Both are silence for their own
    sample format -- $7F is mid-scale for unsigned 8-bit, 0 for signed 16-bit --
    so this is 1.31 filling a Word buffer where 1.39b fills a byte one. The
    immediate at 1292 is `6A 00`; there is nothing to interpret. }
  if not UsingGUS then
    for i := 1 to NumBuffers do
    begin
      {a VIRTUAL call on the heap object at DS:$39ae, through
        `[DI+8]`, which is virtual method number two. See HEAPS.PAS, which is a
        stub for segment 17cf and exists to put HGetMem in that slot.

        `ADD DI,1390` is base-1 AND field-folded: $1394 - 11 + 7 is $1390, so the
        one expression carries the array's base and `IData`'s offset inside the
        record together. }
      FullHeap.HGetMem(Buffers[i].IData, SizeOfABuffer);

      if Buffers[i].IData = nil then
      begin
        Song.Status := msOutOfMemory;
        PlayStop;
        asm
          STI
        end;
        Exit
      end;

      FillChar(Buffers[i].IData^, SizeOfABuffer, 0)
    end;

  BuffIdx  := 1;
  BuffGive := 1;

  {and clear both per-channel tables. The EventRing clear is
    1.31's own; the release only clears RawChannels here. }
  FillChar(EventRing, SizeOf(EventRing), 0);
  FillChar(RawChannels, SizeOf(RawChannels), 0);

  {program the hardware for the rate that was asked for, and only
    then let the timer back in. Everything above this point runs under the `CLI`
    from 10a5. }
  ChangeSamplingRate(DesiredHz);

  asm
    STI
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
  SetBufferAsker(IdleGiver);

  if UsingGUS then
    DontExecute := True;

  MyCanFallBack := False;
  Playing       := True;

  if UsingGUS then
    SetGusChannels(Song.NumChannels);

  StartSampling;
  DontExecute := False;

  SetBufferAsker(BufferGiver);

  PleaseFallback := 0;
  MyCanFallBack  := CanFallBack
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
  DesiredHz := Hz;
  MyHz := TGetFreqProc(ActiveDevice^.GetRealFreqProc)(Hz);

  {more samples per second than a tick can hold. The product is
    computed into AX and compared against MyHz, which is why it reads as the
    right-hand side here. }
  if MyHz > MaxSplPerTick * TicksPerSecond then
  begin
    Dec(Hz, 100);
    goto Otra
  end;

  if MyHz < 1000 then
  begin
    Inc(Hz, 100);
    goto Otra
  end;

  if MyHz <> ActualHz then
  begin
    ActualHz := MyHz;

    {`MOV SI,AX / SHL AX,1 / ADD AX,SI / SHR AX,1` is
      `TicksPerSecond * 3 div 2` and nothing else: AX becomes T, 2T, 3T, then 3T
      div 2. The release's line carries two commented-out alternative divisors
      beside it, an 8 and a DIV 3, so the ratio was tuned by hand; 1.31's shifts
      fix it at three halves. }
    SetPeriodicProc(ProcessTickEntry, TicksPerSecond * 3 div 2);

    {and size the DMA buffer from the rate. Stereo gets the whole
      figure and mono half of it, then the result is rounded DOWN to a multiple of
      four by `AND AX,FFFC` -- four bytes being one stereo 16-bit frame, which is
      the smallest unit the 8237 may stop on. }
    if Stereo then
      DMABufferSize := ActualHz
    else
      DMABufferSize := ActualHz div 2;

    DMABufferSize := DMABufferSize and $FFFC;

    {reprogram the controller, unless there is no channel to
      program. `$FF` IS THE "NO DMA" SENTINEL, and it is compared as a WORD
      (`81 3E C4 0B FF 00`, six bytes) rather than a byte, which is what settles
      DMAChannel's width -- see the note beside its declaration in SOUNDDEV.

      Mode $58 is single-mode, address-increment, auto-initialise, read (the
      8237 reading memory to feed the card), which is what a continuously
      circling playback buffer needs. }
    if DMAChannel <> $FF then
      DMASet(DMAChannel, $58, DMABuffer, DMABufferSize);

    {and resynchronise the tick gate, because the rate the mixer
      is paced against has just moved. `Ticks` is VTSilenc's and exported;
      TickSnapshot is the copy SeqTick compares it with at 0c52. }
    TickSnapshot := Ticks
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
  { **NEW IN v1.51, AND IT IS A DEBUGGING LINE THE RELEASE LEFT IN.** 12ce:174c
    writes a four-character string at CS:$1743 -- `04 'S' 't' 'o' 'p'`, a Pascal
    short string sitting in the code segment -- and then calls SYSTEM's WriteLn.

    NO FILE VARIABLE, WHICH IS WHY IT IS `Output`. The Text pushed is DS:$6890, and
    that is NOT VTShell's `ConFile`: ProgName measures at $5e38 in 1.51 against
    $3ade in 1.31b, a shift of $235a, which would put ConFile at $5d38. $6890 is
    further on and is what a bare `WriteLn` uses.

    So a released player prints "Stop" every time a module ends. Transcribed because
    it is there. }
  WriteLn('Stop');

  Playing := False;

  { The idle asker returns nil, so anything still asking for a buffer while this
    unwinds is told there is nothing to play. }
  SetBufferAsker(IdleGiver);

  if not UsingGUS then
    for i := 1 to NumBuffers do
      FullHeap.HFreeMem(Buffers[i].IData, SizeOfABuffer)
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
  Playing   := False;
  LoopMod   := False;
  ActualHz  := 0;

  if FilterIsOn then
    FilterVal := FilterOn
  else
    FilterVal := FilterOff;

  { Every voice at full volume, every channel permitted, no filter history. }
  FillChar(UserVols, SizeOf(UserVols), 255);
  FillChar(Permisos, SizeOf(Permisos), True);
  FillChar(SplBuf,   SizeOf(SplBuf),   0);

  FillChar(EventRing, SizeOf(EventRing), 0);
  FillChar(NoteRing,  SizeOf(NoteRing),  0);

  { NEW IN v1.51 -- the wide ring and its flag grid are cleared here with the narrow
    one, and the two immediates confirm both shapes independently of the routines
    that use them: `PUSH 0C80h` is 3,200, which is 25 rows of 128 bytes, and
    `PUSH 0320h` is 800, which is 25 rows of 32. }
  FillChar(WideRing,  SizeOf(WideRing),  0);
  FillChar(WideHit,   SizeOf(WideHit),   0)
end.
