{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  Segment 109c -- THE COMMAND-LINE SWITCHES. 3,296 bytes, twenty-two routines.

  COMPLETE. All 3,296 bytes, 484 pending fixups, from the release's bodies in five builds.

  FIVE THINGS HAD TO BE MEASURED, and every one was a jump displacement first:

      SetVTDevice loses three statements    no DeviceSet guard, no UsingGUS := FALSE,
                                           no GUS fallback -- the `then` is EMPTY
      NumExts is 7, not 6                  eight extensions, read out of the DATA image
      DoSongColl clears ModOffset          eight bytes at 079f the release lacks
      CmdInitShell calls SkipRest          which is what NAMED 116e's extra virtual
      CmdInitFreq has ONE Val              the release's duplicate line is not here

  THE COUNTERPART IS `VTCMD.PAS`, measured at 42.1% by `demovt/relmatch.py`. It is
  `116e`'s DESCENDANT -- two descendants, in fact -- and it is the unit that finally
  explained `116e`'s missing two routines.

  **`census.py` MAPPED ALL TWENTY-TWO ROUTINES AND ALL TWENTY-ONE SWITCH BRANCHES, and
  the switch table did most of the work.** `109c:0844..088f` is a solid run of
  length-prefixed Pascal strings and it is the whole switch vocabulary:

      0844 'nobf'  0849 'bfil'  084e 'nolp'  0853 'loop'  0858 'nofl'  085d 'port'
      0862 'irq'   0866 'dma'   086a 'off'   086e 'flp'   0872 'lq'    0875 'hq'
      0878 'ss'    087b 'sl'    087e 'sr'    0881 'sh'    0884 'nx'    0887 'nb'
      088a 'd'     088c 'f'     088e 'v'

  **TWENTY-ONE NAMES, ENDING EXACTLY WHERE `InterpretSwitch` BEGINS at 0890, and
  `census.py` counts exactly twenty-one `CALLF [DI+18]`** -- one CmpSwitch per name, in
  this order. The release's list is the same but for three changes:

      'frst' is ABSENT          and so is CmdInit1stSong, the only thing it called
      'nx' and 'nb' are NEW     inserted after 'sh', each calling a new procedure

  AND THE BRANCHES NAME EVERY LOCAL ROUTINE, because each one calls exactly one and the
  near-call targets are unambiguous. Pairing the CmpSwitch sites with the table in order
  gives the routine behind each switch, and the frame sizes then confirm each in turn:

      'd'  -> 03fb  ENTER $100   CmdInitDevice      (a String parameter, no locals)
      'f'  -> 0435  ENTER $104   CmdInitFreq        (a String plus i, r)
      ...  -> 055f  ENTER $106   CmdModOffset       (a String plus l : LONGINT and r)
      'sh' -> 0b7c  CALLF [DI+2c]  CmdInitShell     -- see below, it is the KEY
      'nx' -> 06d3  PUSH BP, near RET, no parameters   NEW
      'nb' -> 05b2  PUSH BP, near RET, no parameters   NEW

  **`109c:0b7c` IS WHAT RESOLVED `116e`'s OPEN QUESTION.** It is a `CALLF [DI+2c]`, and
  +$2c is the first virtual `TVTCmdSwitch` ADDS to what it inherits. A new virtual at
  +$2c means the inherited ones stop at +$28 -- so `TCmdLineInterpreter` really does
  declare nine virtuals, and `116e`'s eight bodies really are one short of two. The
  answer is the LINKER: `109c` overrides both `InterpretNoSwitch` and `InterpretSwitch`,
  and `TCmdLineInterpreter` is never instantiated, so the base's own VMT is dead and
  nothing anywhere refers to those two empty bodies. Turbo Pascal smart-links per
  routine, and they are gone. See CMDLINE.PAS and docs/CONTINUATION.md.

  THE FAR AND NEAR CALL COUNTS AGREE WITH THE RELEASE'S `DoAllMODs` TERM FOR TERM:

      116a:0000  AddBar2Path  x3   Dirs[0], Dirs[3] and DefaultPath -- exactly three
      1b6f:0178  FExpand      x4   Dir, ModPath, DefaultPath, Path
      1b6f:0241  FSplit       x2
      1b6f:0000  FindFirst    x1   and 1b6f:003e FindNext x1
      1a17:0248  LocateDevice x1   from SetVTDevice at 0000
      1a17:018c  SetDevice    x1   also SetVTDevice
      12ba:132f  ChangeSamplingRate x1  from SetVTFreq at 0038

  AND `1ba1:0f81` -- `Val` -- IS CALLED NINE TIMES FOR NINE ROUTINES. The release's
  `CmdInitFreq` has `VAL(s, i, r);` written TWICE in a row, plainly by accident; 1.31 has
  it once. One Val per routine, and the count is what says so.
  =========================================================================== }
unit VTCmd;

interface

