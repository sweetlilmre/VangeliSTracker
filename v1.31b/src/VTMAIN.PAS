{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).

  Segment 1000 -- the program itself. 1621 bytes: four banner strings, five
  routines, the dispatcher, the init chain at $04b3 and the body at $04e0.

  **THE LAST SEGMENT, AND NO LONGER BLOCKED ON ANY OTHER.** Every one of the
  twenty-six units this program reaches is transcribed and byte-exact, so the
  seventeen `Unit_<seg>_<ofs>` placeholders are gone -- see the note at `uses`.

  IT IS STILL NOT A COMPILABLE TRANSCRIPTION. This file was written as a
  READING of the segment during the line-by-line pass, and parts of the body
  are notional rather than Pascal -- `Str(Buffer^ : -128, ...)` at 1000:03da is
  the clearest case. Turning it into something that builds is the remaining
  work, and it is a transcription pass like any other; what has changed is that
  nothing external stands in the way of starting it.

  NAMES ARE PROVISIONAL. The binary is Borland Pascal 6 with no debug
  information, so no unit or routine name survives. Everything here is named
  for what it does, and every name is followed by the address it was read
  from.

  ADDRESS MAP
    banner text   1000:0000  four String[61], stride 62
    ShowBanner    1000:00f8     TimerChain    1000:016b
    PollDriver    1000:0171     TimerHandler  1000:01a5
    HookTimer     1000:01bd     UnhookTimer   1000:020a
    Dispatch      1000:024c     PlayModule    1000:02b5
    usage text    1000:0405  three String[44], then two more
    init chain    1000:04b3     the body      1000:04e0

  DGROUP (segment 1caa)
    $0002  the poll re-entrancy guard     $0004  'DemoVT v1.31 (beta)'
    $009a  PlayModule, as a far pointer   $02d1  set when run as INCONEXI.EXE
    $09e8  "the banner has been shown"    $0b96  the sound driver object
    $0c6e  -> TimerChain                  $0c72  "say if no song was found"
    $22c6  THE CONTROL BLOCK              $23e7  CB+$121: the dispatcher
  =========================================================================== }

{ THE STACK IS 20,000 BYTES, NOT THE DEFAULT 16,384, AND THE EXE HEADER IS WHAT SAYS SO.
  The original's initial SP is $4E20 -- 20000 -- where a default build gives $4000, and its
  MINALLOC is 226 paragraphs larger than ours, which is 3,616 bytes, which is
  20000 - 16384 exactly. Two independent header fields agreeing on one number.

  HeapMin stays 0: if it differed, MINALLOC would be out by more than the stack delta and
  it is not. HeapMax is left at the default because the original's MAXALLOC is $FFFF, and
  that is almost certainly LZEXE's rather than TPC's -- the unpacker claims all available
  memory -- so it is a risk-3 question about the packer, not a compiler directive. }
{$M 20000,0,655360}

{$G+}   { PUSHA/POPA in the dispatcher and the timer handler }

program DemoVT;

{ EVERY `Unit_<seg>_<ofs>` PLACEHOLDER IS GONE. All twenty-six units this
  program reaches are transcribed and byte-exact, so the seventeen calls that
  were written as addresses are now written as names:

    109c:0000 SetVTDevice     109c:0038 SetVTFreq    109c:0724 DoSongColl
    116e:04b2 GetDOSCmdLine   12ba:10a1 PlayStart    12ba:13d7 PlayStop
    14b9:0000 TSong.Init      14b9:0106 LoadFName    14b9:02f5 SetInsidePath
    17cf:00b5 InitUmbHeap     17cf:01d3 ShrinkSystemHeap
    17cf:0a63 InitHeapVariables
    1891:0000 TObject.Init    1891:03a7 TCollection.Init
    1b6f:00a6 SwapVectors     (twice, around the Exec)

  THE INIT CHAIN AT 1000:04b3 IS THE CONSTRAINT ON THIS `uses` CLAUSE, and it
  is not a free choice. Turbo Pascal emits one call per unit that HAS an
  initialisation section, in dependency-resolved order, and the original's is

      1ba1:0000  RTL        193a:0488  DevSB      1931:0029  VTShell
      17cf:0a93  Heaps      14b7:0000  VTCtrl     12ba:141e  PlayMod
      11bb:0f2e  VTCfg      1084:0101  DevGus     1065:0172  VTSilenc
      1ba1:1038  RTL exit

  so the clause below has to produce exactly that order. Units with no
  initialisation section never appear in the chain however they are listed.

  AND **DevSB REGISTERS BEFORE DevGus**, which decides the default device.
  DEVGUS.PAS records that InitDevice pushes onto the front of the list but
  selects only when nothing is selected yet, so the FIRST to register wins --
  and that note concluded "a machine with both ends up on the GUS" while
  comparing DevGus against VTSilenc alone. With 193a in the chain the SB
  registers first. Whether that changes the conclusion is not settled here;
  it is flagged because the note was written without this segment. }
{ THE ORDER OF THIS CLAUSE IS THE PROGRAM'S SEGMENT LAYOUT, AND IT IS SOLVED RATHER
  THAN CHOSEN. TP6 emits segments in reverse DFS post-order over the `uses` graph, so
  the original's segment ADDRESSES read backwards are its finish order -- and that is
  the one thing about the original link that can simply be measured. The first eleven
  entries below are the unique sequence that reproduces it; `linkorder.py`
  simulates the rule and diffs the result, and it agrees on all thirty positions.

  Two of them are worth pointing at, because they are not what a reader would guess:

  * SoundDevices, SoundBlaster and Hardware are NOT listed here at all. They arrive
    through DevSB, which is what puts them at positions 24..26 -- listing any of them
    earlier pulls it forward and moves three segments.
  * SongElements and GUS arrive through PlayMod (via SongUnit), not from here.

  The entries after the blank line are already finished by the time the walk reaches
  them, so they are no-ops in the ordering and their position is unobservable FROM THE
  SEGMENT MAP. It is not unobservable in general, and `VTGlobal` is the proof: it emits
  no segment, so the map says nothing about it, but it does emit DATA, and its block
  sits between VTShell's and DevSB's in the original's DGROUP. That is what moved it up
  into the ordered group. Any other declarations-only unit with initialised data can be
  placed the same way -- `dgroup.py` is the instrument, not `mapcmp.py`. }
