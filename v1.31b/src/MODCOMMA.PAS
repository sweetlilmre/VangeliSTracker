{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).

  SEGMENT 142f -- NOTES AND EFFECTS. 2,176 bytes, seventeen routines.

  COMPLETE. All 2,175 bytes of code; 142f:087f is one byte of padding. `units.py` reports the prefix,
  which is the right measure while the unit is being built strictly top-down:
  Turbo Pascal lays procedures out in source order, so a stub of the wrong size
  displaces everything below it and the prefix stops at the first one.

      transcribed   0000..087e   COMPLETE. Forty-three routines and the dispatch
                                 table; 087f is one byte of linker padding.

  THE RELEASE IS THE COUNTERPART AND THE MAPPING IS 1:1 SO FAR. `LIB/MODCOMMA.PAS`
  is 1.39b's version of this unit -- 959 lines against 1.31's 2,176 bytes, because
  it grew the S3M and Oktalizer effects -- and its first six routines are these
  six, in this order, with the same bodies -- twelve now, and the three after those
  are empty in both. That is twelve consecutive confirmations rather than one
  plausible name, which is what the standing rule asks for.

  IT IS ALSO THE HOME OF `TCanal`, because 142f takes it and 12ba fills it, so
  neither can own it. The release splits it the same way.

  WHERE 1.31 AND 1.39b DIVERGE, so far:

  * **THE PORTAMENTO STEP IS UNSCALED HERE AND SCALED BY FOUR IN THE RELEASE**, and
    it is specific to the portamentos rather than a change of units across the
    unit -- `StartVibrato` keeps the release's `SHL 2` on its depth at 02dd, so the
    tidier story of "1.31 counts whole periods everywhere" is NOT what the bytes
    say. `StartTPortUp` stores the parameter unscaled where the release has
    `can.TPortaIncr := WORD(n.Parameter) SHL 2`; `StartNPortamento` reads and writes
    `PeriodIncr` unscaled where the release has a `SHR 2` on the way out and a
    `SHL 2` on the way in. Two routines, four places, no shift in any of them --
    142f:00d9 is `MOV AL,[DI+5] / XOR AH,AH / MOV [DI+1f],AX` and there is nothing
    between the load and the store. So the same pattern data slides four times
    faster in 1.31, which is a behavioural difference and worth knowing before
    anyone compares the two players by ear.
  * `StartArpeggio` uses A PERIOD TABLE where the release uses a MULTIPLY TABLE.
    1.39b computes `f SHL 14 DIV ArpTable[semitones]`, which works for any tuning;
    1.31 looks the period's note up in `VTNotes.NoteOf`, adds the semitones, and
    reads `VTNotes.NotePeriods` -- the classic ProTracker way, and it only works
    on the twelve-tone table. That is the earlier design, and it is why 142f is
    the consumer of the table 1650 builds.
  =========================================================================== }
unit ModCommands;

interface

uses
  SongUnit, VTNotes;

