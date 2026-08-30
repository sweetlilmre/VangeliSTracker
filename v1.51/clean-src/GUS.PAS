{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Segment 1723 -- the Gravis UltraSound hardware layer. 2752 bytes, 24 framed
  routines and six frameless ones the prologue scanner cannot see.

  Every port write to the card happens here. 1084 is the DRIVER -- the record
  of eight entry points 1a17 walks -- and it calls into this unit for anything
  that touches hardware.

  THE THING WORTH KNOWING BEFORE READING ANY OF IT. Starting a voice does not
  program the card. `TriggerVoice` writes the voice's addresses into tables in
  the data segment, raises an active flag, and installs `RestartChannels` as
  the TIMER 1 callback. The next timer tick sweeps those flags, builds a
  command list, and blasts it at the GF1 in one loop.

  So voice changes are DEFERRED AND BATCHED. The caller never touches a port,
  and the card sees one burst per tick instead of scattered writes from
  whatever context happened to be running. That is why 12ba keeps a ring of
  voice commands rather than issuing them as it finds them, and it is the
  single decision that shapes the whole GUS path.

  This file claimed the opposite for a long time -- that Port[] always
  matched -- and it was wrong in both directions. See docs/06-transcription.md.

  THE NAMES ARE THE RELEASE'S, NOT GUESSES. Every routine and global here is
  named after its counterpart in VangeliSTracker 1.39b's `LIB/GUS.PAS`, which
  is a later version of this same unit; the pairings were each confirmed by
  reading the two bodies against one another. Only `SetMixControl`, `CmdList`
  and `IrqCode` keep invented names -- 1.39b factored the last two out into
  `Hardware` and has no counterpart for the first.

  Two of the release's names correct a misleading one. `ProbeUltrasound` does
  not probe DRAM -- it writes and reads back voice registers $02/$03, and was
  called `ProbeDram` here. `GUSStopTimer1` stops timer 1 specifically, not both
  timers as `StopTimers` implied; 1.31 has no counterpart to `GUSStopTimer2`.

  Names remain provisional in ONE respect: the original carries no debug
  information, so nothing proves 1.31 spelled them as 1.39b does.
  =========================================================================== }

{$G+}   { SHR AX,imm and SHL AX,imm -- 186 instructions }

unit GUS;

interface

const
  MaxVoice = 31;  { the card has 32 voices, numbered from 0 }

{ **THE GF1's REGISTER NUMBERS, UNDER THE RELEASE'S OWN NAMES.** Every one of the
  53 register accesses in this unit was written as a bare hex number, because a
  bare hex number is what the instruction holds. `LIB/GUS.PAS` names all
  twenty-two, and the numbers agree exactly -- so these are the author's names for
  the author's constants, not a vocabulary invented here.

  THEY EMIT NOTHING. An untyped constant in Turbo Pascal is a compile-time value,
  so naming 53 call sites moves no byte and the rebuild proves it. What changes is
  that `SetGusRegister8(grTimerControl, ...)` now says which register it selects.

  The first sixteen are per-voice and the last six are global to the card, which
  is why the numbers fall in two runs with a gap between them. }
const
  grVoiceControl     = $00;   { the voice on/off and mode bits }
  grFreqControl      = $01;
  grStartAddrHigh    = $02;
  grStartAddrLow     = $03;
  grEndAddrHigh      = $04;
  grEndAddrLow       = $05;
  grRampRate         = $06;
  grRampStart        = $07;
  grRampEnd          = $08;
  grCurrentVol       = $09;
  grCurrentAddrHigh  = $0A;
  grCurrentAddrLow   = $0B;
  grPanPosition      = $0C;
  grVolumeControl    = $0D;   { the ramp on/off and direction bits }
  grActiveVoices     = $0E;
  grVoiceIRQ         = $0F;
  grDRAMLowIO        = $43;   { the low 16 bits of a DRAM address }
  grDRAMHighIO       = $44;   { and its high bits }
  grTimerControl     = $45;
  grTimer1Count      = $46;
  grTimer2Count      = $47;
  grReset            = $4C;   { 0 holds the GF1 in reset, 1 releases it }


{ THIS UNIT'S INTERFACE DGROUP BLOCK, $0582..$0591 -- TYPED CONSTANTS, not vars, and
  the linked image is what says so. As plain `var`s none of these sixteen bytes existed:
  a `var` is reserved space the linker never writes.

  ALL FOUR VALUES ARE IN THE IMAGE AND ALL FOUR ARE THE RELEASE'S DEFAULTS, which is
  four independent agreements in one block -- `LIB/GUS.PAS` opens with exactly
  `GUSPort = $FFFF`, `GUSIrq = 11`, `GUSChannels = 32`, `GUSDivisor = 19293`, and the
  original holds `ff ff`, `0b 00`, `20`, `5d 4b` at those addresses. $0587 is TP
  word-aligning GUSDivisor after the Byte, the same rule as everywhere else here.

  `GUSChannels` IS 32 EVEN THOUGH THE PLAYER USES 8. It is the card's voice count, not
  the module's -- `MaxVoice` is 31 below for the same reason -- and it is 12ba's
  `MaxChannels` that is 8. Two different numbers that a reader will want to conflate. }
