{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  THE PLAYER. Everything between a loaded module and sound coming out of the
  card is in this unit: it walks the pattern data in time, decides what each
  channel should be doing, and turns that into a stream of samples.

  IT IS THE BIGGEST UNIT IN THE PROGRAM, and it is big because it sits at the
  junction of three different clocks.

    * THE MUSIC'S CLOCK: rows, ticks and the tempo that converts between them.
      One row every few ticks, one tick every few milliseconds.
    * THE MIXER'S CLOCK: samples. Each channel is a sample being stepped
      through at its own rate, and the rates have nothing to do with each other
      or with the tick.
    * THE HARDWARE'S CLOCK: buffers. The card asks for a block of samples when
      it is ready and will not wait, so the mixer must always be far enough
      ahead to answer.

  THE MIXING KERNEL IS NOT HERE. It is hand-written assembler in PLAYMOD.ASM,
  linked in as an external, because mixing is where every cycle shows: it is
  the one routine that touches every sample of every channel.

  AND IT DRIVES TWO KINDS OF HARDWARE THAT WANT OPPOSITE THINGS. A
  SoundBlaster has one DMA channel, so this unit must mix all the voices into
  one stream itself. A Gravis Ultrasound has 32 voices of its own and wants to
  be TOLD what to play, not handed the result -- so for the GUS the same
  sequencer output goes down a different path entirely: instead of samples, it
  publishes a table of what changed on each row, and the GUS driver turns those
  into voice commands. Two output paths from one sequencer, which is why so
  much of this unit is about publishing state rather than producing sound.

  ROWS ARE PUBLISHED AHEAD OF TIME, and that is the shape to hold on to. The
  mixer runs ahead of what is audible by a whole buffer, so "what the music is
  doing now" and "what the mixer is working on" are different rows. Anything
  that has to line up with what a listener HEARS -- the GUS, the demo's own
  cues, the display -- reads from a ring of published rows rather than from the
  sequencer directly.

  [re] Segment 12ba -- 5,968 bytes, the largest thing in the program after the
  program itself.

  [re] NAMES ARE THE 1.39b RELEASE'S. `LIB/PLAYMOD.PAS` is the later version of
  this unit and the pairing is confirmed rather than assumed:

    12ba:0007  UnCanal          the release's routine, statement for statement
    12ba:0664  MyMove           a hand-written Move, ASSEMBLER in both
    12ba:1600  DumpInstrument   the resampling kernel, EXTERNAL from PLAYMOD.ASM

  and `TModRawChan`'s FIELD LAYOUT lands on every offset the reading pass had
  already recorded -- `+$0b` the non-looping limit, `+$19` and `+$1b` the 16.16
  step, `+$1d` the byte handed to the kernel, `+$1e` and `+$20` the loop, 34
  bytes in total. That is why it is adopted here and `TSong`'s was not: this one
  is CONFIRMED by the binary, field by field, and 1.39b's `TSong` demonstrably
  did not fit.

  [re] `+$1d` IS THE VOLUME, which the reading had left open as "step or volume,
  the kernel at 12ba:1600 would say". The release passes `Raw.Volume` in that
  argument position, and the DumpEmpty call at `12ba:012c` passes a literal 0
  there, which only makes sense for a volume.

  [re] `+$19`/`+$1b` ARE THE STEP, NOT THE POSITION. The reading called them
  "sample position, low word of a 16.16 fixed point". They are
  `StepFrac`/`StepInt`, the per-sample INCREMENT; the position is
  `SplPosFrac`/`SplPosInt` at `+$01`/`+$03`. The arithmetic is the same either
  way, which is why reading alone could not separate them.

  [re] AND ONE THING THE DISASSEMBLY SETTLED AGAINST THE RELEASE. 1.39b has two
  kernels, `DumpInstrument` and `DumpEmpty`. 1.31 has ONE, at `12ba:1600`, with
  a final Boolean argument -- `6a 00` at `009b` and `0111`, `6a 01` at `016f`.
  The release split it in two later. The release settles shapes and names; the
  disassembly settles what is actually there.
  =========================================================================== }
unit PlayMod;

{ $G+ for the 286 instructions, as everywhere else in this tree. }

interface

{ THE SEQUENCER'S POSITION AND SPEED ARE DECLARED IN MODCOMMA, not here, even
  though this unit does the sequencing. The effect commands WRITE those
  variables -- a Bxx jumps to another pattern -- and this unit `uses`
  ModCommands, so the dependency only runs one way. See the note above their
  declaration there.

  [re] Nine of them moved out of this file, and the DGROUP LAYOUT is what moved
  them:

      MyLoopMod  $0334    TempoDiv  $0336 (release: BPMDivider)
      TempoAccum $033a    RangeStart $033c   RangeEnd $033e
      ReqStart   $0342    ReqEnd    $0344    ReqLen   $0346    TickInRow $034e

  Their addresses INTERLEAVE with `MySongLen` at $0340, `FilterIsOn` at $0348
  and the tempo pair, which were already ModCommands' -- and two units' data
  cannot interleave, because the linker lays DGROUP down one unit at a time in
  link order. Nothing about the code changes -- a DGROUP reference is a linker
  fixup either way -- so PLAYMOD still verifying identical with the same 1,187
  pending fixups was the check. }

{ [re] VTSilenc IS NOT A DEPENDENCY, AND THE LINK ORDER IS WHAT SAYS SO. It was
  listed here for one identifier, `Ticks`, which is SoundDevices' now. The
  original's segment addresses put `1065`/VTSilenc at the very END of the unit
  order and `12ba`/PlayMod in the middle, and TP6's order is reverse DFS
  post-order over the `uses` graph, so a dependency in this direction is
  impossible. `linkorder.py` checks every edge in the tree against it. }
uses
  SongUnit, SongElements, SoundDevices, VTCtrl, GUS, ModCommands, Filters,
  Heaps, Hardware;

{ --------------------------------------------------------------------------
  THE RAW CHANNEL: what the MIXER needs, as opposed to what the music means.
  There is one of these per voice, and it is deliberately dumb -- no notes, no
  commands, no instruments, just a pointer walking through memory at a rate.
  The sequencer decides what should happen; this record is the instruction the
  mixer gets, and it is shaped so the kernel can run without a single decision
  it does not have to make.

  THE POSITION IS 48 BITS: a segment, an offset, and a FRACTION. Playing a
  sample at any pitch other than its own means stepping through it by a
  non-whole amount per output sample, so the position has to carry a fraction
  and the step is a 16.16 fixed-point number added to it every sample. That one
  representation is the whole of pitch on a SoundBlaster.

  THE SAMPLE IS DESCRIBED THREE TIMES, and that is a real-mode problem showing
  through. A sample longer than 64K cannot be addressed as one block, so it is
  split in two parts, each with its own segment, offset and limit -- and the
  third triple is whichever part is CURRENTLY being played, copied into place
  so the kernel only ever reads one. Swapping parts is a few stores when the
  first runs out, instead of a test in the inner loop.

  [re] 34 bytes, one per voice, DS:$13a6 upward; $1384 is the base-1 base the
  compiler indexes from, not the array's address. Names and layout are
  `LIB/PLAYMOD.PAS`'s. Every offset below was already recorded from the
  disassembly; the release supplied the names and the three fields nothing had
  touched yet.
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
  THE EVENT RING: cues waiting to be heard. The mixer runs a buffer ahead of
  the speaker, so a cue written by the sequencer has not happened YET -- it
  belongs to sound that is mixed but not yet played. Holding cues in a ring,
  one row per buffer, lets them be released at the moment the sound they
  belong to actually reaches the listener.

  THAT DELAY IS THE WHOLE REASON THE RING EXISTS. Without it a demo would cut
  its visuals a buffer early, which at these buffer sizes is plainly visible.

  [re] DS:$14b6, 400 bytes, 25 rows of 8 entries; `12ba:0202` posts and
  `12ba:0187` consumes. Two bytes per entry and both are read: `+$01` is the
  marker the consumer tests and `+$00` an index into the published control
  block. No counterpart in the 1.39b release, so these names are ours.
  -------------------------------------------------------------------------- }
const
  { HOW MANY VOICES THE PLAYER WILL MIX. Not a format limit -- a four-channel
    MOD and a sixteen-channel S3M both fit -- but a cost limit: every extra
    channel is another pass over every output sample.

    THREE DIFFERENT WIDTHS LIVE IN THIS BUILD AT ONCE, and they are not the
    same number by accident. The player mixes sixteen; the published row
    describes thirty-two, because publishing costs almost nothing and a wider
    row outlives this player's limits.

    [re] SIXTEEN IN v1.51, EIGHT IN 1.31b, AND `TPlayingNote`'s SIZE IS THE
    PROOF. 12ce:07e9 is `IMUL DI,[02fc],77h` where 1.31b has `IMUL DI,..,3Fh`,
    and 0807 pushes `6A 77` where 1.31b pushes `6A 3F` -- so the record is 119
    bytes against 63. 1.39b's field list makes that arithmetic decisive: four
    fixed bytes, then `Volume : TVolumes` which is one byte a channel, then
    `Note` which is a 6-byte TFullNote a channel, then a Word and a filler.
    119 - 7 is 112, and 112 divided by seven is 16. No other channel count gives
    119. The release's own SOUNDDEV says `MaxChannels = 32`; DemoVT 1.51 went
    half way. }
  MaxChannels = 16;

