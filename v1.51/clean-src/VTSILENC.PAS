{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Segment 1065 -- the "Silence" driver. 496 bytes, eight routines.

  A SOUND DRIVER THAT MAKES NO SOUND. Its name is in the driver record at
  DS:$001e, seven characters: 'Silence'.

  What it provides is a CLOCK, and nothing else. A serial port's
  transmit-holding-empty interrupt fires at a rate you choose by setting the
  baud divisor, so this driver programs COM1 to 1200 baud, sends a byte from
  the handler to keep the interrupts coming, and counts. The music advances,
  the pattern position moves, anything watching the play position sees it
  progress -- and not a sample is played.

  THE RATE IS EXACTLY 50 Hz, and the arithmetic is worth following:

      1200 baud, 8 data bits + start + stop  =  10 bits per character
      1200 / 10                              =  120 interrupts per second
      the handler adds 5 and carries at 12   =  120 * 5/12 = 50 ticks/second

  Fifty is the PAL field rate and the tick a tracker is written against. The
  5-in-12 accumulator gets there exactly, with no drift, from a divisor the
  UART can actually produce -- which a direct 50 Hz divisor cannot.

  ITS POLL IS NOT ITS OWN. Register below puts 1a17:1008 -- the player core's
  shared poll -- in slot +$2a, not anything in this unit. So the core still
  does all its mixing work on schedule; there is simply nowhere for the
  result to go. Compare 1084, where the GUS supplies its own poll because the
  card plays for itself.

  THIS UNIT DOES NOT COMPILE YET: the poll slot and InitDevice both live
  in 1a17, which is not transcribed. See docs/06-transcription.md.

  ADDRESS MAP
    DevName      1065:0000     IrqHandler  1065:0005 *
    Probe       1065:0039     Start       1065:0046
    AskRate     1065:00f3     ChgHz      1065:0104
    DevPoll      1065:010b     Stop        1065:0110
    Register    1065:0172                     (* frameless, IRET)

  DGROUP
    $0018  the 5-in-12 accumulator     $001a  the displaced INT 0Ch vector
    $001e  THE DRIVER RECORD           $0bc8  the tick counter
    $0e2e  saved MCR                   $0e30  saved LCR
    $0e32  saved baud divisor          $0e34  saved IER
    $0e36  "IRQ 4 was masked before"

  NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.
  =========================================================================== }

unit VTSilenc;

interface

uses
  VTDriver;