const

  GUSPort         : Word    = $FFFF;

  GUSIrq          : Word    = 11;
  GUSChannels     : Byte    = 32;      { the CARD's voices; pad $0587 }
  GUSDivisor      : Word    = 19293;
  GUSTimer1RutPtr : Pointer = nil;
  GUSTimer2RutPtr : Pointer = nil;


procedure DumpToUltrasound(var Src; Count : Word;
                     DramAt : LongInt; Signed : Word); far;
procedure GUSInitTimer1(Count : Byte); far;
procedure GUSInitTimer2(Count : Byte); far;
procedure GUSStopTimer1; far;
procedure InitGusIRQ; far;
procedure DoneGusIRQ; far;
procedure StartUltrasound; far;
function  DetectUltrasound : Boolean; far;
procedure RestartChannels; far;
procedure SetGusChannels(N : Byte); far;

{ The address parameters are StartA/LoopA/EndA rather than the release's
  VoiceStart/LoopStart/VoiceEnd because LastVoiceStart, LastLoopStart and
  LastVoiceEnd are the per-voice TABLES this writes into, and 1.39b's parameter
  names would read as near-duplicates of them. }
procedure TriggerVoice(Voice, Vol : Byte; Freq : LongInt; Pan : Byte;
                       StartA, LoopA, EndA : LongInt); far;
procedure ChangeVoiceParams(Channel, Vol : Byte; Freq : LongInt;
                            Panning : Byte); far;

implementation

uses
  Hardware;

{ $0592..$0599 -- TYPED CONSTANTS for the same reason, and their addresses are what
  fixes their position: they have to sit BELOW `IrqCode` at $059a, and an
  implementation declaration comes after every interface one, so this is the only place
  they can be. The arithmetic closes with nothing over -- $0592 + 1 + 1 + 4 + 1 + 1 is
  $059a, and $059a + 16 is $05aa, which is `GUSPorts`. Three consecutive blocks landing
  on two addresses that were already known. All five hold zero. }
const
  TimerControl  : Byte    = 0;    { shadow of GF1 register $45      }
  TimerMask     : Byte    = 0;    { shadow of the timer control     }
  OldIrqHandler : Pointer = nil;
  OldIrqState   : Boolean = False;{ enabled before InitGusIRQ?      }
  GusIRQInited  : Boolean = False;

  { the GF1 encodes its interrupt in three bits rather than
    taking the number, so the number has to be translated. Zero means the
    card cannot be wired to that line at all. }
  IrqCode : array[0..15] of Byte =
    (0, 0, 1, 3, 0, 2, 0, 4, 0, 0, 0, 5, 6, 0, 0, 7);

  { the twelve addresses a GUS can be jumpered to.
    DetectUltrasound walks these in order when GUSPort has not been
    configured, so the first one that answers wins, not the lowest. }
  GUSPorts : array[1..12] of Word =
    ($0220, $0240, $0200, $0210, $0230, $0250,
     $0260, $0270, $0280, $0290, $02A0, $02B0);

var

  { **THE SEVEN ADDRESSES BELOW ARE STALE, AND NOTHING HERE CAN CORRECT THEM.**
    They are consistent with each other -- $371a, +128, +128, +128, +32, +128,
    +32 lands on every one of them -- and consistent is all they are.

    THEY ARE ALSO UNANCHORED, WHICH IS RARE. A `var` holds no bytes in the image,
    so no comparison sees it; and none of these is public, so the linker map does
    not name one either. Of this tree's 289 address claims, nine are in that
    position and seven of them are here.

    THE LINK ORDER IS WHAT CATCHES THEM. Every unit's variables sit above the
    variables of every unit linked before it -- eight anchored units agree, with
    no exception:

        DemoVT $0d16   VTCmd $0ef6   PlayMod $12b8   VTCtrl $461a
        VTNotes $4920  Heaps $5d08   VTShell $5d38   SoundDevices $665c

    GUS links at position 19, between VTNotes at 17 and Heaps at 20, so its
    variables must start above $4920 and end below $5d08. $371a is impossible.

    WHAT THE TRUE ADDRESSES ARE IS STILL OPEN. Computing them needs every
    intervening unit's variable sizes, and SongElements alone has nine
    declarations this transcription cannot size. The addresses are left as they
    stand rather than replaced with a guess -- a wrong number that is admitted is
    worth more than a wrong number that is not. }
  LastVoiceStart : array[0..MaxVoice] of LongInt;  { STALE, see above }
  LastLoopStart  : array[0..MaxVoice] of LongInt;  { filled with $FE }
  LastVoiceEnd   : array[0..MaxVoice] of LongInt;  { filled with $FF }
  LastVolumes    : array[0..MaxVoice] of Byte;     { filled with $FF }
  LastFreqs      : array[0..MaxVoice] of LongInt;  { filled with $FF }
  LastPans       : array[0..MaxVoice] of Byte;     { filled with $7F }
  VoicesChanged  : array[0..MaxVoice] of Byte;     { filled with $00 }



{ --------------------------------------------------------------------------
the GF1 register interface.

  Hand assembler -- see the note on the five routines below.

  base+$102  voice select        base+$103  register select
  base+$104  data, word          base+$105  data, high byte

  THE READ CONVENTION IS THE ONE DETAIL TO KEEP. A GF1 register below $40 is
  read by setting bit 7 of its NUMBER when selecting it -- the register file
  is write-only below $40 unless you ask for the read alias. Registers $40 and
  up are readable as they stand, which is why the test is `< $40` and not a
  blanket OR.
  -------------------------------------------------------------------------- }
{ **THE GF1's PORT MAP, WHICH IS WHAT ALL FIVE ROUTINES BELOW ARE DOING.**
  The card answers on a base address -- GUSPort, jumpered, one of twelve -- and
  everything is reached at a fixed offset from it:

      base+$102   voice select     which of the 32 voices the next access means
      base+$103   register select  which of the GF1's registers
      base+$104   data, 16-bit     the register's value as a word
      base+$105   data, 8-bit      the same register's value as a byte

  So writing to a register is always two steps: say which register, then send
  the value. There is no single instruction that does both, and no way to
  address a register directly. THAT is why the register numbers named at the top
  of this unit -- grVoiceControl and the rest -- are values written to $103
  rather than addresses of anything.

  And it is why voice-indexed work looks the way it does: SetGusVoice writes
  $102 once, and every register access after it applies to that voice until the
  next one. A caller that forgets to select a voice will read and write another
  voice's registers with no error of any kind.

  The 8-bit and 16-bit data ports are the SAME register seen two ways, which is
  why SetGusRegister8 and SetGusRegister16 differ only in which of $104 and $105
  they finish on -- INC DX for the word port, ADD DX,2 for the byte port.

  **AND THIS IS NOT THE ONLY WINDOW ON THE CARD.** base+8 and base+9 are a
  second select-and-data pair reaching a different set of registers, the GF1's
  interrupt control, and the timer routines further down use it. A reader who
  takes the four ports above for the whole story will meet those two lines and
  think the code is wrong. It is not; see the note above GUSInitTimer1.

  ----------------------------------------------------------------------------
  THESE FIVE ARE ASSEMBLER, AND THE REASON IS WORTH RECORDING.

  Same length, different registers -- so this was invisible to every check
  that looked at code size. The original keeps the port in DX throughout and
  walks it with ADD DX,2 and INC DX rather than recomputing, which is what an
  assembler block does and what Pascal cannot express.

  This corrects a rule recorded in docs/06-transcription.md: port code is
  faithfully Pascal only when the port number is CONSTANT. }

{ Choose which voice the following register accesses apply to. It stays chosen
  until this is called again -- see the port map above. }
procedure SetGusVoice(N : Byte); assembler;
asm
        MOV     DX,GUSPort
        ADD     DX,$102     { the voice-select register }
        MOV     AL,N
        OUT     DX,AL
end;

{ The read alias: registers below $40 are read at register+$80. }
function GetGusRegister8(Reg : Byte) : Byte; assembler;
asm
        MOV     DX,GUSPort
        ADD     DX,$103     { the register-select port }
        MOV     AL,Reg
        CMP     AL,$40
        JNB     @@Hi        { already an alias }
        ADD     AL,$80
@@Hi:
        OUT     DX,AL
        ADD     DX,2   { -> the data port, $105 }
        IN      AL,DX
end;

{ No alias on the write path -- writes use the register number as given. }
procedure SetGusRegister8(Reg, Val : Byte); assembler;
asm
        MOV     DX,GUSPort
        ADD     DX,$103
        MOV     AL,Reg      { the FIRST parameter }
        OUT     DX,AL
        ADD     DX,2
        MOV     AL,Val
        OUT     DX,AL
end;

function GetGusRegister16(Reg : Byte) : Word; assembler;
asm
        MOV     DX,GUSPort
        ADD     DX,$103
        MOV     AL,Reg
        CMP     AL,$40
        JNB     @@Hi
        ADD     AL,$80
@@Hi:
        OUT     DX,AL
        INC     DX     { -> $104, the 16-bit port }
        IN      AX,DX  { a WORD read }
end;

procedure SetGusRegister16(Reg : Byte; Val : Word); assembler;
asm
        MOV     DX,GUSPort
        ADD     DX,$103
        MOV     AL,Reg
        OUT     DX,AL
        INC     DX
        MOV     AX,Val
        OUT     DX,AX
end;

{ --------------------------------------------------------------------------
settling delay. FRAMELESS: no parameters, no frame, a bare RET.

  HAND ASSEMBLER, verbatim. Seven reads of the base port with every result
  thrown away. The GF1 needs time between register accesses and this is how
  the original buys it -- not a counted loop, because the delay wanted is a
  number of ISA bus cycles, and an IN is the only thing that reliably costs
  one whatever the CPU speed. A `for` loop would get faster with the machine;
  this does not.
  -------------------------------------------------------------------------- }
procedure GusDelay; assembler;
asm
  MOV  DX, GUSPort
  IN   AL, DX
  IN   AL, DX
  IN   AL, DX
  IN   AL, DX
  IN   AL, DX
  IN   AL, DX
  IN   AL, DX
end;

{ --------------------------------------------------------------------------
copy a sample into the card's own DRAM.

  HAND ASSEMBLER, verbatim, and it has to be: it walks the source with LODSB
  through a reloaded DS, which Pascal cannot express.

  Registers $43 and $44 are the DRAM address, low word and high byte, and
  base+$107 is the data port.

  THE SIGN FLIP IS BRANCHLESS. GUS DRAM holds unsigned samples and a module
  holds signed ones, so each byte needs XOR $80 -- but only when the caller
  says the source is signed. Rather than branch per byte, the flag is turned
  into a MASK once, before the loop:

      CMP BH,1  /  SBB BH,BH  /  SHL BH,7      ->  $80 when BH was 0, else 0

  and every byte is then XORed with it unconditionally. Three instructions of
  setup to remove a test from a loop that runs once per sample byte.

  THE ADDRESS HIGH BYTE IS ONLY REWRITTEN WHEN THE LOW WORD WRAPS. `INC DI /
  JNZ` costs nothing on the 65535 iterations where it does not.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      SetGusRegister8(grDRAMHighIO, DramAt shr 16);  SetGusRegister16(grDRAMLowIO, DramAt and $FFFF);
      for I := 1 to Count do
      begin
        SetGusRegister16(grDRAMLowIO, DI);  Port[GUSPort+$107] := Src^[I] xor Mask;
        Inc(DI);  if DI = 0 then begin Inc(BL); SetGusRegister8(grDRAMHighIO, BL) end
      end
  -------------------------------------------------------------------------- }
{ PASCAL FIRST, THEN ASSEMBLER. The routine opens with two ordinary calls --
 is compiler output, including a runtime helper at
 for the 32-bit shift -- and only the transfer loop is hand
  written. Declared `assembler`, the whole prologue vanishes and the unit
  diverges at the first byte after the frame.}
procedure DumpToUltrasound(var Src; Count : Word;
                     DramAt : LongInt; Signed : Word);
begin
  SetGusRegister8(grDRAMHighIO, DramAt shr 16);
  SetGusRegister16(grDRAMLowIO, DramAt and $FFFF);
  asm
  PUSH DS          { LODSB will take DS away              }
  MOV  CX, Count
  LES  DI, DramAt  { the DRAM address, low word in DI     }
  MOV  BX, ES      { ... high half in BL                  }
  MOV  BH, BYTE PTR Signed
  CMP  BH, 1        { carry when the caller said 0         }
  SBB  BH, BH       { $FF when signed, else $00            }
  SHL  BH, 7        { ... becomes the $80 XOR mask         }
  MOV  DX, GUSPort
  LDS  SI, Src
  ADD  DX, 0103h    { the register select port             }
@@Byte:
  MOV  AL, 43h  { DRAM address, low word               }
  OUT  DX, AL
  INC  DX       { base+$104                            }
  MOV  AX, DI
  OUT  DX, AX
  ADD  DX, 3    { base+$107, the DRAM data port        }
  LODSB
  XOR  AL, BH   { signed -> unsigned, or nothing       }
  OUT  DX, AL
  INC  DI
  JNZ  @@Same   { the low word did not wrap            }
  INC  BL
  SUB  DX, 4    { back to base+$103                    }
  MOV  AL, 44h  { DRAM address, high byte              }
  OUT  DX, AL
  ADD  DX, 2    { base+$105                            }
  MOV  AL, BL
  OUT  DX, AL
  ADD  DX, 2
@@Same:
  SUB  DX, 4   { base+$103, ready for the next        }
  LOOP @@Byte
  POP  DS
  end          { LEAVE / RETF 0Ch, from Pascal        }
end;

{ --------------------------------------------------------------------------
the two GF1 timers.

  Compiler output. Registers $46 and $47 hold the counts, $45 is the timer
  control, and base+8 / base+9 are the AdLib-compatible pair that gates the
  interrupt.}
{ **THE TWO TIMERS DO DIFFERENT JOBS AND THE ROUTINES ARE OTHERWISE IDENTICAL.**
  Timer 1 is the one TriggerVoice arms: it fires once, shortly after a note is
  set up, and RestartChannels starts the voices on it. Timer 2 drives whatever
  GUSTimer2RutPtr holds. Each has its own enable bit in the control register
  ($04 and $08) and its own mask bit in the interrupt mask ($01 and $02), and
  the two routines below differ in nothing else.

  **AND THERE IS A SECOND REGISTER WINDOW, WHICH THE PORT MAP ABOVE DOES NOT
  COVER.** The last two lines write base+8 and base+9 rather than base+$103 and
  base+$105. That is a different pair of ports reaching a different set of
  registers -- the GF1's interrupt control -- selected the same way: say which
  register at +8, write the value at +9. Register 4 there is the timer interrupt
  mask.

  So a reader who has learned the $103/$105 pattern will meet these two lines
  and think something is wrong. Nothing is: the chip simply has two windows, and
  the timers need both. }
procedure GUSInitTimer1(Count : Byte);
begin
  SetGusRegister8(grTimer1Count, Count);
  TimerControl := TimerControl or $04;
  SetGusRegister8(grTimerControl, TimerControl);
  TimerMask := TimerMask or $01;        { timer 1's mask bit }
  Port[GUSPort + 8] := 4;               { select register 4 in the
                                          interrupt window -- see above }
  Port[GUSPort + 9] := TimerMask;       { and write it }
end;

procedure GUSInitTimer2(Count : Byte);
begin
  SetGusRegister8(grTimer2Count, Count);
  TimerControl := TimerControl or $08;
  SetGusRegister8(grTimerControl, TimerControl);
  TimerMask := TimerMask or $02;
  Port[GUSPort + 8] := 4;
  Port[GUSPort + 9] := TimerMask;
end;

procedure GUSStopTimer1;
begin
  TimerControl := TimerControl and $FB;
  SetGusRegister8(grTimerControl, TimerControl);
  TimerMask := TimerMask and $FE;
  Port[GUSPort + 8] := 4;
  Port[GUSPort + 9] := TimerMask;
end;

{ --------------------------------------------------------------------------
 -- a timer expired.

  Compiler output, near, private. Clearing the enable bit and setting it
  straight back is what acknowledges the timer to the GF1; the shadow is not
  disturbed, so the two writes are `TimerControl and mask` followed by plain
  `TimerControl`.

  The callback is only called if the far pointer is non-nil, and the test is
  on BOTH halves -- a segment of zero with a non-zero offset would still be
  called. That is deliberate enough to preserve.}
procedure ServiceTimer1;
begin
  SetGusRegister8(grTimerControl, TimerControl and $FB);
  SetGusRegister8(grTimerControl, TimerControl);
  if GUSTimer1RutPtr <> nil then
    asm
      CALL DWORD PTR GUSTimer1RutPtr
    end;
end;

{ **ACKNOWLEDGE BY CLEARING THE BIT AND PUTTING IT BACK.** The GF1 holds its
  timer interrupt asserted until the enable bit is taken away, so the two writes
  below are not redundant: the first clears bit 3 to drop the interrupt, and the
  second restores the shadow -- which has bit 3 still set -- to re-arm it.
  Writing the shadow twice would do nothing at all.

  Reading the register to clear it is not an option; it is write-only, which is
  why the shadow exists. See the note above the timer routines. }
procedure ServiceTimer2;
begin
  SetGusRegister8(grTimerControl, TimerControl and $F7);  { drop it }
  SetGusRegister8(grTimerControl, TimerControl);          { re-arm }
  if GUSTimer2RutPtr <> nil then
    asm
      CALL DWORD PTR GUSTimer2RutPtr
    end;
end;

{ --------------------------------------------------------------------------
the card's interrupt handler. FRAMELESS, ends in IRET.

  HAND ASSEMBLER, verbatim. It cannot be a Pascal `interrupt` procedure: it
  masks its own line at the 8259, re-enables interrupts in the middle, and
  loops on the card's status register.

  THE ORDER IS THE WHOLE POINT.

  EOI FIRST, before any work. The controller is released immediately, so a
  different device's interrupt is not held off for however long the callbacks
  take. The slave gets one too when the line is above 7.

  THEN MASK OUR OWN LINE. That is what makes the `STI` below safe: other
  devices can interrupt, this one cannot, so the handler cannot re-enter.
  Doing it with a mask rather than by leaving interrupts off is what keeps
  the rest of the machine responsive.

  THEN LOOP ON THE STATUS REGISTER until it reports nothing outstanding. A
  GF1 can raise a second timer while the first is being serviced; a handler
  that serviced one source and returned would leave the card asserting its
  line forever, and the machine would lock.

  UNMASK LAST, and read register $0F on the way out to clear anything the
  card latched while we were inside.
  -------------------------------------------------------------------------- }
procedure GUSIrqHandler; assembler;
asm
  CLI
  PUSHA
  PUSH ES
  PUSH DS
  MOV  AX, SEG @DATA        { was MOV AX,1CAAh                     }
  MOV  DS, AX
  MOV  AL, 20h              { non-specific EOI                     }
  OUT  20h, AL              { release the master straight away     }
  MOV  AH, BYTE PTR GUSIrq
  CMP  AH, 8
  JC   @@Master
  OUT  0A0h, AL             { the slave as well                    }
@@Master:
  MOV  AL, AH
  XOR  AH, AH
  PUSH AX
  CALL DisableIRQ  { keep ourselves out      }
@@Again:
  CLI
  MOV  DX, GUSPort
  ADD  DX, 6          { the IRQ status register              }
  IN   AL, DX
  TEST AL, 0Ch        { either timer?                        }
  JZ   @@Done
  STI                 { callbacks run with interrupts on     }
  TEST AL, 4
  JZ   @@NotOne
  PUSH AX
  CALL ServiceTimer1
  POP  AX
@@NotOne:
  TEST AL, 8
  JZ   @@NotTwo
  PUSH AX
  CALL ServiceTimer2
  POP  AX
@@NotTwo:
  JMP  @@Again  { until the card is quiet              }
@@Done:
  MOV  AL, BYTE PTR GUSIrq
  XOR  AH, AH
  PUSH AX
  CALL EnableIRQ
  PUSH 000Fh
  CALL GetGusRegister8      { clear anything latched               }
  POP  DS
  POP  ES
  POPA
  IRET
end;

{ --------------------------------------------------------------------------
take the interrupt line, and give it back.

  THE STATE IS RESTORED PROPERLY, which is rarer than it should be. InitGusIRQ
  records whether the line was ALREADY enabled; DoneGusIRQ only disables it
  again if it was not. A driver that blindly masked on the way out would
  silence whatever else had been sharing that line.
  -------------------------------------------------------------------------- }
procedure InitGusIRQ;
begin
  if GusIRQInited then Exit;
  GusIRQInited := True;
  OldIrqState  := IRQState(GUSIrq);
  OldIrqHandler := SetIRQVector(GUSIrq, @GUSIrqHandler);
  EnableIRQ(GUSIrq);
  GetGusRegister8(grVoiceIRQ);                                   { clear status }
end;

procedure DoneGusIRQ;
begin
  if not GusIRQInited then Exit;
  GusIRQInited := False;
  if not OldIrqState then DisableIRQ(GUSIrq);  { only if we turned it on }
  SetIRQVector(GUSIrq, OldIrqHandler);
end;

{ --------------------------------------------------------------------------
mix control and the IRQ latch. Near, private.

  Compiler output, held under CLI with the flags saved and restored rather
  than blindly re-enabled -- so it is safe to call from inside a handler.

  The GF1 latches its interrupt assignment through a strobe at base+$00 and
  base+$0B, and the value has to be written TWICE: the first write arms the
  latch, the second commits it. That is the card's documented sequence, not a
  belt-and-braces repeat.

  `IrqCode[GUSIrq] + $40` is the translation from a PC interrupt number to the
  three-bit field the card wants, with bit 6 set to say "the same line for
  both channels".
  -------------------------------------------------------------------------- }
{ `Port[GUSPort]`, NOT `Port[GUSPort + $00]`. Writing the zero makes Turbo
  Pascal evaluate an address expression -- MOV AX,[GUSPort] / ADD AX,0 /
  MOV DX,AX -- where the original loads the port straight into DX with
  MOV DX,[GUSPort] and loads the VALUE first. Three bytes and a different
  instruction order, from a `+ 0` that reads as harmless. }
procedure SetMixControl;
var
  V : Byte;
begin
  V := IrqCode[GUSIrq] + $40;
  asm
    PUSHF  { keep the caller's interrupt state    }
    CLI
  end;
  Port[GUSPort + $0F] := 5;
  Port[GUSPort] := $0B;
  Port[GUSPort + $0B] := 0;
  Port[GUSPort + $0F] := 0;
  Port[GUSPort] := $4B;
  Port[GUSPort + $0B] := V;   { arm         }
  Port[GUSPort] := $4B;
  Port[GUSPort + $0B] := V;   { commit      }
  Port[GUSPort + $102] := 0;
  Port[GUSPort] := $0C;
  Port[GUSPort + $102] := 0;
  asm
    POPF
  end;
end;

{ --------------------------------------------------------------------------
reset the card and every voice.

  Compiler output. The seven FillChar calls are what fix the table sizes: two
  of $20 bytes and five of $80, over 32 voices.

  THE FILL VALUES ARE NOT ALL ZERO, and that is the interesting part.
  Addresses are filled with $FF and $FE so that "no address" is a value no
  real address can be; the pan table is filled with $7F, dead centre; only
  the active flags start at zero. A voice that has never been programmed is
  therefore inactive AND centred AND pointing nowhere, and nothing has to
  special-case the first use.

  Register $4C is the reset register: 0 holds the GF1 in reset, 1 releases
  it, 7 releases it with the DAC and the IRQ enabled. The delay between is
  the settling wait, and it is why `GusDelay` exists.
  -------------------------------------------------------------------------- }
procedure StartUltrasound;
var
  V : Word;
begin
  FillChar(LastVoiceStart,  $80, $FF);
  FillChar(LastLoopStart, $80, $FE);
  FillChar(LastVoiceEnd,  $80, $FF);
  FillChar(LastVolumes,    $20, $FF);
  FillChar(LastFreqs,    $80, $FF);
  FillChar(LastPans,     $20, $7F);     { dead centre }
  FillChar(VoicesChanged,   $20, $00);

  SetMixControl;


  asm
    MOV  DX, GUSPort
    MOV  AL, 0Bh      { [1.39b] "Turn off output, to avoid   }
                      {             clicks." -- the reason for the whole }
                      {             port write, and not in the bytes     }
    OUT  DX, AL
  end;
  SetGusRegister8(grReset, 0);    { [1.39b] "Reset the GUS card." }
  GusDelay;
  SetGusRegister8(grReset, 1);    { [1.39b] "DAC turned off."     }
  SetGusRegister8(grActiveVoices, $DF);  { 32 voices     }
  SetGusRegister16(grDRAMLowIO, 0);
  SetGusRegister8(grDRAMHighIO, 0);

  { silence every voice before anything else can start one.}
  for V := 0 to MaxVoice do
  begin
    SetGusVoice(V);
    SetGusRegister8(grVoiceControl, 3);  { stopped      }
    SetGusRegister8(grVolumeControl, 3);  { volume idle  }

    if GetGusRegister16(grCurrentVol) > $1800 then
    begin
      SetGusRegister8(grRampStart, $18);
      SetGusRegister8(grRampEnd, Hi(GetGusRegister16(grCurrentVol)));
      SetGusRegister8(grRampRate, $1F);                        { fastest ramp }
      SetGusRegister8(grVolumeControl, $40);
    end;
  end;  { CMP V,$1F }

  { **AND THE PORT WRITE THAT FOLLOWS IS THE OTHER HALF OF THE CLICK GUARD.**
    The release pairs them explicitly: 0Bh at the top is "[1.39b] Turn off
    output, to avoid clicks" and 0Ch at the bottom is "[1.39b] Turn on output".
    The card is silenced before the reset and unsilenced after it, so the
    transition itself is never audible. }
  SetGusRegister8(grReset, 7);  { [1.39b] "DAC turned on."  }
  asm                       { hand assembler, same as the $0B poke above:      }
    MOV  DX, GUSPort        { port first, then the value            }
    MOV  AL, 0Ch
    OUT  DX, AL
  end;
  SetGusChannels(GUSChannels);
end;

{ --------------------------------------------------------------------------
is there really a card at GUSPort? Near, private.

  Compiler output, under CLI throughout.

  TWO PATTERNS INTO TWO DIFFERENT VOICES, and both must read back. One value
  in one register would be satisfied by a bus that floats back whatever was
  last written -- which is exactly what an empty ISA address does. Two
  distinct values in two distinct voices cannot be faked that way.

  The read-back is masked with $1FFF because the register is thirteen bits
  wide and the top three read as noise.

  AND IT PUTS BOTH REGISTERS BACK on every exit path, so probing a card that
  is already playing does not disturb it. That matters here: DetectUltrasound
  below walks twelve candidate addresses, and eleven of them may belong to
  something else entirely.
  -------------------------------------------------------------------------- }
function ProbeUltrasound : Boolean;

label
  Fin;
var
  Save0, Save1 : Word;
begin
  ProbeUltrasound := False;
  asm CLI end;

  SetGusRegister8(grReset, 0);    { hold in reset }
  GusDelay;
  SetGusRegister8(grReset, 7);
  SetGusRegister8(grActiveVoices, $DF);

  SetGusVoice(0);
  Save0 := GetGusRegister16(grStartAddrHigh);
  SetGusRegister16(grStartAddrHigh, $16D8);

  SetGusVoice(1);
  Save1 := GetGusRegister16(grStartAddrHigh);
  SetGusRegister16(grStartAddrHigh, $0F83);

  SetGusVoice(0);
  if (GetGusRegister16(grStartAddrHigh) and $1FFF) <> $16D8 then goto Fin;
  SetGusVoice(1);
  if (GetGusRegister16(grStartAddrHigh) and $1FFF) <> $0F83 then goto Fin;
  ProbeUltrasound := True;
Fin:

  SetGusVoice(0);
  SetGusRegister16(grStartAddrHigh, Save0);
  SetGusVoice(1);
  SetGusRegister16(grStartAddrHigh, Save1);
  asm STI end;
end;

{ --------------------------------------------------------------------------
find a card.

  Compiler output. If GUSPort was configured, probe that and nothing else;
  otherwise walk the twelve jumper positions and take the first that answers.
  The candidate order is the table's, not numerical -- $0220 and $0240 are
  tried before $0200, presumably because they were the common settings.}
{ The 1.39b release has this as DetectUltrasound. It sets the result TRUE
  first and leaves by `Exit` the moment a port answers; only falling out of
  the search clears it. A `Found` local and a `repeat` were both wrong -- the
  result is assigned directly and the search is a FOR. }
function DetectUltrasound : Boolean;
var
  I : Word;
begin
  DetectUltrasound := True;

  if GUSPort = $FFFF then  { not configured }
  begin
    for I := 1 to 12 do
    begin
      GUSPort := GUSPorts[I];
      if ProbeUltrasound then Exit;
    end
  end
  else
    if ProbeUltrasound then Exit;

  DetectUltrasound := False;  { nothing answered }

end;

{ --------------------------------------------------------------------------
a byte address into the GF1's split form. Near, private.

  Compiler output.

      A := (A shl 9);   low := A and $FE00;   high := (A shr 16) and $1FFF

  The GF1 does not hold a DRAM address as a plain number. It splits it so the
  high register carries `DramAt shr 7` and the low register carries
  `(DramAt and $7F) shl 9` -- the low bits sit at the TOP of their word, which
  is what leaves room underneath for the fractional part a playing voice
  accumulates. Shifting the whole thing left nine and masking each half is
  the cheapest way to land both.
  -------------------------------------------------------------------------- }
procedure SwapGusAddress(var A : LongInt);
begin
  { ONE STATEMENT. The release's SwapGusAddress is
    `Addr := (Addr SHL 9) AND $1FFFFE00;` -- a single shift and a single
    32-bit mask, not a shift followed by a rebuild from two halves. }
  A := (A shl 9) and $1FFFFE00;
end;

{ --------------------------------------------------------------------------
set a voice's pan. Near, private.

  Compiler output. $FF means "leave it alone" and anything above $7F is
  clamped to $7F, so the caller can pass a don't-care without a separate
  flag. The stored value is compared against the table first and the write is
  skipped when nothing changed -- a pan write costs a register select and the
  card is slow.
  -------------------------------------------------------------------------- }
const

  VolumeTable : array[0..127] of Word = (
    $1800, $9DF0, $A5F0, $ACF0, $B1F0, $B570, $B8F0, $BC70,
    $BFF0, $C1B0, $C370, $C530, $C6F0, $C8B0, $CA70, $CC30,
    $CDF0, $CFB0, $D0B0, $D190, $D270, $D350, $D430, $D510,
    $D5F0, $D6D0, $D7B0, $D890, $D970, $DA50, $DB30, $DC10,
    $DCF0, $DDD0, $DEB0, $DF90, $E030, $E0A0, $E110, $E180,
    $E1F0, $E260, $E2D0, $E340, $E3B0, $E420, $E490, $E500,
    $E570, $E5E0, $E650, $E6C0, $E730, $E7A0, $E810, $E880,
    $E8F0, $E960, $E9D0, $EA40, $EAB0, $EB20, $EB90, $EC00,
    $EC70, $ECE0, $ED50, $EDC0, $EE30, $EEA0, $EF10, $EF80,
    $EFF0, $F030, $F060, $F0A0, $F0D0, $F110, $F140, $F180,
    $F1B0, $F1F0, $F220, $F260, $F290, $F2D0, $F300, $F340,
    $F370, $F3B0, $F3E0, $F420, $F450, $F490, $F4C0, $F500,
    $F530, $F570, $F5A0, $F5E0, $F610, $F650, $F680, $F6C0,
    $F6F0, $F730, $F760, $F7A0, $F7D0, $F810, $F840, $F880,
    $F8B0, $F8F0, $F920, $F960, $F990, $F9D0, $FA00, $FA40,
    $FA70, $FAB0, $FAE0, $FB20, $FB50, $FB90, $FBC0, $FC00
  );

{ --------------------------------------------------------------------------
set a voice's volume, ramping to it rather than jumping.

 is LastVolumes, not the mode table -- also misnamed here until now.

  It never jumps the volume. It reads where the ramp currently is, points the
  ramp at the new value from whichever end it has to travel, and sets the
  direction bit in the volume-control register accordingly. $40 is the
  decreasing-ramp bit.
  -------------------------------------------------------------------------- }
procedure ChangeVol(Channel, Vol, Ramp : Byte);
var
  Oldv : Byte;
begin
  if (Vol > 127) and (Vol <> $FF) then
    Vol := 127;

  if (Vol <> $FF) and (LastVolumes[Channel] <> Vol) then
  begin
    LastVolumes[Channel] := Vol;

    SetGusRegister8(grVolumeControl, 3);            { ramp stopped }
    Oldv := Hi(GetGusRegister16(grCurrentVol));  { where it is  }

    if Oldv <> Hi(VolumeTable[Vol]) then
    begin
      if Oldv > Hi(VolumeTable[Vol]) then  { going down   }
      begin
        SetGusRegister8(grRampEnd, Oldv);                  { ramp end     }
        SetGusRegister8(grRampStart, Hi(VolumeTable[Vol]));  { ramp start   }
      end
      else
      begin
        SetGusRegister8(grRampStart, Oldv);
        SetGusRegister8(grRampEnd, Hi(VolumeTable[Vol]));
      end;

      SetGusRegister16(grCurrentVol, Word(Oldv) shl 8);
      SetGusRegister8(grRampRate, Ramp);               { ramp rate    }

      if Oldv > Hi(VolumeTable[Vol]) then
        SetGusRegister8(grVolumeControl, GetGusRegister8(grVolumeControl) and not 3 or $40)
      else
        SetGusRegister8(grVolumeControl, GetGusRegister8(grVolumeControl) and not 3 and not $40)
    end
  end
end;

{ --------------------------------------------------------------------------
push one voice's stored addresses at the card. Near, private.

  Compiler output. Reads the three tables, converts each to the GF1's split
  form, and writes the register pairs: $0A/$0B current, $04/$05 end,
  $02/$03 loop.

  THE LOOP FLAG IS DERIVED, not passed. A loop address of all-ones means the
  sample does not loop, so bit 3 of the voice control register is cleared and
  the loop registers are left alone; anything else sets it. That is why
  StartUltrasound fills LastLoopStart with $FE rather than $FF -- a voice that
  has never been programmed must not look like a looping one.
  -------------------------------------------------------------------------- }
procedure ChangeSample(Voice : Byte);
var
  Cur, Loop, Fin : LongInt;
begin
  Cur  := LastVoiceStart[Voice];
  Loop := LastLoopStart[Voice];
  Fin  := LastVoiceEnd[Voice];

  SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) or $03);  { stop it first }

  SwapGusAddress(Cur);
  SetGusRegister16(grCurrentAddrLow, Cur and $FFFF);
  SetGusRegister16(grCurrentAddrHigh, Cur shr 16);

  SwapGusAddress(Fin);
  SetGusRegister16(grEndAddrLow, Fin and $FFFF);
  SetGusRegister16(grEndAddrHigh, Fin shr 16);

  if Loop = -1 then                                     { no loop }
    SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) and $F7)
  else
  begin
    SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) or $08);  { looping }
    SwapGusAddress(Loop);
    SetGusRegister16(grStartAddrLow, Loop and $FFFF);
    SetGusRegister16(grStartAddrHigh, Loop shr 16);
  end;
