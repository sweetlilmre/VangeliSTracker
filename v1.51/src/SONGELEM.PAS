{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Segment 165a -- THE SONG'S ELEMENTS. 3,216 bytes, FIFTEEN routines: an instrument, a
  track and a pattern, each an object with a constructor, a destructor and a
  FreeContents.

  COMPLETE. All 3,216 bytes, 207 pending fixups, written from the release's bodies
  verbatim in TWO builds. The first came back at 9% and the second was exact -- and the
  9% was a jump displacement, not a wrong instruction: everything downstream of it was
  already right and only the routine's total LENGTH was off.

  THREE THINGS HAD TO BE MEASURED, AND ALL THREE ARE IN `Change`:

      the `Repl <= 4` guard is absent          forty-two bytes 1.31 does not have
      eighty-three more bytes at the end       a second free, on a different flag
      DumpToUltrasound takes `var Src`         and `GUS.PAS` had it as a Pointer

  **THE LAST ONE CORRECTED A UNIT THAT WAS ALREADY BYTE-EXACT.** See the note at the
  DumpToUltrasound call.

  THE COUNTERPART IS `LIB/SONGELEM.PAS`, measured at 65.1% by `relmatch.py` --
  the highest-scoring untranscribed segment in the tree when this was started.

  **THE WHOLE STRUCTURE WAS READ WITHOUT DISASSEMBLING A SINGLE INSTRUCTION.**
  `survey.py 165a` reports fifteen far returns, no printable strings, ten far-call
  targets and twenty-two virtual call sites, and between them they identify every routine,
  name the five the release has and 1.31 does not, and confirm the field sizes.

  FIRST, THE FIFTEEN RETURNS. The stack-cleanup count is a signature, and a Turbo Pascal
  constructor and destructor each carry a hidden word beyond `Self`:

      0000 RETF 6   TInstrument.Init        081d RETF 6   TTrack.Init
      0023 RETF 6   TInstrument.Done        083f RETF 6   TTrack.Done
      005d RETF 4   TInstrument.FreeContents 0876 RETF 4  TTrack.FreeContents
      012a RETF 8   TInstrument.Change      08e2 RETF 8   TTrack.SetFullTrack
      037a RETF 4   TInstrument.Desample    0ab8 RETF 10  TTrack.GetNote
      0583 RETF 4   TInstrument.Resample    0baa RETF 8   TPattern.Init(Chans)
      07c0 RETF 8   TInstrument.SetName     0c1c RETF 6   TPattern.Done
                                            0c53 RETF 4   TPattern.FreeContents

  **AND THAT IS THE RELEASE'S IMPLEMENTATION ORDER EXACTLY, with five bodies removed.**
  Turbo Pascal lays routines out in source order, so the agreement is itself the check.

  THE FIVE ABSENT ROUTINES, and every one of them is an editor's, not a player's:

      TInstrument.GetName  |  TTrack.GetName  |  TPattern.GetName
          all three: no routine returns a String except SetName, and there is not one
          printable string in 3,216 bytes. A player never displays an instrument's name.

      TTrack.ChangeNote
          `0ab8` is `PUSH BP`, not `ENTER`. ChangeNote declares `Track : TFullTrack` --
          1,536 bytes of frame -- so it cannot be the frameless routine, and GetNote,
          which has no locals at all, must be. `RETF 10` fits both, so the FRAME is what
          separates them.

      TTrack.GetFullTrack
          its only caller in the release is ChangeNote, so dropping the note-writer drops
          the track-reader with it. No fourth `RETF 8` exists to hold it: the four are
          Change, SetName, SetFullTrack and TPattern.Init.

  SECOND, `ENTER $606` AT `08e2` IS AN EXACT ARITHMETIC MATCH and it is what identifies
  SetFullTrack rather than GetFullTrack:

      MNote : TNoteTrack   2 + 256 * SizeOf(TNoCommandNote) = 2 + 1024 = 1026
      MComm : TCommTrack   2 + 256 * SizeOf(TCommandNote)   = 2 +  512 =  514
      i     : WORD                                                          2
                                                             ---------------
                                                              1542 = $606

  GetFullTrack's frame would be `ENTER $002`. **Nothing about that reading needs a
  disassembler.** `ENTER $004` at `012a` is `Change`'s `l : LONGINT`, and `ENTER $00e` at
  both `037a` and `0583` is Desample's and Resample's identical three locals plus a `WITH`
  slot -- the pair share a frame size because they share a shape.

  THIRD, THE FAR CALLS COUNT THE ARITHMETIC. Two System helpers appear five times each
  and nowhere else in the segment:

      1ba1:0a2e  x5, all inside Desample   -- and Desample has exactly five LongInt DIVs
                                              (Len DIV 2 three times, Reps, Repl)
      1ba1:0a13  x5, all inside Resample   -- and Resample has exactly five LongInt MULs
                                              (Repl*3, Repl*2, Repl*3, Repl*4, Repl*4)
      1ba1:0fb2  x3 at 0177, 0a83, 0aaf    -- Move, and the release has exactly three:
                                              one in Change, two in SetFullTrack
      1ba1:0fd5  x4 at 08f1, 0901, 0ac7, 0c00
                                           -- FillChar: two in SetFullTrack, one in
                                              GetNote, one in TPattern.Init
      1723:0089  x2 at 023b, 02ca          -- DumpToUltrasound, and Change calls it twice
      1891:0000  x3  /  1891:0031  x3      -- TObject.Init and TObject.Done, three each

  **FIVE DIVS AND FIVE MULS, TERM FOR TERM, IS NOT A COINCIDENCE OF SIZE.** It says
  Desample's and Resample's expressions are the release's without a single one added or
  dropped, before a byte has been compared.

  FOURTH, THE TWENTY-TWO VIRTUAL SITES CONFIRM `HEAPS.PAS`'s VMT FROM OUTSIDE. They land
  on four slots only, and all four are what `17cf` independently says they are:

      [DI+08]  x5   HGetMem       Change 1, Resample 1, SetFullTrack 2, TPattern.Init 1
      [DI+0c]  x13  HFreeMem      see the note in Change -- ten are accounted for
      [DI+30]  x1   HNewStr       SetName
      [DI+34]  x3   HDisposeStr   SetName, TTrack.Done, TPattern.Done

  **THE THREE HDisposeStr SITES ARE THE SHARPEST OF THE LOT.** TTrack.Done and
  TPattern.Done each call it directly, and TInstrument.Done does NOT -- it calls
  `SetName('')` instead, and SetName is where the third site is. That asymmetry is in the
  release verbatim, and a transcription that tidied it would show up immediately.

  AND THE ONE COUNT THAT DID NOT AGREE WAS THE MOST VALUABLE OF THEM. Thirteen
  `HFreeMem` sites where the release's surviving bodies want ten, all three extra
  inside `Change` -- and they turned out to be a whole block the release has no trace
  of, guarded by a different global. **A count that does not add up is a finding, not
  noise.** See the note in Change.
  =========================================================================== }