const
  { $0018..$001d -- `Frac` AND `OldVec` ARE TYPED CONSTANTS, AND THEY OPEN THIS UNIT'S
    BLOCK. Their addresses are named by this unit's own instructions -- `1065:0018` is
    `MOV AL,[0018]` and `1065:005e` tests `[001a]` -- and they are in the INITIALISED
    half of DGROUP, which is what makes them constants rather than vars. Declared as
    `var`s they went to the variable half instead, six bytes that pushed every unit
    after this one down; and the six they should occupy were being counted as the tail
    of the program's `SelfName`, which is why that was read as String[25] and is really
    String[19]. Frac ($0204), a pad ($0205), OldVec ($0206..$0209), `Driver` at $020a:
    the arithmetic closes with nothing over.

    THE FIVE ADDRESSES ABOVE WERE v1.31b's UNTIL THE LINKER WAS ASKED, and so
    were the two instruction addresses this paragraph cites -- 1065 is a v1.31b
    segment. The ARGUMENT is untouched: the widths, the order, and the reasoning
    about the initialised half of DGROUP all hold. Only the numbers moved, which
    is what makes prose like this dangerous -- it stayed persuasive while every
    figure in it was wrong. }
  { NEW IN v1.51, AND THEY OPEN THE BLOCK. v1.31b has these as UNTYPED
    constants -- `ComPort = $3F8; ComIrq = 4;` -- which occupy no DGROUP and
    compile to immediates: 1065:0013 is `MOV DX,03F8`. v1.51 makes both
    configurable (`/port:` and `/irq:` in WHATSNEW.DOC), so they become typed
    constants and 115e:0013 is `MOV DX,[0200]`, four bytes against three.

    CHANGING THE DECLARATION IS THE WHOLE EDIT. Turbo Pascal's inline assembler
    resolves a typed constant to a MEMORY OPERAND and an untyped one to an
    IMMEDIATE, so every `MOV DX, ComPort` in this unit's assembler follows
    automatically -- nothing in the bodies changes.

    THEY HAVE TO SIT AHEAD OF `Frac`, and the block arithmetic is what says so:
    v1.31b runs Frac $18, pad, OldVec $1a, Driver $1e, table $34 -- and $34-$18
    is $1c. v1.51's table is at $220 and its Frac at $204, the same $1c apart,
    with $200 and $202 above. Four bytes, two Words, declared first. }
  { **COM2 IN v1.51, COM1 IN 1.31b.** DGROUP +$0200 holds `f8 02` and +$0202 holds
    `03 00`. Two bytes, and no instruction anywhere names either value -- both are
    initialisers a command-line switch overwrites, so only the image says what the
    default is. }
  ComPort : Word    = $2F8;   { COM2 by default }
  ComIrq  : Word    = 3;

  Frac    : Byte    = 0;      { the 5-in-12 accumulator }
  OldVec  : Pointer = nil;    { the displaced INT 0Ch vector }

  { DS:$001e. A TYPED CONSTANT, not a var, so that 'Silence' is INITIALISED
    DATA rather than something the unit assigns at run time -- exactly what
    DEVGUS does with 'GUS'. The old shape had a `begin Driver.DevID :=
    'Silence' end.` block, and that block is code the original has not got. }
  { DMA IS **TRUE**, AND IT IS READ FROM THE IMAGE RATHER THAN REASONED. DS:$0033 is
    this record's +$15, which is `DMA` -- DevID is a String[20] and so occupies +$00
    to +$14 -- and the original holds 01 there where this said False. It was the only
    byte of the whole initialised DGROUP whose VALUE disagreed once the layout lined
    up, which is what made it visible at all.

    It also makes sense of the driver. 1065 is a UART on IRQ 4 driven purely as a
    CLOCK, and 12ba:0c52 gates the mixer with `IF IsDmaDevice AND (TickSnapshot =
    Ticks)`. A device that produces no output and only paces the tick wants that gate
    active, which is what claiming DMA does. DevGus's own record has DMA FALSE at the
    same offset in both images, so the two are not simply copies of one default. }
  Driver : TSoundDevice = ( DevID : 'Silence'; DMA : True );

{ ~~Ticks : Word at DS:$0bc8~~ -- MOVED TO SOUNDDEV.PAS, where the note explains
  why. In short: PlayMod reads $0bc8 and the original's link order forbids PlayMod
  from using this unit, so the counter cannot be declared here. This unit still
  advances it; it just does not own it. }

{ ~~procedure Register; far;~~ -- 1065:0172 IS THE UNIT'S INITIALISATION
  SECTION, not an exported procedure, and the LINK is what settled it: nothing
  anywhere calls `Register`, so the smart linker discarded it and everything it
  referenced, leaving VTSILENC at 30 bytes of a 489-byte segment. The original's
  init chain calls 1065:0172. **This is the same error DEVGUS already had and
  this file already describes** -- see the note there, where fixing it took the
  unit from 402 bytes to 376. }

implementation

uses
  Hardware, SoundDevices;

const
  Divisor  = $0060;      { 115200/96 = 1200 baud }
  AddPer   = 5;          { the accumulator step  }
  CarryAt  = 12;         { ... and its modulus   }

