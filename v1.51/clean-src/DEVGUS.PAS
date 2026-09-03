{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  The Gravis UltraSound DRIVER: the eight entry points the player core calls,
  and the timer callback that drives them.

  NOT THE HARDWARE LAYER. Every port write lives in the GUS unit next door;
  this is the thin adapter that presents the card to the core in the shape the
  core expects, and almost nothing else.

  WHY THE GUS DRIVER IS ALMOST EMPTY. Three of its eight slots do nothing and
  a fourth returns its argument unchanged. A GUS holds the samples in its own
  DRAM and mixes them itself, so there is no buffer for the host to refill --
  the poll only has to count. Compare the Sound Blaster driver in 193a, where
  the same slot has to move data.

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
  LastTick : Word    = 0;   { clears it, so it is exported }

  Fill0016 : LongInt = 0;

  Busy     : Byte    = 0;   { in v1.51  the handler's guard          }

  { **THE FIRST OF THE FIVE IS AN ALIGNMENT PAD, AND 1.31b SAYS SO.** Its own
    DevGus declares `Busy : Byte = 0` and comments it "the re-entrancy guard;
    pad at $005f" -- one byte of guard, then one byte of padding, then an even
    address. The same pair is here: `Busy` at $001A and a pad at $001B. }
  Pad001B  : Byte    = 0;   { alignment, as 1.31b's $005f is    }

  { **FOUR BYTES v1.51 HAS AND 1.31b DOES NOT.** This note used to say 1.31b
    carried them too, as `Fill005A`, "between the tick counter and the guard" --
    and that is `Fill0016`'s position, which the note above already claims. 1.31b
    has ONE four-byte filler in this unit and two declarations here were both
    calling it their counterpart.

    THE NEIGHBOURS SETTLE IT. `Fill0016` sits between `LastTick` and `Busy`, and
    so does 1.31b's `Fill005A` -- same two neighbours, same width. These four sit
    between `Pad001B` and `PollBusy`, and `PollBusy` is NEW IN v1.51, so the whole
    region is. 1.31b goes $005e Busy, $005f pad, $0060 DevData with nothing in
    between; v1.51 goes $001a Busy, $001b pad, these four, then $0020 PollBusy.
    Five bytes that version does not have.

    So these are v1.51's own and only a reader in THIS image can name them.
    Nothing in the SEGMENT touches them. }
  Fill001C : LongInt = 0;

  PollBusy : Byte    = 0;

  { `03 'G' 'U' 'S'` and a zero -- INITIALISED DATA, so a typed
    constant rather than a var assigned at run time. The eight pointers below
    +$16 are filled in by the initialisation section at the foot of this unit.

    A typed constant may leave its trailing fields out, which is what the
    release does too: everything past DMA is written as code. }
  DevData : TSoundDevice = (
    DevID : GUSDevID;
    DMA   : False
  );

implementation



{ --------------------------------------------------------------------------
the timer callback. Runs on somebody else's stack, with DS
  unknown.

  HAND ASSEMBLER, verbatim, and it could not be Pascal: it loads DS from a
  constant and switches SS:SP mid-routine. Neither is expressible.

  THREE THINGS HAPPEN BEFORE ANY WORK, and each is there for a reason.

  DS is loaded from `SEG @DATA` -- in the binary a literal `MOV AX,1CAAh`,
  which per the standing rule does NOT cross over as a number. An interrupt
  can arrive with any DS at all, so a callback has to establish its own.

  THE WORK ITSELF is one indirect far call, and it is SKIPPED when the driver
  is started and the tick counter has not moved since last time -- there is
  nothing new to do. When it is not started, the call happens unconditionally.
  -------------------------------------------------------------------------- }
procedure NullTimerHandler; far;
begin
  asm
  MOV  AX, SEG @DATA
  MOV  DS, AX
  CMP  Busy, 0
  JBE  @@Take         { zero -> nobody is inside              }
  JMP  @@Out          { already inside; do nothing            }
@@Take:
  INC  Busy
  INC  LastTick
  CALL FAR PTR FlushEventRow    { hand the queued voice
                                commands to the card                     }
  DEC  Busy
@@Out:
  end  { LEAVE / RETF, supplied by Pascal      }
end;

{ --------------------------------------------------------------------------
THE POLL, slot +$2a.

  One increment. The whole of what a GUS driver has to do per tick, because
  the card is playing from its own memory and needs nothing from the host.
  NullTimerHandler above reads this counter to decide whether anything moved.
  -------------------------------------------------------------------------- }
procedure Poll; far;
begin
  { THE WORK THAT LEFT THE INTERRUPT. In v1.31b this routine
    was one increment and the handler did the stack switch and the indirect
    call; v1.51 moves both here. WHATSNEW.DOC: "under GUS the CallMusic() is no
    longer a dumb do-nothing -- now the partiture is not interpreted during
    interrupts, and behaves more like under SB."

    NO `MOV AX,SEG @DATA` at the top, unlike the handler: Poll is called with DS
    already right, and only an interrupt entry has to establish it.

    The guard is PollBusy, not Busy. The two now run at different times and each
    needs its own.

    **THERE ARE TWO POLLS IN THIS PROGRAM AND THEY ARE NEARLY THE SAME ROUTINE.**
    Reading them side by side is the fastest way to understand either:

                      SoundDevices.SharedPoll      DevGus.Poll (here)
      reached from    a timer interrupt            a Pascal call
      saves registers PUSHA, ES, DS -- it          nothing: the compiler's
                      borrowed them                own prologue covers it
      loads DS        MOV AX,SEG @DATA             not needed; DS is right
      guard           Busy, in the CODE SEGMENT    PollBusy, in DGROUP -- DS
                      because DS is not trusted    is already trusted here
                      yet
      stack           SoundDevices.DevStack        SoundDevices.PollStack
      saves SS:SP to  SavedSS / SavedSP            SavedSS / SavedSP -- THE
                                                   SAME PAIR

    The last line is the one that matters. Both save into the same two words, so
    if either could run inside the other the second save would destroy the
    first and the outer routine would return onto a stack that no longer
    exists. Nothing enforces that at the machine level; the two guards do, and
    that is what they are for.

    NOT SAVING REGISTERS IS CORRECT HERE, not an omission. An interrupt arrives
    uninvited and must leave no trace; a `far` procedure is called by code that
    already expects Pascal's conventions, and the compiler's own prologue and
    epilogue handle the rest. }
  asm
  { **A TEST AND TWO JUMPS WHERE ONE WOULD DO.** `JBE @@Take / JMP @@Out` is a
    short conditional jump forward over a long unconditional one -- written the
    obvious way round, as `JA @@Out`, the target would be out of a short jump's
    reach and the assembler would have to grow the instruction. The compiler
    does the same thing throughout this tree; here it is hand-written to match. }
  CMP  PollBusy, 0
  JBE  @@Take
  JMP  @@Out
@@Take:
  INC  PollBusy
  MOV  SoundDevices.SavedSS, SS { keep the caller's stack     }
  MOV  SoundDevices.SavedSP, SP
  MOV  DX, DS
  { **THE STACK THIS SWITCHES TO IS `SoundDevices.PollStack`**, and the operand
    below is why nothing could find it: SP is loaded with the address of `SavedSS`,
    the variable ABOVE the block, and the stack then grows down through it. The
    block's own address appears in no instruction anywhere in the image. }
  MOV  SS, DX         { ours lives in the data SEGMENT        }
  MOV  SP, OFFSET SoundDevices.SavedSS  { the top of PollStack }
  CALL DWORD PTR SoundDevices.PeriodicProc
  MOV  SS, SoundDevices.SavedSS
  MOV  SP, SoundDevices.SavedSP
  INC  DriverTicks    { AFTER the call, not before            }
  DEC  PollBusy
@@Out:
  end  { LEAVE / RETF, supplied by Pascal      }
end;

{ --------------------------------------------------------------------------
slot +$16, the device name. It returns an EMPTY STRING.

  This looked for a long time like "clears one byte through a far pointer",
  because that is literally what the four instructions do:

  The giveaway is the plain `RETF` with no immediate while a parameter at
 is being read: the routine does not pop what it was passed. That is
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
slot +$1a, the probe. Hands the question to the hardware layer
  and passes the answer straight back.

  TRUE means the card answered. No caller in the program tests the result --
  see the note on Autodetect in VTDRIVER.PAS.
  -------------------------------------------------------------------------- }
function DevDetect : Boolean; far;
begin
  DevDetect := GUS.DetectUltrasound;
end;

{ --------------------------------------------------------------------------
slot +$1e, start.

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
slot +$32, stop. Two calls into the hardware layer, in the
  reverse order to Start's.
  -------------------------------------------------------------------------- }
procedure DevEnd; far;
begin
  GUS.DoneGusIRQ;
  GUS.StartUltrasound;
end;

{ --------------------------------------------------------------------------
slot +$26, "what rate can you actually manage?"

  Returns what it was given. The GUS resamples every voice in hardware, so
  any rate the caller names is one it can play. A driver that could not would
  answer with the nearest it supports; see 193a.
  -------------------------------------------------------------------------- }
function DevGetRealFreq(Hz : Word) : Word; far;
begin
  DevGetRealFreq := Hz;
end;

{ --------------------------------------------------------------------------
  Change the sample rate, and poll the device: BOTH DO NOTHING. The card mixes
  from its own DRAM at a rate it was given once, so there is no rate to change
  mid-stream and nothing for a poll to move. The slots exist because the
  driver record has them.

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
fill in the record and hand it to the player core.

  The name at +$00 is not written here: 'GUS' is already sitting in DGROUP as
  initialised data, so the reconstruction gives it as a typed constant in the
  initialisation below rather than assigning it. }
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
