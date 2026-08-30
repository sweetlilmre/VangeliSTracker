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

  and `TModRawChan`'s FIELD LAYOUT lands on every offset the reading pass had
  already recorded -- `+$0b` the non-looping limit, `+$19` and `+$1b` the 16.16
  step, `+$1d` the byte handed to the kernel, `+$1e` and `+$20` the loop, 34
  bytes in total. That is why it is adopted here and `TSong`'s was not: this one
  is CONFIRMED by the binary, field by field, and 1.39b's `TSong` demonstrably
  did not fit.}
unit PlayMod;

{ $G+ for the 286 instructions, as everywhere else in this tree. }

interface

{ THE SEQUENCER'S POSITION AND SPEED ARE DECLARED IN MODCOMMA, not here, even
  though this unit does the sequencing. The effect commands WRITE those
  variables -- a Bxx jumps to another pattern -- and this unit `uses`
  ModCommands, so the dependency only runs one way. See the note above their
  declaration there.

  Their addresses INTERLEAVE with `MySongLen` at $0340, `FilterIsOn` at $0348
  and the tempo pair, which were already ModCommands' -- and two units' data
  cannot interleave, because the linker lays DGROUP down one unit at a time in
  link order. Nothing about the code changes -- a DGROUP reference is a linker
  fixup either way -- so PLAYMOD still verifying identical with the same 1,187
  pending fixups was the check. }


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
  first runs out, instead of a test in the inner loop.}
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
  its visuals a buffer early, which at these buffer sizes is plainly visible.}