unit SongElements;

interface

uses
  Objects, SoundDevices;

{ ---------------------------------------------------------------------------
  A NOTE IS FOUR FIELDS IN SIX BYTES, and the variant record is what lets a track store
  the pitch half and the command half in two separate arrays. `TNoCommandNote` is the
  three fields a note needs to sound; `TCommandNote` is the two an effect needs. Most
  notes have no effect, so most tracks store a long note array and a very short command
  one -- which is the entire reason for the split.
  --------------------------------------------------------------------------- }
type
  { **EVERY DESCRIPTION BELOW IS THE RELEASE'S**, from LIB/SONGELEM.PAS, kept in
    its own words -- including the ones where it says it does not know. The
    effect code in the first braces is ProTracker's, and it is what a composer
    types; the enumeration's ORDER is what this program dispatches on, and the
    two are not the same numbering.

    The honest gaps are worth keeping as gaps. Where the release did not know
    it did not know what the effect did, and nothing in this image says either --
    so the entry is marked unknown rather than filled in with a guess that would
    read like a finding. }
  TModCommand = (
    mcNone,           { 0 00 }  { just play the note, with no special option    }
    mcArpeggio,       { 0 xy }  { rotate through three notes rapidly            }
    mcTPortUp,        { 1 xx }  { tone portamento up: gradual change of tone    }
                                {   towards high frequencies                    }
    mcTPortDown,      { 2 xx }  { tone portamento down: towards low frequencies }
    mcNPortamento,    { 3 xy }  { note portamento: gradual change towards a
                                  given note                                    }
    mcVibrato,        { 4 xy }  { frequency changes around the note             }
    mcT_VSlide,       { 5 xy }  { tone portamento up + volume slide; the
                                  parameter means the volume slide              }
    mcVib_VSlide,     { 6 xy }  { vibrato + volume slide; likewise              }
    mcTremolo,        { 7 xy }  { "I don't know for sure. Fast volume
                                  variations, I think."                         }
    mcNPI1,           { 8 xx }  { "Do Nothing (as far as I know)" -- and DemoVT
                                  took this one for its semaphores. See
                                  ModCommands.StartRingEvent                     }
    mcSampleOffs,     { 9 xx }  { start the sample from the middle              }
    mcVolSlide,       { A xy }  { gradual change in volume                      }
    mcJumpPattern,    { B xx }  { end the pattern and continue from a different
                                  position in the sequence                      }
    mcSetVolume,      { C xx }  { set the volume of the sound                   }
    mcEndPattern,     { D xx }  { continue at the start of the next pattern     }
    mcExtended,       { E xy }  { the extended set of commands (ProTracker)     }
    mcSetTempo,       { F xx }  { set the tempo, in 1/50ths of a second         }

    mcSetFilter,      { E 0x }  { set the output filter to its on or off value  }
    mcFinePortaUp,    { E 1x }  { like TPortUp, but slower                      }
    mcFinePortaDn,    { E 2x }  { like TPortDown, but slower                    }
    mcGlissCtrl,      { E 3x }  { UNKNOWN -- the release did not know         }
    mcVibCtrl,        { E 4x }  { set the vibrato waveform                      }
    mcFineTune,       { E 5x }  { fine tune the frequency of the sound          }
    mcJumpLoop,       { E 6x }  { make a loop inside a pattern                  }
    mcTremCtrl,       { E 7x }  { "set the tremolo waveform (I think)"          }
    mcNPI2,           { E 8x }  { "Do Nothing (as far as I know)"               }
    mcRetrigNote,     { E 9x }  { UNKNOWN -- the release did not know         }
    mcVolFineUp,      { E Ax }  { like VolSlide, but slower and upward          }
    mcVolFineDown,    { E Bx }  { like VolSlide, but slower and downward        }
    mcNoteCut,        { E Cx }  { UNKNOWN -- the release did not know         }
    mcNoteDelay,      { E Dx }  { wait a little before starting the note        }
    mcPattDelay,      { E Ex }  { UNKNOWN -- the release did not know         }
    mcFunkIt,         { E Fx }  { "No idea, but sounds funny."                  }

    mcOktArp,                   { Oktalizer arpeggio                            }
    mcOktArp2,                  { Oktalizer arpeggio 2                          }
    mcS3mRetrigNote,            { no description in the release                 }
    mcLast
  );

{ **WHAT A NOTE'S FOUR FIELDS MEAN, IN THE RELEASE'S OWN WORDS.** None of this
  is recoverable from the image: a range, a unit and a sentinel are conventions
  the code obeys without ever stating them.

    Period      "A number in the range 0..2047 which states the period of the
                note in units of 1/3584000 per sample. (this is a somewhat
                empyric number. If anyone knows the exact Amiga number, please,
                tell us). A zero means to keep using the same period used
                before."

    Instrument  "A number in range 0..63 meaning the number of the instrument
                which will be used for the note. A zero means use the same."

    Command     "A number (no real range) of the way the note should be played
                (i.e. Vibrato) a change in the playing sequence (i.e. pattern
                break) or a change in the general parameters of the module
                player (i.e. set tempo). All the possible values are defined in
                the TModCommand enumerated type" above.

    Parameter   "A parameter for the command. Its meaning differs from one
                command to another. Sometimes each nibble is considered as a
                different parameter."

  TWO ZEROES THAT MEAN "UNCHANGED" ARE THE PART WORTH HAVING. A zero period and
  a zero instrument are not silence and not instrument zero -- they say to carry
  the previous value forward, which is why a pattern can be mostly empty and
  still play. An implementation that treated either as a value would sound wrong
  in a way no byte comparison could ever show.

  AND THE PERIOD UNIT IS ADMITTED TO BE APPROXIMATE. The author says so and asks
  for the exact Amiga figure. It is preserved as written rather than corrected,
  because this program's timing derives from the number it actually used. }

  PNoCommandNote = ^TNoCommandNote;
  TNoCommandNote = record
    Instrument : Byte;
    Period     : Word;
    Volume     : Byte;
  end;

  PCommandNote = ^TCommandNote;
  TCommandNote = record
    Command    : TModCommand;
    Parameter  : Byte;
  end;

  PFullNote = ^TFullNote;
  TFullNote = record
    case Byte of
      0 : ( Instrument : Byte;
            Period     : Word;
            Volume     : Byte;
            Command    : TModCommand;
            Parameter  : Byte        );
      1 : ( Note : TNoCommandNote;
            Comm : TCommandNote      );
  end;


{ ---------------------------------------------------------------------------
  AN INSTRUMENT IS A SAMPLE PLUS A LOOP. `Len`, `Reps` and `Repl` are LongInt because a
  sample can exceed 64K, and `Data`/`Xtra` is how a sample longer than 65,520 bytes is
  held: the first 65,520 in one block and the rest in a second. `MaxSample` is 65,520
  rather than 65,536 because a Turbo Pascal heap block cannot be a whole segment.
  --------------------------------------------------------------------------- }
const
  MaxSample      = 65520;
  MaxInstruments = 255;

  { A TYPED CONSTANT, so it is a variable in all but name and the configurator can turn
    it off. When set, every instrument is halved and then quadrupled on load -- see
    Desample and Resample. }
  LowQuality : Boolean = True;

  { [1.39b] "Set if the instrument is played always at the same freq (not
    implemented)." -- so this bit is defined and does nothing, in the release and
    here. }
  ipMonoFreq = $0001;
  { [1.39b] "Set if the instrument's sample is longer than 65520 bytes." }
  ipLong     = $0002;

type
  PSample = ^TSample;
  TSample = array[0..MaxSample - 1] of ShortInt;

  TIProperties = Word;

{ [1.39b] "Instruments are fragments of sampled sound (long arrays of bytes
  which describe the wave of the sound of the instrument). The samples used in
  music modules have a default volume and also, they can have a loop (for
  sustained instruments) and a fine tuning constant (not yet implemented)."

  Every field description below is the release's. Two of them say a thing the
  image cannot: `Ftune` is NOT IMPLEMENTED, and `Vol`'s range is 0..64 -- a
  ceiling of 64 rather than 63 or 255, which is what makes S3M's 0..64 clamp at
  $40 the same scale rather than a coincidence. }
  PInstrumentRec = ^TInstrumentRec;
  TInstrumentRec =
    record
      Len,          { [1.39b] length of the instrument's sampled image      }
      Reps,         { [1.39b] starting offset of the repeated portion       }
      Repl  : LongInt;  { [1.39b] size of the repeated portion              }
      Vol   : Byte;     { [1.39b] default volume of the instrument (0..64)  }
      Ftune : Byte;     { [1.39b] fine tuning value -- NOT YET IMPLEMENTED  }
      NAdj  : Word;     { [1.39b] numerator of the note adjustment          }
      DAdj  : Word;     { [1.39b] denominator of the note adjustment        }
      Data  : ^TSample; { [1.39b] pointer to the first 65520 bytes          }
      Xtra  : ^TSample; { [1.39b] pointer to the second 65520 bytes, if any }
      Prop  : TIProperties;  { [1.39b] bit mapped properties value          }
    end;

  PInstrument = ^TInstrument;
  TInstrument =
    object(TObject)
      Name  : PString;
      Instr : PInstrumentRec;

      constructor Init;
      destructor  Done; virtual;

      procedure FreeContents;
      procedure Desample;
      procedure Resample;

      procedure Change(Instrument : PInstrumentRec);
      procedure SetName(S : String);
    end;


{ ---------------------------------------------------------------------------
  A TRACK IS ONE CHANNEL'S COLUMN OF NOTES, stored with the leading and trailing blanks
  removed -- `NoteOffset` is where the first real note sits and `NumNotes` is how many
  follow. A track whose notes run from line 12 to line 20 costs nine notes, not 256.

  THE RELEASE SAYS THE SAME THING INDEPENDENTLY: "[1.39b] Tracks are lists of
  notes and command values of which the empty leading and trailing blanks have
  been removed (obviated)." That was worked out here from `NoteOffset` and
  `NumNotes` before the release's own words were read, and the two agree.

  THE TWO ARRAYS ARE DECLARED AT FULL LENGTH AND ALLOCATED SHORT. `TNoteTrack` says
  `array[0..255]` but `TTrack.FreeContents` frees `NumNotes * SizeOf(TNoCommandNote) + 2`
  -- the declared type is a window onto a block sized to fit. That is why every allocation
  in this unit computes its own length rather than using SizeOf.
  --------------------------------------------------------------------------- }
type
  PNoteTrack = ^TNoteTrack;
  TNoteTrack =
    record
      NoteOffset : Byte;
      NumNotes   : Byte;
      Notes      : array[0..255] of TNoCommandNote;
    end;

  PCommTrack = ^TCommTrack;
  TCommTrack =
    record
      NoteOffset : Byte;
      NumNotes   : Byte;
      Notes      : array[0..255] of TCommandNote;
    end;

  PFullTrack = ^TFullTrack;
  TFullTrack = array[0..255] of TFullNote;

  PTrack = ^TTrack;
  TTrack =
    object(TObject)
      Name : PString;
      Note : PNoteTrack;
      Comm : PCommTrack;

      constructor Init;
      destructor  Done; virtual;

      procedure FreeContents;

      procedure SetFullTrack(var Track : TFullTrack);
      procedure GetNote(At : Word; var FullNote : TFullNote);
    end;


{ ---------------------------------------------------------------------------
  A PATTERN IS A LIST OF TRACK NUMBERS, one per channel, and `Channels` is declared at
  MaxChannels but allocated at `Chans * 2 + 4` -- the same window-onto-a-short-block
  pattern as the track arrays.

  `MaxChannels` IS 8 HERE AND 32 IN THE RELEASE. The release takes it from
  `SoundDevices.MaxChannels`; 1.31's value is 8, measured in `12ba` three separate ways
  (see PLAYMOD.PAS). **It reaches no instruction in this segment** -- TPattern.Init and
  FreeContents both compute their block size from `Chans` and `Patt^.NChans`, and nothing
  here takes SizeOf(TPatternRec) -- so the figure is documentation, not a measurement.

  **AND THE RELEASE'S OWN PROSE DISAGREES WITH THE RELEASE'S OWN CONSTANT.** Its
  section header reads "[1.39b] Patterns are arrays of pointers to tracks (up to
  12 tracks). A music module can have up to 255 individual patterns, arranged in
  a sequence of up to 255." Twelve is not 32, which is what its `MaxChannels`
  actually holds, and 255 is not 256, which is what its `MaxPatterns` and
  `MaxSequence` hold.

  So there are three figures in play and the prose is the odd one out. It is
  recorded here rather than repeated as fact, because it is a worked example of
  the rule this whole harvest runs under: **a comment is a candidate, not a
  measurement -- including in the source it came from.** Twelve was probably true
  when the sentence was written and the constant grew past it afterwards, which
  is exactly how the addresses in this reconstruction's own comments went stale.
  --------------------------------------------------------------------------- }