{ ~~DevGUS~~ IS NOT A DEPENDENCY OF THIS UNIT, and the LINK ORDER is what says so.
  The original's segments put `1084`/DevGus at position 3 and `109c`/VTCmd at 4, and
  TP6 lays segments out in reverse DFS post-order over the `uses` graph -- so DevGus
  finishes AFTER VTCmd and cannot be something VTCmd uses. Checked against the source
  before removing it: not one identifier from DevGus is named anywhere in this file,
  so the clause entry was never doing anything. `demovt/linkorder.py` is the check. }
uses
  Dos, Objects,
  VTDriver, SoundDevices,
  VTGlobal, CmdLine;

type
  TDoOneProc = function(FName, InsidePath : PathStr) : Boolean;

  { THE RELEASE DECLARES `TSoundDevice.Autodetect` AS `FUNCTION : BOOLEAN` and this
    project declares it as a raw `Pointer` -- see the long note in VTDRIVER.PAS, which
    records the sense of the result and the two producers that agree on it. This type
    exists only so `SetVTDevice` can call through that field without changing a
    declaration two byte-exact units assign to. }
  TAutodetectFunc = function : Boolean;

{ A TYPED CONSTANT WITH A VARIABLE OVERLAID ON IT, which is how 1993 Pascal gets an
  initialised procedural variable: `TDoOneProc` cannot be given a value in a `const`
  section, but a `POINTER` can, and `ABSOLUTE` then reinterprets the same four bytes. }
const
  OneModPtr  : Pointer = nil;
var
  OneMODProc : TDoOneProc absolute OneModPtr;

type
  TCmdOptions =
    record
      LowQuality : Boolean;
      DevID      : TDevID;
      Freq       : Word;
      Volume     : Word;
    end;

  { TWO DESCENDANTS, NOT ONE, and the split is what makes `116e`'s two empty overrides
    unreachable. `TVTCmdSwitch` overrides InterpretSwitch and adds four virtuals of its
    own; `TVTCmd` then overrides InterpretNoSwitch. Between them every slot the base
    left empty is filled by a routine in THIS segment. }
  TVTCmdSwitch =
    object(TCmdLineInterpreter)
      procedure CmdInitShell     (Shell : String);        virtual;  { VMT +$2c }
      procedure InterpretSwitch  (Token : TCmdLine);      virtual;  { VMT +$28 }
      procedure GetCmdOptions    (var Opt : TCmdOptions); virtual;  { VMT +$30 }
      procedure SetCmdOptions    (var Opt : TCmdOptions); virtual;  { VMT +$34 }
    end;

  TVTCmd =
    object(TVTCmdSwitch)
      procedure InterpretNoSwitch(Token : TCmdLine); virtual;       { VMT +$24 }
    end;

