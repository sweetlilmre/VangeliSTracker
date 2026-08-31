{  Every one of those patch sites is a label here rather than a literal
  address, per the standing rule in docs/06-transcription.md.

  NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information. Every
  routine is named for what it does and carries the address it came from.
  =========================================================================== }

{$G+}   { 80286 code, which this unit needs for PUSHA/POPA and the shift
          forms the mixer uses. A 386 is not required: the few 386
          instructions appear as an explicit prefix byte rather than as
          generated code, so the player still runs on a 286. }

unit SoundDevices;

interface

uses VTDriver, Dos, Hardware;

type
  { The block the provider hands back. Every offset here is read off
 and they agree with the release's TSampleBuffer exactly:
    InUse at +0, NSamples at +1, RateHz at +3, Channels at +5, DataType at +6
    and the data pointer at +7.

    THE RELEASE MAKES THIS A VARIANT RECORD, `CASE DataType : TDataType OF
    dtInteger: (IData : PIntBuff); dtShortInt: (SData : PShortBuff)`, and both
    arms are a far pointer at the same offset. Flattened to one field here
    because the layout is identical and nothing in this segment reads it as
    anything but an address.

    DataType IS SIGNED, and that is from the bytes rather than a choice:
 sign-extends it with CBW. A Turbo Pascal enumerated type would
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


procedure SetDevice(D : PSoundDevice);
function  InitDevice(D : PSoundDevice) : Word;
function  LocateDevice(ID : String) : PSoundDevice;


procedure StartSampling;
procedure EndSampling;


procedure SetPeriodicProc(Proc : TProc; PerSecond : Word);
procedure SetBufferAsker(Proc : TAskBufferProc);


function  GetRealFreq(Hz : Word) : Word;
procedure CalcTimerData(Hz : Word);

{ ---- the buffer queue ---------------------------------------------------- }

function  DoGetBuffer : Word;


procedure InitSoundDevices;


function  GetPlayPos : Pointer;


procedure SharedPoll;

procedure DevInitSbDMA(Stereo : Boolean; Bits : Byte);

{ ---- state that other units reach into -------------------------------
  In the original these are absolute DGROUP addresses, quoted here so the
  reading can be checked against the disassembly. Nothing outside this unit
  uses the addresses; see "one DGROUP, many units" in docs/06-transcription. }

{ ==========================================================================
  THIS UNIT'S DGROUP CONST BLOCK, $0b94..$0c0b, IN ADDRESS ORDER.

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

  THE PADS ARE TP WORD-ALIGNING EACH CONSTANT, the same rule as everywhere else in this
  layout: $0b95 after NumDevices, $0ba7 after DeviceIdling, $0c4e, $0bc3, $0bcf and
  $0be3. Every one of them lands the following constant on an address an instruction
  already named.
  ========================================================================== }
const
  NumDevices        : Byte         = 0;      { pad at $0b95         }
  ActiveDevice      : PSoundDevice = nil;
  Sounding          : Pointer      = nil;    { NON-DMA only         }
  SoundLeft         : Word         = 0;
  NumChannels       : Word         = 1;
  ChannelIncr       : Word         = 1;
  DMABufferSize     : Word         = 46000;
  DeviceIdling      : Byte         = 1;      { pad at $0ba7         }

  { $0ba8..$0baf. THREE OF THE FOUR HOLD 16000, WHICH FIXES `DefaultHz`. The release
    initialises TimerHz, SoundHz and DesiredHz to `DefaultHz` and does not say what
    that is here; 1.31's image says 16000 three times over -- and VTGlobal's `ShellHz`
    holds 12000, which is the release's `DefaultHz * 3 DIV 4` exactly. Two units
    agreeing on a constant neither of them stores by name. }
  TimerHz           : Word         = 16000;
  LastHz            : Word         = 0;
  SoundHz           : Word         = 16000;
  DesiredHz         : Word         = 16000;

  { the release calls it `SystemClockCount`; ours says what it does,
    accumulating SystemClockIncr until it carries, which is when the displaced BIOS
    handler gets called. }
  ClockAccum        : Word         = 0;
  SystemClockIncr   : Word         = 0;
  TimerVal          : Word         = 0;      { what goes to the PIT }
  DeviceInitialized : Boolean      = False;  { pad at $0bb7         }
  DMAOffset         : Word         = 1;      { samples held back    }
  HzChanged         : Boolean      = False;
  DoBassPower       : Boolean      = False;  { the filter stage     }
  MixMethod         : Byte         = 3;      { 0..3                 }
  Stereo            : Boolean      = False;
  BytesPerSample    : Byte         = 1;
  DevBits           : Byte         = 8;
  DMAStop           : Boolean      = False;
  DMAStopped        : Boolean      = False;
  DMAIrqWatch       : Byte         = 0;      { pad at $0bc3         }

  DMAChannel        : Word         = 255;

  NxOption          : Boolean      = False;  { set by `nx`, unread  }

  IsDmaDevice       : Boolean      = False;  { picks @@Prepare's path }

  Ticks             : Word         = 0;      { VTSilenc advances it  }
  TickSnapshot      : Word         = 0;      { compares it }
  TicksPerSecond    : Word         = 50;     { 50 = Europe           }

  UsingGUS          : Boolean      = False;  { pad; was GusStarted   }
  { A SECOND TICK COUNTER, and 1.31's own: the release has nothing between
    TicksPerSecond and the filter coefficients. DevGus's timer handler advances it and
 clears it, so it was declared in BOTH of those units -- DevGus called it
    `Ticks` and VTMAIN called it `WordAtBD0`. It is neither unit's: this block is
    contiguous from $0b94 to $0c0b and DevGus's own data is at $0058..$0099.}
  DriverTicks       : Word         = 0;      { the polled driver's   }

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
    independent channel volumes to hold at startup.}
  TrebleFilterVal_Left   : Word = 6;
  TrebleFilterMult_Left  : Word = 3;
  BassFilterVal_Left     : Word = 13;
  BassFilterMult_Left    : Word = 0;
  TrebleFilterVal_Right  : Word = 6;
  TrebleFilterMult_Right : Word = 3;
  BassFilterVal_Right    : Word = 13;
  BassFilterMult_Right   : Word = 0;

  PeriodicHz        : Byte         = 0;      { pad at $0be3         }
  PeriodicStart     : Word         = 1;      { NON-DMA countdown    }
  PeriodicCount     : Word         = 0;
  DSPWritePort      : Word         = 0;
  DSP8AckPort       : Word         = 0;
  DSPLifePort       : Word         = 0;
  SbCmdTimeout      : Word         = 100;
  SbSplTimeout      : Word         = 10;

  { $0bf2..$0bf7 -- THREE DAC PORTS, all $378, which is LPT1. A Covox or similar
    hangs off the printer port; the left and right pair is for a stereo one. }
  DacPort           : Word         = $378;
  LDacPort          : Word         = $378;
  RDacPort          : Word         = $378;

  { $0bf8..$0c01 -- FIVE slots, not four. The release calls them DeviceStartRut,
    DeviceRut1, DeviceRut2, DeviceKickRut and DeviceFillRut; ours are named for the
    1a17 offsets that patch them, and the fifth is what the gap at $0c00 was. }
  OutSlot0          : Word         = 0;      { the four output loops, patched }
  OutSlot1          : Word         = 0;      { in by SelectOutput: 8 or 16    }
  OutSlot2          : Word         = 0;      { bit, mono or stereo. The mixer }
  OutSlot3          : Word         = 0;      { calls one indirectly per step. }
  MixRut            : Word         = 0;      { release: DeviceFillRut }

  DeviceList        : PSoundDevice = nil;
  OldTimerHandler   : Pointer      = nil;
  IntInstalled      : Boolean      = False;  { pad at $0c0b         }

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
    blocks of a thousand, not because the stack is 2000.}
  DevStack          : array[1..DevStkSize] of Byte;

  {    THE SIZE IS THE SAME `DevStkSize`, and the arithmetic closes with nothing
    over: $5e8c + 1000 is $6274, $6274 + 1000 is $665c, and $665c is `SavedSS`. }
  PollStack         : array[1..DevStkSize] of Byte;

  { $4302/$4304 -- the caller's stack, saved across the poll, because the poll
    switches to the stack above. The release calls them `DevSS` and `DevSP`. }
  SavedSS           : Word;
  SavedSP           : Word;

  DMABufferPtr      : Pointer;       { where the mixer is up to  }
  DMABuffer         : Pointer;
  DMABufferEnd      : Word;          { Ofs(DMABuffer^) + the size }
  DMABufferYet      : Boolean;       { and a pad at $4311        }

  { the far routine the poll actually calls once it is on its
    own stack and has taken the guard. Installed by the core at startup. }
  PeriodicProc      : Pointer;

  { ---- the buffer queue ------------------------------------------------ }
  AskBufferProc     : TAskBufferProc;{ where the next buffer comes from     }
  ActualBuffer      : PSampleBuffer; { the block playing         }
  NextBuffer        : PSampleBuffer; { the one behind it         }
  PleaseFallback    : Word;          { no buffer was available   }


{ ---- WHAT CANNOT MATCH, AND WHERE ------------------------------------
  FOUR BYTES, in three places, and they all say the same thing.

    1007         1  the near epilogue RET, where the original has a 00 pad
    104d         1  SharedPoll's far epilogue RETF, which the original has not
                    got at all
 2  the epilogue again, where the original ends RETF 4

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

 19  the value-String copy. It was the compiler, and TP6 makes
                    the runtime call the original makes.
 8  GetPlayPos's register allocation -- not the compiler at all.
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
 -- the two null callbacks.}
procedure NullProcedure; far; assembler;
asm
end;                                          { 0000  a bare RETF, one byte }

function NullBufferProc : PSampleBuffer; far;
begin
  NullBufferProc := nil
end;

{ ==========================================================================
  Start the periodic callback: hook the timer and set its rate.

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
  if PeriodicHz = 0 then
  begin
    PeriodicStart   := 0;
    PeriodicCount   := 0;
    SystemClockIncr := TimerVal
  end
  else
  begin
    PeriodicStart := TimerHz div PeriodicHz;
    if PeriodicStart = 0 then
      PeriodicStart := 1;                     { 0049  never zero            }
    PeriodicCount   := 1;
    SystemClockIncr := TimerVal
  end
end;

{ ==========================================================================
SetPeriodicProc

  Installs the routine every poll path funnels into. The store is an asm block
  rather than a Pascal assignment because it has to be ATOMIC against the
  interrupt that is about to call through it -- PUSHF/CLI around a two-word
  write, restoring the caller's flag state rather than blindly re-enabling.
  The release has the same asm block for the same reason.}
procedure SetPeriodicProc(Proc : TProc; PerSecond : Word);
begin
  asm
    PUSHF
    CLI
    LES  BX, Proc                { the FIRST parameter     }
    MOV  WORD PTR PeriodicProc, BX
    MOV  WORD PTR PeriodicProc+2, ES
    POPF                         { 006d  the caller's flags, not STI       }
  end;
  PeriodicHz := PerSecond;
  InitPeriodic
end;

{ ==========================================================================
OriginalHwTimer. FRAMELESS: no parameters, a bare RET.

  HAND ASSEMBLER, verbatim. Puts PIT counter 0 back the way the BIOS left it:
  mode 3, square wave, reload 0 meaning a full 65536. That is 18.2 Hz, which
  is what every DOS program expects INT 8 to arrive at.

  The reload is written as two byte OUTs to the same port because the 8253
  latches low-then-high on consecutive writes; there is no word access.
  ========================================================================== }
procedure OriginalHwTimer; assembler;
asm
  MOV  AL, 36h           { 007b  counter 0, both bytes, mode 3             }
  OUT  43h, AL
  XOR  AL, AL
  OUT  40h, AL           { 0081  reload, low byte                          }
  OUT  40h, AL           { 0083  ... and high -- 0 means 65536             }
end;

{ ==========================================================================
RestoreTimer. Near and private.

  Gives IRQ 0 back. Guarded by its own flag so calling it twice is harmless,
  which matters because both EndSampling and StartSampling reach it.

  THE ORDER IS THE VECTOR FIRST, THEN THE PIT. Reprogramming the PIT while our
  handler is still hooked would leave it being entered at 18.2 Hz, which it can
  survive; doing it the other way round would leave the BIOS handler being
  entered at the mixer's rate, which it cannot.
  ========================================================================== }
procedure RestoreTimer;
begin
  if IntInstalled then
  begin
    SetIntVec(8, OldTimerHandler);
    OriginalHwTimer;
    IntInstalled := False
  end
end;

{ ==========================================================================
StartSampling. Far; one of the two entry points VTMain reaches.

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
  if not DeviceInitialized then RestoreTimer;

  ActualBuffer   := nil;
  NextBuffer     := nil;
  SoundLeft      := 0;
  PleaseFallback := 0;
  DeviceIdling   := 1;
  DMABufferPtr   := DMABuffer;
  DMABufferYet   := True;
  Stereo         := False;
  DevBits        := 8;
  BytesPerSample := 1;

  FillChar(DMABuffer^, DMABufferSize, $80);   { see above       }

  if ActiveDevice <> nil then                 { 0108  AX OR DX              }
  begin
    asm CLI end;
    DeviceInitialized := True;
    { 0117 pushes DesiredHz, then 011b..011f is LES DI / CALLF [DI+$1e] }
    TInitDevProc(ActiveDevice^.InitRut)(DesiredHz);
    asm STI end
  end;

  BytesPerSample := (DevBits + 7) div 8 *
                    (Byte(Stereo) + 1)
end;

{ ==========================================================================
EndSampling. Far.}
procedure EndSampling;
begin
  if (ActiveDevice <> nil) and DeviceInitialized then
  begin
    FillChar(DMABuffer^, DMABufferSize, $80);
    asm CLI end;
    TProc(ActiveDevice^.EndRut);              { CALLF [DI+$32]  }
    RestoreTimer;
    asm STI end;
    DeviceInitialized := False
  end
end;

{ ==========================================================================
SetBufferAsker

  A plain far-pointer store, but between CLI and STI: the queue drains from an
  interrupt, and a half-written pointer here would be called.

  Note this one is CLI/STI, not PUSHF/CLI/POPF as SetPeriodicProc uses. Both
  are the release's, and the difference is real rather than sloppy -- this is
  reached only from initialisation, where interrupts are known to be on.
  ========================================================================== }
procedure SetBufferAsker(Proc : TAskBufferProc);
begin
  asm CLI end;
  AskBufferProc := Proc;
  asm STI end
end;

{ ==========================================================================
SetDevice

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
    if DeviceInitialized then
    begin
      if D <> ActiveDevice then
      begin
        EndSampling;
        ActiveDevice := D;
        StartSampling;
        Exit
      end
    end;
    ActiveDevice := D
  end
end;

{ ==========================================================================
  Find a driver in the chain by name, matching on a prefix so that a short
  name in the config file reaches a longer registered one.

  Finds a device by the identification string at the head of its record. This
  is what VTMain uses to turn a name out of VT.CFG into a driver.

  ITS SENSE IS INVERTED, and deliberately so. It returns TRUE when the strings
  do NOT match, which is what lets the search read as one `while` with no
  negation: `while (p <> nil) and NotInStr(...) do p := p^.Next`. Reading it
  the obvious way round makes the loop condition wrong.

  IT IS A PREFIX TEST, NOT AN EQUALITY TEST. Only Length(ss) characters are
  compared, so 'GUS' matches a record whose ID is 'GUS16' -- the shorter of the
  two decides. The length guard rejects only the case where the pattern is
  LONGER than the candidate.}
function LocateDevice(ID : String) : PSoundDevice;

  function NotInStr(var s, ss : String) : Boolean;
  var
    i : Word;                     { the channel being mixed                }
  begin
    NotInStr := True;
    if Length(ss) > Length(s) then Exit;
    for i := 1 to Length(ss) do
      if UpCase(s[i]) <> UpCase(ss[i]) then Exit;
    NotInStr := False
  end;

var
  p : PSoundDevice;
begin
  p := DeviceList;
  while (p <> nil) and NotInStr(p^.DevID, ID) do
    p := p^.Next;                             { Next at +$36    }
  LocateDevice := p
end;

{ ==========================================================================
InitDevice

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
  D^.Next := DeviceList;
  DeviceList := D;
  if ActiveDevice = nil then                            { 02dd  AX OR DX   }
    SetDevice(D);
  Inc(NumDevices)
end;

{ ==========================================================================
GetRealFreq

  Answers "if you ask the PIT for this rate, what will you actually get?"

  THE POINT IS THE ROUNDING. The PIT takes an integer divisor, so only rates of
  the form 1193180/i are available. Dividing to get i and dividing back gives
  the rate for i; this ALSO computes the rate for i+1 and keeps whichever is
  nearer what was asked. Truncating the divisor always errs the same way, and
  over a whole module that is an audible pitch offset.

  Note both distances are computed with `Abs(Integer(...))` on a WORD
  subtraction: the difference is taken modulo 65536 first and only then read as
  signed. For rates anywhere near the audible range that is the same answer,
  and it is what the release does.
  ========================================================================== }
function GetRealFreq(Hz : Word) : Word;
var
  i    : Word;
  NHz1 : Word;
  NHz2 : Word;
begin
  if Hz = 0 then Hz := 1;                     { never divide by 0}
  i := 1193180 div Hz;

  NHz1 := 1193180 div  i;
  NHz2 := 1193180 div (i + 1);
  if Abs(Integer(NHz1 - Hz)) > Abs(Integer(NHz2 - Hz)) then
    NHz1 := NHz2;

  GetRealFreq := NHz1
end;

{ ==========================================================================
CalcTimerData

  A rate of zero gives $FFFF, the slowest the counter can go, rather than
  dividing by zero.}
procedure CalcTimerData(Hz : Word);
begin
  Hz := GetRealFreq(Hz);                      { PUSH CS / CALL  }

  if Hz = 0 then TimerVal := $FFFF
            else TimerVal := 1193180 div Hz;

  TimerHz := 1193180 div TimerVal;
  SoundHz := TimerHz
end;

{ ==========================================================================
DoGetBuffer. THE BUFFER QUEUE, and the heart of the double
  buffering that keeps a card fed.

  Two blocks are tracked: ActualBuffer is playing, NextBuffer is the one
  behind it. Each call retires the current block, promotes the next, and asks
  the provider for a replacement. When the provider has nothing, the queue has
  run dry and the else-branch handles the underrun.

  THE UNDERRUN PATH DROPS THE RATE TO PeriodicHz on a non-DMA device, which
  makes the timer tick slowly until buffers come back rather than spinning at
  the sample rate with nothing to play.
  ========================================================================== }
function DoGetBuffer : Word;
const
  Semaphore : Byte = 0;                       { see above       }
  Size      : Word = 1;
begin
  DoGetBuffer := 0;
  if Semaphore > 0 then Exit;
  Inc(Semaphore);

  if ActualBuffer <> nil then
    Size := ActualBuffer^.NSamples;

  ActualBuffer := NextBuffer;

  if ActualBuffer = nil then
  begin
    ActualBuffer := AskBufferProc;
    if ActualBuffer <> nil then
      ActualBuffer^.InUse := True
  end;

  if ActualBuffer = nil then                  { the queue is dry}
  begin
    if (Size <> 1) and (not ActiveDevice^.DMA) then
      Inc(PleaseFallback);
    SoundLeft := 0;
    if not ActiveDevice^.DMA then
    begin
      PeriodicCount := 1;
      LastHz        := PeriodicHz;
      TInitDevProc(ActiveDevice^.ChgHzProc)(LastHz)   { +$22    }
    end
  end
  else
  begin
    Sounding    := ActualBuffer^.IData;
    SoundLeft   := ActualBuffer^.NSamples;
    NumChannels := ActualBuffer^.Channels;
    ChannelIncr := ActualBuffer^.Channels *
                   (Ord(ActualBuffer^.DataType) + 1);

    if LastHz <> ActualBuffer^.RateHz then
    begin
      LastHz := ActualBuffer^.RateHz;
      TInitDevProc(ActiveDevice^.ChgHzProc)(LastHz);
      HzChanged := True
    end;

    { The DMA path plays a few samples behind where the mixer has written, so
      the last DMAOffset samples of the block are held back -- and never fewer
      than five, which is what the else-branch is for. }
    if ActiveDevice^.DMA then
    begin
      if SoundLeft > DMAOffset + 5 then
        Dec(SoundLeft, DMAOffset)
      else
        SoundLeft := 5
    end;

    NextBuffer := AskBufferProc;
    if NextBuffer <> nil then
      NextBuffer^.InUse := True
  end;

  DoGetBuffer := SoundLeft;
  Dec(Semaphore)
end;

{ ==========================================================================
InitSoundDevices. THE UNIT'S OWN INITIALISATION, and the most
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
  the base up to the next one and remembers the gap in OffsFree.}
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
  l        : LongInt;
  PtrFree  : Pointer;
  OldHPtr  : Pointer;
  p        : PFreeBlock;
  OffsFree : Word;
begin
  { `@`, because PeriodicProc is a plain Pointer here rather than the release's
    procedural type -- SharedPoll calls it with CALL DWORD PTR, so typing it
    would buy nothing. AskBufferProc IS typed, so that one needs no `@`. }
  PeriodicProc  := @NullProcedure;            { do nothing until a driver    }
  AskBufferProc := NullBufferProc;            { installs its own             }

  { The buffer starts at the heap top, wherever that is. }
  DMABuffer := HeapPtr;

  l := (LongInt(Seg(DMABuffer^)) shl 4) + Ofs(DMABuffer^);

  PtrFree  := HeapPtr;
  OffsFree := 0;

  { Would the buffer cross a 64K physical boundary? If so, step the base up to
    the next one and remember how much was skipped. }
  if LongInt(Word(l)) + DMABufferSize > 65536 then
  begin
    OffsFree := 65536 - LongInt(Word(l));
    l := (l and $F0000) + $10000
  end;

  DMABuffer    := Ptr((l shr 4) and $F000, Word(l));
  DMABufferPtr := DMABuffer;
  DMABufferEnd := Ofs(DMABuffer^) + DMABufferSize;

  { Allocate it by moving the heap top past it, by hand. }
  OldHPtr := HeapPtr;
  HeapPtr := Ptr((l + DMABufferSize + 16) shr 4, 0);
  if OldHPtr = FreeList then
    FreeList := HeapPtr
  else
  begin
    p := FreeList;
    while p^.Next <> OldHPtr do
      p := p^.Next;
    p^.Next := HeapPtr
  end;

  FillChar(HeapPtr^, 8, 0);

  if OffsFree > 0 then
    FreeMem(PtrFree, OffsFree)
end;

{ ==========================================================================
GetDMACount. Near and private.

  A one-line wrapper: hands the channel to 1b24's GetDMACount and passes the
  answer back. The release writes it as
  `GetDMACount := Hardware.GetDMACount(DMAChannel)`, with the unit
  qualification there for the same reason it is needed here -- the inner and
  outer routines share a name.}
function GetDMACount : Word;
begin
  GetDMACount := Hardware.GetDMACount(DMAChannel)
end;

{ ==========================================================================
  WHERE THE PLAYER HAS GOT TO IN THE OUTPUT BUFFER, in bytes.

  This is the only routine in the core that a DEMO calls rather than the
  player, and it answers the question a demo actually has: not "which pattern
  row" but "how far through the sound has the card got", which is what lets
  visuals be timed against the audio rather than against the tick.

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

  So this is dead code in the original -- the remains of an edit, where a
  statement that used to consume `x * BytesPerSample` was removed and its
  operand setup was not. It is transcribed as an `asm` block because there is
  no Pascal that produces it: any expression the compiler would accept would
  also load AX first. Verbatim, per the standing rule, rather than dropped --
  dropping it would shift every byte after it.
  ========================================================================== }
function GetPlayPos : Pointer;
var
  Left : Word;
begin
  { HAND-WRITTEN, and 0703..070b of it is DEAD. See above.

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
    MOV  DL, BytesPerSample
    XOR  DH, DH
    MUL  DX                   { 0709  AX is undefined on entry              }
    PUSH AX                   { 070b  and never popped; LEAVE discards it   }

    CALL GetDMACount          { 070c  near, back to 06ea                    }
    MOV  BX, DMABufferSize
    SUB  BX, AX               { 0713  29 c3 -- assembler direction           }
    MOV  Left, BX
  end;

  GetPlayPos := Ptr(Seg(DMABuffer^),
                    Ofs(DMABuffer^) +
                    (DMABufferSize + Left - 100)
                    mod DMABufferSize)
end;

{$L SOUNDDEV.OBJ}
procedure SetGains; external;
procedure SharedPoll; external;
procedure SelectOutput; external;
procedure DevInitSbDMA(Stereo : Boolean; Bits : Byte); external;

end.