const
  MaxSequence     = 256;
  MaxPatterns     = 256;
  MaxPatternLines = 256;
  MaxChannels     = 8;

type
  PPatternRec = ^TPatternRec;
  TPatternRec =
    record
      NNotes   : Byte;
      NChans   : Byte;
      Tempo    : Byte;
      BPM      : Byte;
      Channels : array[1..MaxChannels] of Word;
    end;

  PPattern = ^TPattern;
  TPattern =
    object(TObject)
      Name : PString;
      Patt : PPatternRec;

      constructor Init(Chans : Word);
      destructor  Done; virtual;

      procedure FreeContents;
    end;

  PPatternSequence = ^TPatternSequence;
  TPatternSequence = array[1..MaxSequence] of Byte;

  PSongComment = ^TSongComment;
  TSongComment = array[1..16] of String[60];



implementation

{ THE RELEASE ALSO USES `Debugging` AND `HexConversions`, and 1.31 uses neither -- see
  Change's note. `survey.py` finds far calls to three segments only: `1ba1` (System),
  `1891` (Objects) and `1723` (GUS). }
uses
  Heaps, GUS;


{ ===========================================================================
  TInstrument.
  =========================================================================== }

{ A TYPED CONSTANT USED AS A UNIT-LEVEL CURSOR: the next free byte of the GUS's own RAM.
  It is reset in the destructor rather than the constructor, which only works because one
  instrument is torn down before the next song loads. }