uses
  Dos, VTResid, DevSB, VTGlobal, VTShell, Objects, Heaps, PlayMod, VTCfg,
  VTCmd, DevGus, VTSilenc,

  SoundDevices, SongUnit, VTCtrl, CmdLine, VTNotes, Hardware, VTDosMem,
  ModCommands;

{ `Guard` IS A TYPED CONSTANT, NOT A VAR, and that is the only thing that can put it
  at $0002. DGROUP is laid out as ALL the units' typed constants in link order and then
  all their variables, so anything in the initialised image -- which is what the EXE
  actually stores, and what `dgroup.py` reads -- has to be a constant. The
  original's image opens with four zero bytes and SelfName at $0004; declared a `var`
  this byte went to the variable region instead and left ours opening with two.

  Moving it around the source as a `var` was tried first and moved nothing, which is
  how the const/var split got established: **TP6 emits a unit's typed constants before
  its variables regardless of the order the sections appear in.** A typed constant is
  writable in Turbo Pascal, so `Inc(Guard)` is still legal.

  What was already settled is the width. `Guard` is a BYTE, not a Word: 1000:0174 is
  `80 3E 02 00 00`, `CMP byte [0002],0`, and 1000:017b is `FE 06 02 00`, `INC byte`
  -- a Word gives the `83 3E` and `FF 06` forms instead. So $0003 is a PAD, which is
  TP word-aligning `SelfName` after it; the same alignment shows up three more times
  in VTGlobal's block. }
const
  Guard     : Byte = 0;  { DS:$0002  the poll re-entrancy guard }

  { 1000:0000, FOUR SEPARATE UNTYPED CONSTANTS on a stride of 62 -- CP437 box
    drawing. NOT an `array[1..4] of String[61]`, which is what this was, and the
    difference is where the bytes live: a TYPED constant is initialised DGROUP data
    and an UNTYPED one is a literal that Turbo Pascal lays down in the CODE segment.
    The original has them in CODE at 1000:0000..00f7, with ShowBanner's own code
    starting at 00f8 -- which is also the rule this project already knows, that a
    routine's literals are emitted immediately before it.

    THREE THINGS SAY SO INDEPENDENTLY, and the array form contradicts all three:
      * 1000:0000 is the strings, so ShowBanner does not begin at offset 0;
      * the initialised DGROUP at DS:$0000 is thirty bytes -- four zeros and one
        String[25] -- with no room for 248 bytes of banner (`dgroup.py`);
      * ShowBanner's prologue is `55 89 E5`, PUSH BP / MOV BP,SP with no ENTER, so
        the routine has NO LOCAL, and the `for I` the loop form needs is not there.
    The four WriteLns are UNROLLED for the same reason: 1000:0111, 0127, 013d and
    0153 are `MOV DI,0000 / 003e / 007c / 00ba` as immediates, each with a PUSH CS.
    A loop would compute the address from an index instead. }
  Banner1 = '    ' + #218 + #196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196 + #191;
  Banner2 = '    ' + #179 + '  DemoVT.  VangeliSTracker''s version for demos, v1.31  ' + #179;
  Banner3 = '    ' + #179 + '                (C) 1992-93  VangeliSTeam              ' + #179;
  Banner4 = '    ' + #192 + #196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196 + #217;

  { 1000:0405, three String[44] on a stride of 45. }
  UsageTop = ' ' + #218 + #196#196#196#196#196#196#196#196#196#196#196#196#196 +
                   #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
                   #196#196#196#196#196#196#196#196#196#196#196#196#196 + #191;
  UsageMid = ' ' + #179 + ' USAGE:  DemoVT <file>[<.Ext>] [options] ' + #179;
  UsageBot = ' ' + #192 + #196#196#196#196#196#196#196#196#196#196#196#196#196 +
                   #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
                   #196#196#196#196#196#196#196#196#196#196#196#196#196 + #217;

  { 1000:048c -- compared against the program's OWN file name. Renaming the
    executable to INCONEXI.EXE sets DS:$02d1, which nothing in this segment
    reads; whatever it selects lives in a unit not yet read. }
  AltName  = 'inconexi';

  { 1000:0495 }
  NoSong   = 'No encuentro ninguna canci' + #162 + 'n.';

  { 1caa:0004 -- the name Install publishes over INT 2Fh. A TYPED constant, so it
    lives in DGROUP rather than in the code segment, and TWO measurements say so:
    1000:0599 is `MOV DI,0004 / PUSH DS / PUSH DI`, and PUSH DS against PUSH CS is
    this project's standing test for where a constant lives -- an untyped one is a
    literal in CODE. And the LENGTH follows from the neighbour: VTSilenc's `Driver`
    is the next unit's first datum and the original puts it at $001e, so this
    occupies $0004..$001d, which is 26 bytes, which is String[25]. The declared
    length was read as String[25] on the strength of VTSilenc's `Driver` starting at
    $001e -- and that was wrong, because the six bytes between are not this string's.
    **THEY ARE VTSILENC'S `Frac` AND `OldVec`**, two typed constants at $0018 and $001a
    which its own code names outright: `1065:0018` is `MOV AL,[0018]` and `1065:005e`
    tests `[001a]`. So this is `String[19]`, exactly as long as its text.

    **AND `dgroup.py` REPORTING THE INITIALISED HALF IDENTICAL DID NOT CATCH IT.** Every
    byte from $0018 to $001d is zero whichever way the six are divided, so the image is
    the same and the SIZES were still wrong. A byte comparison of initialised data cannot
    see a boundary inside a run of zeros; only an instruction that names an address can,
    and `linkcmp.py` is what reads those. }
  SelfName : String[19] = 'DemoVT v1.31 (beta)';

var
  { ~~PlayProc $009a and AltMode $02d1~~ -- BOTH GONE, and both were other units'.

    `PlayProc` IS `VTCmd.OneModPtr`, THE HOOK THE PLAYLIST CALLS THROUGH. $009a is four
    bytes immediately below TVTCmd's VMT at $009e, inside VTCmd's block, and VTCMD.PAS
    already declares it: `OneModPtr : Pointer = nil` with `OneMODProc : TDoOneProc
    absolute OneModPtr` laid over it, which is how 1993 Pascal gives a procedural
    variable an initial value. `1000:05e2` installs this program's `PlayModule` into it
    and `DoSongColl` calls it for every entry it collected -- and clears it again at
    109c:079f, which this project had already read as "the caller's hook cannot outlive
    the collection". The two ends of the same mechanism, finally joined up.

    `AltMode` IS PLAYMOD'S, at $02d1, between `DontExecute` and `Playing` in its
    address-ordered const block -- the one insertion 1.31 makes in the release's
    sequence. This program SETS it (when the executable is called INCONEXI.EXE) and
    12ba is the only reader, which is why it was declared in both. }
  { ~~NoBanner : Boolean at DS:$09e8~~ -- GONE. It is `VTGlobal.NoBanner`, the same byte,
    and this program declared a second name for it. $09e8 is inside VTGlobal's DGROUP
    block ($083a..$09e8, and it is the LAST byte of it), so it cannot have been this
    program's; and the behaviour is one thing, not two -- `109c`'s `nb` switch suppresses
    the banner by setting it, and ShowBanner sets the same byte so the banner prints
    once. The note under `nb` in VTGLOBAL.PAS has described it that way all along. }
  { ~~Driver : Pointer at DS:$0b96~~ -- GONE. $0b96 is `SoundDevices.ActiveDevice`,
    the selected driver, and this program declared a second name for it. The DGROUP
    layout is what settled it: $0b96 is the second datum of SoundDevices' block
    ($0b94 NumDevices, then this), so it cannot have been the program's. Every
    `LES DI, Driver` below is now `LES DI, ActiveDevice`. }
{ THIS PROGRAM'S VARIABLE BLOCK, $0c6e..$0e2c, IN ADDRESS ORDER. The variable half of
  DGROUP is laid out per unit in link order exactly as the constant half is, and this
  program is first, so its block opens the region. It is not in the EXE -- a `var` is
  space the linker never writes -- but every instruction that touches one carries the
  resolved address, so `linkcmp.py` reads the layout back out of the CODE.

  The order below is the original's, taken from those operands:

      $0c6e ChainPtr   $0c72 Complain   $0c74 Song (94 bytes)   $0cd2 SavedCD
      $0cd6 Str1208 (256)               $0dd6 four bytes unidentified
      $0dda Dir        $0e1e Name       $0e28 Ext -> VTSilenc's block at $0e2e

  `Song` used to be declared LAST and is second; `Str1208` was carrying `DS:$1208`,
  which is PlayMod's `UserVols` and not this at all -- its real address is $0cd6, and
  256 + 4 is exactly the gap between `SavedCD` and `Dir`. }
  ChainPtr  : Pointer;   { DS:$0c6e -> TimerChain }
  Complain  : Boolean;   { DS:$0c72  and a pad at $0c73 }
  Song      : TSong;     { DS:$0c74  94 bytes; Init at 1000:032a }

{ --------------------------------------------------------------------------
  EIGHT NAMES RESOLVED TO THE UNITS THAT OWN THEM, now that all of them are
  transcribed. These used to be `Var<addr>` placeholders here:

    $02c8 LoopMod        PlayMod        $02c9 ForceLoopMod   PlayMod
    $0bae DesiredHz      SoundDevices   $3ade ProgName       VTShell
    $08c8 ShellParam     VTGlobal       $397e Heap           Heaps
    $0bc8 Ticks          VTSilenc       $4306 DMABufferPtr   SoundDevices

  Each was already declared at that address by its owner, independently, so
  eight addresses agreeing is a cross-check rather than an assumption.

  THE REST ARE STILL DECLARED HERE AND STILL WRONG TO BE. Every one below is a
  DGROUP address this segment reads or writes whose OWNER has not been
  established -- some almost certainly belong to VTCmd or VTCfg. A DGROUP
  reference is a linker fixup, so the byte comparison cannot tell a right home
  from a wrong one; that is risk 1, and declaring them here is that risk taken
  deliberately rather than by accident. Compare DEVGUS, where three globals sat
  in the wrong unit and nothing could see it.
  -------------------------------------------------------------------------- }
  { ~~ELEVEN `Var<addr>` PLACEHOLDERS USED TO BE DECLARED HERE~~ and every one of them
    was another unit's global under a made-up name. The DGROUP layout named all eleven at
    once, because each address falls inside a block whose owner is now settled:

      MaxOutputFreq    $02ce  -> MaxOutputFreq  PlayMod
      VtVolume   $08ba  -> VtVolume       VTGlobal
      ShellLoopMod   $08bb  -> ShellLoopMod   VTGlobal
      ShellHz    $08bc  -> ShellHz        VTGlobal
      VT1stPattern    $08c2  -> VT1stPattern   VTGlobal
      VTRepStart    $08c4  -> VTRepStart     VTGlobal
      VTSongLen    $08c6  -> VTSongLen      VTGlobal
      ReqStart    $0342  -> ReqStart       ModCommands
      ReqEnd    $0344  -> ReqEnd         ModCommands
      ReqLen    $0346  -> ReqLen         ModCommands
      UserVols   $1208  -> UserVols       PlayMod
      Song.Status  $0ccd  -> Song.Status    this program, as a FIELD

    `Song.Status` is the interesting one: $0ccd is not a variable at all. `Song` is this
    program's own `TSong` at $0c74 -- `1000:0322` is `MOV DI,0C74h` and the two virtual
    calls at `03fb` and `038d` go through it -- and $0c74 + $59 is $0ccd, which is the
    record's `Status`. The reading had it as a standalone byte because a field of a
    global and a global of its own look identical in a `MOV`.

    None of this could be seen before the layout: a DGROUP reference is a linker fixup,
    so `units.py` excused every one and the program compiled either way. }
  { ~~VarC76 $0c76 and VarC78 $0c78~~ -- NOT VARIABLES. `Song` is at $0c74 and is 94
    bytes, so both of these are INSIDE it: $0c74 + 2 is `SongStart` and + 4 is `SongLen`,
    which SONGUNIT.PAS already declares as the record's first two fields. The two
    statements that used them read `if VT1stPattern <> 0 then Song.SongStart := ...` --
    the program copying the play range the command line asked for into the song it is
    about to play, which is what `VT1stPattern` and `VTSongLen` are for. }
  { DS:$0cd2, ONE LongInt rather than two Words: ShrinkSystemHeap takes a
    LongInt and 1000:03c4 pushes both halves of this pair into it. The asm at
    0390 stores AX and DX into $0cd2 and $0cd4, which is the same object seen
    from the other end. }
  SavedCD   : LongInt;   { DS:$0cd2 }
  { ~~TickSnapshot $0bca, LastTick $0058, DriverTicks $0bd0~~ -- ALL THREE GONE, and each
    was a second declaration of a global another unit owns. The layout is what settled
    it: $0bca and $0bd0 are inside SoundDevices' block ($0b94..$0c0b) and $0058 is
    inside DevGus's ($0058..$0099), while this program's own data is at $0000..$001d
    and above $0c70. The names they now carry are `SoundDevices.TickSnapshot`,
    `DevGus.LastTick` and `SoundDevices.DriverTicks`; the dispatcher below writes all
    three by those names. }
  { DS:$0cd6 -- 256 bytes, and its address comes from its NEIGHBOURS rather than from
    any instruction: nothing in the program references it, so no operand names it. What
    fixes it is that `SavedCD` ends at $0cd5 and `Dir` begins at $0dda, and 256 + 4 is
    the gap. It used to be quoted at DS:$1208, which is PlayMod's `UserVols`. }
  Str1208   : String;    { DS:$0cd6 }

  { DS:$0dd6 -- FOUR BYTES THIS TRANSCRIPTION CANNOT NAME, between the string above and
    `Dir` at $0dda. Nothing references them. Filler, so the SIZE is right and the
    missing name is stated rather than invented. }
  Fill0DD6  : LongInt;   { DS:$0dd6 }
  { ~~Obj0E38 : TObject~~ and ~~Var0F82 : TCollection~~ ARE GONE. They were
    VTCmd's own `Cmd` and `SongColl`, and declaring stand-ins here is what kept
    both CMDLINE and VTCMD out of the linked image -- see the body at 1000:05bb.
    DS:$0e38 and DS:$0f82 are their measured addresses; VTCMD.PAS carries them. }
  { ~~Var0F3A $0f3a~~ -- ALSO NOT A VARIABLE. `Cmd` is at $0e38 and $0e38 + $102 is
    `FileDir`, which CMDLINE.PAS declares at that offset in TCmdLineInterpreter -- VMT,
    then `Line : String` at +$002, then `FileDir : DirStr` at +$102. So the last
    statement of the program is `DoSongColl(Cmd.FileDir)`, and `109c`'s own
    `InterpretNoSwitch` calls `DoSongColl(FileDir)` on the same field. Two callers, one
    field, and the reading had this one as a standalone PathStr. }

{ DS:$22c6, THE CONTROL BLOCK, is NOT declared here. It lives in VTCtrl,
  the unit for segment 14b7, which is the code that clears it. There must be
  exactly one of it: INT 2Fh publishes its address to every client, so a
  second copy would mean the demo talked to a block nothing was updating.
  See docs/06-transcription.md, "one DGROUP, many units". }

{ --------------------------------------------------------------------------
  1000:00f8 -- print the banner, once. Guarded by DS:$09e8, because both the
  body and PlayModule call it.
  -------------------------------------------------------------------------- }
{ @asm 000 1000:00f8 +115 }
procedure ShowBanner;
begin
  if not NoBanner then                               { 1000:00fb }
  begin
    WriteLn;                                      { 1000:0102 }
    WriteLn(Banner1);                             { 1000:010c }
    WriteLn(Banner2);                             { 1000:0122 }
    WriteLn(Banner3);                             { 1000:0138 }
    WriteLn(Banner4);                             { 1000:014e }
    NoBanner := True;                                { 1000:0164 }
  end;
end;

{ --------------------------------------------------------------------------
  1000:016b -- the chain to whatever held INT 1Ch before us.

  HAND ASSEMBLER, and it has to be: this is not a routine that is called, it
  is a five-byte JMP FAR whose OPERAND is patched. HookTimer writes the old
  vector into the two words at +1 and +3, and UnhookTimer reads them back out.

  It is assembled pointing at itself so that a stray call before the patch
  spins rather than jumping into nothing; the body then zeroes both words.
  -------------------------------------------------------------------------- }
{ IT IS `far`, AND THE BYTE AT $0170 IS ITS EPILOGUE RATHER THAN DATA. This used to
  write the `CB` as an explicit `DB 0CBh` and let the compiler add its own epilogue on
  top, which is one byte more than the original has -- `cb c3` where the original ends
  `cb`. An `assembler` procedure ALWAYS gets an epilogue, which this document records
  under "a written RET in a far assembler procedure becomes RETF"; the fix is to stop
  writing the RETF and let the epilogue be it, and to make the procedure FAR so that
  the epilogue is `RETF` and not a near `RET`. `1000:01b7` jumps here with a far JMP
  and `1000:0577` takes its address, so far is what it is. }
{ @asm 000 1000:016b +6 }
procedure TimerChain; far; assembler;
asm
  DB   0EAh              { 1000:016b  JMP FAR seg:ofs -- the operand is data }
  DW   OFFSET TimerChain { 1000:016c  patched with the old INT 1Ch offset    }
  DW   SEG TimerChain    { 1000:016e  patched with the old INT 1Ch segment   }
                         { 1000:0170  the epilogue's RETF, never reached     }
end;

{ --------------------------------------------------------------------------
  1000:0171 -- poll the sound driver four times, non-reentrant.

  Four calls, not a loop: the binary has the LES/CALLF pair written out four
  times over. DS:$0002 keeps the timer out of itself when a poll runs long.
  -------------------------------------------------------------------------- }
{ @asm 000 1000:0171 +52 }
procedure PollDriver;
type
  TPoll = procedure;
begin
  if Guard = 0 then                               { 1000:0174 }
  begin
    Inc(Guard);                                   { 1000:017b }
    { 1000:017f, 0187, 018f, 0197 -- LES DI,[0b96]; CALL DWORD PTR ES:[DI+$2a] }
    asm
      LES  DI, ActiveDevice        { 1000:017f                                    }
      CALL DWORD PTR ES:[DI+2Ah]         { 1000:0183  the driver's poll method          }
      LES  DI, ActiveDevice        { 1000:0187                                    }
      CALL DWORD PTR ES:[DI+2Ah]         { 1000:018b                                    }
      LES  DI, ActiveDevice        { 1000:018f                                    }
      CALL DWORD PTR ES:[DI+2Ah]         { 1000:0193                                    }
      LES  DI, ActiveDevice        { 1000:0197                                    }
      CALL DWORD PTR ES:[DI+2Ah]         { 1000:019b                                    }
    end;
    Dec(Guard);                                   { 1000:019f }
  end;
end;

{ --------------------------------------------------------------------------
  1000:01a5 -- the INT 1Ch handler. THIS is what drives the music.

  HAND ASSEMBLER, verbatim. It cannot be a Pascal `interrupt` procedure: it
  ends in a JMP FAR to the chain stub rather than an IRET, so the previous
  handler still runs and the BIOS tick is not swallowed.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      PollDriver;   -- then jump to the old handler

  -------------------------------------------------------------------------- }
{ @asm 000 1000:01a5 +24 }
procedure TimerHandler; assembler;
asm
  PUSHF                  { 1000:01a5  the chain expects the flags on top     }
  PUSHA                  { 1000:01a6                                         }
  PUSH DS                { 1000:01a7                                         }
  PUSH ES                { 1000:01a8                                         }
  MOV  AX, SEG @DATA     { 1000:01a9  the binary has MOV AX,1CAAh -- an
                                      absolute segment, and copying it would
                                      point us at somebody else's data       }
  MOV  DS, AX            { 1000:01ac                                         }
  CLD                    { 1000:01ae                                         }
  STI                    { 1000:01af  a poll is long; let the machine breathe}
  CALL PollDriver        { 1000:01b0                                         }
  POP  ES                { 1000:01b3                                         }
  POP  DS                { 1000:01b4                                         }
  POPA                   { 1000:01b5                                         }
  POPF                   { 1000:01b6                                         }
  JMP  FAR PTR TimerChain{ 1000:01b7  and on to whoever had INT 1Ch          }
end;

{ --------------------------------------------------------------------------
  1000:01bd -- FUNCTION 0, the one every Psycho Neurosis part calls
  "MusicStart".

  What it actually does is hook INT 1Ch. The music starts because the timer
  starts feeding the driver, not because anything is told to play.

  It does nothing if the stub already holds a vector, so calling it twice is
  harmless -- which is why parts can call MusicStart without checking.
  -------------------------------------------------------------------------- }
{ @asm 000 1000:01bd +77 }
procedure HookTimer;
begin
  { 1000:01c0 -- the stub's operand is the "are we hooked" flag. }
  asm
    LES  DI, ChainPtr      { 1000:01c0                                       }
    MOV  AX, ES:[DI+1]     { 1000:01c4                                       }
    OR   AX, ES:[DI+3]     { 1000:01c8                                       }
    JZ   @@NotHooked       { 1000:01cc                                       }
    JMP  @@Done            { 1000:01ce  already hooked -- leave it alone     }
  @@NotHooked:
    { **`MOV SI,0000` AND NOT `XOR SI,SI`**, six times over in this file. Same value,
      three bytes against two, and the original has the long form -- `be 00 00`, not
      `31 f6`. It is the segment of the interrupt vector table being formed, and a
      1993 hand-assembler writes it out. This file already records the identical fix in
      VTRESID, where four of them cost four bytes; here it cost six. **The verbatim rule
      exists for exactly this.** }
    MOV  SI, 0000h            { 1000:01d0                                       }
    MOV  ES, SI            { 1000:01d3  ES := 0000, the vector table         }
    MOV  AX, ES:[70h]      { 1000:01d5  INT 1Ch offset                       }
    MOV  SI, 0000h            { 1000:01d9                                       }
    MOV  ES, SI            { 1000:01dc                                       }
    MOV  DX, ES:[72h]      { 1000:01de  INT 1Ch segment                      }
    LES  DI, ChainPtr      { 1000:01e3                                       }
    MOV  ES:[DI+1], AX     { 1000:01e7  patch the chain stub                 }
    MOV  ES:[DI+3], DX     { 1000:01eb                                       }
    MOV  AX, OFFSET TimerHandler   { 1000:01ef  the binary has 01A5h         }
    MOV  DX, SEG TimerHandler      { 1000:01f2  and 1000h                    }
    MOV  SI, 0000h            { 1000:01f5                                       }
    MOV  ES, SI            { 1000:01f8                                       }
    MOV  ES:[70h], AX      { 1000:01fa                                       }
    MOV  SI, 0000h            { 1000:01fe                                       }
    MOV  ES, SI            { 1000:0201                                       }
    MOV  ES:[72h], DX      { 1000:0203                                       }
  @@Done:
  end;
end;

{ --------------------------------------------------------------------------
  1000:020a -- FUNCTION 1, "MusicStop": put INT 1Ch back and clear the stub.

  Note that neither this nor HookTimer touches the sound hardware. Silence is
  a consequence of the driver no longer being polled.
  -------------------------------------------------------------------------- }
{ @asm 000 1000:020a +66 }
procedure UnhookTimer;
begin
  asm
    LES  DI, ChainPtr      { 1000:020d                                       }
    MOV  AX, ES:[DI+1]     { 1000:0211                                       }
    OR   AX, ES:[DI+3]     { 1000:0215                                       }
    JNZ  @@Hooked          { 1000:0219                                       }
    JMP  @@Done            { 1000:021b  never hooked -- nothing to undo      }
  @@Hooked:
    LES  DI, ChainPtr      { 1000:021d                                       }
    MOV  AX, ES:[DI+1]     { 1000:0221                                       }
    MOV  DX, ES:[DI+3]     { 1000:0225                                       }
    MOV  SI, 0000h            { 1000:0229                                       }
    MOV  ES, SI            { 1000:022c                                       }
    MOV  ES:[70h], AX      { 1000:022e                                       }
    MOV  SI, 0000h            { 1000:0232                                       }
    MOV  ES, SI            { 1000:0235                                       }
    MOV  ES:[72h], DX      { 1000:0237                                       }
    LES  DI, ChainPtr      { 1000:023c                                       }
    XOR  AX, AX            { 1000:0240                                       }
    MOV  ES:[DI+1], AX     { 1000:0242  and mark it unhooked                 }
    MOV  ES:[DI+3], AX     { 1000:0246                                       }
  @@Done:
  end;
end;

{ ==========================================================================
  1000:024c -- THE DISPATCHER.

  This is the routine every Psycho Neurosis part far-calls. Its address is
  published at CB+$121 (DS:$23e7) by the body, and the demo finds it through
  the INT 2Fh handshake. See docs/01-int2f.md.

  The PUSHA / PUSH DS / MOV DS pair is not decoration: the caller is a
  different program with a different data segment, so nothing may be assumed
  about any register on entry.

  The result is set to zero and never changed, so the demo is right to ignore
  it.
  -------------------------------------------------------------------------- }
{ @asm 000 1000:024c +105 }
function Dispatch(Func : Word) : Word; far;
begin
  asm
    PUSHA                  { 1000:0250                                       }
    PUSH ES                { 1000:0251                                       }
    PUSH DS                { 1000:0252                                       }
    MOV  AX, SEG @DATA     { 1000:0253  the binary has MOV AX,1CAAh          }
    MOV  DS, AX            { 1000:0256                                       }
  end;

  Dispatch := 0;                                  { 1000:0258 }

  case Func of                                    { 1000:025d }
    0 : HookTimer;                                { 1000:0265 }
    1 : UnhookTimer;                              { 1000:026f }
    2 : asm                                       { 1000:0279 }
          LES  DI, ActiveDevice    { 1000:0279  one poll, where the timer does four}
          CALL DWORD PTR ES:[DI+2Ah]     { 1000:027d                                     }
        end;
    3 : begin
          { 1000:0288 -- part 001 is the only caller. It marks where the
            player has got to in its output buffer and resets the counters;
            it does not stop anything. GetPlayPos returns a far pointer into
            that buffer. }
          { ONE STATEMENT, AND A 32-BIT `and` IS WHAT SAYS SO. This was written as two
            -- assign, then rebuild the pointer with `Ptr(Seg(..), Ofs(..) and $FFFC)`
            -- which round-trips through the variable and costs eighteen bytes the
            original has not got. The original masks in the REGISTERS the function
            returned in: `25 fc ff` is `AND AX,0FFFCh` and `81 e2 ff ff` is
            `AND DX,0FFFFh`.

            **THE REDUNDANT `AND DX,0FFFFh` IS THE TELL.** Masking a high word with
            all-ones does nothing, and no programmer writes it; a 32-bit `and` against
            $FFFFFFFC does, because Turbo Pascal splits the constant into two 16-bit
            ANDs and emits both halves whatever they hold. So the source is a LongInt
            AND over the whole pointer, aligning it down to a multiple of four. }
          LongInt(DMABufferPtr) := LongInt(GetPlayPos) and $FFFFFFFC;
                                                       { 1000:0288..0293  -> $4306 }
          TickSnapshot := Ticks;                    { 1000:029b  $0bca := $0bc8 }
          LastTick := 0;                          { 1000:02a1  $0058 := 0     }
          DriverTicks := 0;                         { 1000:02a8  $0bd0 := 0     }
        end;
  end;

  asm
    POP  DS                { 1000:02ab                                       }
    POP  ES                { 1000:02ac                                       }
    POPA                   { 1000:02ad                                       }
  end;
end;

{ --------------------------------------------------------------------------
  1000:02b5 -- load and play one module. Published at DS:$009a as a far
  pointer, so a unit not yet read is what calls it.

  RETF 8: two String parameters, both copied into String[79] locals.
  -------------------------------------------------------------------------- }
{ THE PARAMETERS ARE `PathStr`, AND THE TWO 80-BYTE SLOTS ARE THE COMPILER'S OWN
  COPIES OF THEM -- not locals, and not statements. `ENTER 00a2,0` is 162 bytes, which
  is 80 + 80 + `Ok` + one pad and nothing else; declared `String` the two value
  parameters get 256-byte copies each and the frame is 676. And `PathStr` is
  `String[79]`, so the `PUSH 4Fh` in each copy is `SizeOf - 1` exactly.

  SO `N := Name` AND `P := Params` WERE NEVER SOURCE STATEMENTS. `1000:02b9` is
  `LES DI,[BP+0a] / PUSH ES / PUSH DI / LEA DI,[BP-52] / PUSH SS / PUSH DI / PUSH 4Fh /
  CALLF 1ba1:0add` -- push the source, push the destination slot, push the length, call
  the string-copy helper. That IS how Turbo Pascal copies a value String parameter into
  the frame on entry, and reading it as an assignment produced two extra locals and two
  extra copies. Same class as the invented `String` locals in `1b54` and `164b`: **a
  frame is explained by the parameters before it is explained by declarations.** }
{ @asm 000 1000:02b5 +336 }
function PlayModule(Name, Params : PathStr) : Boolean; far;
{ AND THERE IS NO LOCAL AT ALL. `[BP-1]` is the FUNCTION RESULT: the tail of the
  routine is `8a 46 ff / c9 / ca 08 00`, `MOV AL,[BP-1] / LEAVE / RETF 8`, which is
  Turbo Pascal loading a Boolean result out of its frame slot on the way out. Borland
  allocates that slot at the TOP of the frame, above the value-parameter copies -- so a
  separate `Ok : Boolean` lands BELOW them instead, at [BP-$a3], and every reference to
  it grows from `c6 46 ff 01` to `c6 86 5d ff 01`. This file already carries the rule as
  "assign to the function identifier, not to a local"; the three assignments below do
  that now, and the closing `PlayModule := Ok` is gone with the variable. }
begin
  Complain := False;                              { 1000:02dc }
  PlayModule := True;                             { 1000:02e1 }
  ShowBanner;                                     { 1000:02e5 }

  if ShellLoopMod then                                 { 1000:02e8 }
  begin
    LoopMod := True;                              { 1000:02ef }
    ForceLoopMod := True;                              { 1000:02f4 }
  end;

  SetVTDevice;                                     { 1000:02f9 }
  asm
    LES  DI, ActiveDevice        { 1000:02fe                                       }
    CALL DWORD PTR ES:[DI+1Ah]         { 1000:0302  a second driver method               }
  end;
  SetVTFreq;                                       { 1000:0306 }
  MaxOutputFreq := DesiredHz;                      { 1000:030b  $02ce := $0bae }
  { 1000:0311..0320 -- a FillChar, NOT the Str this file used to read here.
    survey.py puts 1ba1:0fd5 at both 031c and 03da, and 14b9 already
    established 1ba1:0fd5 as FillChar. The pushes are dest, count, VALUE:
    DS:$1208 for eight bytes of whatever $08ba holds. }
  FillChar(UserVols, 8, VtVolume);                  { 1000:0311..0320 }
  Song.Init;                     { 1000:032a }
  Song.SetInsidePath(Params);                   { 1000:033a }

  if VT1stPattern <> 0 then Song.SongStart := VT1stPattern;  { 1000:033f }
  if VTSongLen <> 0 then Song.SongLen := VTSongLen;          { 1000:034c }
  StartSampling;                                  { 1000:0359  1a17:00a9 }
  Song.LoadFName(Name);                         { 1000:0368 }

  PlayModule := False;                            { 1000:036d }
  if Song.Status <= 2 then                           { 1000:0371 }
  begin
    PlayModule := True;                           { 1000:0378 }
    PlayStart(Song);                         { 1000:0381 }
    asm
      MOV  DI, OFFSET Heap   { 1000:0386                                  }
      PUSH DS                   { 1000:0389                                  }
      PUSH DI                   { 1000:038a                                  }
      MOV  DI, [DI]             { 1000:038b  its VMT                         }
      { NO `ES:` HERE, AND THE DIFFERENCE IS WHICH REGISTER HOLDS THE OBJECT.
        `MOV DI, OFFSET Heap` puts a DGROUP offset in DI, so the VMT fetch and the
        call through it are both DS-relative and the original emits no prefix --
        `ff 5d 18`. The four calls in PollDriver and the one at 0302 DO carry `26`,
        because those reach the driver through `LES DI, ActiveDevice` and are
        ES-relative. Same instruction, two addressing bases, one byte apart. }
      CALL DWORD PTR [DI+18h]               { 1000:038d                                  }
      MOV  WORD PTR [OFFSET SavedCD], AX{ 1000:0390                                  }
      MOV  WORD PTR [OFFSET SavedCD+2], DX{ 1000:0393                                  }
    end;
    ShrinkSystemHeap(0);                         { 1000:039b }
    SwapVectors;                                  { 1000:03a0 }
    Exec(ProgName, ShellParam);                        { 1000:03af  1b6f:00df }
    UnhookTimer;                                  { 1000:03b4  a NEAR call   }
    SwapVectors;                                  { 1000:03b7 }
    ShrinkSystemHeap(SavedCD);           { 1000:03c4 }
    PlayStop;                                     { 1000:03c9 }
    { 1000:03ce..03de -- the OTHER FillChar, and the argument says what it is
      for: `PUSH -0x80` is $80, which is SILENCE for unsigned 8-bit audio. It
      wipes the whole DMA buffer after the shell-out, so whatever the shelled
      program left in it cannot be played back. }
    FillChar(DMABuffer^, DMABufferSize, $80);     { 1000:03ce..03de }

    { 1000:03df..03f0 -- three Words copied straight across, which is all the
      `Copy8C2To342` placeholder ever stood for. }
    ReqStart := VT1stPattern;                             { 1000:03df }
    ReqEnd := VTRepStart;                             { 1000:03e5 }
    ReqLen := VTSongLen;                             { 1000:03eb }
  end;

  asm
    XOR  AX, AX            { 1000:03f1                                       }
    PUSH AX                { 1000:03f3                                       }
    MOV  DI, OFFSET Song   { 1000:03f4                                       }
    PUSH DS                { 1000:03f7                                       }
    PUSH DI                { 1000:03f8                                       }
    MOV  DI, [DI]          { 1000:03f9  the song object's VMT                }
    CALL DWORD PTR [DI+4]              { 1000:03fb  Done(0); DS-relative, see 038d       }
  end;

  { 1000:03fe is `MOV AL,[BP-1]`, the epilogue loading the result -- not a statement. }
end;

{ ==========================================================================
  1000:04e0 -- the body. The init chain that precedes it is at 1000:04b3:

      1ba1:0000  the RTL      193a:0488   1931:0029   17cf:0a93
      14b7:0000  12ba:141e    11bb:0f2e   1084:0101   1065:0172
  -------------------------------------------------------------------------- }
{ ~~Self : String at [BP-$100]~~ -- NOT A VARIABLE. `[BP-$100]` is the COMPILER'S
  256-byte temporary for `ParamStr`'s result: 1000:0542 is `LEA DI,[BP-0100] / PUSH SS /
  PUSH DI / PUSH 0 / CALLF 1ba1:0fe9`, and a String function is handed the address of a
  temporary to build its result in. Declared as a variable it became a GLOBAL -- a
  program's `var` section is global in Pascal -- and the temporary got COPIED into it,
  which is the thirteen bytes this segment was over: five to push the destination, three
  for `PUSH 00FFh` and five for the string-copy call.

  AND THE STATEMENT IS ONE CALL, NOT TWO. `FSplit`'s first argument is ParamStr's result
  POINTER, still on the stack because a String function does not pop it -- the original
  pushes only the three VAR parameters after the call and then goes straight into
  `1b6f:0241`. **Third instance of that rule in this file**, after `Cmd.ParseLine(
  GetDOSCmdLine)` and the two in 14b9's `LoadFName`. }
var
  { FSplit at 1000:0556 needs all three, and Dos supplies the widths:
    DirStr is String[67], NameStr String[8], ExtStr String[4] -- the same
    arithmetic that settled 14b9's FileName and FileExt. }
  Dir  : DirStr;
  Name : NameStr;
  Ext  : ExtStr;

begin
  if ParamCount = 0 then                          { 1000:04e4 }
  begin
    ShowBanner;                                   { 1000:04ed }
    { THREE `WriteLn`s, NOT SIX. Each bare `WriteLn` costs ten bytes -- five to push
      `Output` again and five for the call -- and the original has none of them: the
      three groups from 04fc to 0534 are each `[PUSH Output][PUSH CS:literal][PUSH 0]
      [CALL Write][CALL WriteLn]` and nothing between. `WriteLn(X)` already ends the
      line; the extra ones would print three blank ones. }
    WriteLn(UsageTop);                            { 1000:04fc }
    WriteLn(UsageMid);                            { 1000:0512 }
    WriteLn(UsageBot);                            { 1000:0528 }
    Halt(1);                                      { 1000:0535 }
  end;

  FSplit(ParamStr(0), Dir, Name, Ext);            { 1000:0542..055a  1b6f:0241 }

  { 1000:0565 -- renaming the executable to INCONEXI.EXE turns something on.
    Nothing in this segment reads DS:$02d1. }
  if Name = AltName then AltMode := True;         { 1000:056c }

  ChainPtr := @TimerChain;                        { 1000:0577 }
  asm
    LES  DI, ChainPtr      { 1000:057e                                       }
    XOR  AX, AX            { 1000:0582                                       }
    MOV  ES:[DI+1], AX     { 1000:0584  start out plainly unhooked           }
    MOV  ES:[DI+3], AX     { 1000:0588                                       }
  end;

  CtrlBlock.Dispatch := @Dispatch;                { 1000:058c  -> DS:$23e7 }

  Install(SelfName, @CtrlBlock);                  { 1000:05a3  1b54:0088 }

  InitHeapVariables;                                 { 1000:05a8 }
  InitUmbHeap;                                    { 1000:05ad }
  { 1000:05b2 pushes a VMT offset of $009e and far-calls 1891:0000, TObject.Init,
    so `Cmd` inherits its constructor rather than declaring one -- which is
    exactly what TVTCmd does. 05c4 pushes $07fe and calls 1891:03a7,
    TCollection.Init, NOT TSortedCollection's: see the note on SongColl's type. }
  Cmd.Init;                                       { 1000:05bb  1891:0000 }
  SongColl.Init(1, 1);                            { 1000:05cd  1891:03a7 }
  InitSoundDevices;                               { 1000:05d2  1a17:053c }
  BuildNoteTable;                                 { 1000:05d7  1650:0000 }
  DesiredHz := ShellHz;                               { 1000:05dc }
  OneModPtr := @PlayModule;                       { 1000:05e2  -> DS:$009a }
  Complain := True;                               { 1000:05ef }
  { ONE STATEMENT, NOT TWO, and the stack is what says so. 05f4 pushes
    SS:[BP-0100] and calls GetDOSCmdLine, which is a STRING FUNCTION and so does
    NOT pop its own hidden result pointer -- the caller does. 05ff then pushes
    only `Self` before the virtual call, so the pointer still sitting there IS
    ParseLine's `S`. Slot +$08 is ParseLine, per CMDLINE's declaration order.
    Written as two statements the temporary is discarded and ParseLine has no
    argument to take. See CONTINUATION.md, "a String function's result pointer
    is reused as the following assignment's source" -- the same rule, one call
    further on. }
  Cmd.ParseLine(GetDOSCmdLine);          { 1000:05f4, 05fa 116e:04b2, 0606 +$08 }

  if DoSongColl(Cmd.FileDir) and Complain then     { 1000:060e, 1000:0617 }
    WriteLn(NoSong);                              { 1000:062a }

  EndSampling;                                    { 1000:0634  1a17:013e }
  ShowBanner;                                     { 1000:0639 }

  { NO EXPLICIT `Halt(0)`, AND THE ORDER OF THE LAST THREE INSTRUCTIONS IS WHY.
    The original ends `e8 bc fa / c9 / 31 c0 / 9a e9 00 a1 0b` -- the near CALL to
    ShowBanner, then LEAVE, then `XOR AX,AX / CALLF 1ba1:00e9`. The LEAVE comes BEFORE
    the Halt, which no statement can produce: a written `Halt(0)` sits inside the block
    and is emitted before the epilogue, not after it. So those seven bytes are Turbo
    Pascal's own end-of-program sequence, and writing the call as well emitted it twice.
    The code ends at 0643, and 1616 - 1604 is twelve bytes of segment padding. }
end.
