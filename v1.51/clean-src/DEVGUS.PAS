{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  Segment 1084 -- the Gravis UltraSound DRIVER. 384 bytes, ten routines.

  Not the hardware layer -- that is 1723, and every port write happens there.
  This is the thin record of eight entry points that 1a17 walks, plus the
  timer callback that drives them.

  THIS UNIT DOES NOT COMPILE YET. It calls into 1723 (the GUS hardware) and
  1a17 (the player core), neither of which is transcribed, so the calls are
  written `Unit_<seg>_<ofs>` and the build reports it as blocked rather than
  failing. See docs/06-transcription.md.

  WHY THE GUS DRIVER IS ALMOST EMPTY. Three of its eight slots do nothing and
  a fourth returns its argument unchanged. A GUS holds the samples in its own
  DRAM and mixes them itself, so there is no buffer for the host to refill --
  the poll only has to count. Compare the Sound Blaster driver in 193a, where
  the same slot has to move data.

  NAMES ARE THE 1.39b RELEASE'S. LIB/DEVGUS.PAS is the counterpart and it
  supplies the unit name, the ID constant, the record and seven of the eight
  routines. `Poll` keeps an invented name: the release assigns
  SoundDevices.NullTimerHandler to the TimerHandler slot where 1.31 assigns
  this unit's own tick counter, which is the version drift already recorded in
  docs/06-transcription.md, so there is nothing to pair it with.

  ADDRESS MAP
    NullTimerHandler  1084:0000   Poll             1084:004c
    DevName           1084:0055   DevDetect        1084:0061
    DevInit           1084:0072   DevEnd           1084:00d5
    DevGetRealFreq    1084:00e4   DevChgHz         1084:00f5
    DevPoll           1084:00fc   the init section 1084:0101

  DGROUP
    $0060  THE DRIVER RECORD ('GUS')     $0076..$0095  its eight slots
    $005e  the re-entrancy guard         $0058  the last tick seen
    $0bce  "started"                     $0bd0  the tick counter
    $0bcc  the sample rate               $4302  saved SS
    $4304  saved SP                      $4312  the callback the core installs

  NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.
  =========================================================================== }

unit DevGUS;

interface

uses
  VTDriver, GUS, SoundDevices, PlayMod;

const
  { The release keeps the ID as a named constant and initialises the record
    from it. 1caa:0060 holds `03 'G' 'U' 'S'`. }
  GUSDevID = 'GUS';

type
  { Turbo Pascal 7 has no PByte -- that is a Delphi type. Declared here
    because DevName takes one. }
  PByteVal = ^Byte;

{ THIS UNIT'S WHOLE DGROUP CONST BLOCK, $0058..$0099, IN ADDRESS ORDER.

  `DevData` is at $0060 and the eight bytes below it are this unit's too -- VTSILENC's
  block ends at $0057 and the original's image has $0058..$005f as zeros. They were
  declared in the implementation section, which put them AFTER the record; a unit's
  interface declarations all come first, so the addresses require them here. }
