{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Segment 14b9 -- THE MODULE OBJECT. **COMPLETE: 2,224 of 2,224 bytes.**
  Sixteen routines, 198 pending fixups, no real difference anywhere.

  This unit used to hold no code at all: it was the shared layout, declared once
  because the original has ONE FLAT DGROUP and one struct that eight different
  code segments index by absolute offset -- 154d and 164b while loading, 165a
  and 14b9 while building it, 12ba while playing. See docs/06-transcription.md,
  "one DGROUP, many units". It still is that, and it is now also the unit that
  owns segment 14b9.

  THE NAME CLASH IS WHY IT IS THIS FILE AND NOT `VTSONG.PAS`. The tree carried
  two files here and their names were crossed: `VTSONG.PAS` was a five-routine
  STUB standing in for segment 14b9, while this file carried the release's unit
  name and the record. The segment's counterpart in the release IS
  `LIB/SONGUNIT.PAS` -- one unit holding TSong and its twenty-one methods -- so
  the stub was folded in here and deleted. This file was already imported by
  PLAYMOD, UNKLOADE and VTCFG, three byte-exact units whose `uses` clauses would
  otherwise all have had to change.

  ONE DELIBERATE DEVIATION, AND IT IS DATA RATHER THAN CODE: `SongLoaders` is
  an uninitialised `var` where the original has a typed constant holding two
  procedure addresses. TP6 rejects the circular unit reference that would let it
  be written, and the table's contents are invisible to every measurement this
  project makes. It is flagged at the declaration and it is risk 1. Fill it in
  before anything is LINKED.

  EVERY NAMED FIELD BELOW WAS READ OFF AN INSTRUCTION. There is almost no filler
  left: `Free` and `InitValues` between them touch every field in the release's
  order, and their operands ARE the declaration. What remains unnamed is named
  by its offset rather than invented.

  THE TOTAL SIZE IS SETTLED AT $5e BYTES. This header used to say it was not,
  and that it was waiting on the constructor; `InitValues` is the routine it was
  really waiting on, and it initialises every field and touches nothing past
  +$5d.

  THE UNIT AND THE ENUMERATIONS CARRY THE RELEASE'S NAMES; THE LAYOUT CANNOT.
  LIB/SONGUNIT.PAS is the counterpart and it supplies the unit name, PSong,
  TSong, and every `ms`/`mff` constant below. It does NOT supply the field
  layout, and must not be used for it: its own history block records
  "06-Feb-1993 Remodelling. Made the memory-optimized, object-oriented
  interface", so 1.39b's TSong is a TObject descendant with a different shape.
  The layout is DATA, and data comes from the disassembly -- with ONE correction
  now measured: this paragraph used to add that the release's first two fields
  "would map onto 1.31's +$02 and +$04, which are written with 1 and $100 by a
  constructor -- a speed and a tempo, not a start and a length". They ARE
  SongStart and SongLen; MaxSequence is 256, which is $100. See the note at the
  fields. Where the layout really does not carry over is further down, and the
  fillers say so.

  One field name IS adopted, on role rather than position: +$5d holds the mff*
  value a recogniser stores, so it is the release's `FileFormat`.

  NAMES ARE PROVISIONAL in one respect regardless: Borland Pascal 6, no debug
  information, so nothing proves 1.31 spelled any of them this way.
  =========================================================================== }

unit SongUnit;

interface

uses

  { SongElements -- 165a, and the release's own layering: its SONGUNIT.PAS uses
    SongElem, not the other way round. GetInstrument, GetTrack and GetPattern
    each CONSTRUCT one of its objects, and a constructor cannot be reached
    through a local look-alike record. The three SizeOfs the code pushes are
    exactly SongElements' three objects:

 PUSH 000a    SizeOf(TInstrument)  VMT + Name + Instr
 PUSH 000e    SizeOf(TTrack)       VMT + Name + Note + Comm
      (GetPattern)             SizeOf(TPattern)     VMT + Name + Patt

    THE LOOK-ALIKE TYPES BELOW ARE KEPT ANYWAY, and deliberately: PLAYMOD reads
    a pattern as `Rows^.RowCount`/`Rows^.Speed` where SongElements spells the
    same two bytes `Patt^.NNotes`/`Patt^.Tempo`. Pointing PLAYMOD at the release's
    names is a rename in a byte-exact unit and belongs in its own pass; until
    then this unit qualifies SongElements' types explicitly where it needs the
    constructors, and the local declarations serve PLAYMOD. }

  Objects, Dos, Heaps, SongElements, VTGlobal;

