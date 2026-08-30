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

  PASCAL OR ASSEMBLER? THE PORT NUMBER DECIDES. `Port[X]` compiles to
  `MOV DX,[X] / OUT DX,AL` only when X is a bare variable or a constant. With
  a computed index -- `GUSPort + $103` -- Turbo Pascal evaluates an address
  expression through AX and the bytes differ, so the register interface at
  1723:0000..0079 is hand assembler and the routines that poke a fixed port
  are Pascal. Writing `Port[GUSPort + $00]` counts as computed; the `+ 0`
  costs three bytes and reorders the instructions.

  This file claimed the opposite for a long time -- that Port[] always
  matched -- and it was wrong in both directions. See docs/06-transcription.md.

  ADDRESS MAP
    SetGusVoice        1723:0000 *   GetGusRegister8    1723:0013 *
    SetGusRegister8    1723:0030 *   GetGusRegister16   1723:004a *
    SetGusRegister16   1723:0065 *   GusDelay           1723:007d *
    DumpToUltrasound   1723:0089     GUSInitTimer1      1723:0100
    GUSInitTimer2      1723:0140     GUSStopTimer1      1723:0180
    ServiceTimer1      1723:01b5 *   ServiceTimer2      1723:01db *
    GUSIrqHandler      1723:0201 *   InitGusIRQ         1723:025a
    DoneGusIRQ         1723:029f     SetMixControl      1723:02d3 *
    StartUltrasound    1723:0357     ProbeUltrasound    1723:045a *
    DetectUltrasound   1723:04f1     SwapGusAddress     1723:0539 *
    ChangeVol          1723:0565 *   ChangeSample       1723:0662 *
    RestartChannels    1723:077a     TriggerVoice       1723:08e6
    ChangeVoiceParams  1723:0980     SetGusChannels     1723:0a6a
                                             (* near, private to the unit)

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
  MaxVoice = 31;  { the tables in 1723:0357 are 32 entries }

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
  { DS:$0582 -- $FFFF means "not configured, go and look". 109c:047c writes
    the config file's value here, which is what ties VT.CFG to the card. }
  GUSPort         : Word    = $FFFF;

  GUSIrq          : Word    = 11;      { DS:$062C                            }
  GUSChannels     : Byte    = 32;      { DS:$062E  the CARD's voices; pad $0587 }
  GUSDivisor      : Word    = 19293;   { DS:$0630  4b 5d                     }
  GUSTimer1RutPtr : Pointer = nil;     { DS:$0632                            }
  GUSTimer2RutPtr : Pointer = nil;     { DS:$0636                            }

{ `VAR Src` UNTYPED, AND `165a` IS WHAT SETTLED IT. Inside this routine a Pointer
  parameter and an untyped var parameter are the same four bytes and `LDS SI,Src`
  loads the same address either way, so nothing here could tell them apart. The CALL
  SITE can: `165a:02b0` is `LES DI,ES:[DI+16] / PUSH ES / PUSH DI`, which is how a
  var parameter is passed, where a Pointer argument would be two word pushes. Two
  bytes shorter, and it is the release's declaration too. }
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
  TimerControl  : Byte    = 0;    { DS:$063A  shadow of GF1 register $45      }
  TimerMask     : Byte    = 0;    { DS:$063B  shadow of the timer control     }
  OldIrqHandler : Pointer = nil;  { DS:$063C                                  }
  OldIrqState   : Boolean = False;{ DS:$0640  enabled before InitGusIRQ?      }
  GusIRQInited  : Boolean = False;{ DS:$0641                                  }

  { DS:$059a -- the GF1 encodes its interrupt in three bits rather than
    taking the number, so the number has to be translated. Zero means the
    card cannot be wired to that line at all. }
  IrqCode : array[0..15] of Byte =
    (0, 0, 1, 3, 0, 2, 0, 4, 0, 0, 0, 5, 6, 0, 0, 7);

  { DS:$05aa -- the twelve addresses a GUS can be jumpered to.
    DetectUltrasound walks these in order when GUSPort has not been
    configured, so the first one that answers wins, not the lowest. }
  GUSPorts : array[1..12] of Word =
    ($0220, $0240, $0200, $0210, $0230, $0250,
     $0260, $0270, $0280, $0290, $02A0, $02B0);

var
  { The per-voice tables StartUltrasound clears and TriggerVoice fills in.
    Their sizes come straight from the FillChar calls at 1723:0357: $80 bytes
    for the LongInt ones and $20 for the Byte ones, so 32 voices throughout.

    VoicesChanged is the release's name and the release's is a BOOLEAN. It is
    kept as a Byte here because the code tests it as `<> 0` and stores 1, and
    rewriting those as `then`/`True` is a codegen change, not a rename. }
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
  LastVoiceStart : array[0..MaxVoice] of LongInt;  { DS:$371a  STALE, see above }
  LastLoopStart  : array[0..MaxVoice] of LongInt;  { DS:$379a  filled with $FE }
  LastVoiceEnd   : array[0..MaxVoice] of LongInt;  { DS:$381a  filled with $FF }
  LastVolumes    : array[0..MaxVoice] of Byte;     { DS:$389a  filled with $FF }
  LastFreqs      : array[0..MaxVoice] of LongInt;  { DS:$38ba  filled with $FF }
  LastPans       : array[0..MaxVoice] of Byte;     { DS:$393a  filled with $7F }
  VoicesChanged  : array[0..MaxVoice] of Byte;     { DS:$395a  filled with $00 }

  { ~~CmdList : array[0..255] of Byte~~ -- GONE FROM HERE. It is 64 bytes, it is a TYPED
  CONSTANT, and it is LOCAL to `RestartChannels`; all three were open questions and the
  DGROUP layout closed all three at once. The note that used to sit here said exactly
  that this was "a guess that will have to be revisited" once the layout was known, and
  named the release's shape -- `buf : ARRAY[1..64] OF BYTE`, a local typed constant --
  as the likely answer. It was.

  WHAT SETTLED IT: `1723:08c8` is `MOV SI,06C2h`, and $06c2 is the first byte after this
  unit's `VolumeTable`, which ends at $06c1. The next thing in DGROUP is HEAPS' first
  virtual method table at $0702 -- so the array is bounded at 64 bytes, which is two per
  voice for 32 voices exactly. It is in the INITIALISED region, so it is a typed
  constant and not a `var`; and a local typed constant of RestartChannels is what puts
  it after VolumeTable, because DGROUP follows declaration order and VolumeTable is
  declared earlier in the file.

  AND THE `+1` WAS WRONG. The asm read `MOV SI, OFFSET CmdList+1`, which only reaches
  $06c2 if the array starts at $06c1 -- inside VolumeTable's last byte. With
  `array[1..64]` the array itself starts at $06c2 and the `+1` comes off. Neither form
  could be measured before: `OFFSET` of a DGROUP symbol is a linker fixup, so the .TPU
  holds zeros either way and `units.py` excused it. See the declaration in
  RestartChannels. }

{ --------------------------------------------------------------------------
  1723:0000 .. 1723:0065 -- the GF1 register interface.

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

  They were Pascal here until units.py could not even find the unit's first
  instruction. Turbo Pascal's `Port[]` pseudo-array compiles to a bare
  `MOV DX,imm / OUT DX,AL` ONLY when the index is a constant. With a computed
  index it evaluates the address as an ordinary expression, through AX:

      Port[GUSPort + $102] := N        the original
      -----------------------------     ------------
      MOV AX,[GUSPort]                 MOV DX,[GUSPort]
      ADD AX,0102                       ADD DX,0102
      MOV DX,AX
      MOV AL,[BP+4]                     MOV AL,[BP+4]
      OUT DX,AL                         OUT DX,AL

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
        MOV     DX,GUSPort  { 1723:0003 }
        ADD     DX,$102     { 1723:0007  the voice-select register }
        MOV     AL,N        { 1723:000b }
        OUT     DX,AL       { 1723:000e }
end;

{ The read alias: registers below $40 are read at register+$80. }
function GetGusRegister8(Reg : Byte) : Byte; assembler;
asm
        MOV     DX,GUSPort  { 1723:0016 }
        ADD     DX,$103     { 1723:001a  the register-select port }
        MOV     AL,Reg      { 1723:001e }
        CMP     AL,$40      { 1723:0021 }
        JNB     @@Hi        { 1723:0023  already an alias }
        ADD     AL,$80      { 1723:0025 }
@@Hi:
        OUT     DX,AL  { 1723:0027 }
        ADD     DX,2   { 1723:0028  -> the data port, $105 }
        IN      AL,DX  { 1723:002b }
end;

{ No alias on the write path -- writes use the register number as given. }
procedure SetGusRegister8(Reg, Val : Byte); assembler;
asm
        MOV     DX,GUSPort  { 1723:0033 }
        ADD     DX,$103     { 1723:0037 }
        MOV     AL,Reg      { 1723:003b  [BP+6], the FIRST parameter }
        OUT     DX,AL       { 1723:003e }
        ADD     DX,2        { 1723:003f }
        MOV     AL,Val      { 1723:0042  [BP+4] }
        OUT     DX,AL       { 1723:0045 }
end;

function GetGusRegister16(Reg : Byte) : Word; assembler;
asm
        MOV     DX,GUSPort  { 1723:004d }
        ADD     DX,$103     { 1723:0051 }
        MOV     AL,Reg      { 1723:0055 }
        CMP     AL,$40      { 1723:0058 }
        JNB     @@Hi        { 1723:005a }
        ADD     AL,$80      { 1723:005c }
@@Hi:
        OUT     DX,AL  { 1723:005e }
        INC     DX     { 1723:005f  -> $104, the 16-bit port }
        IN      AX,DX  { 1723:0060  a WORD read }
end;

procedure SetGusRegister16(Reg : Byte; Val : Word); assembler;
asm
        MOV     DX,GUSPort  { 1723:0068 }
        ADD     DX,$103     { 1723:006c }
        MOV     AL,Reg      { 1723:0070  [BP+6] }
        OUT     DX,AL       { 1723:0073 }
        INC     DX          { 1723:0074 }
        MOV     AX,Val      { 1723:0075  [BP+4] }
        OUT     DX,AX       { 1723:0078 }
end;

{ --------------------------------------------------------------------------
  1723:007d -- settling delay. FRAMELESS: no parameters, no frame, a bare RET.

  HAND ASSEMBLER, verbatim. Seven reads of the base port with every result
  thrown away. The GF1 needs time between register accesses and this is how
  the original buys it -- not a counted loop, because the delay wanted is a
  number of ISA bus cycles, and an IN is the only thing that reliably costs
  one whatever the CPU speed. A `for` loop would get faster with the machine;
  this does not.
  -------------------------------------------------------------------------- }
procedure GusDelay; assembler;
asm
  MOV  DX, GUSPort  { 1723:007d                                       }
  IN   AL, DX       { 1723:0081                                       }
  IN   AL, DX       { 1723:0082                                       }
  IN   AL, DX       { 1723:0083                                       }
  IN   AL, DX       { 1723:0084                                       }
  IN   AL, DX       { 1723:0085                                       }
  IN   AL, DX       { 1723:0086                                       }
  IN   AL, DX       { 1723:0087                                       }
end;

{ --------------------------------------------------------------------------
  1723:0089 -- copy a sample into the card's own DRAM.

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
  1723:008c..00b2 is compiler output, including a runtime helper at
  1ba1:0a9c for the 32-bit shift -- and only the transfer loop is hand
  written. Declared `assembler`, the whole prologue vanishes and the unit
  diverges at the first byte after the frame.

  THE DRAM ADDRESS IS LOADED WITH LES. `LES DI,DramAt` puts the low word of
  the LongInt in DI and the high word in ES, which is why 1723:00bc reads
  the page byte back out of ES rather than from the frame. It looks like a
  pointer load and it is not one; the source pointer is the separate
  LDS SI,Src further down. }
procedure DumpToUltrasound(var Src; Count : Word;
                     DramAt : LongInt; Signed : Word);
begin
  SetGusRegister8(grDRAMHighIO, DramAt shr 16);      { 1723:008c .. 1723:009f }
  SetGusRegister16(grDRAMLowIO, DramAt and $FFFF);  { 1723:00a2 .. 1723:00b2 }
  asm
  PUSH DS          { 1723:00b5  LODSB will take DS away              }
  MOV  CX, Count   { 1723:00b6  [BP+0Ch]                             }
  LES  DI, DramAt  { 1723:00b9  the DRAM address, low word in DI     }
  MOV  BX, ES      { 1723:00bc  ... high half in BL                  }
  MOV  BH, BYTE PTR Signed { 1723:00be  [BP+06h]                           }
  CMP  BH, 1        { 1723:00c1  carry when the caller said 0         }
  SBB  BH, BH       { 1723:00c4  $FF when signed, else $00            }
  SHL  BH, 7        { 1723:00c6  ... becomes the $80 XOR mask         }
  MOV  DX, GUSPort  { 1723:00c9                                       }
  LDS  SI, Src      { 1723:00cd  [BP+0Eh]                             }
  ADD  DX, 0103h    { 1723:00d0  the register select port             }
@@Byte:
  MOV  AL, 43h  { 1723:00d4  DRAM address, low word               }
  OUT  DX, AL   { 1723:00d6                                       }
  INC  DX       { 1723:00d7  base+$104                            }
  MOV  AX, DI   { 1723:00d8                                       }
  OUT  DX, AX   { 1723:00da                                       }
  ADD  DX, 3    { 1723:00db  base+$107, the DRAM data port        }
  LODSB         { 1723:00de                                       }
  XOR  AL, BH   { 1723:00df  signed -> unsigned, or nothing       }
  OUT  DX, AL   { 1723:00e1                                       }
  INC  DI       { 1723:00e2                                       }
  JNZ  @@Same   { 1723:00e3  the low word did not wrap            }
  INC  BL       { 1723:00e5                                       }
  SUB  DX, 4    { 1723:00e7  back to base+$103                    }
  MOV  AL, 44h  { 1723:00ea  DRAM address, high byte              }
  OUT  DX, AL   { 1723:00ec                                       }
  ADD  DX, 2    { 1723:00ed  base+$105                            }
  MOV  AL, BL   { 1723:00f0                                       }
  OUT  DX, AL   { 1723:00f2                                       }
  ADD  DX, 2    { 1723:00f3                                       }
@@Same:
  SUB  DX, 4   { 1723:00f6  base+$103, ready for the next        }
  LOOP @@Byte  { 1723:00f9                                       }
  POP  DS      { 1723:00fb                                       }
  end          { 1723:00fc  LEAVE / RETF 0Ch, from Pascal        }
end;

{ --------------------------------------------------------------------------
  1723:0100 / 1723:0140 / 1723:0180 -- the two GF1 timers.

  Compiler output. Registers $46 and $47 hold the counts, $45 is the timer
  control, and base+8 / base+9 are the AdLib-compatible pair that gates the
  interrupt.

  BOTH CONTROL REGISTERS ARE SHADOWED in the data segment, at DS:$0592 and
  DS:$0593, because neither is readable. Every change is made to the shadow
  and the shadow is written out whole -- the only way to set one bit without
  knowing the others.
  -------------------------------------------------------------------------- }
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
  SetGusRegister8(grTimer1Count, Count);          { 1723:0109 }
  TimerControl := TimerControl or $04;  { 1723:010f }
  SetGusRegister8(grTimerControl, TimerControl);   { 1723:011a }
  TimerMask := TimerMask or $01;        { 1723:0120  timer 1's mask bit }
  Port[GUSPort + 8] := 4;               { 1723:012f  select register 4 in the
                                          interrupt window -- see above }
  Port[GUSPort + 9] := TimerMask;       { 1723:013b  and write it }
end;

procedure GUSInitTimer2(Count : Byte);
begin
  SetGusRegister8(grTimer2Count, Count);          { 1723:0149 }
  TimerControl := TimerControl or $08;  { 1723:014f }
  SetGusRegister8(grTimerControl, TimerControl);   { 1723:015a }
  TimerMask := TimerMask or $02;        { 1723:0160 }
  Port[GUSPort + 8] := 4;               { 1723:016f }
  Port[GUSPort + 9] := TimerMask;       { 1723:017b }
end;

procedure GUSStopTimer1;
begin
  TimerControl := TimerControl and $FB;  { 1723:0186 }
  SetGusRegister8(grTimerControl, TimerControl);    { 1723:0191 }
  TimerMask := TimerMask and $FE;        { 1723:0197 }
  Port[GUSPort + 8] := 4;                { 1723:01a6 }
  Port[GUSPort + 9] := TimerMask;        { 1723:01b2 }
end;

{ --------------------------------------------------------------------------
  1723:01b5 and 1723:01db -- a timer expired.

  Compiler output, near, private. Clearing the enable bit and setting it
  straight back is what acknowledges the timer to the GF1; the shadow is not
  disturbed, so the two writes are `TimerControl and mask` followed by plain
  `TimerControl`.

  The callback is only called if the far pointer is non-nil, and the test is
  on BOTH halves -- a segment of zero with a non-zero offset would still be
  called. That is deliberate enough to preserve.

  DS:$058e is the one that matters to the rest of the program: 1084:008a puts
  the GUS driver's own handler there, so timer 2 is what drives the music.
  -------------------------------------------------------------------------- }
procedure ServiceTimer1;
begin
  SetGusRegister8(grTimerControl, TimerControl and $FB);  { 1723:01c0 }
  SetGusRegister8(grTimerControl, TimerControl);          { 1723:01c9 }
  if GUSTimer1RutPtr <> nil then               { 1723:01cc }
    asm
      CALL DWORD PTR GUSTimer1RutPtr  { 1723:01d5                              }
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
  SetGusRegister8(grTimerControl, TimerControl and $F7);  { 1723:01e6  drop it }
  SetGusRegister8(grTimerControl, TimerControl);          { 1723:01ef  re-arm }
  if GUSTimer2RutPtr <> nil then               { 1723:01f2 }
    asm
      CALL DWORD PTR GUSTimer2RutPtr  { 1723:01fb                              }
    end;
end;

{ --------------------------------------------------------------------------
  1723:0201 -- the card's interrupt handler. FRAMELESS, ends in IRET.

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
  CLI                       { 1723:0201                                       }
  PUSHA                     { 1723:0202                                       }
  PUSH ES                   { 1723:0203                                       }
  PUSH DS                   { 1723:0204                                       }
  MOV  AX, SEG @DATA        { 1723:0205  was MOV AX,1CAAh                     }
  MOV  DS, AX               { 1723:0208                                       }
  MOV  AL, 20h              { 1723:020a  non-specific EOI                     }
  OUT  20h, AL              { 1723:020c  release the master straight away     }
  MOV  AH, BYTE PTR GUSIrq  { 1723:020e                                       }
  CMP  AH, 8                { 1723:0212                                       }
  JC   @@Master             { 1723:0215                                       }
  OUT  0A0h, AL             { 1723:0217  the slave as well                    }
@@Master:
  MOV  AL, AH      { 1723:0219                                       }
  XOR  AH, AH      { 1723:021b                                       }
  PUSH AX          { 1723:021d                                       }
  CALL DisableIRQ  { 1723:021e  1b24:0044 -- keep ourselves out      }
@@Again:
  CLI                 { 1723:0223                                       }
  MOV  DX, GUSPort    { 1723:0224                                       }
  ADD  DX, 6          { 1723:0228  the IRQ status register              }
  IN   AL, DX         { 1723:022b                                       }
  TEST AL, 0Ch        { 1723:022c  either timer?                        }
  JZ   @@Done         { 1723:022e                                       }
  STI                 { 1723:0230  callbacks run with interrupts on     }
  TEST AL, 4          { 1723:0231                                       }
  JZ   @@NotOne       { 1723:0233                                       }
  PUSH AX             { 1723:0235                                       }
  CALL ServiceTimer1  { 1723:0236                                       }
  POP  AX             { 1723:0239                                       }
@@NotOne:
  TEST AL, 8          { 1723:023a                                       }
  JZ   @@NotTwo       { 1723:023c                                       }
  PUSH AX             { 1723:023e                                       }
  CALL ServiceTimer2  { 1723:023f                                       }
  POP  AX             { 1723:0242                                       }
@@NotTwo:
  JMP  @@Again  { 1723:0243  until the card is quiet              }
@@Done:
  MOV  AL, BYTE PTR GUSIrq  { 1723:0245                                       }
  XOR  AH, AH               { 1723:0248                                       }
  PUSH AX                   { 1723:024a                                       }
  CALL EnableIRQ             { 1723:024b  1b24:0000                            }
  PUSH 000Fh                { 1723:0250                                       }
  CALL GetGusRegister8      { 1723:0252  clear anything latched               }
  POP  DS                   { 1723:0255                                       }
  POP  ES                   { 1723:0256                                       }
  POPA                      { 1723:0257                                       }
  IRET                      { 1723:0258                                       }
end;

{ --------------------------------------------------------------------------
  1723:025a / 1723:029f -- take the interrupt line, and give it back.

  Compiler output. Both are guarded by DS:$0599 so a second InitGusIRQ does
  nothing and a second DoneGusIRQ does nothing.

  THE STATE IS RESTORED PROPERLY, which is rarer than it should be. InitGusIRQ
  records whether the line was ALREADY enabled; DoneGusIRQ only disables it
  again if it was not. A driver that blindly masked on the way out would
  silence whatever else had been sharing that line.
  -------------------------------------------------------------------------- }
procedure InitGusIRQ;
begin
  if GusIRQInited then Exit;                              { 1723:025d }
  GusIRQInited := True;                                   { 1723:0266 }
  OldIrqState  := IRQState(GUSIrq);                     { 1723:026f  1b24:007e }
  OldIrqHandler := SetIRQVector(GUSIrq, @GUSIrqHandler);  { 1723:0283  1b24:00d7 }
  EnableIRQ(GUSIrq);                                      { 1723:0293  1b24:0000 }
  GetGusRegister8(grVoiceIRQ);                                   { 1723:029a  clear status }
end;

procedure DoneGusIRQ;
begin
  if not GusIRQInited then Exit;               { 1723:02a2 }
  GusIRQInited := False;                       { 1723:02ab }
  if not OldIrqState then DisableIRQ(GUSIrq);  { 1723:02b0  only if we turned it on }
  SetIRQVector(GUSIrq, OldIrqHandler);         { 1723:02cc }
end;

{ --------------------------------------------------------------------------
  1723:02d3 -- mix control and the IRQ latch. Near, private.

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
  V := IrqCode[GUSIrq] + $40;  { 1723:02db }
  asm
    PUSHF  { 1723:02e7  keep the caller's interrupt state    }
    CLI    { 1723:02e8                                       }
  end;
  Port[GUSPort + $0F] := 5;   { 1723:02f3 }
  Port[GUSPort] := $0B;       { 1723:02fa }
  Port[GUSPort + $0B] := 0;   { 1723:0305 }
  Port[GUSPort + $0F] := 0;   { 1723:0310 }
  Port[GUSPort] := $4B;       { 1723:0317 }
  Port[GUSPort + $0B] := V;   { 1723:0323  arm         }
  Port[GUSPort] := $4B;       { 1723:032a }
  Port[GUSPort + $0B] := V;   { 1723:0336  commit      }
  Port[GUSPort + $102] := 0;  { 1723:0341 }
  Port[GUSPort] := $0C;       { 1723:0348 }
  Port[GUSPort + $102] := 0;  { 1723:0353 }
  asm
    POPF  { 1723:0354                                       }
  end;
end;

{ --------------------------------------------------------------------------
  1723:0357 -- reset the card and every voice.

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
  FillChar(LastVoiceStart,  $80, $FF);  { 1723:0365 }
  FillChar(LastLoopStart, $80, $FE);    { 1723:0374 }
  FillChar(LastVoiceEnd,  $80, $FF);    { 1723:0383 }
  FillChar(LastVolumes,    $20, $FF);   { 1723:0391 }
  FillChar(LastFreqs,    $80, $FF);     { 1723:03a0 }
  FillChar(LastPans,     $20, $7F);     { 1723:03ae  dead centre }
  FillChar(VoicesChanged,   $20, $00);  { 1723:03bc }

  SetMixControl;  { 1723:03c1 }

  { HAND ASSEMBLER, and the ORDER is why. The identical Pascal statement
    compiles to MOV AL / MOV DX / OUT at 1723:02f4, but here the original has
    MOV DX / MOV AL / OUT -- same three instructions, same seven bytes,
    opposite order. Turbo Pascal will not emit the second form for a port
    assignment, and BASM emits exactly what it is told. }
  asm
    MOV  DX, GUSPort  { 1723:03c4                                       }
    MOV  AL, 0Bh      { 1723:03c8  [1.39b] "Turn off output, to avoid   }
                      {             clicks." -- the reason for the whole }
                      {             port write, and not in the bytes     }
    OUT  DX, AL       { 1723:03ca                                       }
  end;
  SetGusRegister8(grReset, 0);    { 1723:03cf  [1.39b] "Reset the GUS card." }
  GusDelay;                   { 1723:03d2 }
  SetGusRegister8(grReset, 1);    { 1723:03d9  [1.39b] "DAC turned off."     }
  SetGusRegister8(grActiveVoices, $DF);  { 1723:03e0  32 voices     }
  SetGusRegister16(grDRAMLowIO, 0);   { 1723:03e7 }
  SetGusRegister8(grDRAMHighIO, 0);    { 1723:03ee }

  { 1723:03f1 -- silence every voice before anything else can start one.

    A FOR LOOP, AND IT STARTS AT ZERO. 1723:03f6 is `JMP` past the increment,
    which is Borland's FOR head; written as `repeat Inc(V) ... until` the
    increment happens BEFORE the first body and voice 0 is never silenced. }
  for V := 0 to MaxVoice do  { 1723:03f1, 1723:043c }
  begin
    SetGusVoice(V);           { 1723:03ff }
    SetGusRegister8(grVoiceControl, 3);  { 1723:0406  stopped      }
    SetGusRegister8(grVolumeControl, 3);  { 1723:040d  volume idle  }
    { ALL FOUR ARE INSIDE THE `if`. The JBE at 1723:0418 jumps to 1723:043c,
      which is the loop test -- so it skips the ramp settings too, not just
      the two volume writes. Written with the last two outside, a voice whose
      current volume is already low never gets its ramp rate set. }
    if GetGusRegister16(grCurrentVol) > $1800 then  { 1723:0412 }
    begin
      SetGusRegister8(grRampStart, $18);                        { 1723:041e }
      SetGusRegister8(grRampEnd, Hi(GetGusRegister16(grCurrentVol)));  { 1723:042b }
      SetGusRegister8(grRampRate, $1F);                        { 1723:0432  fastest ramp }
      SetGusRegister8(grVolumeControl, $40);                        { 1723:0439 }
    end;
  end;  { 1723:043c  CMP V,$1F }

  { **AND THE PORT WRITE THAT FOLLOWS IS THE OTHER HALF OF THE CLICK GUARD.**
    The release pairs them explicitly: 0Bh at the top is "[1.39b] Turn off
    output, to avoid clicks" and 0Ch at the bottom is "[1.39b] Turn on output".
    The card is silenced before the reset and unsilenced after it, so the
    transition itself is never audible. }
  SetGusRegister8(grReset, 7);  { 1723:0446  [1.39b] "DAC turned on."  }
  asm                       { hand assembler, same as the $0B poke above:      }
    MOV  DX, GUSPort        { 1723:044f  port first, then the value            }
    MOV  AL, 0Ch            { 1723:0453                                       }
    OUT  DX, AL             { 1723:0455                                       }
  end;
  SetGusChannels(GUSChannels);  { 1723:0455 }
end;

{ --------------------------------------------------------------------------
  1723:045a -- is there really a card at GUSPort? Near, private.

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
{ NO `Ok` LOCAL -- assign to the function result directly. The original writes
  its Boolean to [BP-1], an ODD offset that Turbo Pascal will not give a
  declared variable (it word-aligns them to [BP-2]). That byte is the function
  RESULT, which Borland allocates as a hidden local at the top of the frame; a
  separate flag variable gets one of its own and everything below shifts.
  Not the $A switch -- compiling this unit $A- changes nothing. }
label
  Fin;
var
  Save0, Save1 : Word;
begin
  ProbeUltrasound := False;  { 1723:045e }
  asm CLI end;               { 1723:0462 }

  SetGusRegister8(grReset, 0);    { 1723:0467  hold in reset }
  GusDelay;                   { 1723:046a }
  SetGusRegister8(grReset, 7);    { 1723:0471 }
  SetGusRegister8(grActiveVoices, $DF);  { 1723:0478 }

  SetGusVoice(0);                  { 1723:047d }
  Save0 := GetGusRegister16(grStartAddrHigh);  { 1723:0482 }
  SetGusRegister16(grStartAddrHigh, $16D8);    { 1723:048d }

  SetGusVoice(1);                  { 1723:0492 }
  Save1 := GetGusRegister16(grStartAddrHigh);  { 1723:0497 }
  SetGusRegister16(grStartAddrHigh, $0F83);    { 1723:04a2 }

  SetGusVoice(0);                                              { 1723:04a7 }
  if (GetGusRegister16(grStartAddrHigh) and $1FFF) <> $16D8 then goto Fin; { 1723:04b2 }
  SetGusVoice(1);                                              { 1723:04bb }
  if (GetGusRegister16(grStartAddrHigh) and $1FFF) <> $0F83 then goto Fin; { 1723:04c6 }
  ProbeUltrasound := True;                                     { 1723:04cd }
Fin:

  SetGusVoice(0);                { 1723:04d3 }
  SetGusRegister16(grStartAddrHigh, Save0);  { 1723:04db }
  SetGusVoice(1);                { 1723:04e0 }
  SetGusRegister16(grStartAddrHigh, Save1);  { 1723:04e8 }
  asm STI end;                   { 1723:04eb }
end;

{ --------------------------------------------------------------------------
  1723:04f1 -- find a card.

  Compiler output. If GUSPort was configured, probe that and nothing else;
  otherwise walk the twelve jumper positions and take the first that answers.
  The candidate order is the table's, not numerical -- $0220 and $0240 are
  tried before $0200, presumably because they were the common settings.

  MIND THE SENSE OF THE RESULT -- IT IS INVERTED FROM WHAT IT LOOKS LIKE.
  This returns 1 when a card ANSWERED and 0 when none did, and 1084:0061
  passes that straight into driver slot +$1a. But the slot is an ERROR CODE:
  109c:0021 selects a driver only when the probe returns ZERO.

  So the value that means "I found a GUS" is the value that means "do not
  use this driver". That is not a bug -- there is no path in this program
  where a GUS probe result reaches 109c:0021, because the config file names
  the driver and the GUS registers first regardless. But it is a trap for
  anyone reading this routine on its own, and it caught this reconstruction
  once already: three separate producers were read, all agreed, and all were
  read backwards. See VTDriver for the consumer that settles it.
  -------------------------------------------------------------------------- }
{ The 1.39b release has this as DetectUltrasound. It sets the result TRUE
  first and leaves by `Exit` the moment a port answers; only falling out of
  the search clears it. A `Found` local and a `repeat` were both wrong -- the
  result is assigned directly and the search is a FOR. }
function DetectUltrasound : Boolean;
var
  I : Word;
begin
  DetectUltrasound := True;  { 1723:04f5 }

  if GUSPort = $FFFF then  { 1723:04f9  not configured }
  begin
    for I := 1 to 12 do  { 1723:0500, 1723:051f }
    begin
      GUSPort := GUSPorts[I];        { 1723:050f }
      if ProbeUltrasound then Exit;  { 1723:0519 }
    end
  end
  else
    if ProbeUltrasound then Exit;  { 1723:052a }

  DetectUltrasound := False;  { 1723:0530  nothing answered }

end;

{ --------------------------------------------------------------------------
  1723:0539 -- a byte address into the GF1's split form. Near, private.

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
  A := (A shl 9) and $1FFFFE00;  { 1723:054b .. 1723:0553 }
end;

{ --------------------------------------------------------------------------
  1723:0565 -- set a voice's pan. Near, private.

  Compiler output. $FF means "leave it alone" and anything above $7F is
  clamped to $7F, so the caller can pass a don't-care without a separate
  flag. The stored value is compared against the table first and the write is
  skipped when nothing changed -- a pan write costs a register select and the
  card is slow.
  -------------------------------------------------------------------------- }
const
  { DS:$066a in v1.51 -- 128 words, read out of the image, as 1.31b's were.

    **RETUNED AGAIN BETWEEN 1.31b AND 1.51**, and only entry 0 survives -- $1800, the
    same value that is the only agreement with the 1.39b release. Every other word
    differs from BOTH earlier tables.

    THE NOTE THAT STOOD HERE WAS RIGHT AND STILL LET THIS THROUGH. It said "the
    release settled the SHAPE of the routine below and is worth nothing for its data",
    which is correct, and it is exactly why carrying 1.31b's numbers forward was never
    safe either: a table nothing computes has no witness but the image it came from.
    **Data transcribed from one version is a measurement of that version only** -- the
    routine that reads it is identical in all three, so no comparison of code could
    ever have said the numbers were stale. 253 of the 256 bytes were wrong and the
    unit verified byte-for-byte throughout.

    A logarithmic volume ramp: entry 0 is silence and the rest climb to $FE30. }
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
  1723:0565 -- set a voice's volume, ramping to it rather than jumping.

  THIS WAS TRANSCRIBED AS `SetPan` AND IT IS NOTHING OF THE KIND. The old
  version was seven lines against the original's 253 bytes, took its
  parameters in the wrong order, and wrote the wrong register. The release
  has it as ChangeVol(Channel, Vol, Ramp) and the frame agrees exactly:
  RET 6, with Channel at [BP+8], Vol at [BP+6] and Ramp at [BP+4].

  DS:$389a is LastVolumes, not the mode table -- also misnamed here until now.

  It never jumps the volume. It reads where the ramp currently is, points the
  ramp at the new value from whichever end it has to travel, and sets the
  direction bit in the volume-control register accordingly. $40 is the
  decreasing-ramp bit.
  -------------------------------------------------------------------------- }
procedure ChangeVol(Channel, Vol, Ramp : Byte);
var
  Oldv : Byte;  { [BP-1] }
begin
  if (Vol > 127) and (Vol <> $FF) then  { 1723:0569, 1723:056f }
    Vol := 127;                         { 1723:0575 }

  if (Vol <> $FF) and (LastVolumes[Channel] <> Vol) then  { 1723:0579, 058d }
  begin
    LastVolumes[Channel] := Vol;  { 1723:059f }

    SetGusRegister8(grVolumeControl, 3);            { 1723:05a7  ramp stopped }
    Oldv := Hi(GetGusRegister16(grCurrentVol));  { 1723:05ac  where it is  }

    if Oldv <> Hi(VolumeTable[Vol]) then  { 1723:05bd }
    begin
      if Oldv > Hi(VolumeTable[Vol]) then  { 1723:05d2  going down   }
      begin
        SetGusRegister8(grRampEnd, Oldv);                  { 1723:05e1  ramp end     }
        SetGusRegister8(grRampStart, Hi(VolumeTable[Vol]));  { 1723:05f4  ramp start   }
      end
      else
      begin
        SetGusRegister8(grRampStart, Oldv);                  { 1723:05ff }
        SetGusRegister8(grRampEnd, Hi(VolumeTable[Vol]));  { 1723:0612 }
      end;

      SetGusRegister16(grCurrentVol, Word(Oldv) shl 8);  { 1723:0620 }
      SetGusRegister8(grRampRate, Ramp);               { 1723:0629  ramp rate    }

      if Oldv > Hi(VolumeTable[Vol]) then                            { 1723:0635 }
        SetGusRegister8(grVolumeControl, GetGusRegister8(grVolumeControl) and not 3 or $40)  { 1723:064a }
      else
        SetGusRegister8(grVolumeControl, GetGusRegister8(grVolumeControl) and not 3 and not $40) { 1723:065b }
    end
  end
end;

{ --------------------------------------------------------------------------
  1723:0662 -- push one voice's stored addresses at the card. Near, private.

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
  Cur  := LastVoiceStart[Voice];  { 1723:0670 }
  Loop := LastLoopStart[Voice];   { 1723:0688 }
  Fin  := LastVoiceEnd[Voice];    { 1723:06a0 }

  SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) or $03);  { 1723:06b2  stop it first }

  SwapGusAddress(Cur);                   { 1723:06c0 }
  SetGusRegister16(grCurrentAddrLow, Cur and $FFFF);  { 1723:06d3 }
  SetGusRegister16(grCurrentAddrHigh, Cur shr 16);     { 1723:06e9 }

  SwapGusAddress(Fin);                   { 1723:06f1 }
  SetGusRegister16(grEndAddrLow, Fin and $FFFF);  { 1723:0704 }
  SetGusRegister16(grEndAddrHigh, Fin shr 16);     { 1723:071a }

  if Loop = -1 then                                     { 1723:071d  no loop }
    SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) and $F7)  { 1723:0733 }
  else
  begin
    SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) or $08);  { 1723:0742  looping }
    SwapGusAddress(Loop);                               { 1723:074a }
    SetGusRegister16(grStartAddrLow, Loop and $FFFF);              { 1723:075d }
    SetGusRegister16(grStartAddrHigh, Loop shr 16);                 { 1723:0773 }
  end;
end;

{ --------------------------------------------------------------------------
  1723:077a -- THE DEFERRED SWEEP. Installed as the timer 1 callback by
  TriggerVoice, and where every voice change actually reaches the card.

  Two passes over the active flags, and the split matters.

  THE FIRST PASS programs each flagged voice -- addresses, pan, ramp -- and
  clears its flag. THE SECOND PASS collects the voices that are now ready
  into a command list at DS:$06c1, two bytes per entry, and only then walks
  that list writing voice-select and control-register pairs back to back.

  Separating them is what makes the card see one burst. Programming a voice
  is a dozen register writes with the voice stopped; starting it is two. Doing
  all the slow work first and all the starts together means voices that were
  meant to begin on the same tick actually do, instead of drifting apart by
  however long the register writes took.

  THE POSITION READ-BACK at 1723:08a2 reads a voice's current address twice
  and only accepts it when two consecutive reads agree -- the same distrust
  of a live counter as 1b24's Count8, solved by retry rather than by
  judging the difference.
  -------------------------------------------------------------------------- }
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
  { DECLARATION ORDER SETS THE FRAME, and this one is settled byte by byte
    against 1723:077a..08c2. `ENTER 8,0` reserves eight bytes and the original
    touches five of them:

      [BP-1]  i        the FOR variable -- AND the kicked voice, see below
      [BP-2]  k        the kicked voice's control byte
      [BP-3]  Vol
      [BP-4]  padding: Turbo Pascal rounds the running size up to even
              before allocating a Word, so three bytes become four
      [BP-6]  j        the Word, occupying [BP-6] and [BP-5]
      [BP-7]  the compiler's own temporary for the FOR limit
      [BP-8]  padding to the eight ENTER reserves

    THREE BYTES, NOT FOUR. This declared a separate `KickVoice` and the frame
    says there is no such variable: 1723:0856 writes the kicked voice into
    [BP-1], which is i's slot. Turbo Pascal does not reuse a dead local's slot,
    so the same slot means the same variable -- the original reuses the loop
    counter, which it has finished with by then, rather than declaring another
    byte. A fourth byte pushes k to [BP-7] and the FOR temporary to [BP-8],
    which is what eleven of this unit's divergences were.

    THE RELEASE AGREES, INDEPENDENTLY. 1.39b's RestartChannels declares
    `i, k, Vol : BYTE; j : WORD` -- three bytes then a word -- and then writes
    `i := buf[j-1]; k := buf[j]`, reusing the loop variable for the kicked
    voice just as the shared slot says. It also declares `Scr` (ABSOLUTE, so no
    frame space) and `First : BOOLEAN`, and 1.31 has NEITHER: a Boolean here
    would take [BP-7] and push the FOR temporary to [BP-8], and the original
    reads its limit from [BP-7]. A later addition, so it is left out. }
  i, k, Vol : Byte;
  j         : Word;
  { NEW IN v1.51, AND THIS FILE PREDICTED IT. The note above records that 1.39b
    declares `First : BOOLEAN` here, that a Boolean would take [BP-7] and push
    the FOR temporary to [BP-8], and that v1.31b has neither -- "a later
    addition, so it is left out". v1.51 IS that later addition: 1911:0837 is
    `MOV BYTE PTR [BP-07],01` right after the second pass, and without a local
    there the third pass's limit temporary takes -$07 and every reference in
    the routine is one byte out.

    Nothing in the segment READS it, so the name is the release's rather than
    anything measured here. }
  First     : Boolean;
begin
  GUSStopTimer1;  { 1723:077f }

  { --- pass one: program everything that is flagged ------------------ }
  { A REAL `for`, not a repeat emulating one. The release has
    `FOR i := 0 TO GUSChannels-1 DO IF VoicesChanged[i] THEN ...` and Turbo
    Pascal evaluates the limit into a temporary, which is what 1723:0787
    stores -- no `Last` variable is involved. }
  for i := 0 to GUSChannels - 1 do  { 1723:0787, 1723:07e0 }
    if VoicesChanged[i] <> 0 then   { 1723:07a1 }
    begin
      SetGusVoice(i);          { 1723:07ac }
      ChangeSample(i);         { 1723:07b3 }
      Vol := LastVolumes[i];   { 1723:07bd }
      LastVolumes[i] := 0;     { 1723:07cb }
      ChangeVol(i, Vol, $1F);  { 1723:07d0 .. 07da }
    end;

  { --- pass two: collect the ready voices, then start them together -- }
  j := 0;                           { 1723:07e7 }
  for i := 0 to GUSChannels - 1 do  { 1723:07f0, 1723:083e }
    if VoicesChanged[i] <> 0 then   { 1723:0809 }
    begin
      Inc(j, 2);                                   { 1723:0810 }
      CmdList[j - 1] := i;                         { 1723:081d }
      CmdList[j] := GetGusRegister8(grVoiceControl) and $FC;  { 1723:082b  clear the stop bits }
      { v1.51 DOES NOT CLEAR IT HERE. The clear moved into the third pass
        below, which is the pass that actually starts the voice. }
    end;

  { ------------------------------------------------------------------
    1911:0837..0888 -- A THIRD PASS, WHERE v1.31b HAD SIXTY BYTES OF HAND
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
  First := True;                      { 1911:0837 }

  for i := 0 to GUSChannels - 1 do    { 1911:083b, 1911:0881 }
    if VoicesChanged[i] <> 0 then     { 1911:085a }
    begin
      SetGusVoice(i);                                  { 1911:0865 }
      SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) and $FC);  { 1911:086c..0872 }
      VoicesChanged[i] := 0                            { 1911:087c }
    end
end;

{ --------------------------------------------------------------------------
  1723:08e6 -- start a voice with a loop. THE ENTRY 12ba's ring flushes to.

  Compiler output, and it programs NOTHING. It stores the three addresses,
  raises the active flag, records the pan, and points the timer 1 callback at
  RestartChannels. The card is touched on the next tick, not now.

  The stores are held under PUSHF/CLI -- not because the card cares, but
  because RestartChannels runs from an interrupt and must not find a half-
  written table.

  ChangeVoiceParams is called first, for the frequency and pan, and this adds
  the addresses on top.

  SEVEN PARAMETERS, AND THIS ORDER. The list was transcribed backwards, as
  `(EndA, LoopA, StartA, Mode, Freq, Pan, Voice)`, which happens to total the
  same 22 bytes and so still emitted a correct `RETF $16` -- every frame
  reference inside was wrong instead. The frame settles it: Voice at [BP+1a],
  Vol at [BP+18], Freq at [BP+14], Pan at [BP+12], then the three addresses
  at [BP+0e], [BP+0a] and [BP+06]. That is the release's
  `TriggerVoice(Channel, Vol, Freq, Panning, VoiceStart, LoopStart, VoiceEnd)`
  exactly.

  AND THE VOLUME IS RECORDED, NOT THE PAN. 1723:095c reads [BP+18], which is
  Vol -- the pan has already gone to the card through ChangeVoiceParams. The
  backwards list made this look like `LastVolumes[Voice] := Pan` because [BP+08]
  was where Pan sat.
  -------------------------------------------------------------------------- }
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
  SetGusVoice(Voice);                      { 1723:08ed  all register writes
                                             below apply to this voice }
  ChangeVoiceParams(Voice, 0, Freq, Pan);  { 1723:0901  volume 0: silent until
                                             the restart ramps it up }

  asm PUSHF; CLI end;                { 1723:0904  the five updates are one
                                       transaction -- see above }
  LastVoiceStart[Voice]  := StartA;  { 1723:0916  DS:$371a }
  LastLoopStart[Voice] := LoopA;     { 1723:092e  DS:$379a }
  LastVoiceEnd[Voice]  := EndA;      { 1723:0946  DS:$381a }
  VoicesChanged[Voice]   := 1;       { 1723:0955  DS:$395a }
  LastVolumes[Voice] := Vol;         { 1723:0964  DS:$389a }
  asm POPF end;                      { 1723:0968 }

  { Arm the timer that will do the actual restart. The routine pointer is
    installed each time rather than once, so whatever the timer last ran does
    not decide what happens now. }
  GUSTimer1RutPtr := @RestartChannels;  { 1723:096f  DS:$058a }
  GUSInitTimer1($F6);                   { 1723:0979  $F6 is the countdown, not
                                          a register number }
end;

{ --------------------------------------------------------------------------
  1723:0980 -- set a live voice's frequency and pan, without restarting it.

  Compiler output. Does nothing at all if the voice is not already active,
  which is what lets the mixer send pitch changes for voices that may have
  finished without having to track that itself.

  THE FREQUENCY IS RATE-RELATIVE. The value written is

      (Freq * (GUSDivisor div 2)) div (GUSDivisor div 2 + Freq')

  worked out in 32 bits from DS:$0588, so the same module plays at the same
  pitch whatever mixing rate the card was set to. The previous value is kept
  in a table and the write skipped when it has not moved.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  1723:0980 -- set a running voice's volume, pitch and pan.

  FOUR PARAMETERS, NOT THREE. This was transcribed as
  `StartVoice(Freq, Pan, Voice)` with the volume and the pan sharing one
  argument. The frame says otherwise -- RETF $0A with Channel at [BP+0e],
  Vol at [BP+0c], Freq at [BP+08] and Panning at [BP+06] -- and the release
  has it as ChangeVoiceParams(Channel, Vol, Freq, Panning).

  THE FIRST TEST IS NOT AN EXIT. 1723:0996 branches on VoicesChanged and both
  arms do work: a voice already queued for restart just has its volume
  recorded, because RestartChannels will apply it; a voice that is not queued
  gets the ramp applied immediately.
  -------------------------------------------------------------------------- }
procedure ChangeVoiceParams(Channel, Vol : Byte; Freq : LongInt;
                            Panning : Byte);
begin
  SetGusVoice(Channel);  { 1723:0987 }

  if VoicesChanged[Channel] <> 0 then  { 1723:0991 }
  begin
    if Vol <> $FF then  { 1723:0998 }
    begin
      if Vol > $7F then Vol := $7F;  { 1723:09a4 }
      LastVolumes[Channel] := Vol;   { 1723:09b2 }
    end
  end
  else
    ChangeVol(Channel, Vol, $1F);  { 1723:09b8 .. 09c2 }

  if (Freq <> -1) and (LastFreqs[Channel] <> Freq) then  { 1723:09c5, 09e3 }
  begin
    LastFreqs[Channel] := Freq;  { 1723:09fd  DS:$38ba }
    SetGusRegister16(grFreqControl, ((Freq shl 9) + LongInt(GUSDivisor shr 1))
                    div LongInt(GUSDivisor shr 1));  { 1723:0a1b .. 0a31 }
  end;

  if LastPans[Channel] <> Panning then  { 1723:0a45 }
  begin
    LastPans[Channel] := Panning;         { 1723:0a54  DS:$393a }
    SetGusRegister8(grPanPosition, Panning shr 4);  { 1723:0a63 }
  end;
end;

{ --------------------------------------------------------------------------
  1723:0a6a -- how many voices, and what that costs in sample rate.

  Compiler output. The GF1 divides one fixed clock between however many
  voices are enabled, so asking for fewer voices buys a higher rate:

      GUSDivisor := 617400 div GUSChannels

  Clamped to 14..32. Fourteen is the fewest the chip allows; thirty-two is
  all it has. Register $0E takes the count in the top bits with the low bit
  set, hence `+ $C0 - 1`.
  -------------------------------------------------------------------------- }
procedure SetGusChannels(N : Byte);
begin
  if N > $20 then N := $20        { 1723:0a6d  at most 32 }
  else if N < $14 then N := $14;  { 1723:0a79  at least 14 }

  SetGusRegister8(grActiveVoices, $C0 + N - 1);  { 1723:0a8f }
  GUSDivisor    := 617400 div N;      { 1723:0aa3  1ba1:0a2e }
  GUSChannels := N;                   { 1723:0aae }
end;

end.
