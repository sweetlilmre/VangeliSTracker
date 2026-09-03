{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  THE PROGRAM ITSELF -- start here.

  WHAT DEMOVT DOES, END TO END. It reads the config file and the command line,
  finds a sound card and opens it, goes resident on INT 2Fh so a demo can find
  it, and then walks its playlist: load a module, play it, run whatever program
  the entry names, and move on. When the list is finished or a client sets the
  Abort flag, it unhooks everything and exits.

  ITS REAL JOB IS TO BE A BACKGROUND SERVICE. The player runs off the timer
  interrupt, so once a module is going this program has nothing to do -- and
  that is the point. It shells out to the demo, the demo draws, the music keeps
  playing underneath, and the two stay in step through the control block.

  THE INIT CHAIN IS THE OTHER HALF OF THE STORY. Turbo Pascal runs every unit's
  initialisation section before the body, in link order, and that is where the
  drivers register themselves and the resident handler is installed. By the
  time the first statement of the body runs, the program is already findable.

  NAMES ARE PROVISIONAL. The binary is Borland Pascal 6 with no debug
  information, so no unit or routine name survives. Everything here is named
  for what it does, and every name is followed by the address it was read
  from.

  [re] ADDRESS MAP
  [re] VERIFIED in this image: 64 bytes unchanged at 1000:0000 -- the map was already right.
    banner text   1000:0000  four String[61], stride 62
    ShowBanner    1000:00f8     TimerChain    1000:016b
    PollDriver    1000:0171     TimerHandler  1000:01a5
    HookTimer     1000:01bd     UnhookTimer   1000:020a
    Dispatch      1000:024c     PlayModule    1000:02b5
    usage text    1000:0405  three String[44], then two more
    [re] init chain    1000:04b3     the body      1000:04e0

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

    [re] 1086:0000 SetVTDevice     1086:0038 SetVTFreq    1086:0724 DoSongColl
    1182:04b2 GetDOSCmdLine   12ce:10a1 PlayStart    12ce:13d7 PlayStop
    153a:0000 TSong.Init      153a:0106 LoadFName    153a:02f5 SetInsidePath
    19b7:00b5 InitUmbHeap     19b7:01d3 ShrinkSystemHeap
    19b7:0a63 InitHeapVariables
    1a79:0000 TObject.Init    1a79:03a7 TCollection.Init
    1d57:00a6 SwapVectors     (twice, around the Exec)

  [re] THE INIT CHAIN AT 1000:04b3 IS THE CONSTRAINT ON THIS `uses` CLAUSE, and it
  is not a free choice. Turbo Pascal emits one call per unit that HAS an
  initialisation section, in dependency-resolved order, and the original's is

      1d89:0000  RTL        1b22:0488  DevSB      1b19:0029  VTShell
      19b7:0a93  Heaps      1538:0000  VTCtrl     12ce:141e  PlayMod
      11cf:0f2e  VTCfg      106e:0101  DevGus     115e:0172  VTSilenc
      1d89:1038  RTL exit

  so the clause below has to produce exactly that order. Units with no
  initialisation section never appear in the chain however they are listed.

  AND **DevSB REGISTERS BEFORE DevGus**, which decides the default device.
  DEVGUS.PAS records that InitDevice pushes onto the front of the list but
  selects only when nothing is selected yet, so the FIRST to register wins --
  and that note concluded "a machine with both ends up on the GUS" while
  comparing DevGus against VTSilenc alone. With 193a in the chain the SB
  registers first. Whether that changes the conclusion is not settled here;
  it is flagged because the note was written without this segment. }
{ [re] THE ORDER OF THIS CLAUSE IS THE PROGRAM'S SEGMENT LAYOUT, AND IT IS SOLVED RATHER
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

  [re] The entries after the blank line are already finished by the time the walk reaches
  them, so they are no-ops in the ordering and their position is unobservable FROM THE
  SEGMENT MAP. It is not unobservable in general, and `VTGlobal` is the proof: it emits
  no segment, so the map says nothing about it, but it does emit DATA, and its block
  sits between VTShell's and DevSB's in the original's DGROUP. That is what moved it up
  into the ordered group. Any other declarations-only unit with initialised data can be
  placed the same way -- `dgroup.py` is the instrument, not `mapcmp.py`. }
uses
  Dos, VTResid, DevSB, VTGlobal, VTShell, Objects, Heaps, PlayMod, VTCfg,
  { [re] ~~VTSilenc MOVED AHEAD OF VTCmd~~ -- **IT GOES AFTER, AND CMDLINE IS WHY.** The
    earlier note had VTSilenc finishing before VTCmd's whole subtree, which produces
    DEVGUS, VTCMD, FILEUTIL, ..., CMDLINE, VTSILENC -- right for the first four and
    one place out for the last two. The original is DEVGUS, VTCMD, FILEUTIL,
    VTSILENC, CMDLINE, so reading the reverse post-order backwards, the finish order
    has to be CmdLine, then VTSilenc, then FileUtil, and all three inside VTCmd.

    So VTSilenc must NOT be reached from here before VTCmd. It is named last in this
    clause instead, where it is already visited and the mention costs nothing; what
    orders it is VTCMD's own implementation list, which now reads GUS, VTSilenc,
    FileUtil. Two edges in two files for one position. }
  VTCmd, DevGus,

  SoundDevices, SongUnit, VTCtrl, CmdLine, VTNotes, Hardware, VTDosMem,
  ModCommands, VTSilenc;

