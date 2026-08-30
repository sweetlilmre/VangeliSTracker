{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  A SOUND DRIVER THAT MAKES NO SOUND. Its name is in the driver record at
 seven characters: 'Silence'.

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

  ITS POLL IS NOT ITS OWN. Register below puts the player core's SHARED poll
  in the timer slot, not anything in this unit -- so the core still does all
  its mixing work on schedule and there is simply nowhere for the result to
  go. Compare DevGus, which supplies its own poll because the card plays for
  itself.

  WHY HAVE IT AT ALL. A machine with no sound card, or one whose card is not
  recognised, still has to run the demo: the music has to advance so the
  semaphores fire and the visuals stay on their marks. This driver is what
  makes that an ordinary case rather than an error path, and it is why the
  driver chain ends with something that always succeeds.

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


  { **COM2 IN v1.51, COM1 IN 1.31b.** DGROUP +$0200 holds `f8 02` and +$0202 holds
    `03 00`. Two bytes, and no instruction anywhere names either value -- both are
    initialisers a command-line switch overwrites, so only the image says what the
    default is. }
  ComPort : Word    = $2F8;   { COM2 by default }
  ComIrq  : Word    = 3;

  Frac    : Byte    = 0;      { the 5-in-12 accumulator }
  OldVec  : Pointer = nil;    { the displaced INT 0Ch vector }


  { DMA IS **TRUE** ON A DRIVER THAT PLAYS NOTHING, which looks wrong and is
    not. The mixer gates its work on `IsDmaDevice AND (TickSnapshot = Ticks)`,
    so a device that only paces the tick wants that gate active. Claiming DMA
    is how it gets it.}
  Driver : TSoundDevice = ( DevID : 'Silence'; DMA : True );





implementation

uses
  Hardware, SoundDevices;

const
  Divisor  = $0060;      { 115200/96 = 1200 baud }
  AddPer   = 5;          { the accumulator step  }
  CarryAt  = 12;         { ... and its modulus   }

var

  SavedMCR, SavedLCR, SavedDiv, SavedIER : Word;   { .. $0e34 }
  { **STALE, AND UNANCHORED.** This unit links at position 4 and VTCmd at 2, so
    this variable must sit above VTCmd's $0ef6. It does not. The claim is
    consistent with nothing else in the file -- it is the only variable here with
    an address -- and no instrument in the kit can reach it: a variable is absent
    from the image, and this one is not public, so the linker map is silent too.
    Left as it stands and marked, rather than replaced with a guess. }
  WasOn  : Boolean;     { STALE }



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
  { A SECOND EOI FOR THE SLAVE PIC, NEW IN v1.51 AND A
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

  IT ALWAYS SAYS YES, and there is nothing here to detect. A driver's probe
  answers "is my hardware present?"; this one has no hardware, and a clock
  that produces no sound cannot fail in a way a caller could act on.

  IT IS ALSO NEVER ASKED, in the normal path. A driver is chosen by NAME out
  of the config file and by registration order, not by probing -- the selector
  looks up the named driver and probes only that one. 'Silence' is reached by
  being the last thing registered, not by passing a test.}
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

  { `IRQState(ComIrq)`, WHERE v1.31b READS THE 8259 DIRECTLY.
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
  Change the sample rate, and poll the device: BOTH DO NOTHING. A driver that
  plays no sound has no rate to change, and its polling is the core's shared
  one rather than anything here. The slots exist because the record has them.}
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


    if not WasOn then DisableIRQ(ComIrq)
  end
end;

{ --------------------------------------------------------------------------
fill in the record and hand it to the player core.}
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
