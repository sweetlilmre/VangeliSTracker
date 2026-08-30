{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  SEGMENT 1a17 -- THE PLAYER CORE. 4304 bytes, the largest unit in the
  program and the one everything else hangs off.

  COMPLETE. Every routine in the segment is transcribed, and 4261 of its 4303
  bytes compare against the original with ZERO real mismatches -- the rest is
  segment padding plus 27 bytes that cannot match from the source: two parked
  compiler differences and three places where wrapping a frameless run in a
  Pascal procedure forces an entry or an exit the original does not have. Each
  is documented where it occurs. See docs/06-transcription.md.

  WHAT THE CORE DOES. It owns the driver list, the selected driver, the
  output rate, the sample buffer, and the mixer. Drivers register themselves
  with it (InitDevice); the configuration code picks one by name
  (VTMain, via 109c); and from then on the core drives everything through
  the driver record's eight slots.

  THIS UNIT IS FULL OF SELF-MODIFYING CODE, and that is not incidental --
  it is how the mixer gets its speed. There are no multiplies in the inner
  loop and no indexed gain lookups. Instead:

    * the gain applied to each channel is a CALL to a hand-built routine
      that does the multiply in shifts and adds, and changing the volume
      means overwriting the CALL's target (SetGains, 1a17:0a81);
    * the downmix loop is unrolled 32 times and entered partway down by
      patching a JMP displacement, so the channel count costs nothing;
    * the re-entrancy guard of the shared poll lives at CS:$104b, INSIDE
      the instruction stream, not in DGROUP.

  Every one of those patch sites is a label here rather than a literal
  address, per the standing rule in docs/06-transcription.md.

  NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information. Every
  routine is named for what it does and carries the address it came from.
  =========================================================================== }

{$G+}   { 80286 code -- required for PUSHA/POPA/ENTER/LEAVE and the shift
          forms this unit uses. The 386 instructions in the gain ladder and
          the mixer are emitted as an explicit DB 66h prefix in front of a
          16-bit mnemonic; see emit_gain.py. }

unit SoundDevices;

interface

uses VTDriver, Dos, Hardware;
  { Dos for SetIntVec/GetIntVec at 1a17:0086; Hardware for GetDMACount at 06ea }

type
  { The release's name for the buffer provider, 1a17:4316. It returns the next
    block to play, or nil when there is none -- see 1a17:03d2, which calls it
    when the queue empties. }
  { The block the provider hands back. Every offset here is read off
    1a17:03d2..0529 and they agree with the release's TSampleBuffer exactly:
    InUse at +0, NSamples at +1, RateHz at +3, Channels at +5, DataType at +6
    and the data pointer at +7.

    THE RELEASE MAKES THIS A VARIANT RECORD, `CASE DataType : TDataType OF
    dtInteger: (IData : PIntBuff); dtShortInt: (SData : PShortBuff)`, and both
    arms are a far pointer at the same offset. Flattened to one field here
    because the layout is identical and nothing in this segment reads it as
    anything but an address.

    DataType IS SIGNED, and that is from the bytes rather than a choice:
    1a17:04af sign-extends it with CBW. A Turbo Pascal enumerated type would
    zero-extend, so whatever 1.31 declared was not one. }
  PSampleBuffer = ^TSampleBuffer;
  TSampleBuffer = record
    InUse    : Boolean;    { +$00  set while the device is playing it        }
    NSamples : Word;       { +$01  length, in samples                       }
    RateHz   : Word;       { +$03                                           }
    Channels : Byte;       { +$05  1 or 4                                   }
    DataType : ShortInt;   { +$06  0 = Integer, 1 = ShortInt                }
    IData    : Pointer;    { +$07                                           }
  end;

  TAskBufferProc = function : PSampleBuffer;
  TProc          = procedure;
  TInitDevProc   = procedure(Hz : Word);

{ The driver record holds its slots as plain `Pointer`, so calling one needs a
  procedural cast. The release types the fields themselves -- `InitRut :
  TInitDevProc` -- and that would read better here too, but retyping them
  reaches into every unit that fills a slot, and two of those currently
  reproduce the original exactly. Not worth risking for a cast. A procedural
  type is always FAR in Turbo Pascal, which is what CALLF [DI+$1e] needs. }

{ ---- the device list, 1a17:018c and 1a17:02ba ------------------------- }

procedure SetDevice(D : PSoundDevice);
function  InitDevice(D : PSoundDevice) : Word;
function  LocateDevice(ID : String) : PSoundDevice;

{ ---- start and stop, 1a17:00a9 and 1a17:013e -------------------------- }

procedure StartSampling;
procedure EndSampling;

{ ---- the two installable callbacks, 1a17:005d and 1a17:0176 ----------- }

procedure SetPeriodicProc(Proc : TProc; PerSecond : Word);
procedure SetBufferAsker(Proc : TAskBufferProc);

{ ---- the rate, 1a17:02fb and 1a17:037f -------------------------------- }

function  GetRealFreq(Hz : Word) : Word;
procedure CalcTimerData(Hz : Word);

{ ---- the buffer queue, 1a17:03d2 -------------------------------------- }

function  DoGetBuffer : Word;

{ ---- unit initialisation, 1a17:053c ----------------------------------- }

procedure InitSoundDevices;

{ ---- 1a17:06ff -- where the player has got to in the output buffer -----
  Exported because the DEMO calls it, not the player: 1000:0288 is its only
  caller. }

function  GetPlayPos : Pointer;

{ ---- the shared poll, 1a17:1008 -------------------------------------- }

procedure SharedPoll;

{ ---- 1a17:1090 -- install the output loop, mono or stereo ---------------
  EXPORTED BECAUSE 193a CALLS IT: 193a:0352 is a direct far call here, which is
  what made the second entry point into the assembler module need a name. 1087
  is the same tail forced to mono and is the release's DevInitSbNonDMA; this
  is its DevInitSbDMA. The four bytes of arguments are what its shared
  RETF 4 removes. }
procedure DevInitSbDMA(Stereo : Boolean; Bits : Byte);

{ ---- state that other units reach into -------------------------------
  In the original these are absolute DGROUP addresses, quoted here so the
  reading can be checked against the disassembly. Nothing outside this unit
  uses the addresses; see "one DGROUP, many units" in docs/06-transcription. }

{ ==========================================================================
  THIS UNIT'S DGROUP CONST BLOCK, $0b94..$0c0b, IN ADDRESS ORDER.

  All of it was plain `var`s, so none of it existed in the linked image: a typed
  constant is initialised data the linker writes into the EXE and a `var` is reserved
  space it never touches. That is 120 of the 124 bytes `dgroup.py` reported
  missing between SoundBlaster's block and Hardware's.

  THE VALUES ARE READ OUT OF THE ORIGINAL'S IMAGE AND THE RELEASE SUPPLIED THE ORDER,
  and the two agree to a degree that leaves nothing to argue about. Three groups the
  transcription did not have AT ALL were named outright by `LIB/SOUNDDEV.PAS`'s own
  declaration sequence, and each one's values are in the image:

    * **The eight FILTER coefficients, $0bd2..$0be1**, as two identical groups of four:
      treble value 6, treble multiplier 3, bass value 13, bass multiplier 0, once for
      the left channel and once for the right. Eight declarations, eight values, exact.
    * **The three DAC ports, $0bf2..$0bf7**, all holding $378 -- which is LPT1. This
      file already lists "the three DAC ports" among the globals VTCfg writes and had
      no home for them.
    * **`DMAStop`, `DMAStopped` and `DMAIrqWatch` at $0bc0..$0bc2**, which is what the
      four-byte gap below DMAChannel was.

  AND A FIFTH OUTPUT SLOT. `OutSlot0..3` covered $0bf8..$0bff and the release has FIVE
  words there -- DeviceStartRut, DeviceRut1, DeviceRut2, DeviceKickRut, DeviceFillRut --
  which is exactly what the two bytes at $0c00 were.

  FOUR GLOBALS ARRIVE FROM OTHER UNITS, and the layout is what sent them here. Each was
  declared in a unit whose own block is nowhere near these addresses, and this file
  already carried the neighbours either side of every one of them:

      $0c6e  NxOption      was VTGLOBAL's     $0c72  TickSnapshot  was PLAYMOD/VTMAIN's
      $0c74  TicksPerSecond was PLAYMOD's and DEVGUS's -- declared TWICE
      $0bd0  WordAtBD0     was VTMAIN's

  `TicksPerSecond` is the interesting one: it holds **50**, which is the release's own
  comment "50 = Europe, 60 = USA", and it was declared in two units at once. This file
  has listed it as a duplicated global and a risk-1 example since `12ba` was
  transcribed; the layout is what finally says whose it is, and the answer is neither.

  ONE RENAME WAS FORCED: `GusStarted` IS `UsingGUS`. PlayMod called $0bce `GusStarted`
  and this unit called it `UsingGUS`; one address cannot have two names, and the
  release's is `UsingGUS`. PlayMod's fifteen references are renamed with it.

  TWO VALUES DIFFER FROM THE RELEASE and both are read from the image, per the standing
  rule: `DMAChannel` is **255** where 1.39b initialises it to 0 -- and 255 is what
  `12ba:13ae`'s six-byte word compare against $00FF tests, so it means "no channel" --
  and `DMABufferSize` is a typed constant here holding **46000**, where the release
  declares it as an untyped constant.

  THE PADS ARE TP WORD-ALIGNING EACH CONSTANT, the same rule as everywhere else in this
  layout: $0b95 after NumDevices, $0ba7 after DeviceIdling, $0c4e, $0bc3, $0bcf and
  $0be3. Every one of them lands the following constant on an address an instruction
  already named.
  ========================================================================== }