{ [re] `Guard` IS A TYPED CONSTANT, NOT A VAR, and that is the only thing that can put it
  at $0002. DGROUP is laid out as ALL the units' typed constants in link order and then
  all their variables, so anything in the initialised image -- which is what the EXE
  actually stores, and what `dgroup.py` reads -- has to be a constant. The
  original's image opens with four zero bytes and SelfName at $0004; declared a `var`
  this byte went to the variable region instead and left ours opening with two.

  Moving it around the source as a `var` was tried first and moved nothing, which is
  how the const/var split got established: **TP6 emits a unit's typed constants before
  its variables regardless of the order the sections appear in.** A typed constant is
  writable in Turbo Pascal, so `Inc(Guard)` is still legal.

  [re] What was already settled is the width. `Guard` is a BYTE, not a Word: 1000:0174 is
  `80 3E 02 00 00`, `CMP byte [0002],0`, and 1000:017b is `FE 06 02 00`, `INC byte`
  -- a Word gives the `83 3E` and `FF 06` forms instead. So $0003 is a PAD, which is
  TP word-aligning `SelfName` after it; the same alignment shows up three more times
  in VTGlobal's block. }
const
  Guard     : Byte = 0;  { DS:$0002  the poll re-entrancy guard }

  { [re] DS:$0003 and DS:$0004, AND THE LAYOUT IS WHAT FOUND THEM. `dgroup.py` puts this
    unit's block at 20 bytes in the original against our 24, and the original's
    version string starts at $0006 where 1.31b's starts at $0004 -- so two bytes went
    in ahead of it. A scan of the image for absolute references to $0004 finds
    exactly two, both in this segment: `CMP byte [0004],0 / JZ` at 1000:02f7 and
    `MOV byte [0004],1` at 1000:03c8. A BYTE, set and tested, and nothing else
    touches it.

    $0003 IS STILL THE PAD 1.31b HAD -- it has to be declared now rather than left to
    the compiler, because the flag below would otherwise take that slot and the
    string would land two bytes early. A pad that was invisible while it was the last
    thing before an aligned field becomes a real declaration the moment something
    follows it. }
  Fill0003  : Byte = 0;  { DS:$0003  1.31b's alignment pad, now explicit }
  { [re] **NAMED FOR WHAT IT GUARDS, WHICH IS THE ONLY THING THAT CAN NAME IT.** There is
    one writer -- 1000:03c8, immediately after `Song.LoadFName` returns -- and one
    reader, 1000:02f7, which decides whether `StopModule` calls `Song.Done`. That pair
    says the byte means "the song object owns a file", and nothing in the image says
    more. An address is not a name; a writer and a reader together are. }
  SongOpen  : Boolean = False;  { a module is loaded and not yet freed        }

  { [re] DS:$0005 -- A SECOND FLAG, AND $0003 IS THE ONLY PAD. The version string starts at
    $0006 and Guard is at $0002, so those four bytes are accounted for exactly: a byte
    at $0003, then two flags. 1000:02ca reads this one with `CMP byte [0005],0 / JZ`,
    guarding a block that reloads three words from another unit's data. Declared
    rather than left as the compiler's alignment, because a pad and a variable are the
    same byte until something reads it.

    [re] **THE NAME COMES FROM THE PAIRING, NOT FROM THE SET.** It is written at 1000:03df
    inside `if Song.Status <= 2` -- so only when the song actually started -- and read
    to decide whether the timer needs UNHOOKING, the DMA buffer silencing and the
    requested range restoring. Everything it guards is a teardown of something the
    start-up did, which is what makes "started" the right word rather than "playing":
    the byte stays set after the module ends. }
  PlayerStarted : Boolean = False;  { the mixer has been started              }

  { [re] 1000:0000, FOUR SEPARATE UNTYPED CONSTANTS on a stride of 62 -- CP437 box
    drawing. NOT an `array[1..4] of String[61]`, which is what this was, and the
    difference is where the bytes live: a TYPED constant is initialised DGROUP data
    and an UNTYPED one is a literal that Turbo Pascal lays down in the CODE segment.
    The original has them in CODE at 1000:0000..00f7, with ShowBanner's own code
    starting at 00f8 -- which is also the rule this project already knows, that a
    routine's literals are emitted immediately before it.

    [re] THREE THINGS SAY SO INDEPENDENTLY, and the array form contradicts all three:
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
  { [re] THE VERSION AND THE YEAR BOTH MOVE, and both are same-length substitutions --
    each line is $3d bytes in the original as it is here, so the box still closes.
    1000:0077 is `35 31` where ours had `33 31`, and 1000:0097 is `39 34` for `39 33`. }
  Banner2 = '    ' + #179 + '  DemoVT.  VangeliSTracker''s version for demos, v1.51  ' + #179;
  Banner3 = '    ' + #179 + '                (C) 1992-94  VangeliSTeam              ' + #179;
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

  { [re] 1000:048c -- compared against the program's OWN file name. Renaming the
    executable to INCONEXI.EXE sets DS:$02d1, which nothing in this segment
    reads; whatever it selects lives in a unit not yet read. }
  AltName  = 'inconexi';

  { 1000:0501 -- **AND IT IS IN ENGLISH IN v1.51.** 1.31b carries the Spanish
    `No encuentro ninguna canci' + #162 + 'n.` -- twenty-nine characters and a CP437
    o-acute; the original's is `12 "Can't find a song."`, eighteen. The length byte is
    what identifies it: $1d against $12, and the text follows immediately.

    THE STRING GOT SHORTER, WHICH IS WHY IT WAS NOT FOUND EARLIER. Everything after it
    in the code segment moves ELEVEN BYTES down, and a routine-size check that is
    already reporting the segment short by more than that has nothing to catch it on.
    Only an aligned byte diff of the segment shows a literal changing. }
  NoSong   = 'Can''t find a song.';

  { [re] 1e92:0004 -- the name Install publishes over INT 2Fh. A TYPED constant, so it
    lives in DGROUP rather than in the code segment, and TWO measurements say so:
    1000:0599 is `MOV DI,0004 / PUSH DS / PUSH DI`, and PUSH DS against PUSH CS is
    this project's standing test for where a constant lives -- an untyped one is a
    literal in CODE. And the LENGTH follows from the neighbour: VTSilenc's `Driver`
    is the next unit's first datum and the original puts it at $001e, so this
    occupies $0004..$001d, which is 26 bytes, which is String[25]. The declared
    length was read as String[25] on the strength of VTSilenc's `Driver` starting at
    $001e -- and that was wrong, because the six bytes between are not this string's.
    **THEY ARE VTSILENC'S `Frac` AND `OldVec`**, two typed constants at $0018 and $001a
    which its own code names outright: `115e:0018` is `MOV AL,[0018]` and `115e:005e`
    tests `[001a]`. So this is `String[19]`, exactly as long as its text.

    [re] **AND `dgroup.py` REPORTING THE INITIALISED HALF IDENTICAL DID NOT CATCH IT.** Every
    byte from $0018 to $001d is zero whichever way the six are divided, so the image is
    the same and the SIZES were still wrong. A byte comparison of initialised data cannot
    see a boundary inside a run of zeros; only an instruction that names an address can,
    and `linkcmp.py` is what reads those. }
  { **String[13] AND 'DemoVT v1.51'.** The declared width is measured, not chosen:
    the field runs from $0006 to $0013 because DEVGUS's block -- whose first typed
    constant is the driver record beginning `03 'GUS'` -- starts at $0014, and
    $0014 - $0006 - 1 is 13. The release dropped the `(beta)` and the string got
    shorter with it. }
  SelfName : String[13] = 'DemoVT v1.51';

var
  { [re] ~~PlayProc $009a and AltMode $02d1~~ -- BOTH GONE, and both were other units'.

    [re] `PlayProc` IS `VTCmd.OneModPtr`, THE HOOK THE PLAYLIST CALLS THROUGH. $009a is four
    bytes immediately below TVTCmd's VMT at $009e, inside VTCmd's block, and VTCMD.PAS
    already declares it: `OneModPtr : Pointer = nil` with `OneMODProc : TDoOneProc
    absolute OneModPtr` laid over it, which is how 1993 Pascal gives a procedural
    variable an initial value. `1000:05e2` installs this program's `PlayModule` into it
    and `DoSongColl` calls it for every entry it collected -- and clears it again at
    1086:079f, which this project had already read as "the caller's hook cannot outlive
    the collection". The two ends of the same mechanism, finally joined up.

    `AltMode` IS PLAYMOD'S, at $02d1, between `DontExecute` and `Playing` in its
    address-ordered const block -- the one insertion 1.31 makes in the release's
    sequence. This program SETS it (when the executable is called INCONEXI.EXE) and
    12ba is the only reader, which is why it was declared in both. }
  { [re] ~~NoBanner : Boolean at DS:$09e8~~ -- GONE. It is `VTGlobal.NoBanner`, the same byte,
    and this program declared a second name for it. $09e8 is inside VTGlobal's DGROUP
    block ($083a..$09e8, and it is the LAST byte of it), so it cannot have been this
    program's; and the behaviour is one thing, not two -- `109c`'s `nb` switch suppresses
    the banner by setting it, and ShowBanner sets the same byte so the banner prints
    once. The note under `nb` in VTGLOBAL.PAS has described it that way all along. }
  { [re] ~~Driver : Pointer at DS:$0b96~~ -- GONE. $0b96 is `SoundDevices.ActiveDevice`,
    the selected driver, and this program declared a second name for it. The DGROUP
    layout is what settled it: $0b96 is the second datum of SoundDevices' block
    ($0b94 NumDevices, then this), so it cannot have been the program's. Every
    `LES DI, Driver` below is now `LES DI, ActiveDevice`. }
{ [re] THIS PROGRAM'S VARIABLE BLOCK, $0c6e..$0e2c, IN ADDRESS ORDER. The variable half of
  DGROUP is laid out per unit in link order exactly as the constant half is, and this
  program is first, so its block opens the region. It is not in the EXE -- a `var` is
  space the linker never writes -- but every instruction that touches one carries the
  resolved address, so `linkcmp.py` reads the layout back out of the CODE.

  The order below is the original's, taken from those operands:

      $0d16 ChainPtr   $0d1a Complain   $0d1c Song (94 bytes)   $0d9a SavedCD
      $0d9e Str1208 (256)               $0dd6 four bytes unidentified
      $0dda Dir        $0e1e Name       $0e28 Ext -> VTSilenc's block at $0e2e

  [re] `Song` used to be declared LAST and is second; `Str1208` was carrying `DS:$1208`,
  which is PlayMod's `UserVols` and not this at all -- its real address is $0cd6, and
  256 + 4 is exactly the gap between `SavedCD` and `Dir`. }
  ChainPtr  : Pointer;   { DS:$0d16 -> TimerChain }
  Complain  : Boolean;   { DS:$0d1a  and a pad at $0c73 }
  Song      : TSong;     { the module currently loaded, if any             }

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
  { [re] ~~ELEVEN `Var<addr>` PLACEHOLDERS USED TO BE DECLARED HERE~~ and every one of them
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

    [re] `Song.Status` is the interesting one: $0ccd is not a variable at all. `Song` is this
    program's own `TSong` at $0c74 -- `1000:0322` is `MOV DI,0C74h` and the two virtual
    calls at `03fb` and `038d` go through it -- and $0c74 + $59 is $0ccd, which is the
    record's `Status`. The reading had it as a standalone byte because a field of a
    global and a global of its own look identical in a `MOV`.

    [re] None of this could be seen before the layout: a DGROUP reference is a linker fixup,
    so `units.py` excused every one and the program compiled either way. }
  { [re] ~~VarC76 $0c76 and VarC78 $0c78~~ -- NOT VARIABLES. `Song` is at $0c74 and is 94
    bytes, so both of these are INSIDE it: $0c74 + 2 is `SongStart` and + 4 is `SongLen`,
    which SONGUNIT.PAS already declares as the record's first two fields. The two
    statements that used them read `if VT1stPattern <> 0 then Song.SongStart := ...` --
    the program copying the play range the command line asked for into the song it is
    about to play, which is what `VT1stPattern` and `VTSongLen` are for. }
  { [re] DS:$0cd2, ONE LongInt rather than two Words: ShrinkSystemHeap takes a
    LongInt and 1000:03c4 pushes both halves of this pair into it. The asm at
    0390 stores AX and DX into $0cd2 and $0cd4, which is the same object seen
    from the other end. }
  SavedCD   : LongInt;   { DS:$0d9a }
  { [re] ~~TickSnapshot $0bca, LastTick $0058, DriverTicks $0bd0~~ -- ALL THREE GONE, and each
    was a second declaration of a global another unit owns. The layout is what settled
    it: $0bca and $0bd0 are inside SoundDevices' block ($0b94..$0c0b) and $0058 is
    inside DevGus's ($0058..$0099), while this program's own data is at $0000..$001d
    and above $0c70. The names they now carry are `SoundDevices.TickSnapshot`,
    `DevGus.LastTick` and `SoundDevices.DriverTicks`; the dispatcher below writes all
    three by those names. }
  { [re] DS:$0cd6 -- 256 bytes, and its address comes from its NEIGHBOURS rather than from
    any instruction: nothing in the program references it, so no operand names it. What
    fixes it is that `SavedCD` ends at $0cd5 and `Dir` begins at $0dda, and 256 + 4 is
    the gap. It used to be quoted at DS:$1208, which is PlayMod's `UserVols`. }
  Str1208   : String;    { DS:$0d9e }

  { DS:$0e9e -- FOUR BYTES THIS TRANSCRIPTION CANNOT NAME, between the string above and
    `Dir` at $0dda. Nothing references them. Filler, so the SIZE is right and the
    missing name is stated rather than invented. }
  { **FOUR BYTES, AND 1.31b HAS THE SAME FOUR.** There they are `Fill0DD6`, with
    a note that reads almost word for word like this one -- four bytes this
    transcription cannot name, between the string above and what follows. Two
    versions, two independent readings, the same silence.

    THAT IS THE END OF WHAT EVIDENCE CAN DO HERE. This build is byte-identical and
    its source names these bytes nowhere, so no instruction in the original names
    them either; the v1.39b release has no counterpart for this unit at all, since
    its main program is a tracker rather than a player. They are not a defect and
    not a gap in the transcription -- they are four bytes the program reserves and
    never uses. }
  Fill0E9E  : LongInt;   { DS:$0e9e }
  { [re] ~~Obj0E38 : TObject~~ and ~~Var0F82 : TCollection~~ ARE GONE. They were
    VTCmd's own `Cmd` and `SongColl`, and declaring stand-ins here is what kept
    both CMDLINE and VTCMD out of the linked image -- see the body at 1000:05bb.
    DS:$0e38 and DS:$0f82 are their measured addresses; VTCMD.PAS carries them. }
  { [re] ~~Var0F3A $0f3a~~ -- ALSO NOT A VARIABLE. `Cmd` is at $0e38 and $0e38 + $102 is
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
  Print the four-line startup banner -- ONCE. The flag that suppresses it is
  also SET here, so the second caller prints nothing.

  [re] 1000:00f8. Guarded by DS:$09e8, because both the
  body and PlayModule call it.
  -------------------------------------------------------------------------- }
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
{ [re] IT IS `far`, AND THE BYTE AT $0170 IS ITS EPILOGUE RATHER THAN DATA. This used to
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

  [re] Four calls, not a loop: the binary has the LES/CALLF pair written out four
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

  [re] This is the routine every Psycho Neurosis part far-calls. Its address is
  published at CB+$121 (DS:$23e7) by the body, and the demo finds it through
  the INT 2Fh handshake. See ../v1.31b/docs/01-int2f.md.

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
          DriverTicks := 0;                         { 1000:02a6  $0c78 := 0     }

          { [re] ~~AFTER THE CASE~~ -- **INSIDE THIS ARM, AND FOUR JUMP DISPLACEMENTS SAY
            SO.** Placed after the case, every arm's exit jumps to 1000:02ab, the
            start of these two statements; the original's four arms jump to 02b6,
            past them. Eleven bytes, four `eb` displacements, and no other byte in the
            segment different -- so the code was right and only its BRACKET was wrong.

            A jump that lands eleven bytes early is not a missing eleven bytes. It is
            the same eleven bytes on the wrong side of an `end`.

            THE PAIR HAS TO BE SET TOGETHER -- `XOR AX,AX / MOV [02e8],AX /
            MOV word [02ea],1`. One slot of daylight is the ring's empty state, so
            zeroing both would make PlayMod's full test fire on the first tick. }
          RingSlot  := 0;                         { 1000:02ab              }
          FlushSlot := 1;                         { 1000:02b0              }
        end;
  end;

  asm
    POP  DS                { 1000:02ab                                       }
    POP  ES                { 1000:02ac                                       }
    POPA                   { 1000:02ad                                       }
  end;
end;

{ --------------------------------------------------------------------------
  LOAD AND PLAY ONE MODULE, and then run whatever program the playlist entry
  named. This is the body of the playlist loop and the closest thing the
  program has to a main routine.

  [re] 1000:02b5. Published at DS:$009a as a far
  pointer, so a unit not yet read is what calls it.

  RETF 8: two String parameters, both copied into String[79] locals.
  -------------------------------------------------------------------------- }
{ THE PARAMETERS ARE `PathStr`, AND THE TWO 80-BYTE SLOTS ARE THE COMPILER'S OWN
  COPIES OF THEM -- not locals, and not statements. `ENTER 00a2,0` is 162 bytes, which
  is 80 + 80 + `Ok` + one pad and nothing else; declared `String` the two value
  parameters get 256-byte copies each and the frame is 676. And `PathStr` is
  `String[79]`, so the `PUSH 4Fh` in each copy is `SizeOf - 1` exactly.

  [re] SO `N := Name` AND `P := Params` WERE NEVER SOURCE STATEMENTS. `1000:02b9` is
  `LES DI,[BP+0a] / PUSH ES / PUSH DI / LEA DI,[BP-52] / PUSH SS / PUSH DI / PUSH 4Fh /
  CALLF 1d89:0add` -- push the source, push the destination slot, push the length, call
  the string-copy helper. That IS how Turbo Pascal copies a value String parameter into
  the frame on entry, and reading it as an assignment produced two extra locals and two
  extra copies. Same class as the invented `String` locals in `1b54` and `164b`: **a
  frame is explained by the parameters before it is explained by declarations.** }
{ --------------------------------------------------------------------------
  THE REGISTER-CONVENTION ENTRY POINT: take the command in AX rather than on
  the stack, and hand it to Dispatch.

  IT EXISTS TO MOVE THE FUNCTION NUMBER FROM A REGISTER TO THE STACK, which is
  what lets a client written in assembler and one written in Pascal both call
  this program without either having to know the other's convention.

  [re] 1000:02c0, NEW IN v1.51. Seven bytes: `PUSH AX / CALLF Dispatch / RETF`,
  with the RETF the compiler's own. `Dispatch`
  takes its selector as a Word parameter; a client reaching this program over INT 2Fh
  has it in AX. 1.31b published `Dispatch` itself and left the caller to push -- this
  stub does it, so the published address and the Pascal signature stop having to agree
  about who owns the argument. }
procedure DispatchEntry; far; assembler;
asm
  PUSH    AX                     { 1000:02c0                                }
  CALL    FAR PTR Dispatch       { 1000:02c1                                }
end;


{ --------------------------------------------------------------------------
  STOP EVERYTHING: unhook the timer, silence the device, free the module.

  Called between playlist entries and again on the way out, so it has to be
  safe to call when nothing is playing -- which is what the SongOpen guard is
  for.

  [re] 1000:02c7, NEW IN v1.51, and it is what the main body calls before
  `EndSampling` at 1000:06b7.

  [re] FOUR ADDRESSES IDENTIFIED IT AND THE LINKER MAP IS WHAT NAMED THEM: $0d1c is `Song`,
  $0c4c is `DMABufferSize`, the near call at 02d1 reaches 1000:020a which this file's
  own address map has as `UnhookTimer`, and the far call at 02c1 above reaches
  1000:024c, `Dispatch`. Reading the map beat reading the instructions, and it was
  available all along -- it only became so once the link order was right.

  [re] `Song.Done` IS A DESTRUCTOR AND THE EXTRA PUSH SAYS SO. 1000:02fe is
  `XOR AX,AX / PUSH AX` BEFORE Self, which is Turbo Pascal's hidden deallocate flag;
  zero means "do not dispose", so this is `Song.Done` on a statically allocated object
  and not a `Dispose`.

  [re] THE BUFFER IS FILLED WITH $80 AND NOT ZERO. Unsigned 8-bit audio has silence at
  mid-scale; SoundDevices' own `StartSampling` does the same thing at 1bff:00f7. }
procedure StopModule;
begin
  if PlayerStarted then                                { 1000:02ca }
  begin
    UnhookTimer;                                  { 1000:02d1 }
    FillChar(DMABuffer^, DMABufferSize, $80);     { 1000:02d4 }

    { The range a caller ASKED for is put back, so the next module starts from the
      command line's own numbers rather than from whatever the last one left. }
    ReqStart := VT1stPattern;                     { 1000:02e5 }
    ReqEnd   := VTRepStart;                       { 1000:02eb }
    ReqLen   := VTSongLen                         { 1000:02f1 }
  end;

  if SongOpen then                                { 1000:02f7 }
    Song.Done                                     { 1000:02fe }
end;


{ @asm 000 1000:02b5 +336 }
function PlayModule(Name, Params : PathStr) : Boolean; far;
{ [re] AND THERE IS NO LOCAL AT ALL. `[BP-1]` is the FUNCTION RESULT: the tail of the
  routine is `8a 46 ff / c9 / ca 08 00`, `MOV AL,[BP-1] / LEAVE / RETF 8`, which is
  Turbo Pascal loading a Boolean result out of its frame slot on the way out. Borland
  allocates that slot at the TOP of the frame, above the value-parameter copies -- so a
  separate `Ok : Boolean` lands BELOW them instead, at [BP-$a3], and every reference to
  it grows from `c6 46 ff 01` to `c6 86 5d ff 01`. This file already carries the rule as
  "assign to the function identifier, not to a local"; the three assignments below do
  that now, and the closing `PlayModule := Ok` is gone with the variable. }
begin
  { [re] **NEW IN v1.51 AND IT IS THE FIRST STATEMENT**, before even `Complain := False`:
    1000:0334's `E8 90 FF` reaches 02c7. Whatever was playing is stopped, silenced and
    disposed of before the next module is looked at -- which is what makes calling
    PlayModule twice in a row safe, and is presumably why the sequence was factored
    out of the shell-out in the first place. }
  StopModule;                                     { 1000:0334 }

  Complain := False;                              { 1000:0337 }
  PlayModule := True;                             { 1000:033c }
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
  { [re] 1000:0311..0320 -- a FillChar, NOT the Str this file used to read here.
    survey.py puts 1d89:0fd5 at both 031c and 03da, and 14b9 already
    established 1d89:0fd5 as FillChar. The pushes are dest, count, VALUE:
    DS:$1208 for eight bytes of whatever $08ba holds. }
  { [re] **THE FOURTH LITERAL EIGHT.** 1000:0372 pushes $10, not 8 -- `UserVols` is
    `TVolumes`, which follows the channel count, and this is the only site that wrote
    the length out rather than asking for it. Written as SizeOf so a fifth cannot
    happen here. }
  FillChar(UserVols, SizeOf(UserVols), VtVolume);   { 1000:036c..037b }
  Song.Init;                     { 1000:032a }
  Song.SetInsidePath(Params);                   { 1000:033a }

  if VT1stPattern <> 0 then Song.SongStart := VT1stPattern;  { 1000:033f }
  if VTSongLen <> 0 then Song.SongLen := VTSongLen;          { 1000:034c }
  StartSampling;                                  { 1000:0359  1bff:00a9 }
  Song.LoadFName(Name);                         { 1000:0368 }

  SongOpen := True;                               { 1000:03c8 }

  PlayModule := False;                            { 1000:03cd }
  if Song.Status <= 2 then                        { 1000:03d1 }
  begin
    PlayModule := True;                           { 1000:03db }

    { **NEW IN v1.51 -- THE CONTROL BLOCK IS RESET FOR THE NEW MODULE, and every
      address in the block confirms TCtrlBlock's layout from the outside.** $461a is
      CtrlBlock itself; $471a is CB+$100, the thirty-two `ChansTrig` flags; $4747 is
      CB+$12D, the 128-byte `ChansData` row; $473f is CB+$125, `TickCounter`; $47c7
      and $47c8 are CB+$1AD and CB+$1AE; $481d is CB+$203, `JumpNewPos`. Six fields
      measured one at a time in PlayMod and VTCtrl, all landing where this routine
      puts them -- and all six now confirmed by the client bindings the v1.5
      distribution ships.

      THE TWO INDICES START AT ONE, NOT ZERO, which is the same convention
      NotePlaying and SeqPlaying carry inside TPlayingNote -- row 1 of order position
      1, not a zero that would read as "before the start".

      THE 256 BYTES ARE THE SEMAPHORE ARRAY, and DEMOVT.DOC names this very
      instruction: "When DemoVT is started, all semaphores are set to zero." A
      client that polls a semaphore must not see the previous module's count.

      This paragraph called them "the 1.31b-era per-channel tally" and cleared
      them under the name `Filler1`, which is what a correct transcription of an
      un-understood field looks like: the byte count right, the site right, the
      meaning absent. Cleared BY NAME regardless, because `FillChar(CtrlBlock, ...)`
      with a length of $100 says the same thing to the compiler and something false
      to a reader -- and that much was right both before and after. }
    PlayerStarted := True;                             { 1000:03df }

    FillChar(CtrlBlock.Semaphores,
             SizeOf(CtrlBlock.Semaphores), 0);       { 1000:03e4 }
    FillChar(CtrlBlock.ChansTrig,
             SizeOf(CtrlBlock.ChansTrig), 0);       { 1000:03f3 }
    FillChar(CtrlBlock.ChansData,
             SizeOf(CtrlBlock.ChansData), 0);     { 1000:0401 }

    CtrlBlock.TickCounter     := 0;                   { 1000:0410 }
    CtrlBlock.Pos := 1;                   { 1000:0418 }
    CtrlBlock.Seq  := 1;                   { 1000:041d }
    CtrlBlock.JumpNewPos    := 0;                   { 1000:0422 }
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
    Exec(ProgName, ShellParam);                        { 1000:03af  1d57:00df }
    { [re] ~~UnhookTimer, PlayStop, THE FillChar AND THE THREE Req COPIES STOOD HERE~~ --
      **ALL FIVE MOVED INTO `StopModule` IN v1.51.** 1.31b runs the whole
      unhook-silence-restore sequence inline in the middle of the shell-out; 1.51's
      PlayModule goes straight from the Exec to `ShrinkSystemHeap(SavedCD)` and its
      epilogue -- 1000:0464 is the restore and 0471 is `MOV AL,[BP-1]`, with nothing
      between them.

      THE DUPLICATE IS WHAT FOUND IT. Writing StopModule left this routine 53 bytes
      LONGER than the original while the segment was still short overall, and the
      extra bytes disassembled to the same instructions the new routine has. Two
      copies of one sequence is what factoring out looks like from the wrong side. }
    SwapVectors;                                  { 1000:045f }
    ShrinkSystemHeap(SavedCD);                    { 1000:0464 }
  end;

  { [re] ~~AND `Song.Done` STOOD HERE~~ -- it is StopModule's last statement now, guarded by
    `SongOpen` rather than run unconditionally. 1000:0471 is the epilogue and it
    follows `ShrinkSystemHeap` directly. }
end;

{ ==========================================================================
  THE BODY: read the settings, open a device, go resident, walk the playlist.

  Everything the units set up for themselves has already happened by the time
  the first statement here runs -- the drivers are registered and the resident
  handler is installed by their initialisation sections, in link order.

  [re] 1000:04e0. The init chain that precedes it is at 1000:04b3:

      [re] 1d89:0000  the RTL      1b22:0488   1b19:0029   19b7:0a93
      1538:0000  12ce:141e    11cf:0f2e   106e:0101   115e:0172
  -------------------------------------------------------------------------- }
{ [re] ~~Self : String at [BP-$100]~~ -- NOT A VARIABLE. `[BP-$100]` is the COMPILER'S
  256-byte temporary for `ParamStr`'s result: 1000:0542 is `LEA DI,[BP-0100] / PUSH SS /
  PUSH DI / PUSH 0 / CALLF 1d89:0fe9`, and a String function is handed the address of a
  temporary to build its result in. Declared as a variable it became a GLOBAL -- a
  program's `var` section is global in Pascal -- and the temporary got COPIED into it,
  which is the thirteen bytes this segment was over: five to push the destination, three
  for `PUSH 00FFh` and five for the string-copy call.

  [re] AND THE STATEMENT IS ONE CALL, NOT TWO. `FSplit`'s first argument is ParamStr's result
  POINTER, still on the stack because a String function does not pop it -- the original
  pushes only the three VAR parameters after the call and then goes straight into
  `1d57:0241`. **Third instance of that rule in this file**, after `Cmd.ParseLine(
  GetDOSCmdLine)` and the two in 14b9's `LoadFName`. }
var
  { [re] FSplit at 1000:0556 needs all three, and Dos supplies the widths:
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

  FSplit(ParamStr(0), Dir, Name, Ext);            { 1000:0542..055a  1d57:0241 }

  { [re] 1000:0565 -- renaming the executable to INCONEXI.EXE turns something on.
    Nothing in this segment reads DS:$02d1. }
  if Name = AltName then AltMode := True;         { 1000:056c }

  ChainPtr := @TimerChain;                        { 1000:0577 }
  asm
    LES  DI, ChainPtr      { 1000:057e                                       }
    XOR  AX, AX            { 1000:0582                                       }
    MOV  ES:[DI+1], AX     { 1000:0584  start out plainly unhooked           }
    MOV  ES:[DI+3], AX     { 1000:0588                                       }
  end;

  { [re] ~~@DispatchEntry AND NOT @Dispatch~~ -- **BOTH, AND THAT IS THE POINT.** 1000:05f4
    loads $024c into CB+$121 and 0601 loads $02c0 into CB+$129: the old entry, which
    takes its selector as a Pascal parameter, and the new stub, which takes it in AX.
    Two conventions published side by side so a client written against 1.31b keeps
    working.

    [re] THE STUB STILL HAS TO BE REFERENCED TO EXIST. Turbo Pascal drops an unreferenced
    routine, so writing it and pointing nothing at it emitted no bytes at all and left
    a seven-byte hole exactly where 1000:02c0 is. The second assignment below is what
    brings it into the image. }
  CtrlBlock.CtrlEntryPoint := @Dispatch;              { 1000:05f4  -> CB+$121   }
  CtrlBlock.RegEntryPoint := @DispatchEntry;         { 1000:0601  -> CB+$129   }

  Install(SelfName, @CtrlBlock);                  { 1000:05a3  1d3c:0088 }

  InitHeapVariables;                                 { 1000:05a8 }
  InitUmbHeap;                                    { 1000:05ad }
  { [re] 1000:05b2 pushes a VMT offset of $009e and far-calls 1a79:0000, TObject.Init,
    so `Cmd` inherits its constructor rather than declaring one -- which is
    exactly what TVTCmd does. 05c4 pushes $07fe and calls 1a79:03a7,
    TCollection.Init, NOT TSortedCollection's: see the note on SongColl's type. }
  Cmd.Init;                                       { 1000:05bb  1a79:0000 }
  SongColl.Init(1, 1);                            { 1000:05cd  1a79:03a7 }
  InitSoundDevices;                               { 1000:05d2  1bff:053c }
  BuildNoteTable;                                 { 1000:05d7  183e:0000 }
  DesiredHz := ShellHz;                               { 1000:05dc }
  OneModPtr := @PlayModule;                       { the playlist calls through here }
  Complain := True;                               { 1000:05ef }
  { [re] ONE STATEMENT, NOT TWO, and the stack is what says so. 05f4 pushes
    SS:[BP-0100] and calls GetDOSCmdLine, which is a STRING FUNCTION and so does
    NOT pop its own hidden result pointer -- the caller does. 05ff then pushes
    only `Self` before the virtual call, so the pointer still sitting there IS
    ParseLine's `S`. Slot +$08 is ParseLine, per CMDLINE's declaration order.
    Written as two statements the temporary is discarded and ParseLine has no
    argument to take. See CONTINUATION.md, "a String function's result pointer
    is reused as the following assignment's source" -- the same rule, one call
    further on. }
  Cmd.ParseLine(GetDOSCmdLine);          { 1000:05f4, 05fa, 0606 }

  { [re] **AN EMPTY COLLECTION IS NOT AN ERROR, AND v1.51 SAYS SO FIRST.** 1000:0679 is
    `CMP word [1046],0 / JZ` ahead of the DoSongColl call -- $1046 is VTCmd's
    `SongColl`, whose Count is at +$4. A command line that named no module gets no
    complaint about not finding one, and DoSongColl is not called at all from here.
    Its shell-out path still runs, because `InterpretSwitch` calls it too.

    [re] **`CtrlBlock.Abort` GUARDS THE COMPLAINT TOO, AND THIS IS ITS THIRD READER.**
    VTCMD tests it twice inside DoSongColl and this is the other one: 1000:069a is
    `CMP byte [4821],0 / JNZ` between the `Complain` test and the WriteLn. Every one
    of the three asks the same question -- has something asked us to stop -- and a
    program that is stopping does not complain about what it did not play.

    THIS PARAGRAPH SAID TWICE THAT NOTHING WRITES $4821. It is CB+$207, a published
    control-block field, and the writers are outside this image: the whole point of
    the block is that another program reaches into it. Three reads and no writes is
    not an unfinished switch -- it is exactly what an INPUT looks like, and the shape
    that should have named it. See VTCtrl's declaration. }
  if (SongColl.Count <> 0) and DoSongColl(Cmd.FileDir) and Complain
     and not CtrlBlock.Abort then                        { 1000:0679..06a0        }
    WriteLn(NoSong);                              { 1000:06a1              }

  StopModule;                                     { 1000:06b7              }
  EndSampling;                                    { 1000:06ba  1bff:013e   }

  { **AND THE CLOSING BANNER IS SUPPRESSED WHEN THE PROGRAM HAS JUST COMPLAINED.**
    1000:06bf tests the same `Complain` byte the WriteLn above tests, with the sense
    reversed -- `JZ` there, `JNZ` here. One variable read twice in ten instructions
    to opposite ends, which is why the address had to be checked rather than the
    second test assumed to be a different flag. }
  if not Complain then                            { 1000:06bf..06c5        }
    ShowBanner;                                   { 1000:06c6              }

  { [re] NO EXPLICIT `Halt(0)`, AND THE ORDER OF THE LAST THREE INSTRUCTIONS IS WHY.
    The original ends `e8 bc fa / c9 / 31 c0 / 9a e9 00 a1 0b` -- the near CALL to
    ShowBanner, then LEAVE, then `XOR AX,AX / CALLF 1d89:00e9`. The LEAVE comes BEFORE
    the Halt, which no statement can produce: a written `Halt(0)` sits inside the block
    and is emitted before the epilogue, not after it. So those seven bytes are Turbo
    Pascal's own end-of-program sequence, and writing the call as well emitted it twice.
    The code ends at 0643, and 1616 - 1604 is twelve bytes of segment padding. }
end.