const
  LastTick : Word    = 0;   { DS:$0014  1000:02a1 clears it, so it is exported }

  { DS:$0016 -- FOUR BYTES THIS TRANSCRIPTION CANNOT NAME, AND 1.31b COULD NOT
    EITHER. The addresses either side are measured and the block is contiguous, so
    the bytes exist; nothing in the tree reads or writes them. Declared as filler
    rather than invented as a variable, which keeps the SIZE honest and says
    plainly that the name is missing.

    1.31b CARRIES THE SAME FOUR BYTES as `Fill005A`, between `LastTick` and
    `Busy` -- the same two neighbours, the same width, the same silence.

    **AND THE RELEASE HAS NOTHING TO SAY HERE**, which is worth recording so the
    search is not run twice. The technique that named PlayMod's four unknowns --
    match a routine's typed-constant block against 1.39b's, in declaration order --
    has nothing to match against: 1.39b's LIB/DEVGUS.PAS declares exactly one typed
    constant in the whole unit, the `DevData : TSoundDevice` driver record. Its GUS
    driver keeps no state of its own. These bytes and the five below are v1.51's, and
    only a reader in this image can name them. }
  Fill0016 : LongInt = 0;

  Busy     : Byte    = 0;   { DS:$001a in v1.51  the handler's guard          }

  { FIVE BYTES BETWEEN THE TWO GUARDS. Busy is at DS:$001a and PollBusy at
    DS:$0020, and nothing in the segment touches what lies between. Declared as
    filler for the same reason Fill0016 above is: it keeps the SIZE honest and
    says plainly that the name is missing. }
  { **THE FIRST OF THE FIVE IS AN ALIGNMENT PAD, AND 1.31b SAYS SO.** Its own
    DevGus declares `Busy : Byte = 0` and comments it "the re-entrancy guard;
    pad at $005f" -- one byte of guard, then one byte of padding, then an even
    address. The same pair is here: `Busy` at $001A and a pad at $001B.

    THE ORDER WAS ALREADY MEASURED, which is what made the reading available.
    `PollBusy` is at $0020 -- 106e:0029, 0032 and 0055 all name it -- so the five
    bytes between the two guards start at $001B, and a byte has to come first:
    declared LongInt-first the compiler aligns it to $001C and everything after
    lands one byte high, which is exactly the three operands that were wrong. The
    release supplies the REASON for the shape the addresses had already forced. }
  Pad001B  : Byte    = 0;   { DS:$001b  alignment, as 1.31b's $005f is    }

  { **FOUR BYTES NEITHER VERSION NAMES.** 1.31b has them too, as `Fill005A`, in
    the same place relative to its neighbours -- between the tick counter and the
    guard -- and its transcription could not name them either. So this is not
    something v1.51 introduced and not something a later reading of this image
    will settle: nothing in either program touches them. }
  Fill001C : LongInt = 0;

  { NEW IN v1.51, DS:$0020. Poll acquired a body and needs its own guard: the
    handler's Busy cannot serve, because the whole point of the change is that
    the two now run at different times. }
  PollBusy : Byte    = 0;

  { DS:$0060. `03 'G' 'U' 'S'` and a zero -- INITIALISED DATA, so a typed
    constant rather than a var assigned at run time. The eight pointers below
    +$16 are filled in by the initialisation section at the foot of this unit.

    A typed constant may leave its trailing fields out, which is what the
    release does too: everything past DMA is written as code. }
  DevData : TSoundDevice = (
    DevID : GUSDevID;
    DMA   : False
  );

implementation

{ ~~Busy, LastTick, UsingGUS, TicksPerSecond and DriverTicks were declared here.~~ ALL FIVE
  HAVE MOVED, and the DGROUP LAYOUT is what moved them.

  `UsingGUS` ($0bce), `TicksPerSecond` ($0bcc) and `DriverTicks` ($0bd0) are in SOUNDDEVICES'
  block, which runs $0b94..$0c0b unbroken -- this unit's own data is at $0058..$0099 and
  cannot reach any of them. All three were declared in two units at once; this file's
  own note said `TicksPerSecond`'s ownership was "the DGROUP-ownership question, not a
  naming one", and it now has an answer: neither of the two units that declared it.
  Two of the three needed a rename to go, because one address cannot carry two names --
  `UsingGUS` is SoundDevices' `UsingGUS`, which is also the release's name for it, and
  `DriverTicks` is `DriverTicks`, to keep it apart from the core's own `DriverTicks` at $0bc8.

  `Busy` and `LastTick` stay in this unit but moved UP into the interface const block,
  because their addresses are BELOW `DevData` at $0060 and a unit lays its interface
  declarations down before its implementation ones. `LastTick` also has to be visible:
  1000:02a1 writes it. }

{ THREE VARIABLES USED TO BE DECLARED HERE AND ALL THREE WERE DUPLICATES of
  globals another unit already owns. Every reference to one is a linker fixup,
  so verify.py could not see any of it -- the bytes agreed either way -- and
  `Callback` was standing in for TWO DIFFERENT ADDRESSES at once:

    DS:$4302/$4304   SavedSS/SavedSP, owned by SoundDevices, which switches
                     to the same private stack in its own shared poll
    DS:$4312         SoundDevices.PeriodicProc -- what 1084:003a CALLs
    DS:$058e         GUS.GUSTimer2RutPtr -- what 1084:008a STORES to

  The store and the call went through one `Callback : Pointer` whose comment
  claimed $4312, while the assignment's own comment said it reached $058e. The
  release settles it: DevInit writes `GUSTimer2Rut := NullTimerhandler` and
  NullTimerHandler calls `[PeriodicProc]`. Two different globals in two
  different units, and both are now referenced where they live. }

{ --------------------------------------------------------------------------
  1084:0000 -- the timer callback. Runs on somebody else's stack, with DS
  unknown.

  HAND ASSEMBLER, verbatim, and it could not be Pascal: it loads DS from a
  constant and switches SS:SP mid-routine. Neither is expressible.

  THREE THINGS HAPPEN BEFORE ANY WORK, and each is there for a reason.

  DS is loaded from `SEG @DATA` -- in the binary a literal `MOV AX,1CAAh`,
  which per the standing rule does NOT cross over as a number. An interrupt
  can arrive with any DS at all, so a callback has to establish its own.

  A RE-ENTRANCY GUARD at DS:$005e. If a poll runs long enough for the next
  timer tick to arrive, the second one turns round at the door rather than
  re-entering. The test is `JBE` rather than `JNZ`, which is what Borland
  Pascal emits for `if Busy <= 0`.

  A PRIVATE STACK. SS:SP are saved to DS:$4302 and DS:$4304, then SS is
  pointed at the data segment and SP at $4302 -- so the callback's stack
  grows downwards from just below the two words holding the caller's. The
  interrupted program's stack may be tiny, and a mixing routine's frame is
  not; borrowing it would corrupt whatever was interrupted. The same trick
  is in 1a17:1008, the core's shared poll.

  THE WORK ITSELF is one indirect far call, and it is SKIPPED when the driver
  is started and the tick counter has not moved since last time -- there is
  nothing new to do. When it is not started, the call happens unconditionally.
  -------------------------------------------------------------------------- }
{ NOT AN `assembler` PROCEDURE -- an ordinary one with an asm block inside.
  The distinction is visible in the bytes. An `assembler` procedure that
  names no parameter gets NO frame at all, so it would begin straight at
  MOV AX,SEG @DATA. The original begins PUSH BP / MOV BP,SP at 1084:0000 and
  ends LEAVE / RETF at 1084:004a, which is the standard prologue and epilogue
  wrapped around a hand-written body. }
procedure NullTimerHandler; far;
begin
  asm
  MOV  AX, SEG @DATA
  MOV  DS, AX
  CMP  Busy, 0
  JBE  @@Take         { 106e:000d  zero -> nobody is inside              }
  JMP  @@Out          { 106e:000f  already inside; do nothing            }
@@Take:
  INC  Busy
  INC  LastTick
  CALL FAR PTR FlushEventRow    { 106e:0019  CALLF 12ce:03d9  -- NOT      }
                              { AdvanceEventRow; see PlayMod's interface  }
  DEC  Busy
@@Out:
  end  { 106e:0022  LEAVE / RETF, supplied by Pascal      }
end;

{ --------------------------------------------------------------------------
  1084:004c -- THE POLL, slot +$2a.

  One increment. The whole of what a GUS driver has to do per tick, because
  the card is playing from its own memory and needs nothing from the host.
  NullTimerHandler above reads this counter to decide whether anything moved.
  -------------------------------------------------------------------------- }
procedure Poll; far;
begin
  {THE WORK THAT LEFT THE INTERRUPT. In v1.31b this routine
    was one increment and the handler did the stack switch and the indirect
    call; v1.51 moves both here. WHATSNEW.DOC: "under GUS the CallMusic() is no
    longer a dumb do-nothing -- now the partiture is not interpreted during
    interrupts, and behaves more like under SB."

    NO `MOV AX,SEG @DATA` at the top, unlike the handler: Poll is called with DS
    already right, and only an interrupt entry has to establish it.

    The guard is PollBusy, not Busy. The two now run at different times and each
    needs its own. }
  asm
  CMP  PollBusy, 0
  JBE  @@Take
  JMP  @@Out
@@Take:
  INC  PollBusy
  MOV  SoundDevices.SavedSS, SS { 106e:0034  keep the caller's stack     }
  MOV  SoundDevices.SavedSP, SP
  MOV  DX, DS
  { **THE STACK THIS SWITCHES TO IS `SoundDevices.PollStack`**, and the operand
    below is why nothing could find it: SP is loaded with the address of `SavedSS`,
    the variable ABOVE the block, and the stack then grows down through it. The
    block's own address appears in no instruction anywhere in the image. }
  MOV  SS, DX         { 106e:003e  ours lives in the data segment        }
  MOV  SP, OFFSET SoundDevices.SavedSS  { 106e:0040  the top of PollStack }
  CALL DWORD PTR SoundDevices.PeriodicProc
  MOV  SS, SoundDevices.SavedSS
  MOV  SP, SoundDevices.SavedSP
  INC  DriverTicks    { 106e:004f  AFTER the call, not before            }
  DEC  PollBusy
@@Out:
  end  { 106e:0057  LEAVE / RETF, supplied by Pascal      }
end;

{ --------------------------------------------------------------------------
  1084:0055 -- slot +$16, the device name. It returns an EMPTY STRING.

  This looked for a long time like "clears one byte through a far pointer",
  because that is literally what the four instructions do:

      LES DI,[BP+6] / MOV BYTE PTR ES:[DI],0 / LEAVE / RETF

  The giveaway is the plain `RETF` with no immediate while a parameter at
  [BP+6] is being read: the routine does not pop what it was passed. That is
  exactly how Turbo Pascal returns a String from a far function -- the CALLER
  allocates the result buffer, pushes a pointer to it, and pops it again --
  and writing 0 to the first byte sets the length to zero.

  Declared as taking a pointer, it compiles to RETF 4 and pops an argument
  the caller has already accounted for. Declared as the function it is, the
  bytes match.
  -------------------------------------------------------------------------- }
function DevName : TDevID; far;
begin
  DevName := '';
end;

{ --------------------------------------------------------------------------
  1084:0061 -- slot +$1a, the probe. Hands the question to the hardware layer
  and passes the answer straight back.

  TRUE means the card answered. No caller in the program tests the result --
  see the note on Autodetect in VTDRIVER.PAS.
  -------------------------------------------------------------------------- }
function DevDetect : Boolean; far;
begin
  DevDetect := GUS.DetectUltrasound;
end;

{ --------------------------------------------------------------------------
  1084:0072 -- slot +$1e, start.

  Reset the card, install this unit's timer entry as the driver's callback,
  and program the GF1's own timer from the sample rate.

  THE DIVISOR is the interesting part:

      D := 2000000 div (Rate * 320)
      D := (D + 1) shr 1
      Value := $100 - D

  A count subtracted from 256 is the reload value for an eight-bit
  down-counter, which is what the GF1's timers are. The `+1` before the halve
  is a round-to-nearest rather than a truncation, so the tick lands as close
  to the requested rate as an eight-bit divisor allows.
  -------------------------------------------------------------------------- }
{ NO LOCAL. The original's frame is PUSH BP / MOV BP,SP with nothing
  reserved; splitting the divisor across a LongInt local makes Turbo Pascal
  emit ENTER 4,0 and the whole routine shifts. It is one expression, and the
  1.39b release's DevInit writes it as one too:

      GUSInitTimer2($100 - ((2000000 DIV (TicksPerSecond*320) + 1) SHR 1)) }
{ IT TAKES A RATE AND IGNORES IT. The original ends `RETF 2`, so two bytes
  of parameter are popped, but the body reads the rate from DGROUP at
  [0bcc] rather than from the frame. Declared without the parameter it
  compiles to a plain RETF and every caller's stack is two bytes out. }
procedure DevInit(Hz : Word); far;
begin
  GUS.StartUltrasound;
  GUS.InitGusIRQ;
  UsingGUS := True;

  GUS.GUSTimer2RutPtr := @NullTimerHandler;

  { THE MULTIPLY IS 16-BIT. The original is `IMUL AX,[Rate],$140` -- one 286
    instruction with an immediate -- followed by XOR DX,DX to widen the WORD
    product into a LongInt for the divide. Casting Rate to LongInt first
    instead calls the 32-bit runtime multiply and looks nothing like it.

    That also settles what it is: a 16-bit product only stays in range for a
    tick rate of around 50, not a sample rate, which is why it carries the
    release's name TicksPerSecond. }
  GUS.GUSInitTimer2($100 -
    ((2000000 div LongInt(TicksPerSecond * $140) + 1) shr 1));

  LastTick := DriverTicks;
end;

{ --------------------------------------------------------------------------
  1084:00d5 -- slot +$32, stop. Two calls into the hardware layer, in the
  reverse order to Start's.
  -------------------------------------------------------------------------- }
procedure DevEnd; far;
begin
  GUS.DoneGusIRQ;
  GUS.StartUltrasound;
end;

{ --------------------------------------------------------------------------
  1084:00e4 -- slot +$26, "what rate can you actually manage?"

  Returns what it was given. The GUS resamples every voice in hardware, so
  any rate the caller names is one it can play. A driver that could not would
  answer with the nearest it supports; see 193a.
  -------------------------------------------------------------------------- }
function DevGetRealFreq(Hz : Word) : Word; far;
begin
  DevGetRealFreq := Hz;
end;

{ --------------------------------------------------------------------------
  1084:00f5 and 1084:00fc -- slots +$22 and +$2e. Empty.

  The first takes a word and the second takes nothing, and neither does
  anything with it. Whatever these mean, the GUS has no use for them.
  -------------------------------------------------------------------------- }
procedure DevChgHz(Hz : Word); far;
begin
end;

procedure DevPoll; far;
begin
end;

{ --------------------------------------------------------------------------
  1084:0101 -- fill in the record and hand it to the player core.

  Eight far addresses written straight into DS:$0076..DS:$0095. That range is
  DS:$0060 + $16 through + $35, which is what fixes the driver layout -- see
  VTDevData. No VMT is built and none is referenced.

  The name at +$00 is not written here: 'GUS' is already sitting in DGROUP as
  initialised data, so the reconstruction gives it as a typed constant in the
  initialisation below rather than assigning it.

  REGISTRATION ORDER DECIDES THE DEFAULT DEVICE. 1a17:02ba pushes onto the
  front of the list but only SELECTS when nothing is selected yet, so the
  first driver to register wins -- and this unit registers before 1065. That
  is why a machine with both ends up on the GUS.
  -------------------------------------------------------------------------- }
begin
  DevData.Name            := @DevName;
  DevData.Autodetect      := @DevDetect;
  DevData.InitRut         := @DevInit;
  DevData.ChgHzProc       := @DevChgHz;
  DevData.GetRealFreqProc := @DevGetRealFreq;
  DevData.TimerHandler    := @Poll;
  DevData.PollRut         := @DevPoll;
  DevData.EndRut          := @DevEnd;

  SoundDevices.InitDevice(@DevData);
end.