const
  GUSAddr : LongInt = 0;

{ 165a:0000 -- and the whole body is one inherited call. The thirty bytes are almost all
  the constructor's compiler-generated prologue: `1ba1:04f5` at `0005` sets the VMT up and
  arranges for a failed constructor to return False, which is also why the return is
  `RETF 6` and not `RETF 4`. }
constructor TInstrument.Init;
begin
  TObject.Init;
end;


{ 165a:0023 -- and `SetName('')` where TTrack.Done and TPattern.Done call HDisposeStr
  directly. That asymmetry is the release's and it is measurable: `survey.py` finds the
  three `[DI+34]` sites in SetName, TTrack.Done and TPattern.Done, and none in this
  routine. }
destructor TInstrument.Done;
begin
  GUSAddr := 0;
  SetName('');
  FreeContents;
  TObject.Done;
end;


{ ---------------------------------------------------------------------------
  165a:005d -- FreeContents, and its three `HFreeMem` calls are the segment's first three
  `[DI+0c]` sites, at `00ca`, `010e` and `0123`.

  `IF NOT UsingGUS` GUARDS THE SAMPLE BUT NOT THE RECORD. When the Gravis holds the
  sample, `Instr^.Data` is not a pointer at all -- Change overwrote it with a GUS RAM
  address -- so freeing it would hand the heap a number. The record itself is always ours,
  so its free is outside the guard.

  AND `Instr^.Len := 65520` AFTER FREEING `Xtra` is not tidying: the very next line frees
  `Data` for `Instr^.Len` bytes, and without the clamp it would ask for the whole sample's
  length from a 65,520-byte block.
  --------------------------------------------------------------------------- }