type
  { A NAMED type on purpose: Turbo Pascal will only assign one array to another
    when both are the SAME named type, and two places in this unit copy a whole
    set of channel volumes in one statement. Declared anonymously they would
    have to be `Move` calls instead.

    [re] 12ba:075e and 12ba:119e are those assignments -- see the note at each.
    Reading them as `Move` was what the anonymous declaration forced. }
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


  { [re] THE SAMPLE BUFFERS, DS:$1394. NOT A NEW RECORD: this is
    `SoundDevices.TSampleBuffer`, already declared in SOUNDDEV with these exact
    offsets -- InUse, NSamples, RateHz, Channels, DataType, IData, eleven bytes.
    It was transcribed here first as an invented `TModEntry` with the offsets
    right and every name wrong, and 12ba:1049 is what exposed that: a far
    function returning a pointer to one of these with no arguments is
    `SoundDevices.TAskBufferProc`, the driver's buffer callback.

    [re] The release confirms the rest: `Buffers : ARRAY[1..NumBuffers] OF
    TSampleBuffer` with `NumBuffers = 3`, and `BuffIdx, BuffGive : WORD` --
    "Tail of the buffer" and "Head of the buffer" -- which are DS:$1390 and
    DS:$1392. AND `InUse` SETTLES THE FLAG SENSE INDEPENDENTLY: 12ba:0b57 exits
    when it is non-zero, which the reading notes had backwards. }

  { The buffer's data is declared as an untyped Pointer and used as an array of
    16-bit samples; this is the type that makes the second view legal.

    [re] 12ba:0b98 dereferences it and adds `(MixChan-1)*2`. }
  PWordArray = ^TWordArray;
  TWordArray = array[0..0] of Word;

  { A PUBLISHED ROW: everything about one moment of the music, in one record,
    for anybody who is not the mixer. The player fills one of these as it
    crosses a row and posts it; the GUS driver, the display and the demo all
    read from the posted copy rather than from the player's own variables.

    THAT SEPARATION IS THE POINT. The player's variables are always ahead of
    what is audible, and they change under an interrupt. A published row is a
    snapshot, complete and consistent, tied to a moment that will arrive. }
  PPlayingNote = ^TPlayingNote;
  { [re] Every field is confirmed against the binary. The last one to fall was
    `Note`: 12ba:094b computes `ChanIdx*6 + 6` and adds it to the record's
    address, which is Turbo Pascal's base-1 indexing of an `array[1..8] of
    TFullNote` starting at +$0c. That fixes the whole layout, and the total is
    exactly 63 bytes in 1.31b. IT IS THE RELEASE'S FIELD LIST IN THE RELEASE'S
    ORDER: EoMod, Tempo, NotePlaying, SeqPlaying, Volume, Note, NMuestras, fill.
    1.39b's record is 32 bytes because its own `MaxChannels` differs. Same
    shape, different width -- which is why the fields carry over and the SIZE
    does not. }
  TPlayingNote = record
    EoMod       : Boolean;      { +$00                                       }
    Tempo       : Byte;         { +$01                                       }
    NotePlaying : Byte;         { the row this snapshot is of              }
    SeqPlaying  : Byte;         { and the order position it came from      }
    Volume      : TVolumes;     { every channel's volume                   }
    Note        : array[1..MaxChannels] of TFullNote;   { and every note   }
    NMuestras   : Word;         { the release's name; unused so far        }
    Fill        : Byte;

    { [re] +$02 and +$03 are written from NextNote and NextSeq at 12ba:074a and
      12ba:0754; Volume at +$04 is assigned from UserVols; Note is +$14 in
      v1.51, +$0c in 1.31b; NMuestras +$3c, Fill +$3e. }
  end;

{ --------------------------------------------------------------------------
  THE GUS EVENT RING: the same delayed-release idea as the cue ring, but
  carrying voice commands. A Gravis card plays its own samples out of its own
  memory, so it is not handed audio -- it is handed instructions. Those
  instructions still have to arrive when the sound they belong to would have
  been heard, so they queue in a ring exactly as the cues do.

  ONE ENTRY IS ONE `TriggerVoice` CALL, ALREADY PACKED. Everything the driver
  needs -- volume, frequency, pan, and the three addresses that define the
  sample and its loop -- sits in one 18-byte slot, so flushing a row is
  reading the fields back out in order and calling. No decisions at flush time.

  [re] DS:$1646, 3,200 bytes, 25 rows of 8. THE FIELDS ARE `1723.TriggerVoice`'s
  PARAMETER LIST, which is what identified them. `12ba:02ea` flushes a slot by
  passing `+$0c`, `+$08`, `+$06`, `+$04`, `+$03`, `+$01`, `+$00` and the voice
  number straight into `TriggerVoice(Voice, Vol : Byte; Freq : LongInt; Pan :
  Byte; StartA, LoopA, EndA : LongInt)`, and every size lines up. Names are
  ours: there is no counterpart in the 1.39b release, whose GUS support was
  rebuilt elsewhere.
  -------------------------------------------------------------------------- }
type
  { `Freq` IS 32 BITS BECAUSE THAT IS WHAT THE DRIVER TAKES. Storing it any
    narrower means widening it again at every flush, and the flush runs under
    an interrupt; carrying the driver's own width costs two bytes a slot and
    nothing else. It also gives the flush a free emptiness test -- a slot with
    no frequency in it is a slot with nothing to do.

    [re] EIGHTEEN BYTES IN v1.51, SIXTEEN IN 1.31b. 12ce:02de is `IMUL AX,AX,12h`
    where 1.31b has `SHL AX,4`; 12ce:0305/0309 store a WORD PAIR into +$1 and +$3
    from [BP+12] and [BP+14], where 1.31b stored one word. Every field after it
    moves up two, and FlushEventRow's free-slot test at 12ce:0413 is `MOV
    AX,ES:[DI+1] / OR AX,ES:[DI+3]` -- a 32-bit zero test, which it could not
    have been while Freq was a Word. 1.31b's flush had to `XOR DX,DX` before
    passing Freq to TriggerVoice; 12ce:043e pushes +$3 and +$1 straight
    through. }
  TGusEvent = record
    Vol    : Byte;              { +$00                                       }
    Freq   : LongInt;           { +$01  a Word in 1.31b                      }
    Pan    : Byte;              { +$05                                       }
    StartA : LongInt;           { +$06                                       }
    LoopA  : LongInt;           { +$0a                                       }
    EndA   : LongInt;           { +$0e  the flush tests this for the long form }
  end;
const
  { How many GUS voices a queued row can describe. It happens to equal
    `MaxChannels`, and it is declared separately anyway: one is what this player
    will mix and the other is what that card can be told, and nothing requires
    them to stay equal.

    [re] 12ce:02e1 multiplies the row index by $120, and $120 divided by the
    18-byte event is 16. The two were measured from different instructions. }
  GusVoices = 16;

type
  { [re] SIXTEEN VOICES IN v1.51 AND EIGHT IN 1.31b. 12ce:02e1 multiplies the
    row index by $120 -- 288, which is 16 x 18 -- and FlushEventRow's loop closes
    on `CMP [02f8],0Fh`, so the last voice is 15. }
  TGusEventRow = array[0..GusVoices - 1] of TGusEvent;   { 288 bytes            }

{ [re] THE CHANNEL STATE, DS:$1260. `TCanal` and `TFullNote` ARE the release's,
    head for head, and 12ba:0820 proves it: the four stores in that loop land on
    `Note.Period`, `Note.Instrument`, `Note.Command` and `Period`, at +$01, +$00,
    +$04 and +$0b, which is exactly where `TFullNote` (Instrument, Period,
    Volume, Command, Parameter -- six bytes) followed by `Instrument :
    PInstrumentRec`, `Volume` and `Period` puts them. And `Period := 800` twice
    is a ProTracker period, not a coincidence. The record itself is declared in
    MODCOMMA, which is where the effects that give its fields meaning live. }



const
  RingRows = 25;

  { THE PUBLISHED ROW IS TWICE AS WIDE AS THE PLAYER. Publishing costs a table
    entry; mixing costs a pass over every sample. So the row that goes out to
    the display and the demo describes thirty-two channels even though this
    player will only ever sound sixteen -- the ring outlives the limit.

    [re] NEW IN v1.51. 12ce:0243's `SHL DI,5` fixes the flag grid at 32 bytes a
    row and 12ce:0258 stops the loop at 20h. Both ring widths are live at once:
    the narrow ring at 0183 and the wide one at 0202 run back to back. }
  WideChans = 32;



  { ONE BUFFER, WHERE THE RELEASE USES THREE. More buffers mean more latency
    between a note being mixed and being heard, and this player is driving a
    demo: everything on screen is cut to the music, so the delay is visible as
    well as audible. One buffer is the tightest the hardware allows.

    [re] The release's name. `NumBuffers` is 1 against the release's 3 -- see
    the note beside Buffers. `MaxChannels` is used as a MULTIPLIER at 12ba:1224,
    where `MaxSplPerTick * MaxChannels * 2` folds to a pair of shifts, so the
    byte confirms its value. }
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
  THIS UNIT'S GLOBAL STATE, IN ONE BLOCK. What the player is playing, what the
  output hardware can do, and where the published rows have got to.

  THE ORDER OF THESE LINES IS THE MEMORY LAYOUT, which is why they are one
  block and not six scattered ones. Turbo Pascal lays a unit's typed constants
  down in declaration order, so moving a declaration moves an address --
  something that does not show up until the program is linked.

  [re] $02c4..$0333, in address order. It used to be six separate `const` and
  `var` sections scattered down the file, and that was invisible until the
  program linked. **DGROUP is laid out per unit in LINK order and, within a
  unit, in DECLARATION order**, with a unit's TYPED CONSTANTS in one region and
  its plain vars in another -- so a var here is not a slower constant, it is a
  variable in a different part of DGROUP entirely. `dgroup.py` measures it.

  [re] EVERY VALUE IS READ OUT OF THE ORIGINAL'S IMAGE, never taken from the
  release, and one of them differs: `MaxOutputFreq` is 44000 here and 45000 in
  1.39b. `MaxSplPerTick` agrees at 880 and the pan table agrees byte for byte.

  [re] THE RELEASE SETTLED THE ORDER AND THE ADDRESSES CONFIRMED IT, sixteen at
  a time: `LIB/PLAYMOD.PAS`'s interface declares PlayingSong, LoopMod,
  ForceLoopMod, CanFallBack, FilterOn, FilterOff, FilterIsOn, MaxOutputFreq,
  DontExecute, Playing, ModTickProcValid, NoteTl, NoteHd, NoteSound,
  NoteProcessed, MaxSplPerTick in that sequence, and every one lands on an
  address an instruction in this segment already named. `AltMode` at $02d1 is
  the single insertion 1.31 makes -- it has no counterpart in the release, which
  fits what it is for, the INCONEXI.EXE rename.

  [re] FOUR RUNS ARE UNIDENTIFIED AND ARE DECLARED AS FILLER, NOT INVENTED AS
  VARIABLES. The addresses either side of each are measured and the block is
  contiguous, so the bytes certainly exist; what is not known is what they are
  called. Filler keeps the SIZE honest and says plainly that the name is
  missing. $0308 is the interesting one: it is the only non-zero pair in the
  unidentified set, and it holds 1.
  ========================================================================== }
const
  PlayingSong      : PSong         = nil;      { the module, or nil            }
  LoopMod          : Boolean       = True;     { nothing reads it              }
  ForceLoopMod     : Boolean       = False;    { the ForceLoopMod key          }
  CanFallBack      : Boolean       = True;     { may a cheaper mixer be used?  }

  { WHICH MIXING KERNEL EACH FILTER SETTING SELECTS. The Amiga's low-pass
    filter has no equivalent on a PC, so it is emulated by choosing a different
    kernel; these two say which. }
  FilterOn         : TFilterMethod = fmNone;
  FilterOff        : TFilterMethod = fmNone;

  { [re] DS:$02ca, $02ce, $02cf, $02d0, $02d1, $02d2. 12ba:1325 reads
    CanFallBack; the ForceLoopMod, FilterOn and FilterOff keys write three of
    the others. }

  { THE FILTER AS THE MIXER HAS IT. There are two variables of this name in
    the program: this one is what the mixer is DOING, and ModCommands' is what
    the E0x command last ASKED for. Whoever means one must not silently get the
    other, which is why every reference outside this unit qualifies it. }
  FilterIsOn       : Boolean       = False;

  { The ceiling on the output rate, in Hz. Higher costs proportionally more
    mixing per second of sound, so this is where quality is traded for CPU. }
  MaxOutputFreq    : Word          = 44000;

  DontExecute      : Boolean       = False;
  AltMode          : Boolean       = False;    { 1.31 onwards                  }
  Playing          : Boolean       = False;
  ModTickProcValid : Boolean       = False;

  { THE PUBLISHED-ROW RING'S THREE CURSORS. `NoteHd` is where the sequencer is
    writing, `NoteTl` where the oldest unread row sits, and the two pointers
    name the row the SOUND has reached and the row the demo has already dealt
    with. Four positions into one ring, because four different things are
    reading it at four different delays. }
  NoteTl           : Word          = 0;
  NoteHd           : Word          = 0;
  NoteSound        : PPlayingNote  = nil;
  NoteProcessed    : PPlayingNote  = nil;

  { The most samples one tick may produce -- what sizes the mix buffer. }
  MaxSplPerTick    : Word          = 880;

  { [re] DS:$02d3..$02e6. `FilterIsOn` is NOT ModCommands' at DS:$0348; 1.31 has
    two, and so does the release, which declares one in each of the same two
    interfaces. Both are exported because the ADDRESS requires it: $02d3 sits
    between two interface globals, and a unit's implementation declarations all
    come after its interface ones. THE ADDRESS IN THAT ARGUMENT WAS $02cd UNTIL
    THE LINKER WAS ASKED -- prose that argues FROM an address reads as
    corroboration for it. MaxOutputFreq is `ab e0`, 45000 in the release;
    MaxSplPerTick is `03 70` and agrees. }

  { THE RING CURSORS. A ring buffer needs a producer and a consumer, and the
    GUS ring has three sets of them because three different things write and
    read it at three different points in the delay.

    THE CONSUMER STARTS ONE SLOT AHEAD OF THE PRODUCER, not level with it. A
    ring that is empty and a ring that is full look identical when both cursors
    coincide; leaving one slot of daylight makes the two states distinguishable
    without a separate count, at a cost of one wasted slot. }
  RingSlot         : Word          = 0;        { the producer's cursor         }
  FlushSlot        : Word          = 1;        { the consumer's                }

  Rest             : Word          = 0;
  EventSlot        : Word          = 0;
  EventChan        : Word          = 0;

  { The wide ring's own three, for the 32-channel published row. }
  WideSlot         : Word          = 0;
  WideChan         : Word          = 0;
  WidePrev         : Word          = 0;

  RingVoice        : Word          = 0;
  NewFlags         : Byte          = 0;
  NoLoop           : Byte          = 0;
  NextIdx          : Word          = 0;
  ChanIdx          : Word          = 0;

  { [re] DS:$02e8..$02fe. THE ORDER OF THIS RUN IS MEASURED, AND IT IS NOT
    1.31b's: every address is named by an instruction in 12ce, and declaration
    order is the only thing that can put them there. 1.31b runs Rest, EventSlot,
    EventChan, then the ring pair; 1.51 puts the ring pair FIRST, moves the wide
    ring's three in ahead of RingVoice, and leaves RingVoice where
    FlushEventRow's loop names it. The wide three are named by 12ce:0206, 023c
    and 02cd; RingVoice by FlushEventRow's loop.

    [re] `FlushSlot`'s INITIALISER IS WHY THAT WAS NOTICED. Setting it to 1
    changed no byte of the image, because the declaration sat at the wrong
    address -- `dgroup.py` went from 164 blocks in place to 163 and one MOVED,
    which is the only reading that says "right content, wrong place". Two
    independent places give the value: DGROUP holds `01 00` at $02ea in the
    original's initialised image, and 1000:02b0 sets it again at run time with
    `MOV word [02ea],1` beside `RingSlot := 0`.

    [re] ~~Pannings~~ IS GONE IN v1.51 and the previous commit's guess never had
    to be resolved. The original's DGROUP has `00 00 01 00` at $02e8 where ours
    had the table, and MODCOMMANDS' block starts 20 bytes lower than ours --
    sixteen of which are exactly this. All three readers had moved to
    `PlayingSong^.ChannelPan`, so the declaration was the only thing keeping it
    alive, and Turbo Pascal emits a typed constant whether or not anything reads
    it. A dead typed constant is invisible to every code comparison and sixteen
    bytes wide in the layout. 1.31b's values were $40, $b0, $b0, $40, $40, $b0,
    $b0, $40 -- a third of the way in from each side, in the L R R L L R R L
    pattern the Amiga uses; 1.51 gets the same effect from the song's own
    per-channel pan, which is where the release always had it. }

  { [re] DS:$02fa, six bytes. The initialiser names the FIRST variant's fields,
    which is the only form Turbo Pascal accepts for a variant record's typed
    constant -- Instrument, Period, Volume, Command, Parameter is
    1 + 2 + 1 + 1 + 1, and $02fa + 6 is $0300, which is CurCanal. }
  NewNote          : TFullNote     = (Instrument : 0; Period : 0; Volume : 0;
                                      Command    : mcNone; Parameter : 0);
  CurCanal         : PCanal        = nil;      { DS:$0306                       }
  Pattern          : PPattern      = nil;      { DS:$030a in v1.51             }

  { Set when this row started a sample. A 9xx sample offset can only be applied
    to a sample that is actually starting, and the command runs AFTER the note
    is set up -- so the note's half leaves this behind for the command's half to
    find.

    [re] NEW IN v1.51, DS:$030e, and it is the release's, carried since 1993:
    1.39b declares `NewSample : BOOLEAN = FALSE` among ProcessNewNote's own
    typed constants. }
  NewSample        : Boolean       = False;    { DS:$030e                       }

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

  MixChan          : Word          = 0;        { DS:$0312                       }
  ChanRec          : PModRawChan   = nil;      { DS:$0314                       }
  OutPtr           : Pointer       = nil;      { DS:$0318                       }
  ModRec           : PSampleBuffer = nil;      { DS:$031C                       }
  { FOUR OF THE VARIABLES IN THIS RUN ARE NEVER READ, HERE OR IN THE RELEASE.
    They are leftovers of an earlier version of the tick routine, and they were
    already leftovers in 1993. They are declared because their SPACE is real --
    everything after them sits where it sits because they are there.

    [re] THE WHOLE OF ProcessTick's CONSTANT BLOCK IS HERE, IN THE RELEASE'S
    ORDER, and matching it end to end is what named the four unknowns. 1.39b's
    LIB/PLAYMOD.PAS:1024 declares, after an untyped SizeOf:

        incr : INTEGER   OTempoCt : WORD   Can : PCanal   Raw : PModRawChan
        NoteHzFreq : LONGINT   i : WORD   j : WORD   t : WORD   step : LONGINT
        FBCount : WORD   NumChannels : BYTE

    Every width matches ours, in sequence, with no slack. `incr`, `NoteHzFreq`,
    `FBCount` and `j` occur exactly once each in the whole of 1.39b's PlayMod:
    their own declarations. A variable nothing reads has no witness in the code,
    so the sequence is the only evidence there is -- and it is enough because it
    is exact. }
  Incr             : Integer       = 0;        { the release's `incr`, unread    }
  PrevTick         : Word          = 0;        { the release's `OTempoCt`        }

  CanalPtr         : PCanal        = nil;      { DS:$0324                       }
  RawPtr           : PModRawChan   = nil;      { DS:$0328                       }
  NoteHzFreq       : LongInt       = 0;        { unread here and in 1.39b       }
  { ONE VARIABLE, TWO UNRELATED JOBS -- a tempo span first, then a channel
    index -- because the first use is finished before the second begins. This
    unit does that in three places, and it is the original's habit rather than
    an accident, which is why the name here claims nothing about either role.

    [re] DS:$0330 IN v1.51, and the layout is what forced it. A separate
    `TickSpan` put this unit's block four bytes over; the original has only six
    bytes between `NoteHzFreq` and `StepVal`, not eight. 12ce:0f2f stores the
    span into [0330] and 12ce:11b1 reads [0330] as the channel index in the
    volume pass. The notes at $02f6 and $0328 record the other two reuses, both
    found the same way. }
  TmpVal           : Word          = 0;
  UnusedIdx        : Word          = 0;        { never read; see above          }

  TickIter         : Word          = 0;        { the tempo loop's counter       }

  { [re] `UnusedIdx` is the release's `j`, the second of ProcessTick's two Word
    indices -- `TmpVal` is its `i`. `TickIter` is 1.39b's `t`, and it IS its own
    variable: 12ce:0f45's `DEC word [0334]` and 0fa5's `CMP [0334],1` are two
    bytes the span's address cannot account for. }
  StepVal          : LongInt       = 0;
  FBCount          : Word          = 0;        { never read                     }
  TickChans        : Byte          = 0;

  { [re] `StepVal` IS A LONGINT IN v1.51 AND A WORD IN 1.31b, AND THE ZERO STORE
    IS WHAT SETTLES IT. 12ce:11a5 is `MOV word [0336],1000 / MOV word [0338],0`
    -- two immediate stores. Written as two separate Word variables the second
    would be `XOR AX,AX / MOV [x],AX`, because Turbo Pascal special-cases
    assigning zero and five bytes beat six; it only emits the immediate form for
    BOTH halves when they are one 32-bit assignment. Our build proved that by
    emitting the XOR when it was tried the other way. AND THE SHIFTS BELOW ARE
    CAST BACK DOWN: 121d and 122b are `SHL AX,4` and `SHR AX,0Ch` on the low word
    alone, because a LongInt shift would be an RTL call.

    [re] `FBCount` IS A WORD IN v1.51 WHERE 1.31b HAS A LONGINT, and the two ends
    pinned it before the release confirmed it: StepVal occupies four bytes and
    TickChans follows two later, not four. 1.39b calls it a fall-back counter,
    beside `CanFallBack` and `FBTicks`, and never reads it. }

{ [re] NOTES ON INDIVIDUAL DECLARATIONS IN THE BLOCK ABOVE, kept for their
  content. DS:$02ca is the release's `CanFallBack`, "TRUE if fall-back is
  allowed", and a TYPED constant there as it must be here: 12ba:1325 reads it
  with `MOV AL,[02ca]` and an untyped constant would have folded to an
  immediate. It is the client's standing permission; `MyCanFallBack` at $121e is
  the working copy PlayStart clears while it is setting up and restores on the
  way out.

  [re] DS:$02ce is the release's `LoopMod`, "TRUE if music CAN be played
  forever", the client's half of the pair whose working copy is `MyLoopMod` at
  $0334. Its address proves the release's declaration order again: `LoopMod`
  then `ForceLoopMod` is $02c8 then $02c9, two adjacent bytes. NOTHING IN 1.31
  READS IT -- the initialisation section clears it at 12ba:1426 and no other
  instruction in the segment touches $02c8, because the operand that would have
  read it is COMMENTED OUT in the expression at 1121, which is where the stray
  `True and` comes from. The release still carries it the same way.

  [re] FIVE ARE EXPORTED BECAUSE 11bb WRITES THEM, and for no other reason. They
  were in the implementation section until segment 11bb -- the configuration
  file reader -- turned out to set every one from a key in VT.CFG:

      ForceLoopMod   $02c9   the `ForceLoopMod` key      11bb:0b0e
      FilterOn       $02cb   the `FilterOn` key
      FilterOff      $02cc   the `FilterOff` key
      MaxOutputFreq  $02d4   the `MaxFreq` key
      TicksPerSecond $0bcc   the `TicksPerSec` key

  [re] Moving a declaration from the implementation section to the interface
  cannot change a byte of either unit: every reference to a global is a linker fixup
  either way, and `units.py` is the check. What it does change is who may write
  them, and the answer turns out to be "a text file".

  [re] `FilterIsOn` IS EXPORTED TOO, and the DGROUP ADDRESS is what forced it.
  $02cd sits between `FilterOff` at $02cb and `MaxOutputFreq` at $02ce, both
  interface globals, and a unit lays its interface declarations down before its
  implementation ones -- so nothing private can land there. The shadowing hazard
  is handled at the one place it bites: VTCFG writes ModCommands' `FilterIsOn`
  at $0348 and says so by qualifying the reference.

  [re] `TicksPerSecond` IS GONE FROM HERE. It is SoundDevices' typed constant at
  $0bcc, holding 50. This unit had it AND DevGus had it, and the DGROUP layout
  says it is neither's: $0bcc sits between `TickSnapshot` at $0bca and `UsingGUS`
  at $0bce, both of which are the core's. Left as a declaration here it would
  SHADOW the real one for every reference in this unit, which is a bug no byte
  comparison can see.

  [re] `UserVols` at DS:$1208 is EXPORTED because `1000:0311` fills it: the
  program does `FillChar(UserVols, 8, VtVolume)` to set every channel to its
  master volume before a module starts. The release keeps it in its interface
  too, in the same VAR group as ActualHz and Permisos. }

{ ==========================================================================
  THIS UNIT'S VARIABLES -- the ones that hold no initial value and so are
  reserved space rather than data: the channel array, the raw mixer channels,
  the sample buffers, and the rings.

  THEY ARE IN ADDRESS ORDER FOR THE SAME REASON THE CONSTANTS ARE. Declaration
  order is layout, and layout is not something a reader can guess back from the
  code.

  [re] $11f0..$1745. The addresses were all correct and the ORDER was not, which
  is a distinction nothing could measure until the program linked: a `var` is
  space the linker never writes, so `dgroup.py` cannot see it, and inside a
  `.TPU` every reference to one is an unresolved fixup that `units.py` excuses.
  `linkcmp.py` compares the LINKED code, where each of those fixups is a real
  address, and it reported this block scattered over fourteen different deltas
  -- +3530, +3976, -428, -700 and the rest -- which is what a correctly-sized
  block in the wrong internal order looks like.

  [re] THE RELEASE'S INTERFACE VAR GROUP IS THIS ORDER EXACTLY: SplBuf, then
  ActualHz, NoteHz, NoteCalcVal, UserVols, Permisos, TickCount, ModTickProc,
  MyCanFallBack, FilterVal. 1.31 continues with NoteBuff where 1.39b has
  `PlayModStack`, and then agrees again on Canales, BuffGive, Buffers and
  SizeOfABuffer.

  [re] FIVE OF THE ADDRESSES BELOW ARE BASE-1 BASES rather than the arrays
  themselves: `$11ee` is SplBuf's, `$12E0` UserVols', `$12e0` Permisos', `$1260`
  Canales' and `$13A6` RawChannels'. An instruction naming one of those is
  indexing the array, not touching the byte.

  [re] Only the first five need to be visible: `UserVols` because 1000:0311
  fills it, and the four above it because they have to precede it. The rest
  follow in the implementation, which keeps them private without moving them --
  a unit's implementation variables come after all of its interface ones, so the
  order is preserved either way.
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
  SplBuf          : array[1..MaxChannels] of Word;  { DS:$12b8               }
  ActualHz        : Word;  { DS:$12D8 }
  NoteHz          : Word;  { DS:$12DA }
  NoteCalcVal     : LongInt;  { DS:$12DC }
  UserVols        : TVolumes;             { DS:$12E0  base-1 base $1207 }

{ NEGOTIATE AN OUTPUT RATE. The caller ASKS for a rate; the card answers with
  what it can actually do, the buffers are sized for that, and the DMA is
  programmed. It can also be called again mid-song, which is why it exists as a
  routine rather than as part of starting playback.

  [re] 12ba:132f. Declared here because 12ba:0d4e calls it and it lives 1,500
  bytes further down the segment; the release exports it too, as
  `PROCEDURE ChangeSamplingRate(Hz: WORD)`. }
procedure ChangeSamplingRate(Hz : Word); far;
{ RELEASE ONE ROW OF QUEUED GUS COMMANDS. Called from the GUS driver's
  interrupt handler, once per buffer, which is what ties the queue to the sound
  actually being heard rather than to the sequencer's position.

  [re] Exported for that caller: DEVGUS's handler calls it at 106e:0019 as
  `CALLF 12ce:03d9`, and it ends `LEAVE / RETF` at 12ce:04b9. THAT ADDRESS WAS
  READ AS `AdvanceEventRow` FOR A WHILE, and the evidence was right while the
  name was wrong: 03d9 is `ENTER 4,0 / CLD / INC [02ea]`, then
  `IMUL DI,[02ea],0120` into a ring at $29fa, walking the row calling two FAR
  routines before FillChar-ing it -- FlushEventRow, instruction for instruction.
  AdvanceEventRow is at 0183 and ends `LEAVE / RET` at 0201, near.

  [re] NOTHING IN DEVGUS COULD HAVE CAUGHT THAT. The call is `9A` plus a segment
  fixup and an offset the linker supplies, so DEVGUS assembles to the same bytes
  whichever PlayMod routine the name resolves to, and it verified byte-exact
  under the wrong one -- the same shape as SOUNDDEV's unlinked fixups and
  MODCOMMA's shadowed `mcLast`. A cross-unit reference can only be checked by
  the CALLEE's own bytes. }
procedure FlushEventRow; far;

procedure ProcessTickEntry; far;

{ Stop playing and hand the buffers back. Also called from inside PlayStart's
  own failure path, which is why it has to work on a player that never fully
  started.

  [re] 12ba:13d7, called from 12ba:127c 1,300 bytes above it; the release
  exports it too. }
procedure PlayStop; far;

{ Start playing a module: take the requested range, set up the channels, size
  and claim the buffers, and hand the first of them to the card.

  [re] 12ba:10a1. EXPORTED BECAUSE 1000 CALLS IT: 1000:0381 is
  `CALLF 12ba:10a1` from inside PlayModule, and until segment 1000 was read
  nothing outside this unit was known to reach it. SEVENTH INTERFACE CORRECTED
  BY A CALLER IN ANOTHER SEGMENT -- see VTDOSRSZ, VTDOSMEM, GUS, UNKLOADE,
  TSong.Status and HARDWARE.DMAReset. Exporting an already-far routine cannot
  move a byte; PLAYMOD verifying unchanged is the check. }
procedure PlayStart(var Song : TSong); far;

implementation

{ [re] NOTES WITHOUT DECLARATIONS. Everything from here to the next `type`
  section describes a global that now lives in one of this unit's two ORDERED
  blocks -- the typed constants at the top of the file, $02c4..$0333, or the
  variables further down, $11f0..$1745. They are kept because several record
  measurements that are not repeated there; the address each one opens with is
  how to find the declaration. }
  { [re] DS:$13a4. The release keeps this in its implementation section too, which
    is where the disassembly puts it -- nothing outside 12ba reads it. }


{ [re] The declaration this note describes now lives in the ordered const
  block at the top of this file; it is NOT the declaration below. }
  { [re] DS:$02d1, THE RENAME FLAG, and it is declared in two units. VTMAIN owns it
    as `AltMode` -- set when the executable is called INCONEXI.EXE -- and
    nothing in THAT segment reads it; this is the only reader. A global's
    address is a linker fixup, so the byte comparison cannot see the
    duplication either way, which is exactly the shape of risk 1 and exactly
    what DEVGUS's three duplicated globals looked like. Left declared here,
    flagged rather than resolved: settling it needs the DGROUP layout. }


  { [re] ~~ONE cursor, shared~~ -- **v1.51 SPLITS IT, AND ADDS THE FULL TEST THAT GOES
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

  { [re] DS:$02f4 -- `Raw.Flags` UNDER CONSTRUCTION, and the bit values are what say
    so: 12ba:03cc starts it at 2 and then adds $01, $04, $10 and $20, which are
    exactly rcfActiveChannel, rcfLongSample, rcfDoesLoop, rcfLongLoopLen and
    rcfLongLoopEnd. It was read as "a GUS voice control byte" until the last two
    turned up. Whatever stores it into the record is further down the routine.

    DS:$02f5 is its companion: set to 1 when the sample's loop is shorter than
    four bytes -- treated as no loop at all -- and 0 when it loops, which is why
    every test of it reads `= 0`. }

  { [re] DS:$0bce -- THE SECOND DUPLICATED GLOBAL IN THIS UNIT, and the same shape as
    AltMode above. DevGUS declares it as `Started` in its IMPLEMENTATION section,
    so it is private there and invisible here, yet 12ba:05a8 plainly reads it: the
    routine below posts nothing unless the GUS driver has started. One of the two
    declarations has to go when DGROUP ownership is settled, and the release gives
    no guidance because 1.39b rebuilt its GUS support elsewhere. Flagged, not
    resolved -- and invisible to the byte comparison either way. See risk 1. }

{ [re] The declaration this note describes now lives in the ordered const
  block at the top of this file; it is NOT the declaration below. }
  { [re] --- the sequencer's state, DS:$02d6 upward -----------------------------
    The 63-byte record at DS:$1220 is the release's `TPlayingNote` -- ITS FIRST
    FIELD IS CONFIRMED and nothing else is. 1.39b describes `EoMod` as "TRUE if
    it is the note following the last", and 12ba:06fe sets exactly that from a
    row number of $FFFF. The release's record is 32 bytes and this one is 63, so
    the rest of the layout does not carry over and is left as filler.

    The two indices and the pointer follow the release's naming where the role
    matches; they are provisional. }
  { [re] DS:$13a6, AND $1384 IS THE BASE-1 BASE RATHER THAN THE ARRAY. Every access
    is `IMUL DI,i,$22 / ADD DI,$1384`, which for i=1 lands on $13a6 -- one 34-byte
    element above $1384, exactly as the base-1 rule says. 12ba:12ba settles it
    outright: `FillChar(RawChannels, SIZEOF(RawChannels), 0)` passes $13a6 and
    $0110, and $0110 is 272, which is 8 x 34. The earlier comment here gave $1384
    as the array's own address and it was the base. }

  { [re] All four names are the release's, and each is confirmed by what 12ba does
    with it: ActualHz divided by the tick rate gives samples per tick, capped by
    MaxSplPerTick -- whose release comment is literally "Maximum samples in the
    buffer. Means maximum samples per tick." }
  { [re] THE RELEASE'S DECLARATION ORDER, AND THE ADDRESSES CONFIRM IT: `BuffIdx,
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

  { [re] Both the release's names. `SplBuf` carries each channel's filter state from
    one call to the next -- it is what FilterChunkWord takes as `OldSpl` and
    returns -- and `FilterVal` is the method in force. Base-1 again: the compiler
    addresses SplBuf from $11ee, one element below its real start. }

  { [re] All four the release's names, and each confirmed by its use here: the pair of
    methods and the switch between them at 12ba:0f15, and the per-channel
    permission at 12ba:0f2a -- "permissions for playing the channels", which is
    exactly what it gates. Base-1 again for the array. }
{ [re] The declaration this note describes now lives in the ordered const
  block at the top of this file; it is NOT the declaration below. }
  { [re] DS:$02cd -- AND THIS IS NOT ModCommands' `FilterIsOn`, which is at DS:$0348.
    142f:04da writes that one from the E0x command and nothing reads it; this one is
    read by the initialisation section at 12ba:1430 to choose between FilterOn and
    FilterOff. Two variables where the release has one. ModCommands keeps its copy in
    its IMPLEMENTATION section precisely so that this name cannot be shadowed here --
    if both were exported, every reference in this unit would silently bind to this
    one and no byte comparison could see it. }

  { [re] DS:$02d4 -- the release's `MaxOutputFreq`, whose comment is "Maximum frequency
    of the output sound. Less means less memory for buffers." Divided by the tick
    rate at 12ba:1174 it gives exactly MaxSplPerTick, which is that sentence. }

  { [re] DS:$0bca -- THE FOURTH DUPLICATED GLOBAL. VTMAIN owns it as `Snapshot` and
    12ba compares it against `VTSilenc.Ticks` at DS:$0bc8, which IS exported and
    is used from here directly. So one of the pair resolves cleanly and the other
    does not, in the same comparison. Risk 1 again. }

  { [re] DS:$034e IS A TICK COUNTER WITHIN THE ROW, not the row number, and
    docs/04-units.md has it as "the current row". 12ba:0cdf compares it against
    `NoteProcessed^.Tempo` -- the release's "number of ticks the note will last"
    -- and 12ba:0cf7 resets it to zero when the pattern advances. A row number
    would be compared against a pattern length and would not reset. }

  { [re] DS:$121e -- the release's `MyCanFallBack`, "actual permission to fall back",
    and the use fits exactly: with permission withheld, SoundDevices' request to
    fall back to a lower rate is simply cleared. }
  { [re] DS:$0328 -- ONE GLOBAL, TWO JOBS, like DS:$02f6 before it. At 12ba:0d14 it
    holds a candidate sample rate while the driver is negotiated; from 12ba:0da1
    it is the control variable of a loop over the channels. The name is neutral
    because neither role owns it. }


type
  { ASK A DEVICE WHAT RATE IT CAN ACTUALLY DO. The player names a rate it would
    like; the driver answers with the nearest one its hardware can produce, and
    that answer is what the buffers are sized for. Every card gives a different
    answer, which is why this is a call into the driver rather than a table.

    [re] The driver record's +$26, reached through its Pointer field the way
    SOUNDDEV does with `TInitDevProc`; 12ba:0d44 stores the result.
    `TChanData` and `TChansData` were declared here once and are VTCtrl's now,
    because the published row and the wide ring have to be one type for the
    copies below to be ASSIGNMENTS rather than Move calls. }
  TGetFreqProc = function(Hz : Word) : Word;

  { WHAT RUNS ON EVERY TICK. A client can install its own; the player calls it
    once per tick with the song and a flag saying whether this tick begins a new
    row, which is the distinction almost every caller cares about.

    [re] The release's own type, and 12ba:1032 confirms both arguments: the song
    by reference and a Boolean computed there as `TickInRow = 0`. }
  TTickProc = procedure(var Song : TSong; Note : Boolean);

{ ...and the rest, private but in the same run -- see the note above. }
var
  Permisos        : array[1..MaxChannels] of Boolean;  { DS:$1210  base-1 base $120f }
  TickCount       : Word;  { DS:$1220 }
  ModTickProc     : TTickProc;  { DS:$121a }
  MyCanFallBack   : Boolean;  { DS:$121e }
  FilterVal       : TFilterMethod;  { DS:$121f }
  NoteBuff        : array[0..0] of TPlayingNote;  { DS:$1220  63 bytes, then a pad }
  Canales         : array[1..MaxChannels] of TCanal;  { DS:$1260  base-1 base $123a }
  BuffIdx         : Word;  { DS:$1390 }
  BuffGive        : Word;  { DS:$1392 }
  Buffers         : array[1..NumBuffers] of TSampleBuffer;  { DS:$1394 }
  SizeOfABuffer   : Word;  { DS:$13a0 }
  ModFlag         : Boolean;  { DS:$13a2 }
  MuestrasPerTick : Word;  { DS:$13a4 }
  RawChannels     : array[1..MaxChannels] of TModRawChan;  { DS:$13a6  base-1 base $1384 }
  NoteRing        : array[0..RingRows - 1] of TRingRow;  { DS:$14b6 }

  { NEW IN v1.51 -- THE WIDE RING, and its shape is read off three multipliers.
    12ce:021a is `SHL DI,7`, so a row is 128 bytes; 0243 is `SHL DI,5`, so the
    flag grid is 32 bytes a row; and 0206..0211 is `INC / CMP 18 / SUB 19`, so
    there are 25 rows exactly as the narrow ring has. }
  WideRing        : array[0..RingRows - 1] of TChansData;
  WideHit         : array[0..RingRows - 1, 1..WideChans] of Byte;

  { WHERE IN THE SONG EACH PUBLISHED ROW CAME FROM -- the row number and the
    order position, one byte each. They ride the ring alongside the row so that
    a reader picking up a row a quarter of a second later still knows which
    moment of the music it belongs to.

    [re] TWO arrays and not a record of two: 12ce:0263 and 026e index them
    separately, 26 apart, and they are published to CB+$1AD and CB+$1AE. WHAT
    THEY HOLD CAME FROM THE WRITER, NOT THE READER: PublishWideRow only moves
    them, so nothing there says which is which; 12ce:090b does, storing
    `NoteProcessed^.NotePlaying` into the first and `SeqPlaying` into the
    second. The transcription had the pair swapped until that was read. }
  WideNoteRing     : array[0..RingRows - 1] of Byte;
  WideSeqRing    : array[0..RingRows - 1] of Byte;
  EventRing       : array[0..RingRows - 1] of TGusEventRow;  { DS:$1646 }

{ [re] MORE NOTES WITHOUT DECLARATIONS. Same as the run above: these described
  variables that are now in the ordered block at $11f0..$1745, a few lines up. }
  { [re] The release's name, confirmed by 12ba:1008 along with the guard it returns on,
    the song it plays and the flag that says the procedure has been set up -- the
    other four of that group are typed constants and are in the ordered block at the
    top of this file. }


{ [re] The declaration this note describes now lives in the ordered const
  block at the top of this file; it is NOT the declaration below. }
  { [re] DS:$0c74 `TicksPerSecond` -- THE THIRD DUPLICATED GLOBAL, after AltMode and
    UsingGUS. DevGUS
    declares it privately in its implementation section, where a comment already
    records that the release moved it to SoundDevices and that ownership is the
    open question rather than the name. 12ba reads it here. Risk 1 again. }
  { [re] DS:$02f6 -- ONE GLOBAL, TWO JOBS. At 06bc it is the note buffer's next slot;
    from 0802 it is the control variable of a `for` loop over the channels. The
    first use is finished before the second starts, so the reuse is harmless --
    but it is why the name is neutral rather than either role's. }

{ [re] The declaration this note describes now lives in the ordered const
  block at the top of this file; it is NOT the declaration below. }
  { [re] DS:$0334 -- THE RELEASE'S `MyLoopMod`, no longer provisional. Its assignment
    at 1121..113d is the release's `(TRUE AND (MyRepStart <> 0)) OR ForceLoopMod`
    character for character, including the commented-out LoopMod operand that is why a
    literal 1 is tested there, and 0717 reads it as the release's line 821 does.
    The client-facing `LoopMod` it was named after is a DIFFERENT variable, at
    $02c8; see its declaration in the interface. }
  { [re] MOVED TO ModCommands as well: `CurSpeed` ($0349) and `CurTempo` ($0338), which
    142f:04a6 and 142f:04bc write from the F-command. Names unchanged; the release
    calls them Tempo and BPMIncrement and the rename is declined there for reasons
    given at the declaration. }

  { [re] MOVED TO ModCommands: `NextSeq` ($034c), `NextNote` ($034a) and `MySongLen`
    ($0340), which this unit knew as NextSeq, NextNote and MySongLen. 142f writes all
    three from its effect routines, and PlayMod uses ModCommands rather than the
    other way round, so ModCommands has to own them. See the note at their
    declaration; the release splits them the same way. }
  { [re] The range a caller ASKS for, copied into the working three at 12ba:10b4.
    Provisional names: nothing outside 12ba has been seen to set them. }
{ [re] The declaration this note describes now lives in the ordered const
  block at the top of this file; it is NOT the declaration below. }
  { [re] DS:$02cf -- the release's `ForceLoopMod`, "TRUE if music must be played
    forever", and 12ba:112e uses it exactly that way: it forces LoopMod on. }


{ --------------------------------------------------------------------------
  THE RESAMPLING KERNEL, and the whole reason this unit links an object module.
  It is the inner loop of the entire program: for each output sample it reads
  the source at the current position, scales it by the volume, adds it to what
  is already there, and advances the position by the step. Everything else in
  this unit exists to set up one call to this.

  IT IS HAND-WRITTEN ASSEMBLER because it runs tens of thousands of times a
  second and a compiler's output would not keep up on the hardware this was
  written for. It lives in PLAYMOD.ASM and is linked in below.

  IT IS CALLED IN BOUNDED RUNS, AND THAT IS WHAT KEEPS IT STRAIGHT-LINE. The
  caller works out how far the kernel can go before it hits something -- the
  end of the sample, the end of a loop, the end of what is owed -- and asks for
  no more than that. So the kernel needs no wrap test, no end-of-sample test
  and no branch inside its loop; the caller handles the boundary and calls
  again. `Rest` is both the request and the answer: how many samples are owed
  going in, how many are still owed coming out.

  ONE KERNEL DOES TWO JOBS. A silent channel still has to advance its position
  and still has to leave the output untouched, so rather than a second routine
  there is a `Silent` flag. The release later split it in two.

  [re] 12ba:1600. `PUSH BP / MOV BP,SP` is not what starts it; the prologue
  scanner found `ENTER $000`, the hand-written frame of an assembler routine,
  and 1.39b builds its equivalent from `LIB/PLAYMOD.ASM` under a $L. The
  signature is read off the call sites at 009b, 0111 and 016f -- eight
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
{ [re] `units.py` REPORTS THIS UNIT AS MISMATCHED, AND THAT IS THE INSTRUMENT'S
  LIMIT RATHER THAN A DEFECT. It compares .TPU files, and this unit's code is
  partly in the .OBJ linked below -- so the TPU holds a call to something that
  is not in it, and the comparison diverges at the first such site. SoundDevices
  reports the same for the same reason, and they are the only two units in the
  tree with an external module. THE LINKED IMAGE IS THE CHECK THAT COUNTS, and
  it reports zero differing bytes. }
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
  MIX ONE CHANNEL'S WORTH OF SAMPLES. Called once per channel per tick, and
  between them these calls are where nearly all the program's time goes.

  IT IS A LOOP AROUND THE KERNEL, NOT A CALL TO IT, and the loop is what
  handles boundaries. The kernel is only ever asked for a run it can complete
  without deciding anything: as far as the loop end, or as far as the sample
  end, or as much as is still owed -- whichever comes first. When it stops
  short, this routine works out why, adjusts the position, and asks again.
  Every branch lives here so that the inner loop can have none.

  A SAMPLE THAT LOOPS AND ONE THAT DOES NOT ARE DIFFERENT SHAPES. A looping
  sample runs until the tick is satisfied, winding the position back by one
  loop length each time it reaches the end. A one-shot runs at most once and
  then it is finished.

  AND SILENCE STILL COSTS A CALL. If the channel could not fill the tick -- it
  ended, or it was never active -- the remainder is passed through the kernel
  with a volume of zero, so the position advances and the output is left
  untouched. That is cheaper than a special case, and it keeps every channel's
  position honest whether it is sounding or not.

  [re] 12ba:0007. `Rest` doubles as the argument and the result -- how many
  samples are owed going in, how many still owed coming out, so "did anything
  happen" and "how much is left" are one value. It is a typed constant at
  DS:$02ea in the release and the disassembly agrees, `a3 ea 02`.
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
  RELEASE ONE ROW OF CUES AND STEP THE RING ON. This is the far end of the
  music-to-demo channel: a cue written by an 8xx command a fraction of a second
  ago has now reached the listener, so it is counted into the published control
  block where anything outside the program can see it.

  IT COUNTS RATHER THAN DELIVERS. Each cue increments one of 256 counters, and
  a client reads the counter and sees how many times that cue has fired. A
  counter cannot be missed the way a flag can -- a demo running at 25 frames a
  second and music running at 50 ticks would drop every other event if this
  were a single flag.

  THE ROW IS CLEARED AS IT IS RELEASED, which is what makes the ring
  self-maintaining: a slot is empty by the time the producer comes round to it
  again, so nothing has to track which slots are stale.

  [re] 12ba:0187, a NEAR procedure taking nothing, with one Pointer local at
  [BP-4]. The counters live in `VTCtrl.CtrlBlock`, the 768-byte structure
  published over INT 2Fh.

  [re] THE SHAPE IS A `FOR`, AND THE READING PASS HAD IT AS A NESTED `IF` --
  recorded as `if Counter > $18 then begin ... if $02d1 <> 0 then ... else
  Inc($02ee) end`, which is what `MOV [02ee],0 / JMP past / INC [02ee]` looks
  like if the loop is not recognised. Borland's FOR opens exactly that way, with
  the increment ABOVE the body and jumped over on entry; the `JNZ` at `01e8`
  closes it back onto the `INC` and the `CMP [02ee],7` before it is the limit.
  So `$02ee` is a loop variable over the row's eight entries, not a second
  counter, and the rename flag is tested UNCONDITIONALLY rather than inside the
  wrap. The `CLD` at `018b` is the compiler's: Turbo Pascal emits it in the
  prologue of any routine whose body uses a string instruction, and the
  `FillChar` at the end is one.
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
    { [re] 01b3..01ca -- a WITH, and the frame slot is its doing. Turbo Pascal
      implements `with <indexed record>` by computing the record's address ONCE
      into a hidden four-byte frame slot, stored offset-then-DS, and every field
      reference inside the block reloads it with `LES DI,[BP-4]` -- which is
      what 01cb and 01d5 do. So the `ENTER 4,0` at 0187 is the with-slot and
      this routine declares NO local at all.

      [re] `@Ring[..]` gets the INDEX computation exactly right, byte for byte,
      through 01c0: `MOV AX,EventChan / SHL AX,1 / MOV DI,EventSlot / SHL DI,4 /
      ADD DI,AX`. What differed was the four instructions after it:

        original   ADD DI,OFFSET Ring / MOV [BP-4],DI / MOV [BP-2],DS
        ours       LEA AX,[DI+Ring] / MOV DX,DS / MOV [BP-4],AX / MOV [BP-2],DX

      Turbo Pascal wants a pointer VALUE in AX:DX to assign; the original never
      forms one, it just stores the offset it already has in DI beside DS.
      `Ptr(Seg(NoteRing), ... + Ofs(NoteRing))` was tried and is WORSE -- it
      changes the index arithmetic too and the prefix drops from 01c1 to 01b3. }
    { **THIS IS WHERE THE MUSIC SIGNALS THE DEMO**, and it is three lines.

      A composer writes effect `8xx` on a note. The effect engine stores xx
      into the channel and flags it; the sequencer copies both into this ring;
      and here, one tick later -- when the sound has actually reached the
      listener -- the semaphore that xx names is incremented. The demo polls
      that semaphore and sees the beat arrive.

      So the whole synchronisation mechanism of the program, the reason it
      exists rather than being an ordinary player, passes through this `Inc`.
      Everything else is buffers and mixing. }
    with NoteRing[EventSlot, EventChan] do              { 01b3..01ca             }
      if Pending <> 0 then                          { 01cb..01d4             }
        Inc(CtrlBlock.Semaphores[Sem])              { 01d5..01e2             }
  end;

  FillChar(NoteRing[EventSlot], SizeOf(TRingRow), 0)    { 01ea..01ff             }
end;

{ --------------------------------------------------------------------------
  12ce:0202 -- THE WIDE ROW, NEW IN v1.51, and it is the 8-channel ring above it
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
  { 0205 -- the same hand-written CLD as AdvanceEventRow's, and for the same
    reason: two `Move`s and a `FillChar` on a path the timer can reach. }
  asm
    CLD                                             { 0205                   }
  end;

  Inc(WideSlot);                                    { 0206..0209             }
  if WideSlot > RingRows - 1 then                   { 020a..0210             }
    Dec(WideSlot, RingRows);                        { 0211..0215             }

  { AN ASSIGNMENT, NOT A `Move`, AND THE HELPER IS WHAT SAYS SO -- 022b calls SYSTEM's
    $09f7 where a written `Move` gets $0fb2. Same rule this file already records for
    `Volume := UserVols`. }
  CtrlBlock.ChansData := WideRing[WideSlot];        { 0216..022f             }

  for WideChan := 1 to WideChans do                 { 0230..0237, 0258..025e }
    if WideHit[WideSlot, WideChan] <> 0 then        { 023c..024e             }
      CtrlBlock.ChansTrig[WideChan] := 1;             { 024f..0257             }

  CtrlBlock.Pos := WideNoteRing[WideSlot];   { 025f..0269             }
  CtrlBlock.Seq  := WideSeqRing[WideSlot];    { 026a..0274             }

  WideRing[WideSlot] := WideRing[WidePrev];        { 0275..0296             }

  FillChar(WideHit[WideSlot], WideChans, 0);        { 0297..02ac             }

  WideNoteRing[WideSlot]  := WideNoteRing[WidePrev];  { 02ad..02bc             }
  WideSeqRing[WideSlot] := WideSeqRing[WidePrev]; { 02bd..02cc             }

  WidePrev := WideSlot                              { 02cd..02d2             }
end;


{ --------------------------------------------------------------------------
  QUEUE A COMPLETE VOICE COMMAND. Everything the GUS needs to start a note --
  volume, pitch, pan and the three addresses that define the sample and its
  loop -- written into one slot, to be handed to the card when this row's sound
  is due.

  IT TESTS NOTHING. This is the raw setter, used when a note is genuinely
  starting; `PostEvent` below is the one that merges into a slot that may
  already be occupied.

  THE PARAMETERS ARE DELIBERATELY NOT NAMED AFTER THE FIELDS. Inside a `with`,
  an unqualified name binds to the record's field first, so `Vol := Vol` would
  quietly assign a field to itself.

  [re] 12ba:0202, near, `RET 16h` in v1.51 against 1.31b's `RET 14h` -- the two
  bytes are AFreq going from Word to LongInt, the same change the record made.
  The seven arguments are `TriggerVoice`'s own list minus its `Voice`, which
  indexes the row here rather than being stored. Another `with`: `ENTER 4,0`,
  the address stored offset-then-DS at [BP-4], and `LES DI,[BP-4]` reloaded
  before every field -- six stores, six reloads.
  -------------------------------------------------------------------------- }
procedure SetEvent(Voice, AVol : Byte; AFreq : LongInt; APan : Byte;
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
  CHANGE A VOICE THAT IS ALREADY SOUNDING -- or start one, if the slot is
  empty. A tick can adjust the pitch of a note that began several rows ago, and
  it must not disturb the sample addresses that note is playing from.

  AN EMPTY SLOT IS FILLED; AN OCCUPIED ONE IS MERGED. And a slot is empty when
  its frequency is zero -- no separate valid flag, because the flush wipes each
  row as it releases it, so a slot is always clean by the time the ring comes
  round again.

  ALL-ONES MEANS "LEAVE THIS ONE ALONE". A caller changing only the pitch
  passes $FF for the volume and the merge skips it. That is how a vibrato
  updates a voice without knowing or caring what its volume currently is.

  THE PAN IS THE EXCEPTION: it is written unconditionally on the merge path,
  with no sentinel test at all, so a caller cannot decline to set it.

  [re] 12ba:0275, near, `RET 8`, the same `with` on the same slot as 12ba:0202
  but only the first four fields. The pan's lack of a guard was read the other
  way at first -- recorded as `if B <> $FFFF then begin E^[1] := B; E^[3] := C
  end` -- and the byte comparison says otherwise: the `JZ` at 02d0 jumps ten
  bytes, the `Freq` store alone, not the twenty the pair would need.

  [re] AFreq IS A LONGINT HERE TOO, and the sentinel test shows it most plainly:
  12ce:03ae is `CMP [BP+8],-1 / JNZ / CMP [BP+6],-1 / JZ`, Turbo Pascal's 32-bit
  compare done high word first. 1.31b had one `CMP ...,$FFFF`. Written as `-1`
  and not `$FFFFFFFF` because that is what gives the sign-extended byte
  immediate the original has.
  -------------------------------------------------------------------------- }
procedure PostEvent(Voice, AVol : Byte; AFreq : LongInt; APan : Byte);
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
      if AFreq <> -1 then                        { 03ae..03b9                }
        Freq := AFreq;                           { 03ba..03c3                }
      Pan := APan                                { 02dc..02e5                }
    end
end;

{ --------------------------------------------------------------------------
  HAND ONE ROW OF QUEUED COMMANDS TO THE CARD. Called from the GUS driver's
  interrupt when a buffer completes, which is what makes the queue release in
  step with what is actually being heard.

  ADVANCE, APPLY, WIPE -- in that order, and the wipe is what lets an empty
  slot be recognised by a zero frequency alone.

  A SLOT IS EITHER A NEW NOTE OR AN ADJUSTMENT, and the loop addresses are what
  tell them apart: a command carrying a sample end starts a voice from
  scratch, one without it only changes the pitch, volume and pan of a voice
  already running. Two different driver calls, chosen per slot.

  [re] 12ba:02ea, near, no arguments. THE TWO GUS ENTRY POINTS ARE CHOSEN BY
  `EndA > 0` on the 32-bit value: the `CMP [DI+$0e],0 / JG / JL / CMP
  [DI+$0c],0 / JBE` at 0330 is Turbo Pascal's LongInt comparison, high word
  first. With loop information it is the full `TriggerVoice`; without, it is
  `ChangeVoiceParams`. In 1.31b `Freq` is a Word in the ring and a LongInt in
  both calls, widened here with `XOR DX,DX`.
  -------------------------------------------------------------------------- }
procedure FlushEventRow;
begin
  asm
    CLD                                          { 03dd                      }
  end;

  Inc(FlushSlot);                                { 03de..03e1                }
  if FlushSlot > RingRows - 1 then               { 03e2..03e8                }
    Dec(FlushSlot, RingRows);                    { 03e9..03ed                }

  for RingVoice := 0 to GusVoices - 1 do         { 03ee..03f8, 0499..04a2    }
    with EventRing[FlushSlot, RingVoice] do      { 03f9..0411                }
      if Freq <> 0 then                          { 0323..032c                }
        if EndA > 0 then                         { 032d..033f                }
          TriggerVoice(RingVoice, Vol, Freq, Pan,
                       StartA, LoopA, EndA)      { 0340..0383                }
        else
          ChangeVoiceParams(RingVoice, Vol, Freq, Pan);   { 0386..03a8       }

  FillChar(EventRing[FlushSlot], SizeOf(TGusEventRow), 0) { 04a3..04b8       }
end;

{ --------------------------------------------------------------------------
  START A SAMPLE ON A CHANNEL. Everything between "the score says play
  instrument 7" and a channel that is actually walking through instrument 7's
  bytes at the right rate.

  MOST OF IT IS THE 64K PROBLEM. A sample may be longer than a real-mode
  segment can address, so it arrives as two blocks, and this routine works out
  which block holds the start, which holds the loop point, which holds the loop
  end, and sets the flags that tell the mixer. Those four questions are why the
  raw channel has three sets of segment/offset/limit and why four of its seven
  flags exist at all.

  THE 9xx SAMPLE OFFSET ARRIVES HERE. The effect engine cannot move a sample
  pointer -- the note it applies to has not started yet -- so it leaves the
  offset behind and this routine adds it to the sample's start address as the
  channel is set up. One feature, two units, and this is the seam.

  AND FOR A GRAVIS IT QUEUES INSTEAD OF SETTING UP. The card walks its own
  memory, so what it needs is a command in the ring rather than a pointer in a
  record. Same decision, two entirely different outputs.

  [re] 12ba:03cc, 664 bytes, `RET 0Ch` in v1.51 against 1.31b's `RET 0Ah` -- the
  two extra bytes are `Offs`, and everything the routine already did moved up
  two: Desc from [BP+4] to [BP+6], Raw from [BP+8] to [BP+0a]. [BP+4] is read
  twice, at 12ce:06cd and 073c, as `MOV AX,[BP+4] / XOR DX,DX / ADD
  AX,ES:[DI+12] / ADC DX,ES:[DI+14]` -- a Word widened and added to the
  sample's start address.

  [re] THE SIGNATURE WAS READ OFF THE CALL SITE at 12ba:09e3 rather than the
  callee, per the standing rule. It pushes `MOV AL,[02f8] / PUSH AX` (a Byte),
  then `IMUL DI,[02f8],$22 / ADD DI,$1384 / PUSH DS / PUSH DI` (the address of a
  34-byte record), then a four-byte value read out of `[0300]^` at `+6`/`+8`.
  That CONFIRMS DS:$1384 as the `RawChannels` array -- `IMUL ..,$22` is the
  record's 34-byte stride.

  [re] THE NAME IS THE RELEASE'S. LIB/PLAYMOD.PAS line 532 is `SetNewSample(i:
  BYTE; VAR Raw: TModRawChan; Spl: PInstrumentRec; Offs: WORD)`, and its two
  call sites pass `0` and `can^.SOffsVal` -- the same field 147d:0369 sets from
  command $0a. It was called `SetGusVoiceCtl` here for a while and was never
  GUS-specific: 1.39b has no GUS support in this unit at all and still has this
  routine.

  [re] THE BODY IS PART COMPILED AND PART HAND-WRITTEN, and `var Raw` is
  reached two different ways because of it:

      03da  MOV DI,[BP+8]        then MOV [DI+$0d],AX      DS-relative
      044c  LES DI,[BP+8]        then MOV ES:[DI+$17],AX   far, ES reloaded

  Both are correct at run time, because `RawChannels` is in DGROUP and the
  segment the caller pushed IS DS -- but Turbo Pascal's code generator emits
  only the far form for a `var` parameter. The tell that settles it is `21 C0`
  at 03f7: `AND AX,AX` in the `r/m,reg` direction, which the INLINE ASSEMBLER
  emits and the code generator does not (it tests with `OR`, as `08 C0` at
  12ba:0018 and `0B 46 06` at 03d2 both show). In TP's asm a `var` parameter
  names the POINTER, so loading its low word gives the offset. Same shape as
  `1a17`'s GetPlayPos: a compiled routine with hand-written asm inside it, and
  the encodings are what separate the two halves.
  -------------------------------------------------------------------------- }
{ [1.39b] "Start a new sample on one of the channels."

  The release's own one-line description of this routine, in translation. Its
  section header for the group this belongs to reads "[1.39b] Routines that
  interpret the score." }
procedure SetNewSample(Chan : Byte; var Raw : TModRawChan; Desc : PInstrumentRec;
                       Offs : Word);
begin
  { [re] 03cf..03d9 -- compiled: `OR AX,[BP+6]` is the code generator's
    direction, and the `JNZ +3 / JMP` pair is what a large if-body gives when
    the skip is out of short range. }
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
        MOV     DI, WORD PTR Raw       { 042c                                }
        LES     SI, Desc               { 042f                                }
        OR      BYTE PTR NewFlags, rcfLongSample   { 0432                    }
        MOV     WORD PTR [DI+$11], MaxSample   { 0437  -> Raw.SplLimit1          }
        LES     DI, Desc               { 043c                                }
        MOV     AX, ES:[DI]            { 043f  SplLen, low word              }
        MOV     DX, ES:[DI+$02]        { 0442  ... and high                   }
        SUB     AX, MaxSample              { 0446                                }
        SBB     DX, 0                  { 0449                                }
        LES     DI, Raw                { 044c                                }
        MOV     ES:[DI+$17], AX        { 044f  -> Raw.SplLimit2              }
      end;

    { 0453..0472 -- compiled, and the shape names the field: `LES DI,ES:[DI+$16]`
      loads a FAR POINTER out of the descriptor and then `MOV AX,DI` / `MOV AX,ES`
      take its halves, which is `Ofs(P^)` and `Seg(P^)` -- an Ofs of a
      dereference, not of the field. }
    Raw.SplOfs2 := Ofs(Desc^.Xtra^);
    Raw.SplSeg2 := Seg(Desc^.Xtra^);

    { [1.39b] "If there is a loop, a small mess :-)" -- the author's own
      assessment of the arithmetic below, and a fair one. A loop inside a sample
      that spans two 64K parts has to be expressed in whichever part it lands
      in, so each of the three quantities gets a test and a subtraction. }
    if NoLoop = 0 then                              { 0473..047c            }
    begin
      { 047d..04b1 -- two LongInt comparisons with short-circuit `or`. The loop
        needs no splitting if it lies wholly inside one 64K part: either it
        starts beyond the boundary, or it starts and ends below it. `$FFF0` is
        the same 65,520 as above. }
      if (Desc^.Reps > MaxSample) or
         (Desc^.Reps + Desc^.Repl <= MaxSample) then
        { 04b2..04c1 -- the low word only, which is what makes the LongInt
          field assignable to a Word without a cast. }
        Raw.LoopLen := Desc^.Repl
      else
      begin
        { 04c2..04de -- the loop STRADDLES the 64K boundary, so its length is
          measured from the start of the second part and the flag says so.
          `ADD byte,$10` rather than `OR`, which is what `Inc` gives. }
        Raw.LoopLen := Desc^.Repl - MaxSample;
        Inc(NewFlags, rcfLongLoopLen)
      end;

      { 04df..0547 -- and the same question again for the loop's END. The sum is
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
    { 054a..056a -- HAND-WRITTEN, the short-sample path. `AND AL,AL` at 0559 is
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

  { THE GRAVIS PATH. Nothing above this touched the card; everything above set
    up the raw channel the software mixer walks. A Gravis needs none of that --
    it needs to be told where the sample lives IN ITS OWN MEMORY and where its
    loop is, so the same decision comes out as a queued command instead.

    THE EVENT CARRIES ONLY THE ADDRESSES AND A PAN. Volume and pitch are passed
    as the "leave this alone" sentinels, because starting a sample says nothing
    about how loud or how high it should be -- those arrive separately, from
    whatever the note and its effects work out.

    A 9xx MOVES THE START AND NOTHING ELSE. The offset is added to the start
    address; the loop points are still measured from the unshifted sample,
    which is right -- entering a sample part-way in must not move where it
    repeats.

    THE PAN COMES FROM THE SONG rather than from a table in the player, so a
    module that specifies its own channel positions gets them.

    [re] 05a8..065f, compiled. `DS:$0bce` is `DevGUS.Started`, so nothing is
    posted unless the GUS driver is running. Both arms call 12ba:0202; a
    looping sample gets LoopA and EndA measured from the loop, a one-shot gets
    LoopA = -1 and EndA at the end of the sample.

    [re] `$FFFF` BECOMES `-1` because AFreq is a LongInt now: 12ce:0728 and 072a
    are `PUSH -1 / PUSH -1`, two words where 1.31b pushed one. 073c is
    `MOV AX,[BP+4] / XOR DX,DX / ADD AX,ES:[DI+12] / ADC DX,ES:[DI+14]`.

    [re] AND THE PAN IS THE 1.31b NOTE COMING TRUE. The note at `Pannings` said
    the release keeps pan in the SONG and 1.31 keeps it in the player.
    12ce:0731 is `LES DI,[02ca] / ADD DI,AX / MOV AL,ES:[DI+28]`; $02ca is
    `PlayingSong` after this block's +$6 shift, and +$28 plus a base-1 index is
    `TSong.ChannelPan` -- the field SONGUNIT measured from the S3M loader's own
    `ES:[DI+28]`. Two units, two independent measurements, one field. }
  if UsingGUS then                             { 0699..06a3             }
    if (Raw.Flags and rcfDoesLoop) <> 0 then         { 06a4..06af             }
      SetEvent(Chan - 1, $FF, -1, PlayingSong^.ChannelPan[Chan],
               { **`Data` IS A POINTER IN SongElements AND THIS IS A GUS DRAM ADDRESS**, so
        every use of it here is cast. The SongUnit copy declared the field a
        LongInt outright, which made the arithmetic read naturally and was the one
        thing that copy got MORE right than the release -- 12ba:05e0 adds a loop
        offset to it, and you cannot add to a `^TSample`. The cast reinterprets
        and emits nothing; the byte count is the check. }
      Offs + LongInt(Desc^.Data),
               LongInt(Desc^.Data) + Desc^.Reps,
               LongInt(Desc^.Data) + Desc^.Reps + Desc^.Repl)  { 06b0..071f   }
    else
      SetEvent(Chan - 1, $FF, -1, PlayingSong^.ChannelPan[Chan],
               Offs + LongInt(Desc^.Data), -1,
               LongInt(Desc^.Data) + Desc^.Len);          { 0722..076b             }

  { NEW IN v1.51, AND IT IS OUTSIDE THE `UsingGUS` TEST. The false path at 06a1 jumps
    to 076c, which is this store -- so a channel is marked in the wide ring whatever
    the output device is, while the event ring above it is GUS-only. That is what
    makes the published row a description of the SONG rather than of the hardware. }
    WideHit[WideSlot, Chan] := 1                     { 076c..077e             }
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
  NullProcedure($FFFF, 0, 0);                        { 0697..069f            }

  if CtrlBlock.JumpNewPos <> 0 then                    { 06a0..06a6            }
  begin
    CtrlBlock.JumpNewPos := 0;                         { 06a7..06ab            }
    NextSeq := CtrlBlock.JumpPosSeq;                    { 06ac..06b3            }
    NextNote := CtrlBlock.JumpPosNote                     { 06b4..06bb            }
  end;

  NextIdx := (NoteHd + 1) and 0;                  { 06bc..06c5            }
  NoteProcessed := @NoteBuff[NextIdx];                 { 06c6..06d7            }
  MyMove(NoteBuff[NoteHd], NoteProcessed^, SizeOf(TPlayingNote));  { 06d8..06ed   }
  NoteHd := NextIdx;                              { 06ee..06f3            }

  with NoteProcessed^ do
  begin                                              { 0806..080f            }

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
    repeat                                           { 081d                  }
    EoMod := NextNote = $FFFF;                        { 0810..081f            }

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
    Volume := UserVols;                              { 0870..0884            }

      if Song.GetPatternSequence(SeqPlaying) >=
         Song.Patterns.Count then                    { 0892..08bd            }
      begin
        Inc(NextSeq);                                { 08be..08c1            }
        if NextSeq > MySongLen then                  { 08c2..08ca            }
          NextNote := $FFFF                          { 08cb..08d0            }
        else
          NextNote := 1                              { 08d3..08d8            }
      end
    until Song.GetPatternSequence(SeqPlaying) <
          Song.Patterns.Count;                       { 08d9..090a            }

    { NEW IN v1.51 -- the wide ring learns where the song is. These are the two loose
      bytes PublishWideRow later hands to CB+$1AD and CB+$1AE, and this is the writer
      that says which is which. }
    WideNoteRing[WideSlot] := NotePlaying;           { 090b..0919            }
    WideSeqRing[WideSlot]  := SeqPlaying;            { 091a..0928            }

    { 0773..078d -- `Pattern := Song.GetPatternSeq(SeqPlaying)`, a far call into
      14b9, which is src/SONGUNIT.PAS. THAT UNIT WAS A STUB WHEN THIS WAS
      WRITTEN AND IS COMPLETE NOW -- it compiles and reproduces its segment --
      but the note stands for a different reason than it did: the call site
      is real: the arguments, their order and the far linkage are read off these
      bytes, and the target is a pending fixup exactly as the linker would leave
      it. The position is pushed FIRST, so it is the first declared parameter and
      `Song` the second; 1.39b calls the equivalent as a method, which its own
      history block explains -- `TSong` became an object in February 1993. }
    Pattern := Song.GetPatternSeq(SeqPlaying);       { 0773..078d            }

    { 078e..07c1 -- advance one row, or fall off the end of the pattern and
      advance the order position instead. `Pattern^.Patt^` is a byte reached
      through a far pointer at the pattern's +$06; a position past the last one
      sets the row to $FFFF, which is the marker 06fe tests on the next call. }
    { **`NNotes` AND `Patt` ARE SongElements' NAMES FOR THE SAME TWO BYTES.** The
      operand ORDER stays as it is: 1.39b writes `IF NextNote < Patt^.Patt^.NNotes`
      and the original's codegen here puts the field first. A field rename is free
      and flipping a comparison is not. }
    if Pattern^.Patt^.NNotes > NextNote then          { 078e..07a0            }
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
      the branch, which a byte placeholder cannot do. See src/SONGUNIT.PAS. }
    if Song.GetPatternSequence(SeqPlaying) = 0 then   { 07c2..07dc            }
    begin
      CurSpeed := Song.InitialTempo;                       { 07dd..07e6            }
      CurTempo := Song.InitialBPM;                       { 07e7..07f2            }
      FillChar(Canales, SizeOf(Canales), 0);           { 07f3..0801            }

      { A silent note at period 800 in every channel. }
      { `CMP [02fc],10h` in v1.51 against 1.31b's `CMP ..,08` -- the literal follows
        the channel count, so it goes through the constant now. }
      for NextIdx := 1 to MaxChannels do               { 09b7..09c2, 09f3..09f9 }
        with Canales[NextIdx] do
        begin
          Note.Period     := 800;                      { 081d..0825            }
          Note.Instrument := 1;                        { 0826..082c            }
          Note.Command    := mcNone;                   { 082d..0834            }
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
        if Pattern^.Patt^.Tempo <> 0 then              { 08cf..08dd            }
          CurSpeed := Pattern^.Patt^.Tempo             { 08de..08ec            }
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

      { NEW IN v1.51 -- A CHANGE OF INSTRUMENT MARKS THE CHANNEL IN THE WIDE RING,
        and it is a narrower test than the retrigger below: only the instrument
        number, not the period. 12ce:0b2a compares the channel's current instrument
        against the new note's and sets the flag when they differ. }
      if (NewNote.Instrument <> 0) and
         (CurCanal^.Note.Instrument <> NewNote.Instrument) then  { 0b1c..0b2f    }
        WideHit[WideSlot, ChanIdx] := 1;               { 0b30..0b40             }

      NewSample := False;                              { 0b41..0b45             }

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
          (NewNote.Command <> mcNPortamento) and
          (NewNote.Command <> mcT_VSlide)) then
      begin
        { 098f..09c7 -- a new instrument: remember it and fetch its sample data. }
        if NewNote.Instrument <> 0 then                { 098f..0995            }
        begin
          CurCanal^.Note.Instrument := NewNote.Instrument;      { 0996..099f   }
          { `Instr`, and the rename is the proof the six bytes ahead of it were a
            VMT word and a name: GetInstrument returns a `PInstrument` OBJECT, and
            the pointer at +$06 is its `Instr` field. The local copy called the
            object a record and the field `Data`. }
          CurCanal^.Instrument :=
            Song.GetInstrument(NewNote.Instrument)^.Instr      { 09a0..09c7   }
        end;

        { 09c8..09e5 -- and hand the sample to the GUS voice. This is the call
          site that gave SetNewSample its signature back when 03cc was
          transcribed: the channel number as a Byte, the raw channel by
          reference, the descriptor by value. }
        SetNewSample(ChanIdx, RawChannels[ChanIdx],
                     CurCanal^.Instrument, 0);         { 0ba8..0bc5            }
        NewSample := True                              { 0bc6..0bcb            }
      end;

      { 09e6..0a0e -- a new instrument also resets the channel's volume to that
        instrument's own default, which lives at the descriptor's +$0c. The nil
        test is `MOV AX,[DI+6] / OR AX,[DI+8]`, both halves of the pointer, which
        is how Turbo Pascal compares a Pointer against nil. }
      if (NewNote.Instrument <> 0) and
         (CurCanal^.Instrument <> nil) then            { 09e6..09fa            }
        CurCanal^.Volume := CurCanal^.Instrument^.Vol;   { 09fb..0a0e       }

      { 0a0f..0a37 -- the note's own volume overrides it, stored one lower than
        written, and clamped to 64 whichever way it arrived. }
      if NewNote.Volume <> 0 then                    { 0a0f..0a15            }
        CurCanal^.Volume := NewNote.Volume - 1;      { 0a16..0a23            }
      if CurCanal^.Volume > 64 then                  { 0a24..0a2e            }
        CurCanal^.Volume := 64;                      { 0a2f..0a37            }

      { 0a38..0a4c -- hand the note to the effects unit. `CommandStart` is the
        release's name and the argument order is its own; see MODCOMMA.PAS. }
      CommandStart(Song, CurCanal^, NewNote);        { 0c18..0c2c            }

      { NEW IN v1.51 -- THE SAMPLE IS HANDED OVER A SECOND TIME, and this is the far
        end of the 9xx path. `CommandStart` has just run, so if the row carried a
        sample-offset command `StartSampleOffs` has set `SOffs` and `SOffsVal` by
        now; re-issuing the sample with the offset is what makes the effect audible.
        `NewSample` is what stops it firing on a row that did not start a sample at
        all -- the offset would then apply to a note already part-way through.

        BOTH HALVES OF THIS FEATURE WERE MEASURED BEFORE EITHER WAS NAMED. 147d:0369
        set the two fields, 12ce:04bb grew the parameter that carries the value, and
        only 1.39b's own call site joined them up. }
      if NewSample and CurCanal^.SOffs then          { 0c2d..0c3e            }
        SetNewSample(ChanIdx, RawChannels[ChanIdx],
                     CurCanal^.Instrument,
                     CurCanal^.SOffsVal);            { 0c3f..0c60            }

      { 0a4d..0a57 -- and NOT `Tempo := CurSpeed`, which is what the enclosing
        `with` would give. The original reloads the pointer from DS:$02dc, so the
        source names it: inside a `with P^ do`, writing `P^.Field` explicitly
        makes Turbo Pascal reload P instead of using the with-slot. Two different
        instruction sequences for the same assignment. }
      NoteProcessed^.Tempo := CurSpeed;                   { 0a4d..0a57            }

      { 0a58..0a72 -- publish the channel's event into the note ring, where
        12ba:0187 will increment the semaphore it names. The ring is indexed by
        the CONSUMER's slot, DS:$02ec, not the event ring's. }
      NoteRing[EventSlot, ChanIdx - 1].Pending :=
        CurCanal^.RingPending;                       { 0a58..0a72            }
      NoteRing[EventSlot, ChanIdx - 1].Sem :=
        CurCanal^.RingSem;                           { 0a73..0a8d            }
      CurCanal^.RingPending := 0                        { 0a8e..0a96            }
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
  if UsingGUS then                                 { 0e70..0e77            }
  begin
    if (RingSlot + 1) mod RingRows = FlushSlot then { 0e78..0e8c            }
      Exit;
    Inc(RingSlot);                                 { 0e8d..0e90            }
    if RingSlot > RingRows - 1 then                { 0e91..0e97            }
      Dec(RingSlot, RingRows)                      { 0e98..0e9c            }
  end;

  if IsDmaDevice and (TickSnapshot = Ticks) then     { 0e9d..0eaf            }
    Exit;
  Inc(TickSnapshot);                                 { 0c65..0c68            }

  if ModFlag and not UsingGUS then                 { 0c69..0c76            }
  begin
    MixTick(Song);                                   { 0c77..0c7e            }
    if ModFlag then                                  { 0c7f..0c85            }
      Exit                                           { 0c86                  }
  end;

  { ~~if UsingGUS then FlushEventRow~~ -- **GONE IN v1.51, AND DEVGUS IS WHY.** The
    consumer now runs from the timer interrupt: 106e:0019 is `CALLF FlushEventRow`,
    so draining the ring is no longer the sequencer's job. What replaces the call
    here is the wide ring's own advance, which IS the sequencer's. 12ce:0ed4 and 0ed7
    are two bare near CALLs with nothing between them. }
  AdvanceEventRow;                                   { 0ed4..0ed6            }
  PublishWideRow;                                    { 0ed7..0ed9            }

  Inc(TickCount);                                    { 0eda..0edd            }

  { 0c9a..0ca3 -- a 32-bit counter INSIDE the published control block, at
    CtrlBlock + $125, immediately after the dispatch pointer. Together with the
    per-channel counters 12ba:0187 bumps, that is live state any INT 2Fh client
    can read. Psycho Neurosis never does. }
  Inc(CtrlBlock.TickCounter);                            { 0ede..0ee7            }

  { **MOVED UP IN v1.51** -- 1.31b assigns this 170 bytes further down, immediately
    before the hand-written loop that reads it. Nothing between the two positions
    touches it, so the move changes no behaviour and it is transcribed where the
    original puts it. }
  TickChans := Song.NumChannels;                     { 0ee8..0ef1            }

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
  if TickInRow <> PrevTick then                      { 0f0e..0f18            }
    TempoAccum := TempoAccum mod TempoDiv;           { 0f19..0f25            }

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
  TmpVal := TickInRow - PrevTick;                  { 0f26..0f31            }
  TickInRow := PrevTick;                             { 0f32..0f37            }

  for TickIter := TmpVal downto 1 do               { 0f38..0f48, 0fa5..0fab }
  begin
    Inc(TickInRow);                                  { 0f49..0f4c            }

    { The row is over when its tick count is reached. `Tempo` is the release's name
      and its comment is "Number of ticks the note will last". }
    if TickInRow >= NoteProcessed^.Tempo then        { 0f4d..0f59            }
    begin
      NextPattern(Song);                             { 0f5a..0f61            }
      if not Playing then                            { 0f62..0f6b            }
        Exit;                                        { 0f69                  }
      TickInRow := 0                                 { 0f6c..0f70            }
    end;

  { ~~TWO `NullProcedure` CALLS STOOD HERE~~ AND v1.51 HAS NEITHER. 1.31b brackets
    the effect loop with `NullProcedure($FFFF, 0, 0)` before it and
    `NullProcedure($FFFF, $FFFF, 0)` after; 12ce:0ffc runs from the tempo loop's last
    instruction straight into `LES DI,[BP+4]`, with no `PUSH -1` anywhere between.
    They were debugging colour-bar markers -- 1.39b's equivalent is a commented-out
    `SetBorder` -- and the release took them out. }

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
    if (TickInRow > 0) or (Song.FirstTick <> 0) then  { 0f71..0f81            }
      asm
      XOR     CH, CH                 { 0d75                                   }
      MOV     CL, TickChans          { 0d77                                   }
  @@Chan:
      PUSH    CX                     { 0d7b                                   }
      MOV     AL, CL                 { 0d7c                                   }
      DEC     AL                     { 0d7e                                   }
      { `$2E` IN v1.51 AND `$26` IN 1.31b -- the stride is SizeOf(TCanal), and the
        record grew eight bytes when the retrigger, the sample offset and the S3M
        volume fields went in. Written through SizeOf so the two cannot drift; the
        original has the literal, and a literal is what a hand-written loop would
        have, but a wrong literal here would silently index into the wrong channel. }
      MOV     BL, $2E                { 0f8d  46 in v1.51, 38 in 1.31b         }
      MUL     BL                     { 0d82                                   }
      MOV     SI, OFFSET Canales     { 0d84                                   }
      ADD     SI, AX                 { 0d87                                   }
      MOV     BL, [SI+$04]           { 0d89  Note.Command                     }
      ADD     BL, BL                 { 0d8c  doubled -- a word index          }
      XOR     BH, BH                 { 0d8e                                   }
      CALL    FAR PTR CommandTick    { 0d90                                   }
      POP     CX                     { 0fa2                                   }
      LOOP    @@Chan                 { 0fa3                                   }
      end
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
    { **$7F IN v1.51, $80 IN 1.31b** -- 12ce:10bd stores 7F. One less than the power
      of two, which is what a clamp to "the largest value that fits" looks like when
      the consumer treats the top bit as a sign. }
    { **THE TEST IS $80 AND THE STORE IS $7F**, which is not a slip: the clamp admits
      everything below $80 and pins the rest at the largest value that is not $80. }
    if RawPtr^.Volume >= $80 then                    { 10b3..10bd            }
      RawPtr^.Volume := $7F;                         { 10be..10c6            }

    { 0e5e..0e6f -- the master volume, and HAND-WRITTEN. Two tells: the pointer
      goes into SI, where Turbo Pascal's code generator always uses DI, and the
      multiply is the 8-bit `MUL BL` with the product's high byte stored straight
      back -- Pascal promotes `Byte * Byte` to a word and would emit `MUL DX`
      followed by a shift.

      Equivalent Pascal, REFERENCE ONLY:

          RawPtr^.Volume := RawPtr^.Volume * CtrlBlock.SoundVolume shr 8 }
    asm
      LES     SI, RawPtr                 { 0e5e                              }
      MOV     AL, ES:[SI+$1d]            { 0e62  Volume                      }
      MOV     BL, CtrlBlock.SoundVolume    { 0e66                              }
      MUL     BL                         { 0e6a                              }
      MOV     ES:[SI+$1d], AH            { 0e6c  the high byte = shr 8        }
    end;

    { 10d5..10e4 -- a period of zero would divide by zero downstream. }
    if CanalPtr^.Period = 0 then                     { 10d5..10de            }
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
    if CanalPtr^.Period > $1FFF then                 { 10e5..10f0            }
      CanalPtr^.Period := $1FFF;                     { 10f1..10fa            }

    { 0e85..0ec4 -- turn the channel's period into the one the hardware wants,
      scaled by the instrument's own ratio when there is an instrument.

      THE ARITHMETIC IS HAND-WRITTEN: the pointer goes into SI throughout, and
      Turbo Pascal's code generator uses DI for every dereference it makes. Same
      tell as 0e5e, twelve instructions earlier.

      Equivalent Pascal, REFERENCE ONLY:

          CanalPtr^.RealPeriod := CanalPtr^.Period * Instrument^.NAdj
                                  div Instrument^.DAdj }
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
      RawPtr^.Flags := RawPtr^.Flags and not rcfActiveChannel   { 1148..1153 }
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
    if CanalPtr^.RealPeriod < $1F then               { 1154..115e            }
      CanalPtr^.RealPeriod := $1F                    { 115f..1168            }
    else if CanalPtr^.RealPeriod > $1FFF then        { 116b..1176            }
      CanalPtr^.RealPeriod := $1FFF;                 { 1177..1180            }

    { 0ede..0f14 -- the resampling STEP for this channel: NoteCalcVal over the
      real period, rounded, then spread across the two words of a 16.16-ish
      fixed point -- `shl 4` into StepFrac and `shr 12` into StepInt.

      HAND-WRITTEN, and twice over: the pointer is in SI again, and the rounding
      (`ADD DX,DX / CMP DX,BX / JC / INC AX` -- double the remainder and compare
      against the divisor) is not something Turbo Pascal emits for `div`.

      Equivalent Pascal, REFERENCE ONLY:

          StepVal := round(NoteCalcVal / CanalPtr^.RealPeriod) }
    if not UsingGUS then                             { 1181..1187            }
      asm
      MOV     AX, WORD PTR NoteCalcVal      { 1188                           }
      MOV     DX, WORD PTR NoteCalcVal+2    { 0ee1                           }
      LES     SI, CanalPtr                  { 0ee5                           }
      MOV     BX, ES:[SI+$0d]               { 0ee9  RealPeriod                }
      DIV     BX                            { 0eed                           }
      ADD     DX, DX                        { 0eef  twice the remainder       }
      CMP     DX, BX                        { 0ef1  ... at least the divisor? }
      JC      @@NoRound                     { 0ef3                           }
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
      StepVal := $1000                         { 11a5..11b0                     }
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
    with WideRing[WideSlot, TmpVal] do           { 11b1..11c9                     }
    begin
      Period     := CanalPtr^.RealPeriod;        { 11ca..11d7                     }
      Instrument := CanalPtr^.Note.Instrument;   { 11d8..11e5                     }
      Volume     := CanalPtr^.Volume * UserVols[TmpVal] shr 7;   { 11e6..1207     }

      { AND CLAMPED, STILL INSIDE THE `with` -- 12ce:1208 reloads [BP-6] rather than
        the channel pointer, so the test is on the entry just written and not on the
        channel it came from. Two 6-bit volumes multiplied give thirteen bits and the
        shift takes back only seven, so the product can exceed $3F whenever both are
        near full. }
      if Volume > $3F then                       { 1208..1211                     }
        Volume := $3F                            { 1212..1219                     }
    end;

    { `Word(StepVal)` AND NOT `StepVal` -- see the declaration. 121a and 1228 load the
      low word and shift it sixteen bits wide; the LongInt itself would go through the
      RTL and cost a CALLF apiece. }
    RawPtr^.StepFrac := Word(StepVal) shl 4;         { 121a..1227            }
    RawPtr^.StepInt  := Word(StepVal) shr 12;        { 1228..1235            }

    { 0f15..0f29 -- which filter is in force. }
    if FilterIsOn then                               { 0f15..0f1b            }
      FilterVal := FilterOn                          { 0f1c..0f23            }
    else
      FilterVal := FilterOff;                        { 1245..124a            }

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
    if CanalPtr^.DoRetrig then                       { 124b..1255            }
      if CanalPtr^.Instrument <> nil then            { 1256..1263            }
        { `TmpVal` again -- 12ce:1265 loads [0330], the volume loop's own counter. }
        SetNewSample(TmpVal, RawPtr^,
                     CanalPtr^.Instrument, 0);       { 1264..127e            }

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
                  PlayingSong^.ChannelPan[TmpVal])   { 12b8..12f7            }
      else
        { `-1` AND NOT `$FFFF`, for the same reason SetNewSample's calls changed:
          PostEvent's AFreq is a LongInt in 1.51, so the sentinel is two words. }
        PostEvent(TmpVal - 1, 0, -1,
                  PlayingSong^.ChannelPan[TmpVal]);  { 12fa..1315            }

    { 0fb4..0fe0 -- and hold the period inside ProTracker's range, 57 to 1712. }
    { **$1F AND $1FFF IN v1.51, WHERE 1.31b HAS PROTRACKER'S 57 AND 1712.** The
      widened bounds are the same pair the RealPeriod clamp uses and are there for the
      same reason: an arpeggio that divides and an S3M loader that supplies arbitrary
      periods both produce values ProTracker's range would reject. 1.31b could afford
      the tight bounds because every period came out of a note table. }
    if CanalPtr^.Period < $1F then                   { 131a..1324            }
      CanalPtr^.Period := $1F                        { 1325..1330            }
    else if CanalPtr^.Period > $1FFF then            { 1331..133c            }
      CanalPtr^.Period := $1FFF                      { 133d..1346            }
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

  { NEW IN v1.51, and it is the first thing PlayStart does after the CLI. Publishing
    the channel count is what makes the thirty-two `ChansTrig` flags above it
    readable -- without it a client cannot tell an idle channel from one the song
    does not have. The bindings describe them as being for VU meters, which is
    exactly what needs to know how many bars to draw. }
  CtrlBlock.NumChannels := Song.NumChannels;       { 1408..1411              }

  PlayingSong := @Song;                            { 1412..141f              }

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
  { **NEW IN v1.51, AND IT IS A DEBUGGING LINE THE RELEASE LEFT IN.** 12ce:174c
    writes a four-character string at CS:$1743 -- `04 'S' 't' 'o' 'p'`, a Pascal
    short string sitting in the code segment -- and then calls SYSTEM's WriteLn.

    NO FILE VARIABLE, WHICH IS WHY IT IS `Output`. The Text pushed is DS:$6890, and
    that is NOT VTShell's `ConFile`: ProgName measures at $5e38 in 1.51 against
    $3ade in 1.31b, a shift of $235a, which would put ConFile at $5d38. $6890 is
    further on and is what a bare `WriteLn` uses.

    So a released player prints "Stop" every time a module ends. Transcribed because
    it is there. }
  WriteLn('Stop');                                 { 174c..1761              }

  Playing := False;                                { 1762..1766              }

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
  FillChar(NoteRing,  SizeOf(NoteRing),  0);       { 1804..1813              }

  { NEW IN v1.51 -- the wide ring and its flag grid are cleared here with the narrow
    one, and the two immediates confirm both shapes independently of the routines
    that use them: `PUSH 0C80h` is 3,200, which is 25 rows of 128 bytes, and
    `PUSH 0320h` is 800, which is 25 rows of 32. }
  FillChar(WideRing,  SizeOf(WideRing),  0);       { 1814..1822              }
  FillChar(WideHit,   SizeOf(WideHit),   0)        { 1823..1831              }
end.
