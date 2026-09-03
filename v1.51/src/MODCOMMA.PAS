{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  THE EFFECT ENGINE. A tracker module is a grid of notes, and next to almost
  every note sits a COMMAND: slide the pitch up, wobble it, fade the volume,
  jump to another pattern. This unit is where those commands live. It knows
  nothing about mixing samples and nothing about reading files -- it is handed
  one channel and one note, and it changes the channel.

  EVERY COMMAND HAS TWO HALVES, AND THAT IS THE SHAPE OF THE WHOLE UNIT.

    * A `Start` routine runs ONCE, at the moment the row is read. It decodes
      the command's parameter and arms the channel: sets a step size, a target
      period, a waveform, a counter.
    * A `Tick` routine runs on EVERY tick afterwards until the next row. It
      applies whatever the Start armed -- adds the step, advances the position,
      decrements the counter.

  So a portamento is not one action but fifty small ones, and the Start half
  only decides how big each of them will be. Commands with nothing to do
  between rows (set volume, jump to pattern) have a Tick half that returns
  immediately; commands with nothing to decode (the E-series fine slides) do
  their whole job in the Start half. Both empty halves still exist, because
  both tables must have an entry for every command number.

  THE TWO TABLES ARE THE DISPATCH. `CommandStart` and `CommandTick` do nothing
  but range-check the command number, index a table of routine offsets and
  jump. Adding a command means writing two routines and filling in two slots.

  TICK ROUTINES TAKE THEIR ARGUMENTS IN REGISTERS, NOT ON THE STACK -- SI
  points at the channel, BX holds the tick number -- which is why they are
  assembler and why they cannot be called from Pascal. They run once per
  channel per tick at the mixer's rate, and a stack frame per call was a cost
  the original was not willing to pay.

  WHY THE CHANNEL RECORD IS DECLARED HERE. `TCanal` is filled by the player
  and consumed by the mixer, so neither of those owns it; the effects are what
  give most of its fields meaning, so it lives with them.

  AND SO DOES THE SEQUENCER POSITION. `NextSeq`, `NextNote` and `MySongLen`
  are the pattern-order cursor, and they are declared here rather than in the
  player because the Bxx and Dxx commands WRITE them -- a jump command changes
  where the song goes next. The player `uses` this unit, so this unit cannot
  reach back into the player; the variables have to sit on this side of the
  dependency.

  [re] SEGMENT 147d -- 2,176 bytes, seventeen routines. COMPLETE: all 2,175
  bytes of code, and 147d:087f is one byte of linker padding.

  [re] `units.py` reports the prefix, which is the right measure while a unit
  is being built strictly top-down: Turbo Pascal lays procedures out in source
  order, so a stub of the wrong size displaces everything below it and the
  prefix stops at the first one.

      transcribed   0000..087e   COMPLETE. Forty-three routines and the
                                 dispatch table; 087f is one byte of padding.

  [re] THE RELEASE IS THE COUNTERPART AND THE MAPPING IS 1:1 SO FAR.
  `LIB/MODCOMMA.PAS` is 1.39b's version of this unit -- 959 lines against
  1.31's 2,176 bytes, because it grew the S3M and Oktalizer effects -- and its
  first twelve routines are these twelve, in this order, with the same bodies;
  the three after those are empty in both. That is twelve consecutive
  confirmations rather than one plausible name.

  [re] WHERE 1.31 AND 1.39b DIVERGE, so far:

  [re] **THE PORTAMENTO STEP IS UNSCALED HERE AND SCALED BY FOUR IN THE
  RELEASE**, and it is specific to the portamentos rather than a change of
  units across the unit -- `StartVibrato` keeps the release's `SHL 2` on its
  depth at 02dd, so the tidier story of "1.31 counts whole periods everywhere"
  is NOT what the bytes say. `StartTPortUp` stores the parameter unscaled where
  the release has `can.TPortaIncr := WORD(n.Parameter) SHL 2`;
  `StartNPortamento` reads and writes `PeriodIncr` unscaled where the release
  has a `SHR 2` on the way out and a `SHL 2` on the way in. Two routines, four
  places, no shift in any of them -- 147d:00d9 is `MOV AL,[DI+5] / XOR AH,AH /
  MOV [DI+1f],AX` and there is nothing between the load and the store. So the
  same pattern data slides four times faster in 1.31, which is a behavioural
  difference and worth knowing before anyone compares the two players by ear.

  [re] `StartArpeggio` uses A PERIOD TABLE where the release uses a MULTIPLY
  TABLE. 1.39b computes `f SHL 14 DIV ArpTable[semitones]`, which works for any
  tuning; 1.31 looks the period's note up in `VTNotes.NoteOf`, adds the
  semitones, and reads `VTNotes.NotePeriods` -- the classic ProTracker way, and
  it only works on the twelve-tone table. That is the earlier design, and it is
  why 142f is the consumer of the table 1650 builds.
  =========================================================================== }

unit ModCommands;

interface

uses
  SongUnit, SongElements, VTNotes;

