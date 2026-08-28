{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

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
  { Objects -- TObject, which TSong descends from, and PString.
    Heaps    -- `FullHeap` at DS:$39ae. 14b9:0339 calls its VMT slot +$30 and
                14b9:0329 slot +$34, which HEAPS.PAS independently declares as
                HNewStr and HDisposeStr. That is the same object 12ba calls at
                +$08, so the VMT geometry is confirmed from a third segment. }
  { SongElements -- 165a, and the release's own layering: its SONGUNIT.PAS uses
    SongElem, not the other way round. GetInstrument, GetTrack and GetPattern
    each CONSTRUCT one of its objects, and a constructor cannot be reached
    through a local look-alike record. The three SizeOfs the code pushes are
    exactly SongElements' three objects:

      14b9:0390   PUSH 000a    SizeOf(TInstrument)  VMT + Name + Instr
      14b9:0442   PUSH 000e    SizeOf(TTrack)       VMT + Name + Note + Comm
      (GetPattern)             SizeOf(TPattern)     VMT + Name + Patt

    THE LOOK-ALIKE TYPES BELOW ARE KEPT ANYWAY, and deliberately: PLAYMOD reads
    a pattern as `Rows^.RowCount`/`Rows^.Speed` where SongElements spells the
    same two bytes `Patt^.NNotes`/`Patt^.Tempo`. Pointing PLAYMOD at the release's
    names is a rename in a byte-exact unit and belongs in its own pass; until
    then this unit qualifies SongElements' types explicitly where it needs the
    constructors, and the local declarations serve PLAYMOD. }
  { Dos      -- FSplit, FExpand, PathStr and DirStr; LoadFName calls 1b6f:0241
                and 1b6f:0178, which are those two.
    VTGlobal -- ModOffset. 14b9:0242 pushes the LongInt at DS:$03c0 straight
                into St.Seek, and VTGLOBAL.PAS already declares it. }
  Objects, Dos, Heaps, SongElements, VTGlobal;

const
  MaxSequence = 256;   { the release's, in SONGELEM.PAS; $100 is what 073e writes }



type
  { --- moved here from PlayMod so that 14b9 can name it too -----------------
    A note as the song stores it. The release keeps this in `LIB/SONGELEM.PAS`,
    apart from the player, and the same split is forced on us: VTSong declares
    `GetNote(... var N : TFullNote ...)` and PlayMod uses VTSong, so the type
    cannot live in either of them. }



{ --------------------------------------------------------------------------
  The sample descriptor 165a fills in, as much of it as 12ba establishes.

  ONLY THE FIELDS THIS UNIT PROVES ARE NAMED; 165a is not transcribed and
  guessing at the rest would put invented names into a record other segments
  share. Same policy as VTCtrl's control block.
  -------------------------------------------------------------------------- }
  PSampleDesc = ^TSampleDesc;
  TSampleDesc = record
    SplLen    : LongInt;        { +$00  compared against $FFF0 at 12ba:0417  }
    LoopStart : LongInt;        { +$04  added to LoopLen and compared to 64K }
    LoopLen   : LongInt;        { +$08  and its low three bytes are the test }
    Volume    : Byte;           { +$0c  -> TCanal.Volume at 12ba:0a03        }
    Pad0D     : Byte;           { +$0d                                        }
    { +$0e and +$10 -- a RATIO applied to the period: 12ba:0e9f multiplies by the
      first and divides by the second to turn a channel's period into the one the
      hardware wants. Named for that; what they really are is 165a's business. }
    PeriodMul : Word;           { +$0e                                        }
    PeriodDiv : Word;           { +$10                                        }
    { +$12 -- a GUS DRAM ADDRESS, not a host pointer, and the arithmetic at
      12ba:05e0 proves it: LoopStart is ADDED to it. The asm at 03e0 splits the
      same four bytes into Raw.SplOfs1/SplSeg1, so on the GUS path those two
      fields hold the halves of a DRAM address rather than a segment and an
      offset. }
    Data1     : LongInt;        { +$12                                       }
    Data2     : Pointer;        { +$16  DEREFERENCED, then Ofs and Seg taken }
    Filler2   : array[$1A..$1F] of Byte;
  end;

  TModCommand = Byte;

  TFullNote = record
    Instrument : Byte;          { +$00                                       }
    Period     : Word;          { +$01                                       }
    Volume     : Byte;          { +$03                                       }
    Command    : TModCommand;   { +$04                                       }
    Parameter  : Byte;          { +$05                                       }
  end;


  { THE THREE COLLECTION FIELDS ARE REAL `Objects.TCollection`s, AND THE FILLER
    IS WHAT PROVED IT. They used to be an 8-byte hand-rolled `TColl` -- a VMT
    word, an Items pointer and a Count -- each followed by exactly four bytes of
    filler (`Fill31`, `Fill49`, `Fill55`). TP6's TCollection is
    `object(TObject)` with `Items`, `Count`, `Limit`, `Delta`: **12 bytes, and
    8 + 4 = 12 three times over.** The filler was Limit and Delta.

    The code says the same thing independently. census.py finds `1891:03a7`
    called EXACTLY THREE TIMES, all inside InitValues -- the release's
    `Instruments.Init(32,32)`, `Patterns.Init(64,64)` and `Tracks.Init(256,256)`
    -- and `1891:0405`/`047a` three times each, one pair inside each of
    GetInstrument, GetTrack and GetPattern, which is `At` and `AtInsert`.

    AND `Count` IS AN `Integer`, NOT A `Word`, WHICH ONE COMPARISON FIXES.
    14b9:035d is `CWD` -- 14b9 sign-extends Count to a LongInt before comparing
    it against the Word parameter `i`, which is zero-extended. That is Turbo
    Pascal promoting a SIGNED 16-bit value against an unsigned one. Declared a
    Word the whole comparison collapses to a 16-bit `CMP` and the routine is
    fourteen bytes shorter. TCollection's own declaration has it as Integer. }

  { --- moved here from the VTSONG stub when it was folded in ----------------
    What 14b9:0575 returns. PlayMod reads the far pointer at +$06 and takes the
    byte at IT -- the pattern's row count. Nothing else here is established, and
    these records belong to 14b9 rather than to us.

    THEY DUPLICATE TYPES `SONGELEM.PAS` ALREADY DECLARES, deliberately and for
    now: 165a is byte-exact and its declarations are the real ones, but pointing
    this unit at them means adding `uses SongElements` here and moving SongUnit
    down build.py's ORDER, which is a change that can move a byte in three
    byte-exact units. Do it as its own pass, with verify.py either side. }
  { ONE-BASED, and 14b9:05bc is what proves it: GetPatternSequence computes
    `LES DI,[DI+39] / ADD DI,AX / MOV AL,ES:[DI-1]`, and that -1 is the base.
    256 is the release's `MaxSequence`, declared identically in SONGELEM.PAS. }
  PPatternSequence = ^TPatternSequence;
  TPatternSequence = array[1..MaxSequence] of Byte;

  PPatternData = ^TPatternData;
  TPatternData = record
    RowCount : Byte;            { +$00  12ba:0792 compares it against the row }
    Filler1  : Byte;            { +$01                                        }
    Speed    : Byte;            { +$02  12ba:08d7 -- a per-pattern override   }
  end;

  PInstrumentRec = ^TInstrumentRec;
  TInstrumentRec = record
    Filler1 : array[$00..$05] of Byte;
    Data    : Pointer;          { +$06  -> TCanal.Instrument at 12ba:09b4     }
  end;

  PPattern = ^TPattern;
  TPattern = record
    Filler1 : array[$00..$05] of Byte;
    Rows    : PPatternData;     { +$06                                        }
  end;

  { --------------------------------------------------------------------------
    TSong IS AN OBJECT, AND THE CONSTRUCTOR IS WHAT SAYS SO.

    This was declared a plain `record` for most of the project's life, on the
    strength of 154d far-calling 14b9's accessors with the Song pushed as a
    parameter. That is exactly what a STATIC (non-virtual) method call looks
    like -- parameters, then Self, then a direct far call -- so the call site
    could never have separated the two. Three instructions in 14b9 do:

      14b9:0005  XOR DI,DI / CALLF 1ba1:04f5 / JZ over the body
                 Turbo Pascal's CONSTRUCTOR prologue helper. DI = 0 is "do not
                 allocate"; the JZ is the failure path. Nothing else emits it.
      14b9:0014  CALLF 1891:0000 with a zero VMT word and Self  -- TObject.Init
      14b9:003f  CALLF 1891:0031                                -- TObject.Done

    and both of those routines are `RETF 6`: Self (4) plus the hidden VMT word
    (2) that ONLY a constructor or a destructor carries.

    THE LAYOUT DOES NOT MOVE. TObject has no fields, so the VMT link lands at
    offset 0 -- which is precisely where `Fill00` used to sit, two bytes nothing
    in the tree was ever seen to touch. Every offset below is unchanged, which
    is why nothing ever contradicted the record reading.

    Done is VIRTUAL, as it is in the release; every other method is static, and
    that is what keeps 12ba's and 154d's call sites byte-identical.
    -------------------------------------------------------------------------- }
  { THE 2,048-BYTE SNIFF BUFFER, and 14b9:0074 is the measurement: `Load` reads
    `PUSH 0800` bytes of the file into a stack local before handing it to each
    recogniser in turn. `ENTER 0806,0` accounts for it exactly -- 2048 for the
    header, 2 for `i`, 4 for `Pos`. The release declares the same array. }
  PSongHeader = ^TSongHeader;
  TSongHeader = array[0..2047] of Byte;

  { NEW IN v1.51. Thirty-two per-channel panning positions, one byte each --
    see `TSong.ChannelPan` for how the size and the offset were measured, and
    `DefaultChannelPan` for what the values are.

    IT HAS TO BE A NAMED TYPE, and that is a code fact rather than a style
    choice. InitValues' new statement compiles to 1d89:09f7, which is the copy
    helper WITHOUT the overlap check -- the one Turbo Pascal emits for a whole
    array ASSIGNMENT, where it knows the operands are distinct. `Move` compiles
    to 1d89:0fb2, eleven bytes away, and compares the pointers first. TP only
    allows `A := B` between arrays of the same NAMED type, so an anonymous
    `array[0..31] of Byte` on either side forces the site to be `Move` and
    picks up the wrong helper. The same distinction cost v1.31b two of its last
    five divergent bytes, in PLAYMOD. }
  TChannelPan = array[0..31] of Byte;

  PSong = ^TSong;
  TSong = object(TObject)
    { +$00..+$01 is the VMT link, supplied by TObject. }
    { +$02 AND +$04 ARE `SongStart` AND `SongLen`, AND THE CONSTANT $100 IS WHAT
      SAYS SO. This file used to argue the opposite -- that the release's first
      two fields "would map onto 1.31's +$02 and +$04" but that the values 1 and
      $100 read as a speed and a tempo rather than a start and a length. They do
      not. `InitValues` opens with

        14b9:0735   MOV WORD PTR ES:[DI+02],0001
        14b9:073e   MOV WORD PTR ES:[DI+04],0100

      and the release's `InitValues` opens with `SongStart := 1;` and
      `SongLen := MaxSequence;` -- and **MaxSequence is 256**, which is $100.
      First two statements, first two fields, both values exact. A tempo of 256
      is not a tempo (a MOD's BPM runs 32..255) and the pairing was rejected on
      a reading of the values that the constant refutes.

      Nothing in the transcribed tree READS either one, which is consistent: a
      player that always plays the whole module never needs the play range. }
    SongStart : Word;        { +$02  := 1            by 14b9:0735 }
    SongLen   : Word;        { +$04  := MaxSequence  by 14b9:073e }
    Name     : PString;      { +$06  HDisposeStr at 14b9:069c            }
    { +$0a IS `Name : PString`, and SetName is what says so: 14b9:02f5 calls
      HDisposeStr ([DI+34]) on the address of this field and stores HNewStr's
      ([DI+30]) result back into it. The release's field name, adopted. }
    InsidePath : PString;    { +$0a  SetInsidePath writes it; Free does NOT }
    Comment  : PSongComment; { +$0e  HFreeMem $3d0 = 16 * 61 at 14b9:06b2 }
    FileDir  : PString;      { +$12  HDisposeStr at 14b9:06c5            }

    { $16..$23 WERE FILLER AND ARE NOW SETTLED, by InitValues writing a single
      ZERO BYTE at each of +$16 and +$1f. A lone length byte is how Turbo Pascal
      compiles an empty-string assignment, so both are Strings and the gaps are
      their declared sizes: $16..$1e is nine bytes and $1f..$23 is five. That is
      String[8] and String[4] -- FSplit's NameStr and ExtStr exactly, and
      14b9:0100 is the routine that calls FSplit. The same arithmetic settled
      DirStr as String[67] in 116e.

      AND 154d CONFIRMS +$1f INDEPENDENTLY: docs/CONTINUATION.md records
      154d:0c4d comparing the literal '.WOW' against TSong+$1f, which it already
      called "the release's Song.FileExt". Two segments, one offset. }
    FileName : String[8];    { +$16  emptied at 14b9:077b }
    FileExt  : String[4];    { +$1f  emptied at 14b9:0783 }
    { A Byte, NOT the release's BOOLEAN. The standing rule is not to change a
      type to match the release, and the code decides it here as it did for
      VoicesChanged: 12ba:0d64 tests this field <> 0. 14b9 only ever stores a
      zero byte in it. }
    FirstTick : Byte;        { +$24  := 0 at 14b9:078b; 12ba:0d64 reads it }

    { +$25 and +$26 keep their VALUES and take the release's NAMES: 154d:09d7
      writes 6 and $7d, the ProTracker defaults, and InitValues sets both to 1. }
    InitialTempo : Byte;     { +$25 }
    InitialBPM   : Byte;     { +$26 }
    Volume   : Byte;         { +$27  := 0 at 14b9:07a3 -- was filler }

    NumChannels : Byte;      { +$28  THE CHANNEL COUNT, 4..8 }

    { +$29..+$48 -- THIRTY-TWO BYTES v1.31 DOES NOT HAVE, AND THE ONLY FIELD
      ADDED TO `TSong` BETWEEN THE TWO VERSIONS. Three independent readings
      agree, which is what makes it safe to insert a field into a record every
      other unit indexes:

        * `verdiff.py 14b9 -> 153a` buckets 51 displacement changes at exactly
          +$20, and the SMALLEST old displacement in the bucket is $29. A field
          below an insertion does not move, so the insertion is AT $29.
        * `TSong`'s VMT size word says $7e where v1.31's says $5e. $5e + $20.
        * InitValues gained one statement, and it copies 32 bytes from
          DS:$0440 to Self+$29 -- see `DefaultChannelPan` below.

      THE SIZE IS THE NAME'S EVIDENCE. Thirty-two entries is not a MOD number;
      it is S3M's channel count, and v1.51's WHATSNEW.DOC leads with "Introduced
      .S3M support". The default values settle what the bytes MEAN -- see the
      constant. Nothing in the transcribed tree READS it yet; the two new loader
      segments are where its consumers will be. }
    ChannelPan : TChannelPan; { +$29..+$48 }

    { +$49..+$54 in v1.51; it was +$29..+$34 in v1.31. The release's name:
      GetInstrument is what indexes it, and 14b9:03be reached it as
      `LES DI,[BP+06] / ADD DI,0029` -- 0049 now. Count at +$4f. }
    Instruments : TCollection;
    { +$35 AND +$37 TAKE THE RELEASE'S NAMES. They were Len35 and Len37 --
      addresses for names, because 12ba could only show that both are lengths.
      InitValues clears them in the release's own order, between Instruments.Init
      and the two HGetMems, which is exactly where SequenceLength and
      SequenceRepStart sit in its body. }
    SequenceLength   : Word; { +$35  12ba:10a1 falls back to this for the end }
    SequenceRepStart : Word; { +$37  12ba:1107 compares it against the range end }

    { +$39 and +$3d ARE THE RELEASE'S `PatternSequence` AND `PatternTempos`,
      named by their accessors now that 14b9's routine map is read. 14b9:059f is
      GetPatternSequence and 14b9:05d3 is GetPatternTempo, in the release's own
      implementation order and with its own bodies:

        IF PatternTempos <> NIL THEN Result := PatternTempos^[Seq] ELSE 0

      `Table3D` had kept its address for a name because its accessor did not say
      what it held; 12ba then settled it from the consumer's side as a
      per-order-position SPEED OVERRIDE, zero meaning none. Producer and consumer
      agree, which is what makes the name worth adopting. }
    PatternSequence : PPatternSequence;  { +$39 }
    PatternTempos   : PPatternSequence;  { +$3d }

    Patterns : TCollection;  { +$41..+$4c  count at +$47 }
    Tracks   : TCollection;  { +$4d..+$58  count at +$53 }

    { A ShortInt, NOT a Byte, and 154d is what settles it. 154d:0b4c and
      154d:0b6a are `CMP byte ES:[DI+59],n / JLE` -- a SIGNED byte comparison,
      where a Byte gives the unsigned JBE. Both are `Song.Status > msOk` and
      `> msFileTooShort` in LoadMod. 14b9 and 164b only ever compare it for
      EQUALITY or store it, which is sign-independent, so neither could see
      this -- the fifth thing settled only by a caller in another segment.
      (The release has it as an enumeration; this is read from the bytes rather
      than taken from the release, which is the standing rule working.) }
    Status   : ShortInt;     { +$59  := 0 at 14b9:0875; see the codes below }
    ErrorCode : Word;        { +$5a  := 0 at 14b9:087f -- was filler }
    ThereIsMore : Byte;      { +$5c  := 0 at 14b9:0886 -- was filler; a Byte, as above }
    FileFormat : Byte;       { +$5d  which recogniser claimed it }
    { AND THE RECORD ENDS HERE, at $5e bytes: InitValues initialises every field
      and touches nothing past +$5d. The header's "THE TOTAL SIZE IS NOT SETTLED"
      no longer holds -- it was waiting on exactly this routine. }

    { ------------------------------------------------------------------------
      THE SIXTEEN ROUTINES OF SEGMENT 14b9, IN ADDRESS ORDER.

      Turbo Pascal lays a unit's routines out in SOURCE order, so this list must
      stay in address order or everything below the first misplacement shifts.

      The order is the release's implementation order with five routines removed,
      and 21 - 5 = 16 is the segment's far-return count exactly. The five absent
      are `Save` and `SaveFName` (a player does not write modules),
      `GetErrorString` (census.py finds NO printable string in 2,224 bytes but
      `.MOD`, and that routine is nothing but message literals), and
      `GetInsidePath`/`SetInsidePath`.

      THE `RETF` COUNTS ARE THE SIGNATURE and each one is quoted at its method.
      Note `GetName` is `RETF 4`, not 8: Turbo Pascal does NOT pop the hidden
      string-result pointer, the caller does. 116e's `GetToken : STRING` is
      `RETF 4` for the same reason.
      ------------------------------------------------------------------------ }
    constructor Init;                                            { 0000 RETF 6  }
    destructor  Done; virtual;                                   { 002b RETF 6  }

    { 004f  RETF 8, ENTER 0806,0 -- `TSongHeader` plus the release's `i` and
      `Pos`. NOT TRANSCRIBED, but its NAME and SIGNATURE are no longer guesses:
      14b9:0299 is `PUSH SS / PUSH DI (St) / PUSH ES / PUSH DI (Self) /
      PUSH CS / CALL 004f`, which is `Load(St)` from inside LoadFName, with St
      passed by reference. That is what turned `Rut_004f` into a name. }
    procedure Load(var St : TStream);

    procedure LoadFName(FName : PathStr);                        { 0100 RETF 8  }

    function  GetInsidePath : String;                             { 02c2 RETF 4  }
    procedure SetInsidePath(S : String);                          { 02f5 RETF 8  }

    { 0352  RETF 6.  154d:0030's target. }
    function  GetInstrument(i : Word) : PInstrumentRec;
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

{ DECLARED AFTER `TSong`, AND THE ORDER MATTERS. `TSong`'s VMT is DGROUP data too --
  $03b8..$03bf holds `005e ffa2 002b 04b9`, which is SizeOf(TSong) = $5e, its negative,
  and a far pointer to `TSong.Done` at 14b9:002b -- and the original lays that VMT down
  BEFORE this constant, at the point the TYPE is declared. Declared up beside
  `MaxSequence`, ahead of the type, ModOffset came out first and the two swapped.
  Costs no code either way; `demovt/dgroup.py` is the only thing that can see it. }
{ DS:$03c0 -- `ModOffset` SITS FOUR BYTES BELOW THE TABLE, so it is this unit's, and
  it was declared in VTGLOBAL as a plain `var`. Both halves of that were wrong: the
  address is inside this unit's block, which runs $03c0..$03cb unbroken up to
  ModLoader's, and a `var` puts it in the other DGROUP region entirely so none of its
  four bytes existed. A typed constant holding 0 is what the image has.

  It is the offset of the module inside its file, and `14b9:0242` pushes it into
  `St.Seek` -- which is this unit's own `LoadFName`, so the consumer is here too. }
const
  ModOffset : LongInt = 0;                    { DS:$03c0 }

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
  { TModCommand. The release makes this an ENUMERATION, `TModCommand = (mcNone,
    mcArpeggio, mcTPortUp, ...)` in `LIB/SONGELEM.PAS`, with mcNone first and so
    zero; only the one name is adopted here, because it is the only one 12ba
    stores -- 12ba:120d clears `Canales[i].Note.Command` at the start of a song.
    The TYPE stays a Byte, per the standing rule against taking a type from the
    release: nothing in the transcribed tree treats it as ordered. }
  { AND THE WHOLE ORDERING IS THE RELEASE'S, CONFIRMED BY TWO STORES. 142f:0100
    writes $12 into `Note.Command` where the release's StartTPortUp writes
    `mcFinePortaUp`, and 142f:014f writes $13 where StartTPortDown writes
    `mcFinePortaDn`. Counting the release's enum from mcNone gives exactly 18 and
    19 for those two, so every value between them is fixed as well -- one
    coincidence would be luck, two consecutive ones in the two routines that are
    supposed to produce them is the ordering.

    Note the FIRST TWO SHARE A COMMAND NIBBLE: ProTracker's effect 0 is arpeggio
    when its parameter is non-zero and nothing at all when it is zero, so the
    release spends two enum values on one nibble and everything after is shifted
    by one. That is why mcTPortUp is 2 and not 1. }
  mcNone                   = 0;  { 12ba:120d                            }
  mcArpeggio               = 1;  { 0 xy  142f:0000                      }
  mcTPortUp                = 2;  { 1 xx  142f:00cc                      }
  mcTPortDown              = 3;  { 2 xx  142f:011b                      }
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
  mcFinePortaUp            = 18; { E 1x  142f:0100 stores $12           }
  mcFinePortaDn            = 19; { E 2x  142f:014f stores $13           }

  { AND 20 TO 35 ARE FIXED BY THE DISPATCH TABLE, not by counting the release's
    enum. `142f:063f` guards with `CMP BX,46h`, so the last valid index is 34 and
    `mcLast` is 35; the table at DS:$0370 is 36 words, which is
    `ARRAY[mcNone..mcLast]` exactly as the release declares it. Each index holds the
    offset of the tick routine for that command, and every one lands on the routine
    the release's table has at the same index -- including both DOUBLED pairs, 18
    and 19 sharing TickFPortUpDown and 27 and 28 sharing TickVolFineUpDn. Sixteen
    names came out of that one table.

    `mcLast` IS 35 HERE AND 36 IN THE RELEASE, which is the S3M command missing:
    1.39b has `mcS3mRetrigNote` at 35 and 1.31 has nothing there. Consistent with
    TCanal having no S3mRetAdd/S3mRetVal either. }
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
  mcLast                   = 35; { 142f:063f guards with mcLast*2 = 46h }

  { +$59. TSongStatus. }
  msNotLoaded              = 0;  { 164b:0044 -- the initial state       }
  msOK                     = 1;  { 154d:09d7                            }
  msFileTooShort           = 2;  { 154d:00c9 -- premature end of file   }
  msFileOpenError          = 3;  { not seen stored yet                  }
  msOutOfMemory            = 4;  { 154d:004a, 154d:0490                 }
  msFileDamaged            = 5;  { 154d:09d7                            }
  msFileFormatNotSupported = 6;  { 164b:003a -- recognised, not played  }

  { +$5d. TSongFileFormat. Only the values some routine stores are named, and
    InitValues adds the fourth: 14b9:088e clears the field, and the release's
    last line is `FileFormat := mffUnknown`, so zero is that enumerator. }
  { THE RELEASE'S ENUM ORDER CARRIES OVER, AND THREE-FOR-THREE IS WHY THE REST
    ARE NOW WORTH ADDING. Counting `TSongFileFormat` from mffUnknown gives 1, 4
    and 7 for M_K_, JMPlayer and Wow8 -- exactly the three values recovered
    independently from stores in 154d and 164b. The other values were left out
    while nothing stored them; 154d needs three of them. }
  mffUnknown     = 0;   { 14b9:088e }
  mffMod31M_K_   = 1;   { 154d:0c7f -- 'M.K.', four channels }
  mffMod31FLT4   = 2;   { 'FLT4' }
  mffMod15       = 3;   { the 15-instrument SoundTracker fallback }
  mffJMPlayer    = 4;   { 164b:0007 }
  mffOktalizer   = 5;   { no loader in 1.31 }
  mffComposer669 = 6;   { no loader in 1.31 }
  mffWow8        = 7;   { 154d:0c6d -- '.WOW', eight channels }
  mffFastTracker = 8;   { '6CHN' / '8CHN' }
  { TWO MORE IN v1.51, AND BOTH ARE READ OFF THE STORE RATHER THAN COUNTED.
    Each new loader writes its own value into FileFormat before it tests its
    magic, which is this tree's loader contract, so the value is the first
    instruction of the routine:

      1664:0a90   MOV BYTE PTR ES:[DI+7d],09      LoadS3MFileFormat
      15d0:076b   MOV BYTE PTR ES:[DI+7d],0b      LoadSTMFileFormat

    NINE AND ELEVEN, NOT NINE AND TEN. The gap at 10 is a format v1.51 numbers
    and does not load -- the release's enumeration is longer than its loader
    list, exactly as it is at 5 and 6 above, where mffOktalizer and
    mffComposer669 have no loader in either version. Naming 10 would be an
    invention; leaving the hole is what the binary supports. }
  mffS3M         = 9;   { 1664:0a90 }
  mffSTM         = 11;  { 15d0:076b }

{ DS:$0564 -- the release's `LowQuality`, and its OWNER is the release's too:
  `LIB/SONGELEM.PAS` is this unit's counterpart and declares it. 11bb:0b0e's
  `LowQuality` key writes it, which is the only use in the transcribed tree. }
{ This unit declares NO variables at all -- see the note below. }
  { ~~LowQuality : Boolean at DS:$0564~~ -- IT IS SONGELEMENTS', AND A TYPED CONSTANT.
    $0564 is in the INITIALISED half of DGROUP -- `dgroup.py` reports that half exact and
    accounts for every byte of it -- so it cannot be a `var`; and it is the two bytes
    immediately below SongElements' three VMTs at $0566, $056e and $0576, which puts it
    at the head of that unit's block. Declared here it was two bytes of THIS unit's
    variables, and two bytes is exactly what `VTNOTES`'s `NoteOf` was out by. }

implementation

{ THE CIRCULAR REFERENCE IS REAL AND TP6 ACCEPTS IT -- ON THE SECOND PASS.
  UnkLoader and ModLoader both `uses SongUnit` in their INTERFACE, for TSong
  and TSongHeader; this unit needs them in its IMPLEMENTATION to name the two
  entries of SongLoaders. Compiled from scratch TP6 answers `Error 68:
  Circular unit reference`, because whichever unit goes first needs the
  other's .TPU -- but with those .TPUs already present it compiles without a
  murmur, and the result is 2,224 bytes, byte-identical to the original.

  So the build BOOTSTRAPS: `build.py` compiles this unit once with
  /DBOOTSTRAP, which takes the `uses` and the table's initialiser out, then
  compiles the two loaders against the resulting .TPU, then compiles this unit
  again for real. **The INTERFACE is identical either way**, which is what
  makes the first pass's .TPU a valid thing to compile the loaders against.

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
  VTNotes, UnkLoader, ModLoader, AsciiZ, Filters;
{$ENDIF}

type
  TSongLoader = procedure(var Song : TSong; var St : TStream;
                          var Header : TSongHeader);

const
  { **TWO, NOT THE RELEASE'S EIGHT**, and one instruction says so: 14b9:00b8 is
    `CMP WORD PTR [BP-0802],0002`. 1.39b recognises .669, .OKT, .S2M, .S3M,
    .STM and self-extracting .EXEs as well; 1.31 keeps the first and the last of
    its list and drops the middle six. That is consistent with everything else
    known about this build -- 109c's extension list is the loaders the PLAYER
    still advertises, and the two segments here are 164b (the 'JMPLAY'
    recogniser) and 154d (the ProTracker loader), which are the only two loader
    segments in the whole program's map.

    THE TABLE IS AT DS:$0430 IN v1.51 -- it was $03c4 in v1.31b -- and the code
    indexes it base-1; see the note at Load, because the displacement collides
    with a real variable.

    FOUR ENTRIES NOW, AND THE TABLE ITSELF IS THE MEASUREMENT. DS:$0430 holds
    sixteen bytes, read straight out of ref/vt1.51.bin as four (offset, segment)
    pairs:

        [1] 1839:0000    UnkLoader   -- the 'JMPLAY' recogniser, unchanged
        [2] 1664:0a8b    the segment this tree calls LOADER2
        [3] 15d0:0764    the segment this tree calls LOADER1
        [4] 173d:0bd4    ModLoader   -- the ProTracker loader

    v1.31b's table at $03c4 held eight bytes and exactly entries [1] and [4].
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
  { ENTRIES 2 AND 3 ARE PLACEHOLDERS AND POINT AT THE WRONG ROUTINE. Their real
    targets are 1664:0a8b and 15d0:0764, in two units this tree has not written.

    **`nil` WOULD BE THE HONEST PLACEHOLDER AND TP6 REFUSES IT** -- `SONGUNIT.PAS
    (684): Error 20: Variable identifier expected`. A procedural typed constant
    takes a procedure IDENTIFIER, not a pointer expression, so the choice is a
    wrong name or no table. Repeating a name that already exists costs no code:
    a typed constant is initialised DGROUP data and `Load`'s call through it is
    `CALLF [DI+0430]`, a linker fixup either way.

    THAT IS ALSO WHAT MAKES IT DANGEROUS, and it is the same trap v1.31b flagged
    here for its own two entries. The byte comparison of CODE is blind to this;
    only `dgimage.py` can see it, and it will report eight wrong bytes at
    DS:$0434 and DS:$0438 until the loaders exist. Do not read a green
    `units.py` or `linkcmp.py` as saying this table is right. }
  SongLoaders : array[1..NumLoaders] of TSongLoader =
    (
      LoadJMFileFormat,     { 1839       -- the 'JMPLAY' recogniser }
      LoadJMFileFormat,     { 1664:0a8b  -- PLACEHOLDER, wrong       }
      LoadJMFileFormat,     { 15d0:0764  -- PLACEHOLDER, wrong       }
      LoadModFileFormat     { 173d       -- the ProTracker loader    }
    );
{$ENDIF}

{ DS:$0440..$045f -- THE THIRTY-TWO BYTES `InitValues` COPIES INTO
  `TSong.ChannelPan`, and the values are what name the field.

  The image holds `40 B0 B0 40` repeated eight times. Two positions, alternating
  L-R-R-L: $40 is 64 and $B0 is 176, symmetric about the 128 centre of a byte
  pan range. That is the Amiga/ProTracker channel assignment -- channels 1 and 4
  left, 2 and 3 right -- tiled across all thirty-two channels, and it is also
  S3M's default. A table of thirty-two bytes taking two values in that pattern
  is a panning default and is not plausibly anything else.

  IT SITS AFTER `SongLoaders` BECAUSE THE ORIGINAL PUTS IT THERE. DGROUP holds
  each unit's typed constants in DECLARATION order within the unit's block, so
  this constant's position in this file is load-bearing: SongUnit's block runs
  $0424 (the VMT) .. $045f, and the next unit's constants begin at $0460 with
  the STM loader's '!Scream!' marker. Moving this declaration up moves twenty
  bytes of a neighbour. }
const
  DefaultChannelPan : TChannelPan =
    ($40, $B0, $B0, $40, $40, $B0, $B0, $40,
     $40, $B0, $B0, $40, $40, $B0, $B0, $40,
     $40, $B0, $B0, $40, $40, $B0, $B0, $40,
     $40, $B0, $B0, $40, $40, $B0, $B0, $40);

{ ---------------------------------------------------------------------------
  TRANSCRIBED STRICTLY TOP-DOWN, AND THE ORDER IS THE MEASUREMENT. Turbo Pascal
  lays a unit's routines out in SOURCE order, so a routine written out of place
  displaces everything below it. Routines still to do are PLACEHOLDERS holding
  their position -- they are the wrong length, so every near-call displacement
  and every routine after the first placeholder is wrong too. That is expected:
  `verify.py`'s prefix stops at the first such displacement and says nothing
  about the bytes beyond it. Measure a half-written unit per block, not by the
  prefix -- see docs/CONTINUATION.md, "THE PREFIX IS NOT THE MEASURE MID-ROUTINE".
  --------------------------------------------------------------------------- }

{ 0000..002a.  RETF 6 -- Self plus the hidden VMT word.
  0000  PUSH BP / MOV BP,SP
  0003  XOR DI,DI / CALLF 1ba1:04f5      the constructor prologue helper
  000a  JZ 0022                          allocation/failure path
  000c  XOR AX,AX / PUSH AX / <Self>     VMT word 0 -- an inherited construct
  0014  CALLF 1891:0000                  TObject.Init
  0019  <Self> / PUSH CS / CALL 072f     InitValues
  0022  LES AX,[BP+06] / MOV DX,ES       the result is Self
  The release writes `TObject.Init;` qualified rather than `inherited Init;`;
  the two compile identically and the release's form is the one adopted. }
constructor TSong.Init;
begin
  TObject.Init;                                      { 000c..0018            }
  InitValues                                         { 0019..0021            }
end;

{ 002b..004e.  RETF 6.
  002e  <Self> / PUSH CS / CALL 0687     Free
  0037  XOR AX,AX / PUSH AX / <Self>     VMT word 0
  003f  CALLF 1891:0031                  TObject.Done
  0044  XOR DI,DI / CALLF 1ba1:0539      the destructor epilogue helper }
destructor TSong.Done;
begin
  Free;                                              { 002e..0036            }
  TObject.Done                                       { 0037..0043            }
end;

{ 004f..00ff.  RETF 8, ENTER 0806,0 -- Header (2048), i (2), Pos (4), in the
  release's declaration order laid out downward from BP.

  THE ONE REAL DIFFERENCE FROM THE RELEASE IS THE LOADER COUNT, and it is a
  single instruction: 14b9:00b8 is `CMP WORD PTR [BP-0802],0002`. 1.39b has
  NumLoaders = 8 and eight recognisers; 1.31 has TWO. See the table above.

  AND THE INDEXED CALL LANDS ON A REAL VARIABLE, WHICH IS A TRAP WORTH NAMING.
  00ec is `MOV DI,[i] / SHL DI,2 / CALLF [DI+03c0]`, so the displacement is
  $03c0 -- and `ModOffset` is the LongInt at DS:$03c0, which LoadFName pushes by
  name at 0242. They are not the same object. `SongLoaders` is
  `array[1..2]` of a four-byte procedure pointer, so its BASE-1 base is one
  element low: the array itself starts at DS:$03c4 and $03c0 is what the
  compiler subtracts to index it. `ModOffset` simply happens to occupy those
  four bytes. **A displacement that matches a known variable is not evidence
  that the code touches it** -- check the index scaling first. Same rule as the
  six base-1 arrays in 12ba, with a coincidence on top. }
procedure TSong.Load(var St : TStream);
var
  Header : TSongHeader;
  i      : Word;
  Pos    : LongInt;
begin
  Pos := St.GetPos;                                  { 0053..0065            }

  ThereIsMore := 0;                                  { 0066..006d            }

  St.Read(Header, SizeOf(TSongHeader));              { 006e..0081            }

  if St.Status <> stOk then                          { 0082..008b            }
    begin
      Status    := msFileDamaged;                    { 008c..0093            }
      ErrorCode := St.ErrorInfo;                     { 0094..00a1            }
      St.Done;                                       { 00a2..00af            }
      Exit                                           { 00b0                  }
    end;

  i := 1;                                            { 00b2..00b7            }
  while (i      <= NumLoaders) and                   { 00b8..00be            }
        (Status  = msNotLoaded) do                   { 00bf..00c8            }
    begin
      St.Seek(Pos);                                  { 00c9..00db            }
      SongLoaders[i](PSong(@Self)^, St, Header);     { 00dc..00f6            }
      Inc(i)                                         { 00f7..00fa            }
    end
end;

{ 0100..02c1.  RETF 8, ENTER 01ae,0.  The release's body verbatim.

  THE FRAME IS THE RELEASE'S DECLARATION ORDER, laid out downward from the value
  parameter's copy, and every offset checks:

    [BP-0050]  FName   the value PathStr copy -- 80 bytes, and 010a's PUSH 004f
                       is String[79], which is PathStr exactly
    [BP-0058]  St      8 bytes, TDosStream
    [BP-009c]  Dir     68 bytes, DirStr = String[67] -- the same arithmetic that
                       settled DirStr in 116e
    [BP-00aa]  IPath   13 bytes, String[12]
    [BP-00ac]  OSongStart      [BP-00ae]  OSongLen
    [BP-01ae]  a 256-byte compiler string TEMPORARY -- not a local. Inventing a
               variable to explain it is the mistake 1b54 and 164b both made.

  AND A STRING FUNCTION'S RESULT POINTER IS REUSED AS THE ASSIGNMENT'S SOURCE.
  `IPath := GetInsidePath` at 0131 pushes the temp's address, calls, and then
  pushes only ONE more pointer before the string-assign helper -- because the
  result pointer is still on the stack. The callee did not pop it: that is what
  `RETF 4` on a string function means, seen from the caller's side. Same shape
  again at 017b for `FName := FExpand(FName)`.

  FOUR OFFSETS ARE CONFIRMED A SECOND TIME HERE. 0197 passes `Self+$16` and
  `Self+$1f` straight to `FSplit` as its NameStr and ExtStr, which is what those
  two fields are; 01c6 stores HNewStr's result into `+$12`, which is FileDir;
  and 01ec's `PUSH 0004` is `FileExt := '.MOD'` against a String[4].

  `msFileOpenError` IS NOW SEEN STORED. The constant list has carried it as
  "not seen stored yet" since the reading pass; 14b9:025e writes 3 into `+$59`
  on the stream-open failure path. }
procedure TSong.LoadFName(FName : PathStr);
var
  St         : TDosStream;
  Dir        : DirStr;
  IPath      : String[12];
  OSongStart : Word;
  OSongLen   : Word;
begin
  OSongStart := SongStart;                           { 011b..0125            }
  OSongLen   := SongLen;                             { 0126..0130            }
  IPath := GetInsidePath;                            { 0131..014c            }
  Empty;                                             { 014d..0155            }
  SetInsidePath(IPath);                              { 0156..0164            }
  SongStart := OSongStart;                           { 0165..016f            }
  SongLen   := OSongLen;                             { 0170..017a            }

  FName := FExpand(FName);                           { 017b..0196            }
  FSplit(FName, Dir, FileName, FileExt);             { 0197..01b8            }
  FileDir := FullHeap.HNewStr(Dir);                  { 01b9..01d3            }
  if FileExt = '' then FileExt := '.MOD';            { 01d4..01f2            }
  FName := Dir + FileName + FileExt;                 { 01f3..022b            }

  St.Init(FName, stOpenRead);                        { 022c..0241            }
  St.Seek(ModOffset);                                { 0242..0254            }

  if St.Status <> stOk then                          { 0255..025a            }
    begin
      Status    := msFileOpenError;                  { 025b..0262            }
      ErrorCode := St.ErrorInfo;                     { 0263..026c            }
      St.Done;                                       { 026d..027a            }
      Exit                                           { 027b                  }
    end;

  Status    := msNotLoaded;                          { 027d..0284            }
  ErrorCode := 0;                                    { 0285..028d            }

  Load(St);                                          { 028e..029b            }

  if Status <> msOK then                             { 029c..02a5            }
    ErrorCode := St.ErrorInfo;                       { 02a6..02af            }

  St.Done                                            { 02b0..02bd            }
end;

{ 02c2..02f4.  RETF **4**, not 8: Turbo Pascal does not pop the hidden
  string-result pointer, the caller does, so `[BP+0a]` is the result and only
  Self is cleaned up. 116e's GetToken : STRING is RETF 4 for the same reason.
  02c8  MOV AX,ES:[DI+0a] / OR AX,ES:[DI+0c]    Name <> NIL, tested as one LongInt
  02d2  <Name^> / <result> / PUSH 00FF / CALLF 1ba1:0add    the string assign
  02ea  MOV byte ES:[DI],0                      the empty-string case }
function TSong.GetInsidePath : String;
begin
  if InsidePath <> nil then                          { 02c8..02d1            }
    GetInsidePath := InsidePath^                     { 02d2..02e7            }
  else
    GetInsidePath := ''                                    { 02ea..02f0            }
end;

{ 02f5..0351.  RETF 8, ENTER 0100,0 -- the 256-byte copy of the value String.
  02f9  the parameter copy, PUSH 00FF / CALLF 1ba1:0add
  030f  Name <> NIL again
  0319  ADD DI,0a / <the heap object at DS:39ae> / CALLF [DI+34]   HDisposeStr
  032c  CMP byte [BP-0100],0                    S <> ''
  0333  <S> / <the heap object> / CALLF [DI+30] / store to +$0a    HNewStr
  HDisposeStr takes the ADDRESS of the field (`ADD DI,0a` then PUSH ES/DI), so
  it is a var parameter; that is the release's declaration too. }
procedure TSong.SetInsidePath(S : String);
begin
  if InsidePath <> nil then
    FullHeap.HDisposeStr(InsidePath);                      { 0319..032b            }

  if S <> '' then
    InsidePath := FullHeap.HNewStr(S)                      { 0333..034d            }
end;

{ 0352..0403.  RETF 6, ENTER 000c,0 -- result, Instrument, j, and the FOR limit.
  The release's body verbatim. Three things in it are worth reading off:

  0359  MOV AX,ES:[DI+2f] / CWD / ... / XOR DX,DX / CMP DX,BX / JG / JL / CMP AX,CX
        `i >= Instruments.Count` as a 32-bit compare, because Count is a SIGNED
        Integer and i is an unsigned Word. This is what fixes Count's type.
  0383  MOV [BP-0a],AX / JMP 038b / INC [BP-0a]      Borland's FOR
  03a4  MOV AX,0566 / PUSH AX / <Instrument> / CALLF 165a:0000
        THE $0566 IS THE VMT OFFSET, NOT A PARAMETER. `Instrument^.Init` is a
        CONSTRUCTOR, so it carries the hidden VMT word -- and this one is a real
        construction, where Init's own `TObject.Init` at 000c pushes ZERO because
        an inherited call must not re-stamp the VMT.
  0390  PUSH 000a / <the heap at DS:397e> / CALLF [DI+08]     Heap.HGetMem, 10 }
function TSong.GetInstrument(i : Word) : PInstrumentRec;
var
  Instrument : SongElements.PInstrument;
  j          : Word;
label
  Break;
begin
  if i >= Instruments.Count then                     { 0356..0370            }
    begin
      for j := Instruments.Count to i do             { 0371..038a, 03cd..03d4 }
        begin
          Heap.HGetMem(Pointer(Instrument),
                       SizeOf(SongElements.TInstrument));   { 038b..039b     }
          if Instrument <> nil then                  { 039c..03a3            }
            begin
              Instrument^.Init;                      { 03a4..03b1            }
              Instruments.AtInsert(j, Instrument)     { 03b2..03c8           }
            end
          else
            goto Break                               { 03cb                  }
        end;
Break:
      GetInstrument := PInstrumentRec(Instrument)     { 03d5..03e2           }
    end
  else
    GetInstrument := PInstrumentRec(Instruments.At(i)) { 03e3..03f9          }
end;

{ 0404..04b5.  RETF 6.  The same body against Tracks at +$4d.
  0442  PUSH 000e   SizeOf(TTrack) -- VMT + Name + Note + Comm
  0456  MOV AX,056e / ... / CALLF 165a:081d     TTrack.Init, VMT offset $056e }
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

{ 04b6..0574.  RETF 6.  The same body again, against Patterns at +$41 -- and its
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

{ 0575..059e.  RETF 6, ENTER 4,0 -- the four bytes are the pointer result slot.
  0579  PUSH [BP+0a] / <Self> / PUSH CS / CALL 059f     GetPatternSequence
  0585  PUSH AX      / <Self> / PUSH CS / CALL 04b6     GetPattern
  058f  store to [BP-4]/[BP-2], reload
  One statement, nested, exactly as the release writes it. }
function TSong.GetPatternSeq(i : Word) : PPattern;
begin
  GetPatternSeq := GetPattern(GetPatternSequence(i))  { 0579..059a           }
end;

{ 059f..05d2.  RETF 6, ENTER 2,0.
  05a6  MOV AX,ES:[DI+39] / OR AX,ES:[DI+3b]    PatternSequence <> NIL
  05b0  MOV AX,[BP+0a] / LES DI,ES:[DI+39] / ADD DI,AX / MOV AL,ES:[DI-1]
  THE `-1` IS THE ARRAY'S BASE: TPatternSequence is `array[1..MaxSequence]`.
  05c0  XOR AH,AH                                the result is a WORD
  05c7  XOR AX,AX                                the NIL case }
function TSong.GetPatternSequence(Seq : Word) : Word;
begin
  if PatternSequence <> nil then
    GetPatternSequence := PatternSequence^[Seq]       { 05b0..05c4            }
  else
    GetPatternSequence := 0                          { 05c7..05cb            }
end;

{ 05d3..0606.  RETF 6, ENTER 2,0 -- the same shape against +$3d.
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

{ 0607..0686.  RETF 14 -- Seq, Row, Chan (6) + var Note (4) + Self (4), so
  Self is [BP+06], Note [BP+0a], Chan [BP+0e], Row [BP+10] and Seq [BP+12].
  ENTER 000c,0 is the release's FOUR locals -- Patt, Track, n and NOffs -- and
  `NOffs` is declared because the frame is twelve bytes and the other three
  account for ten. Nothing reads it. Declaring only three would shorten every
  [BP-n] below it.

  0632  MOV AX,[BP+0e] / SHL AX,1 / LES DI,[BP-04] / LES DI,ES:[DI+06]
        ADD DI,AX / MOV AX,ES:[DI+02]
  THE `+02` IS A BASE-1 ARRAY, not a field. TPatternRec is NNotes, NChans,
  Tempo, BPM and then `Channels : array[1..MaxChannels] of Word` at +$04, so
  `Channels[Chan]` is `+04 + (Chan-1)*2` = `+02 + Chan*2`. One element low,
  which is the rule six of 12ba's arrays were identified by.

  0673  JMP 0683   the release's `EXIT` -- straight to LEAVE, skipping FillChar
  0675  PUSH 0006 / PUSH 0000 / CALLF 1ba1:0fd5     FillChar, SizeOf = 6 }
procedure TSong.GetNote(Seq, Row, Chan : Word; var Note : TFullNote);
var
  Patt  : SongElements.PPattern;
  Track : SongElements.PTrack;
  n     : Word;
  NOffs : Word;                  { the frame's last two bytes; never read }
begin
  if PatternSequence <> nil then                     { 060b..0617            }
    begin
      Patt := SongElements.PPattern(GetPatternSeq(Seq));   { 0618..0629      }
      if Patt <> nil then                            { 062a..0631            }
        begin
          n     := Patt^.Patt^.Channels[Chan];       { 0632..0646            }
          Track := SongElements.PTrack(GetTrack(n)); { 0647..0658            }
          if Track <> nil then                       { 0659..0660            }
            begin
              { The two TFullNote declarations are the SAME SIX BYTES and a
                different name: SongElements' is a variant record whose first
                branch is field for field this unit's. Pascal is name-equivalent
                for a var parameter, so the call needs the cast. Aliasing the
                two types instead would be tidier and is NOT done -- PLAYMOD
                writes `Note.Command := 0` and compares it against 4 and 6,
                which a TModCommand enumeration rejects. That is a rename in
                two byte-exact units and belongs in its own pass. }
              Track^.GetNote(Row, SongElements.TFullNote(Note));  { 0661..0672 }
              Exit                                   { 0673                  }
            end
        end
    end;

  FillChar(Note, SizeOf(Note), 0)                    { 0675..0682            }
end;

{ 0687..072e.  RETF 4, ENTER 0002,0 -- the release's `i : WORD`, which nothing
  reads; declaring it is what makes the frame two bytes rather than none.

  EIGHT CALLS, AND THEIR OPERANDS ARE WHAT NAME THE POINTER FIELDS. Every one
  is `LES DI,[BP+06] / ADD DI,<offset> / PUSH ES / PUSH DI`, so the field's
  ADDRESS is passed -- a var parameter -- and the offset is in the instruction:

    069c  +$06        CALLF [DI+34]   HDisposeStr   Name
    06b2  +$0e $03d0  CALLF [DI+0c]   HFreeMem      Comment
    06c5  +$12        CALLF [DI+34]   HDisposeStr   FileDir
    06d7  +$29        CALLF [DI+04]   Done          Instruments
    06ed  +$39 $0100  CALLF [DI+0c]   HFreeMem      PatternSequence
    0703  +$3d $0100  CALLF [DI+0c]   HFreeMem      PatternTempos
    0715  +$41        CALLF [DI+04]   Done          Patterns
    0727  +$4d        CALLF [DI+04]   Done          Tracks

  THE $03d0 IS THE ONE THAT SETTLES IT: `SizeOf(TSongComment)` is
  `16 * 61` = 976 = $3d0 exactly, so +$0e is the comment block. With Comment
  pinned, the release's three-statement order fixes `Name` at +$06 and
  `FileDir` at +$12 -- and that is what corrected `+$0a`, which had been named
  `Name` from SetInsidePath alone. **+$0a IS `InsidePath`**: 1.31 keeps the
  InsidePath pair and drops GetName/SetName, not the other way round, and
  `Free` not touching +$0a is the release's behaviour too.

  `[DI+04]` IS `TObject.Done`, the FIRST virtual slot -- a TP VMT holds the
  positive and negative size words at +$00 and +$02 and the first virtual method
  at +$04 -- so three calls to it are three collections being destroyed.

  AND IT USES `FullHeap` WHERE GetInstrument USES `Heap`. DS:$39ae here,
  DS:$397e there, which is exactly how the release writes the two routines.
  Neither can be measured from the bytes -- a DGROUP address is a fixup -- so
  this is the release settling a question the binary cannot. }
procedure TSong.Free;
var
  i : Word;                      { the frame's two bytes; never read }
begin
  asm cli end;                                       { 068b                  }

  FullHeap.HDisposeStr(Name);                        { 068c..069e            }
  FullHeap.HFreeMem(Pointer(Comment), SizeOf(Comment^));    { 069f..06b4     }
  FullHeap.HDisposeStr(FileDir);                     { 06b5..06c7            }

  Instruments.Done;                                  { 06c8..06d9            }

  FullHeap.HFreeMem(Pointer(PatternSequence),
                    SizeOf(PatternSequence^));       { 06da..06ef            }
  FullHeap.HFreeMem(Pointer(PatternTempos),
                    SizeOf(PatternTempos^));         { 06f0..0705            }
  Patterns.Done;                                     { 0706..0717            }

  Tracks.Done;                                       { 0718..0729            }

  asm sti end                                        { 072a                  }
end;

{ 072f..0896.  RETF 4, no frame -- PUSH BP / MOV BP,SP, so no locals at all.

  THIS IS THE ROUTINE THAT NAMED THE RECORD. It initialises every field, in the
  release's order, so its stores ARE the declaration read off the binary -- which
  is a far stronger instrument than any single accessor. Nine fields that were
  filler or an address-for-a-name are named from it, and the record's total size
  falls out of where it stops.

  THE RELEASE'S LAST STATEMENT IS ABSENT. 1.39b ends with `PanPositions := DefPan`
  and there is no trace of it here: 088e writes +$5d and the next instruction is
  LEAVE. 1.31 keeps pan in 12ba -- `12ba:0275` writes it per channel -- so the
  song does not carry a pan table. That also means no 32-byte typed constant in
  this unit, which is consistent with census.py finding no data here.

  THE THREE COLLECTION LIMITS ARE THE RELEASE'S EXACTLY: (32,32), (64,64) and
  (256,256), pushed as immediates at 07b0, 0844 and 085a. Unlike `NumBuffers` in
  12ba -- where the release's 3 was 1.39b's and 1.31's was 1 -- these three
  counts did carry over, so this is a case where the release's DATA happened to
  be right. It was still checked rather than copied. }
procedure TSong.InitValues;
begin
  SongStart := 1;                                    { 0732..073a            }
  SongLen   := MaxSequence;                          { 073b..0743            }

  Name       := nil;                                 { 0744..0750            }
  InsidePath := nil;                                 { 0751..075d            }
  Comment    := nil;                                 { 075e..076a            }
  FileDir    := nil;                                 { 076b..0777            }

  FileName  := '';                                   { 0778..077f            }
  FileExt   := '';                                   { 0780..0787            }
  FirstTick := 0;                                    { 0788..078f            }

  InitialTempo := 1;                                 { 0790..0797            }
  InitialBPM   := 1;                                 { 0798..079f            }
  Volume       := 0;                                 { 07a0..07a7            }
  NumChannels  := 0;                                 { 07a8..07af            }

  Instruments.Init(32, 32);                          { 07b0..07c5            }

  SequenceLength   := 0;                             { 07c6..07ce            }
  SequenceRepStart := 0;                             { 07cf..07d7            }

  FullHeap.HGetMem(Pointer(PatternSequence),
                   SizeOf(PatternSequence^));        { 07d8..07ed            }
  FullHeap.HGetMem(Pointer(PatternTempos),
                   SizeOf(PatternTempos^));          { 07ee..0803            }
  if PatternSequence <> nil then
    FillChar(PatternSequence^, SizeOf(PatternSequence^), 0);  { 0804..0823   }
  if PatternTempos <> nil then
    FillChar(PatternTempos^, SizeOf(PatternTempos^), 0);      { 0824..0843   }
  Patterns.Init(64, 64);                             { 0844..0859            }

  Tracks.Init(256, 256);                             { 085a..0871            }

  Status      := msNotLoaded;                        { 0872..0879            }
  ErrorCode   := 0;                                  { 087a..0882            }
  ThereIsMore := 0;                                  { 0883..088a            }
  FileFormat  := mffUnknown;                         { 088b..0892            }

  { 0893..08a7 -- NEW IN v1.51, and the LAST statement of InitValues.

      153a:0893  MOV DI,0440 / PUSH DS / PUSH DI      the source constant
      153a:0898  LES DI,[BP+06] / ADD DI,0029         Self.ChannelPan
      153a:08a1  PUSH 20                              32 bytes
      153a:08a3  CALLF 1d89:09f7                      the ASSIGNMENT copy helper

    It must compile to 09f7 and not to 0fb2. Both are copy loops eleven bytes
    apart in SYSTEM; 0fb2 is `Move` and compares the pointers so it can copy
    backwards on overlap, 09f7 is the one the compiler emits for a whole-array
    assignment between two operands of the same NAMED type, where it knows they
    are distinct. See `TChannelPan`. }
  ChannelPan := DefaultChannelPan                    { 0893..08a7            }
end;

{ 0897..08ac.  RETF 4.  The release's `Free; InitValues;` and the last routine
  in both. Written for real because it depends on nothing: two calls. }
procedure TSong.Empty;
begin
  Free;
  InitValues
end;

end.