procedure TInstrument.FreeContents;
begin
  if Instr = nil then Exit;

  if not UsingGUS then
  begin
    if Instr^.Len > 65520 then
    begin
      if Instr^.Xtra <> nil then
        FullHeap.HFreeMem(Pointer(Instr^.Xtra), Instr^.Len - 65520);
      Instr^.Len := 65520;
    end;
    if Instr^.Data <> nil then
      FullHeap.HFreeMem(Pointer(Instr^.Data), Instr^.Len);
  end;

  FullHeap.HFreeMem(Pointer(Instr), SizeOf(Instr^));
end;


{ ---------------------------------------------------------------------------
  165a:012a -- Change. Adopt a caller's instrument record: copy it, sanitise it, halve and
  requadruple the sample if LowQuality is set, and hand it to the Gravis if there is one.

  `ENTER $004` IS `l : LONGINT` and it anchors the routine.

  **THE FIRST THING IT DOES IS FREE WHAT WAS THERE**, which is why `Change` is also how an
  instrument is emptied: `Change(NIL)` frees and stops.

  THE GUS BRANCH IS THE INTERESTING HALF. A sample is uploaded in at most two pieces
  because 65,520 bytes is the largest single transfer, and after each piece the
  conventional-memory copy is freed -- so on a Gravis the sample lives only in the card's
  RAM. `Instr^.Data` is then not a pointer but a GUS RAM offset, which is what
  FreeContents' `IF NOT UsingGUS` guard exists for. `survey.py` puts `DumpToUltrasound` at
  `023b` and `02ca`, exactly twice.

  **THIS SEGMENT IS WHAT FIXED `DumpToUltrasound`'s FIRST PARAMETER.** `GUS.PAS` had it
  as `Src : Pointer` and was byte-exact with it, because inside that routine a Pointer
  and an untyped `var` are the same four bytes and `LDS SI,Src` loads the same address
  from either. The CALL SITE tells them apart: `165a:02b0` reads
  `LES DI,ES:[DI+16] / PUSH ES / PUSH DI`, which is a var parameter, where a Pointer
  argument compiles to two word pushes and costs two bytes more. Changed to `var Src`,
  which is also the release's -- and `GUS` still verifies identical. **The same lesson
  `VTDOSRSZ` taught: a parameter list can be wrong for a unit's whole life while the
  unit itself measures perfect, and only a caller in another segment reveals it.**

  ONE COUNT DOES NOT AGREE AND IS NOT YET EXPLAINED. `survey.py` finds FIVE `[DI+0c]`
  sites inside this routine -- `0257`, `02e6`, `0333`, `0357`, `0373` -- where the
  release's body has two, both in the GUS branch. The first two line up with the
  DumpToUltrasound calls at `023b` and `02ca`; the last three sit after the GUS block and
  before the return, and three is exactly what FreeContents contains. **Do not guess at
  it -- build this and read where the prefix stops.**

  AND THE DIAGNOSTIC IS GONE. The release ends with `IF Debug THEN
  WriteLn(HexPtr(Instr^.Data))`; 1.31 has not one printable string in 3,216 bytes and no
  far call outside System, Objects and GUS, so neither `Debugging` nor `HexConversions` is
  linked. The same absence `17cf`'s HFreeMem has, found the same way.
  --------------------------------------------------------------------------- }
procedure TInstrument.Change(Instrument : PInstrumentRec);
var
  l : LongInt;
