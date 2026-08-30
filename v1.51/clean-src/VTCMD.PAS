{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  THE COMMAND-LINE SWITCHES: what every option DemoVT accepts actually does.

  THIS IS THE DESCENDANT CmdLine WAS WRITTEN FOR. That unit knows how to walk a
  line and split it into tokens and knows nothing about DemoVT; this one
  overrides its two interpret methods and supplies the meanings. Anyone looking
  for what `-nb` or `-gus` does is in the right file.

  A SWITCH IS MATCHED BY PREFIX AND HANDLED BY A METHOD. The vocabulary is a
  run of names, tested in order, and the first that matches wins -- so the
  ORDER of the table is part of the behaviour, and a shorter name that is a
  prefix of a longer one would shadow it.

  IT ALSO BUILDS THE PLAYLIST. A token that is not a switch is a file to play,
  and this is where it is added to the collection the player walks -- which is
  why an `@file` of names, read by the parent's `@` handling, becomes a
  playlist without either unit knowing that word.

  THE OTHER WRITER OF THE GLOBALS IS VTCfg. Neither owns them; a setting given
  on the command line and in the config file is decided by whichever runs last.

  AND THE BRANCHES NAME EVERY LOCAL ROUTINE, because each one calls exactly one and the
  near-call targets are unambiguous. Pairing the CmpSwitch sites with the table in order
  gives the routine behind each switch, and the frame sizes then confirm each in turn:

      'd'  -> 03fb  ENTER $100   CmdInitDevice      (a String parameter, no locals)
      'f'  -> 0435  ENTER $104   CmdInitFreq        (a String plus i, r)
      ...  -> 055f  ENTER $106   CmdModOffset       (a String plus l : LONGINT and r)
      'sh' -> 0b7c  CALLF [DI+2c]  CmdInitShell     -- see below, it is the KEY
      'nx' -> 06d3  PUSH BP, near RET, no parameters   NEW
      'nb' -> 05b2  PUSH BP, near RET, no parameters   NEW

  THE FAR AND NEAR CALL COUNTS AGREE WITH THE RELEASE'S `DoAllMODs` TERM FOR TERM:}
unit VTCmd;

interface


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
  Cmd      : TVTCmd;      { the parser itself, one per program }


  { A `TStringCollection`, AND THE LINKED IMAGE IS WHAT SETTLED IT -- after this file
    had argued the opposite and been WRONG.

    WHAT SETTLED IT IS A VMT. Turbo Pascal lays an object type's VMT down in DGROUP,
    and the original's initialised image holds THREE `Objects` VMTs of sizes 8, 12 and
    13 -- while ours held only the first two. Size 12 is `TCollection` (VMT 2 + Items 4
    + Count 2 + Limit 2 + Delta 2) and size 13 is that plus `Duplicates`, which is
    TSortedCollection exactly; its method table has three more entries than
    TCollection's and shares its first two, which is what a descendant looks like.
    Declaring this one a TStringCollection recovers all 48 bytes and the block then
    matches. **A VMT is measurable data, and it names a type that no call site could.**}
  SongColl : TStringCollection; { the playlist, in the order given }

procedure SetVTFreq;
procedure SetVTDevice;

function DoSongColl(Path : PathStr) : Boolean;


implementation


{ VTSilenc BEFORE FileUtil, AND THE LINK ORDER IS THE ONLY REASON. The two are
  unrelated and either order compiles; the original's segments run FILEUTIL then
  VTSILENC then CMDLINE, and reverse post-order means FileUtil has to finish LAST of
  the three. See VTMAIN's uses clause for the other half of the change. }
uses
  SoundBlaster, VTShell, SongUnit, SongElements, PlayMod, GUS,
  VTSilenc, FileUtil, Heaps, VTCtrl;


{ ===========================================================================
  THE TWO DEVICE HELPERS: choose the sound device by name, and set its rate.

  They are separate from the switch handlers because the same choices arrive
  from two directions -- the command line and the config file -- and both have
  to end up doing the same thing.}

{ --------------------------------------------------------------------------
SetVTDevice, and THREE STATEMENTS OF THE RELEASE'S ARE ABSENT. Fifty-four
  bytes, and every one of them accounted for:

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
  { THE EXTENSIONS TRIED WHEN A NAME HAS NONE. A playlist may say `TUNE` and
    mean `TUNE.MOD`, so each is appended in turn until a file opens -- which
    makes the ORDER below part of the behaviour.

    **THE RELEASE USES A WILDCARD WHERE 1.31 SPELLS BOTH OUT.** 1.39b has `'.S?M'`, one
    entry covering ScreamTracker 2 and 3; 1.31 lists `.S2M` and `.S3M` separately. It also
    has `.STM` where the release has `.STX`. So the release traded two entries for one and
    changed a third -- and 1.31 is the earlier, longer form.}
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

{ ENTER $100, so no locals at all, and it is the only one. }
procedure CmdInitDevice(s : String);
begin
  if s = '' then Exit;

  DevID := s;

  SetVTDevice;
end;



procedure CmdInitFreq(s : String);
var
  i, r : Word;
begin
  if s = '' then Exit;

  Val(s, i, r);
  if r = 0 then
    DesiredHz := i;
end;


{ -- one port and one IRQ for both cards, because only one of
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
    { Set the serial port the silence driver clocks from.}
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
    { the same third store, for the IRQ. }
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


{ `ENTER $106`, the only one, and `l : LONGINT` is why: a module offset can
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


{ THREE INSTRUCTIONS, and the release has nothing like it:

      55 89 e5           PUSH BP / MOV BP,SP
      c6 06 e8 09 01     MOV byte [09e8],1
      c9 c3              LEAVE / RET

  It is the `nb` switch, and `1000` is what names it: that segment tests `[09e8]` and
  skips a four-line banner when it is set. See the declaration of `NoBanner`. }
procedure CmdNoBanner;
begin
  NoBanner := True
end;


{ and the clamp is to 255 because `VtVolume` is a BYTE, so an unchecked
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


{ 068c and 06dd -- the three song-position switches: which pattern to start
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


{ the `nx` switch, and the same three instructions as CmdNoBanner but
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


  if CtrlBlock.Abort then Exit;


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
 onwards -- THE FIVE METHODS, in the release's own implementation order:
  `TVTCmd`'s override first, then `TVTCmdSwitch`'s four. That order is odd -- the
  descendant before its parent -- and it is the release's, and the original agrees.
  =========================================================================== }

{ `ENTER $080`, which is `TCmdLine` = `String[127]` = 128 bytes, and that
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


{ -- save and restore the four settings a shelled-to program
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