end;

{ --------------------------------------------------------------------------
THE DEFERRED SWEEP. Installed as the timer 1 callback by
  TriggerVoice, and where every voice change actually reaches the card.

  Two passes over the active flags, and the split matters.

  Separating them is what makes the card see one burst. Programming a voice
  is a dozen register writes with the voice stopped; starting it is two. Doing
  all the slow work first and all the starts together means voices that were
  meant to begin on the same tick actually do, instead of drifting apart by
  however long the register writes took.}
procedure RestartChannels;
const
  { $06c2..$0701 -- TWO BYTES PER VOICE, thirty-two voices, and the release declares
    exactly this as `buf : ARRAY[1..64] OF BYTE`. A LOCAL typed constant lands in
    DGROUP just as a unit-level one does, which is why the code cannot tell them apart
    and why the layout had to settle it -- see the note where the unit-level
    declaration used to be. Each entry pair is a voice number and the control byte
    read back from register $00 with its stop bits cleared. }
  CmdList : array[1..64] of Byte = (
    0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0);
var

  i, k, Vol : Byte;
  j         : Word;

  First     : Boolean;
begin
  GUSStopTimer1;

  { --- pass one: program everything that is flagged ------------------ }

  for i := 0 to GUSChannels - 1 do
    if VoicesChanged[i] <> 0 then
    begin
      SetGusVoice(i);
      ChangeSample(i);
      Vol := LastVolumes[i];
      LastVolumes[i] := 0;
      ChangeVol(i, Vol, $1F);
    end;

  { --- pass two: collect the ready voices, then start them together -- }
  j := 0;
  for i := 0 to GUSChannels - 1 do
    if VoicesChanged[i] <> 0 then
    begin
      Inc(j, 2);
      CmdList[j - 1] := i;
      CmdList[j] := GetGusRegister8(grVoiceControl) and $FC;  { clear the stop bits }
      { v1.51 DOES NOT CLEAR IT HERE. The clear moved into the third pass
        below, which is the pass that actually starts the voice. }
    end;

  { ------------------------------------------------------------------
A THIRD PASS, WHERE v1.31b HAD SIXTY BYTES OF HAND
    ASSEMBLER.

    v1.31b ended this routine by kicking ONE voice: it took the first entry of
    the command list, saved that voice's control byte and playing position,
    wrote the collected control byte so the voice ran, polled the position
    until it moved, then put both back. The point was the GF1's own service
    rotation -- starting a batch at an arbitrary moment scatters the voices
    across it, and waiting for one voice to advance meant the writes began at a
    known phase.

    v1.51 DELETES ALL OF THAT, and the `if j <= 0 then Exit` guard with it.
    Each changed voice is now started on its own: select it, read register $00,
    clear the stop bits, write it back. Simpler, and it gives up the phase
    alignment the assembler bought.

    The command list built in pass two is still built and is no longer used by
    this routine, which is the sort of thing only a byte comparison notices. }
  First := True;

  for i := 0 to GUSChannels - 1 do
    if VoicesChanged[i] <> 0 then
    begin
      SetGusVoice(i);
      SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) and $FC);
      VoicesChanged[i] := 0
    end