begin
  FreeContents;
  if Instrument <> nil then
  begin
    FullHeap.HGetMem(Pointer(Instr), SizeOf(Instr^));
    if Instr <> nil then
    begin
      Move(Instrument^, Instr^, SizeOf(Instr^));
      if Instr^.Vol > 63 then
        Instr^.Vol := 63;
      if Instr^.NAdj = 0 then
      begin
        Instr^.NAdj := $2000;
        Instr^.DAdj := $2000;
      end;
      { `IF Instr^.Repl <= 4 THEN Instr^.Repl := 0` IS ABSENT FROM 1.31, and its forty-two
        bytes were the whole of our overshoot: at `165a:01be` the original goes straight
        from the NAdj default to the `LowQuality` test, with no LongInt compare of the
        field at +8 in between.

        **AND IT CHANGES WHICH OF Desample/Resample RUNS.** Desample wants
        `(Repl >= 2000) OR (Repl = 0)` and Resample wants `Repl > 0`, so a loop of three
        or four bytes falls between them: the release normalises it to zero first and
        lets Desample halve the sample, while 1.31 leaves it alone and Resample writes
        the three-byte loop out four times over. The release added a guard; 1.31 has the
        rougher behaviour. }
      if LowQuality then
      begin
        Desample;
        Resample;
      end;

      { `l := Instr^.Len` SITS OUTSIDE THE TEST, at 165a:01d7, where the release has it
        inside. That is what lets the second free block below reuse `l` when the GUS
        block did not run -- the one restructuring 1.31 made here. }
      l := Instr^.Len;
      if UsingGUS and (Instr^.Data <> nil) then
      begin
        if l > 65520 then
          l := 65520;
        DumpToUltrasound(Instr^.Data^, l, GUSAddr, 1);
        FullHeap.HFreeMem(Pointer(Instr^.Data), l);
        Instr^.Data := Pointer(GUSAddr);
        Inc(GUSAddr, l);
        if l <> Instr^.Len then
        begin
          l := Instr^.Len - l;
          DumpToUltrasound(Instr^.Xtra^, l, GUSAddr, 1);
          FullHeap.HFreeMem(Pointer(Instr^.Xtra), l);
          Inc(GUSAddr, l);
        end;
      end;

      { ------------------------------------------------------------------
        165a:02f7..0375 -- EIGHTY-THREE BYTES THE RELEASE DOES NOT HAVE, and the
        second free of the same sample.

        It is a second copy of the sample-freeing half of FreeContents, guarded by a
        DIFFERENT global from the block above: `02f7` tests `DS:$0bc7` where `01eb`
        tests `DS:$0bce`. `1084:007f` -- DEVGUS -- writes 1 to `$0bce`, so **that one
        is `UsingGUS`** and the release's block above is correctly identified. `$0bc7`
        is the flag `12ba` tests twice at `0b5c` and `0c52`, which is where our name
        `IsDmaDevice` comes from.

        **THE SEMANTICS ARE SURPRISING AND THE NAME IS PROBABLY WRONG.** `IsDmaDevice`
        is OURS, not the release's -- no such identifier exists in 1.39b -- and it was
        guessed from `12ba` alone. Put the three uses together:

            12ba:0b5c   if NOT <flag> then <do the per-tick software mixing>
            12ba:0c52   if <flag> and (TickSnapshot = Ticks) then ...
            165a:02f7   if <flag> and (Instr^.Data <> nil) then <free the sample>

        A device that needs neither software mixing NOR the sample in main memory is a
        device that plays from its own RAM. **That reads far more like "the hardware
        holds the samples" than like "DMA"**, and a DMA device freeing the sample it is
        about to mix from would be nonsense. The name should probably change; it is
        left alone here because changing it touches two byte-exact units and wants its
        own pass.

        AND IT CAN FREE A POINTER THAT IS NOT ONE. If the `UsingGUS` block above ran,
        `Instr^.Data` was freed and then overwritten with `Pointer(GUSAddr)` -- a GUS
        RAM offset -- so this block would hand the heap a number. Either the two flags
        are mutually exclusive in every configuration that ships, or this is a live
        bug. Transcribed as found either way: the binary decides.

        `l` IS STILL `Instr^.Len` WHEN THE GUS BLOCK DID NOT RUN, because `01d7` assigns
        it before the first test rather than inside it -- which is the one restructuring
        1.31 made to the release's body, and it is what lets this block reuse `l`.
        ------------------------------------------------------------------ }
      if IsDmaDevice and (Instr^.Data <> nil) then
        if l > 65520 then
        begin
          FullHeap.HFreeMem(Pointer(Instr^.Data), 65520);
          FullHeap.HFreeMem(Pointer(Instr^.Xtra), l - 65520);
        end
        else
          FullHeap.HFreeMem(Pointer(Instr^.Data), l);
    end;
  end;
end;


{ ---------------------------------------------------------------------------
  165a:037a -- Desample. Halve a sample's rate in place, then give the freed half back.

  **THIS IS A DESTRUCTIVE OPTIMISATION AND `LowQuality` IS ITS SWITCH.** Averaging pairs
  of samples halves the memory a module needs and costs an octave of top end, which on a
  1993 PC speaker or a 22kHz Sound Blaster was a trade worth making. `Change` calls
  Desample and Resample back to back, so a short looped sample loses half its rate and
  then gets four copies of its loop -- see Resample.

  IT AVERAGES IN PLACE AND FORWARDS, reading `Data^[w*2]` and `Data^[w*2+1]` while writing
  `Data^[w]`. The write index is always behind both reads, so nothing is clobbered before
  it is used, and no second buffer is needed.

  **THE `WITH Instr^` HEADER DEREFERENCES `Instr` BEFORE THE NIL TEST INSIDE IT.** That is
  the release's, transcribed as found. `WITH` evaluates its record reference on entry, so
  by the time `(Instr <> NIL)` is examined the pointer has already been followed. It never
  bites because every caller is `Change`, which has just tested it -- but it is a live nil
  dereference and it is being kept because the binary decides.

  THE POINTER ARITHMETIC IS THE FIDDLY PART. `p` is walked to the first byte past the
  halved sample, then normalised so the offset is small enough to subtract from
  `Data`'s -- the `SHR 4` folds the offset into the segment and `AND $8` keeps what is
  left. `SizeFree` is then the gap in bytes, computed segment-part and offset-part
  separately because a LongInt subtraction of two far pointers is not what is wanted.

  **FIVE LONGINT DIVISIONS, AND `survey.py` COUNTS FIVE.** `Len DIV 2 - 1`,
  `Len DIV 2 + 7`, `Len DIV 2`, `Reps DIV 2`, `Repl DIV 2` -- all five calls to
  `1ba1:0a2e` fall inside this routine and nowhere else in the segment. Term for term.
  --------------------------------------------------------------------------- }
procedure TInstrument.Desample;
var
  w        : Word;
  p        : Pointer;
  SizeFree : Word;