const
  { HOW MANY VOICES THE PLAYER WILL MIX. Not a format limit -- a four-channel
    MOD and a sixteen-channel S3M both fit -- but a cost limit: every extra
    channel is another pass over every output sample.

    THREE DIFFERENT WIDTHS LIVE IN THIS BUILD AT ONCE, and they are not the
    same number by accident. The player mixes sixteen; the published row
    describes thirty-two, because publishing costs almost nothing and a wider
    row outlives this player's limits.}
  MaxChannels = 16;

type
  { A NAMED type on purpose: Turbo Pascal will only assign one array to another
    when both are the SAME named type, and two places in this unit copy a whole
    set of channel volumes in one statement. Declared anonymously they would
    have to be `Move` calls instead.}
  TVolumes = array[1..MaxChannels] of Byte;

  PRingEntry = ^TRingEntry;
  { **THE TWO FIELDS ARE A SEMAPHORE NUMBER AND A PENDING FLAG**, and they were
    `Chan`/`Note` until DEMOVT.DOC named what they feed. Command 8's parameter
    selects one of 256 semaphores; this carries it from the pattern row to
 which increments `CtrlBlock.Semaphores[Sem]`. Nothing here is a
    channel -- `Chan` indexing a 256-entry array should have been the tell. }
  TRingEntry = record
    Sem     : Byte;             { +$00  which semaphore command 8 asked for  }
    Pending : Byte;             { +$01  nonzero means the entry is live      }
  end;
  TRingRow = array[0..7] of TRingEntry;      { 16 bytes                      }




  { The buffer's data is declared as an untyped Pointer and used as an array of
    16-bit samples; this is the type that makes the second view legal.}
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

  TPlayingNote = record
    EoMod       : Boolean;      { +$00                                       }
    Tempo       : Byte;         { +$01                                       }
    NotePlaying : Byte;         { the row this snapshot is of              }
    SeqPlaying  : Byte;         { and the order position it came from      }
    Volume      : TVolumes;     { every channel's volume                   }
    Note        : array[1..MaxChannels] of TFullNote;   { and every note   }
    NMuestras   : Word;         { the release's name; unused so far        }
    Fill        : Byte;


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
  reading the fields back out in order and calling. No decisions at flush time.}
type
  { `Freq` IS 32 BITS BECAUSE THAT IS WHAT THE DRIVER TAKES. Storing it any
    narrower means widening it again at every flush, and the flush runs under
    an interrupt; carrying the driver's own width costs two bytes a slot and
    nothing else. It also gives the flush a free emptiness test -- a slot with
    no frequency in it is a slot with nothing to do.}
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
    them to stay equal.}
  GusVoices = 16;

type

  TGusEventRow = array[0..GusVoices - 1] of TGusEvent;   { 288 bytes            }





const
  RingRows = 25;

  { THE PUBLISHED ROW IS TWICE AS WIDE AS THE PLAYER. Publishing costs a table
    entry; mixing costs a pass over every sample. So the row that goes out to
    the display and the demo describes thirty-two channels even though this
    player will only ever sound sixteen -- the ring outlives the limit.}
  WideChans = 32;



  { ONE BUFFER, WHERE THE RELEASE USES THREE. More buffers mean more latency
    between a note being mixed and being heard, and this player is driving a
    demo: everything on screen is cut to the music, so the delay is visible as
    well as audible. One buffer is the tightest the hardware allows.}
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
  something that does not show up until the program is linked.}
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




  NewNote          : TFullNote     = (Instrument : 0; Period : 0; Volume : 0;
                                      Command    : mcNone; Parameter : 0);
  CurCanal         : PCanal        = nil;
  Pattern          : PPattern      = nil;      { in v1.51             }

  { Set when this row started a sample. A 9xx sample offset can only be applied
    to a sample that is actually starting, and the command runs AFTER the note
    is set up -- so the note's half leaves this behind for the command's half to
    find.}
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
  { FOUR OF THE VARIABLES IN THIS RUN ARE NEVER READ, HERE OR IN THE RELEASE.
    They are leftovers of an earlier version of the tick routine, and they were
    already leftovers in 1993. They are declared because their SPACE is real --
    everything after them sits where it sits because they are there.

    Every width matches ours, in sequence, with no slack. `incr`, `NoteHzFreq`,
    `FBCount` and `j` occur exactly once each in the whole of 1.39b's PlayMod:
    their own declarations. A variable nothing reads has no witness in the code,
    so the sequence is the only evidence there is -- and it is enough because it
    is exact. }
  Incr             : Integer       = 0;        { the release's `incr`, unread    }
  PrevTick         : Word          = 0;        { the release's `OTempoCt`        }

  CanalPtr         : PCanal        = nil;
  RawPtr           : PModRawChan   = nil;
  NoteHzFreq       : LongInt       = 0;        { unread here and in 1.39b       }
  { ONE VARIABLE, TWO UNRELATED JOBS -- a tempo span first, then a channel
    index -- because the first use is finished before the second begins. This
    unit does that in three places, and it is the original's habit rather than
    an accident, which is why the name here claims nothing about either role.}
  TmpVal           : Word          = 0;
  UnusedIdx        : Word          = 0;        { never read; see above          }

  TickIter         : Word          = 0;        { the tempo loop's counter       }


  StepVal          : LongInt       = 0;
  FBCount          : Word          = 0;        { never read                     }
  TickChans        : Byte          = 0;





{ ==========================================================================
  THIS UNIT'S VARIABLES -- the ones that hold no initial value and so are
  reserved space rather than data: the channel array, the raw mixer channels,
  the sample buffers, and the rings.

  THEY ARE IN ADDRESS ORDER FOR THE SAME REASON THE CONSTANTS ARE. Declaration
  order is layout, and layout is not something a reader can guess back from the
  code.}
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
  UserVols        : TVolumes;             { base-1 base $1207 }

{ NEGOTIATE AN OUTPUT RATE. The caller ASKS for a rate; the card answers with
  what it can actually do, the buffers are sized for that, and the DMA is
  programmed. It can also be called again mid-song, which is why it exists as a
  routine rather than as part of starting playback.}
procedure ChangeSamplingRate(Hz : Word); far;
{ RELEASE ONE ROW OF QUEUED GUS COMMANDS. Called from the GUS driver's
  interrupt handler, once per buffer, which is what ties the queue to the sound
  actually being heard rather than to the sequencer's position.}
procedure FlushEventRow; far;

procedure ProcessTickEntry; far;

{ Stop playing and hand the buffers back. Also called from inside PlayStart's
  own failure path, which is why it has to work on a player that never fully
  started.}
procedure PlayStop; far;

{ Start playing a module: take the requested range, set up the channels, size
  and claim the buffers, and hand the first of them to the card.}
procedure PlayStart(var Song : TSong); far;

implementation






































type
  { ASK A DEVICE WHAT RATE IT CAN ACTUALLY DO. The player names a rate it would
    like; the driver answers with the nearest one its hardware can produce, and
    that answer is what the buffers are sized for. Every card gives a different
    answer, which is why this is a call into the driver rather than a table.}
  TGetFreqProc = function(Hz : Word) : Word;

  { WHAT RUNS ON EVERY TICK. A client can install its own; the player calls it
    once per tick with the song and a flag saying whether this tick begins a new
    row, which is the distinction almost every caller cares about.}
  TTickProc = procedure(var Song : TSong; Note : Boolean);

{ ...and the rest, private but in the same run -- see the note above. }
var
  Permisos        : array[1..MaxChannels] of Boolean;  { base-1 base $120f }
  TickCount       : Word;
  ModTickProc     : TTickProc;
  MyCanFallBack   : Boolean;
  FilterVal       : TFilterMethod;
  NoteBuff        : array[0..0] of TPlayingNote;  { 63 bytes, then a pad }
  Canales         : array[1..MaxChannels] of TCanal;  { base-1 base $123a }
  BuffIdx         : Word;
  BuffGive        : Word;
  Buffers         : array[1..NumBuffers] of TSampleBuffer;
  SizeOfABuffer   : Word;
  ModFlag         : Boolean;
  MuestrasPerTick : Word;
  RawChannels     : array[1..MaxChannels] of TModRawChan;  { base-1 base $1384 }
  NoteRing        : array[0..RingRows - 1] of TRingRow;

  { NEW IN v1.51 -- THE WIDE RING, and its shape is read off three multipliers.
 is `SHL DI,7`, so a row is 128 bytes; 0243 is `SHL DI,5`, so the
    flag grid is 32 bytes a row; and 0206..0211 is `INC / CMP 18 / SUB 19`, so
    there are 25 rows exactly as the narrow ring has. }
  WideRing        : array[0..RingRows - 1] of TChansData;
  WideHit         : array[0..RingRows - 1, 1..WideChans] of Byte;

  { WHERE IN THE SONG EACH PUBLISHED ROW CAME FROM -- the row number and the
    order position, one byte each. They ride the ring alongside the row so that
    a reader picking up a row a quarter of a second later still knows which
    moment of the music it belongs to.}
  WideNoteRing     : array[0..RingRows - 1] of Byte;
  WideSeqRing    : array[0..RingRows - 1] of Byte;
  EventRing       : array[0..RingRows - 1] of TGusEventRow;



















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
  there is a `Silent` flag. The release later split it in two.}

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
 pushes `6a ff / 6a 00 / 6a 00`, three immediates. A Pointer argument
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
  position honest whether it is sounding or not.}
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
  again, so nothing has to track which slots are stale.}
procedure AdvanceEventRow;
begin
  { a hand-written CLD, and it has to be hand-written: Turbo Pascal
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
    {      Turbo Pascal wants a pointer VALUE in AX:DX to assign; the original never
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
  { the same hand-written CLD as AdvanceEventRow's, and for the same
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
  QUEUE A COMPLETE VOICE COMMAND. Everything the GUS needs to start a note --
  volume, pitch, pan and the three addresses that define the sample and its
  loop -- written into one slot, to be handed to the card when this row's sound
  is due.

  IT TESTS NOTHING. This is the raw setter, used when a note is genuinely
  starting; `PostEvent` below is the one that merges into a slot that may
  already be occupied.

  THE PARAMETERS ARE DELIBERATELY NOT NAMED AFTER THE FIELDS. Inside a `with`,
  an unqualified name binds to the record's field first, so `Vol := Vol` would
  quietly assign a field to itself.}
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
  with no sentinel test at all, so a caller cannot decline to set it.}
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
  HAND ONE ROW OF QUEUED COMMANDS TO THE CARD. Called from the GUS driver's
  interrupt when a buffer completes, which is what makes the queue release in
  step with what is actually being heard.

  ADVANCE, APPLY, WIPE -- in that order, and the wipe is what lets an empty
  slot be recognised by a zero frequency alone.

  A SLOT IS EITHER A NEW NOTE OR AN ADJUSTMENT, and the loop addresses are what
  tell them apart: a command carrying a sample end starts a voice from
  scratch, one without it only changes the pitch, volume and pan of a voice
  already running. Two different driver calls, chosen per slot.}
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

  Both are correct at run time, because `RawChannels` is in DGROUP and the
  segment the caller pushed IS DS -- but Turbo Pascal's code generator emits
  only the far form for a `var` parameter. The tell that settles it is `21 C0`
  at 03f7: `AND AX,AX` in the `r/m,reg` direction, which the INLINE ASSEMBLER
  emits and the code generator does not (it tests with `OR`, as `08 C0` at
 and `0B 46 06` at 03d2 both show). In TP's asm a `var` parameter
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

  if Desc <> nil then
  begin
    { HAND-WRITTEN, transcribed verbatim per the standing rule.
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

    { compiled: Turbo Pascal's LongInt comparison, high word
      first, `CMP ES:[DI+2],0 / JG / JGE / CMP ES:[DI],$FFF0 / JA`. $FFF0 is
      [1.39b] "Comes here if it is a long sample (more than 65520 bytes)", and
      on the other arm "Comes here if it is a short sample (less than 65520
      bytes)" -- the release's own words for the two branches below.

      65,520, which is what `rcfLongSample` means: a sample too long for one
      64K part. }
    if Desc^.Len > MaxSample then
    begin
      { HAND-WRITTEN again, and the DS-relative store at 0437 is
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

    { compiled, and the shape names the field: `LES DI,ES:[DI+$16]`
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
      { two LongInt comparisons with short-circuit `or`. The loop
        needs no splitting if it lies wholly inside one 64K part: either it
        starts beyond the boundary, or it starts and ends below it. `$FFF0` is
        the same 65,520 as above. }
      if (Desc^.Reps > MaxSample) or
         (Desc^.Reps + Desc^.Repl <= MaxSample) then
        { the low word only, which is what makes the LongInt
          field assignable to a Word without a cast. }
        Raw.LoopLen := Desc^.Repl
      else
      begin
        { the loop STRADDLES the 64K boundary, so its length is
          measured from the start of the second part and the flag says so.
          `ADD byte,$10` rather than `OR`, which is what `Inc` gives. }
        Raw.LoopLen := Desc^.Repl - MaxSample;
        Inc(NewFlags, rcfLongLoopLen)
      end;

      { and the same question again for the loop's END. The sum is
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
    { HAND-WRITTEN, the short-sample path. `AND AL,AL` at 0559 is
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

  { HAND-WRITTEN, and common to both paths. It turns the LENGTHS
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
    module that specifies its own channel positions gets them.}
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
MyMove. A hand-written Move, and the 1.39b release has it
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
advance to the next pattern, and honour a seek request.
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
 is `XOR DX,DX` on the call's result -- a Word, unsigned -- and 08b3 is
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

    { `Pattern := Song.GetPatternSeq(SeqPlaying)`, a far call into
      14b9, which is src/SONGUNIT.PAS. THAT UNIT WAS A STUB WHEN THIS WAS
      WRITTEN AND IS COMPLETE NOW -- it compiles and reproduces its segment --
      but the note stands for a different reason than it did: the call site
      is real: the arguments, their order and the far linkage are read off these
      bytes, and the target is a pending fixup exactly as the linker would leave
      it. The position is pushed FIRST, so it is the first declared parameter and
      `Song` the second; 1.39b calls the equivalent as a method, which its own
      history block explains -- `TSong` became an object in February 1993. }
    Pattern := Song.GetPatternSeq(SeqPlaying);

    { advance one row, or fall off the end of the pattern and
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

    { an EMPTY order position. `GetPatternSequence` returning zero
      means there is no pattern here, so the module's own defaults come back, every
      channel is wiped and given a silent note, and the sequencer walks forward
      until it finds a position that does have one -- or runs off the end.

      This block was blocked until 14b9 could be declared: the call's result drives
      the branch, which a byte placeholder cannot do. See src/SONGUNIT.PAS. }
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

      { walk forward. A position past the last sets the row to
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

    { the SPEED for this row, if anything overrides it. Two sources,
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

    { once per channel: fetch this row's note out of the song and
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

      { DOES THIS ROW RETRIGGER THE CHANNEL? Two groups joined by
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
        { a new instrument: remember it and fetch its sample data. }
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

        { and hand the sample to the GUS voice. This is the call
          site that gave SetNewSample its signature back when 03cc was
          transcribed: the channel number as a Byte, the raw channel by
          reference, the descriptor by value. }
        SetNewSample(ChanIdx, RawChannels[ChanIdx],
                     CurCanal^.Instrument, 0);
        NewSample := True
      end;

      { a new instrument also resets the channel's volume to that
        instrument's own default, which lives at the descriptor's +$0c. The nil
        test is `MOV AX,[DI+6] / OR AX,[DI+8]`, both halves of the pointer, which
        is how Turbo Pascal compares a Pointer against nil. }
      if (NewNote.Instrument <> 0) and
         (CurCanal^.Instrument <> nil) then
        CurCanal^.Volume := CurCanal^.Instrument^.Vol;

      { the note's own volume overrides it, stored one lower than
        written, and clamped to 64 whichever way it arrived. }
      if NewNote.Volume <> 0 then
        CurCanal^.Volume := NewNote.Volume - 1;
      if CurCanal^.Volume > 64 then
        CurCanal^.Volume := 64;

      { hand the note to the effects unit. `CommandStart` is the
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

      { and NOT `Tempo := CurSpeed`, which is what the enclosing
        `with` would give. The original reloads the pointer from DS:$02dc, so the
        source names it: inside a `with P^ do`, writing `P^.Field` explicitly
        makes Turbo Pascal reload P instead of using the with-slot. Two different
        instruction sequences for the same assignment. }
      NoteProcessed^.Tempo := CurSpeed;

      { publish the channel's event into the note ring, where
 will increment the semaphore it names. The ring is indexed by
        the CONSUMER's slot, DS:$02ec, not the event ring's. }
      NoteRing[EventSlot, ChanIdx - 1].Pending :=
        CurCanal^.RingPending;
      NoteRing[EventSlot, ChanIdx - 1].Sem :=
        CurCanal^.RingSem;
      CurCanal^.RingPending := 0
    end;                                             { for end   }

    { how many samples this row is worth.

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
 The author wrote one of these two the long way and not the other,
      in the same routine, ten instructions apart. }
    NMuestras := Tempo * MuestrasPerTick;

    NoteHz := ActualHz;
    if NoteHz = 0 then
      NoteHz := 1;

    { A DIVISION AND THEN A SHIFT, NOT TWO DIVISIONS. `1ba1:0a2e` is the
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

    { publish the row. The tail index catches up with the head and
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

  { mix every channel, unless the device does its own DMA mixing.
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

  { and mark the entry played, with the sample count it produced.
    Both paths reach here: the DMA one jumps straight to it from 0b63. }
  ModRec^.InUse    := True;
  ModRec^.NSamples := MuestrasPerTick;
  ModRec^.RateHz   := NoteHz;
  ModRec^.DataType := 1;
  ModRec^.Channels := Song.NumChannels;

  { AND THE SECOND DISABLED ROTATION IN THIS UNIT. `Inc(ModIdx)`
    followed by a clamp to 1 means the index is 1 from the first call onward, so
    only one entry of the module table is ever used -- exactly like the `and 0` at
 pinning the note buffer to slot zero. Two independent pieces of
    machinery for handling more than one of something, both switched off by their
    own next instruction. Transcribed as found. }
  Inc(BuffIdx);
  if BuffIdx > 1 then
    BuffIdx := 1;

  NullProcedure(0, $FFFF, 0)
end;

{ --------------------------------------------------------------------------
the sequencer tick, and the tempo engine. IN PROGRESS.

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

  { a 32-bit counter INSIDE the published control block, at
    CtrlBlock + $125, immediately after the dispatch pointer. Together with the
    per-channel counters 12ba:0187 bumps, that is live state any INT 2Fh client
    can read. Psycho Neurosis never does. }
  Inc(CtrlBlock.TickCounter);

  { **MOVED UP IN v1.51** -- 1.31b assigns this 170 bytes further down, immediately
    before the hand-written loop that reads it. Nothing between the two positions
    touches it, so the move changes no behaviour and it is transcribed where the
    original puts it. }
  TickChans := Song.NumChannels;

  { THE TEMPO ENGINE, and it divides nothing per row. `TempoAccum`
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

  { run every channel's effect for this tick, unless this is the
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

  { the fall-back request. `PleaseFallback` is SoundDevices' way of
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

    { NEGOTIATE A RATE THE DEVICE WILL ACCEPT. Ask what it can
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

    { and act on it. `PUSH CS / CALL near` is how Turbo Pascal
      calls a FAR routine that lives in the same segment, which is what
      ChangeSamplingRate is. }
    ChangeSamplingRate(DesiredHz)
  end;




  { turn each channel's own volume into the mixing volume the
    resampler will use. The divisor is the channel count rounded UP to an even
    number, so the summed output cannot clip; the `shr 4` is the fixed-point
    scale on UserVols. }
  for TmpVal := 1 to Song.NumChannels do
  begin
    CanalPtr := @Canales[TmpVal];
    RawPtr   := @RawChannels[TmpVal];
    if not UsingGUS then
      { the software path: divide the sum down so it cannot clip. }
      RawPtr^.Volume := CanalPtr^.Volume * UserVols[TmpVal] shr 4
                        div ((Song.NumChannels + 1) and $FFFE)
    else
      { the GUS path needs no headroom, because the card mixes: the
        scale is `shr 6` with a rounding `+1` before the final halving. }
      RawPtr^.Volume := (CanalPtr^.Volume * UserVols[TmpVal] shr 6 + 1) shr 1;

    { AND THESE TWO ARE COMMON TO BOTH PATHS. The software branch's
      `JMP` at 0e22 lands on 0e4a, not past it, which is what says so; written
      inside the GUS branch they would be jumped over. }
    { **$7F IN v1.51, $80 IN 1.31b** -- 12ce:10bd stores 7F. One less than the power
      of two, which is what a clamp to "the largest value that fits" looks like when
      the consumer treats the top bit as a sign. }
    { **THE TEST IS $80 AND THE STORE IS $7F**, which is not a slip: the clamp admits
      everything below $80 and pins the rest at the largest value that is not $80. }
    if RawPtr^.Volume >= $80 then
      RawPtr^.Volume := $7F;

    { the master volume, and HAND-WRITTEN. Two tells: the pointer
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

    { a period of zero would divide by zero downstream. }
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

    { turn the channel's period into the one the hardware wants,
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
      { no instrument, so there is nothing to play: the period is
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

    { the resampling STEP for this channel: NoteCalcVal over the
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
 that 12ce:11c4 builds and every field store reloads with
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

    { which filter is in force. }
    if FilterIsOn then
      FilterVal := FilterOn
    else
      FilterVal := FilterOff;

    { **NEW IN v1.51 -- THIS IS WHERE THE RETRIGGER ACTUALLY RETRIGGERS.** MODCOMMA
      only ever sets a flag: 147d:05d8 counts ticks and raises `DoRetrig`, and
 clears it again on the next dispatch, so it is true for exactly one
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

    { and whether this channel is allowed to sound at all.

      WRITTEN AS A NEGATIVE. The test emits `JNZ` to the branch that SETS the
      bit, which is what `if not Permisos[..] then <clear> else <set>` gives; the
      positive form would put the setting branch first and jump on zero. One
      instruction decides which way round the source reads. }
    if not Permisos[TmpVal] then
      RawPtr^.Flags := RawPtr^.Flags and not rcfActiveChannel
    else
      RawPtr^.Flags := RawPtr^.Flags or rcfActiveChannel;

    { on the GUS, tell the card. A permitted channel gets its
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

    { and hold the period inside ProTracker's range, 57 to 1712. }
    { **$1F AND $1FFF IN v1.51, WHERE 1.31b HAS PROTRACKER'S 57 AND 1712.** The
      widened bounds are the same pair the RealPeriod clamp uses and are there for the
      same reason: an arpeggio that divides and an S3M loader that supplies arbitrary
      periods both produce values ProTracker's range would reject. 1.31b could afford
      the tight bounds because every period came out of a note table. }
    if CanalPtr^.Period < $1F then
      CanalPtr^.Period := $1F
    else if CanalPtr^.Period > $1FFF then
      CanalPtr^.Period := $1FFF
  end;                                               { for end   }

  NullProcedure(0, 0, 0);

  { and on a non-GUS device, mix this tick's samples now that every
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
 -- the two buffer callbacks the sound device asks
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
 that nothing in the routine ever touches, and the four-byte `with`
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

  { an unset END comes from the song too, but only if the song's own
    figure is set AND fits inside the length. Three tests, short-circuited. }
  if (RangeEnd = 0) and (Song.SequenceRepStart <= MySongLen) and
     (Song.SequenceRepStart <> 0) then
    RangeEnd := Song.SequenceRepStart;

  { whether the module may loop.

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

  { and reset the playing state. `TickInRow := $FE` is a sentinel:
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

  { prime the first row and the queue that hands it on. The stores
    land on $1220, $1221, $1222, $1223 and then an 8-byte Move to $1224, which is
    NoteBuff[0]'s EoMod, Tempo, NotePlaying, SeqPlaying and Volume -- the layout
    fixed at 12ba:094b, confirming itself from a different routine. `$125c` is its
    NMuestras at +$3c. Tempo starts at 6, ProTracker's default. }
  NoteBuff[0].EoMod       := False;
  NoteBuff[0].Tempo       := 6;
  NoteBuff[0].NotePlaying := 0;
  NoteBuff[0].SeqPlaying  := 0;
  NoteBuff[0].Volume := UserVols;                  { see 075e    }
  NoteBuff[0].NMuestras   := 0;

  NoteHd        := 0;
  NoteTl        := 0;
  NoteSound     := @NoteBuff[0];
  NoteProcessed := @NoteBuff[0];

  { clear the channels, then give each one a starting note.

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

  { and size a buffer. `SHL AX,3 / SHL AX,1` is `* MaxChannels * 2`
    with MaxChannels folded to 8; the compiler reaches for shifts because both
    factors are powers of two, and the PAIR of them is what fixes the 8. }
  SizeOfABuffer := MaxSplPerTick * MaxChannels * 2;

  FillChar(Buffers, SizeOf(Buffers), 0);

  { claim the mixing buffers, but only when the GUS is not driving.
    The GUS plays out of its own on-card memory and never asks for one.

    THE FILL VALUE IS 0 AND THE RELEASE'S IS $7F. Both are silence for their own
    sample format -- $7F is mid-scale for unsigned 8-bit, 0 for signed 16-bit --
    so this is 1.31 filling a Word buffer where 1.39b fills a byte one. The
    immediate at 1292 is `6A 00`; there is nothing to interpret. }
  if not UsingGUS then
    for i := 1 to NumBuffers do
    begin
      { a VIRTUAL call on the heap object at DS:$39ae, through
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

  { and clear both per-channel tables. The EventRing clear is
    1.31's own; the release only clears RawChannels here. }
  FillChar(EventRing, SizeOf(EventRing), 0);
  FillChar(RawChannels, SizeOf(RawChannels), 0);

  { program the hardware for the rate that was asked for, and only
    then let the timer back in. Everything above this point runs under the `CLI`
    from 10a5. }
  ChangeSamplingRate(DesiredHz);

  asm
    STI
  end;

  { hand the device a buffer source and start it.

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
ask the device for a rate it can really manage, and if what comes
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
  MyHz : Word;                    { and the whole of `ENTER 2,0`       }
begin
Otra:
  DesiredHz := Hz;
  MyHz := TGetFreqProc(ActiveDevice^.GetRealFreqProc)(Hz);

  { more samples per second than a tick can hold. The product is
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

    { `MOV SI,AX / SHL AX,1 / ADD AX,SI / SHR AX,1` is
      `TicksPerSecond * 3 div 2` and nothing else: AX becomes T, 2T, 3T, then 3T
      div 2. The release's line carries two commented-out alternative divisors
      beside it, an 8 and a DIV 3, so the ratio was tuned by hand; 1.31's shifts
      fix it at three halves. }
    SetPeriodicProc(ProcessTickEntry, TicksPerSecond * 3 div 2);

    { and size the DMA buffer from the rate. Stereo gets the whole
      figure and mono half of it, then the result is rounded DOWN to a multiple of
      four by `AND AX,FFFC` -- four bytes being one stereo 16-bit frame, which is
      the smallest unit the 8237 may stop on. }
    if Stereo then
      DMABufferSize := ActualHz
    else
      DMABufferSize := ActualHz div 2;

    DMABufferSize := DMABufferSize and $FFFC;

    { reprogram the controller, unless there is no channel to
      program. `$FF` IS THE "NO DMA" SENTINEL, and it is compared as a WORD
      (`81 3E C4 0B FF 00`, six bytes) rather than a byte, which is what settles
      DMAChannel's width -- see the note beside its declaration in SOUNDDEV.

      Mode $58 is single-mode, address-increment, auto-initialise, read (the
      8237 reading memory to feed the card), which is what a continuously
      circling playback buffer needs. }
    if DMAChannel <> $FF then
      DMASet(DMAChannel, $58, DMABuffer, DMABufferSize);

    { and resynchronise the tick gate, because the rate the mixer
      is paced against has just moved. `Ticks` is VTSilenc's and exported;
      TickSnapshot is the copy SeqTick compares it with at 0c52. }
    TickSnapshot := Ticks
  end
end;

{ --------------------------------------------------------------------------
stop playing and give the mixing buffers back.

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
  i : Word;                       { and the whole of `ENTER 2,0`       }
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
THE UNIT'S INITIALISATION SECTION, not a procedure.

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