end;

{ --------------------------------------------------------------------------
start a voice with a loop. THE ENTRY 12ba's ring flushes to.

  Compiler output, and it programs NOTHING. It stores the three addresses,
  raises the active flag, records the pan, and points the timer 1 callback at
  RestartChannels. The card is touched on the next tick, not now.

  The stores are held under PUSHF/CLI -- not because the card cares, but
  because RestartChannels runs from an interrupt and must not find a half-
  written table.

  ChangeVoiceParams is called first, for the frequency and pan, and this adds
  the addresses on top.}
{ **TriggerVoice DOES NOT START THE VOICE**, and that is the whole design of
  GUS playback here. It writes the frequency and pan, records what the voice
  SHOULD be doing in five parallel arrays, sets a flag, and arms a timer. The
  voice itself is started later, by RestartChannels, from the timer interrupt.

  The reason is that the GF1 restarts a voice by being written a start address,
  an end address and a control byte, and a voice restarted at the wrong moment
  clicks. Deferring the work to a timer puts every restart on the same regular
  boundary rather than wherever the sequencer happened to reach it, and lets
  several voices retrigger together in one pass.

  So the five arrays are not caches of what the card holds -- they are a
  DESCRIPTION OF WHAT IT SHOULD HOLD, and `VoicesChanged` is the difference
  between the two. A reader looking for the code that starts a note will not
  find it here.

    LastVoiceStart  where the sample begins in GUS DRAM
    LastLoopStart   where its loop returns to
    LastVoiceEnd    where it ends
    LastVolumes     the volume it should ramp to
    VoicesChanged   set here, cleared by RestartChannels once it has acted

  **AND THAT IS WHY THE FIVE UPDATES RUN WITH INTERRUPTS OFF.** The timer that
  will read these arrays can fire between any two of them. Without the CLI it
  could see a voice already flagged as changed while three of its five values
  still describe the previous note -- and it would start a sample that never
  existed, with one note's start address and another's end. PUSHF/POPF rather
  than CLI/STI because the caller's interrupt state has to come back as it was:
  this runs inside the sequencer, which may itself already be in a critical
  section. }