begin
  with Instr^ do
    if (Instr <> nil) and (Instr^.Data <> nil)        and
       (Len > 128) and ((Repl >= 2000) or (Repl = 0)) then
    begin
      for w := 0 to Len div 2 - 1 do
        Data^[w] := (Integer(Data^[w * 2]) +
                     Integer(Data^[w * 2 + 1])) div 2;

      p := Ptr(Seg(Data^), Ofs(Data^) + Len div 2 + 7);
      p := Ptr(Seg(p^) + (Ofs(p^) shr 4), Ofs(p^) and $8);

      SizeFree := Len -
                  (Word((Seg(p^) - Seg(Data^)) shl 4) +
                   Word( Ofs(p^) - Ofs(Data^))        );

      FullHeap.HFreeMem(p, SizeFree);

      Len  := Len  div 2;
      Reps := Reps div 2;
      Repl := Repl div 2;
      NAdj := NAdj  *  2;
    end;
end;


{ ---------------------------------------------------------------------------
  165a:0583 -- Resample. The opposite trade: spend memory to make a very short looped
  sample cheaper to play.

  `Len < 128` AND `Repl > 0` IS THE WHOLE CONDITION, and it is deliberately the mirror of
  Desample's `Len > 128`, so exactly one of the pair can act on any instrument. A sample
  under 128 bytes with a loop is a buzz or a bass note, and playing it means restarting the
  loop hundreds of times a second. **Writing the loop out four times over turns four
  restarts into one**, which on a Gravis matters more than the memory: the card's voice
  hardware handles a long loop for free.

  THE COPY IS TWO PASSES, NOT ONE. The first carries `Reps + Repl` bytes across -- the
  lead-in plus one copy of the loop -- and the second appends three more copies of the loop
  alone, striding by `Repl` each time. `Len` ends as `Reps + Repl*4` and `Repl` as
  `Repl*4`, so the loop points still describe the same sound.

  **BUT IT ALLOCATES `Reps + Repl*3` AND WRITES UP TO `Reps + Repl*4`.** That is the
  release's arithmetic, transcribed as found: the second pass' `p^[w + Repl*3]` reaches
  `Reps + Repl*4 - 1`, which is `Repl` bytes past the block. It survives because Turbo
  Pascal's heap rounds an allocation up to eight bytes and because `Repl` is small in every
  instrument that gets here -- but it is a real overrun and it is not being quietly fixed.

  **FIVE LONGINT MULTIPLICATIONS, AND `survey.py` COUNTS FIVE.** `Repl*3`, `Repl*2`,
  `Repl*3`, `Repl*4`, `Repl*4` -- all five calls to `1ba1:0a13` are in this routine and
  nowhere else. The same term-for-term agreement Desample's divisions give, and between
  them the two routines are pinned before a byte is compared.
  --------------------------------------------------------------------------- }
procedure TInstrument.Resample;
var
  w        : Word;
  p        : ^TSample;
  SizeFree : Word;
begin
  with Instr^ do
    if (Instr <> nil) and (Instr^.Data <> nil) and
       (Len < 128) and (Repl > 0)              then
    begin
      FullHeap.HGetMem(Pointer(p), Reps + Repl * 3);
      for w := 0 to Reps + Repl - 1 do
        p^[w] := Data^[w];

      for w := Reps to Reps + Repl - 1 do
      begin
        p^[w + Repl    ] := Data^[w];
        p^[w + Repl * 2] := Data^[w];
        p^[w + Repl * 3] := Data^[w];
      end;

      FullHeap.HFreeMem(Pointer(Data), Len);
      Data := Pointer(p);

      Len  := Reps + Repl * 4;
      Repl := Repl * 4;
    end;
end;


{ 165a:07c0 -- SetName, and `ENTER $100` is the 256-byte copy a value `String` parameter
  costs. It holds both string sites: `HDisposeStr` at `07f4` and `HNewStr` at `080b`.

  NOTE THE ASYMMETRY: the old name is always disposed, the new one only stored if it is
  non-empty -- so `SetName('')` frees and leaves `Name` nil, which is exactly how
  TInstrument.Done uses it. }
procedure TInstrument.SetName(S : String);
begin
  if Name <> nil then
    FullHeap.HDisposeStr(Name);

  if S <> '' then
    Name := FullHeap.HNewStr(S);
end;


{ ===========================================================================
  TTrack.
  =========================================================================== }

{ 165a:081d and 165a:083f. Unlike TInstrument.Done this one calls `HDisposeStr` directly
  -- site `0852` -- and does not guard against a nil `Name`, because HDisposeStr does. }
constructor TTrack.Init;
begin
  TObject.Init;
end;


destructor TTrack.Done;
begin
  FullHeap.HDisposeStr(Name);
  FreeContents;
  TObject.Done;
end;


{ 165a:0876 -- and the two block lengths are recomputed from `NumNotes` rather than
  remembered, which is the price of the window-onto-a-short-block scheme. `+ 2` is the
  `NoteOffset` and `NumNotes` bytes ahead of each array. }
procedure TTrack.FreeContents;
begin
  if Note <> nil then
    FullHeap.HFreeMem(Pointer(Note), Note^.NumNotes * SizeOf(TNoCommandNote) + 2);
  if Comm <> nil then
    FullHeap.HFreeMem(Pointer(Comm), Comm^.NumNotes * SizeOf(TCommandNote)   + 2);
end;