var
  Cmd      : TVTCmd;      { DS:$0ef6  VMT $009e -- 1000:05b2 }

  { A PLAIN `TCollection`, AND THE CONSTRUCTOR IS WHAT SETTLES IT. This was
    declared a `TStringCollection` on the strength of holding strings, and
    `1000:05cd` far-calls `1891:03a7`, which this tree has established as
    `TCollection.Init` (it is the target of `InitValues`'s three `Init(n,n)`
    calls in 14b9). A TStringCollection's `Init` is TSortedCollection's and is a
    different routine at a different address, so the object cannot be one.
    Everything this unit does to it agrees: `AtInsert(Count, NewStr(Token))` is
    how you append to an UNSORTED collection -- a sorted one takes `Insert` and
    would not be given a position -- and `DoSongColl` reads it back through an
    explicit `PString(...)^` cast, which a string collection would not need.
    Eighth interface detail settled by a caller in another segment. }
  { A `TStringCollection`, AND THE LINKED IMAGE IS WHAT SETTLED IT -- after this file
    had argued the opposite and been WRONG.

    THE EARLIER ARGUMENT, now withdrawn: `1000:05cd` far-calls `1891:03a7`, which this
    tree established as `TCollection.Init` (it is the target of `InitValues`'s three
    `Init(n,n)` calls in 14b9), and a TStringCollection's constructor was assumed to be
    TSortedCollection's own. It is not. **TP6's `Objects` gives TSortedCollection no
    `Init` of its own**, so a TStringCollection INHERITS `TCollection.Init` and the call
    at 05cd is exactly what a TStringCollection produces. The supporting points were
    just as weak: `AtInsert` and a `PString(...)^` cast are both legal on a sorted
    collection, they are simply not the idiomatic way to use one.

    WHAT SETTLED IT IS A VMT. Turbo Pascal lays an object type's VMT down in DGROUP,
    and the original's initialised image holds THREE `Objects` VMTs of sizes 8, 12 and
    13 -- while ours held only the first two. Size 12 is `TCollection` (VMT 2 + Items 4
    + Count 2 + Limit 2 + Delta 2) and size 13 is that plus `Duplicates`, which is
    TSortedCollection exactly; its method table has three more entries than
    TCollection's and shares its first two, which is what a descendant looks like.
    Declaring this one a TStringCollection recovers all 48 bytes and the block then
    matches. **A VMT is measurable data, and it names a type that no call site could.**

    So `demovt/dgroup.py` has now found something no byte comparison and no call-site
    reading could: an object's TYPE, from the size word of its virtual method table. }
  SongColl : TStringCollection; { DS:$1040  VMT $07fe -- 1000:05c4 }

procedure SetVTFreq;
procedure SetVTDevice;

function DoSongColl(Path : PathStr) : Boolean;


implementation

{ The release also uses `VTScreens`, which 1.31 has not got. `SongUnit` IS needed and
  was not here: `CmdModOffset` assigns `ModOffset`, which the DGROUP layout has just
  moved out of VTGlobal and into SongUnit -- $03c0 is four bytes below SongUnit's own
  `SongLoaders` at $03c4. Adding it cannot move a segment, because everything in this
  clause is already reached through `PlayMod` before the walk gets here; the order was
  re-checked with `demovt/linkorder.py` either way. }
{ VTSilenc BEFORE FileUtil, AND THE LINK ORDER IS THE ONLY REASON. The two are
  unrelated and either order compiles; the original's segments run FILEUTIL then
  VTSILENC then CMDLINE, and reverse post-order means FileUtil has to finish LAST of
  the three. See VTMAIN's uses clause for the other half of the change. }
uses
  SoundBlaster, VTShell, SongUnit, SongElements, PlayMod, GUS,
  VTSilenc, FileUtil, Heaps, VTCtrl;


{ ===========================================================================
  109c:0000 and 109c:0038 -- the two device/rate helpers. Both are in the INTERFACE, so
  both are FAR, and both take no parameters -- which is exactly the two `RETF` with no
  count that `census.py` finds at `0037` and `0045`, the only two in the segment.
  =========================================================================== }

{ --------------------------------------------------------------------------
SetVTDevice, and THREE STATEMENTS OF THE RELEASE'S ARE ABSENT. Fifty-four
  bytes, and every one of them accounted for:

      0003  MOV DI,0882 / PUSH DS / PUSH DI     DevID -- DS:$0882, agreeing with 11bb
      0008  CALLF 1a17:0248                     LocateDevice
      000d  MOV [087e],AX / MOV [0880],DX       DevPtr := ...  -- DS:$087e, NEW
      0014  MOV AX,[087e] / OR AX,[0880]        DevPtr = nil ?
      001b  JZ  0029                            ... then skip to SetDevice
      001d  LES DI,[087e] / CALLF ES:[DI+1a]    DevPtr^.Autodetect
      0025  OR AL,AL / JNZ 0029                 ... then skip to SetDevice
      0029  PUSH [0880] / PUSH [087e]
      0031  CALLF 1a17:018c                     SetDevice(DevPtr)

  **`if DeviceSet then Exit` IS GONE, `UsingGUS := FALSE` IS GONE, AND SO IS THE GUS
  FALLBACK.** The release, failing to find the configured device, tries the Gravis anyway;
  1.31 evaluates the same condition and does nothing with it.

  **THE `then` BRANCH IS EMPTY, AND THE BYTES PROVE IT RATHER THAN SUGGEST IT.** The `JZ`
  at `001b` and the `JNZ` at `0027` both target `0029`, and the JNZ's displacement is
  literally ZERO -- it jumps to the next instruction. Both arms of a short-circuit `or`
  arriving at the same address with nothing in between is what an empty statement compiles
  to, and `VTDRIVER.PAS` had already flagged this exact `75 00` as looking like a test and
  not being one.

  SO IT IS THE `if C then;` IDIOM, which this author uses elsewhere -- `116e`'s ParseFile
  has `if IOResult <> 0 then;` twice, to consume an I/O result. Here it consumes an
  autodetect result, and the effect is that **`SetDevice` is handed whatever LocateDevice
  returned, nil included.** Half-finished rather than clever, and transcribed as found.
  -------------------------------------------------------------------------- }
procedure SetVTDevice;
begin
  DevPtr := LocateDevice(DevID);

  if (DevPtr = nil) or not TAutodetectFunc(DevPtr^.Autodetect) then;

  SetDevice(DevPtr)
end;


{fourteen bytes: `PUSH [0bae] / CALLF 12ba:132f`, and `DS:$0bae` is
  `DesiredHz` exactly where SOUNDDEV.PAS already documents it. }
procedure SetVTFreq;
begin
  ChangeSamplingRate(DesiredHz)
end;


{ ---------------------------------------------------------------------------
DoAllMODs. Find every module matching a pattern, across a list of
  directories and a list of extensions, and hand each to a caller-supplied procedure.

  IT IS NEAR, not far -- it is not in the interface -- and `RET 12` is its signature:
  two `PathStr` value parameters at four bytes each plus a four-byte procedural
  parameter. `ENTER $284` is the frame.

  **`DoOne` IS CALLED THROUGH `[BP+04]`**, and `census.py` finds exactly one such site,
  at `03c0`. A procedural parameter is a frame slot, not a VMT slot, which is why it
  shows up in the same scan as the virtual calls and why it is the only `[BP+nn]` there.

  THE DIRECTORY LIST IS SEARCHED IN A DELIBERATE ORDER and deduplicated first. If the
  pattern carried a directory, that directory is the only one tried; otherwise it is the
  caller's default, then the pattern's own expansion, then `ModPath` from the config
  file. The `Dirs` array is declared at four entries and only ever holds three, because
  index 0 is the explicit-directory case and indices 1..3 the searched list.

  **THE DEDUPLICATION USES A `GOTO` OUT OF A NESTED LOOP and it is the release's.** Turbo
  Pascal has no `continue`, so `GOTO Sigue` -- Spanish for "carry on" -- jumps to a label
  at the end of the outer loop body. Note it reuses `i` as both the comparison index and
  the shifting index, so the inner loop's counter is destroyed on a match; it works only
  because the `GOTO` leaves immediately afterwards.

  `Exts[0]` AND `Dirs[0]` ARE ASSIGNED TO, so both arrays are typed constants and live in
  DGROUP rather than the code segment. That is why 3,296 bytes contain no `'.MOD'` and no
  `'.669'` -- the strings are initialised data, and the only text in the segment is the
  switch table.

  `'.123'` AT `Exts[0]` IS A PLACEHOLDER that is always overwritten before use: the
  explicit-extension branch assigns `Exts[0] := Ext` and sets both bounds to zero.
  --------------------------------------------------------------------------- }
function DoAllMODs(DefaultPath : PathStr; Path : PathStr; DoOne : TDoOneProc) : Boolean;
const
  { EIGHT EXTENSIONS, NOT THE RELEASE'S SEVEN, and the array is READ OUT OF THE IMAGE
    rather than guessed. `109c:02e0` is `MOV word [BP-0150],0007` where ours had 0006 --
    that is `ExtL := NumExts` -- and the initialised data sits at file offset $00d7b5 in
    the unpacked EXE, immediately before the four empty `Dirs` strings:

        04 '.123'  04 '.MOD'  04 '.STM'  04 '.WOW'
        04 '.OKT'  04 '.S2M'  04 '.S3M'  04 '.669'

    **THE RELEASE USES A WILDCARD WHERE 1.31 SPELLS BOTH OUT.** 1.39b has `'.S?M'`, one
    entry covering ScreamTracker 2 and 3; 1.31 lists `.S2M` and `.S3M` separately. It also
    has `.STM` where the release has `.STX`. So the release traded two entries for one and
    changed a third -- and 1.31 is the earlier, longer form.

    A TYPED CONSTANT ARRAY LIVES IN DGROUP, NOT THE CODE SEGMENT, which is why 3,296 bytes
    of `109c` contain no extension text at all and why this had to be read from the data
    image. `verify.py` compares code only, so **nothing here is checked by the byte
    comparison** -- only `NumExts` is, through that one immediate. }
  NumExts = 7;
  Exts : array[0..NumExts] of ExtStr =
    (
      '.123',

      '.MOD', '.STM', '.WOW', '.OKT', '.S2M', '.S3M', '.669'
    );

  Dirs : array[0..3] of PathStr =
    (
      '',
      '',
      '',
      ''
    );
var
  InsidePath : PathStr;
  Dir        : DirStr;
  Name       : NameStr;
  Ext        : ExtStr;
  DirIdx,
  DirF,
  DirL       : Word;
  ExtF,
  ExtL       : Word;
  i, j       : Word;
  SearchR    : SearchRec;
label
  Sigue;
begin
  DoAllMODs := True;

  i := Pos('/', Path);
  if i > 0 then
  begin
    InsidePath := Copy(Path, i + 1, 255);
    Path       := Copy(Path, 1,   i - 1);
  end
  else
    InsidePath := '';

  FSplit(Path, Dir, Name, Ext);
  if Dir <> '' then
  begin
    Dirs[0] := FExpand(Dir);
    AddBar2Path(Dirs[0]);
    DirF    := 0;
    DirL    := 0;
  end
  else
  begin
    Dirs[3] := FExpand(ModPath);
    AddBar2Path(Dirs[3]);

    DefaultPath := FExpand(DefaultPath);
    AddBar2Path(DefaultPath);
    Dirs[1] := DefaultPath;

    DirF := 1;
    DirL := 3;
  end;

  Path := FExpand(Path);
  FSplit(Path, Dir, Name, Ext);

  if DirF > 0 then
  begin
    Dirs[2] := Dir;

    for DirIdx := DirL downto 2 do
    begin
      for i := DirF to DirIdx - 1 do
        if Dirs[DirIdx] = Dirs[i] then
        begin
          for i := DirIdx to DirL - 1 do
            Dirs[i] := Dirs[i + 1];
          Dec(DirL);
          goto Sigue;
        end;
Sigue:
    end;
  end;


  if Ext <> '' then
  begin
    Exts[0] := Ext;
    ExtF    := 0;
    ExtL    := 0;
  end
  else
  begin
    ExtF := 1;
    ExtL := NumExts;
  end;

  Path := Dir + Name;



  { Loop for all MODs. }

  DoAllMODs := False;

  for j := DirF to DirL do
    for i := ExtF to ExtL do
    begin
      FindFirst(Dirs[j] + Name + Exts[i], ReadOnly, SearchR);

      while DosError = 0 do
      begin
        if not DoOne(Dirs[j] + SearchR.Name, InsidePath) then Exit;

        FindNext(SearchR);
      end;
    end;

  DoAllMODs := True;
end;


{ ===========================================================================
SIXTEEN NEAR PROCEDURES, one per switch action.

  THE ORDER IS THE ORIGINAL'S, NOT THE RELEASE'S, and it was read off the near-call
  targets rather than guessed: each CmpSwitch branch in `InterpretSwitch` calls exactly
  one of these, so pairing the branch order against the switch table names them all.
  1.31 groups the hardware switches (`port`, `irq`, `dma`, `off`) together near the top
  where the release puts the frequency and volume pair there.

  `ENTER $100` VERSUS `$104` VERSUS `$106` distinguishes them without disassembly: the
  256 is the value `String` parameter's frame copy, and what follows is the locals.
  =========================================================================== }

{ ===========================================================================
  **THE SWITCH HANDLERS, AND WHY MOST OF THEM GET NO COMMENT OF THEIR OWN.**
  Everything from here to the end of this section is one handler per command-line
  switch, called from InterpretSwitch when it recognises the switch's name. They
  come in exactly two shapes:

      procedure CmdSomething(s : String)    the switch carries a value
      procedure CmdSomething(f : Boolean)   the switch is on or off

  and the body of most of them is a single assignment into a global that
  something else reads later. `CmdForceLoop` sets `ForceLoopMod`; `CmdLowQuality`
  sets `LowQuality`. There is nothing to say about those that the line does not
  already say, and a header on each would be noise pretending to be
  documentation.

  SO THE ONES WITH COMMENTS BELOW ARE THE ONES WITH SOMETHING TO SAY -- a clamp,
  a parse that can fail, a switch whose effect is not where you would look for
  it. If a handler has no comment, it is because it needs none.

  THE STRING HANDLERS ALL BEGIN THE SAME WAY: `if s = '' then Exit`. A switch
  given without a value leaves its global untouched rather than setting it to
  zero, so `-freq` on its own is not an error and not a change. That is the
  convention; each one repeats it rather than sharing a helper.
  =========================================================================== }

{ENTER $100, so no locals at all, and it is the only one. }
procedure CmdInitDevice(s : String);
begin
  if s = '' then Exit;

  DevID := s;

  SetVTDevice;
end;


{ 109c:0435 -- ONE `Val`, WHERE THE RELEASE HAS `VAL(s, i, r);` TWICE IN A ROW. The
  duplicate is plainly accidental in 1.39b and 1.31 does not have it: `1ba1:0f81` is
  called nine times in this segment for nine routines that parse a number, so exactly
  one apiece. **The count is the whole argument.** }
procedure CmdInitFreq(s : String);
var
  i, r : Word;
begin
  if s = '' then Exit;

  Val(s, i, r);
  if r = 0 then
    DesiredHz := i;
end;


{ 109c:047c and 109c:04ca -- one port and one IRQ for both cards, because only one of
  them can be present. `off` at 0518's neighbour is the odd one out; see CmdModOffset. }
procedure CmdSetPort(s : String);
var
  i, r : Word;
begin
  if s = '' then Exit;

  Val(s, i, r);
  if r = 0 then
  begin
    SbPort  := i;
    GUSPort := i;
    {NEW IN v1.51. `/port:` now reaches the silence device's
      serial port as well as the two sound cards': a third
      `MOV AX,[BP-0102] / MOV [0200],AX` on the end of the same block. }
    ComPort := i;
  end;
end;


procedure CmdSetIRQ(s : String);
var
  i, r : Word;
begin
  if s = '' then Exit;

  Val(s, i, r);
  if r = 0 then
  begin
    SbIrq  := i;
    GUSIrq := i;
    {the same third store, for the IRQ. }
    ComIrq := i;
  end;
end;


{ Only the Sound Blaster has a DMA channel -- the Gravis does its own transfers -- so
  this one has no GUS half. }
procedure CmdSetDMA(s : String);
var
  i, r : Word;
begin
  if s = '' then Exit;

  Val(s, i, r);
  if r = 0 then
    SbDMAChan := i;
end;


{`ENTER $106`, the only one, and `l : LONGINT` is why: a module offset can
  exceed 64K because it is a byte position inside an archive or a bundled file. }
procedure CmdModOffset(s : String);
var
  l : LongInt;
  r : Word;
begin
  if s = '' then Exit;

  Val(s, l, r);
  if r = 0 then
    ModOffset := l;
end;


{THREE INSTRUCTIONS, and the release has nothing like it:

      55 89 e5           PUSH BP / MOV BP,SP
      c6 06 e8 09 01     MOV byte [09e8],1
      c9 c3              LEAVE / RET

  It is the `nb` switch, and `1000` is what names it: that segment tests `[09e8]` and
  skips a four-line banner when it is set. See the declaration of `NoBanner`. }
procedure CmdNoBanner;
begin
  NoBanner := True
end;


{and the clamp is to 255 because `VtVolume` is a BYTE, so an unchecked
  `Val` result would wrap. }
procedure CmdInitVolume(s : String);
var
  i, r : Word;
begin
  if s = '' then Exit;

  Val(s, i, r);
  if r = 0 then
  begin
    if i > 255 then i := 255;
    VtVolume := i;
  end;
end;


{ ---------------------------------------------------------------------------
THE FOUR BOOLEAN SWITCHES, and `RET 2` is their signature:
  one Byte-sized parameter in a word of stack, no frame beyond `PUSH BP`.

  EACH IS CALLED FROM TWO BRANCHES, once with False and once with True, which is what
  the pairs in the switch table are for -- `nolp`/`loop`, `nobf`/`bfil`, `lq`/`hq`. The
  exception is `nofl`/`flp`, where the two names are not adjacent in the table: `nofl` is
  fifth and `flp` tenth, with five hardware switches between them.
  --------------------------------------------------------------------------- }
procedure CmdLoopMod(f : Boolean);
begin
  VTLoopMod := f;
end;


procedure CmdForceLoop(f : Boolean);
begin
  ForceLoopMod := f;
end;


procedure CmdLowQuality(f : Boolean);
begin
  LowQuality := f;
end;


procedure CmdBassFilter(f : Boolean);
begin
  DoBassPower := f;
end;


{ 109c:0645, 068c and 06dd -- the three song-position switches: which pattern to start
  at, how long to play, and where to restart. `ss`, `sl` and `sr`. }
procedure CmdInit1stPattern(s : String);
var
  i, r : Word;
begin
  if s = '' then Exit;

  Val(s, i, r);
  if r = 0 then
    VT1stPattern := i;
end;


procedure CmdInitSongLen(s : String);
var
  i, r : Word;
begin
  if s = '' then Exit;

  Val(s, i, r);
  if r = 0 then
    VTSongLen := i;
end;


{the `nx` switch, and the same three instructions as CmdNoBanner but
  writing `[0bc6]`. **Nothing in any segment reads that byte**, so there is no behaviour
  to name the routine after; a switch that was wired up and left unfinished. Named for
  the switch, like every other handler in this file -- which is the honest answer when
  the only thing demonstrable about a routine is the token that reaches it. }
procedure CmdNx;
begin
  NxOption := True
end;


procedure CmdInitRepStart(s : String);
var
  i, r : Word;
begin
  if s = '' then Exit;

  Val(s, i, r);
  if r = 0 then
    VTRepStart := i;
end;


{ ---------------------------------------------------------------------------
DoSongColl. Play everything the command line collected.

  FAR, because it is in the interface, and `ENTER $056` is 80 bytes of `Path` copy plus
  six of locals. `SongColl` is filled by `TVTCmd.InterpretNoSwitch`, one entry per bare
  argument, and this is where the list is spent.

  **THE `GOTO` IS LOAD-BEARING AND `FreeAll` IS WHY.** Returning early on a failed
  `DoAllMODs` would leave the collection's strings allocated; jumping to a label just
  above `SongColl.FreeAll` frees them on both paths. Turbo Pascal has no `try..finally`,
  so a label is the whole mechanism.

  THE EMPTY CASE RETURNS TRUE, so a command line with no filenames is not an error --
  which is what lets `PSYCHO.EXE` pass only switches and let the config file name the
  module.
  --------------------------------------------------------------------------- }
function DoSongColl(Path : PathStr) : Boolean;
var
  i     : Word;
  Saved : LongInt;
label
  Fin;
begin
  DoSongColl := True;

  { NEW IN v1.51. `1086:074b` tests `[4821]` and jumps the whole body, epilogue
    included -- the `JMP` at `0752` reaches `0803`, which is `MOV AL,[BP-1] / LEAVE /
    RETF 4`. The result is already True by then, so the flag makes this succeed
    without doing anything. See the note on the variable in VTGlobal. }
  if CtrlBlock.Abort then Exit;

  { ~~THE EMPTY CASE JUST RETURNED TRUE~~ -- IN v1.51 IT RUNS THE SHELL.
    `1086:075c..0799` is the Turbo Pascal `Exec` idiom in full, and every part of it
    is forced:

      Saved := Heap.HTotalAvail   `MOV DI,5cd8 / PUSH DS / PUSH DI / MOV DI,[DI] /
                                   CALLF [DI+18]`. $5cd8 is `Heap` and not one of the
                                   other four heap variables, and HEAPS itself proves
                                   it: `ChangeSystemHeap` ends `MOV DI,5cd8 ... CALLF
                                   [DI+20]`, which is `Heap.TransferFromSystem`. +$18
                                   is the sixth virtual slot, `HTotalAvail`.
      ShrinkSystemHeap(0)         hand every free byte back to DOS, because the child
                                   needs somewhere to load. `SetMemTop` is the half
                                   that makes this different from ChangeSystemHeap.
      SwapVectors                 0d57:00a6, no parameters, called twice around the
      Exec(ProgName, ShellParam)  Exec -- the DOS unit's own required protocol.
      SwapVectors                 `0d57` IS the DOS unit: its first routine sets the
                                   DTA with `MOV AH,1A / INT 21` and then FindFirsts
                                   with `MOV AH,4E / INT 21`.
      ShrinkSystemHeap(Saved)     take the memory back.

    `Exec` GETS TWO ADDRESSES AND NO COPIES -- `MOV DI,5e38 / PUSH DS / PUSH DI` and
    the same for $0970 -- which is what an open `string` parameter looks like. $5e38 is
    VTShell's `ProgName` and $0970 is `ShellParam`; v1.31b's `CmdInitShell` fills both
    and that release never ran them from here, because `1000:03af` did the Exec instead.
    In 1.51 the shell moved down here, so a command line that names a program and no
    module runs the program rather than falling through to the player. }
  if SongColl.Count = 0 then
    begin
      Saved := Heap.HTotalAvail;
      ShrinkSystemHeap(0);
      SwapVectors;
      Exec(ProgName, ShellParam);
      SwapVectors;
      ShrinkSystemHeap(Saved)
    end
  else
    begin
      DoSongColl := False;

      { **THE TWO ABORTS ARE ONE BOOLEAN EXPRESSION, NOT TWO STATEMENTS,** and the
        branch targets say so. `07b5` is `CMP [4821],0 / JNZ 07e3` and `07df` is
        `OR AL,AL / JNZ 07e5`, with `07e3` holding a single `JMP 07f1`. Written as two
        `if ... then goto Fin` the first would have to be `JZ +3 / JMP`, five bytes
        where there are two, and there would be two `JMP 07f1` rather than one shared.
        Short-circuit `or` puts both false-paths on the same label, which is what
        Turbo Pascal 6's default boolean evaluation -- B-minus -- emits. }
      for i := 0 to SongColl.Count - 1 do
        if CtrlBlock.Abort or
           not DoAllMODs(Path, PString(SongColl.At(i))^, OneMODProc) then goto Fin;
      DoSongColl := True;

    Fin:
      SongColl.FreeAll;
      ModOffset := 0
    end
end;


{ ===========================================================================
  109c:07ae onwards -- THE FIVE METHODS, in the release's own implementation order:
  `TVTCmd`'s override first, then `TVTCmdSwitch`'s four. That order is odd -- the
  descendant before its parent -- and it is the release's, and the original agrees.
  =========================================================================== }

{`ENTER $080`, which is `TCmdLine` = `String[127]` = 128 bytes, and that
  frame size is what tells this method's parameter apart from the `String` of
  CmdInitShell below.

  EVERY BARE ARGUMENT IS APPENDED TO A COLLECTION rather than acted on, so `DemoVT a b c`
  plays three modules in order. `AtInsert(Count, ...)` appends; `NewStr` copies the token
  onto the heap because `Token` is a frame local that the next `GetToken` will overwrite. }
procedure TVTCmd.InterpretNoSwitch(Token : TCmdLine);
begin
  SongColl.AtInsert(SongColl.Count, NewStr(Token));
end;


{ ---------------------------------------------------------------------------
CmdInitShell. `sh` names a program to run, and everything after it on the
  line is that program's arguments.

  **`Copy(Line, Idx, 255)` IS THE POINT OF THE WHOLE THING.** `Line` and `Idx` are
  `TCmdLineInterpreter`'s fields -- the raw line and the tokeniser's cursor -- so this
  takes the untokenised remainder verbatim, quotes and switches and all. It is the only
  place in either segment that reaches past `GetToken` into the cursor itself.

  **AND THE LAST STATEMENT IS WHY `116e` HAS AN EXTRA VIRTUAL.** `109c:0835` is
  `CALLF [DI+10]`, the ninth slot, whose whole body is `Idx := 255` -- and this is its only
  caller anywhere. Having swallowed the rest of the line into `ShellParam`, the interpreter
  must not then read the same text back as its own switches, so it winds the tokeniser past
  the end. A softer stop than `Abort`, which would unwind the nested `@file` chain too.
  **That call is what let the method be named `SkipRest` instead of `Rut_0110`.**

  THREE ADDRESSES FALL OUT OF THESE FOUR LINES, and all three agree with units already
  verified: `ProgName` at `DS:$3ade` (VTShell), `ShellParam` at `DS:$08c8` with its
  `PUSH 007f` confirming `String[127]` a second time, and **`Idx` at `+$146`, which is the
  third independent confirmation of `TCmdLineInterpreter`'s field layout.**

  `ENTER $204` IS 516 AND IT ACCOUNTS FOR THE UNUSED LOCALS: 256 for the `Shell` value
  parameter, 256 for the `Copy` result temporary, and 4 for `i` and `r`. **A pair of
  locals that no instruction touches is still measurable in the frame size**, so they are
  transcribed rather than tidied away.

  `i, r : WORD` ARE DECLARED AND NEVER USED, which is the release's, and they are what
  makes the frame `ENTER $204` rather than `$200`. **A pair of unused locals is
  measurable**, so they are transcribed rather than tidied away.

  `ShellPath` IS CALLED `ProgName` HERE. `11bb` -- VTCfg, byte-exact -- reads the
  config file's `ShellPath` key into a variable this project already named `ProgName`;
  the release's VTGlobal calls it `ShellPath`. One variable, and the transcribed name
  wins because it is already in a verified unit. }
procedure TVTCmdSwitch.CmdInitShell(Shell : String);
var
  i, r : Word;
begin
  ProgName   := Shell;
  ShellParam := Copy(Line, Idx, 255);

  SkipRest
end;


{ ---------------------------------------------------------------------------
InterpretSwitch, the switch table itself. `ENTER $180` is the 128-byte
  `Token` copy plus a 256-byte temporary for the `TokenParam` results.

  TWENTY-ONE BRANCHES IN ONE `ELSE IF` CHAIN, in the order the constants appear at
  `0844..088f`, and the order matters twice over: **CmpSwitch matches only a PREFIX and
  does not check what follows**, so `nolp` must be tried before `nofl` would ever match
  something beginning `no`, and the four-character names all come before the shorter
  ones. A table sorted alphabetically would break it.

  THE FIRST BRANCH IS THE EMPTY TOKEN, and it is not a switch at all: a bare `-` or `/`
  with nothing after it means "play what has been collected so far", and failing that
  aborts the whole line. `FileDir` is the directory of the `@file` currently being read,
  so an included file's relative paths resolve against itself.

  `frst` IS ABSENT FROM 1.31 and so is `CmdInit1stSong`, the only routine it called --
  the release's fifteenth `ENTER $102` frame has no counterpart here. In its place, two
  new switches after `sh`: `nx`, which sets a byte nothing reads, and `nb`, which
  suppresses `1000`'s banner.

  THE TRAILING BARE `;` AFTER THE LAST BRANCH is the release's and is kept. It is an
  empty statement standing in for the `ELSE` that is not there, so an unrecognised
  switch is silently ignored rather than reported.
  --------------------------------------------------------------------------- }
procedure TVTCmdSwitch.InterpretSwitch(Token : TCmdLine);
begin

  if      Token = ''               then begin if not DoSongColl(FileDir) then Abort; end
  else if CmpSwitch(Token, 'nobf') then CmdBassFilter     (False)
  else if CmpSwitch(Token, 'bfil') then CmdBassFilter     (True)
  else if CmpSwitch(Token, 'nolp') then CmdLoopMod        (False)
  else if CmpSwitch(Token, 'loop') then CmdLoopMod        (True)
  else if CmpSwitch(Token, 'nofl') then CmdForceLoop      (False)
  else if CmpSwitch(Token, 'port') then CmdSetPort        (TokenParam(Token))
  else if CmpSwitch(Token, 'irq' ) then CmdSetIRQ         (TokenParam(Token))
  else if CmpSwitch(Token, 'dma' ) then CmdSetDMA         (TokenParam(Token))
  else if CmpSwitch(Token, 'off' ) then CmdModOffset      (TokenParam(Token))
  else if CmpSwitch(Token, 'flp' ) then CmdForceLoop      (True)
  else if CmpSwitch(Token, 'lq'  ) then CmdLowQuality     (True)
  else if CmpSwitch(Token, 'hq'  ) then CmdLowQuality     (False)
  else if CmpSwitch(Token, 'ss'  ) then CmdInit1stPattern (TokenParam(Token))
  else if CmpSwitch(Token, 'sl'  ) then CmdInitSongLen    (TokenParam(Token))
  else if CmpSwitch(Token, 'sr'  ) then CmdInitRepStart   (TokenParam(Token))
  else if CmpSwitch(Token, 'sh'  ) then CmdInitShell      (TokenParam(Token))
  else if CmpSwitch(Token, 'nx'  ) then CmdNx
  else if CmpSwitch(Token, 'nb'  ) then CmdNoBanner
  else if CmpSwitch(Token, 'd'   ) then CmdInitDevice     (TokenParam(Token))
  else if CmpSwitch(Token, 'f'   ) then CmdInitFreq       (TokenParam(Token))
  else if CmpSwitch(Token, 'v'   ) then CmdInitVolume     (TokenParam(Token))
  ;

end;


{ 109c:0c5e and 109c:0c9d -- save and restore the four settings a shelled-to program
  might change. `PUSH BP` with no frame, because a `var` parameter needs no copy, and
  `RETF 8` for Self plus the pointer.

  **BOTH END BY CALLING `SetVTDevice`**, including the getter -- which looks wrong and is
  the release's. Reading the options should not touch the hardware; it does because the
  pair is used around a shell-out and the author wanted the device reinstated either way.
  `DeviceSet` being permanently False means it really does re-locate the device twice. }
procedure TVTCmdSwitch.GetCmdOptions(var Opt : TCmdOptions);
begin
  Opt.LowQuality := LowQuality;
  Opt.DevID      := DevID;
  Opt.Freq       := DesiredHz;
  Opt.Volume     := VtVolume;

  SetVTDevice;
end;


procedure TVTCmdSwitch.SetCmdOptions(var Opt : TCmdOptions);
begin
  LowQuality := Opt.LowQuality;
  DevID      := Opt.DevID;
  DesiredHz  := Opt.Freq;
  VtVolume   := Opt.Volume;

  SetVTDevice;
end;

end.