const
  MaxSequence = 256;   { the release's, in SONGELEM.PAS; $100 is what 073e writes }



type
  { --- moved here from PlayMod so that 14b9 can name it too -----------------
    A note as the song stores it. The release keeps this in `LIB/SONGELEM.PAS`,
    apart from the player, and the same split is forced on us: VTSong declares
    `GetNote(... var N : TFullNote ...)` and PlayMod uses VTSong, so the type
    cannot live in either of them. }








  { THE THREE COLLECTION FIELDS ARE REAL `Objects.TCollection`s, AND THE FILLER
    IS WHAT PROVED IT. They used to be an 8-byte hand-rolled `TColl` -- a VMT
    word, an Items pointer and a Count -- each followed by exactly four bytes of
    filler (`Fill31`, `Fill49`, `Fill55`). TP6's TCollection is
    `object(TObject)` with `Items`, `Count`, `Limit`, `Delta`: **12 bytes, and
    8 + 4 = 12 three times over.** The filler was Limit and Delta.

    AND `Count` IS AN `Integer`, NOT A `Word`, WHICH ONE COMPARISON FIXES.
 is `CWD` -- 14b9 sign-extends Count to a LongInt before comparing
    it against the Word parameter `i`, which is zero-extended. That is Turbo
    Pascal promoting a SIGNED 16-bit value against an unsigned one. Declared a
    Word the whole comparison collapses to a 16-bit `CMP` and the routine is
    fourteen bytes shorter. TCollection's own declaration has it as Integer. }



  { --------------------------------------------------------------------------
    TSong IS AN OBJECT, AND THE CONSTRUCTOR IS WHAT SAYS SO.

    This was declared a plain `record` for most of the project's life, on the
    strength of 154d far-calling 14b9's accessors with the Song pushed as a
    parameter. That is exactly what a STATIC (non-virtual) method call looks
    like -- parameters, then Self, then a direct far call -- so the call site
    could never have separated the two. Three instructions in 14b9 do:

    and both of those routines are `RETF 6`: Self (4) plus the hidden VMT word
    (2) that ONLY a constructor or a destructor carries.

    THE LAYOUT DOES NOT MOVE. TObject has no fields, so the VMT link lands at
    offset 0 -- which is precisely where `Fill00` used to sit, two bytes nothing
    in the tree was ever seen to touch. Every offset below is unchanged, which
    is why nothing ever contradicted the record reading.

    Done is VIRTUAL, as it is in the release; every other method is static, and
    that is what keeps 12ba's and 154d's call sites byte-identical.
    -------------------------------------------------------------------------- }

  PSongHeader = ^TSongHeader;
  TSongHeader = array[0..2047] of Byte;

  { NEW IN v1.51. Thirty-two per-channel panning positions, one byte each --
    see `TSong.ChannelPan` for how the size and the offset were measured, and
    `DefaultChannelPan` for what the values are.}

  TChannelPan = array[1..32] of Byte;

  PSong = ^TSong;
  TSong = object(TObject)
    { +$00..+$01 is the VMT link, supplied by TObject. }
    { +$02 AND +$04 ARE `SongStart` AND `SongLen`, AND THE CONSTANT $100 IS WHAT
      SAYS SO. This file used to argue the opposite -- that the release's first
      two fields "would map onto 1.31's +$02 and +$04" but that the values 1 and
      $100 read as a speed and a tempo rather than a start and a length. They do
      not. `InitValues` opens with

 MOV WORD PTR ES:[DI+02],0001
 MOV WORD PTR ES:[DI+04],0100

      and the release's `InitValues` opens with `SongStart := 1;` and
      `SongLen := MaxSequence;` -- and **MaxSequence is 256**, which is $100.
      First two statements, first two fields, both values exact. A tempo of 256
      is not a tempo (a MOD's BPM runs 32..255) and the pairing was rejected on
      a reading of the values that the constant refutes.

      Nothing in the transcribed tree READS either one, which is consistent: a
      player that always plays the whole module never needs the play range. }
    SongStart : Word;        { +$02  first order entry to play         }
    SongLen   : Word;        { +$04  how many to play; the whole song  }
    Name     : PString;      { +$06  the module's title                 }

    InsidePath : PString;    { +$0a  where inside an archive it came from }
    Comment  : PSongComment; { +$0e  16 lines of the author's own text   }
    FileDir  : PString;      { +$12  the directory it was loaded from    }

    { $16..$23 WERE FILLER AND ARE NOW SETTLED, by InitValues writing a single
      ZERO BYTE at each of +$16 and +$1f. A lone length byte is how Turbo Pascal
      compiles an empty-string assignment, so both are Strings and the gaps are
      their declared sizes: $16..$1e is nine bytes and $1f..$23 is five. That is
      String[8] and String[4] -- FSplit's NameStr and ExtStr exactly, and
 is the routine that calls FSplit. The same arithmetic settled
      DirStr as String[67] in 116e.

      AND 154d CONFIRMS +$1f INDEPENDENTLY: docs/CONTINUATION.md records
 comparing the literal '.WOW' against TSong+$1f, which it already
      called "the release's Song.FileExt". Two segments, one offset. }
    FileName : String[8];    { +$16  8.3, split by FSplit on load        }
    FileExt  : String[4];    { +$1f  and the extension, which .WOW needs }

    FirstTick : Byte;        { +$24  play the first tick of a row?       }


    InitialTempo : Byte;     { +$25 }
    InitialBPM   : Byte;     { +$26 }
    Volume   : Byte;         { +$27  the module's own overall volume     }

    NumChannels : Byte;      { +$28  THE CHANNEL COUNT, 4..8 }

    { +$29..+$48 -- THIRTY-TWO BYTES v1.31 DOES NOT HAVE, AND THE ONLY FIELD
      ADDED TO `TSong` BETWEEN THE TWO VERSIONS. Three independent readings
      agree, which is what makes it safe to insert a field into a record every
      other unit indexes:

      THE SIZE IS THE NAME'S EVIDENCE. Thirty-two entries is not a MOD number;
      it is S3M's channel count, and v1.51's WHATSNEW.DOC leads with "Introduced
      .S3M support". The default values settle what the bytes MEAN -- see the
      constant. Nothing in the transcribed tree READS it yet; the two new loader
      segments are where its consumers will be. }
    ChannelPan : TChannelPan; { +$29..+$48 }


    Instruments : TCollection;
    { +$35 AND +$37 TAKE THE RELEASE'S NAMES. They were Len35 and Len37 --
      addresses for names, because 12ba could only show that both are lengths.
      InitValues clears them in the release's own order, between Instruments.Init
      and the two HGetMems, which is exactly where SequenceLength and
      SequenceRepStart sit in its body. }
    SequenceLength   : Word; { +$35  how long the order list really is   }
    SequenceRepStart : Word; { +$37  where a repeat jumps back to        }


    PatternSequence : PPatternSequence;  { +$39 }
    PatternTempos   : PPatternSequence;  { +$3d }

    Patterns : TCollection;  { +$41..+$4c  count at +$47 }
    Tracks   : TCollection;  { +$4d..+$58  count at +$53 }


    Status   : ShortInt;     { +$59  how the load went; codes below     }
    ErrorCode : Word;        { +$5a  the DOS error, when there was one }
    ThereIsMore : Byte;      { +$5c  the file held more than was read   }
    FileFormat : Byte;       { +$5d  which recogniser claimed it }
    { AND THE RECORD ENDS HERE, at $5e bytes: InitValues initialises every field
      and touches nothing past +$5d. The header's "THE TOTAL SIZE IS NOT SETTLED"
      no longer holds -- it was waiting on exactly this routine. }

    { ------------------------------------------------------------------------
      THE SIXTEEN ROUTINES OF SEGMENT 14b9, IN ADDRESS ORDER.

      Turbo Pascal lays a unit's routines out in SOURCE order, so this list must
      stay in address order or everything below the first misplacement shifts.

      THE `RETF` COUNTS ARE THE SIGNATURE and each one is quoted at its method.
      Note `GetName` is `RETF 4`, not 8: Turbo Pascal does NOT pop the hidden
      string-result pointer, the caller does. 116e's `GetToken : STRING` is
      `RETF 4` for the same reason.
      ------------------------------------------------------------------------ }
    constructor Init;                                            { 0000 RETF 6  }
    destructor  Done; virtual;                                   { 002b RETF 6  }

    { 004f  RETF 8, ENTER 0806,0 -- `TSongHeader` plus the release's `i` and
      `Pos`. NOT TRANSCRIBED, but its NAME and SIGNATURE are no longer guesses:
 is `PUSH SS / PUSH DI (St) / PUSH ES / PUSH DI (Self) /
      PUSH CS / CALL 004f`, which is `Load(St)` from inside LoadFName, with St
      passed by reference. That is what turned `Rut_004f` into a name. }
    procedure Load(var St : TStream);

    procedure LoadFName(FName : PathStr);                        { 0100 RETF 8  }

    function  GetInsidePath : String;                             { 02c2 RETF 4  }
    procedure SetInsidePath(S : String);                          { 02f5 RETF 8  }


    function  GetInstrument(i : Word) : PInstrument;
    { 0404  RETF 6.  154d calls it. }
    function  GetTrack(i : Word) : Pointer;
    { 04b6  RETF 6.  154d calls it. }
    function  GetPattern(i : Word) : PPattern;

    function  GetPatternSeq(i : Word) : PPattern;                { 0575 RETF 6  }
    function  GetPatternSequence(Seq : Word) : Word;             { 059f RETF 6  }
    function  GetPatternTempo(Seq : Word) : Word;                { 05d3 RETF 6  }
    procedure GetNote(Seq, Row, Chan : Word; var Note : TFullNote);
                                                                 { 0607 RETF 14 }

    procedure Free;                                              { 0687 RETF 4  }
    procedure InitValues;                                        { 072f RETF 4  }
    procedure Empty;                                             { 0897 RETF 4  }
  end;


{ `ModOffset` SITS FOUR BYTES BELOW THE TABLE, so it is this unit's, and
  it was declared in VTGLOBAL as a plain `var`. Both halves of that were wrong: the
  address is inside this unit's block, which runs $03c0..$03cb unbroken up to
  ModLoader's, and a `var` puts it in the other DGROUP region entirely so none of its
  four bytes existed. A typed constant holding 0 is what the image has.}
const
  ModOffset : LongInt = 0;

{ --------------------------------------------------------------------------
  Status and format codes.

  Both are enumerations in the original source; here they are constants,
  because only the values that some routine actually stores can be recovered
  from a binary, and an enumeration with holes in it would be a fiction.

  NAMES CONFIRMED against TSongStatus and TSongFileFormat in the 1.39b
  release's LIB/SONGUNIT.PAS. That is a LATER version and is not the source
  of truth -- but the three format values had already been recovered
  independently from stores in 154d and 164b, and all three land on the right
  enumerator. Three for three is good evidence the enumerations did not move
  between 1.31 and 1.39b, which is what makes the status names worth adopting
  too.

  THE STATUS NAMES USED TO BE WRONG, and were wrong in a way that mattered:
  0 was called StatusOK. It is not OK -- it is the INITIAL state, "not yet
  loaded". msOK is 1. A recogniser storing 0 is clearing the field, not
  approving the module.
  -------------------------------------------------------------------------- }

const


  mcNone                   = 0;
  mcArpeggio               = 1;  { 0 xy                    }
  mcTPortUp                = 2;  { 1 xx                    }
  mcTPortDown              = 3;  { 2 xx                    }
  mcNPortamento            = 4;  { 3 xy                                 }
  mcVibrato                = 5;  { 4 xy                                 }
  mcT_VSlide               = 6;  { 5 xy                                 }
  mcVib_VSlide             = 7;  { 6 xy                                 }
  mcTremolo                = 8;  { 7 xy                                 }
  mcNPI1                   = 9;  { 8 xx  does nothing                   }
  mcSampleOffs             = 10; { 9 xx                                 }
  mcVolSlide               = 11; { A xy                                 }
  mcJumpPattern            = 12; { B xx                                 }
  mcSetVolume              = 13; { C xx                                 }
  mcEndPattern             = 14; { D xx                                 }
  mcExtended              = 15;  { E xy  the E-prefixed set             }
  mcSetTempo               = 16; { F xx                                 }
  mcSetFilter              = 17; { E 0x                                 }
  mcFinePortaUp            = 18; { E 1x                                 }
  mcFinePortaDn            = 19; { E 2x                                 }

  {    THESE ARE INTEGER CONSTANTS AND THEY SHADOW THE ENUMERATION. SongElements declares
    `TModCommand` with the same names; this unit's `const` block wins wherever both are
    in scope, which is why `mcLast` here -- and not `Ord(mcLast)` there -- is what
    147d's `CMP BX,mcLast * 2` assembles against. That went unnoticed until the guard
    came out two short. }
  mcGlissCtrl              = 20; { E 3x                                 }
  mcVibCtrl                = 21; { E 4x                                 }
  mcFineTune               = 22; { E 5x                                 }
  mcJumpLoop               = 23; { E 6x                                 }
  mcTremCtrl               = 24; { E 7x                                 }
  mcNPI2                   = 25; { E 8x  does nothing                   }
  mcRetrigNote             = 26; { E 9x                                 }
  mcVolFineUp              = 27; { E Ax                                 }
  mcVolFineDown            = 28; { E Bx                                 }
  mcNoteCut                = 29; { E Cx                                 }
  mcNoteDelay              = 30; { E Dx                                 }
  mcPattDelay              = 31; { E Ex                                 }
  mcFunkIt                 = 32; { E Fx                                 }
  mcOktArp                 = 33; { Oktalizer -- slot exists, tick does not }
  mcOktArp2                = 34; { Oktalizer -- ditto                   }
  mcS3mRetrigNote          = 35; { Scream Tracker Qxy -- NEW IN v1.51   }
  mcLast                   = 36; { guards with mcLast*2 = 48h }

  { +$59. TSongStatus. }
  { **AND THE COMPARISON THIS TREE MEASURED IS THE RELEASE'S OWN BOUNDARY.**
    154d tests `Song.Status > msFileTooShort`, which was read from the bytes and
    said nothing about what the boundary MEANT. The release's source groups these
    same codes under two headings: "[1.39b] Non fatal states" over 1 and 2, and
    "[1.39b] Fatal states" over 3 to 6.

    Those are the same line. A status above msFileTooShort is a fatal one, and
    the test in the code is asking exactly that question.

    Neither source says it alone. The comparison is a measurement with no
    meaning attached; the headings are a meaning with no code attached. Put
    together they name the boundary and explain the test.

    AND STATUS 2 BEING NON-FATAL IS A FACT ABOUT THE WORLD. The release calls it
    "[1.39b] End of file premature (lot's of modules have this)" -- common enough
    in modules of the day that the author expected it and played the file anyway.
    Nothing in any image could have said that. }

  msNotLoaded              = 0;  { the initial state       }
  msOK                     = 1;
  { **[1.39b] "End of file premature (lot's of modules have this)."** Which is
    why it is a NON-FATAL state in the release's own grouping -- it lists 1 and 2
    together under "Non fatal states" and 3 to 6 under "Fatal states". A module
    that ends early is common enough that the author expected it and played the
    file anyway. That is a fact about the corpus of modules in the wild, and
    nothing in this image could have said it. }
  msFileTooShort           = 2;  { premature end of file   }
  msFileOpenError          = 3;  { not seen stored yet                  }
  msOutOfMemory            = 4;
    { [1.39b] "There is not enough memory left. :-( Shouldn't happen." }
  msFileDamaged            = 5;
  { [1.39b] "JMPlayer or ScreamTracker, for example." -- its own examples of a
    format the program recognises and cannot play. }
  msFileFormatNotSupported = 6;  { recognised, not played  }


  { THE RELEASE'S ENUM ORDER CARRIES OVER, AND THREE-FOR-THREE IS WHY THE REST
    ARE NOW WORTH ADDING. Counting `TSongFileFormat` from mffUnknown gives 1, 4
    and 7 for M_K_, JMPlayer and Wow8 -- exactly the three values recovered
    independently from stores in 154d and 164b. The other values were left out
    while nothing stored them; 154d needs three of them. }
  mffUnknown     = 0;
  mffMod31M_K_   = 1;   { 'M.K.', four channels }
  mffMod31FLT4   = 2;   { 'FLT4' }
  mffMod15       = 3;   { [1.39b] SoundTracker 15-instrument module }
  mffJMPlayer    = 4;
  mffOktalizer   = 5;   { [1.39b] 8 voices Oktalizer MOD (.OKT); no loader
                          in 1.31 }
  mffComposer669 = 6;   { no loader in 1.31 }
  mffWow8        = 7;   { [1.39b] "8 voices Grave" (.WOW)               }
  mffFastTracker = 8;   { '6CHN' / '8CHN' -- [1.39b] "6 or 8 voices Triton
                          FastTracker" (.MOD) }
  { TWO MORE IN v1.51, AND BOTH ARE READ OFF THE STORE RATHER THAN COUNTED.
    Each new loader writes its own value into FileFormat before it tests its
    magic, which is this tree's loader contract, so the value is the first
    instruction of the routine:

 MOV BYTE PTR ES:[DI+7d],09      LoadS3MFileFormat
 MOV BYTE PTR ES:[DI+7d],0b      LoadSTMFileFormat

    NINE AND ELEVEN, NOT NINE AND TEN. The gap at 10 is a format v1.51 numbers
    and does not load -- the release's enumeration is longer than its loader
    list, exactly as it is at 5 and 6 above, where mffOktalizer and
    mffComposer669 have no loader in either version. Naming 10 would be an
    invention; leaving the hole is what the binary supports. }
  mffS3M         = 9;
  mffSTM         = 11;


{ This unit declares NO variables at all -- see the note below. }


implementation

{ THE CIRCULAR REFERENCE IS REAL AND TP6 ACCEPTS IT -- ON THE SECOND PASS.
  UnkLoader and ModLoader both `uses SongUnit` in their INTERFACE, for TSong
  and TSongHeader; this unit needs them in its IMPLEMENTATION to name the two
  entries of SongLoaders. Compiled from scratch TP6 answers `Error 68:
  Circular unit reference`, because whichever unit goes first needs the
  other's .TPU -- but with those .TPUs already present it compiles without a
  murmur, and the result is 2,224 bytes, byte-identical to the original.

  That is almost certainly what the author hit and never noticed: .TPUs
  accumulate in a build directory, and only a CLEAN build deadlocks. }
{ VTNOTES FIRST AND FILTERS LAST, AND NEITHER IS REFERENCED BY A LINE OF THIS UNIT.
  They are here because the LINK ORDER requires them and because the release has them,
  which are two independent arguments arriving at the same clause.

  The link argument: TP6 lays segments out in reverse DFS post-order over the `uses`
  graph, so the original's segment addresses read backwards ARE its finish order, and
  between HEAPS and SONGUNIT that order is GUS, SongElements, VTNotes, UnkLoader,
  AsciiZ, ModLoader, Filters. VTNotes has to be reached before UnkLoader and Filters
  after ModLoader, and this unit is the only one positioned to do either -- everything
  else in the neighbourhood finishes on the wrong side. So the clause is forced.

  The release's argument: `LIB/SONGUNIT.PAS`'s implementation clause is `SongUtils,
  UnkLoader, ModLoader, OktLoader, S3mLoader, StmLoader, Loader669, ExeLoader, Heaps,
  StrConst, AsciiZ, Filters`. Take out the six loaders 1.31 has not got (see `Load`,
  which tests `<= 2`) and `StrConst`, and rename `SongUtils` to the name this tree uses
  for `1650` -- and what is left IS the clause below, in that order. Nothing was fitted:
  the order was derived from the segment addresses first and the release checked after.

  A `uses` entry that references nothing is not unusual here -- VTCMD carried a
  `DevGUS` doing exactly that, and the link order is what found it. Costs no bytes:
  a clause changes the link, never the code. }
{$IFNDEF BOOTSTRAP}
uses
  { S3MLoader BEFORE StmLoader, AND THE SEGMENT ORDER IS WHY. Turbo Pascal's
    link order is reverse DFS post-order over the uses graph with clauses taken
    in declaration order, so the unit named LATER in a clause finishes later and
    lands EARLIER in the segment map. The original has 15d0 (STM) below 1664
    (S3M), so StmLoader has to be named second. Written the other way round the
    two segments swap, which `segpair --pair` reports as OUT OF ORDER and which
    moves every DGROUP block below them. }
  VTNotes, UnkLoader, ModLoader, S3MLoader, StmLoader, AsciiZ, Filters;
{$ENDIF}

type
  TSongLoader = procedure(var Song : TSong; var St : TStream;
                          var Header : TSongHeader);

const
  {    v1.31b's table at $03c4 held eight bytes and exactly entries [1] and [4].
    So v1.51 inserts two loaders BETWEEN them, and the order here is the order
    `Load` tries them in. }
  NumLoaders = 4;

  { **THE TWO ENTRIES ARE `NIL` AND THE REAL ONES ARE NAMED IN THIS COMMENT.**
    They are `UnkLoader.LoadJMFileFormat` (segment 164b, the 'JMPLAY'
    recogniser, transcribed and byte-exact) and `ModLoader.LoadModFileFormat`
    (segment 154d, the ProTracker loader, a declared stub in MODLOADE.PAS).
    Both are named here because both are known, not guessed: 164b and 154d are
    the only two loader segments in the program's whole map, and 1.31 keeps
    exactly the FIRST and LAST of the release's eight-entry list.

    WHY NOT WRITE THEM. The release declares this table the same way and reaches
    the two units through an IMPLEMENTATION `uses`, which is the legal direction
    for a circular reference -- both loaders `uses SongUnit` in their interface.
    **TP6 rejects it anyway**, with `Error 68: Circular unit reference`, whether
    or not `/M` is given; TP7 tolerates the same shape, which is how the 1.39b
    release builds. No linear compile order can satisfy it either: whichever of
    the three is compiled first needs one of the others' .TPU.

    AND IT COSTS NOTHING MEASURABLE, WHICH IS THE ONLY REASON THIS IS ACCEPTABLE.
    A typed constant is initialised DGROUP DATA and is not in a .TPU's code at
    all, and `Load`'s call through it is `CALLF [DI+03c0]` -- a DGROUP offset,
    which is a linker fixup and therefore zeros. So the table's CONTENTS cannot
    move a byte of any measurement this project makes, and `Load` compiles
    identically either way. **That is also exactly what makes it dangerous**:
    this is risk 1, the DGROUP layout, in its purest form -- a thing the byte
    comparison is blind to. It is flagged here rather than left to be
    rediscovered, and it must be filled in before anything is LINKED. }
{$IFDEF BOOTSTRAP}
  { First pass only: no initialiser, so the loader units need not exist yet.
    Nothing links against this .TPU -- it exists to be compiled against. }
var
  SongLoaders : array[1..NumLoaders] of TSongLoader;
{$ELSE}

  SongLoaders : array[1..NumLoaders] of TSongLoader =
    (
      LoadJMFileFormat,     { the 'JMPLAY' recogniser  }
      LoadS3MFileFormat,    { the .S3M loader          }
      LoadSTMFileFormat,    { the .STM loader          }
      LoadModFileFormat     { the ProTracker loader    }
    );
{$ENDIF}


const
  DefaultChannelPan : TChannelPan =
    ($40, $B0, $B0, $40, $40, $B0, $B0, $40,
     $40, $B0, $B0, $40, $40, $B0, $B0, $40,
     $40, $B0, $B0, $40, $40, $B0, $B0, $40,
     $40, $B0, $B0, $40, $40, $B0, $B0, $40);




constructor TSong.Init;
begin
  TObject.Init;
  InitValues
end;

{ Throw the module away and put the object back to its empty state, so the
  same TSong can load the next file.}
destructor TSong.Done;
begin
  Free;
  TObject.Done
end;

{ RETF 8, ENTER 0806,0 -- Header (2048), i (2), Pos (4), in the
  release's declaration order laid out downward from BP.}
procedure TSong.Load(var St : TStream);
var
  Header : TSongHeader;
  i      : Word;
  Pos    : LongInt;
begin
  Pos := St.GetPos;

  ThereIsMore := 0;

  St.Read(Header, SizeOf(TSongHeader));

  if St.Status <> stOk then
    begin
      Status    := msFileDamaged;
      ErrorCode := St.ErrorInfo;
      St.Done;
      Exit
    end;

  i := 1;
  while (i      <= NumLoaders) and
        (Status  = msNotLoaded) do
    begin
      St.Seek(Pos);
      SongLoaders[i](PSong(@Self)^, St, Header);
      Inc(i)
    end
end;

{ RETF 8, ENTER 01ae,0.  The release's body verbatim.

  THE FRAME IS THE RELEASE'S DECLARATION ORDER, laid out downward from the value
  parameter's copy, and every offset checks:

  AND A STRING FUNCTION'S RESULT POINTER IS REUSED AS THE ASSIGNMENT'S SOURCE.
  `IPath := GetInsidePath` at 0131 pushes the temp's address, calls, and then
  pushes only ONE more pointer before the string-assign helper -- because the
  result pointer is still on the stack. The callee did not pop it: that is what
  `RETF 4` on a string function means, seen from the caller's side. Same shape
  again at 017b for `FName := FExpand(FName)`.

  FOUR OFFSETS ARE CONFIRMED A SECOND TIME HERE. 0197 passes `Self+$16` and
  `Self+$1f` straight to `FSplit` as its NameStr and ExtStr, which is what those
  two fields are; 01c6 stores HNewStr's result into `+$12`, which is FileDir;
  and 01ec's `PUSH 0004` is `FileExt := '.MOD'` against a String[4].}
procedure TSong.LoadFName(FName : PathStr);
var
  St         : TDosStream;
  Dir        : DirStr;
  IPath      : String[12];
  OSongStart : Word;
  OSongLen   : Word;
begin
  OSongStart := SongStart;
  OSongLen   := SongLen;
  IPath := GetInsidePath;
  Empty;
  SetInsidePath(IPath);
  SongStart := OSongStart;
  SongLen   := OSongLen;

  FName := FExpand(FName);
  FSplit(FName, Dir, FileName, FileExt);
  FileDir := FullHeap.HNewStr(Dir);
  if FileExt = '' then FileExt := '.MOD';
  FName := Dir + FileName + FileExt;

  St.Init(FName, stOpenRead);
  St.Seek(ModOffset);

  if St.Status <> stOk then
    begin
      Status    := msFileOpenError;
      ErrorCode := St.ErrorInfo;
      St.Done;
      Exit
    end;

  Status    := msNotLoaded;
  ErrorCode := 0;

  Load(St);

  if Status <> msOK then
    ErrorCode := St.ErrorInfo;

  St.Done
end;


function TSong.GetInsidePath : String;
begin
  if InsidePath <> nil then
    GetInsidePath := InsidePath^
  else
    GetInsidePath := ''
end;


procedure TSong.SetInsidePath(S : String);
begin
  if InsidePath <> nil then
    FullHeap.HDisposeStr(InsidePath);

  if S <> '' then
    InsidePath := FullHeap.HNewStr(S)
end;

{ RETF 6, ENTER 000c,0 -- result, Instrument, j, and the FOR limit.
  The release's body verbatim. Three things in it are worth reading off:}
function TSong.GetInstrument(i : Word) : PInstrument;
var
  Instrument : PInstrument;
  j          : Word;
label
  Break;
begin
  if i >= Instruments.Count then
    begin
      for j := Instruments.Count to i do
        begin
          Heap.HGetMem(Pointer(Instrument),
                       SizeOf(SongElements.TInstrument));
          if Instrument <> nil then
            begin
              Instrument^.Init;
              Instruments.AtInsert(j, Instrument)
            end
          else
            goto Break
        end;
Break:
      GetInstrument := Instrument
    end
  else
    GetInstrument := PInstrument(Instruments.At(i))
end;


function TSong.GetTrack(i : Word) : Pointer;
var
  Track : SongElements.PTrack;
  j     : Word;
label
  Break;
begin
  if i >= Tracks.Count then
    begin
      for j := Tracks.Count to i do
        begin
          Heap.HGetMem(Pointer(Track), SizeOf(SongElements.TTrack));
          if Track <> nil then
            begin
              Track^.Init;
              Tracks.AtInsert(j, Track)
            end
          else
            goto Break
        end;
Break:
      GetTrack := Track
    end
  else
    GetTrack := Tracks.At(i)
end;

{ RETF 6.  The same body again, against Patterns at +$41 -- and its
  constructor takes an argument where the other two do not: the release writes
  `Pattern^.Init(NumChannels)`, and 1.31's channel count is `Chans` at +$28. }
function TSong.GetPattern(i : Word) : PPattern;
var
  Pattern : SongElements.PPattern;
  j       : Word;
label
  Break;
begin
  if i >= Patterns.Count then
    begin
      for j := Patterns.Count to i do
        begin
          Heap.HGetMem(Pointer(Pattern), SizeOf(SongElements.TPattern));
          if Pattern <> nil then
            begin
              Pattern^.Init(NumChannels);
              Patterns.AtInsert(j, Pattern)
            end
          else
            goto Break
        end;
Break:
      GetPattern := PPattern(Pattern)
    end
  else
    GetPattern := PPattern(Patterns.At(i))
end;


function TSong.GetPatternSeq(i : Word) : PPattern;
begin
  GetPatternSeq := GetPattern(GetPatternSequence(i))
end;


function TSong.GetPatternSequence(Seq : Word) : Word;
begin
  if PatternSequence <> nil then
    GetPatternSequence := PatternSequence^[Seq]
  else
    GetPatternSequence := 0
end;

{ RETF 6, ENTER 2,0 -- the same shape against +$3d.
  This is the accessor docs/CONTINUATION.md carried as "what it holds is not
  determined by its accessor"; 12ba settled it from the consumer's side as a
  per-order-position speed override, and the release names it PatternTempos. }
function TSong.GetPatternTempo(Seq : Word) : Word;
begin
  if PatternTempos <> nil then
    GetPatternTempo := PatternTempos^[Seq]
  else
    GetPatternTempo := 0
end;


procedure TSong.GetNote(Seq, Row, Chan : Word; var Note : TFullNote);
var
  Patt  : SongElements.PPattern;
  Track : SongElements.PTrack;
  n     : Word;
  NOffs : Word;                  { the frame's last two bytes; never read }
begin
  if PatternSequence <> nil then
    begin
      Patt := SongElements.PPattern(GetPatternSeq(Seq));
      if Patt <> nil then
        begin
          n     := Patt^.Patt^.Channels[Chan];
          Track := SongElements.PTrack(GetTrack(n));
          if Track <> nil then
            begin
              { The two TFullNote declarations are the SAME SIX BYTES and a
                different name: SongElements' is a variant record whose first
                branch is field for field this unit's. Pascal is name-equivalent
                for a var parameter, so the call needs the cast. Aliasing the
                two types instead would be tidier and is NOT done -- PLAYMOD
                writes `Note.Command := 0` and compares it against 4 and 6,
                which a TModCommand enumeration rejects. That is a rename in
                two byte-exact units and belongs in its own pass. }
              Track^.GetNote(Row, SongElements.TFullNote(Note));
              Exit
            end
        end
    end;

  FillChar(Note, SizeOf(Note), 0)
end;

{ RETF 4, ENTER 0002,0 -- the release's `i : WORD`, which nothing
  reads; declaring it is what makes the frame two bytes rather than none.

  THE $03d0 IS THE ONE THAT SETTLES IT: `SizeOf(TSongComment)` is
  `16 * 61` = 976 = $3d0 exactly, so +$0e is the comment block. With Comment
  pinned, the release's three-statement order fixes `Name` at +$06 and
  `FileDir` at +$12 -- and that is what corrected `+$0a`, which had been named
  `Name` from SetInsidePath alone. **+$0a IS `InsidePath`**: 1.31 keeps the
  InsidePath pair and drops GetName/SetName, not the other way round, and
  `Free` not touching +$0a is the release's behaviour too.

  `[DI+04]` IS `TObject.Done`, the FIRST virtual slot -- a TP VMT holds the
  positive and negative size words at +$00 and +$02 and the first virtual method
  at +$04 -- so three calls to it are three collections being destroyed.}
procedure TSong.Free;
var
  i : Word;                      { the frame's two bytes; never read }
begin
  asm cli end;

  FullHeap.HDisposeStr(Name);
  FullHeap.HFreeMem(Pointer(Comment), SizeOf(Comment^));
  FullHeap.HDisposeStr(FileDir);

  Instruments.Done;

  FullHeap.HFreeMem(Pointer(PatternSequence),
                    SizeOf(PatternSequence^));
  FullHeap.HFreeMem(Pointer(PatternTempos),
                    SizeOf(PatternTempos^));
  Patterns.Done;

  Tracks.Done;

  asm sti end
end;

{ RETF 4, no frame -- PUSH BP / MOV BP,SP, so no locals at all.

  THIS IS THE ROUTINE THAT NAMED THE RECORD. It initialises every field, in the
  release's order, so its stores ARE the declaration read off the binary -- which
  is a far stronger instrument than any single accessor. Nine fields that were
  filler or an address-for-a-name are named from it, and the record's total size
  falls out of where it stops.

  THE THREE COLLECTION LIMITS ARE THE RELEASE'S EXACTLY: (32,32), (64,64) and
  (256,256), pushed as immediates at 07b0, 0844 and 085a. Unlike `NumBuffers` in
where the release's 3 was 1.39b's and 1.31's was 1 -- these three
  counts did carry over, so this is a case where the release's DATA happened to
  be right. It was still checked rather than copied. }
procedure TSong.InitValues;
begin
  SongStart := 1;
  SongLen   := MaxSequence;

  Name       := nil;
  InsidePath := nil;
  Comment    := nil;
  FileDir    := nil;

  FileName  := '';
  FileExt   := '';
  FirstTick := 0;

  InitialTempo := 1;
  InitialBPM   := 1;
  Volume       := 0;
  NumChannels  := 0;

  Instruments.Init(32, 32);

  SequenceLength   := 0;
  SequenceRepStart := 0;

  FullHeap.HGetMem(Pointer(PatternSequence),
                   SizeOf(PatternSequence^));
  FullHeap.HGetMem(Pointer(PatternTempos),
                   SizeOf(PatternTempos^));
  if PatternSequence <> nil then
    FillChar(PatternSequence^, SizeOf(PatternSequence^), 0);
  if PatternTempos <> nil then
    FillChar(PatternTempos^, SizeOf(PatternTempos^), 0);
  Patterns.Init(64, 64);

  Tracks.Init(256, 256);

  Status      := msNotLoaded;
  ErrorCode   := 0;
  ThereIsMore := 0;
  FileFormat  := mffUnknown;

  { NEW IN v1.51, and the LAST statement of InitValues.

    It must compile to 09f7 and not to 0fb2. Both are copy loops eleven bytes
    apart in SYSTEM; 0fb2 is `Move` and compares the pointers so it can copy
    backwards on overlap, 09f7 is the one the compiler emits for a whole-array
    assignment between two operands of the same NAMED type, where it knows they
    are distinct. See `TChannelPan`. }
  ChannelPan := DefaultChannelPan
end;

{ RETF 4.  The release's `Free; InitValues;` and the last routine
  in both. Written for real because it depends on nothing: two calls. }
procedure TSong.Empty;
begin
  Free;
  InitValues
end;

end.