{ ---------------------------------------------------------------------------
  165a:08e2 -- SetFullTrack. Take 256 full notes and compress them into the two short
  arrays, discarding the blank lead-in and anything past the last real note.

  `ENTER $606` IS THE ROUTINE'S FINGERPRINT: `MNote` 1026 + `MComm` 514 + `i` 2 = 1542.
  It builds both arrays at full size on the stack and then allocates blocks to fit --
  1.5K of frame, which is why the segment's largest routine is this one.

  **THE TWO PASSES ARE INDEPENDENT AND THAT IS THE POINT.** A note with no effect advances
  `MNote` and leaves `MComm` alone, so the command array can start much later and end much
  earlier than the note array. The `IF MNote.NoteOffset = i THEN INC(...)` idiom is how the
  lead-in is skipped without a separate scan: while every line so far has been blank, the
  offset keeps pace with `i`; the first real note stops it for good.

  AND `NumNotes` IS RECOMPUTED ON EVERY REAL NOTE rather than counted, so it always ends
  as the distance from the offset to the LAST real note -- which is what makes the trailing
  blanks free too.

  `FreeContents` BETWEEN THE BUILD AND THE ALLOCATE is what makes this safe to call on a
  track that already has contents; the two `Move`s at `0a83` and `0aaf` are the segment's
  second and third.
  --------------------------------------------------------------------------- }
procedure TTrack.SetFullTrack(var Track : TFullTrack);
var
  i     : Word;
  MNote : TNoteTrack;
  MComm : TCommTrack;
begin
  FillChar(MNote, SizeOf(MNote), 0);
  FillChar(MComm, SizeOf(MComm), 0);
  for i := 0 to 255 do
  begin
    if (Track[i].Instrument = 0) and
       (Track[i].Period     = 0) and
       (Track[i].Volume     = 0) then
    begin
      if MNote.NoteOffset = i then
        Inc(MNote.NoteOffset);
    end
    else
    begin
      MNote.NumNotes := i - MNote.NoteOffset + 1;
      MNote.Notes[i - MNote.NoteOffset] := Track[i].Note;
    end;

    if Track[i].Command = mcNone then
    begin
      if MComm.NoteOffset = i then
        Inc(MComm.NoteOffset);
    end
    else
    begin
      MComm.NumNotes := i - MComm.NoteOffset + 1;
      MComm.Notes[i - MComm.NoteOffset] := Track[i].Comm;
    end;
  end;

  FreeContents;

  FullHeap.HGetMem(Pointer(Note), MNote.NumNotes * SizeOf(TNoCommandNote) + 2);
  FullHeap.HGetMem(Pointer(Comm), MComm.NumNotes * SizeOf(TCommandNote)   + 2);

  if Note <> nil then
    Move(MNote, Note^, MNote.NumNotes * SizeOf(TNoCommandNote) + 2);
  if Comm <> nil then
    Move(MComm, Comm^, MComm.NumNotes * SizeOf(TCommandNote)   + 2);
end;


{ ---------------------------------------------------------------------------
  165a:0ab8 -- GetNote. One line of one track, expanded back into a full note.

  **THIS IS THE ROUTINE WITH NO FRAME AT ALL** -- `PUSH BP` rather than `ENTER` -- which is
  how it is told apart from `ChangeNote`, whose `Track : TFullTrack` local would cost 1,536
  bytes. Both would return `RETF 10`, so the frame is the only discriminator, and it is
  decisive.

  `DEC(At)` FIRST, so callers count lines from one while the arrays count from zero. Every
  caller in `12ba` passes a 1-based line number.

  THE TWO LOOKUPS ARE SEPARATE AND EITHER CAN MISS, which is the compression scheme read
  backwards: a line inside the note array's range but outside the command array's gets its
  pitch filled in and its command left as the `FillChar` zeroed it -- and zero is `mcNone`.
  The `FillChar` at `0ac7` is therefore load-bearing, not hygiene.
  --------------------------------------------------------------------------- }
procedure TTrack.GetNote(At : Word; var FullNote : TFullNote);
begin
  Dec(At);
  FillChar(FullNote, SizeOf(FullNote), 0);

  if (Note <> nil) and (At >= Note^.NoteOffset) and
     (At < Note^.NoteOffset + Note^.NumNotes)   then
    FullNote.Note := Note^.Notes[At - Note^.NoteOffset];

  if (Comm <> nil) and (At >= Comm^.NoteOffset) and
     (At < Comm^.NoteOffset + Comm^.NumNotes)   then
    FullNote.Comm := Comm^.Notes[At - Comm^.NoteOffset];
end;


{ ===========================================================================
  TPattern.
  =========================================================================== }

{ 165a:0baa -- the only constructor here that takes a parameter, hence `RETF 8` where the
  other two are `RETF 6`. `Chans*2 + 4` is the four header bytes plus one word per
  channel; the declared `array[1..MaxChannels]` is never the size allocated.

  `Patt^.NChans := Chans` IS OUTSIDE THE NIL TEST, and that is the release's. If HGetMem
  fails, the FillChar is skipped and then this line writes through nil anyway. Transcribed
  as found. }
constructor TPattern.Init(Chans : Word);
begin
  TObject.Init;

  FullHeap.HGetMem(Pointer(Patt), Chans * 2 + 4);

  if Patt <> nil then
    FillChar(Patt^, Chans * 2 + 4, 0);
  Patt^.NChans := Chans;
end;


destructor TPattern.Done;
begin
  FullHeap.HDisposeStr(Name);
  FreeContents;
  TObject.Done;
end;


{ 165a:0c53 -- and the block's own `NChans` is what sizes the free, so the pattern
  remembers its width rather than the caller having to. }
procedure TPattern.FreeContents;
begin
  if Patt <> nil then
    FullHeap.HFreeMem(Pointer(Patt), Patt^.NChans * 2 + 4);
end;

end.