var
  { ~~Frac and OldVec~~ are TYPED CONSTANTS in the interface now -- see the note there.
    $0018 and $001a really are their addresses; what was wrong was reading those six
    bytes as the tail of the program's `SelfName`. }
  SavedMCR, SavedLCR, SavedDiv, SavedIER : Word;   { .. $0e34 }
  { **STALE, AND UNANCHORED.** This unit links at position 4 and VTCmd at 2, so
    this variable must sit above VTCmd's $0ef6. It does not. The claim is
    consistent with nothing else in the file -- it is the only variable here with
    an address -- and no instrument in the kit can reach it: a variable is absent
    from the image, and this one is not public, so the linker map is silent too.
    Left as it stands and marked, rather than replaced with a guess. }
  WasOn  : Boolean;     { STALE }

{ ~~Flag0BC7, Flag0BBD, Flag0BBF, Flag0BBC~~ -- ALL FOUR GONE, and all four were
  SoundDevices' own, in its CONSTANT-region block at $0bbc..$0bc7. The note here said
  "what they mean belongs to 1a17", which was right about the owner and did not follow
  it through to the declaration; the values are what name them, because Start writes
  1, 0, 8 and 0, which is `IsDmaDevice := True`, `Stereo := False`, `DevBits := 8` and
  `MixMethod := 0`. A driver that produces no output telling the core it is a DMA device
  with 8-bit mono output. Declared here they were four extra bytes of THIS unit's
  variables, which pushed every unit after it down the variable half of DGROUP. }

{ --------------------------------------------------------------------------
slot +$16. Empty, and takes nothing.

  1084's version of this slot takes a far pointer and clears a byte through
  it; this one ignores whatever is passed. Both end in a plain RETF rather
  than RETF n, so the CALLER clears the arguments either way and the two
  signatures can differ without anything going wrong.
  -------------------------------------------------------------------------- }
procedure DevName; far;
begin
end;

{ --------------------------------------------------------------------------
the serial interrupt. FRAMELESS, ends in IRET.

  HAND ASSEMBLER, verbatim. It cannot be a Pascal `interrupt` procedure: it
  loads DS from a constant and saves a hand-picked subset of registers in a
  hand-picked order.

  THE FIRST THING IT DOES IS SEND ANOTHER BYTE. A transmit-holding-empty
  interrupt stops arriving the moment the holding register is not empty, so
  the handler has to refill it or the clock dies after one tick. The byte
  written is zero and nothing is listening -- the port is a metronome, not a
  serial link.

  THEN THE ACCUMULATOR. Add 5, and every time the total reaches 12 subtract
  12 and count a tick. Twelve interrupts produce five ticks, forever, with
  the remainder carried rather than dropped -- so 120 Hz becomes exactly
  50 Hz with no rounding error accumulating over a four-minute module.

  THE EOI IS SENT LATE, after the registers are restored but before DS. That
  is a deliberate ordering: the handler is short enough that holding the
  controller for its duration costs nothing, and doing it late means a second
  serial interrupt cannot arrive while the accumulator is half-updated.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[ComPort] := 0;
      Inc(Frac, 5);
      if Frac >= 12 then begin Dec(Frac, 12); Inc(Ticks) end;
      Port[$20] := $20
  -------------------------------------------------------------------------- }
procedure IrqHandler; assembler;
asm
  CLI
  PUSH AX
  PUSH DS
  PUSH DX
  MOV  AX, SEG @DATA     { was MOV AX,1CAAh                     }
  MOV  DS, AX
  PUSH ES
  PUSH BX
  PUSH CX
  PUSH DI
  PUSH SI
  MOV  DX, ComPort       { was MOV DX,03F8h                     }
  XOR  AL, AL
  OUT  DX, AL            { keep the interrupts coming           }
  MOV  AL, Frac
  ADD  AL, AddPer        { + 5                                  }
  CMP  AL, CarryAt
  JC   @@NoTick
  SUB  AL, CarryAt       { carry the remainder, do not drop it  }
  INC  Ticks
@@NoTick:
  MOV  Frac, AL
  POP  SI
  POP  DI
  POP  CX
  POP  BX
  POP  ES
  {A SECOND EOI FOR THE SLAVE PIC, NEW IN v1.51 AND A
    CONSEQUENCE OF THE IRQ BECOMING CONFIGURABLE. v1.31b is hard-wired to IRQ 4
    and sends one EOI to the master; with `/irq:` able to name 8..15 the slave
    controller has to be acknowledged first, or the second interrupt never
    arrives. `MOV AX,[0202]` loads the whole word and the test is on AL. }
  MOV  AX, ComIrq
  CMP  AL, 8
  JB   @@Master          { master alone for 0..7                }
  MOV  AL, 20h
  OUT  0A0h, AL          { EOI to the slave                     }
@@Master:
  MOV  AL, 20h
  OUT  20h, AL           { EOI, late and on purpose             }
  POP  DX
  POP  DS
  POP  AX
  IRET
end;

{ --------------------------------------------------------------------------
slot +$1a, the probe. Returns 1, unconditionally.

  SLOT +$1a IS AN ERROR CODE, and zero is success -- 109c:0021 selects a
  driver only when the probe returns zero. So returning 1 unconditionally
  means this driver reports "cannot be used", every time.

  That reads as nonsense until you notice how a driver is actually chosen.
  Selection is by NAME out of the config file (1a17:0248) and by
  registration order, not by probing: 109c:0000 looks up the named driver
  and probes only that one. Nothing ever probes 'Silence' in the normal
  path, because it is reached by being the last thing registered rather than
  by passing a test.

  There is nothing here to detect in any case. The serial port addresses
  exist on every PC whether or not a UART answers, and a clock that produces
  no sound cannot fail in a way a caller could act on.

  THIS ROUTINE MISLED THIS RECONSTRUCTION ONCE. Returning 1 unconditionally
  looks like "always available" if you assume the slot is a boolean, and
  that reading survived two other producers agreeing with it. The consumer
  at 109c:0021 settles NOTHING -- its JNZ has a zero displacement. The
  producers settle it, and TRUE means present. See VTDriver.
  -------------------------------------------------------------------------- }
function Probe : Boolean; far;
begin
  Probe := True;
end;

{ --------------------------------------------------------------------------
slot +$1e, start the clock.

  Compiler output with Port[] for the register work.

  The UART sequence is the ordinary one and the order is forced by the chip:
  raise DLAB in the line control register to reach the divisor latch, write
  the divisor, drop DLAB to get the data registers back, then enable the
  transmit interrupt LAST so nothing fires before the port is configured.

  EVERY REGISTER IT TOUCHES IS SAVED FIRST -- modem control, line control,
  divisor, interrupt enable. A serial port may belong to a mouse or a modem,
  and Stop puts all four back.

  `Port[$3FC] := 8` sets OUT2, which on a PC is not a modem signal at all: it
  is what gates the UART's interrupt line through to the 8259. Without it the
  chip raises interrupts that never reach the controller.
  -------------------------------------------------------------------------- }
procedure Start(Rate : Word); far;
begin
  IsDmaDevice := True;
  Stereo      := False;
  DevBits     := 8;
  MixMethod   := 0;

  if OldVec <> nil then Exit;                     { already running }

  {`IRQState(ComIrq)`, WHERE v1.31b READS THE 8259 DIRECTLY.
    v1.31b tests `Port[$21] and $10` with the mask bit for IRQ 4 written in;
    once the IRQ is configurable that constant cannot be formed inline, so the
    work moves to Hardware's own routine, which already knew how to pick the
    controller and the bit. The same shape as the second EOI above: a feature
    turning an immediate into a call. }
  WasOn := IRQState(ComIrq);

  OldVec := SetIRQVector(ComIrq, @IrqHandler);
  EnableIRQ(ComIrq);

  SavedMCR := Port[ComPort + 4];                  { $3FC }
  SavedLCR := Port[ComPort + 3];                  { $3FB }

  Port[ComPort + 4] := 8;                         { OUT2 -- gate the IRQ }
  Port[ComPort + 3] := $83;                       { DLAB + 8N1 }

  { READ THE ORDER HERE BACKWARDS. The original evaluates the HIGH byte
    first -- IN from $3f9, SHL AX,8, MOV CX,AX, then IN from $3f8 and ADD --
    but Turbo Pascal 7 evaluates the RIGHT operand of a `+` first and stashes
    the left one in CX. Written the natural way round, `(Port[+1] shl 8) +
    Port[]`, it compiles to the two reads in the wrong order. Written like
    this it is byte-identical. Same value either way; see demovt/verify.py. }
  SavedDiv := Port[ComPort]
              + (Port[ComPort + 1] shl 8);

  Port[ComPort]     := Lo(Divisor);               { $60 }
  Port[ComPort + 1] := Hi(Divisor);               { $00 -> 1200 baud }
  Port[ComPort + 3] := $03;                       { 8N1, DLAB off }

  SavedIER := Port[ComPort + 1];                  { $3F9 }
  Port[ComPort + 1] := 0;
  Port[ComPort + 1] := 2;                         { transmit empty }
end;

{ --------------------------------------------------------------------------
slot +$26, "what rate can you manage?"

  Returns what it was given, like the GUS. Nothing is played, so any rate is
  one this driver can honour -- the answer costs nothing and keeps the core
  from having to special-case it.
  -------------------------------------------------------------------------- }
function AskRate(Want : Word) : Word; far;
begin
  AskRate := Want;
end;

{ --------------------------------------------------------------------------
 and 1065:010b -- slots +$22 and +$2e. Empty, as in 1084.
  -------------------------------------------------------------------------- }
procedure ChgHz(W : Word); far;
begin
end;

procedure DevPoll; far;
begin
end;

{ --------------------------------------------------------------------------
slot +$32, stop the clock and hand the port back.

  Compiler output. Everything Start saved is restored, in the order the chip
  needs: modem control, then DLAB up to reach the divisor, the divisor, then
  the original line control (which drops DLAB), then the interrupt enable.

  THE INTERRUPT MASK IS RESTORED CONDITIONALLY, the same care as 1723 takes:
  IRQ 4 is only masked again if it had been masked before. A serial mouse
  sharing that line keeps working.
  -------------------------------------------------------------------------- }
procedure Stop; far;
begin
  { A WRAPPED IF, NOT AN EARLY EXIT. The original tests the vector at
 and jumps over the whole body with a single `JZ +54`. An
    `if OldVec = nil then Exit` compiles instead to `JNZ +2 / JMP +54` --
    a conditional jump around an unconditional one, two bytes longer and
    the wrong shape. Same behaviour; only this form reproduces the bytes. }
  if OldVec <> nil then                           { never started }
  begin
    Port[ComPort + 4] := Lo(SavedMCR);
    Port[ComPort + 3] := $80;                     { DLAB, to reach the divisor }
    Port[ComPort]     := Lo(SavedDiv);
    Port[ComPort + 1] := Hi(SavedDiv);
    Port[ComPort + 3] := Lo(SavedLCR);            { drops DLAB }
    Port[ComPort + 1] := 0;
    Port[ComPort + 1] := Lo(SavedIER);

    SetIRQVector(ComIrq, OldVec);
    OldVec := nil;

    { `not WasOn`, AND THE SENSE FLIPPED WITH THE SOURCE OF THE VALUE.
      v1.31b tested the 8259 mask bit directly, so its flag meant "was
      MASKED" and the IRQ was disabled again when it had been. v1.51 takes
      the flag from Hardware.IRQState, which answers the opposite question --
      "is it getting through" -- so restoring the previous state disables the
      IRQ when it was NOT. 115e:01ba is `JNE` over the call where v1.31b has
      `JE` into it: one byte, and the variable's NAME had to change with it. }
    if not WasOn then DisableIRQ(ComIrq)
  end
end;

{ --------------------------------------------------------------------------
fill in the record and hand it to the player core.

  The same shape as 1084:0101, eight far addresses into DS:$0034..DS:$0053,
  which is DS:$001e + $16 .. + $35. That is the second independent
  confirmation of the driver layout.

  SLOT +$2A IS THE ONE TO NOTICE. It is set to 1a17:1008 -- the CORE's shared
  poll -- rather than to anything here. The GUS supplies its own because the
  card plays by itself; this driver has no hardware to feed, so the core's
  general implementation does the work and the output goes nowhere.

  REGISTRATION ORDER DECIDES THE DEFAULT. 1a17:02ba pushes onto the front of
  the list but only selects when nothing is selected, so the FIRST driver to
  register wins -- and 1084 registers before this one. 'Silence' is therefore
  the last resort, which is exactly what it should be.
  -------------------------------------------------------------------------- }
begin
  Driver.Name            := @DevName;
  Driver.Autodetect      := @Probe;
  Driver.InitRut         := @Start;
  Driver.ChgHzProc       := @ChgHz;
  Driver.GetRealFreqProc := @AskRate;
  Driver.TimerHandler    := @SoundDevices.SharedPoll;
  Driver.PollRut         := @DevPoll;
  Driver.EndRut          := @Stop;

  SoundDevices.InitDevice(@Driver)
end.