type
  { ONE CHANNEL'S LIVE STATE. A four- or eight-channel module gives each
    channel its own copy of this record, and between them they are everything
    the player remembers from one tick to the next.

    IT DIVIDES INTO THREE PARTS.

      * WHAT IS PLAYING: the note as it was read from the pattern, the
        instrument it selected, the current volume, and the period -- the pitch,
        expressed the way the format expresses it, as an Amiga sample-clock
        divisor where SMALLER means HIGHER.
      * WHAT IS MOVING: one small group of fields per continuous effect, each
        holding the step size, position or target its Tick routine needs. The
        arpeggio keeps three periods and a counter; the vibrato keeps a
        waveform, a position, a width and a depth; each portamento keeps a
        step, and the note portamento a destination as well.
      * WHAT HAPPENS NEXT: the one-shot flags -- a sample offset to apply, a
        retrigger due, a ring event to publish -- each a small value plus a
        boolean saying whether it is armed.

    THE PERIOD IS KEPT TWICE, and the pair is the reason the effects compose.
    `Period` is what the mixer is actually playing; `RealPeriod` is the note's
    own pitch with no effect applied. Vibrato writes `Period` every tick and
    leaves `RealPeriod` alone, so when the vibrato ends the note returns to
    where it started rather than to wherever the wobble left it.

    THE FIELD ORDER IS NOT NEGOTIABLE. Assembler routines in this unit and in
    the mixer reach fields by fixed offset from SI, so inserting a field would
    silently move every field below it.

    [re] DS:$1260 in 12ba's array. `TCanal` and `TFullNote` ARE the release's,
    head for head. 12ce:11fd..121d proves the head -- four stores landing on
    `Note.Period`, `Note.Instrument`, `Note.Command` and `Period` at +$01,
    +$00, +$04 and +$0b -- and 142f now proves five more fields further in.

    [re] FIFTEEN OFFSETS ARE ANCHORED BY AN INSTRUCTION IN THIS SEGMENT:

        +$0f  PeriodIncr   147d:01c6 tests it signed, 147d:0216 stores a Word
        +$11  PeriodDest   147d:019b stores the note's period, 147d:0258 compares
        +$13  ArpCt        147d:0007 clears it, 147d:00a3 increments it
        +$14  Arp0         147d:002c stores the current period
        +$16  Arp1         147d:0064
        +$18  Arp2         147d:009b
        +$1a  VibWave      147d:028e reads it to select the waveform
        +$1b  VibPos       147d:02fe clears it, 147d:034b advances it
        +$1c  VibWidth     147d:029c and both other CASE arms
        +$1d  VibDepth     147d:02e3 stores it, 147d:0348 adds it
        +$1e  VibReset     147d:02f4 tests it
        +$1f  TPortaIncr   147d:00e5 stores a Word, 147d:016d subtracts it
        +$21  VolumeIncr   147d:038e stores it, 147d:03d7 reads it signed
        +$22  TPortIsFine  147d:00ec clears it, 147d:00f6 tests it
        +$23  VSldIsFine   147d:0370 clears it, 147d:03ac tests it

    [re] THERE ARE NO GAPS LEFT. Every field from +$00 to +$23 is anchored by an
    instruction rather than taken from the release -- +$0f and +$11 fell to
    StartNPortamento, +$1a..+$1e to StartVibrato, and +$21 and +$23 to
    StartVolSlide. That is the pattern to expect: each routine confirms the
    fields it touches, and a layout that was "determined by the gaps" becomes
    one determined by use. Only +$24 and +$25 keep names from elsewhere.

    [re] THE TAIL DOES NOT CARRY OVER FROM 1.31, AND 142f SAYS WHY. There the
    record is 38 bytes, $00..$25, and the release's +$24/+$25 are
    `RetrigCt`/`S3mRetVal` -- but **1.31 HAS NO RETRIGGER COMMAND AT ALL**:
    where 1.39b puts StartRetrigNote and TickRetrigNote, 147d:0584 goes
    straight to the fine volume slide. With no retrigger routine there is
    nothing for those two bytes to hold, which is why 12ba is free to use them
    as the note ring's `Chan` and `Note` (12ce:0a8a and 12ce:0a6f). }
  PCanal = ^TCanal;
  TCanal = record
    { WHAT IS PLAYING. The note exactly as the pattern gave it, the instrument
      it selected, and the two pitches -- see the record's header for why there
      are two. `Volume` is 0..64, the tracker's range, not the hardware's. }
    Note       : TFullNote;     { the row's note, verbatim                   }
    Instrument : PInstrumentRec; { the sample it selected                    }
    Volume     : Byte;          { 0..64                                      }
    Period     : Word;          { what is being played NOW                   }
    RealPeriod : Word;          { the note's own pitch, unmodulated          }

    { [re] +$00, +$06, +$0a, +$0b, +$0d. 12ce:09ff dereferences the pointer and
      12ce:0eaf writes RealPeriod. `PInstrumentRec` is SongElements' own, and
      the release declares this very field as `Instrument : PInstrumentRec`
      with the comment "Pointer to the instrument data". }

    { THE NOTE PORTAMENTO, command 3xx: slide from the pitch being played
      TOWARDS a target and stop there. The step is SIGNED, and its sign is the
      direction -- the Start half works out which way to go once, so the Tick
      half only has to add and test for arrival. }
    PeriodIncr : Integer;       { how far to move each tick, signed          }
    PeriodDest : Integer;       { the period to stop at                      }

    { THE ARPEGGIO, command 0xy: cycle between three pitches on successive
      ticks, fast enough to sound like a chord. The three periods are computed
      once and the counter says which of them is due. }
    ArpCt      : Byte;          { 0, 1 or 2 -- which pitch is due            }
    Arp0       : Word;          { the note itself                            }
    Arp1       : Word;          { plus x semitones                           }
    Arp2       : Word;          { plus y semitones                           }

    { [re] +$0f..+$19, all six anchored. 147d:0194 stores the note's period into
      +$11 and 147d:01c6 tests +$0f with a signed `JLE`, so the step is an
      Integer and its sign carries the direction. 147d:0007 clears ArpCt,
      147d:00a3 increments it; 147d:002c, 0064 and 009b store the three
      periods. }

    { THE VIBRATO, command 4xy: walk a repeating waveform and add it to the
      pitch. The position advances by `VibWidth` each tick and the sample it
      lands on is scaled by `VibDepth` -- so x is the SPEED and y is how far it
      swings. `VibReset` says whether a new note restarts the waveform from
      zero or lets it carry on through. }
    VibWave    : Byte;          { which waveform: sine, ramp, square         }
    VibPos     : Byte;          { how far through it                         }
    VibWidth   : Byte;          { how far to step each tick -- the speed     }
    VibDepth   : Byte;          { how hard to swing                          }
    VibReset   : Boolean;       { restart the waveform on a new note?        }

    { THE PLAIN SLIDES: pitch up/down (1xx and 2xx) and volume up/down (Axy).
      Each keeps one signed step. The `IsFine` flags mark the E-series
      variants, which move by their step ONCE at the row rather than on every
      tick -- same arithmetic, different trigger. }
    TPortaIncr : Integer;       { pitch step per tick, signed                }
    VolumeIncr : ShortInt;      { volume step per tick, signed               }
    TPortIsFine : Boolean;      { E1x/E2x: move once, not per tick           }
    VSldIsFine : Boolean;       { EAx/EBx: the same for volume               }

    { [re] +$1a..+$23. Five vibrato bytes forced by the anchors either side;
      147d:028e reads VibWave, 147d:02fe clears VibPos and 147d:034b advances
      it, 147d:029c reads VibWidth in all three CASE arms, 147d:02e3 stores
      VibDepth and 147d:0348 adds it, 147d:02f4 tests VibReset. Then
      147d:00e5/016d for TPortaIncr, 147d:038e/03d7 for VolumeIncr,
      147d:00ec/00f6 and 147d:0370/03ac for the two flags. }

    { THE RETRIGGER, command E9x: play the note again every x ticks within the
      row. The counter runs up to the period, and when it gets there it is
      cleared and the flag is raised -- the flag is what the mixer reads, so
      the effect never touches the sample pointer itself. }
    RetrigCt   : Byte;          { ticks since the last retrigger             }
    RetrigVal  : Byte;          { retrigger every this many ticks            }
    DoRetrig   : Boolean;       { raised for one tick when one is due        }

    { [re] +$24..+$26, and IN 1.31b THESE THREE BYTES ARE NOT A RETRIGGER -- they
      are the note ring's `Chan` and `Note` (12ce:0a8a, 12ce:0a6f), read by the
      consumer at 12ce:01ce. In v1.51, 147d:05d8 is `INC [SI+24] / MOV AL,[SI+24]
      / CMP AL,[SI+25] / JB out / MOV [SI+24],0 / MOV [SI+26],1`, and 147d:05b9
      stores `N.Parameter` into +$25 from command $1a, `mcRetrigNote`. }

    { THE SAMPLE OFFSET, command 9xx: start the sample part-way in rather than
      at its beginning, which is how a drum loop is chopped into hits. The
      parameter counts 256-byte units, so the reachable offsets are coarse and
      the whole 64K of a sample is addressable in one byte.

      IT IS A REQUEST, NOT AN ACTION. The effect cannot move the sample pointer
      itself, because the note it applies to has not been started yet; it
      leaves the offset and a flag, and the mixer applies them when it does. }
    SOffs      : Boolean;       { an offset is waiting to be applied         }
    SOffsVal   : Word;          { the parameter, times 256                   }

    { [re] +$27, +$28. 147d:0369 is `StartSampleOffs`, reached from
      `CommandStart` on command $0a, `mcSampleOffs`; it sets the flag and stores
      `N.Parameter shl 8`. }

    { SCREAM TRACKER'S Qxy RETRIGGER, which does what E9x does AND changes the
      volume each time it fires. The x nibble picks one of sixteen behaviours,
      and they are not all the same KIND of arithmetic: some scale the volume
      by a fraction, others add or subtract a fixed step. So the parameter is
      decoded once into a value plus a flag saying how to apply it, and the
      Tick half never has to know which nibble it came from. }
    S3mRetAdd : Boolean;       { True: add S3mRetVal. False: scale by it     }
    S3mRetVal : Byte;          { the step, or the multiplier                 }

    { [re] +$2a, +$2b. 147d:0785 looks the high nibble up in a MULTIPLIER table
      and sets +$2a when that entry is ZERO, meaning "this x is not a
      multiply"; 147d:0818 then either multiplies the volume by +$2b and shifts
      down four, or adds +$2b as a signed step. Two tables, one selector byte. }

    { THE RING EVENT, AND IT IS NOT A SOUND EFFECT AT ALL. The demo needs to
      know when the music reaches particular moments, so that lights, wipes and
      scene changes can be cut to the beat. Command 8xx does nothing to a
      ProTracker channel -- so this player borrows it as a CUE: the parameter
      is a label the demo chooses, and the flag says one is waiting to be
      collected. The music is the timeline, and this is how it speaks.

      A SEMAPHORE, NOT A QUEUE. One slot per channel, raised by the effect and
      lowered by whoever reads it; a second cue before the first is collected
      overwrites it. That is enough when the reader runs every frame. }
    RingSem     : Byte;         { the cue's parameter                        }
    RingPending : Byte;         { non-zero: a cue is waiting                 }
  end;

  { [re] +$2c, +$2d; 46 bytes in all. 147d:085d stores `N.Parameter` into +$2c
    and 1 into +$2d, which is 1.31b's `StartRingEvent` moved two fields down the
    record and nothing else changed. `CommandStart` maps command $09 to it --
    `mcNPI1`, ProTracker's do-nothing 8xx. The two versions put these bytes in
    different places, and reading only one of them made that look like a
    contradiction rather than a missing measurement. }

{ --------------------------------------------------------------------------
  THE SEQUENCER'S POSITION AND SPEED, and they are declared in the EFFECTS unit
  rather than in the player because the effects are what MOVE them. Bxx jumps
  to another order position, Dxx breaks to the next pattern, Fxx changes the
  speed -- all three write the variables below. The player `uses` this unit, so
  this unit cannot reach back into the player; the state has to sit on this
  side of the dependency, and the release resolves it the same way.

  THERE ARE TWO KINDS OF SPEED HERE AND CONFUSING THEM IS THE CLASSIC TRACKER
  MISTAKE.

    * `CurSpeed` is TICKS PER ROW -- how many times the effects run before the
      next row is read. Six is the ProTracker default. Lowering it makes
      effects coarser, not the song faster in any musical sense.
    * `CurTempo` is the TICK RATE itself, in the beats-per-minute units the
      format uses, and `TempoDiv`/`TempoAccum` are the divider and accumulator
      that turn it into an interval on the actual timer.

  Fxx sets one or the other depending on its parameter, which is why both live
  next to each other.

  THE PLAY RANGE IS KEPT TWICE, and the pair is a handshake. `Req*` is what a
  caller has ASKED for; `Range*`/`MySongLen` is what the player is currently
  working through. Starting playback copies one set to the other, so a request
  can be lodged at any time without disturbing a song mid-row.

  [re] DS:$033e..$0359, and `147d:03ed` reads DS:$034c, DS:$0340 and DS:$034a.
  Nine of these were declared in PLAYMOD.PAS, which could not have been right:
  their addresses INTERLEAVE with the three already here -- $033c and $033e sit
  either side of $0340 -- and two units' blocks cannot interleave when DGROUP
  is laid out one unit at a time. That contradiction is what found them; the
  release then confirmed all nine in its own `CONST` section.

  [re] DECLARED AS TYPED CONSTANTS, NOT `var`, and the difference is the image
  rather than the accesses. A typed constant is initialised data written into
  the EXE; a plain `var` is reserved space the linker never writes. The two
  live in different regions of DGROUP, so the choice fixes the ADDRESS as well.
  Four of the values are non-zero and land exactly where the release's
  initialisers say: 125, 125, 6, 1 and 1.

  [re] THE RENAMES ARE DECLINED where the release's `Tempo` would collide with a
  field of `TPlayingNote`. Our names are kept and the release's quoted beside
  them. Moving a declaration between units cannot change a byte of either
  unit's code, so `units.py` reporting both unchanged is the check.
  -------------------------------------------------------------------------- }
const
  MyLoopMod          : Boolean = False;  { repeat the song at its end?         }
  PermitFilterChange : Boolean = False;  { may E0x touch the hardware filter?  }

  { THE TICK CLOCK. `CurTempo` is the rate in the format's BPM units;
    `TempoDiv` and `TempoAccum` are the fixed-point divider and running
    remainder that turn it into whole timer intervals without a division per
    tick. Fxx writes CurTempo. }
  TempoDiv           : Word    = 125;    { release: BPMDivider                 }
  CurTempo           : Word    = 125;    { release: BPMIncrement               }
  TempoAccum         : Word    = 0;      { release: BPMCount                   }

  { [re] DS:$033e, $033f, $0340, $0342, $0344. Both flags were declared in
    PLAYMOD until the layout moved them; $033f is the `FilterChange` key.
    147d:04a6 and 147d:04bc write CurTempo from the F-command. }

  { THE PLAY RANGE, twice over: what the player is working through, then what
    a caller has asked it to play next. Starting playback copies the second set
    into the first. `Range*` is the live copy. }
  RangeStart         : Word    = 0;      { release: MyFirstPattern             }
  RangeEnd           : Word    = 0;      { release: MyRepStart                 }
  MySongLen          : Word    = 0;      { the live range's last position      }
  ReqStart           : Word    = 0;      { release: FirstPattern               }
  ReqEnd             : Word    = 0;      { release: RepStart                   }
  ReqLen             : Word    = 0;      { release: SongLen                    }

  { [re] DS:$0346..$0350. PlayStart copies one set to the other, which is where
    both were read from: 12ce:10b4, 10ba, 10c0. }

  { What E0x last asked for. Exported so that the key handler can set it. }
  FilterIsOn         : Boolean = False;

  { THE CURSOR. `NextSeq` is the position in the order list, `NextNote` the row
    within that pattern, and `TickInRow` counts ticks until the row advances --
    it runs up to `CurSpeed` and resets. Together they are exactly where the
    song is. }
  CurSpeed           : Byte    = 6;      { ticks per row. release: Tempo       }
  NextNote           : Word    = 1;      { the row                             }
  NextSeq            : Word    = 1;      { the order position                  }
  TickInRow          : Byte    = 0;      { release: TempoCt                    }

  { [re] DS:$0352..$0358. This `FilterIsOn` is NOT PlayMod's, which is a
    different variable at DS:$02cd -- 1.31 has two and the release has one, and
    11cf:0b0e's key writes this one. Exporting it is safe only because
    PlayMod's copy stays private, so no unit can see both. }

{ THE SEMITONE TABLE: HOW TO TRANSPOSE A PITCH WITHOUT A NOTE TABLE.

  Sixteen words indexed by a semitone count, each 16384 * 2**(n/12) rounded --
  16384, 17358, 18390 ... 32768 at the twelfth, which is the octave and the
  check that fixes the formula. Because a period is INVERSELY proportional to
  frequency, dividing it by 2**(n/12) raises the pitch by n semitones, so
  `(Period shl 14) div SemitoneScale[n]` transposes ANY period at all.

  THAT IS WHY IT REPLACED A LOOKUP. The older arpeggio found the note in a
  table, added the semitones, and read the new period back out -- which only
  works when the channel is sitting exactly on a table entry. Finetuned MOD
  notes are not, and S3M pitches are not remotely; this player loads both.
  Arithmetic works everywhere a lookup only worked on the twelve-tone grid.

  [re] NEW IN v1.51, DS:$035a. This block's addresses all moved +$0a, which is
  what puts the table at $035a and not $0350: verdiff's largest bucket across
  the two versions is seventeen bytes shifting by exactly ten, with old values
  $35..$4c -- the low halves of $0334..$034c. So the unit's block runs
  $033e..$0359 in 1.51 and the table follows it. }
  SemitoneScale : array[0..15] of Word =
    (16384, 17358, 18390, 19483, 20642, 21869, 23170, 24548,
     26007, 27554, 29193, 30928, 32768, 34715, 36781, 38967);

{ THE TWO ENTRY POINTS. Everything else in this unit is reached through one of
  these; nothing outside calls an individual effect.

  Arm the note's command. Called once, as the row is read, for every channel
  that has a command on it. }
procedure CommandStart(var Song : TSong; var Can : TCanal; var N : TFullNote); far;

{ Advance whatever is armed. Called once per channel on every tick.

  IT TAKES ITS ARGUMENTS IN REGISTERS, so it cannot be called from Pascal: SI
  points at the channel and BX holds the command number DOUBLED, ready to index
  the jump table. The declaration carries no parameters and the caller sets the
  registers up by hand.

  [re] 147d:064b and 147d:063f; the caller is 12ce:0d75. The release documents
  the convention in `LIB/MODCOMMA.PAS`: "En las del tick, se entra con SI
  apuntando al TCanal correspondiente." }
procedure CommandTick; far;

implementation

{ --------------------------------------------------------------------------
  THE FILTER FLAGS ARE PRIVATE, AND THERE ARE TWO `FilterIsOn`s IN THIS PROGRAM.

  E0x switches the Amiga's low-pass filter, which on a PC means switching which
  mixing kernel is in force. This unit's flag records what the COMMAND asked
  for; the player has a flag of its own recording what the MIXER is actually
  doing, and the two are separate variables.

  KEEPING THIS ONE OUT OF THE INTERFACE IS THE POINT. Exporting it would put a
  second `FilterIsOn` in scope wherever the player is compiled, and Pascal
  would quietly resolve those references to the player's -- a shadowing bug no
  byte comparison could ever see. `PermitFilterChange` gates the whole thing:
  a module that fiddles with the filter can be told to leave it alone.

  [re] DS:$0348, written by 147d:04da; PlayMod's is DS:$02cd, next to FilterOn
  and FilterOff, and the initialisation section reads it at 12ce:1430 to choose
  the kernel. Nothing in the transcribed tree reads $0348 at all. Whether 1.31
  MEANT one variable and ended up with two is not something the bytes can
  answer; it is the same shape as `LoopMod` at $02c8, also written and never
  read. `PermitFilterChange` is DS:$0335 and is the release's name.
  -------------------------------------------------------------------------- }

{ [re] EVERY ROUTINE IN THIS UNIT IS NEAR. `RET 0C` at 147d:00a0 is a near
  return with twelve bytes of parameters -- three `var` references -- so the
  internal effect routines are called near from within the SEGMENT, and only the
  two the interface publishes are far. That is also why the parameters sit at
  [BP+04] upward rather than [BP+06]: Song at [BP+0C], Can at [BP+08], N at
  [BP+04], which is Pascal order with the first-declared pushed first. }

{ Forward: the two portamento Start routines fall back on the fine variants,
  which are declared a long way below.

  [re] 147d:0114 calls 147d:04e2 and 147d:0163 calls 147d:052f, 1,000 bytes
  further down the SEGMENT. The release declares them FORWARD for the same
  reason and in the same place. }
procedure StartFinePortaUp(var Song : TSong; var Can : TCanal;
                           var N : TFullNote); forward;
procedure StartFinePortaDown(var Song : TSong; var Can : TCanal;
                             var N : TFullNote); forward;

{ Forward: the combined commands (5xy tone-portamento-plus-volume-slide, 6xy
  vibrato-plus-volume-slide) do their own half and then JUMP straight into this
  one rather than duplicating it. A jump, not a call, because the volume slide
  is the last thing either of them does.

  [re] 147d:03cd, confirmed by the two near jumps at 147d:0352 and 147d:0359,
  which the release writes as `JMP TickVolSlide` from both TickT_VSlide and
  TickVib_VSlide. The prologue scanner never found it: it is frameless. Both
  jumps take the three-byte form because the target is 120 bytes below. }
procedure TickVolSlide; forward;


{ --------------------------------------------------------------------------
  ARPEGGIO, command 0xy. Alternate between the note, the note x semitones up,
  and the note y semitones up, on successive ticks -- fast enough that the ear
  hears a chord rather than three notes. It is how a four-channel machine plays
  a triad, and it is the oldest trick the format has.

  ALL THE WORK HAPPENS HERE, ONCE. The two transposed periods are computed at
  the row and stored; the Tick half only picks one of the three and hands it to
  the mixer, which is three instructions and no arithmetic.

  THE TRANSPOSITION IS A DIVIDE, NOT A TABLE LOOKUP -- see `SemitoneScale`
  above for why. The period is shifted up by fourteen bits first because the
  table is written in that fixed point; the shift and the divide together are a
  fractional multiply, and 32 bits is enough that no precision is lost on any
  period the format can express.

  [re] 147d:0000. THE INDEX ARITHMETIC IS 32-BIT AND THAT IS THE SOURCE TALKING.
  147d:0042 is `CWD` on the semitone count and 147d:0053 is `XOR DX,DX` on the
  masked table entry, then `ADD AX,CX / ADC DX,BX` -- a LongInt add whose high
  word is then thrown away by the indexing. Turbo Pascal promotes `Integer +
  Word` to LongInt, so the widening is forced by the operand types.

  [re] THE OPERAND ORDER IS READ OFF THE BYTES, and it is the reverse of what
  reads naturally. Turbo Pascal evaluates the RIGHT operand of a 32-bit add
  first, into CX:BX, then the left into DX:AX -- 147d:003f loads the semitone
  count and sign-extends it into CX:BX before touching either table, so the
  semitone count is the RIGHT-hand operand and the table lookup is the left.
  Written the other way round the two halves swap and nothing else changes.

  [re] AND THE SEMITONE COUNT IS SIGNED, which the `CWD` settles. It comes from
  a nibble so it can only be 0..15, but the variable it is kept in is an Integer
  -- had it been a Word the compiler would have emitted `XOR DX,DX` here too.
  -------------------------------------------------------------------------- }
procedure StartArpeggio(var Song : TSong; var Can : TCanal; var N : TFullNote);
var
  { Both LongInt: `Scaled` needs the width for the fixed point, and `Period`
    matches it so the divide has no conversion in front of it. }
  Period : LongInt;               { the pitch to transpose FROM              }
  Scaled : LongInt;               { the same, shifted up 14 bits             }

  { [re] `ENTER 8,0` in 1.51 where 1.31b has `ENTER 4,0`; [BP-4] and [BP-8].
    147d:0015 stores AX to [BP-4] and DX to [BP-2] after an `XOR DX,DX`, a
    32-bit store of a zero-extended word, and 147d:001b tests the value with
    `MOV AX,[BP-4] / OR AX,[BP-2]`. Nothing else in the routine is 16-bit. }
begin
  Can.ArpCt := 0;                                  { 0004..000b              }

  Period := N.Period;                              { 000c..001a              }
  if Period = 0 then                               { 001b..0022              }
    Period := Can.Note.Period;                     { 0023..0031              }

  { Into the table's fixed point: 1 shl 14 is 16384, which is the table's
    entry for "no semitones at all".

    [re] `MOV CX,0e / XOR BX,BX / CALLF 1d89:0aa8`, and 0aa8 is `AND CX,1F /
    SHL AX,1 / RCL DX,1 / LOOP` -- Turbo Pascal's LongInt shift-left, with the
    count arriving as a whole LongInt in BX:CX because that is how it loads an
    integer constant. }
  Scaled := Period shl 14;                         { 0032..0047              }

  { [re] `MOV AX,[BP-4]` and nothing more -- a LongInt assigned to a Word field
    keeps the low half. }
  Can.Arp0 := Period;                              { 0048..0051              }

  { The two nibbles are the two intervals: high nibble first, low nibble
    second. They are read from the CHANNEL's copy of the note, not from the note
    passed in -- so an arpeggio survives a row that carries no command of its
    own, which is what makes the effect continue across a held note.

    [re] `LES DI,[BP+8]` is the CHANNEL and the note is at [BP+4]; `Can.Note` is
    a TFullNote at offset zero, so its `Parameter` is +$5. THE DIVISOR IS
    EVALUATED FIRST: `MOV AX,[DI+35a] / XOR DX,DX / MOV CX,AX / MOV BX,DX`
    builds the right operand in BX:CX before the left is loaded into DX:AX --
    the LongInt divide helper at 1d89:0a2e takes them that way round. }
  Can.Arp1 := Scaled div SemitoneScale[Can.Note.Parameter shr 4];   { 0052..007d }
  Can.Arp2 := Scaled div SemitoneScale[Can.Note.Parameter and $0F]  { 007e..00a8 }
end;


{ --------------------------------------------------------------------------
  147d:00a3 -- arpeggio, per tick. Frameless, and that is the release's shape
  exactly: `PROCEDURE TickArpeggio; ASSEMBLER;` names no parameter, so Turbo
  Pascal gives it no prologue at all and the channel arrives in SI.

  **AND THE RELEASE STATES THAT CONVENTION OUTRIGHT.** Over the whole group its
  source says "[1.39b] Command routines, for the start of a note and for each
  tick" and then "[1.39b] The tick routines are entered with SI pointing at the
  relevant TCanal." -- which is a fact about EVERY handler below, written once by
  the author, where this reconstruction had to derive it per routine from the
  prologue each one lacks.

  **SO EVERY `[SI+n]` IN THIS FILE IS A FIELD OF TCanal, AND THIS IS THE KEY.**
  Without it each handler reads as arithmetic on anonymous offsets; with it they
  read as what they are. The record is declared above; these are its offsets:

      +$00  Note        the note being played (TFullNote, 6 bytes)
      +$06  Instrument  pointer to the sample's TInstrumentRec
      +$0a  Volume
      +$0b  Period      what the mixer converts into a step
      +$0d  RealPeriod  Period after the instrument's tuning is applied
      +$0f  PeriodIncr  portamento step; SIGNED, and the sign is the direction
      +$11  PeriodDest  portamento target
      +$13  ArpCt       arpeggio phase, 0..2
      +$14  Arp0        the three arpeggio periods
      +$16  Arp1
      +$18  Arp2
      +$1a  VibWave     vibrato waveform and position -- NOT confirmed by use;
      +$1b  VibPos      TickVibrato is a stub, so these two are placed by their
                        neighbours rather than by an instruction

  The last pair carries a warning on purpose. Everything above it is anchored by
  an instruction that reads or writes it; those two are not, and a reader should
  treat them as the best available reading rather than as measured fact.

  A HANDLER MAY NOT ASSUME ANY OTHER REGISTER. SI is the contract; AX, BX, CX
  and DX are scratch, and each routine leaves through @@Fin, which is the RET
  Pascal appends rather than an instruction of this file's own.

  `@@Fin` IS THE EPILOGUE, and it is EMPTY on purpose. A tick routine leaves by
  jumping to a label at the very end of its body, where the compiler's own `RET`
  is waiting. Writing a `RET` there instead would emit two.

  [re] Both `JMP @@Fin`s land on 147d:00cb.
  -------------------------------------------------------------------------- }
{ **ARPEGGIO IS A CHORD FAKED BY ONE VOICE.** [1.39b] "Rotate through three
  notes rapidly." A channel can play one pitch at a time, so it plays three in
  turn -- one per tick, fifty times a second -- and the ear hears a chord rather
  than three separate notes. The three periods were worked out when the command
  started; this routine only decides which of them is current.

  That is why the counter runs 1, 2, 0 and not 0, 1, 2: it is incremented BEFORE
  it is tested, so the first tick after the command lands on Arp0. }
procedure TickArpeggio; assembler;
asm
        { Can.ArpCt := Can.ArpCt + 1, then rotate on its value: 1 -> Arp0,
          2 -> Arp1, anything else -> Arp2 and back to zero. }
        INC     BYTE PTR [SI+13h]        { 00a3  ArpCt                        }
        MOV     AL,[SI+13h]              { 00a6                               }
        DEC     AL                       { 00a9                               }
        JNZ     @@2                      { 00ab                               }
         MOV    AX,[SI+14h]              { 00ad  Arp0                         }
         MOV    [SI+0Bh],AX              { 00b0  -> Period                    }
        JMP     @@Fin                    { 00b3                               }
@@2:    DEC     AL                       { 00b5                               }
        JNZ     @@3                      { 00b7                               }
         MOV    AX,[SI+16h]              { 00b9  Arp1                         }
         MOV    [SI+0Bh],AX              { 00bc                               }
        JMP     @@Fin                    { 00bf                               }
@@3:     MOV    AX,[SI+18h]              { 00c1  Arp2                         }
         MOV    [SI+0Bh],AX              { 00c4                               }
         MOV    BYTE PTR [SI+13h],0      { 00c7  and start the cycle again    }
@@Fin:
end;


{ --------------------------------------------------------------------------
  147d:00cc -- commands 1 and 2, TONE PORTAMENTO up and down. A non-zero
  parameter sets the step; a zero parameter means "the same as last time", and if
  the channel was in FINE portamento it is redirected to the fine version instead
  -- which is why the command byte is rewritten before the call.

  THE PARAMETER IS NOT SCALED HERE and the release scales it by four. See the
  unit header; this is a behavioural difference between the versions.
  -------------------------------------------------------------------------- }
procedure StartTPortUp(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter <> 0 then                         { 00cf..00d8              }
  begin
    Can.TPortaIncr  := N.Parameter;                { 00d9..00e8              }
    Can.TPortIsFine := False                       { 00e9..00f0              }
  end
  else if Can.TPortIsFine then                     { 00f3..00fc              }
  begin
    Can.Note.Command := mcFinePortaUp;             { 00fd..0104  stores $12  }
    StartFinePortaUp(Song, Can, N)                 { 0105..0116              }
  end
end;

procedure StartTPortDown(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter <> 0 then                         { 011e..0127              }
  begin
    Can.TPortaIncr  := N.Parameter;                { 0128..0137              }
    Can.TPortIsFine := False                       { 0138..013f              }
  end
  else if Can.TPortIsFine then                     { 0142..014b              }
  begin
    Can.Note.Command := mcFinePortaDn;             { 014c..0153  stores $13  }
    StartFinePortaDown(Song, Can, N)               { 0154..0165              }
  end
end;


{ --------------------------------------------------------------------------
  147d:016a -- tone portamento, per tick. Four instructions each, and BOTH
  CLAMPS ARE ABSENT. The release carries three of them commented out in the source
  -- a floor at zero, a ceiling at $39 going up and one at $6B0 coming down -- and
  1.31 has none of the code either, so the period is free to run past the ends of
  the table. Neither version clamps; 1.39b merely records that somebody tried.
  -------------------------------------------------------------------------- }
procedure TickTPortUp; assembler;
asm
        MOV     AX,[SI+01h]              { 016a  Note.Period                  }
        SUB     AX,[SI+1Fh]              { 016d  ... minus TPortaIncr         }
        MOV     [SI+01h],AX              { 0170                               }
        MOV     [SI+0Bh],AX              { 0173  and the working period too    }
end;

procedure TickTPortDown; assembler;
asm
        MOV     AX,[SI+01h]              { 0177                               }
        ADD     AX,[SI+1Fh]              { 017a                               }
        MOV     [SI+01h],AX              { 017d                               }
        MOV     [SI+0Bh],AX              { 0180                               }
end;


{ --------------------------------------------------------------------------
  147d:0184 -- command 3, NOTE PORTAMENTO. Slide towards a target period rather
  than by a fixed amount, so the note carries the destination and the parameter
  carries the speed, and either may be omitted to mean "as before".

  BOTH `PeriodDest` AND `PeriodIncr` ARE CONFIRMED HERE, and they had been carried
  as determined-by-the-gap: 0194 stores the note's period into +$11 and 01c6 tests
  +$0f with a SIGNED `JLE`, so +$11 is the destination and +$0f is a signed step.

  THE SIGN OF THE STEP CARRIES THE DIRECTION, which is why the parameter is copied
  back out of it negated at 01dd -- a bare `n.Parameter` has no room for a sign.

  `Integer(...)` AT 0206 IS A DELIBERATE TRUNCATION AND THE RELEASE WRITES IT THE
  SAME WAY. `PeriodDest - Period` is Integer minus Word, which Turbo Pascal
  promotes to LongInt, so the subtraction at 0202 is 32-bit -- and then `OR AX,AX /
  JL` tests the sign of the LOW WORD ONLY. That is not a mistake in the reading:
  1.39b has `IF INTEGER(can.PeriodDest - can.Period) >= 0`, the cast spelled out.
  Without it the compiler would test DX and the instruction would be different.

  AND AGAIN THERE IS NO SCALING. The release reads `BYTE((can.PeriodIncr) SHR 2)`
  and writes `INTEGER(WORD(n.Parameter) SHL 2)`; 1.31 has neither shift. That is
  the second routine in this SEGMENT to show it -- see the unit header. 1.39b moved
  the whole unit to quarter-period units and 1.31 works in whole periods.
  -------------------------------------------------------------------------- }
procedure StartNPortamento(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Period <> 0 then                            { 0187..0190              }
    Can.PeriodDest := N.Period                     { 0191..019e              }
  else if Can.PeriodDest = 0 then                  { 01a1..01aa              }
    Can.PeriodDest := Can.Period;                  { 01ab..01b8              }

  if N.Parameter = 0 then                          { 01b9..01c2              }
  begin
    if Can.PeriodIncr > 0 then                     { 01c3..01cc  signed JLE  }
      N.Parameter := Can.PeriodIncr                { 01cd..01da              }
    else
      N.Parameter := -Can.PeriodIncr               { 01dd..01ec              }
  end;

  if Integer(Can.PeriodDest - Can.Period) >= 0 then   { 01ed..0209           }
    Can.PeriodIncr := N.Parameter                  { 020a..0219              }
  else
    Can.PeriodIncr := -N.Parameter;                { 021c..022d              }

  Can.Note.Period := Can.Period                    { 022e..023b              }
end;


{ --------------------------------------------------------------------------
  147d:0240 -- note portamento, per tick. Step towards the target and stop when
  it is reached, in either direction.

  IT IS THE RELEASE'S BODY INSTRUCTION FOR INSTRUCTION, which is the closest
  pairing in this SEGMENT so far.

  THE TWO `TEST reg,80h` ARE THE SIGN CHECKS, and they are why this is assembler
  rather than Pascal: `TEST AH,80h` asks whether the step is negative and
  `TEST BH,80h` whether the new period has wrapped below zero, and each is followed
  by an UNSIGNED comparison against the target. Sliding up and sliding down need
  opposite senses of "past it", and the wrap test catches a step that overshoots
  through zero -- three-way logic on one 16-bit value that Pascal cannot express
  without converting between signed and unsigned twice.

  `AND AX,AX` IS `21 C0` HERE, the inline assembler's direction and not the code
  generator's, which is one of this project's standing tells for hand-written asm.
  `ADD BX,AX` is `01 C3` for the same reason.
  -------------------------------------------------------------------------- }
procedure TickNPortamento; assembler;
asm
        MOV     AX,[SI+11h]              { 0240  PeriodDest                   }
        AND     AX,AX                    { 0243                               }
        JZ      @@Fin                    { 0245  no target, nothing to do     }
        MOV     AX,[SI+0Fh]              { 0247  PeriodIncr                   }
        AND     AX,AX                    { 024a                               }
        JZ      @@Fin                    { 024c  no step, nothing to do       }
        MOV     BX,[SI+01h]              { 024e  Note.Period                  }
        ADD     BX,AX                    { 0251  ... plus the step            }
        TEST    AH,80h                   { 0253  is the step negative?        }
        JNZ     @@neg                    { 0256                               }
         CMP    BX,[SI+11h]              { 0258  sliding down: past the target? }
         JA     @@pneg                   { 025b                               }
        JMP     @@cnt                    { 025d                               }
@@neg:   TEST   BH,80h                   { 025f  wrapped below zero?          }
         JNZ    @@pneg                   { 0262                               }
         CMP    BX,[SI+11h]              { 0264  sliding up: past the target? }
         JAE    @@cnt                    { 0267                               }
@@pneg:  MOV    BX,[SI+11h]              { 0269  clamp to the target          }
@@cnt:  MOV     [SI+01h],BX              { 026c                               }
        MOV     [SI+0Bh],BX              { 026f                               }
@@Fin:
end;

{ --------------------------------------------------------------------------
  147d:0273 -- command 4, VIBRATO. Set the width and the depth from the two
  nibbles, and reset the position if the note is a new one.

  IT CONFIRMS FOUR MORE `TCanal` FIELDS, all of which had been carried as
  determined-by-the-gap: VibWave at +$1a (read at 028e), VibPos at +$1b (cleared at
  02fe), VibWidth at +$1c (written on all three CASE arms) and VibReset at +$1e
  (tested at 02f4). Only VolumeIncr at +$21 is still unconfirmed.

  THE `case` IS A COMPARE CHAIN, not a jump table. Borland builds a table only when
  the label set is dense enough to pay for one; three consecutive small values
  compile to `CMP AL,0 / CMP AL,1 / CMP AL,2` and fall through to nothing. Note the
  first two arms are IDENTICAL and are still written twice -- the release has them
  as separate arms too, and merging them into `0, 1:` would emit different bytes.

  AND THIS ONE KEEPS THE RELEASE'S `SHL 2`. `f SHL 2` on the depth is at 02dd in
  both versions, so the missing scaling in the two portamentos is NOT a unit-wide
  change of units -- it is specific to the portamento step. Worth stating because
  the opposite would have been the tidier story.
  -------------------------------------------------------------------------- }
procedure StartVibrato(var Song : TSong; var Can : TCanal; var N : TFullNote);
var
  F : Word;                       { [BP-2], and the whole of `ENTER 2,0`      }
begin
  F := N.Parameter and $0F;                        { 0277..0284              }
  if F <> 0 then                                   { 0285..028a              }
    case Can.VibWave of                            { 028b..0295              }
      0: Can.VibWidth := F;                        { 0296..02a1              }
      1: Can.VibWidth := F;                        { 02a2..02b1              }
      2: Can.VibWidth := (F * 255) shr 7;          { 02b2..02c4              }
    end;

  F := N.Parameter shr 4;                          { 02c5..02d3              }
  if F <> 0 then                                   { 02d4..02d9              }
    Can.VibDepth := F shl 2;                       { 02da..02e6              }

  if (N.Period <> 0) and Can.VibReset then         { 02e7..02fa              }
    Can.VibPos := 0                                { 02fb..0302              }
end;


{ --------------------------------------------------------------------------
  147d:0307 -- vibrato, per tick. The release's body instruction for instruction,
  including the sine table, and it is assembler for a reason worth reading.

  THREE WAVEFORMS SHARE ONE PIECE OF ARITHMETIC. VibWave 0 is a SINE, looked up
  with `SHR AL,2 / AND AL,1F / XLAT` -- five bits of the position index a 32-entry
  quarter-scaled table. VibWave 1 is a TRIANGLE, and it is generated rather than
  tabulated: `SHL AL,1 / JNC / NOT AL` doubles the position and complements it on
  the second half, which is a triangle in three instructions. Anything else is a
  SQUARE -- the width is used flat, with no shaping at all.

  THE SIGN COMES FROM THE POSITION'S TOP BIT, not from the table: `TEST DL,80h /
  NEG AX` at 033c mirrors the whole waveform into the second half of its cycle, so
  the table only ever needs to hold a half-cycle. That is why the 32 entries run
  0..255..24 and never go negative.

  [re] `MOV BX,0350` IS A DGROUP OFFSET, NOT A CODE ADDRESS, and it has to be:
  `XLAT` reads `DS:BX+AL`. 147d:0350 in the code SEGMENT is the middle of
  TickT_VSlide, so the table is a typed constant living in DGROUP -- which is
  exactly where Turbo Pascal puts a `const` declared inside a procedure, and
  exactly how the release declares it.

  [re] `AND AH,AH` is `20 E4` and `MOV AL,DL` is `88 D0` -- the inline
  assembler's direction bits throughout, the standing tell for hand-written asm.
  -------------------------------------------------------------------------- }
procedure TickVibrato; assembler;
const
  { HALF A SINE, IN 32 STEPS, 0..255. Only half is stored: the position's top
    bit decides whether the value is added or subtracted, so the second half of
    the cycle is the first half negated and never needs its own entries.

    [re] DS:$0350. The release's table and its comment; transcribed rather than
    computed. }
  VibTabla : array[0..31] of Byte = (
      0,  24,  49,  74,  97, 120, 141, 161,
    180, 197, 212, 224, 235, 244, 250, 253,
    255, 253, 250, 244, 235, 224, 212, 197,
    180, 161, 141, 120,  97,  74,  49,  24
  );
asm
        MOV     AH,[SI+1Ah]              { 0307  VibWave                       }
        MOV     DH,[SI+1Ch]              { 030a  VibWidth                      }
        MOV     DL,[SI+1Bh]              { 030d  VibPos                         }
        MOV     AL,DL                    { 0310                                }
        AND     AH,AH                    { 0312                                }
        JNZ     @@nosn                   { 0314                                }
         SHR    AL,2                     { 0316  waveform 0: the sine table    }
         AND    AL,1Fh                   { 0319                                }
         MOV    BX,OFFSET VibTabla       { 031b                                }
         XLAT                            { 031e                                }
         JMP    @@set                    { 031f                                }
@@nosn: DEC     AH                       { 0321                                }
        JNZ     @@notr                   { 0323                                }
         SHL    AL,1                     { 0325  waveform 1: a triangle,       }
         JNC    @@set                    { 0327   generated, not tabulated     }
          NOT   AL                       { 0329                                }
@@set:   MUL    DH                       { 032b  scale by the width            }
         SHL    AX,1                     { 032d                                }
         MOV    AL,AH                    { 032f  ... and take the high byte    }
         XOR    AH,AH                    { 0331                                }
        JMP     @@calc                   { 0333                                }
@@notr:  MOV    AL,DH                    { 0335  anything else: a square       }
         XOR    AH,AH                    { 0337                                }
@@calc: MOV     BX,[SI+01h]              { 0339  Note.Period                   }
        TEST    DL,80h                   { 033c  second half of the cycle?     }
        JZ      @@mas                    { 033f                                }
         NEG    AX                       { 0341   then mirror it               }
@@mas:  ADD     BX,AX                    { 0343                                }
        MOV     [SI+0Bh],BX              { 0345  -> Period, NOT Note.Period    }
        ADD     DL,[SI+1Dh]              { 0348  advance by VibDepth           }
        MOV     [SI+1Bh],DL              { 034b                                }
end;


{ --------------------------------------------------------------------------
  147d:034f and 147d:0356 -- commands 5 and 6, PORTAMENTO-PLUS-VOLUME-SLIDE and
  VIBRATO-PLUS-VOLUME-SLIDE. Two instructions each: do one effect, then fall into
  the other. The release is identical.

  THE `JMP` IS THE THREE-BYTE NEAR FORM AND THAT IS A FORWARD REFERENCE SHOWING.
  `E9 78 00` at 0352 reaches 03cd, a displacement of $78, which fits a short jump
  twice over -- but `TickVolSlide` is declared FORWARD and lives 120 bytes further
  down, so Turbo Pascal's inline assembler does not yet know the distance and takes
  the long form. It does NOT pad afterwards, which is where it differs from TASM's
  `JUMPS`: TP simply emits three bytes and moves on. Both jumps here are like that.

  THE TRAILING `RET` IS THE COMPILER'S AND IS UNREACHABLE. An `assembler`
  procedure always gets its epilogue, even after an unconditional `JMP` out of
  the body; writing a `RET` in the source would emit a second.

  [re] 0355 and 035c are those two. AND THE JUMPS PIN `TickVolSlide` AT
  147d:03cd -- a routine the prologue scanner never found, because it is
  frameless. Two independent jumps land on it and the release says what both of
  them jump to, so the pairing is confirmed rather than inferred.
  -------------------------------------------------------------------------- }
procedure TickT_VSlide; assembler;
asm
        CALL    TickNPortamento          { 034f                                }
        JMP     TickVolSlide             { 0352                                }
end;

procedure TickVib_VSlide; assembler;
asm
        CALL    TickVibrato              { 0356                                }
        JMP     TickVolSlide             { 0359                                }
end;


{ --------------------------------------------------------------------------
  147d:035d, 035e, 035f -- THREE DO-NOTHING TICK ROUTINES, one byte each.

  A bare `RET` with no parameter count, so all three take no arguments and are
  Tick routines rather than Start ones. The release has exactly three consecutive
  empty `ASSEMBLER` ticks in this region -- `TickTremolo`, `TickNPI1` and
  `TickSampleOffs` -- with `StartSampleOffs` between the second and third.

  AND `StartSampleOffs` IS ABSENT HERE, which is independently supported: it sets
  `can.SOffs` and `can.SOffsVal` at +$27 and +$28, and 1.31's TCanal is 38 bytes
  and stops at +$25. So 1.31 has no sample-offset support and the three empties sit
  next to each other.

  [re] THEY KEPT ADDRESS NAMES UNTIL THE DISPATCH TABLE NAMED THEM. An EMPTY
  body cannot confirm a pairing -- every empty routine matches every other one --
  so position was all there would have been, and position is not confirmation.
  The table at 147d:063f maps each command number to one of these addresses, and
  that is where the names below came from.
  -------------------------------------------------------------------------- }
procedure TickTremolo; assembler;
asm
end;

procedure TickNPI1; assembler;
asm
end;

{ --------------------------------------------------------------------------
  SAMPLE OFFSET, command 9xx. Start the sample xx*256 bytes in rather than at
  its beginning. One drum loop can then be played as a dozen separate hits, by
  entering it at a dozen different points -- which is the whole reason a
  four-channel format can carry a breakbeat.

  THE PARAMETER IS COARSE BY DESIGN. One byte times 256 reaches the whole 64K a
  sample can occupy, at the cost of landing only on 256-byte boundaries. At
  8kHz that is a granularity of about a thirtieth of a second, which is close
  enough for a drum hit and far cheaper than a second parameter byte.

  IT ONLY LEAVES A REQUEST. The note it applies to has not been started yet, so
  there is no sample pointer here to move; the mixer applies the offset when it
  starts the note. A zero parameter means "keep whatever was set last time",
  the same convention the slides use.

  [re] 147d:0369, NEW IN v1.51, and it lands exactly where the 1.31b note said
  it would: between `TickNPI1` and `TickSampleOffs`, with `TickVib_VSlide`'s own
  unreachable trailing `RET` accounting for the third `C3` in the run.

  [re] THE DISPATCH TABLE NAMED IT. `CommandStart` at 147d:088a is an `else if`
  chain on the command byte -- `CMP AL,n / JNZ` twenty-one times -- and decoding
  its near calls maps command $0a to this address. $0a is `mcSampleOffs`. The
  same pass named `StartRetrigNote` ($1a), `StartOktArp` ($21 AND $22, both),
  `StartS3mRetrigNote` ($23) and `StartNPI1` ($09), and confirmed that $06, $07
  and $0b all share `StartVolSlide` -- six routines and one three-way alias from
  one table.

  [re] `XOR AH,AH` before `SHL AX,8` is the byte widening to a Word first. }
procedure StartSampleOffs(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter <> 0 then                         { 036c..0375              }
  begin
    Can.SOffs    := True;                          { 0376..037d              }
    Can.SOffsVal := N.Parameter shl 8              { 037e..0390              }
  end
end;

procedure TickSampleOffs; assembler;
asm
end;


{ ==========================================================================
  FROM HERE ON: the volume slides, the song-position commands, the whole E-series
  of one-nibble sub-commands, and last the two dispatchers the interface
  publishes.
  ========================================================================== }

{ --------------------------------------------------------------------------
  147d:0360 -- command A, VOLUME SLIDE. One nibble slides up and the other down,
  and a zero parameter means "the same as last time" as with the portamentos.

  IT CONFIRMS THE LAST TWO UNANCHORED FIELDS: VolumeIncr at +$21 (written at 038e
  and 03a3, read at 03d7) and VSldIsFine at +$23 (cleared at 0370, tested at 03ac).
  With those two, EVERY field of TCanal from +$00 to +$23 is anchored by an
  instruction rather than taken from the release, and only the two bytes at +$24
  and +$25 keep names derived from what 12ba does with them.

  `-ShortInt(...)` IS IN THE ORIGINAL AND THE CAST MATTERS. 039d is `CBW`, which
  sign-extends the masked nibble before the `NEG` -- so the negation happens in
  sixteen bits and only the low byte is stored. Without the cast the compiler would
  negate a Word and the instruction would be different. The release writes it
  `-SHORTINT(n.Parameter AND $F)`, spelled out the same way.

  THE `asm` BLOCK IS THE RELEASE'S TOO, and it is there because the tick routine
  takes its channel in SI rather than as a parameter. `MOV SI,WORD PTR Can` loads
  the OFFSET HALF of the var reference -- correct because TCanal lives in DGROUP --
  and that is this project's standing tell number four. Note the flag is turned OFF
  around the call and back ON afterwards: TickVolSlide refuses to do anything while
  it is set, so clearing it is how a FINE slide borrows the coarse routine once.
  -------------------------------------------------------------------------- }
procedure StartVolSlide(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter <> 0 then                         { 0363..036c              }
  begin
    Can.VSldIsFine := False;                       { 036d..0374              }
    if N.Parameter > $F then                       { 0375..037e              }
      Can.VolumeIncr := N.Parameter shr 4          { 037f..0391  slide up    }
    else
      Can.VolumeIncr := -ShortInt(N.Parameter and $F)   { 0394..03a6  down   }
  end
  else
  begin
    if Can.VSldIsFine then                         { 03a9..03b2              }
    begin
      Can.VSldIsFine := False;                     { 03b3..03ba              }
      asm
        MOV     SI,WORD PTR Can                    { 03bb  the offset half   }
        CALL    TickVolSlide                       { 03be                    }
      end;
      Can.VSldIsFine := True                       { 03c1..03c8              }
    end
  end
end;


{ --------------------------------------------------------------------------
  147d:03cd -- volume slide, per tick. CONFIRMED at this address by the two jumps
  at 0352 and 0359 and the call at 03be, all three of which the release spells
  `TickVolSlide`. The prologue scanner never found it because it is frameless.

  THE CLAMP IS ONE COMPARISON FOR BOTH ENDS, and that is the whole reason this is
  assembler. `ADD AL,AH` on a byte volume with a signed increment can leave 0..64,
  or wrap below zero to $FF.., or exceed 64 -- and `CMP AL,64 / JBE` accepts only
  the first case. Everything else is out of range, and the SIGN OF THE INCREMENT
  then says which end it fell off: negative means it wrapped low, so zero; positive
  means it went over, so 64. One unsigned compare and one sign test cover three
  outcomes, which is not expressible in Pascal without doing the arithmetic twice.

  `AND AL,AL` is `20 C0` and `ADD AL,AH` is `00 E0` -- the inline assembler's
  direction bits again.
  -------------------------------------------------------------------------- }
procedure TickVolSlide; assembler;
asm
        MOV     AL,[SI+23h]              { 03cd  VSldIsFine                    }
        AND     AL,AL                    { 03d0                                }
        JNZ     @@Sale                   { 03d2  a fine slide does nothing here }

        MOV     AL,[SI+0Ah]              { 03d4  Volume                        }
        MOV     AH,[SI+21h]              { 03d7  VolumeIncr, signed            }
        ADD     AL,AH                    { 03da                                }
        CMP     AL,64                    { 03dc  in range 0..64?               }
        JBE     @@Fin                    { 03de                                }
         XOR    AL,AL                    { 03e0  no -- assume it wrapped low   }
         TEST   AH,80h                   { 03e2  was the increment negative?   }
         JNZ    @@Fin                    { 03e5   then zero is right           }
          MOV   AL,64                    { 03e7   otherwise it overflowed      }
@@Fin:  MOV     [SI+0Ah],AL              { 03e9                                }
@@Sale:
end;

{ --------------------------------------------------------------------------
  147d:03ed -- command B, JUMP TO A PATTERN POSITION. Set the order position from
  the parameter and start at row 1, unless the position is past the end of the
  range, in which case $FFFF stops the song.
  -------------------------------------------------------------------------- }
procedure StartJumpPattern(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  NextSeq := N.Parameter;                          { 03f0..03fb              }
  if NextSeq > MySongLen then                      { 03fc..0404              }
    NextNote := $FFFF                              { 0405..040a              }
  else
    NextNote := 1                                  { 040d..0412              }
end;


{ --------------------------------------------------------------------------
  147d:0417 -- command C, SET VOLUME. Clamped to 64, and note the clamp is
  written back into the NOTE and not just used: 0427 stores $40 into
  `N.Parameter` before 042f reads it again. `N` is a `var` parameter, so that is
  visible to the caller.
  -------------------------------------------------------------------------- }
procedure StartSetVolume(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter > 64 then                         { 041a..0423              }
    N.Parameter := 64;                             { 0424..042b              }
  Can.Volume := N.Parameter                        { 042c..0439              }
end;


{ --------------------------------------------------------------------------
  147d:043e -- command D, END OF PATTERN. Advance to the next order position and
  start at the row the parameter names -- except that it does not, and the release
  has the same defect.

  THE COMPUTED ROW IS THROWN AWAY. 045d..047e builds a row number out of the two
  nibbles as a DECIMAL pair -- `(low) + (high)*10 + 1`, which is how a tracker
  displays row numbers -- stores it in `NextNote`, and then 047f..048b overwrites it
  with 1 unless it happens to be $FFFF. So the parameter has no effect and every
  D-command starts at row one. Both versions do this; 1.39b's line is
  `IF NextNote <> $FFFF THEN NextNote := 1` sitting right after the calculation.
  Transcribed as found, per the standing rule -- this is the original's behaviour
  and not a transcription artefact.

  AND IT CONFIRMS THE OPERAND ORDER AGAIN, this time in 16 bits. `SHR 4 / IMUL
  AX,AX,0Ah / MOV DX,AX` evaluates the MULTIPLY term first and the `AND $0F` term
  second, so in the release's `(n.Parameter AND $0F) + (n.Parameter SHR 4)*10` the
  right-hand operand is the one Turbo Pascal computes first. Same rule the 32-bit
  add in StartArpeggio showed.
  -------------------------------------------------------------------------- }
procedure StartEndPattern(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if NextNote <> 1 then                            { 0441..0447              }
    Inc(NextSeq);                                  { 0448..044b              }

  if NextSeq > MySongLen then                      { 044c..0454              }
    NextNote := $FFFF                              { 0455..045a              }
  else
    NextNote := (N.Parameter and $0F) +
                (N.Parameter shr 4) * 10 + 1;      { 045d..047e              }

  if NextNote <> $FFFF then                        { 047f..0485              }
    NextNote := 1                                  { 0486..048b              }
end;


{ --------------------------------------------------------------------------
  147d:0490 -- command F, SET TEMPO. ProTracker overloads one command: a value
  above $30 is a BPM and anything else is a tick count, which is why the two arms
  write different variables and different widths.
  -------------------------------------------------------------------------- }
procedure StartSetTempo(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter > $30 then                        { 0493..049c              }
    CurTempo := N.Parameter                        { 049d..04a8              }
  else
    if N.Parameter <> 0 then                       { 04ab..04b4              }
      CurSpeed := N.Parameter                      { 04b5..04be              }
end;


{ --------------------------------------------------------------------------
  147d:04c3 -- command E0x, SET THE OUTPUT FILTER, and only if the client has
  allowed the pattern to touch it.

  `MOV AL,0 / JZ +1 / INC AX` IS THE BOOLEAN EXPRESSION, not a branch. That is how
  Turbo Pascal materialises `X <> 0` as a value: clear AL, skip the increment when
  the comparison was equal. Note the `CMP` at 04d0 sets the flags and the `MOV AL,0`
  between it and the `JZ` does not disturb them -- which is why the compiler can put
  it there and save a jump.

  WHAT IT WRITES IS NOT PLAYMOD'S FILTER FLAG. See the note beside the declaration:
  $0348 here, $02cd there, and nothing in the tree reads this one.
  -------------------------------------------------------------------------- }
procedure StartSetFilter(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if PermitFilterChange then                       { 04c6..04cc              }
    FilterIsOn := N.Parameter <> 0                 { 04cd..04dc              }
end;


{ E0x has nothing to do between rows: the filter is switched at the row and
  stays switched. Empty on purpose -- see the note below the E-series.

  [re] 147d:04e1, one byte, a bare `RET`. The release has it as `TickSetFilter`
  and it is empty there too; the dispatch table at 063f is what named it. }
procedure TickSetFilter; assembler;
asm
end;

{ --------------------------------------------------------------------------
  FINE PORTAMENTO, commands E1x and E2x: move the pitch by x ONCE, at the row,
  instead of by x on every tick. It is how a tracker nudges a note slightly out
  of tune -- to thicken a chord, or to beat one channel against another --
  without the audible slide a coarse portamento would give.

  THE WHOLE DIFFERENCE IS WHEN IT FIRES, NOT WHAT IT DOES. So the fine version
  arms the channel exactly as the coarse one does, then CALLS THE COARSE TICK
  ROUTINE ITSELF, on the spot, and the per-tick dispatcher never sees the
  command again. One movement instead of fifty; the same arithmetic either way.

  THE FOUR ROUTINES TOGETHER MEAN "AGAIN, WHICHEVER KIND IT WAS". A zero
  parameter means repeat the last portamento, and the flag remembers which kind
  that was -- so each of the four checks the flag and, if the note belongs to
  the other kind, REWRITES the command byte and hands it over. Coarse with a
  zero parameter and the fine flag set goes fine; fine with a zero parameter
  and the flag clear goes coarse.

  [re] 147d:04e2 and 147d:052f, CONFIRMED at both addresses by the near calls at
  147d:0114 and 147d:0163. `MOV SI,WORD PTR Can` is the offset half of a var
  reference, because TickTPortUp takes its channel in SI.

  [re] `MOV byte ES:[DI+4],2` AT 0516 IS A THIRD CONFIRMATION OF THE COMMAND
  ENUM. mcTPortUp is 2 and mcTPortDown is 3 counting from mcNone, and 0563
  stores 3. With the $12 and $13 in StartTPortUp/Down that is four values fixed
  by four stores.

  [re] NO SCALING, again: the release has `WORD(n.Parameter) SHL 2` in both and
  04f2..04fb has no shift.
  -------------------------------------------------------------------------- }
procedure StartFinePortaUp(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter <> 0 then                         { 04e5..04ee              }
  begin
    Can.TPortaIncr  := N.Parameter;                { 04ef..04fe              }
    Can.TPortIsFine := True                        { 04ff..0506              }
  end
  else if not Can.TPortIsFine then                 { 0509..0512              }
    Can.Note.Command := mcTPortUp;                 { 0513..051a  stores 2    }

  if Can.TPortIsFine then                          { 051b..0524              }
    asm
      MOV       SI,WORD PTR Can                    { 0525                    }
      CALL      TickTPortUp                        { 0528                    }
    end
end;

procedure StartFinePortaDown(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter <> 0 then                         { 0532..053b              }
  begin
    Can.TPortaIncr  := N.Parameter;                { 053c..054b              }
    Can.TPortIsFine := True                        { 054c..0553              }
  end
  else if not Can.TPortIsFine then                 { 0556..055f              }
    Can.Note.Command := mcTPortDown;               { 0560..0567  stores 3    }

  if Can.TPortIsFine then                          { 0568..0571              }
    asm
      MOV       SI,WORD PTR Can                    { 0572                    }
      CALL      TickTPortDown                      { 0575                    }
    end
end;


{ --------------------------------------------------------------------------
  EIGHT DO-NOTHING TICK ROUTINES IN A ROW. All eight commands below do their
  whole job at the row and have nothing left to do between rows -- see the note
  after them for why an empty body is the right implementation and not a
  missing one.

  [re] 147d:057c..0583, one byte each: `C3 C3 C3 C3 C3 C3 C3 C3`, eight bare
  near returns, so eight parameterless `assembler` procedures with empty bodies.
  The release has SEVEN consecutive empties here (`TickFPortUpDown`,
  `TickGlissCtrl`, `TickVibCtrl`, `TickFineTune`, `TickJumpLoop`,
  `TickTremCtrl`, `TickNPI2`) and 1.31 has eight, so one has no counterpart in
  1.39b -- or 1.39b merged two, which eight identical bodies cannot settle. The
  names here come from the dispatch table at 147d:063f, which is the only thing
  that could have supplied them.
  -------------------------------------------------------------------------- }
procedure TickFPortUpDown; assembler;
asm
end;

{ ===========================================================================
  **THE EMPTY TICK HANDLERS, AND THEY ARE EMPTY ON PURPOSE.** Everything from
  here to TickNPI2 is `asm end;` with no instruction in it, and a reader is
  entitled to assume that means unfinished. It does not.

  A command has two entry points: a Start routine that runs once when the note
  begins, and a Tick routine that runs on every tick afterwards. Most effects
  need both -- a portamento has to move the pitch each tick. But a command that
  merely SETS SOMETHING has nothing left to do once it has set it:

      TickGlissCtrl   glissando control -- chooses a mode, then nothing
      TickVibCtrl     picks the vibrato waveform
      TickFineTune    adjusts the pitch once
      TickJumpLoop    acts on the pattern, not on the channel
      TickTremCtrl    picks the tremolo waveform
      TickNPI2        [1.39b] "Do Nothing (as far as I know)"

  So the routine exists to fill a slot in the dispatch table and to be called
  and return. Removing it is not possible: the table is indexed by command
  number, and a missing entry would shift every command after it.

  THE COST OF THE DESIGN IS PAID HERE, AND IT IS WORTH IT. A dispatch table with
  no gaps means the tick loop never tests whether a command HAS a tick routine
  -- it calls through the table unconditionally, thousands of times a second,
  and an empty routine costs a call and a return. The alternative is a test on
  every channel on every tick to save that.

  ONE OF THEM IS DIFFERENT AND IS MARKED WHERE IT SITS. TickRetrigNote below is
  empty because the effect is NOT IMPLEMENTED in this version, which is a
  different fact from having nothing to do. See its own note.
  =========================================================================== }
procedure TickGlissCtrl; assembler;
asm
end;

procedure TickVibCtrl; assembler;
asm
end;

procedure TickFineTune; assembler;
asm
end;

procedure TickJumpLoop; assembler;
asm
end;

procedure TickTremCtrl; assembler;
asm
end;

procedure TickNPI2; assembler;
asm
end;

{ --------------------------------------------------------------------------
  147d:05b9 and 147d:05d8 -- RETRIGGER, START AND TICK, and 1.31b has neither: it
  carries an empty `TickRetrigNote` and no Start at all. `CommandStart` maps command
  $1a to 05b9, and $1a is `mcRetrigNote`.

  `JB`, NOT `JBE`. 05e1 is `72 08`, so the counter is compared UNSIGNED and the reset
  happens when it REACHES the period rather than passes it -- `if Can.RetrigCt >=
  Can.RetrigVal`, written the way round the compare emits.

  THE TICK IS FRAMELESS AND TAKES THE CHANNEL IN SI, like every other Tick here, so
  it is `assembler` with no parameters and the record fields are reached through SI
  by hand. }
procedure StartRetrigNote(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter <> 0 then                         { 05bc..05c5              }
    Can.RetrigVal := N.Parameter                   { 05c6..05d3              }
end;

procedure TickRetrigNote; assembler;
asm
        INC     BYTE PTR [SI+24h]        { 05d8  RetrigCt                      }
        MOV     AL,[SI+24h]              { 05db                                }
        CMP     AL,[SI+25h]              { 05de  RetrigVal                     }
        JB      @@Out                    { 05e1                                }
         MOV    BYTE PTR [SI+24h],0      { 05e3                                }
         MOV    BYTE PTR [SI+26h],1      { 05e7  DoRetrig                     }
@@Out:
end;

{ --------------------------------------------------------------------------
  147d:0584 and 147d:05cd -- commands EAx and EBx, FINE VOLUME SLIDE up and down.
  The same borrow-the-coarse-routine trick StartVolSlide uses: set the increment,
  clear the fine flag so TickVolSlide will act, call it once, set the flag again.

  AND THEY ARE WHY 1.31 HAS NO RETRIGGER, WHICH SETTLES THE TAIL OF `TCanal`.
  The release's order here is `StartRetrigNote`, `TickRetrigNote`, then these two.
  1.31 goes straight to these two -- 0584 is a fine volume slide, not a retrigger --
  so the retrigger command is absent from this version altogether. That is what
  frees `+$24` and `+$25`: the release keeps `RetrigCt` and `S3mRetVal` there, and
  with no retrigger routine there is nothing to keep. So the two bytes 12ba uses as
  the note ring's `Chan` and `Note` are not a reinterpretation of the release's
  fields -- the release's fields simply do not exist yet. The record's tail has been
  described as "does not carry over" since the reading pass; this is WHY.
  -------------------------------------------------------------------------- }
procedure StartVolFineUp(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter <> 0 then                         { 0587..0590              }
  begin
    Can.VSldIsFine := True;                        { 0591..0598              }
    Can.VolumeIncr := N.Parameter and $0F          { 0599..05a8              }
  end;

  if Can.VSldIsFine then                           { 05a9..05b2              }
  begin
    Can.VSldIsFine := False;                       { 05b3..05ba              }
    asm
      MOV     SI,WORD PTR Can                      { 05bb                    }
      CALL    TickVolSlide                         { 05be                    }
    end;
    Can.VSldIsFine := True                         { 05c1..05c8              }
  end
end;

procedure StartVolFineDown(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  if N.Parameter <> 0 then                         { 05d0..05d9              }
  begin
    Can.VSldIsFine := True;                        { 05da..05e1              }
    Can.VolumeIncr := -ShortInt(N.Parameter and $0F)    { 05e2..05f3         }
  end;

  if Can.VSldIsFine then                           { 05f4..05fd              }
  begin
    Can.VSldIsFine := False;                       { 05fe..0605              }
    asm
      MOV     SI,WORD PTR Can                      { 0606                    }
      CALL    TickVolSlide                         { 0609                    }
    end;
    Can.VSldIsFine := True                         { 060c..0613              }
  end
end;


{ --------------------------------------------------------------------------
  147d:0619 -- fine volume slide, per tick, and it is one instruction: fall into
  the coarse routine, which refuses to act while the fine flag is set. So a fine
  slide moves on the row and never on a tick, and this exists only to give the
  dispatch table something to point at.

  THE `JMP` IS THREE BYTES BECAUSE THE TARGET IS 591 BYTES BEHIND IT, not because of
  a forward reference this time. `E9 B1 FD` reaches 03cd, which is far outside a
  short jump's range, so the long form is the only one available. Worth noting
  alongside the two forward jumps at 0352 and 0359, which take the same form for a
  completely different reason -- do not read a long jump as evidence of either.
  -------------------------------------------------------------------------- }
procedure TickVolFineUpDn; assembler;
asm
        JMP     TickVolSlide             { 0619, and 061c is the epilogue      }
end;


{ --------------------------------------------------------------------------
  147d:061d..0621 -- FIVE MORE DO-NOTHING TICKS, one byte each, and this time the
  COUNT matches the release exactly: `TickNoteCut`, `TickNoteDelay`,
  `TickPattDelay`, `TickFunkIt` and `TickNone`, all five empty in 1.39b too.

  Which is suggestive and still not proof -- five empty bodies in a row match five
  other empty bodies in a row whatever the order. Address names until the dispatch
  table at 063f says otherwise. That is now SIXTEEN one-byte routines in this
  SEGMENT waiting on that one table.
  -------------------------------------------------------------------------- }
procedure TickNoteCut; assembler;
asm
end;

{ **THESE THREE ARE EMPTY FOR A DIFFERENT REASON: THEY ARE NOT IMPLEMENTED.**
  Unlike the group above, these are effects with real per-tick work that this
  version does not do.

    TickNoteDelay   [1.39b] "Wait a little before starting note." A delay has
                    to count ticks, so an empty tick routine means a delayed
                    note simply plays at once.
    TickPattDelay   the release did not know what it did either -- see the
                    enumeration in SongElements.
    TickFunkIt      [1.39b] "No idea, but sounds funny."

  A MODULE USING ANY OF THEM WILL PLAY, AND PLAY WRONG. Nothing errors: the
  dispatch finds a routine, calls it, and it returns having done nothing. That
  is the failure mode to expect if a module sounds subtly out of time, and it
  is silent by construction. }
procedure TickNoteDelay; assembler;
asm
end;

procedure TickPattDelay; assembler;
asm
end;

procedure TickFunkIt; assembler;
asm
end;

{ Command zero: [1.39b] "Just play the note, without any special option." There
  is nothing to do on a tick and nothing to do at the start either, which is why
  this is the only handler whose emptiness needs no explanation. }
procedure TickNone; assembler;
asm
end;

{ --------------------------------------------------------------------------
  THE OKTALIZER ARPEGGIO. Oktalizer was another tracker, and its arpeggio is
  not quite ProTracker's: the two intervals are read from the parameter the
  other way round, and the cycle is FOUR steps rather than three -- note, first
  interval, second interval, first interval again. Supporting somebody else's
  format means matching its quirks exactly, so this is a separate command
  rather than a flag on the ordinary one.

  THE PITCH ARITHMETIC IS THE ORDINARY ARPEGGIO'S, unchanged. Only the nibble
  order and the tick cycle differ, and the cycle lives in the Tick half.

  [re] 147d:068a, NEW IN v1.51, taking the source position 1.31b's
  `StartRingEvent` used to hold. `CommandStart` maps BOTH command $21 and
  command $22 -- `mcOktArp` and `mcOktArp2` -- to this one address. The high
  nibble reaches `Arp1` through `xor $0F`, which on a 0..15 value is 15 - n.

  [re] **`Period := Period shl 1` IS DEAD AND IT IS THE ORIGINAL'S.** 147d:070d
  shifts the period left one and stores it back to [BP-4], and nothing reads
  [BP-4] again -- the second divide at 073a loads `Scaled` from [BP-8], which
  the shift did not touch. It looks like an octave drop the author meant to fold
  into `Scaled` and did not. Transcribed because it is four instructions of the
  release's, not because it does anything.
  -------------------------------------------------------------------------- }
procedure StartOktArp(var Song : TSong; var Can : TCanal; var N : TFullNote);
const
  { The same sixteen values as `SemitoneScale`, declared again inside this
    procedure. The original carries two copies and so does this.

    [re] DS:$039a; thirty-two bytes, which is what a `const` declared inside a
    second procedure looks like. }
  OktScale : array[0..15] of Word =
    (16384, 17358, 18390, 19483, 20642, 21869, 23170, 24548,
     26007, 27554, 29193, 30928, 32768, 34715, 36781, 38967);
var
  Period : LongInt;               { [BP-4]                                   }
  Scaled : LongInt;               { [BP-8]                                   }
begin
  Can.ArpCt := 0;                                  { 068e..0695              }

  Period := N.Period;                              { 0696..06a4              }
  if Period = 0 then                               { 06a5..06ac              }
    Period := Can.Note.Period;                     { 06ad..06bb              }

  Scaled := Period shl 14;                         { 06bc..06d1              }
  Can.Arp0 := Period;                              { 06d2..06db              }

  Can.Arp2 := Scaled div OktScale[Can.Note.Parameter and $0F];     { 06dc..0706 }

  { See the note above: this result is never read. }
  Period := Period shl 1;                          { 0707..071c              }

  Can.Arp1 := Scaled div OktScale[(Can.Note.Parameter shr 4) xor $0F] { 071d..074b }
end;


{ --------------------------------------------------------------------------
  147d:0750 -- the Oktalizer arpeggio, per tick, and it is a FOUR-step cycle where
  the ProTracker one is three: 1 -> Arp1, 2 -> Arp2, 3 -> Arp1 again, then Arp0 and
  reset. The third step repeating Arp1 is what makes it Oktalizer's.

  `DEC AL` THREE TIMES RATHER THAN THREE COMPARES. The counter is loaded once and
  decremented between tests, two bytes a step against three -- the inline assembler
  emits what it is written, so this is the release's own hand-written shape.

  THE DISPATCH TABLE POINTS HERE FROM INDEX 34 ONLY. Index 33 -- `mcOktArp` -- points
  at `TickArpeggio` instead, so the two Oktalizer commands share a Start routine and
  differ in their tick. 1.31b's table has TickNone at both. }
procedure TickOktArp; assembler;
asm
        INC     BYTE PTR [SI+13h]        { 0750  ArpCt                         }
        MOV     AL,[SI+13h]              { 0753                                }
        DEC     AL                       { 0756                                }
        JNZ     @@2                      { 0758                                }
         MOV    AX,[SI+16h]              { 075a  Arp1                          }
         MOV    [SI+0Bh],AX              { 075d                                }
         JMP    @@Out                    { 0760                                }
@@2:    DEC     AL                       { 0762                                }
        JNZ     @@3                      { 0764                                }
         MOV    AX,[SI+18h]              { 0766  Arp2                          }
         MOV    [SI+0Bh],AX              { 0769                                }
         JMP    @@Out                    { 076c                                }
@@3:    DEC     AL                       { 076e                                }
        JNZ     @@0                      { 0770                                }
         MOV    AX,[SI+16h]              { 0772  Arp1 again -- the fourth step }
         MOV    [SI+0Bh],AX              { 0775                                }
         JMP    @@Out                    { 0778                                }
@@0:     MOV    AX,[SI+14h]              { 077a  Arp0                          }
         MOV    [SI+0Bh],AX              { 077d                                }
         MOV    BYTE PTR [SI+13h],0      { 0780                                }
@@Out:
end;


{ --------------------------------------------------------------------------
  SCREAM TRACKER'S RETRIGGER, command Qxy: play the note again every y ticks
  AND change its volume each time. It is what makes a retriggered note swell or
  fade instead of simply repeating -- a rolled snare that gets louder, a hit
  that echoes away.

  THE x NIBBLE PICKS ONE OF SIXTEEN VOLUME BEHAVIOURS, and they are not all the
  same kind of arithmetic. Some SCALE the volume by a fraction; others ADD or
  subtract a fixed step. So there are two tables -- a multiplier and an addend
  -- and the multiplier is looked up first: where its entry is zero, that x is
  not a multiply at all and the addend table applies instead. The decoded
  answer goes into the channel as a value plus a flag, so the per-tick half
  never repeats this decision.

  THE COUNTING IS NOT DONE HERE. This routine masks the parameter down to the
  tick count and hands off to the plain retrigger, which already knows how to
  count ticks and raise the flag. Only the volume behaviour is new.

  [re] 147d:0785, NEW IN v1.51. `CommandStart` maps command $23,
  `mcS3mRetrigNote`, here; 147d:0811's `E8 A5 FD` reaches `StartRetrigNote` at
  05b9. `MOV AL,0 / JNZ +1 / INC AX` computes `Ord(RetMult[x] = 0)`, an
  expression whose whole body is a set-on-condition the 8086 has no instruction
  for.

  [re] THE MULTIPLIERS ARE IN SIXTEENTHS: $08 is a half, $18 is three halves,
  $20 is a double. $0c at index 6 is three quarters where Scream Tracker's own
  document says two thirds -- **the binary wins**, and that is the standing rule
  for every place the format reference and this program disagree.
  -------------------------------------------------------------------------- }
procedure StartS3mRetrigNote(var Song : TSong; var Can : TCanal; var N : TFullNote);
const
  { The two behaviours, one table each, indexed by the x nibble. A zero in
    `RetMult` means "this x is an addend, not a factor" -- which is why the
    multiplier table is the one consulted first.

    [re] DS:$03ba and DS:$03ca. BOTH TABLES ARE THE RELEASE'S, names and all,
    and so is `RetAdd` being SHORTINT: the transcription had it as Byte with
    $FF..$F0, the same sixteen bytes, which says nothing about the sign. Reading
    them as signed is what makes the tick's `ADD AH,AL / JNC / MOV AH,0`
    obviously an underflow test rather than a wrap. }
  RetMult : array[0..15] of Byte     = ( 0,  0,  0,  0,  0,   0, $0C, $08,
                                         0,  0,  0,  0,  0,   0, $18, $20);
  RetAdd  : array[0..15] of ShortInt = ( 0, -1, -2, -4, -8, -16,   0,   0,
                                         0,  1,  2,  4,  8,  16,   0,   0);
begin
  if N.Parameter <> 0 then                         { 0788..0794              }
  begin
    Can.S3mRetAdd := RetMult[N.Parameter shr 4] = 0;    { 0795..07b3      }

    if Can.S3mRetAdd then                         { 07b4..07bd              }
      Can.S3mRetVal := RetAdd[N.Parameter shr 4]        { 07be..07d8      }
    else
      Can.S3mRetVal := RetMult[N.Parameter shr 4];       { 07d9..07f1      }

    N.Parameter := N.Parameter and $0F;            { 07f2..0801              }
    StartRetrigNote(Song, Can, N)                  { 0802..0813              }
  end
end;


{ --------------------------------------------------------------------------
  147d:0818 -- Qxy per tick. Run the plain retrigger's counter first, and if it fired
  this tick, change the volume.

  `MUL AH` AND A FLOOR OF SIXTEEN. The multiply is byte by byte into AX, and the
  product is clamped UP to 16 BEFORE the shift rather than after -- so a volume of 1
  times a half gives 16 shr 4 = 1 and not 0, and a note being faded never reaches
  silence by rounding. The clamp is `CMP AX,10 / JNC` on the whole product.

  THE ADDITIVE PATH DETECTS UNDERFLOW WITH THE CARRY. `ADD AH,AL / JNC / MOV AH,0` --
  adding $FF..$F0 to a small volume wraps, and the wrap is what says the slide went
  below zero. Both paths then clamp at $3F. }
procedure TickS3mRetrigNote; assembler;
asm
        CALL    TickRetrigNote           { 0818                                }
        CMP     BYTE PTR [SI+26h],0      { 081b  DoRetrig                     }
        JZ      @@Out                    { 081f                                }
        CMP     BYTE PTR [SI+2Ah],0      { 0821  S3mRetAdd                    }
        JNZ     @@Add                    { 0825                                }
         MOV    AL,[SI+2Bh]              { 0827  the multiplicative path       }
         MOV    AH,[SI+0Ah]              { 082a  Volume                        }
         MUL    AH                       { 082d                                }
         CMP    AX,16                    { 082f                                }
         JNC    @@Shift                  { 0832                                }
          MOV   AX,16                    { 0834                                }
@@Shift:  SHR   AX,4                     { 0837                                }
         CMP    AX,3Fh                   { 083a                                }
         JB     @@PutMul                 { 083d                                }
          MOV   AL,3Fh                   { 083f                                }
@@PutMul: MOV   [SI+0Ah],AL              { 0841                                }
         JMP    @@Out                    { 0844                                }
@@Add:   MOV    AL,[SI+2Bh]              { 0846  the additive path             }
         MOV    AH,[SI+0Ah]              { 0849                                }
         ADD    AH,AL                    { 084c                                }
         JNC    @@Cap                    { 084e                                }
          MOV   AH,0                     { 0850   it wrapped -- underflow      }
@@Cap:   CMP    AH,3Fh                   { 0852                                }
         JB     @@PutAdd                 { 0855                                }
          MOV   AH,3Fh                   { 0857                                }
@@PutAdd: MOV   [SI+0Ah],AH              { 0859                                }
@@Out:
end;


{ --------------------------------------------------------------------------
  THE RING EVENT: HOW A TUNE TALKS TO THE DEMO. This is the one command in the
  unit that makes no sound at all.

  A demo has to cut its visuals to the music, and the music is the only thing
  in the program that knows where the beat is. So the composer writes a cue
  into the pattern -- at the drop, at the key change, wherever the picture
  should change -- and this routine records it. The player collects the cue on
  its next pass and publishes it, and whatever is drawing the screen reads it
  from there. The tune becomes the timeline for the whole production.

  IT BORROWS THE ONE COMMAND THAT DOES NOTHING. ProTracker's 8xx is documented
  as having no effect, so repurposing it costs no musical ability whatsoever
  and ANY tracker can author it -- a composer needs no special tool and no
  special build to write cues. That is the whole synchronisation channel: one
  spare command, two bytes of channel state.

  THE STORE IS UNCONDITIONAL, INCLUDING A ZERO PARAMETER. A cue of zero is
  still a cue; it is a label the demo chooses the meaning of, not a quantity.

  [re] 147d:0622, and it has no counterpart in the release at all.
  12ce:0a58..0a8d copies both fields into `NoteRing[EventSlot, chan]` and then
  clears `RingPending` again; 12ce:0187 tallies the ring into the control block
  the INT 2Fh interface publishes. `VangeliSTracker/LIB` has nothing like it,
  and it is the clearest single piece of evidence that DemoVT is a purpose-built
  fork rather than a subset build.

  [re] IT IS NOT `StartRetrigNote`, which is what its position suggests. The
  release's StartRetrigNote has ONE conditional store (`IF n.Parameter <> 0 THEN
  can.retrigval := n.Parameter`); this has two unconditional ones. And the
  release's TickRetrigNote needs three fields where 1.31's record has two. The
  dispatch table settles it independently: index 26, mcRetrigNote, points at a
  do-nothing tick.

  [re] THE COMMAND IS `mcNPI1`, whose release comment reads "8 xx  Do Nothing
  (as far as I know)". CommandStart's case arm at 147d:06dc calls this routine
  for it. The release has NO Start routine for the command at all -- it is
  absent from 1.39b's case -- and its tick is one of the empty ones. ITS CASE
  ARM IS ALSO LAST IN THE CHAIN: the other sixteen run in the release's own
  order and this one is appended after them, which is what an arm ADDED to an
  existing `case` looks like.
  -------------------------------------------------------------------------- }
procedure StartRingEvent(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  Can.RingSem := N.Parameter;                     { 0860..0871              }
  Can.RingPending := 1                                { 0872..0875              }
end;

{ --------------------------------------------------------------------------
  THE TICK DISPATCH TABLE: one entry per command, holding the ADDRESS of that
  command's per-tick routine. `CommandTick` range-checks the command number,
  indexes this and calls through it -- which is why adding a command is two
  routines and two table slots, and why a command with nothing to do per tick
  still needs an entry.

  IT HOLDS OFFSETS, NOT PROCEDURE POINTERS. Everything in this unit is in one
  SEGMENT, so a 16-bit offset is enough and the call is near. Two bytes per
  command instead of four, and no SEGMENT fixup for the linker to resolve.

  SEVERAL COMMANDS SHARE A TICK, and the sharing is the interesting part: the
  fine portamentos both point at one routine, the fine volume slides at
  another, and every command whose work is done entirely at the row points at
  the do-nothing tick. Sharing is what keeps seventeen of this unit's routines
  down to a single `RET` each.

  [re] DS:$0370, 36 words. THIS IS THE TABLE THAT NAMED SEVENTEEN ROUTINES, and
  it is the only thing that could have: seventeen are one-byte `RET`s, and an
  empty body cannot confirm a pairing -- every empty routine matches every other
  one, so source position was all there was, and position is not confirmation.
  Reading it against the release's `TickCommOfs` at the same index gives each
  one its name from the binary.

  [re] AND THE SIGNATURE IS STRONGER THAN SEVENTEEN SEPARATE MATCHES. Two
  entries are DOUBLED in the release -- 18 and 19 both TickFPortUpDown, 27 and
  28 both TickVolFineUpDn -- and 1.31's table doubles at exactly those four
  indices, on exactly those two addresses. Five entries point at TickNone at
  indices 12..16, and those five land on the same indices too.
  -------------------------------------------------------------------------- }
const
  TickCommOfs : array[mcNone..mcLast] of Word = (
    Ofs(TickNone),          { 0 00  no command                            }

    Ofs(TickArpeggio),      { 0 xy                                        }
    Ofs(TickTPortUp),       { 1 xx                                        }
    Ofs(TickTPortDown),     { 2 xx                                        }
    Ofs(TickNPortamento),   { 3 xy                                        }
    Ofs(TickVibrato),       { 4 xy                                        }
    Ofs(TickT_VSlide),      { 5 xy                                        }
    Ofs(TickVib_VSlide),    { 6 xy                                        }
    Ofs(TickTremolo),       { 7 xy  and it does nothing                   }
    Ofs(TickNPI1),          { 8 xx                                        }
    Ofs(TickSampleOffs),    { 9 xx  nothing -- no SOffs field in 1.31     }
    Ofs(TickVolSlide),      { A xy                                        }
    Ofs(TickNone),          { B xx  all its work is done at row start     }
    Ofs(TickNone),          { C xx                                        }
    Ofs(TickNone),          { D xx                                        }
    Ofs(TickNone),          { E xy                                        }
    Ofs(TickNone),          { F xx                                        }

    Ofs(TickSetFilter),     { E 0x  nothing                               }
    Ofs(TickFPortUpDown),   { E 1x  DOUBLED with E2x, as the release has it }
    Ofs(TickFPortUpDown),   { E 2x                                        }
    Ofs(TickGlissCtrl),     { E 3x                                        }
    Ofs(TickVibCtrl),       { E 4x                                        }
    Ofs(TickFineTune),      { E 5x                                        }
    Ofs(TickJumpLoop),      { E 6x                                        }
    Ofs(TickTremCtrl),      { E 7x                                        }
    Ofs(TickNPI2),          { E 8x                                        }
    Ofs(TickRetrigNote),    { E 9x  nothing -- 1.31 starts it and never acts }
    Ofs(TickVolFineUpDn),   { E Ax  DOUBLED with EBx                      }
    Ofs(TickVolFineUpDn),   { E Bx                                        }
    Ofs(TickNoteCut),       { E Cx                                        }
    Ofs(TickNoteDelay),     { E Dx                                        }
    Ofs(TickPattDelay),     { E Ex                                        }
    Ofs(TickFunkIt),        { E Fx                                        }

    { THREE ENTRIES 1.31b PARKED ON TickNone, AND THE 1.31b NOTE CALLED ALL THREE.
      It said indices 33 and 34 "point at TickNone where the release points at
      TickArpeggio and TickArpeggio2. The slots exist and the feature does not."
      1.51 fills them in, and it does it exactly that way: 33 shares the ORDINARY
      arpeggio tick and only 34 gets the new four-step one, even though both
      commands share a Start routine.

      AND INDEX 35 IS NO LONGER DEAD. `CommandTick`'s guard is `CMP BX,48h` in 1.51
      against 46h in 1.31b, so it now admits index 35 -- and 35 is mcS3mRetrigNote,
      which is the whole point of the version. The note that called this entry
      unreachable was right about 1.31b and is why the change is visible at all. }
    Ofs(TickArpeggio),      { Okt   33 -- the ORDINARY tick, not the new one }
    Ofs(TickOktArp),        { Okt   34                                     }

    Ofs(TickS3mRetrigNote), { 35    reachable in 1.51; 1.31b's guard stopped at 34 }

    { A slot that can never be reached: `mcLast` is a count rather than a
      command, and the guard rejects it. It exists only because the array is
      declared `mcNone..mcLast` and Pascal sizes it from the bounds.

      [re] DS:$0422 holds $0689 -- TickNone -- and the guard admits 0..35. The
      release's table has the same dead final entry, one index earlier. }
    Ofs(TickNone)           { 36    mcLast -- unreachable, as it was in 1.31b }
  );

{ --------------------------------------------------------------------------
  THE PER-TICK DISPATCHER, and the hottest routine in the unit: it runs once
  per channel on every tick, which is thousands of times a second. Five
  instructions.

  THE COMMAND ARRIVES ALREADY DOUBLED, in BX, and the channel in SI. Doubling
  is the caller's job because the caller has the command byte in hand anyway,
  and doing it there saves a shift here -- in a routine this hot, that is the
  kind of saving worth arranging.

  THE RANGE CHECK IS THE ONLY SAFETY THERE IS. A command number out of range
  would index past the table and call whatever offset happened to be there, so
  an out-of-range command simply does nothing rather than being trusted.

  IT ALSO CLEARS `DoRetrig` ON THE WAY THROUGH, which is what makes that flag
  mean "a retrigger fired on THIS tick": whoever raised it gets exactly one
  tick to be seen before the next dispatch clears it again.

  [re] 147d:063f. SI and BX are set up by the caller at 12ce:0d75. `CMP BX,48h`
  is `mcLast * 2`, where 1.31b has 46h -- `mcLast` grew by one when
  `mcS3mRetrigNote` joined the enumeration, so the same source expression emits
  a different immediate. Turbo Pascal emits the sign-extended byte form because
  the value fits; `ADD BX,OFFSET TickCommOfs` cannot, because a relocatable
  offset needs sixteen bits. `RETF` at 064a is the compiler's epilogue and is
  why this must be `far`. 147d:087f is `C6 44 26 00`, the DoRetrig clear, which
  1.31b has no field for and so does not carry.
  -------------------------------------------------------------------------- }
procedure CommandTick; assembler;
asm
        CMP     BX,mcLast * 2            { 087a  $48; 1.31b's mcLast made it $46 }
        JNC     @@1                      { 087d                                }
        MOV     BYTE PTR [SI+26h],0      { 087f  DoRetrig -- one tick only    }
        ADD     BX,OFFSET TickCommOfs    { 0883                                }
        CALL    WORD PTR [BX]            { 0887                                }
@@1:
end;

{ --------------------------------------------------------------------------
  THE ROW-START HALF OF THE UNIT, and the largest routine in it. Called once
  per channel whenever a new row is read: fold the note into the channel, tidy
  up after whatever the last command left behind, then dispatch to the new
  command's Start routine.

  MOST OF IT IS THE TIDYING, AND THAT IS THE INTERESTING PART. An effect that
  was running when the row arrived may have left the channel displaced from
  where the music says it should be, and only this routine knows both the old
  command and the new one, so only this routine can put things back:

    * AN ARPEGGIO OR A VIBRATO LEAVES THE PITCH WHEREVER IT LANDED. If the new
      row does not continue it, the period is restored from the note. A vibrato
      followed by another vibrato is NOT restored -- the wobble carries on
      through, which is what a composer writing 4xy on consecutive rows means.
    * A RETRIGGER'S COUNTER IS RESET WHEN THE EFFECT BEGINS, not while it runs,
      so that a retrigger held across several rows keeps its phase instead of
      restarting on every one.
    * A SAMPLE OFFSET IS CONSUMED. The flag is cleared here so that one 9xx
      applies to one note and not to every note after it.
    * A NOTE PORTAMENTO THAT HAS ARRIVED snaps its period to the destination,
      because repeated adding of a step will overshoot and stop just past it.

  THE NEW NOTE'S PERIOD IS TAKEN LAST, AND NOT FOR A NOTE PORTAMENTO -- that
  command's whole point is to slide from where the channel already is towards
  the new note rather than jump to it. The exception is the reason the
  assignment is guarded at all.

  [re] 147d:064b, 565 bytes. FAR, and the frame says so: `RETF 0C` at 087c,
  with the parameters at [BP+06] upward rather than [BP+04] as every other
  routine in this unit has them; the interface publishes it and 12ce:0a38 calls
  it far.

  [re] The first test's bracketing is read off the jump targets: 0656 goes
  forward to the assignment, 0660 to the pair of `N.Command` tests, and
  066a/0674/067e all land past the assignment -- `A or (B and C)`, not
  `(A or B) and C`.

  [re] THE CASE ARMS ARE THE RELEASE'S ORDER PLUS ONE: `mcNPI1`, which is
  StartRingEvent, appended last. In 1.31b five of the arms present here were
  absent -- `mcSampleOffs`, `mcRetrigNote`, `mcOktArp`, `mcOktArp2`,
  `mcS3mRetrigNote` -- along with the retrigger reset, the `SOffs` clear and the
  portamento-arrival block, all of which touch fields 1.31b's TCanal does not
  have. There, 068d ran straight into the `N.Period` test.
  -------------------------------------------------------------------------- }
procedure CommandStart(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  { 064e..068d -- an effect that displaced the period has ended; put it back. }
  if (Can.Note.Command = mcArpeggio) or
     (((Can.Note.Command = mcVibrato) or
       (Can.Note.Command = mcVib_VSlide)) and
      ((N.Command <> mcVibrato) and
       (N.Command <> mcVib_VSlide))) then          { 064e..067f              }
    Can.Period := Can.Note.Period;                 { 08bf..08cc              }

  { ALL THREE OF THE ADDITIONS BELOW WERE NAMED BY THE 1.31b NOTE ABOVE, a version
    before any of them could be measured. It read the release and recorded "a
    retrigger-counter reset, a `can.SOffs := FALSE`, and a block that copies
    `PeriodDest` into the period when a note portamento ends. All three touch fields
    1.31's TCanal does not have, and all three are simply absent." They are here, in
    that order, and the fields exist now.

    THE RETRIGGER COUNTER RESETS WHEN THE EFFECT STARTS, not while it runs -- the old
    command must NOT be a retrigger and the new one must be. Five compares and four
    branches, and the branch targets are what fix the bracketing: 08d5 and 08df both
    leave for 08fd, so those two are the `and`; 08e9 goes to the STATEMENT at 08f5 and
    08f3 leaves for 08fd, which is an `or` whose true-path is the assignment. }
  if (Can.Note.Command <> mcS3mRetrigNote) and
     (Can.Note.Command <> mcRetrigNote) and
     ((N.Command = mcS3mRetrigNote) or
      (N.Command = mcRetrigNote)) then             { 08cd..08f4              }
    Can.RetrigCt := 0;                             { 08f5..08fc              }

  { A NOTE PORTAMENTO THAT HAS JUST ENDED SNAPS TO ITS TARGET. Both the note's period
    and the channel's are set, and both from `PeriodDest` -- 0911 and 091f each reload
    +$11 rather than reusing AX, which is two statements and not one. }
  if (Can.Note.Command = mcNPortamento) and
     (N.Command <> mcNPortamento) then             { 08fd..0910              }
    begin
      Can.Note.Period := Can.PeriodDest;           { 0911..091e              }
      Can.Period      := Can.PeriodDest            { 091f..092c              }
    end;

  if N.Period <> 0 then                            { 092d..0936              }
    Can.Note.Period := N.Period;                   { 0937..0944              }

  { CLEARED ON EVERY ROW, so a 9xx offset applies to the row that carries it and not
    to the one after. `StartSampleOffs` sets it again a few instructions later if the
    new command is one. }
  Can.SOffs := False;                              { 0945..094c              }

  Can.Note.Command   := N.Command;                 { 094d..095a              }
  Can.Note.Parameter := N.Parameter;               { 095b..0968              }

  { THE ARM ORDER IS THE COMPARE ORDER AND IT IS NOT SORTED. Turbo Pascal keeps a
    sparse `case` selector in AL and emits `CMP AL,n / JNZ` once per label in the
    order the labels are WRITTEN, so the chain in the binary is a direct reading of
    the release's source order and nothing else. 1.51's is

        01 02 03 04 05 0c | 06 07 0b | 0a | 0d 0e 10 11 | 1a 1b 1c | 12 13 |
        21 22 23 | 09

    which is 1.31b's with `0a` inserted after the volume-slide group, `1a` ahead of
    `1b`/`1c`, and the three new ones pushed in before `09` -- which stays last,
    still the appended DemoVT arm the 1.31b note identified.

    `mcOktArp` AND `mcOktArp2` ARE TWO ARMS, NOT ONE LABEL LIST. Both call 068a, but
    from different displacements -- `E8 55 FB` and `E8 3D FB` -- so each has its own
    copy of the three pushes and its own call. Written as `mcOktArp, mcOktArp2:` the
    compiler would emit one body and a shared jump, which is 25 bytes fewer. }
  case N.Command of                                { 0969..0b7c              }
    mcArpeggio:      StartArpeggio(Song, Can, N);
    mcTPortUp:       StartTPortUp(Song, Can, N);
    mcTPortDown:     StartTPortDown(Song, Can, N);
    mcNPortamento:   StartNPortamento(Song, Can, N);
    mcVibrato:       StartVibrato(Song, Can, N);
    mcJumpPattern:   StartJumpPattern(Song, Can, N);
    mcT_VSlide,
    mcVib_VSlide,
    mcVolSlide:      StartVolSlide(Song, Can, N);
    mcSampleOffs:    StartSampleOffs(Song, Can, N);
    mcSetVolume:     StartSetVolume(Song, Can, N);
    mcEndPattern:    StartEndPattern(Song, Can, N);
    mcSetTempo:      StartSetTempo(Song, Can, N);
    mcSetFilter:     StartSetFilter(Song, Can, N);
    mcRetrigNote:    StartRetrigNote(Song, Can, N);
    mcVolFineUp:     StartVolFineUp(Song, Can, N);
    mcVolFineDown:   StartVolFineDown(Song, Can, N);
    mcFinePortaUp:   StartFinePortaUp(Song, Can, N);
    mcFinePortaDn:   StartFinePortaDown(Song, Can, N);
    mcOktArp:        StartOktArp(Song, Can, N);
    mcOktArp2:       StartOktArp(Song, Can, N);
    mcS3mRetrigNote: StartS3mRetrigNote(Song, Can, N);
    mcNPI1:          StartRingEvent(Song, Can, N);
  end;

  { 0859..087a -- and take the new note's pitch, unless a note portamento is meant
    to slide to it from wherever the channel already is. }
  if (N.Period <> 0) and (N.Command <> mcNPortamento) then   { 0859..086c      }
    Can.Period := N.Period                         { 086d..087a              }
end;

end.