procedure TriggerVoice(Voice, Vol : Byte; Freq : LongInt; Pan : Byte;
                         StartA, LoopA, EndA : LongInt);
begin
  SetGusVoice(Voice);                      { all register writes
                                             below apply to this voice }
  ChangeVoiceParams(Voice, 0, Freq, Pan);  { volume 0: silent until
                                             the restart ramps it up }

  asm PUSHF; CLI end;                { the five updates are one
                                       transaction -- see above }
  LastVoiceStart[Voice]  := StartA;
  LastLoopStart[Voice] := LoopA;
  LastVoiceEnd[Voice]  := EndA;
  VoicesChanged[Voice]   := 1;
  LastVolumes[Voice] := Vol;
  asm POPF end;

  { Arm the timer that will do the actual restart. The routine pointer is
    installed each time rather than once, so whatever the timer last ran does
    not decide what happens now. }
  GUSTimer1RutPtr := @RestartChannels;
  GUSInitTimer1($F6);                   { $F6 is the countdown, not
                                          a register number }
end;

{ --------------------------------------------------------------------------
set a live voice's frequency and pan, without restarting it.

  Compiler output. Does nothing at all if the voice is not already active,
  which is what lets the mixer send pitch changes for voices that may have
  finished without having to track that itself.

  THE FREQUENCY IS RATE-RELATIVE. The value written is

      (Freq * (GUSDivisor div 2)) div (GUSDivisor div 2 + Freq')}
{ --------------------------------------------------------------------------
set a running voice's volume, pitch and pan.}
procedure ChangeVoiceParams(Channel, Vol : Byte; Freq : LongInt;
                            Panning : Byte);
begin
  SetGusVoice(Channel);

  if VoicesChanged[Channel] <> 0 then
  begin
    if Vol <> $FF then
    begin
      if Vol > $7F then Vol := $7F;
      LastVolumes[Channel] := Vol;
    end
  end
  else
    ChangeVol(Channel, Vol, $1F);

  if (Freq <> -1) and (LastFreqs[Channel] <> Freq) then
  begin
    LastFreqs[Channel] := Freq;
    SetGusRegister16(grFreqControl, ((Freq shl 9) + LongInt(GUSDivisor shr 1))
                    div LongInt(GUSDivisor shr 1));
  end;

  if LastPans[Channel] <> Panning then
  begin
    LastPans[Channel] := Panning;
    SetGusRegister8(grPanPosition, Panning shr 4);
  end;
end;

{ --------------------------------------------------------------------------
how many voices, and what that costs in sample rate.

  Compiler output. The GF1 divides one fixed clock between however many
  voices are enabled, so asking for fewer voices buys a higher rate:

      GUSDivisor := 617400 div GUSChannels

  Clamped to 14..32. Fourteen is the fewest the chip allows; thirty-two is
  all it has. Register $0E takes the count in the top bits with the low bit
  set, hence `+ $C0 - 1`.
  -------------------------------------------------------------------------- }
procedure SetGusChannels(N : Byte);
begin
  if N > $20 then N := $20        { at most 32 }
  else if N < $14 then N := $14;  { at least 14 }

  SetGusRegister8(grActiveVoices, $C0 + N - 1);
  GUSDivisor    := 617400 div N;
  GUSChannels := N;
end;

end.