type
  { --- the channel state, DS:$1260 in 12ba's array ------------------------
    `TCanal` and `TFullNote` ARE the release's, head for head. 12ba:11fd..121d
    proves the head -- four stores landing on `Note.Period`, `Note.Instrument`,
    `Note.Command` and `Period` at +$01, +$00, +$04 and +$0b -- and 142f now
    proves five more fields further in.

    FIFTEEN OFFSETS ARE NOW ANCHORED BY AN INSTRUCTION IN THIS SEGMENT:

        +$0f  PeriodIncr   142f:01c6 tests it signed, 142f:0216 stores a Word
        +$11  PeriodDest   142f:019b stores the note's period, 142f:0258 compares
        +$13  ArpCt        142f:0007 clears it, 142f:00a3 increments it
        +$14  Arp0         142f:002c stores the current period
        +$16  Arp1         142f:0064
        +$18  Arp2         142f:009b
        +$1a  VibWave      142f:028e reads it to select the waveform
        +$1b  VibPos       142f:02fe clears it, 142f:034b advances it
        +$1c  VibWidth     142f:029c and both other CASE arms
        +$1d  VibDepth     142f:02e3 stores it, 142f:0348 adds it
        +$1e  VibReset     142f:02f4 tests it
        +$1f  TPortaIncr   142f:00e5 stores a Word, 142f:016d subtracts it
        +$21  VolumeIncr   142f:038e stores it, 142f:03d7 reads it signed
        +$22  TPortIsFine  142f:00ec clears it, 142f:00f6 tests it
        +$23  VSldIsFine   142f:0370 clears it, 142f:03ac tests it

    THERE ARE NO GAPS LEFT. Every field from +$00 to +$23 is anchored by an
    instruction rather than taken from the release, which is what the standing rule
    wants and what the record did not have two sessions ago -- +$0f and +$11 fell to
    StartNPortamento, +$1a..+$1e to StartVibrato, and +$21 and +$23 to
    StartVolSlide. That is the pattern to expect from here on: each routine confirms
    the fields it touches, and a layout that was "determined by the gaps" becomes one
    that is determined by use. Only +$24 and +$25 keep names from elsewhere.

    THE TAIL DOES NOT CARRY OVER, AND 142f SAYS WHY. The record is 38 bytes,
    $00..$25. The release runs to +$2b and its +$24/+$25 are `RetrigCt`/`RetrigVal`
    -- but **1.31 HAS NO RETRIGGER COMMAND AT ALL**: where 1.39b puts
    StartRetrigNote and TickRetrigNote, 142f:0584 goes straight to the fine volume
    slide. With no retrigger routine there is nothing for those two bytes to hold,
    which is why 12ba is free to use them as the note ring's `Chan` and `Note`
    (12ba:0a8a and 12ba:0a6f). Ours keep the names their USE gives them, and the
    reason the release's names do not apply is now a fact rather than a caution. }
  PCanal = ^TCanal;
  TCanal = record
    Note       : TFullNote;     { +$00                                       }
    Instrument : PSampleDesc;   { +$06  and 12ba:09ff dereferences it        }
    Volume     : Byte;          { +$0a                                       }
    Period     : Word;          { +$0b                                       }
    RealPeriod : Word;          { +$0d  the release's name; 12ba:0eaf writes it }

    { +$0f, +$11 -- the note portamento's step and target, the release's names,
      and BOTH ARE NOW ANCHORED by StartNPortamento: 142f:0194 stores the note's
      period into +$11, and 142f:01c6 tests +$0f with a signed `JLE`, so the step
      is an Integer and the sign of it carries the slide's direction. }
    PeriodIncr : Integer;       { +$0f  ANCHORED                             }
    PeriodDest : Integer;       { +$11  ANCHORED                             }

    ArpCt      : Byte;          { +$13  ANCHORED                             }
    Arp0       : Word;          { +$14  ANCHORED                             }
    Arp1       : Word;          { +$16  ANCHORED                             }
    Arp2       : Word;          { +$18  ANCHORED                             }

    { +$1a..+$1e -- the vibrato state. Five bytes for five fields, forced by the
      anchors either side; TickVibrato is a stub, so none is confirmed by use. }
    VibWave    : Byte;          { +$1a  not yet confirmed                    }
    VibPos     : Byte;          { +$1b  not yet confirmed                    }
    VibWidth   : Byte;          { +$1c  not yet confirmed                    }
    VibDepth   : Byte;          { +$1d  not yet confirmed                    }
    VibReset   : Boolean;       { +$1e  not yet confirmed                    }

    TPortaIncr : Integer;       { +$1f  ANCHORED                             }
    VolumeIncr : ShortInt;      { +$21  ANCHORED                             }
    TPortIsFine : Boolean;      { +$22  ANCHORED                             }
    VSldIsFine : Boolean;       { +$23  ANCHORED                             }

    { +$24 and +$25 -- named for WHERE THEY GO rather than what they are:
      12ba:0a8a copies +$24 into the note ring's `Chan` byte and 12ba:0a6f copies
      +$25 into its `Note`. The consumer at 12ba:01ce tests the second and uses
      the first to index the published control block. }
    RingChan   : Byte;          { +$24                                        }
    RingNote   : Byte;          { +$25   38 bytes in all                      }
  end;

{ --------------------------------------------------------------------------
  THE SEQUENCER STATE LIVES HERE, NOT IN PLAYMOD, AND 142f IS WHAT FORCED IT.

  `142f:03ed` reads DS:$034c, DS:$0340 and DS:$034a, and all three were declared in
  PLAYMOD.PAS. That cannot stand: PlayMod `uses` ModCommands, so ModCommands cannot
  use PlayMod, and the effect routines in this SEGMENT write the sequencer's
  position directly. The release resolves it the same way -- `LIB/MODCOMMA.PAS`
  declares `NextNote`, `NextSeq` and `MySongLen` in its own interface, with the
  comment "Values set from outside this UNIT ... They both must have been set BEFORE
  calling this UNIT."

  SO THE OWNERSHIP IS SETTLED BY THE CALL GRAPH RATHER THAN BY PREFERENCE, which is
  the first time anything in this project has settled a DGROUP question for a
  structural reason instead of an address. Compare `DEVGUS`, where three globals sat
  in the wrong unit and nothing could see it.

  THE NAMES ARE THE RELEASE'S and the pairing is confirmed by reading both bodies:
  ours called them `PlayPos`, `PlayRow` and `OrderLen`, and every statement they
  appear in matches the release's line for line.

      NextSeq    $034c   was PlayPos    the order position being played
      NextNote   $034a   was PlayRow    the row; $FFFF means past the end
      MySongLen  $0340   was OrderLen   the last order position in the range

  ~~DECLARED `var`, NOT AS TYPED CONSTANTS.~~ **WITHDRAWN, AND THE ARGUMENT FOR IT WAS
  WRONG IN ITS PREMISE.** The note said "a `var` and a typed constant compile to
  identical accesses, so the shape that claims less is the one to use". The ACCESSES
  are identical; the IMAGE is not. A typed constant is initialised data written into
  the EXE, and a plain `var` is reserved space the linker never writes -- and the two
  live in different regions of DGROUP, so the choice fixes the ADDRESS as well. It was
  unmeasurable until the program linked, and `dgroup.py` measures it now.

  It also was not a case of taking DATA from the release. The values below are read out
  of the original's DGROUP image, and four of them are non-zero and land exactly where
  the release's initialisers say: 125, 125, 6, 1 and 1.

  **SIXTEEN DECLARATIONS ON SIXTEEN KNOWN ADDRESSES, IN ONE PASS.** DGROUP is laid out
  in link order, `12ba`/PlayMod comes immediately before `142f`/ModCommands, and this
  unit's block runs $0334..$034f. Laying the release's declaration order into it lands
  every one of the sixteen on an address some instruction in the tree already named:

      $0334 MyLoopMod          $0335 PermitFilterChange   $0336 TempoDiv    = 125
      $0338 CurTempo    = 125  $033a TempoAccum           $033c RangeStart
      $033e RangeEnd          $0340 MySongLen            $0342 ReqStart
      $0344 ReqEnd            $0346 ReqLen               $0348 FilterIsOn
      $0349 CurSpeed    = 6    $034a NextNote      = 1     $034c NextSeq     = 1
      $034e TickInRow

  **AND NINE OF THEM WERE DECLARED IN PLAYMOD.PAS, WHICH COULD NOT HAVE BEEN RIGHT.**
  Their addresses INTERLEAVE with the three that were already here -- $033c and $033e
  sit either side of $0340 -- and two units' blocks cannot interleave when DGROUP is
  laid out one unit at a time. That contradiction is what found them; the release then
  confirmed all nine in its own `CONST` section. Same lesson as the three that moved
  before: **the call graph settled those, and the LAYOUT settles these.**

  THE RENAMES ARE STILL DECLINED, for the reason recorded below: the release's `Tempo`
  collides with a field of `TPlayingNote`. Our names are kept and the release's are
  quoted beside them. Moving a declaration between units cannot change a byte of
  either one's code, so `units.py` reporting both units unchanged is the check.
  -------------------------------------------------------------------------- }
const
  { $0334..$0337 -- both of these were declared in PLAYMOD until the layout moved them. }
  MyLoopMod          : Boolean = False;  { DS:$0334                            }
  PermitFilterChange : Boolean = False;  { DS:$0335  the `FilterChange` key     }
  TempoDiv           : Word    = 125;    { DS:$0336  release: BPMDivider        }

  { The release calls these `BPMIncrement` and `BPMCount`. 142f:04a6 and 142f:04bc
    write CurTempo from the F-command. }
  CurTempo           : Word    = 125;    { DS:$0338  release: BPMIncrement      }
  TempoAccum         : Word    = 0;      { DS:$033a  release: BPMCount          }

  { THE TWO HALVES OF THE PLAY RANGE. `My*` is the copy the player is working
    through and the bare name is what a client asked for; PlayStart copies one to
    the other, which is where both sets were read from (12ba:10b4, 10ba, 10c0). }
  RangeStart         : Word    = 0;      { DS:$033c  release: MyFirstPattern    }
  RangeEnd           : Word    = 0;      { DS:$033e  release: MyRepStart        }
  MySongLen          : Word    = 0;      { DS:$0340                            }
  ReqStart           : Word    = 0;      { DS:$0342  release: FirstPattern      }
  ReqEnd             : Word    = 0;      { DS:$0344  release: RepStart          }
  ReqLen             : Word    = 0;      { DS:$0346  release: SongLen           }

  { NOT PlayMod's `FilterIsOn`, which is a DIFFERENT variable at DS:$02cd. 1.31 has
    two of them and the release has one; see the long note that used to sit below.
    11bb:0b0e's `FilterIsOn` key writes THIS one, which is why it is exported --
    safe only because PlayMod's copy stays private, so no unit can see both. }
  FilterIsOn         : Boolean = False;  { DS:$0348                             }

  { $0349..$034f. The release's names are `Tempo`, `NextNote`, `NextSeq`, `TempoCt`;
    `Tempo` is the one rename this tree declines on purpose. }
  CurSpeed           : Byte    = 6;      { DS:$0349  release: Tempo             }
  NextNote           : Word    = 1;      { DS:$034a                             }
  NextSeq            : Word    = 1;      { DS:$034c                             }
  TickInRow          : Byte    = 0;      { DS:$034e  release: TempoCt           }

{ 142f:064b -- start whatever effect the note carries. STILL A STUB. }
procedure CommandStart(var Song : TSong; var Can : TCanal; var N : TFullNote); far;

{ 142f:063f -- the per-tick effect dispatcher. STILL A STUB.

  IT TAKES ITS ARGUMENTS IN REGISTERS: SI points at the channel and BX holds the
  command number DOUBLED, which is a jump-table index. The release documents the
  convention in `LIB/MODCOMMA.PAS`: "En las del tick, se entra con SI apuntando al
  TCanal correspondiente." So the declaration below carries no parameters and the
  caller sets the registers up by hand -- see 12ba:0d75. }
procedure CommandTick; far;

implementation

{ --------------------------------------------------------------------------
  TWO FLAGS THAT STAY PRIVATE, and the first of them is a genuine oddity.

  `FilterIsOn` at DS:$0348 is what the E0x command writes (142f:04da). The release
  has exactly ONE variable of that name, in this unit's interface -- but 1.31 HAS
  TWO: PlayMod's own filter flag is at DS:$02cd, next to FilterOn and FilterOff, and
  it is the one the initialisation section reads at 12ba:1430 to choose which kernel
  is in force. Two addresses, two variables, and nothing in the transcribed tree
  reads $0348 at all.

  SO IT IS DECLARED IN THE IMPLEMENTATION SECTION RATHER THAN THE INTERFACE, which
  is the least-claim option: exporting it would put a second `FilterIsOn` in scope
  wherever PlayMod is compiled, and Pascal would silently resolve those references
  to PlayMod's own. That is a shadowing bug waiting to happen and no byte comparison
  could ever see it. Whether 1.31 MEANT one variable and ended up with two is not
  something the bytes can answer; it is the same shape as `LoopMod` at $02c8, which
  is also written and never read.

  `PermitFilterChange` at DS:$0335 gates the whole thing and is the release's name.
  -------------------------------------------------------------------------- }

{ --------------------------------------------------------------------------
  EVERY ROUTINE IN THIS UNIT IS NEAR. `RET 0C` at 142f:00a0 is a near return with
  twelve bytes of parameters -- three `var` references -- so the internal effect
  routines are called near from within the SEGMENT, and only the two the interface
  publishes are far. That is also why the parameters sit at [BP+04] upward rather
  than [BP+06]: Song at [BP+0C], Can at [BP+08], N at [BP+04], which is Pascal
  order with the first-declared pushed first.
  -------------------------------------------------------------------------- }

{ Forward, because StartTPortUp and StartTPortDown fall back on them and their
  bodies are 1,000 bytes further down the SEGMENT -- 142f:0114 calls 142f:04e2
  and 142f:0163 calls 142f:052f. The release declares them FORWARD for the same
  reason and in the same place. }
procedure StartFinePortaUp(var Song : TSong; var Can : TCanal;
                           var N : TFullNote); forward;
procedure StartFinePortaDown(var Song : TSong; var Can : TCanal;
                             var N : TFullNote); forward;

{ 142f:03cd -- CONFIRMED by the two near jumps at 142f:0352 and 142f:0359, which
  the release writes as `JMP TickVolSlide` from both TickT_VSlide and
  TickVib_VSlide. The prologue scanner never found it: it is frameless. Forward
  because those two jump to it from 120 bytes above, which is also why both jumps
  take the three-byte form. STILL A STUB. }
procedure TickVolSlide; forward;


{ --------------------------------------------------------------------------
  142f:0000 -- command 0, ARPEGGIO. Precompute the three periods it rotates
  through; TickArpeggio just cycles them.

  THE TWO TABLE LOOKUPS ARE THE WHOLE ROUTINE, and they are why 1650 exists:
  `NoteOf[Period]` turns a period back into a note number, the semitone offset
  from the effect's nibble is added, and `NotePeriods` turns it back into a
  period. Both tables live in VTNotes and both are now exported.

  THE INDEX ARITHMETIC IS 32-BIT AND THAT IS THE SOURCE TALKING. 142f:0042 is
  `CWD` on the semitone count and 142f:0053 is `XOR DX,DX` on the masked table
  entry, then `ADD AX,CX / ADC DX,BX` -- a LongInt add whose high word is then
  thrown away by the indexing. Turbo Pascal promotes `Integer + Word` to LongInt,
  so the widening is forced by the operand types and not by anything written: the
  semitone count is signed and `NoteOf[..] and $FF` is not.

  THE OPERAND ORDER IS READ OFF THE BYTES, and it is the reverse of what reads
  naturally. Turbo Pascal evaluates the RIGHT operand of a 32-bit add first, into
  CX:BX, then the left into DX:AX -- 142f:003f loads the semitone count and
  sign-extends it into CX:BX before touching either table, so the semitone count
  is the RIGHT-hand operand and the table lookup is the left. Written the other way
  round the two halves swap and nothing else changes, which is why it had to be
  measured rather than reasoned.

  AND THE SEMITONE COUNT IS SIGNED, which the `CWD` settles. It comes from a
  nibble so it can only be 0..15, but the variable it is kept in is an Integer --
  had it been a Word the compiler would have emitted `XOR DX,DX` here too.
  -------------------------------------------------------------------------- }
procedure StartArpeggio(var Song : TSong; var Can : TCanal; var N : TFullNote);
var
  { `ENTER 4,0`, and both slots are written then read back, so both are declared
    variables rather than compiler temporaries. Semis is assigned twice, once per
    nibble, which by the standing rule makes it one variable and not two. }
  Period : Word;                  { [BP-2]                                   }
  Semis  : Integer;               { [BP-4]                                   }
begin
  Can.ArpCt := 0;                                  { 0007..000b              }

  Period := N.Period;                              { 000c..0015              }
  if Period = 0 then                               { 0016..001b              }
    Period := Can.Note.Period;                     { 001c..0025              }

  Can.Arp0 := Period;                              { 0026..002f              }

  Semis := N.Parameter shr 4;                      { 0030..003e              }
  Can.Arp1 := NotePeriods[(NoteOf[Period] and $FF) + Semis];   { 003f..0067   }

  Semis := N.Parameter and $0F;                    { 0068..0075              }
  Can.Arp2 := NotePeriods[(NoteOf[Period] and $FF) + Semis]    { 0076..009e   }
end;


{ --------------------------------------------------------------------------
  142f:00a3 -- arpeggio, per tick. Frameless, and that is the release's shape
  exactly: `PROCEDURE TickArpeggio; ASSEMBLER;` names no parameter, so Turbo
  Pascal gives it no prologue at all and the channel arrives in SI.

  **AND THE RELEASE STATES THAT CONVENTION FOR THE WHOLE GROUP.** Over these
  routines LIB/MODCOMMA.PAS says "[1.39b] Command routines, for the start of a
  note and for each tick", then "[1.39b] The tick routines are entered with SI
  pointing at the relevant TCanal." One sentence covering every handler here,
  written by the author, where this tree derived it per routine from the
  prologue each one lacks. The two agree.

  **SO EVERY `[SI+n]` IN THIS FILE IS A TCanal FIELD, AND THIS IS THE KEY** --
  this version's own offsets, which are not v1.51's past +$13:

      +$00  Note        the note being played (TFullNote, 6 bytes)
      +$06  Instrument  pointer to the sample descriptor
      +$0a  Volume
      +$0b  Period      what the mixer turns into a step
      +$0d  RealPeriod  Period after the instrument's tuning
      +$0f  PeriodIncr  portamento step; SIGNED, the sign is the direction
      +$11  PeriodDest  portamento target
      +$13  ArpCt       arpeggio phase
      +$1a  VibWave     vibrato waveform and state -- NONE of these five is
      +$1b  VibPos      confirmed by an instruction, because TickVibrato is a
      +$1c  VibWidth    stub here. They are placed by their neighbours, and a
      +$1d  VibDepth    reader should treat them as the best available reading
      +$1e  VibReset    rather than as measurement.

  A handler may assume SI and nothing else; AX, BX, CX and DX are scratch.

  `@@Fin` IS THE EPILOGUE. Both `JMP @@Fin`s land on 142f:00cb, which is the `RET`
  the compiler appends -- there is no instruction of our own at that label. Written
  with a written `RET` instead, TP would emit a second one.
  -------------------------------------------------------------------------- }
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
  142f:00cc -- commands 1 and 2, TONE PORTAMENTO up and down. A non-zero
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
  142f:016a -- tone portamento, per tick. Four instructions each, and BOTH
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
  142f:0184 -- command 3, NOTE PORTAMENTO. Slide towards a target period rather
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
  142f:0240 -- note portamento, per tick. Step towards the target and stop when
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
  142f:0273 -- command 4, VIBRATO. Set the width and the depth from the two
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
  142f:0307 -- vibrato, per tick. The release's body instruction for instruction,
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

  `MOV BX,0350` IS A DGROUP OFFSET, NOT A CODE ADDRESS, and it has to be: `XLAT`
  reads `DS:BX+AL`. 142f:0350 in the code SEGMENT is the middle of TickT_VSlide, so
  the table is a typed constant living in DGROUP -- which is exactly where Turbo
  Pascal puts a `const` declared inside a procedure, and exactly how the release
  declares it.

  `AND AH,AH` is `20 E4` and `MOV AL,DL` is `88 D0` -- the inline assembler's
  direction bits throughout, which is the standing tell for hand-written asm.
  -------------------------------------------------------------------------- }
procedure TickVibrato; assembler;
const
  { A quarter-scaled half-cycle sine, DS:$0350. The release's table and its
    comment; transcribed rather than computed. }
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
  142f:034f and 142f:0356 -- commands 5 and 6, PORTAMENTO-PLUS-VOLUME-SLIDE and
  VIBRATO-PLUS-VOLUME-SLIDE. Two instructions each: do one effect, then fall into
  the other. The release is identical.

  THE `JMP` IS THE THREE-BYTE NEAR FORM AND THAT IS A FORWARD REFERENCE SHOWING.
  `E9 78 00` at 0352 reaches 03cd, a displacement of $78, which fits a short jump
  twice over -- but `TickVolSlide` is declared FORWARD and lives 120 bytes further
  down, so Turbo Pascal's inline assembler does not yet know the distance and takes
  the long form. It does NOT pad afterwards, which is where it differs from TASM's
  `JUMPS`: TP simply emits three bytes and moves on. Both jumps here are like that.

  AND THAT PINS `TickVolSlide` AT 142f:03cd -- a routine the prologue scanner never
  found, because it is frameless. Two independent jumps land on it and the release
  says what both of them jump to, so the pairing is confirmed rather than inferred.

  THE TRAILING `RET` IS THE COMPILER'S AND IS UNREACHABLE. An `assembler` procedure
  always gets its epilogue, even after an unconditional `JMP` out of the body --
  0355 and 035c are those, and writing a `RET` in the source would emit a second.
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
  142f:035d, 035e, 035f -- THREE DO-NOTHING TICK ROUTINES, one byte each.

  A bare `RET` with no parameter count, so all three take no arguments and are
  Tick routines rather than Start ones. The release has exactly three consecutive
  empty `ASSEMBLER` ticks in this region -- `TickTremolo`, `TickNPI1` and
  `TickSampleOffs` -- with `StartSampleOffs` between the second and third.

  AND `StartSampleOffs` IS ABSENT HERE, which is independently supported: it sets
  `can.SOffs` and `can.SOffsVal` at +$27 and +$28, and 1.31's TCanal is 38 bytes
  and stops at +$25. So 1.31 has no sample-offset support and the three empties sit
  next to each other.

  THEY KEEP ADDRESS NAMES ANYWAY, and this is the clearest case in the project for
  why. An EMPTY body cannot confirm a pairing -- every empty routine matches every
  other one -- so position is all there would be, and position is not confirmation.
  What will settle it is the DISPATCH TABLE at 142f:063f, which maps each command
  number to one of these addresses. Rename them then, from the table, not now.
  -------------------------------------------------------------------------- }
procedure TickTremolo; assembler;
asm
end;

procedure TickNPI1; assembler;
asm
end;

procedure TickSampleOffs; assembler;
asm
end;


{ ==========================================================================
  NOTHING BELOW IS A STUB ANY MORE. Kept as a section marker because the routines
  below are the ones the interface publishes plus the DemoVT-only command, and they
  are last in the SEGMENT. Note
  that TickVolSlide, above, is one the prologue scanner never found at all -- it is
  frameless, and it was located by reading the jumps that reach it. Expect more of
  those among what is left, so do not treat the scanner's list as complete. They are named by ADDRESS on purpose:
  the release's routine list continues `StartNPortamento, TickNPortamento,
  StartVibrato, TickVibrato, ...` and the mapping has held for six routines
  running, but the standing rule is that a pairing must be confirmed by reading
  both bodies -- not inferred from position. Two of the thirteen ARE confirmed,
  by the calls at 142f:0114 and 142f:0163, and those two carry real names.

  The bodies are deliberately wrong. `units.py`'s prefix stops at 0184.
  ========================================================================== }

{ --------------------------------------------------------------------------
  142f:0360 -- command A, VOLUME SLIDE. One nibble slides up and the other down,
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
  142f:03cd -- volume slide, per tick. CONFIRMED at this address by the two jumps
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
  142f:03ed -- command B, JUMP TO A PATTERN POSITION. Set the order position from
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
  142f:0417 -- command C, SET VOLUME. Clamped to 64, and note the clamp is
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
  142f:043e -- command D, END OF PATTERN. Advance to the next order position and
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
  142f:0490 -- command F, SET TEMPO. ProTracker overloads one command: a value
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
  142f:04c3 -- command E0x, SET THE OUTPUT FILTER, and only if the client has
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


{ 142f:04e1 -- command E0x per tick, and it does nothing. One byte, a bare `RET`,
  which is an `assembler` procedure with no parameters and an empty body. The
  release has it as `TickSetFilter` and it is empty there too -- but an empty body
  confirms nothing, so this keeps its address like the three at 035d..035f. The
  dispatch table at 063f will name it. }
procedure TickSetFilter; assembler;
asm
end;

{ --------------------------------------------------------------------------
  142f:04e2 and 142f:052f -- commands E1x and E2x, FINE PORTAMENTO up and down.
  CONFIRMED at both addresses by the near calls at 142f:0114 and 142f:0163.

  THEY ARE THE MIRROR OF StartTPortUp AND StartTPortDown, and the pair of pairs is
  what makes the `TPortIsFine` flag make sense: each version sets the flag its own
  way, and a zero parameter sends the note to the OTHER one by rewriting
  `Note.Command`. Coarse with a zero parameter and the fine flag set goes fine;
  fine with a zero parameter and the flag clear goes coarse. Between them the four
  routines implement "repeat the last portamento, whichever kind it was".

  AND THE FINE VERSION APPLIES ITSELF IMMEDIATELY. The `asm` block at 0525 calls the
  COARSE tick routine once, on the spot, which is what makes a fine portamento fine:
  it moves the period on the row itself and then the per-tick dispatcher never sees
  it, where a coarse one moves on every tick but the first. `MOV SI,WORD PTR Can`
  again -- the offset half of a var reference, because TickTPortUp takes its channel
  in SI.

  `MOV byte ES:[DI+4],2` AT 0516 IS A THIRD CONFIRMATION OF THE COMMAND ENUM.
  mcTPortUp is 2 and mcTPortDown is 3 counting from mcNone, and 0563 stores 3. With
  the $12 and $13 in StartTPortUp/Down that is four values fixed by four stores.

  NO SCALING, again: the release has `WORD(n.Parameter) SHL 2` in both and
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
  142f:057c..0583 -- EIGHT DO-NOTHING TICK ROUTINES, one byte each.

  `C3 C3 C3 C3 C3 C3 C3 C3` -- eight bare near returns in a row, so eight
  parameterless `assembler` procedures with empty bodies. The release has SEVEN
  consecutive empties here (`TickFPortUpDown`, `TickGlissCtrl`, `TickVibCtrl`,
  `TickFineTune`, `TickJumpLoop`, `TickTremCtrl`, `TickNPI2`) and 1.31 has eight, so
  one of them has no counterpart in 1.39b at all -- or 1.39b merged two. Which is
  not answerable from eight identical bodies.

  ADDRESS NAMES, AND FOR THE SAME REASON AS BEFORE: an empty body cannot confirm a
  pairing. That is now eleven one-byte routines in this SEGMENT waiting on the
  DISPATCH TABLE at 142f:063f, which maps command numbers to addresses and is the
  only thing that can name any of them. Doing that is the natural end of this
  SEGMENT rather than a chore -- the table settles eleven names at once.
  -------------------------------------------------------------------------- }
procedure TickFPortUpDown; assembler;
asm
end;

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

procedure TickRetrigNote; assembler;
asm
end;

{ --------------------------------------------------------------------------
  142f:0584 and 142f:05cd -- commands EAx and EBx, FINE VOLUME SLIDE up and down.
  The same borrow-the-coarse-routine trick StartVolSlide uses: set the increment,
  clear the fine flag so TickVolSlide will act, call it once, set the flag again.

  AND THEY ARE WHY 1.31 HAS NO RETRIGGER, WHICH SETTLES THE TAIL OF `TCanal`.
  The release's order here is `StartRetrigNote`, `TickRetrigNote`, then these two.
  1.31 goes straight to these two -- 0584 is a fine volume slide, not a retrigger --
  so the retrigger command is absent from this version altogether. That is what
  frees `+$24` and `+$25`: the release keeps `RetrigCt` and `RetrigVal` there, and
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
  142f:0619 -- fine volume slide, per tick, and it is one instruction: fall into
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
  142f:061d..0621 -- FIVE MORE DO-NOTHING TICKS, one byte each, and this time the
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

procedure TickNoteDelay; assembler;
asm
end;

procedure TickPattDelay; assembler;
asm
end;

procedure TickFunkIt; assembler;
asm
end;

procedure TickNone; assembler;
asm
end;

{ --------------------------------------------------------------------------
  142f:0622 -- A DEMOVT-ONLY COMMAND, and the one routine in this SEGMENT with no
  counterpart in the release at all.

  It stores the parameter into `Can.RingChan` and 1 into `Can.RingNote`, and 12ba
  does the rest: 12ba:0a58..0a8d copies both into `NoteRing[EventSlot, chan]` and
  then clears `RingNote` again, and 12ba:0187 tallies the ring into the control
  block the INT 2Fh interface publishes. So `RingNote` is "an event is waiting" and
  `RingChan` is its payload -- **this is how a tune signals the demo**, which is the
  one thing a demo player needs that a tracker does not. `VangeliSTracker/LIB` has
  nothing like it, and it is the clearest single piece of evidence that DemoVT is a
  purpose-built fork rather than a subset build.

  IT IS NOT `StartRetrigNote`, which is what its position suggests. The release's
  StartRetrigNote has ONE conditional store (`IF n.Parameter <> 0 THEN
  can.retrigval := n.Parameter`); this has two unconditional ones. And the release's
  TickRetrigNote needs three fields where 1.31's record has two. The dispatch table
  settles it independently: index 26, mcRetrigNote, points at a do-nothing tick.

  AND THE COMMAND IT IMPLEMENTS IS `mcNPI1` -- PROTRACKER'S EFFECT 8, THE ONE THAT
  DOES NOTHING. CommandStart's case arm at 142f:06dc calls this routine for command
  9... no: for command 9 in our numbering, which is `mcNPI1`, whose release comment
  reads "8 xx  Do Nothing (as far as I know)". The release has NO Start routine for
  it at all -- it is absent from 1.39b's case -- and its tick is one of the empty
  ones.

  SO DEMOVT STOLE THE NO-OP EFFECT, which is the obvious choice and a genuinely neat
  one: `8xx` is the one ProTracker command a composer can write with no audible
  consequence, so it costs nothing to repurpose and any tracker can author it. That
  is the whole music-to-demo synchronisation channel, and it is why this routine has
  no counterpart anywhere in the release.

  ITS CASE ARM IS ALSO LAST IN THE CHAIN. The other sixteen arms run in the release's
  own order; this one is appended after them, which is what an arm ADDED to an
  existing `case` looks like. Named `StartRingEvent` for its role, matching the
  `RingChan`/`RingNote` fields it writes -- the release's `mcNPI1` supplies the
  command's name but would be a terrible name for a routine that does something.
  -------------------------------------------------------------------------- }
procedure StartRingEvent(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  Can.RingChan := N.Parameter;                     { 0625..0632              }
  Can.RingNote := 1                                { 0633..063a              }
end;

{ --------------------------------------------------------------------------
  THE DISPATCH TABLE, DS:$0370 -- 36 words, one per command, holding the OFFSET of
  that command's tick routine. This is the table that named seventeen routines.

  IT IS THE ONLY THING THAT COULD HAVE NAMED THEM. Seventeen of this unit's routines
  are one-byte `RET`s, and an empty body cannot confirm a pairing -- every empty
  routine matches every other one, so source position was all there was and position
  is not confirmation. The table's INDEX is the command number, so reading it against
  the release's `TickCommOfs` at the same index gives each one its name from the
  binary rather than from an assumption.

  AND THE SIGNATURE IS STRONGER THAN SEVENTEEN SEPARATE MATCHES. Two entries are
  DOUBLED in the release -- 18 and 19 both point at TickFPortUpDown, 27 and 28 both
  at TickVolFineUpDn, because E1x/E2x and EAx/EBx share a tick -- and 1.31's table
  doubles at exactly those four indices, on exactly those two addresses. Five
  entries point at TickNone where a command has no tick at all (12..16, the ones
  whose work is all done at row start), and those five land on the same indices too.

  WHAT 1.31 DOES NOT HAVE: indices 33 and 34, the two Oktalizer arpeggios, point at
  TickNone where the release points at TickArpeggio and TickArpeggio2. The slots
  exist and the feature does not. And there is no index 35 command at all -- the
  release's `mcS3mRetrigNote` -- which is why `mcLast` is 35 here and 36 there.

  Index 35 is the `mcLast` slot itself and is unreachable: 063f's guard admits
  indices 0..34. The release's table has the same dead final entry.
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

    Ofs(TickNone),          { Okt   the release has TickArpeggio here     }
    Ofs(TickNone),          { Okt   ... and TickArpeggio2 here            }

    Ofs(TickNone)           { mcLast -- unreachable, the guard stops at 34 }
  );

{ --------------------------------------------------------------------------
  142f:063f -- CommandTick. Five instructions: range-check the command, index the
  table, and call through it. SI already points at the channel and BX holds the
  command number DOUBLED, both set up by the caller at 12ba:0d75.

  `CMP BX,46h` IS `mcLast * 2` and it is where mcLast comes from. Turbo Pascal
  emits the sign-extended byte form because 70 fits; `ADD BX,OFFSET TickCommOfs`
  cannot, because a relocatable offset needs sixteen bits, so that one is the long
  form. Two immediates, two encodings, and both are forced.

  `RETF` AT 064a IS THE COMPILER'S EPILOGUE and is why this must be declared `far`:
  the interface publishes it and 12ba calls it far.

  THE RELEASE HAS ONE MORE INSTRUCTION -- `MOV TCanal([SI]).doretrig,0` between the
  guard and the table lookup. 1.31 has no `doretrig` field, so it has no line.
  -------------------------------------------------------------------------- }
procedure CommandTick; assembler;
asm
        CMP     BX,mcLast * 2            { 063f                                }
        JNC     @@1                      { 0642                                }
        ADD     BX,OFFSET TickCommOfs    { 0644                                }
        CALL    WORD PTR [BX]            { 0648                                }
@@1:
end;

{ --------------------------------------------------------------------------
  142f:064b -- CommandStart. The row-start half of the unit: fold the new note into
  the channel, then dispatch to whichever Start routine the command wants. 565
  bytes, the largest routine in the SEGMENT, and almost all of it is the `case`.

  FAR, and the frame says so: `RETF 0C` at 087c, with the parameters at [BP+06]
  upward rather than [BP+04] as every other routine in this unit has them. The
  interface publishes this one and 12ba:0a38 calls it far.

  THE FIRST TEST IS THE ONE PIECE OF REAL LOGIC. `Can.Period := Can.Note.Period`
  runs when the OLD command was an arpeggio, or when it was a vibrato and the NEW
  one is not -- both of which are effects that leave `Period` displaced from the
  note. Restoring it is how the channel recovers its true pitch when the effect
  stops. Read the jump targets to see the grouping: 0656 goes forward to the
  assignment, 0660 goes to the pair of `N.Command` tests, and 066a/0674/067e all
  land past the assignment, which is `A or (B and C)` and not `(A or B) and C`.

  WHAT THE RELEASE HAS HERE AND 1.31 DOES NOT: a retrigger-counter reset, a
  `can.SOffs := FALSE`, and a block that copies `PeriodDest` into the period when a
  note portamento ends. All three touch fields 1.31's TCanal does not have, and all
  three are simply absent -- 068d runs straight into the `N.Period` test.

  THE CASE ARMS ARE THE RELEASE'S ORDER, minus five commands and plus one. Gone:
  `mcSampleOffs`, `mcRetrigNote`, `mcOktArp`, `mcOktArp2`, `mcS3mRetrigNote` -- the
  two Oktalizer and one S3M commands this version predates, and two whose TCanal
  fields do not exist. Added, and last in the chain: `mcNPI1`, which is
  StartRingEvent. Eighteen command values are handled and the other seventeen fall
  through the `case` doing nothing.

  AND THE LAST STATEMENT IS NOT THE SAME AS THE FIRST. `Can.Period := N.Period`
  under `(N.Period <> 0) and (N.Command <> mcNPortamento)` sets the working period
  from the new note -- except for a note portamento, which must slide from where it
  is rather than jump. That exception is the whole reason the statement is guarded.
  -------------------------------------------------------------------------- }
procedure CommandStart(var Song : TSong; var Can : TCanal; var N : TFullNote);
begin
  { 064e..068d -- an effect that displaced the period has ended; put it back. }
  if (Can.Note.Command = mcArpeggio) or
     (((Can.Note.Command = mcVibrato) or
       (Can.Note.Command = mcVib_VSlide)) and
      ((N.Command <> mcVibrato) and
       (N.Command <> mcVib_VSlide))) then          { 064e..067f              }
    Can.Period := Can.Note.Period;                 { 0680..068d              }

  if N.Period <> 0 then                            { 068e..0697              }
    Can.Note.Period := N.Period;                   { 0698..06a5              }

  Can.Note.Command   := N.Command;                 { 06a6..06b3              }
  Can.Note.Parameter := N.Parameter;               { 06b4..06c1              }

  case N.Command of                                { 06c2..0858              }
    mcArpeggio:      StartArpeggio(Song, Can, N);
    mcTPortUp:       StartTPortUp(Song, Can, N);
    mcTPortDown:     StartTPortDown(Song, Can, N);
    mcNPortamento:   StartNPortamento(Song, Can, N);
    mcVibrato:       StartVibrato(Song, Can, N);
    mcJumpPattern:   StartJumpPattern(Song, Can, N);
    mcT_VSlide,
    mcVib_VSlide,
    mcVolSlide:      StartVolSlide(Song, Can, N);
    mcSetVolume:     StartSetVolume(Song, Can, N);
    mcEndPattern:    StartEndPattern(Song, Can, N);
    mcSetTempo:      StartSetTempo(Song, Can, N);
    mcSetFilter:     StartSetFilter(Song, Can, N);
    mcVolFineUp:     StartVolFineUp(Song, Can, N);
    mcVolFineDown:   StartVolFineDown(Song, Can, N);
    mcFinePortaUp:   StartFinePortaUp(Song, Can, N);
    mcFinePortaDn:   StartFinePortaDown(Song, Can, N);
    mcNPI1:          StartRingEvent(Song, Can, N);
  end;

  { 0859..087a -- and take the new note's pitch, unless a note portamento is meant
    to slide to it from wherever the channel already is. }
  if (N.Period <> 0) and (N.Command <> mcNPortamento) then   { 0859..086c      }
    Can.Period := N.Period                         { 086d..087a              }
end;

end.