const
  NumDevices        : Byte         = 0;      { DS:$0c3c  pad at $0b95         }
  ActiveDevice      : PSoundDevice = nil;    { DS:$0c3e                       }
  Sounding          : Pointer      = nil;    { DS:$0c42  NON-DMA only         }
  SoundLeft         : Word         = 0;      { DS:$0c46                       }
  NumChannels       : Word         = 1;      { DS:$0c48                       }
  ChannelIncr       : Word         = 1;      { DS:$0c4a                       }
  DMABufferSize     : Word         = 46000;  { DS:$0c4c  b3 b0                }
  { A BYTE, NOT THE RELEASE'S BOOLEAN, AND THE CODE IS WHY: 1a17:00d0 assigns 1 to it
    rather than testing it as a flag, so the standing rule -- do not take a TYPE from
    the release -- keeps it a Byte. The value is the same either way; $0ba6 holds 01. }
  DeviceIdling      : Byte         = 1;      { DS:$0c4e  pad at $0ba7         }

  { $0ba8..$0baf. THREE OF THE FOUR HOLD 16000, WHICH FIXES `DefaultHz`. The release
    initialises TimerHz, SoundHz and DesiredHz to `DefaultHz` and does not say what
    that is here; 1.31's image says 16000 three times over -- and VTGlobal's `ShellHz`
    holds 12000, which is the release's `DefaultHz * 3 DIV 4` exactly. Two units
    agreeing on a constant neither of them stores by name. }
  TimerHz           : Word         = 16000;  { DS:$0c50  80 3e                }
  LastHz            : Word         = 0;      { DS:$0c52                       }
  SoundHz           : Word         = 16000;  { DS:$0c54                       }
  DesiredHz         : Word         = 16000;  { DS:$0c56                       }

  { DS:$0bb0 -- the release calls it `SystemClockCount`; ours says what it does,
    accumulating SystemClockIncr until it carries, which is when the displaced BIOS
    handler gets called. }
  ClockAccum        : Word         = 0;      { DS:$0c58                       }
  SystemClockIncr   : Word         = 0;      { DS:$0c5a                       }
  TimerVal          : Word         = 0;      { DS:$0c5c  what goes to the PIT }
  DeviceInitialized : Boolean      = False;  { DS:$0c5e  pad at $0bb7         }
  DMAOffset         : Word         = 1;      { DS:$0c60  samples held back    }
  HzChanged         : Boolean      = False;  { DS:$0c62                       }
  DoBassPower       : Boolean      = False;  { DS:$0c63  the filter stage     }
  MixMethod         : Byte         = 3;      { DS:$0c64  0..3                 }
  Stereo            : Boolean      = False;  { DS:$0c65                       }
  BytesPerSample    : Byte         = 1;      { DS:$0c66                       }
  DevBits           : Byte         = 8;      { DS:$0c67                       }
  DMAStop           : Boolean      = False;  { DS:$0c68                       }
  DMAStopped        : Boolean      = False;  { DS:$0c69                       }
  DMAIrqWatch       : Byte         = 0;      { DS:$0c6a  pad at $0bc3         }

  { DS:$0bc4 -- A WORD, and 255 rather than the release's 0. 12ba:13ae is
    `81 3E C4 0B FF 00`, a six-byte WORD compare against $00FF, where a Byte gives the
    five-byte form -- so both the width and the value are read rather than taken. }
  DMAChannel        : Word         = 255;    { DS:$0c6c                       }

  { DS:$0bc6 -- WAS DECLARED IN VTGLOBAL. 109c:06d3 sets it from the `nx` switch and a
    scan of every segment finds NO READER anywhere in the program. Its address is what
    puts it here: $0bc4 and $0bc7 are both this unit's.

    **NAMED FOR ITS WRITER BECAUSE IT HAS NOTHING ELSE.** Every other name in this
    reconstruction comes from what a value is USED for, and with no reader there is no
    use to name it after -- so this one is named after the switch that sets it, and
    the name is deliberately shaped to say so. `NxOption` claims exactly what can be
    demonstrated: the command line said `nx`. It does NOT claim to know what `nx` was
    going to do, and a behavioural name here -- `NoExtended`, `NoXms` -- would be an
    invention dressed as a measurement. A half-finished feature should read as one. }
  NxOption          : Boolean      = False;  { DS:$0c6e  set by `nx`, unread  }

  IsDmaDevice       : Boolean      = False;  { DS:$0c6f  picks @@Prepare's path }

  { $0bc8..$0bcd -- THE TICK GROUP, and all three used to be somewhere else. `Ticks`
    came from VTSILENC, which the LINK ORDER moved; `TickSnapshot` from PlayMod and
    VTMAIN, which both declared it; `TicksPerSecond` from PlayMod AND DevGus, which
    both declared it. The core owns the shared poll at 1a17:1008 and the periodic
    proc, so a tick counter, the mixer's copy of it and the rate all belong with them. }
  Ticks             : Word         = 0;      { DS:$0c70  VTSilenc advances it  }
  TickSnapshot      : Word         = 0;      { DS:$0c72  12ba:0c52 compares it }
  TicksPerSecond    : Word         = 50;     { DS:$0c74  50 = Europe           }

  UsingGUS          : Boolean      = False;  { DS:$0c76  pad; was GusStarted   }
  { DS:$0bd0 -- A SECOND TICK COUNTER, and 1.31's own: the release has nothing between
    TicksPerSecond and the filter coefficients. DevGus's timer handler advances it and
    1000:02a8 clears it, so it was declared in BOTH of those units -- DevGus called it
    `Ticks` and VTMAIN called it `WordAtBD0`. It is neither unit's: this block is
    contiguous from $0b94 to $0c0b and DevGus's own data is at $0058..$0099.

    TWO COUNTERS IS NOT A MISTAKE. `Ticks` at $0bc8 is the one VTSilenc advances and
    the one 12ba:0c52 gates the mixer on; this one is the polled driver's. The gate is
    guarded by `IsDmaDevice`, so on a GUS -- which is polled, not DMA -- the mixer never
    reads $0bc8 at all, and the two never have to agree. }
  DriverTicks       : Word         = 0;      { DS:$0c78  the polled driver's   }

  { $0bd2..$0be1 -- SIXTEEN BYTES THIS TREE HAS READ TWO DIFFERENT WAYS, AND THE
    LAYOUT DOES NOT DEPEND ON WHICH IS RIGHT. What is certain is that they are a typed
    constant holding 6, 3, 13, 0, 6, 3, 13, 0 -- that is in the image -- and that is
    all the DGROUP measurement needs.

    THE NAMES BELOW ARE THE RELEASE'S FILTER COEFFICIENTS, and three things favour them:
    `LIB/SOUNDDEV.PAS` declares exactly TrebleFilterVal, TrebleFilterMult,
    BassFilterVal, BassFilterMult per channel at exactly this position between
    DMAChannel and PeriodicHz, both of which are independently confirmed; its defaults
    are 6, 3, 13 and 0; and 1.31's sixteen bytes are those four values TWICE, which is
    what a stereo pair of filters looks like and is a strange thing for eight
    independent channel volumes to hold at startup.

    **BUT THE ASSEMBLER MODULE READS THE SAME SIXTEEN BYTES AS `Volumes`.**
    `objcheck.py` finds seven `OFFSET <symbol> + n` fixups in SOUNDDEV.OBJ that all
    imply a DGROUP symbol at $0bd2, and this unit has documented them since as "eight
    per-channel volumes, 0..15" that SetGains turns into eight patched CALL targets.
    Their spacing alternates 0x11, 0x19, which fits FOUR PAIRS -- and a pair is exactly
    a value and its multiplier. It also fits the note's own explanation, that alternate
    entries are scaled differently, so the access pattern does not separate the two
    readings. The VALUES do, and they are what the image gives.

    SO THE ROUTINE'S NAME IS THE THING LEFT OPEN, not the data. If these are filter
    coefficients then `SetGains` at 1a17:0a81 is setting up a filter rather than eight
    gains, and that wants reading against the disassembly -- flagged, not decided. The
    `Volumes` alias below keeps the assembler module's EXTRN resolving to the same
    address whichever way it goes, and `absolute` emits no bytes of its own. }
  TrebleFilterVal_Left   : Word = 6;         { DS:$0c7a                       }
  TrebleFilterMult_Left  : Word = 3;         { DS:$0c7c                       }
  BassFilterVal_Left     : Word = 13;        { DS:$0c7e                       }
  BassFilterMult_Left    : Word = 0;         { DS:$0c80                       }
  TrebleFilterVal_Right  : Word = 6;         { DS:$0c82                       }
  TrebleFilterMult_Right : Word = 3;         { DS:$0c84                       }
  BassFilterVal_Right    : Word = 13;        { DS:$0c86                       }
  BassFilterMult_Right   : Word = 0;         { DS:$0c88                       }

  PeriodicHz        : Byte         = 0;      { DS:$0c8a  pad at $0be3         }
  PeriodicStart     : Word         = 1;      { DS:$0c8c  NON-DMA countdown    }
  PeriodicCount     : Word         = 0;      { DS:$0c8e                       }
  DSPWritePort      : Word         = 0;      { DS:$0c90                       }
  DSP8AckPort       : Word         = 0;      { DS:$0c92                       }
  DSPLifePort       : Word         = 0;      { DS:$0c94                       }
  SbCmdTimeout      : Word         = 100;    { DS:$0c96                       }
  SbSplTimeout      : Word         = 10;     { DS:$0c98                       }

  { $0bf2..$0bf7 -- THREE DAC PORTS, all $378, which is LPT1. A Covox or similar
    hangs off the printer port; the left and right pair is for a stereo one. }
  DacPort           : Word         = $378;   { DS:$0c9a                       }
  LDacPort          : Word         = $378;   { DS:$0c9c                       }
  RDacPort          : Word         = $378;   { DS:$0c9e                       }

  { $0bf8..$0c01 -- FIVE slots, not four. The release calls them DeviceStartRut,
    DeviceRut1, DeviceRut2, DeviceKickRut and DeviceFillRut; ours are named for the
    1a17 offsets that patch them, and the fifth is what the gap at $0c00 was. }
  OutSlot0          : Word         = 0;      { DS:$0ca0  -> 1a17:0f64         }
  OutSlot1          : Word         = 0;      { DS:$0ca2  -> 1a17:104d         }
  OutSlot2          : Word         = 0;      { DS:$0ca4  -> 1a17:1063         }
  OutSlot3          : Word         = 0;      { DS:$0ca6  -> 1a17:107c         }
  { DS:$0ca8 -- this unit already had it as `MixRut`, "the output loop 1a17:1087/1090
    installs, mono or stereo", declared as a lone `var` well away from the other four.
    It is the fifth entry of the same table: the release's DeviceFillRut. A NEAR
    pointer, as the other four are, because the kernels are in this segment. }
  MixRut            : Word         = 0;      { DS:$0ca8  release: DeviceFillRut }

  DeviceList        : PSoundDevice = nil;    { DS:$0caa                       }
  OldTimerHandler   : Pointer      = nil;    { DS:$0cae                       }
  IntInstalled      : Boolean      = False;  { DS:$0cb2  pad at $0c0b         }

  { THE ASSEMBLER MODULE'S VIEW OF $0bd2..$0be1. `SOUNDDEV.ASM` has
    `EXTRN Volumes : WORD` and indexes it +0..+14, so the symbol has to exist under
    that name; `absolute` gives it the address without a second copy of the bytes.
    See the long note on those sixteen bytes above. }
{ THE ASSEMBLER MODULE'S VIEW OF $0bd2..$0be1. `SOUNDDEV.ASM` has
  `EXTRN Volumes : WORD` and indexes it +0..+14, so the symbol has to exist under that
  name; `absolute` gives it the address without a second copy of the bytes. See the long
  note on those sixteen bytes above. }
var
  Volumes           : array[0..7] of Word absolute TrebleFilterVal_Left;

{ ==========================================================================
  THIS UNIT'S DGROUP VARIABLE BLOCK, $3b32..$4323, IN ADDRESS ORDER.

  **`DevStack` IS 2,000 BYTES AND WAS MISSING ENTIRELY**, which is most of the 2,350
  bytes our whole DGROUP was short. It is the private stack the shared poll switches to,
  and `SavedSS`/`SavedSP` -- the release's `DevSS`/`DevSP` -- are the caller's stack saved
  across that switch, which is why the three belong together and why the stack comes
  first. `linkcmp.py` is what measured it: the original's `SavedSS` is at $4302 and
  ours came out at $39fa, and with everything before this unit accounted for the block
  had to start at $3b32. $4302 - $3b32 is exactly $7D0.

  ~~THE SIZE IS 1.31's, NOT THE RELEASE'S~~ -- **IT IS 1000, AND THE RELEASE WAS RIGHT.**
  The note said 2000 "read off the two addresses", and the two addresses only bound the
  DISTANCE from DevStack to SavedSS; they say nothing about how that distance is
  divided. 1bff:102b is what divides it: `MOV SP,6274`, and $6274 is DevStack + 998,
  which is the top of a **1000-byte** stack less the two bytes a stack pointer starts
  below its top. A 2000-byte stack's top-less-two is $665c.

  SO A SECOND 1000-BYTE VARIABLE FOLLOWS IT, unnamed, because the total to SavedSS is
  fixed and only half of it is the stack. Declared as filler below.

  **AND THE RULE THAT PRODUCED THE WRONG SIZE IS STILL RIGHT** -- a count is data and
  the release is worth nothing for data. What went wrong is that this was not a count
  read from the release and rejected; it was a count INFERRED from a span, with the
  release's own answer sitting there disagreeing. A disagreement with the release is a
  reason to find the instruction that settles it, not to close the question.

  The order below is the original's, and it was wrong in four places: the buffer-queue
  group was declared FIRST and belongs last, and DMABuffer/DMABufferPtr and
  DMABufferYet/DMABufferEnd were each the wrong way round.
  ========================================================================== }
const
  { **THE RELEASE'S OWN VALUE**, `LIB/SOUNDDEV.PAS`'s `DevStkSize = 1000`, restored
    after 1bff:102b confirmed it. }
  DevStkSize = 1000;

var

  { **THE POLL'S OWN STACK, 1000 BYTES, AND IT STARTS TWO BYTES EARLIER THAN THIS
    FILE USED TO SAY.** A two-byte `Fill5E8C` stood ahead of it and the assembler
    reached its top with `OFFSET DevStack + 998`, which is the same address
    written as an odd number.

    v1.31b SETTLES IT, AND ITS OWN COMMENT IS WHAT MISLED BOTH VERSIONS. There the
    block runs $3b32..$4301 and the assembler writes `MOV SP,3F1Ah` under the note
    "its top". $3F1A is NOT the top: $3b32 + $7D0 is $4302. It is exactly 1000
    bytes in, and **a stack grows downwards**, so a thousand bytes below $3F1A are
    the stack and a thousand above it are not.

    THAT MAKES THE RELEASE RIGHT ABOUT THE SIZE. `LIB/SOUNDDEV.PAS` has
    `DevStkSize = 1000` and 1.31b's note overruled it from a span that only
    bounded the distance between two ends. The span is 2000 because there are two
    blocks of a thousand, not because the stack is 2000.

    The arithmetic closes in v1.51 with nothing over. The map puts `SavedSS` at
    $665c; $665c - $5e8c is $7d0, the same 2000; and $5e8c + 1000 is $6274, which
    is what 1bff:102b sets SP to. The `+ 998` is gone and the assembler now writes
    the release's own form, `OFFSET DevStack + DevStkSize`. }
  DevStack          : array[1..DevStkSize] of Byte;

  { **THE SECOND STACK, AND DEVGUS IS WHAT NAMES IT.** 106e:0040 is
    `MOV SP,OFFSET SoundDevices.SavedSS` -- SP set to $665c, with SS already
    pointing at DGROUP two instructions earlier. A stack grows DOWNWARDS, so that
    switch runs on the thousand bytes below $665c: $6274..$665b, which is exactly
    this block.

    **IT WAS INVISIBLE BECAUSE THE CODE NEVER USES ITS OWN ADDRESS.** Every
    instrument here asks the same question -- what reads or writes these bytes --
    and the answer really is nothing. No instruction names $6274. The one
    instruction that uses the block names the address ABOVE it, `SavedSS`, and
    lets the hardware walk down. A search for a block's own address cannot find a
    block that is only ever addressed by its neighbour.

    TWO POLLS, TWO STACKS, TWO GUARDS, and v1.51 is where the second of each
    appears. SoundDevices switches to `DevStack` at 1bff:102b behind `Busy`;
    DevGus switches to this one at 106e:0040 behind `PollBusy`, which is new in
    this version. Both save the caller's SS:SP into the same `SavedSS`/`SavedSP`
    pair, which is safe only because the two guards stop them from nesting -- and
    that is why the poll needed a guard of its own once it acquired a body.

    THE SIZE IS THE SAME `DevStkSize`, and the arithmetic closes with nothing
    over: $5e8c + 1000 is $6274, $6274 + 1000 is $665c, and $665c is `SavedSS`. }
  PollStack         : array[1..DevStkSize] of Byte;

  { $4302/$4304 -- the caller's stack, saved across the poll, because the poll
    switches to the stack above. The release calls them `DevSS` and `DevSP`. }
  SavedSS           : Word;          { DS:$665C                            }
  SavedSP           : Word;          { DS:$665E                            }

  { ---- the DMA buffer -------------------------------------------------
    DMABufferSize is NOT here: it is a typed constant at $0ba4 holding 46000. The
    release has it as a plain untyped constant, and 1a17:00fd pushes
    `word ptr [0ba4]`, so in 1.31 it is a word in DGROUP and the disassembly wins. }
  DMABufferPtr      : Pointer;       { DS:$6660  where the mixer is up to  }
  DMABuffer         : Pointer;       { DS:$6664                            }
  DMABufferEnd      : Word;          { DS:$6668  Ofs(DMABuffer^) + the size }
  DMABufferYet      : Boolean;       { DS:$666A  and a pad at $4311        }

  { DS:$4312 -- the far routine the poll actually calls once it is on its
    own stack and has taken the guard. Installed by the core at startup. }
  PeriodicProc      : Pointer;       { DS:$666C                            }

  { ---- the buffer queue, 1a17:03d2 ------------------------------------ }
  AskBufferProc     : TAskBufferProc;{ DS:$6670  installed by 1a17:0176    }
  ActualBuffer      : PSampleBuffer; { DS:$6674  the block playing         }
  NextBuffer        : PSampleBuffer; { DS:$6678  the one behind it         }
  PleaseFallback    : Word;          { DS:$667C  no buffer was available   }

{ ~~A DOZEN COMMENTS USED TO SIT IN THIS SECTION~~ describing declarations that are now
  in the address-ordered const block above -- the periodic process, the INT 8 hook, the
  DSP ports, DMAChannel's width, UsingGUS, the output format, the four output slots and
  the tick counter. Their content went with them. Nothing was dropped except the
  adjacency, which had become false: a comment above the wrong declaration is worse than
  no comment, and moving forty-two declarations out of a section is how that happens. }

{ ---- WHAT CANNOT MATCH, AND WHERE ------------------------------------
  FOUR BYTES, in three places, and they all say the same thing.

    1007         1  the near epilogue RET, where the original has a 00 pad
    104d         1  SharedPoll's far epilogue RETF, which the original has not
                    got at all
    10c1..10c2   2  the epilogue again, where the original ends RETF 4

  All three are the boundary of a Pascal procedure inside what the original
  built as ONE frameless run from 0746 to 10c3, and the reason it has no such
  boundaries is now identified: **the run was an external TASM module, linked
  with the $L directive, not inline Pascal `asm`.** The 1.39b release does
  exactly that -- `LIB/SOUNDDEV.PAS` line 744 is an $L of SOUNDDEV and declares
  seven routines
  `EXTERNAL` out of `LIB/SOUNDDEV.ASM`, an IDEAL-mode TASM module whose entry
  points are bare `PUBLIC` labels with no prologue or epilogue.

  And the ENCODINGS settle it, because the two assemblers disagree and each
  matches a different part of this segment:

    instruction     original      TASM 4.1   TP6 inline asm
    AND AL,AL       22 C0 @1014   22 C0      20 C0
    XOR AL,AL       32 C0 @102e   32 C0      30 C0
    ADD AX,AX       03 C0 @0a84   03 C0      01 C0
    RETF 4          CA 04 00      CA 04 00   cannot express
    SUB BX,AX       29 C3 @0713   2B D8      29 C3

  The first four are all inside 0746..10c3 and all TASM's; the fifth is inside
  GetPlayPos, a compiled Pascal function with an inline `asm` block, and is
  TP's. That is why this file is full of `DB 22h, 0C0h`-style byte encodings
  through the run and nowhere else -- they are TASM output being spelled out
  because TP's inline assembler will not produce it.

  So the four bytes are not a Pascal limitation to be lived with; they are the
  residue of transcribing an assembler module as inline asm. Closing them means
  moving 0746..10c3 into a real `.ASM`, assembling it with TASM (`C:\TASM\BIN`
  in the image) and linking it with $L -- see docs/06-transcription.md.

  CLOSED, and each one had been recorded here as unfixable:

    024c..025e  19  the value-String copy. It was the compiler, and TP6 makes
                    the runtime call the original makes.
    070f..0716   8  GetPlayPos's register allocation -- not the compiler at all.
                    `SUB BX,AX` is `29 C3`, which TP's inline assembler emits
                    and its code generator does not, so those four instructions
                    are hand-written. Transcribed verbatim, they match.
    0746         3  the JMP that let Pascal enter SetGains at its first byte.
                    Nothing calls SetGains by name, so it never needed one --
                    and with the JMP gone the four `DW OFFSET SetGains + delta`
                    patch targets stopped pointing three bytes short.

  Nothing here is a missing routine. }

implementation

{ ==========================================================================
  1a17:0000 and 1a17:0001 -- the two null callbacks.

  What the hook slots hold before anything real is installed. The first is a
  bare RETF -- ONE byte, and `assembler` with an empty body is the only way to
  get Turbo Pascal to emit just that. The second returns a nil POINTER, not a
  zero LongInt as docs/04-units.md had it: `ENTER 4,0` with the result loaded
  into DX:AX fits either, but 1a17:03d2 tests what comes back for nil and
  indexes through it, so it is the buffer provider. The release settles it as
  `NullBufferProc : PSampleBuffer`.
  ========================================================================== }
procedure NullProcedure; far; assembler;
asm
end;                                          { 0000  a bare RETF, one byte }

function NullBufferProc : PSampleBuffer; far;
begin
  NullBufferProc := nil                       { 0001..0014                  }
end;

{ ==========================================================================
  1a17:0015 -- InitPeriodic. Near and private.

  Turns a rate in Hz into a countdown reload. The clamp is the point: a rate
  faster than the timer itself divides to zero, and a zero reload would make
  the countdown never fire rather than fire always.

  SystemClockIncr is assigned in BOTH arms, and the release shows why it looks
  redundant -- in 1.39b the multiply that belonged on the second one is itself
  commented out, leaving `SystemClockIncr := TimerVal` with a disabled
  `* PeriodicStart` after it. So this is the original's own dead
  simplification, not a misreading.
  ========================================================================== }
procedure InitPeriodic;
begin
  if PeriodicHz = 0 then                      { 0018                        }
  begin
    PeriodicStart   := 0;                     { 001f                        }
    PeriodicCount   := 0;                     { 0024                        }
    SystemClockIncr := TimerVal                { 0029                        }
  end
  else
  begin
    PeriodicStart := TimerHz div PeriodicHz;  { 0031..003f                  }
    if PeriodicStart = 0 then                 { 0042                        }
      PeriodicStart := 1;                     { 0049  never zero            }
    PeriodicCount   := 1;                     { 004f                        }
    SystemClockIncr := TimerVal                { 0055                        }
  end
end;

{ ==========================================================================
  1a17:005d -- SetPeriodicProc

  Installs the routine every poll path funnels into. The store is an asm block
  rather than a Pascal assignment because it has to be ATOMIC against the
  interrupt that is about to call through it -- PUSHF/CLI around a two-word
  write, restoring the caller's flag state rather than blindly re-enabling.
  The release has the same asm block for the same reason.

  PerSecond IS A WORD AND PeriodicHz IS A BYTE. 1a17:006e reads one byte off
  the frame, so the high half of the argument is discarded. That is the
  release's declaration too, and it is worth leaving as found rather than
  narrowing the parameter to match the variable.
  ========================================================================== }
procedure SetPeriodicProc(Proc : TProc; PerSecond : Word);
begin
  asm
    PUSHF                        { 0060                                    }
    CLI                          { 0061                                    }
    LES  BX, Proc                { 0062  [BP+8] -- the FIRST parameter     }
    MOV  WORD PTR PeriodicProc, BX      { 0065                             }
    MOV  WORD PTR PeriodicProc+2, ES    { 0069                             }
    POPF                         { 006d  the caller's flags, not STI       }
  end;
  PeriodicHz := PerSecond;                    { 006e..0073                  }
  InitPeriodic                                { 0074                        }
end;

{ ==========================================================================
  1a17:007b -- OriginalHwTimer. FRAMELESS: no parameters, a bare RET.

  HAND ASSEMBLER, verbatim. Puts PIT counter 0 back the way the BIOS left it:
  mode 3, square wave, reload 0 meaning a full 65536. That is 18.2 Hz, which
  is what every DOS program expects INT 8 to arrive at.

  The reload is written as two byte OUTs to the same port because the 8253
  latches low-then-high on consecutive writes; there is no word access.
  ========================================================================== }
procedure OriginalHwTimer; assembler;
asm
  MOV  AL, 36h           { 007b  counter 0, both bytes, mode 3             }
  OUT  43h, AL           { 007d                                            }
  XOR  AL, AL            { 007f                                            }
  OUT  40h, AL           { 0081  reload, low byte                          }
  OUT  40h, AL           { 0083  ... and high -- 0 means 65536             }
end;

{ ==========================================================================
  1a17:0086 -- RestoreTimer. Near and private.

  Gives IRQ 0 back. Guarded by its own flag so calling it twice is harmless,
  which matters because both EndSampling and StartSampling reach it.

  THE ORDER IS THE VECTOR FIRST, THEN THE PIT. Reprogramming the PIT while our
  handler is still hooked would leave it being entered at 18.2 Hz, which it can
  survive; doing it the other way round would leave the BIOS handler being
  entered at the mixer's rate, which it cannot.
  ========================================================================== }
procedure RestoreTimer;
begin
  if IntInstalled then                        { 0089                        }
  begin
    SetIntVec(8, OldTimerHandler);            { 0090..009a                  }
    OriginalHwTimer;                          { 009f                        }
    IntInstalled := False                     { 00a2                        }
  end
end;

{ ==========================================================================
  1a17:00a9 -- StartSampling. Far; one of the two entry points VTMain reaches.

  Resets every piece of output state, fills the buffer with silence, and only
  then opens the device.

  THE SILENCE IS $80, NOT 0. Eight-bit DAC samples are unsigned with $80 as
  the midpoint, so a buffer of zeros is not quiet -- it is a hard rail to one
  extreme, which is a click on every card the program supports.

  THE GUARD IS INVERTED FROM WHAT YOU WOULD EXPECT: `if NOT DeviceInitialized
  then RestoreTimer`. Restoring the timer when nothing is running looks like a
  no-op, and it is one -- IntInstalled will be false. It is there for the case
  where a previous device left the hook installed without being initialised.

  BytesPerSample IS COMPUTED LAST, after the driver has run, because the
  driver is what sets Stereo and DevBits. The expression is the release's
  exactly, and note that Boolean-to-integer goes through a byte load and an
  INC rather than any conditional.
  ========================================================================== }
procedure StartSampling;
begin
  if not DeviceInitialized then RestoreTimer; { 00ac..00b3                  }

  ActualBuffer   := nil;                      { 00b6                        }
  NextBuffer     := nil;                      { 00be                        }
  SoundLeft      := 0;                        { 00c6                        }
  PleaseFallback := 0;                        { 00cb                        }
  DeviceIdling   := 1;                        { 00d0                        }
  DMABufferPtr   := DMABuffer;                { 00d5..00df                  }
  DMABufferYet   := True;                     { 00e3                        }
  Stereo         := False;                    { 00e8                        }
  DevBits        := 8;                        { 00ed                        }
  BytesPerSample := 1;                        { 00f2                        }

  FillChar(DMABuffer^, DMABufferSize, $80);   { 00f7..0103  see above       }

  if ActiveDevice <> nil then                 { 0108  AX OR DX              }
  begin
    asm CLI end;                              { 0111                        }
    DeviceInitialized := True;                { 0112                        }
    { 0117 pushes DesiredHz, then 011b..011f is LES DI / CALLF [DI+$1e] }
    TInitDevProc(ActiveDevice^.InitRut)(DesiredHz);
    asm STI end                               { 0123                        }
  end;

  BytesPerSample := (DevBits + 7) div 8 *     { 0124..0139                  }
                    (Byte(Stereo) + 1)
end;

{ ==========================================================================
  1a17:013e -- EndSampling. Far.

  THE BUFFER IS SILENCED BEFORE THE DEVICE IS CLOSED, and before interrupts
  are even disabled. Whatever the card is still playing out of that memory
  goes quiet first; closing the device first and clearing afterwards would
  leave the tail of the last block audible. 1a17:0151 is ahead of the CLI at
  0162, and the release has the CLI first -- the disassembly wins.
  ========================================================================== }
procedure EndSampling;
begin
  if (ActiveDevice <> nil) and DeviceInitialized then  { 0141, 014a         }
  begin
    FillChar(DMABuffer^, DMABufferSize, $80); { 0151..015d                  }
    asm CLI end;                              { 0162                        }
    TProc(ActiveDevice^.EndRut);              { 0163..0167  CALLF [DI+$32]  }
    RestoreTimer;                             { 016b                        }
    asm STI end;                              { 016e                        }
    DeviceInitialized := False                { 016f                        }
  end
end;

{ ==========================================================================
  1a17:0176 -- SetBufferAsker

  A plain far-pointer store, but between CLI and STI: the queue drains from an
  interrupt, and a half-written pointer here would be called.

  Note this one is CLI/STI, not PUSHF/CLI/POPF as SetPeriodicProc uses. Both
  are the release's, and the difference is real rather than sloppy -- this is
  reached only from initialisation, where interrupts are known to be on.
  ========================================================================== }
procedure SetBufferAsker(Proc : TAskBufferProc);
begin
  asm CLI end;                                { 0179                        }
  AskBufferProc := Proc;                      { 017a..0183                  }
  asm STI end                                 { 0187                        }
end;

{ ==========================================================================
  1a17:018c -- SetDevice

  Switching drivers while the player is running has to stop the old one
  first, because the driver owns the timer hook. When nothing is running,
  or when the driver is already the current one, it is a bare store.

  The `PUSH CS / CALL near` at 01b0 and 01c1 is the same-segment far call
  idiom: Stop and Start both end in RETF, so the return segment has to be
  pushed by hand. Transcribed as ordinary Pascal calls, which is what the
  original source must have had.
  ========================================================================== }

procedure SetDevice(D : PSoundDevice);
begin
  if D <> nil then                                       { 018f  ptr <> nil }
  begin
    if DeviceInitialized then                                      { 0197             }
    begin
      if D <> ActiveDevice then                         { 01a4, 01aa       }
      begin
        EndSampling;                                     { 01b0             }
        ActiveDevice := D;                              { 01b4             }
        StartSampling;                                   { 01c1             }
        Exit                                             { 01c5             }
      end
    end;
    ActiveDevice := D                                   { 01c7             }
  end
end;

{ ==========================================================================
  1a17:0248 -- LocateDevice, with NotInStr nested inside it at 1a17:01d8.

  Finds a device by the identification string at the head of its record. This
  is what VTMain uses to turn a name out of VT.CFG into a driver.

  NOTINSTR IS NESTED, and the byte stream is what says so: 1a17:0285 pushes BP
  as a fourth argument on top of the two VAR strings, which is Turbo Pascal
  handing a nested routine the static link to its parent's frame. That is also
  why NotInStr is emitted BEFORE its parent rather than after, and why it ends
  `RET $0A` -- eight bytes of pointers plus the two-byte link.

  ITS SENSE IS INVERTED, and deliberately so. It returns TRUE when the strings
  do NOT match, which is what lets the search read as one `while` with no
  negation: `while (p <> nil) and NotInStr(...) do p := p^.Next`. Reading it
  the obvious way round makes the loop condition wrong.

  IT IS A PREFIX TEST, NOT AN EQUALITY TEST. Only Length(ss) characters are
  compared, so 'GUS' matches a record whose ID is 'GUS16' -- the shorter of the
  two decides. The length guard rejects only the case where the pattern is
  LONGER than the candidate.

  ENTER $108 IS NOT A MISREADING. LocateDevice takes its string BY VALUE, so
  Turbo Pascal copies all 256 bytes of it onto the frame at 1a17:024c before
  anything else happens; `p` and the result account for the other eight.

  THAT COPY IS THE ONE THING HERE THAT WILL NOT MATCH, and it is a known
  parked divergence rather than anything about this routine. The original CALLS
  a runtime helper at 1ba1:0add to make the copy; TP7 inlines it as
  LDS SI / LODSB. Two regions, at 024c and 0255, and everything from 025f
  onwards -- the whole body, all of NotInStr -- is byte-exact. This is the
  fifth instance of the same pattern; see `1b54`'s `S := Name` in
  docs/06-transcription.md and risk 2 in docs/CONTINUATION.md.
  ========================================================================== }
function LocateDevice(ID : String) : PSoundDevice;

  function NotInStr(var s, ss : String) : Boolean;
  var
    i : Word;                     { [BP-4]; [BP-6] is the FOR limit temporary }
  begin
    NotInStr := True;                         { 01dc                        }
    if Length(ss) > Length(s) then Exit;      { 01e0..01ee                  }
    for i := 1 to Length(ss) do               { 01f0..0208                  }
      if UpCase(s[i]) <> UpCase(ss[i]) then Exit;  { 020b..0233             }
    NotInStr := False                         { 023d                        }
  end;

var
  p : PSoundDevice;
begin
  p := DeviceList;                            { 025f..026a                  }
  while (p <> nil) and NotInStr(p^.DevID, ID) do   { 026e..028a             }
    p := p^.Next;                             { 028c..02a0  Next at +$36    }
  LocateDevice := p                           { 02a2..02ad                  }
end;

{ ==========================================================================
  1a17:02ba -- InitDevice

  Links the driver onto the front of the list and, if nothing has been
  selected yet, selects it. That last part is why load order decides the
  default: the LAST driver to register with an empty selection wins, and
  'Silence' registers first precisely so that a real driver can displace it.

  THE RESULT IS NEVER ASSIGNED. The original allocates two bytes of local
  (ENTER 2,0) and loads them into AX at 02f4 as a function result, but no
  path writes them. It is a function that returns whatever was on the stack.
  Every caller ignores it. Transcribed as it stands rather than tidied into
  a procedure, because the frame and the RETF 4 are evidence of what the
  original source declared.
  ========================================================================== }

function InitDevice(D : PSoundDevice) : Word;
begin
  D^.Next := DeviceList;                                 { 02be..02cc       }
  DeviceList := D;                                       { 02d0..02dd       }
  if ActiveDevice = nil then                            { 02dd  AX OR DX   }
    SetDevice(D);                                     { 02e6             }
  Inc(NumDevices)                                       { 02f0             }
  { 02f4: MOV AX,[BP-2] -- the undefined result, see above }
end;

{ ==========================================================================
  1a17:02fb -- GetRealFreq

  Answers "if you ask the PIT for this rate, what will you actually get?"

  THE POINT IS THE ROUNDING. The PIT takes an integer divisor, so only rates of
  the form 1193180/i are available. Dividing to get i and dividing back gives
  the rate for i; this ALSO computes the rate for i+1 and keeps whichever is
  nearer what was asked. Truncating the divisor always errs the same way, and
  over a whole module that is an audible pitch offset.

  Every division is a 32-bit one through the runtime helper at 1ba1:0a2e, even
  though every operand and result fits a word -- 1193180 does not, so the whole
  expression is promoted.

  Note both distances are computed with `Abs(Integer(...))` on a WORD
  subtraction: the difference is taken modulo 65536 first and only then read as
  signed. For rates anywhere near the audible range that is the same answer,
  and it is what the release does.
  ========================================================================== }
function GetRealFreq(Hz : Word) : Word;
var
  i    : Word;                                { [BP-4]                      }
  NHz1 : Word;                                { [BP-6]                      }
  NHz2 : Word;                                { [BP-8]                      }
begin
  if Hz = 0 then Hz := 1;                     { 02ff..0305  never divide by 0}
  i := 1193180 div Hz;                        { 030a..031e                  }

  NHz1 := 1193180 div  i;                     { 0321..0335                  }
  NHz2 := 1193180 div (i + 1);                { 0338..034d                  }
  if Abs(Integer(NHz1 - Hz)) > Abs(Integer(NHz2 - Hz)) then  { 0350..036a   }
    NHz1 := NHz2;                             { 036c                        }

  GetRealFreq := NHz1                         { 0372..0378                  }
end;

{ ==========================================================================
  1a17:037f -- CalcTimerData

  Turns a wanted rate into the PIT reload value and records what that rate
  really is. TimerHz is derived BACK from the divisor rather than assumed to be
  the request, and everything downstream that needs "ticks per second" reads
  TimerHz -- the same care 193a:007f takes over the Sound Blaster's time
  constant.

  A rate of zero gives $FFFF, the slowest the counter can go, rather than
  dividing by zero.

  `SystemClockIncr := TimerVal` is NOT here, and 1.39b shows why: it is
  commented out there too. 1a17:03ce is the LEAVE, so there is nothing between
  the SoundHz store and the exit.
  ========================================================================== }
procedure CalcTimerData(Hz : Word);
begin
  Hz := GetRealFreq(Hz);                      { 0382..0389  PUSH CS / CALL  }

  if Hz = 0 then TimerVal := $FFFF            { 038c..0392                  }
            else TimerVal := 1193180 div Hz;  { 039a..03ae                  }

  TimerHz := 1193180 div TimerVal;            { 03b1..03c5                  }
  SoundHz := TimerHz                          { 03c8..03cb                  }
end;

{ ==========================================================================
  1a17:03d2 -- DoGetBuffer. THE BUFFER QUEUE, and the heart of the double
  buffering that keeps a card fed.

  Two blocks are tracked: ActualBuffer is playing, NextBuffer is the one
  behind it. Each call retires the current block, promotes the next, and asks
  the provider for a replacement. When the provider has nothing, the queue has
  run dry and the else-branch handles the underrun.

  THE SEMAPHORE IS A LOCAL TYPED CONSTANT, not a variable -- which in Turbo
  Pascal means it lives in DGROUP at DS:$0c0c and persists between calls, which
  is the whole point. It is a re-entrancy guard: this is reached from an
  interrupt and must not run inside itself.

  `Size` is the same kind of thing, at DS:$0c0e, and it is the odd one. It is
  set from the RETIRING block's length and read only in the underrun path, to
  decide whether to raise PleaseFallback -- so "was the last block a real one"
  is remembered across calls through its initial value of 1.

  ONE LINE THE RELEASE HAS AND 1.31 DOES NOT. 1.39b clears the retiring
  block's InUse here (`ActualBuffer^.InUse := FALSE`, with the comment "It must
  be already finished using"). 1a17:03f0 jumps straight from the Size store to
  the promotion, so in 1.31 the flag is left set and the block is never
  released. The disassembly wins; whether that is a leak or whether something
  else clears it is not settled from this segment alone.

  THE UNDERRUN PATH DROPS THE RATE TO PeriodicHz on a non-DMA device, which
  makes the timer tick slowly until buffers come back rather than spinning at
  the sample rate with nothing to play.
  ========================================================================== }
function DoGetBuffer : Word;
const
  Semaphore : Byte = 0;                       { DS:$0cb4 -- see above       }
  Size      : Word = 1;                       { DS:$0cb6                    }
begin
  DoGetBuffer := 0;                           { 03d6                        }
  if Semaphore > 0 then Exit;                 { 03db..03e2                  }
  Inc(Semaphore);                             { 03e5                        }

  if ActualBuffer <> nil then                 { 03e9..03f0                  }
    Size := ActualBuffer^.NSamples;           { 03f2..03fa                  }

  ActualBuffer := NextBuffer;                 { 03fd..0407                  }

  if ActualBuffer = nil then                  { 040b..0412                  }
  begin
    ActualBuffer := AskBufferProc;            { 0414..041b                  }
    if ActualBuffer <> nil then               { 041f..0426                  }
      ActualBuffer^.InUse := True             { 0428..042c                  }
  end;

  if ActualBuffer = nil then                  { 0430..0437  the queue is dry}
  begin
    if (Size <> 1) and (not ActiveDevice^.DMA) then  { 0439..0449           }
      Inc(PleaseFallback);                    { 044b                        }
    SoundLeft := 0;                           { 044f                        }
    if not ActiveDevice^.DMA then             { 0454..045d                  }
    begin
      PeriodicCount := 1;                     { 045f                        }
      LastHz        := PeriodicHz;            { 0465..046a                  }
      TInitDevProc(ActiveDevice^.ChgHzProc)(LastHz)   { 046d..0475  +$22    }
    end
  end
  else
  begin
    Sounding    := ActualBuffer^.IData;       { 047c..048b                  }
    SoundLeft   := ActualBuffer^.NSamples;    { 048f..0497                  }
    NumChannels := ActualBuffer^.Channels;    { 049a..04a4                  }
    ChannelIncr := ActualBuffer^.Channels *   { 04a7..04bf                  }
                   (Ord(ActualBuffer^.DataType) + 1);

    if LastHz <> ActualBuffer^.RateHz then    { 04c2..04cd                  }
    begin
      LastHz := ActualBuffer^.RateHz;         { 04cf..04d7                  }
      TInitDevProc(ActiveDevice^.ChgHzProc)(LastHz);  { 04da..04e2          }
      HzChanged := True                       { 04e6                        }
    end;

    { The DMA path plays a few samples behind where the mixer has written, so
      the last DMAOffset samples of the block are held back -- and never fewer
      than five, which is what the else-branch is for. }
    if ActiveDevice^.DMA then                 { 04eb..04f4                  }
    begin
      if SoundLeft > DMAOffset + 5 then       { 04f6..0500                  }
        Dec(SoundLeft, DMAOffset)             { 0502..0505                  }
      else
        SoundLeft := 5                        { 050b                        }
    end;

    NextBuffer := AskBufferProc;              { 0511..0518                  }
    if NextBuffer <> nil then                 { 051c..0523                  }
      NextBuffer^.InUse := True               { 0525..0529                  }
  end;

  DoGetBuffer := SoundLeft;                   { 052d..0530                  }
  Dec(Semaphore)                              { 0533                        }
end;

{ ==========================================================================
  1a17:053c -- InitSoundDevices. THE UNIT'S OWN INITIALISATION, and the most
  invasive thing in the segment.

  It installs the two null callbacks and then CARVES THE DMA BUFFER OUT OF
  TURBO PASCAL'S HEAP BY HAND, reaching into System's own HeapPtr and FreeList
  rather than calling GetMem. The release's comment on it is "This messes with
  the heap, but works", which is fair.

  WHY IT HAS TO. An 8237 DMA transfer cannot cross a 64K physical boundary --
  the controller increments only the low 16 bits of the address, so a buffer
  straddling the boundary wraps to the start of its own page mid-transfer and
  plays the wrong memory. GetMem gives no such guarantee, so this computes the
  buffer's LINEAR address, and if the buffer would cross a boundary it moves
  the base up to the next one and remembers the gap in OffsFree.

  THE GAP IS GIVEN BACK. `FreeMem(PtrFree, OffsFree)` at 1a17:06da returns the
  skipped bytes to the heap rather than leaking them -- which is only safe
  because PtrFree was the heap top before any of this happened.

  THE FREELIST SPLICE is the other half. HeapPtr is moved past the buffer by
  hand, and whatever pointed AT the old HeapPtr has to be made to point at the
  new one: either FreeList itself, or the block in the chain whose Next reaches
  it, found by the walk at 1a17:0681..06b2. Getting this wrong corrupts the
  heap rather than failing visibly.

  Both 32-bit shifts go through the runtime helpers at 1ba1:0a9c and 1ba1:0aac
  -- `SHL 4` and `SHR 4` on a LongInt are not inline even with $G+.
  ========================================================================== }
procedure InitSoundDevices;
type
  { Turbo Pascal's own free-list node, as System lays it out: the next free
    block and this one's size, both as pointers. Declared locally because it is
    the release's shape and nothing else here needs it. }
  PFreeBlock = ^TFreeBlock;
  TFreeBlock = record
    Next : PFreeBlock;
    Size : Pointer;
  end;
var
  l        : LongInt;                         { [BP-04]                     }
  PtrFree  : Pointer;                         { [BP-08]                     }
  OldHPtr  : Pointer;                         { [BP-0c]                     }
  p        : PFreeBlock;                      { [BP-10]                     }
  OffsFree : Word;                            { [BP-12]                     }
begin
  { `@`, because PeriodicProc is a plain Pointer here rather than the release's
    procedural type -- SharedPoll calls it with CALL DWORD PTR, so typing it
    would buy nothing. AskBufferProc IS typed, so that one needs no `@`. }
  PeriodicProc  := @NullProcedure;            { 0540..0549  -> 1a17:0000    }
  AskBufferProc := NullBufferProc;            { 054d..0556  -> 1a17:0001    }

  { The buffer starts at the heap top, wherever that is. }
  DMABuffer := HeapPtr;                       { 055a..0564                  }

  l := (LongInt(Seg(DMABuffer^)) shl 4) + Ofs(DMABuffer^);   { 0568..058d   }

  PtrFree  := HeapPtr;                        { 0590..059a                  }
  OffsFree := 0;                              { 059d                        }

  { Would the buffer cross a 64K physical boundary? If so, step the base up to
    the next one and remember how much was skipped. }
  if LongInt(Word(l)) + DMABufferSize > 65536 then      { 05a2..05be        }
  begin
    OffsFree := 65536 - LongInt(Word(l));     { 05c0..05d2                  }
    l := (l and $F0000) + $10000              { 05d5..05eb                  }
  end;

  DMABuffer    := Ptr((l shr 4) and $F000, Word(l));   { 05ee..060d         }
  DMABufferPtr := DMABuffer;                  { 0611..061b                  }
  DMABufferEnd := Ofs(DMABuffer^) + DMABufferSize;     { 061f..0629         }

  { Allocate it by moving the heap top past it, by hand. }
  OldHPtr := HeapPtr;                         { 062c..0636                  }
  HeapPtr := Ptr((l + DMABufferSize + 16) shr 4, 0);   { 0639..065b         }
  if OldHPtr = FreeList then                  { 065f..066f                  }
    FreeList := HeapPtr                       { 0671..067b                  }
  else
  begin
    p := FreeList;                            { 0681..068b                  }
    while p^.Next <> OldHPtr do               { 068e..06a0                  }
      p := p^.Next;                           { 06a2..06b2                  }
    p^.Next := HeapPtr                        { 06b4..06c1                  }
  end;

  FillChar(HeapPtr^, 8, 0);                   { 06c5..06cf                  }

  if OffsFree > 0 then                        { 06d4..06d8                  }
    FreeMem(PtrFree, OffsFree)                { 06da..06e3                  }
end;

{ ==========================================================================
  1a17:06ea -- GetDMACount. Near and private.

  A one-line wrapper: hands the channel to 1b24's GetDMACount and passes the
  answer back. The release writes it as
  `GetDMACount := Hardware.GetDMACount(DMAChannel)`, with the unit
  qualification there for the same reason it is needed here -- the inner and
  outer routines share a name.

  DMAChannel IS A BYTE HERE. 1a17:06ee reads one byte and widens it; the
  release has `DMAChannel : WORD`. Either reading compiles to the same
  argument push, but the load says byte.
  ========================================================================== }
function GetDMACount : Word;
begin
  GetDMACount := Hardware.GetDMACount(DMAChannel)   { 06ee..06f7                }
end;

{ ==========================================================================
  1a17:06ff -- GetPlayPos. Far; the only entry point in this segment that
  the DEMO reaches rather than the player. 1000:0288 calls it as
  `MarkPos := GetPlayPos`, masks the offset down to a multiple of four, and
  uses it to remember where the player had got to.

  WHAT IT COMPUTES. How far the card has drained the DMA buffer, turned back
  into an address inside it:

      Left := DMABufferSize - GetDMACount
      Result := Ptr(Seg(DMABuffer^),
                    Ofs(DMABuffer^) +
                    (DMABufferSize + Left - 100) mod DMABufferSize)

  The `+ DMABufferSize` before the `mod` is there so the `- 100` cannot go
  negative on an unsigned word; the modulo then folds it back into the buffer.
  A hundred samples of margin behind the play position, so the caller's mark is
  safely inside what has already been played.

  THE FIRST FOUR INSTRUCTIONS ARE DEAD, AND THAT IS THE FINDING. 1a17:0703
  computes `something * BytesPerSample` and pushes it, but nothing has loaded
  AX -- and the call site settles it: 1000:0288 is a bare `CALLF 1a17:06ff`
  with no argument pushed and no register set up, so the multiply runs on
  whatever the demo happened to leave in AX. The PUSH is never popped either;
  the LEAVE at 0744 discards it, so it is not a stack leak.

  So this is dead code in the original -- the remains of an edit, where a
  statement that used to consume `x * BytesPerSample` was removed and its
  operand setup was not. It is transcribed as an `asm` block because there is
  no Pascal that produces it: any expression the compiler would accept would
  also load AX first. Verbatim, per the standing rule, rather than dropped --
  dropping it would shift every byte after it.
  ========================================================================== }
{ No `far` here: the interface declaration already makes it one, and repeating
  the directive is an error. It IS far -- 1000:0288 calls it across segments. }
function GetPlayPos : Pointer;
var
  { [BP-6]. The Pointer result takes [BP-4]..[BP-1], at the top of the frame,
    which is what makes ENTER 6,0 six and not four. }
  Left : Word;
begin
  { 0703..0717 -- HAND-WRITTEN, and 0703..070b of it is DEAD. See above.

    Equivalent Pascal for the live half, REFERENCE ONLY -- the compiler does
    not produce these bytes from it, which is how the asm was identified:

        Left := DMABufferSize - GetDMACount;

    `SUB BX,AX` is `29 c3` here, the `SUB r/m,reg` direction that Turbo
    Pascal's inline assembler emits and its CODE GENERATOR does not -- the
    generator makes AX the accumulator and produces
    `MOV DX,AX / MOV AX,mem / SUB AX,DX`, one byte longer. That difference was
    parked for several sessions as the last compiler divergence in the tree.
    It was not the compiler; it was this block. }
  asm
    MOV  DL, BytesPerSample   { 0703                                        }
    XOR  DH, DH               { 0707                                        }
    MUL  DX                   { 0709  AX is undefined on entry              }
    PUSH AX                   { 070b  and never popped; LEAVE discards it   }

    CALL GetDMACount          { 070c  near, back to 06ea                    }
    MOV  BX, DMABufferSize    { 070f                                        }
    SUB  BX, AX               { 0713  29 c3 -- assembler direction           }
    MOV  Left, BX             { 0715                                        }
  end;

  GetPlayPos := Ptr(Seg(DMABuffer^),              { 0732..073b              }
                    Ofs(DMABuffer^) +             { 072a..0730              }
                    (DMABufferSize + Left - 100)  { 0718..071e              }
                    mod DMABufferSize)            { 0721..0728              }
end;

{ ---- 1a17:0746..1a17:10c3 -- THE ASSEMBLER MODULE ----------------------
  `src/SOUNDDEV.ASM`, assembled by TASM and linked with $L. It holds the
  gain ladder and its patcher, the mixing chain, SharedPoll and the output
  selectors: one frameless run with three entry points and two different
  returns, which is a shape no Pascal procedure has.

  IT USED TO BE THREE `assembler` PROCEDURES HERE, and that cost four bytes --
  an epilogue at 1007 where the original has a 00 pad, another at 104d, and a
  near RET at 10c1 where the original ends RETF 4. The encodings inside the run
  are TASM's throughout (see the table at the head of this file), the 1.39b
  release builds this same unit with $L over `LIB/SOUNDDEV.ASM`, and TP6 places
  object-module code AFTER all of a unit's Pascal code -- which is exactly where
  0746 has to be, immediately after GetPlayPos.

  THE PASCAL SIDE OF THE LINK. Everything the module reaches is declared above:
  the DGROUP variables it names in its EXTRN list, and the two near routines
  DoGetBuffer and GetDMACount that the chain calls. Nothing here calls SetGains
  or SelectOutput by name -- they are declared so that the module has something
  to be PUBLIC for, and so that the unit reads as what it links.

  The generated half is still generated: `python emit_gain.py >
  src/VTGAIN.INC`, now emitting TASM syntax, INCLUDEd by SOUNDDEV.ASM.
  The generator still asserts the closed form of all 48 gains and checks the
  patcher's length, so it fails rather than emitting something plausible. }
{$L SOUNDDEV.OBJ}
procedure SetGains; external;
procedure SharedPoll; external;
procedure SelectOutput; external;
procedure DevInitSbDMA(Stereo : Boolean; Bits : Byte); external;

end.
