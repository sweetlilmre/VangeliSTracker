{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  THE SOUND BLASTER DRIVER, and unlike the Gravis one it has real work to do.

  A SOUND BLASTER PLAYS FROM HOST MEMORY OVER DMA. The card is handed a buffer
  and a length, drains it at the sample rate, and raises an interrupt when it
  is done -- so the driver must keep refilling ahead of the card, and its poll
  actually moves data rather than only counting ticks. Compare DevGus, whose
  card holds the samples itself and whose poll does nothing.

  FOUR DEVICES OUT OF ONE UNIT. The same code registers four entries -- mono
  and stereo, DMA and non-DMA -- differing only in which routines go in which
  record slots. The core sees four drivers; there is one implementation.

  THE HARDWARE IS NEXT DOOR. Every port write and every DSP command lives in
  the SoundBlaster unit; this one decides WHEN, and calls in.

  [re] SEGMENT 1b22. **COMPLETE: 1,617 of 1,617 bytes**, seventeen blocks, 569
  pending fixups, no real difference anywhere.

  [re] BOTH BLOCKING NAMES ARE RESOLVED. They were:

    * `DevInitSbDMA` -- `1b22:0352` calls `1bff:1090`, nine bytes past
      `SelectOutput` at `1bff:1087`. Two entry points into one tail, and the
      release names them `DevInitSbNonDMA` and `DevInitSbDMA`: 1087 forces
      mono and ignores its arguments (a non-DMA device is always mono) while
      1090 picks by its first. SOUNDDEV.ASM now publishes the second label --
      a label emits no bytes, and SOUNDDEV verifying unchanged is the check.
    * `InitTimer` -- **it does not exist.** The release calls it as DMASBInit's
      last act; 1b22:03b7 and 03bc are the two flag stores with nothing between
      them and DMASet, so there is no such call. The release also runs DMASet
      FIRST; 1.31 runs it AFTER SbPlaySample. Two measured differences where a
      missing name was assumed.

  [re] It pairs with the release's `LIB/DEVSB.PAS` and stands to `19a0`
  exactly as `1084` (DevGus) stands to `1723` (GUS) -- a device unit calling a
  hardware unit -- which is the structural pairing CONTINUATION.md recorded long
  before either was read. All nine of its entry points into `19a0` exist.

  ---------------------------------------------------------------------------
  [re] THE ROUTINE MAP, AND THE INITIALISATION SECTION IS WHAT NAMED IT.

  [re] `1b22:048a` onward fills four device records field by field with far
  addresses, exactly as `106e:0101` does -- and those addresses ARE the routine
  table. It named eleven of the sixteen routines outright:

      [re] 0000  Name (device 1)     0005 000a 000f  the other three
      0014  SetVars             NEAR -- ends in RET, which is why survey.py's
                                far-return sweep does not see it
      002b  DevPoll             empty
      0030  DMAIrq              the interrupt handler; ends 007d
      007f  DMASBGetRealFreq    -> 0138
      013c  DMASBProGetRealFreq -> 0202
      0206  DMASBCalcTimerData  NEAR
      02c2  SbMonoDetect        -> 02e5
      02e7  SbStereoDetect      -> 031d
      0321  DMASBInit           NEAR
      03c5  DMASBMonoInit       -> 03dd
      03e1  DMASBSterInit       -> 03f9
      03fd  DMASBMixInit        -> 0415
      0419  DMASBMix2Init       -> 0431
      0435  DMASBChgHz          -> 043e
      0442  DMASBEnd            -> 0486
      048a  the initialisation section

  [re] ONE `IRET` IN THE WHOLE SEGMENT, at 007d, so there is exactly one interrupt
  handler and it is 78 bytes. That single byte-pattern search settled a layout
  question the far-return census could not: a handler ends in IRET and a near
  routine in RET, and survey.py counts neither.

  [re] FOUR DEVICES, NOT THE RELEASE'S SIX. The records are at DS:$09f4, $0a2e,
  $0a68 and $0aa2 -- **58 bytes apart, which is SizeOf(TSoundDevice) exactly**,
  `Next` at +$36 included -- and the four `InitDevice` calls at 0630..064e
  register them in REVERSE, $0aa2 first. The release also has `SBData` (non-DMA)
  and `DMAPASData` (Pro Audio Spectrum); 1.31 has neither, and correspondingly
  no `SBInit`, `SBChgHz`, `SBEnd`, `DMAPASMonoInit` or `DMAPASEnd`. What
  survives is the four DMA-SB variants: mono, stereo, and two mixed stereo.

  AND ITS FOUR `Name` FUNCTIONS ARE EMPTY -- five bytes each, `PUSH BP /
  MOV BP,SP / LEAVE / RETF`, with no assignment at all. That is a String
  function whose CALLER pops the hidden result pointer, which is why the RETF
  carries no operand (the rule 14b9's `GetInsidePath` established). DEVGUS
  writes `DevName := ''` and costs twelve bytes; these write nothing.
  =========================================================================== }

unit DevSB;

interface

{ THE FOUR SB PRO MIXER BYTES ARE THE ONLY THING THIS UNIT EXPORTS, and they are
  exported because VTCFG WRITES them -- its `MasterVol`, `DACVol`, `FMVol` and `Filter`
  keys. They also have to be here rather than in the implementation for a second and
  independent reason: they are the FIRST four bytes of this unit's DGROUP block, at
  $09ea, and a unit lays its interface data down before its implementation data. So the
  visibility and the address agree.

  The image holds `ff ff ff 00` there -- three volumes at full and the filter off, which
  is the release's own default. Everything else this unit declares stays private and
  follows on at $09ee. }
const
  SbProMixMasterVol : Byte    = 255;  { DS:$0a92  the VT.CFG `MasterVol` key   }
  SbProMixDACVol    : Byte    = 255;  { DS:$0a93  ... `DACVol`                 }
  SbProMixFMVol     : Byte    = 255;  { DS:$0a94  ... `FMVol`                  }
  SbProMixFilter    : Boolean = False;{ DS:$0a95  ... `Filter`                 }

implementation

uses
  VTDriver, SoundDevices, SoundBlaster, Hardware;

{ VTDRIVER declares the record's eight callbacks as bare `Pointer`s, because
  most consumers only store them. DMASBCalcTimerData is the one place in the
  tree that CALLS one, so it needs the shape -- and it must be FAR, which is
  what the compiler-switch bracket below is for: the build compiles with /$F-
  and a near procedure type would emit a near indirect call. }
{$F+}
type
  TGetRealFreqProc = function(Hz : Word) : Word;
{$F-}

const
  DMASBDevID     : TDevID = 'DMA-SB-Mono';
  DMASBSterDevID : TDevID = 'DMA-SB-Stereo';
  DMASBMixDevID  : TDevID = 'Mix-DMA-SB-Stereo';
  DMASBMix2DevID : TDevID = 'Mix2-DMA-SB-Stereo';

{ TEN BYTES SIT BELOW THE FOUR DEVICE RECORDS, and the layout is what put them
  there. This unit's DGROUP block runs $09ea..$0adb -- VTGlobal's `NoBanner` is at
  $09e8 and SoundBlaster's first port at $0adc -- and the records themselves are at
  $09f4, $0a2e, $0a68 and $0aa2, so exactly ten bytes precede them. `OldDMAIrq` used
  to be declared AFTER the records, which put its four bytes past the end of the block
  and made this unit four bytes too long; the other six were not here at all.

  THE RELEASE NAMES ALL SIX AND THE IMAGE CONFIRMS FOUR OF THEM OUTRIGHT. `LIB/DEVSB.PAS`
  declares, in this order, `SbProMixMasterVol = 255`, `SbProMixDACVol = 255`,
  `SbProMixFMVol = 255`, `SbProMixFilter = FALSE`, then `OldDMAIrq = NIL` and
  `DMAPlacedInBuf = 0` -- and the original holds `ff ff ff 00` at $09ea..$09ed. Three
  volumes at full and the filter off is exactly what a mixer's defaults look like.

  The release's seventh, `Old83 : BYTE`, is ABSENT, and the ten bytes are what say so:
  4 + 4 + 2 leaves no room for it. That is consistent with what else is missing -- it
  belongs to `DMAPASData`, the Pro Audio Spectrum device this file already records 1.31
  as not having.

  THE FOUR MIXER BYTES WERE DECLARED IN VTCFG, at these exact addresses, because that
  is the unit that WRITES them -- its `MasterVol`, `DACVol`, `FMVol` and `Filter` keys.
  But VTCfg's own block is $0240..$02c3, nowhere near, so it cannot have owned them;
  it now reaches them through this unit, which is also the direction the link order
  allows (DevSB finishes long before VTCfg). }
const
  { DS:$09ee -- the saved vector, NIL while the handler is not hooked. Both DMASBInit
    and DMASBEnd test it, which is what makes it the "am I hooked?" flag rather than
    merely a saved pointer. Its address used to be quoted as $0bd8, which is inside
    SoundDevices' block and cannot have been this unit's. }
  OldDMAIrq         : Pointer = nil;  { DS:$09ee                               }

  { DS:$09f2 -- the release's name. Nothing in the transcribed tree reads or writes it,
    so it is here for its two bytes and its name; the ten-byte arithmetic is what says
    it exists. }
  DMAPlacedInBuf    : Word    = 0;    { DS:$09f2                               }

const
  DMASBData     : TSoundDevice = ( DevID : 'DMA-SB-Mono';        DMA : True );
  DMASBSterData : TSoundDevice = ( DevID : 'DMA-SB-Stereo';      DMA : True );
  DMASBMixData  : TSoundDevice = ( DevID : 'Mix-DMA-SB-Stereo';  DMA : True );
  DMASBMix2Data : TSoundDevice = ( DevID : 'Mix2-DMA-SB-Stereo'; DMA : True );

{ 0000, 0005, 000a, 000f.  Four empty String functions, one per device. }
function  DMASBName : TDevID; far;      begin end;
function  DMASBSterName : TDevID; far;  begin end;
function  DMASBMixName : TDevID; far;   begin end;
function  DMASBMix2Name : TDevID; far;  begin end;

{ 0014..002a.  NEAR -- it ends in `RET`, not `RETF`, so it is an
  implementation-only helper and nothing outside the SEGMENT reaches it.

  It copies three port numbers out of this card's hardware unit into the
  PLAYER CORE's copies, which is how 1a17 drives the DSP without knowing which
  card it is:

    1b22:0017  [0b02] -> [0be8]   SoundBlaster.DSPWritePort -> SoundDevices'
    1b22:001d  [0b06] -> [0bea]   DSP8AckPort
    1b22:0023  [0afe] -> [0bec]   DSPLifePort

  All six addresses were already known from the two units independently, so
  this routine is a six-way cross-check that both are right. }
procedure SetVars;
begin
  SoundDevices.DSPWritePort := SoundBlaster.DSPWritePort;   { 0017 }
  SoundDevices.DSP8AckPort  := SoundBlaster.DSP8AckPort;    { 001d }
  SoundDevices.DSPLifePort  := SoundBlaster.DSPLifePort     { 0023 }
end;

{ 002b..002f.  Empty, and the release's is too. }
procedure DevPoll; far;
begin
end;

{ 0030..007d.  THE DMA INTERRUPT HANDLER, transcribed VERBATIM per the standing
  rule. It is `assembler` and names no parameter, so it gets no frame -- there
  is no `PUSH BP` at 0030, which is what distinguishes it from every other
  routine here.

  Equivalent Pascal, REFERENCE ONLY and not to be substituted for the asm:
    acknowledge the 8-bit DMA IRQ by reading DSP8AckPort and DSPLifePort;
    DMAIrqWatch := 0;
    if DMAStop then begin DMAStopped := DMAStop; DeviceIdling := DMAStop end
                else SbPlaySample($FA00, True);
    if Lo(SbIrq) = $0A then Port[$A0] := $20;   -- slave EOI
    Port[$20] := $20;                           -- master EOI

  THE SLAVE EOI IS CONDITIONAL ON THE IRQ NUMBER, which is the giveaway that
  this is hand-written: `CMP AL,0Ah / JNZ` reaches past the second controller's
  end-of-interrupt only for IRQ 10 and above. Turbo Pascal's `interrupt`
  directive emits neither the EOI nor a test for it.

  AND IT PUSHES ONLY WHAT IT USES. TP's `interrupt` prologue saves every
  register; this one saves AX, DS and DX at entry, and ES/BX/CX/DI/SI only
  around the SbPlaySample call. That is a hand-written handler economising on
  the common path. }
procedure DMAIrq; assembler;
asm
                CLI                             { 0030 }
                PUSH    AX                      { 0031 }
                PUSH    DS                      { 0032 }
                PUSH    DX                      { 0033 }
                MOV     AX,SEG @DATA            { 0034 }
                MOV     DS,AX                   { 0037 }

                MOV     DX,[SoundBlaster.DSP8AckPort]   { 0039 }
                IN      AL,DX                   { 003d }
                MOV     DX,[SoundBlaster.DSPLifePort]   { 003e }
                IN      AL,DX                   { 0042 }

                XOR     AL,AL                   { 0043 }
                MOV     [DMAIrqWatch],AL        { 0045 }

                MOV     AL,[DMAStop]            { 0048 }
                AND     AL,AL                   { 004b }
                JZ      @@play                  { 004d }

                MOV     [DMAStopped],AL         { 004f }
                MOV     [DeviceIdling],AL       { 0052 }
                JMP     @@eoi                   { 0055 }

@@play:         PUSH    ES                      { 0057 }
                PUSH    BX                      { 0058 }
                PUSH    CX                      { 0059 }
                PUSH    DI                      { 005a }
                PUSH    SI                      { 005b }
                PUSH    0FA00h                  { 005c }
                PUSH    1                       { 005f }
                CALL    SbPlaySample            { 0061 }
                POP     SI                      { 0066 }
                POP     DI                      { 0067 }
                POP     CX                      { 0068 }
                POP     BX                      { 0069 }
                POP     ES                      { 006a }

@@eoi:          MOV     AX,[SbIrq]              { 006b }
                CMP     AL,0Ah                  { 006e }
                JNZ     @@master                { 0070 }
                MOV     AL,20h                  { 0072 }
                OUT     0A0h,AL                 { 0074 }
@@master:       MOV     AL,20h                  { 0076 }
                OUT     20h,AL                  { 0078 }

                POP     DX                      { 007a }
                POP     DS                      { 007b }
                POP     AX                      { 007c }
                IRET                            { 007d }
end;

{ [re] 007f..013b.  RETF 2.  Three LongInt divisions, which survey.py counts at
  00bf, 00ea and 0105 -- one per `DIV` in the release's body. }
function DMASBGetRealFreq(Hz : Word) : Word; far;
var
  i    : Word;
  NHz1 : Word;
  NHz2 : Word;
begin
  if Hz < 4000 then Hz := 4000;
  if (not DoHiSpeed) or (SbStereo and not Sb16Detected) then
    if Hz > 21800 then Hz := 21800;

  i := Hi(65536 - (256000000 div Hz));
  NHz1 := 1000000 div (256 - i);
  NHz2 := 1000000 div (256 - i - 1);

  if Abs(Integer(NHz1 - Hz)) > Abs(Integer(NHz2 - Hz)) then NHz1 := NHz2;

  DMASBGetRealFreq := NHz1
end;

{ 013c..0205.  RETF 2.  The stereo device's rate calculator -- half the clock,
  because a stereo DMA block carries two samples per tick. Divisions at 0189,
  01b4, 01cf. }
function DMASBProGetRealFreq(Hz : Word) : Word; far;
var
  i    : Word;
  NHz1 : Word;
  NHz2 : Word;
begin
  if Sb16Detected then
    begin
      DMASBProGetRealFreq := DMASBGetRealFreq(Hz);
      Exit
    end;

  if Hz < 4000 then Hz := 4000;
  if (not DoHiSpeed) or SbStereo then
    if Hz > 21800 then Hz := 21800;

  i := Hi(65536 - (128000000 div Hz));
  NHz1 :=  500000 div (256 - i);
  NHz2 :=  500000 div (256 - i - 1);

  if Abs(Integer(NHz1 - Hz)) > Abs(Integer(NHz2 - Hz)) then NHz1 := NHz2;

  DMASBProGetRealFreq := NHz1
end;

{ [re] 0206..02c1.  NEAR.  `020f` calls 1bff:037f -- SoundDevices.CalcTimerData --
  which is the release's first line. Four more LongInt divisions follow. }
procedure DMASBCalcTimerData(Hz : Word);
begin
  CalcTimerData(PeriodicHz);                     { 020f }

  Hz := TGetRealFreqProc(ActiveDevice^.GetRealFreqProc)(Hz);

  if SbStereo and not Sb16Detected then
    begin
      TimeConst := Hi(65536 - 128000000 div Hz);
      SoundHz   :=  500000 div (256 - Word(TimeConst))
    end
  else
    begin
      TimeConst := Hi(65536 - 256000000 div Hz);
      SoundHz   := 1000000 div (256 - Word(TimeConst))
    end;

  { 1b22:02be -- NEW IN v1.51, AND IT IS THE LAST STATEMENT. `DEC BYTE PTR
    [0c36]` sits after the whole if/else, so it applies to both arms: the time
    constant the Sound Blaster is actually given is one below the one the
    sample rate was computed from. The four other references to this variable
    are byte for byte what v1.31b has -- 0253, 0256, 029b, 029e -- so this one
    instruction is the entire change to the routine. }
  Dec(TimeConst)
end;

{ 02c2..02e6.  RETF.  Device 1's Autodetect. }
function SbMonoDetect : Boolean; far;
begin
  SbRegInit;                                     { 02c6 }
  SbProInit;                                     { 02cb }
  Sb16Init;                                      { 02d0 }
  { 02d5 -- `MOV byte [0bbd],00`, and $0bbd is SoundDevices.Stereo. The
    DETECTORS set the mixing mode, which the release's do not: a five-byte
    store sits between the three inits and the result in both of them, 0 here
    and 1 in the stereo one. }
  Stereo := False;                               { 02d5 }
  SbMonoDetect := SbRegDetect                    { 02da }
end;

{ 02e7..0320.  RETF.  Devices 2, 3 and 4 all point their Autodetect here. }
function SbStereoDetect : Boolean; far;
begin
  SbRegInit;                                     { 02eb }
  SbProInit;                                     { 02f0 }
  Sb16Init;                                      { 02f5 }
  Stereo := True;                                { 02fa  MOV byte [0bbd],01 }
  SbStereoDetect := SbProDetect or Sb16Detect    { 02ff, 0308 }
end;

{ 0321..03c4.  NEAR.  The shared opener; the four FAR entry points below set
  Stereo/DevBits/MixMethod and fall into it.

  `OldDMAIrq = NIL` is the "not hooked yet" test -- the vector is saved and the
  IRQ enabled only once, however many times a device is opened. }
procedure DMASBInit(Hz : Word);
begin
  { **THE WHOLE ROUTINE IS GUARDED**, not just the vector hooking. 0322 tests
    OldDMAIrq and 032b jumps straight to the epilogue, so opening a second SB
    device while one is already open does NOTHING at all. The release guards
    only the SetIRQVector pair and re-runs everything else. }
  if OldDMAIrq <> nil then Exit;                 { 0322..032d }

  SbStereo := Stereo;                            { 032e }

  SbRegInit;                                     { 0334 }
  SbProInit;                                     { 0339 }
  Sb16Init;                                      { 033e }

  { The release sends sdcTurnOnSpeaker here; 0343 goes straight to SetVars. }
  SetVars;                                       { 0343 }

  DMAChannel := SbDMAChan;                       { 0346 }

  DevInitSbDMA(SbStereo, 8);                     { 034c..0352 }

  { AND THE RELEASE'S INNER GUARD IS STILL HERE TOO. 0357 tests OldDMAIrq a
    SECOND time, and it cannot fail: the routine already returned at 032b if it
    was non-nil. The author added the outer guard and left the inner one where
    it was -- redundant, and transcribed as found. }
  if OldDMAIrq = nil then                        { 0357..0360 }
    begin
      OldDMAIrq := SetIRQVector(SbIrq, @DMAIrq); { 0361..036c }
      EnableIRQ(SbIrq)                           { 037c }
    end;

  SbProSetStereo(SbStereo);                      { 0385 }
  DMASBCalcTimerData(Hz);

  { THE RELEASE PUTS `DMASet` FIRST AND CALLS `InitTimer` LAST; 1.31 DOES
    NEITHER. 0390 is SbUpdateTimeConst, 039b SbPlaySample and only then 03b2
    DMASet -- so the DMA controller is programmed AFTER the DSP has been told
    to play, not before. And 03b7/03bc are the two flag stores, with nothing
    between them and DMASet: there is no InitTimer call anywhere in the
    routine. Both are measured, not inferred. }
  SbUpdateTimeConst;                             { 0390 }
  { 0395 pushes [0ba4], which is DMABufferSize -- NOT a literal 10. The release
    reads `SbPlaySample(10, FALSE)` with DMABufferSize commented out beside the
    literal -- the real argument parked next to a debugging one. 1.31 has the
    real one. A comment in
    the release is not a record of what 1.31 did; this is the third time that
    has mattered in two segments. }
  SbPlaySample(DMABufferSize, False);            { 0395..039d }

  DMASet(SbDMAChan, $58, DMABuffer, DMABufferSize);   { 03a0..03b6 }

  DMAStopped := False;                           { 03b7 }
  DMAStop    := False                            { 03bc }
end;

{ 03c5..03e0.  RETF 2.  Device 1's InitRut. }
procedure DMASBMonoInit(Hz : Word); far;
begin
  Stereo    := False;
  DevBits   := 8;
  MixMethod := 0;
  DMASBInit(Hz)
end;

{ 03e1..03fc.  RETF 2.  Device 2's. }
procedure DMASBSterInit(Hz : Word); far;
begin
  Stereo    := True;
  DevBits   := 8;
  MixMethod := 1;
  DMASBInit(Hz)
end;

{ 03fd..0418.  RETF 2.  Device 3's. }
procedure DMASBMixInit(Hz : Word); far;
begin
  Stereo    := True;
  DevBits   := 8;
  MixMethod := 2;
  DMASBInit(Hz)
end;

{ 0419..0434.  RETF 2.  Device 4's. }
procedure DMASBMix2Init(Hz : Word); far;
begin
  Stereo    := True;
  DevBits   := 8;
  MixMethod := 3;
  DMASBInit(Hz)
end;

{ 0435..0441.  RETF 2.  All four devices share it. }
procedure DMASBChgHz(Hz : Word); far;
begin
  DMASBCalcTimerData(Hz)
end;

{ 0442..0489.  RETF.  All four devices share it. The wait loop spins with
  interrupts enabled until the handler reports the DMA stopped, then restores
  the vector. `PUSHF/STI ... POPF` brackets it so the caller's interrupt flag
  is preserved -- 1.31 drops the release's `KbdKeyPressed` escape, which is a
  tracker's, and keeps `DeviceIdling`. }
procedure DMASBEnd; far;
begin
  if OldDMAIrq <> nil then
    begin
      DMAStopped := False;
      DMAStop    := True;

      { **THERE IS NO WAIT LOOP.** 0458 is PUSHF/STI and 045a is POPF, back to
        back with nothing between them -- the release spins here on
        "while not DMAStopped and not DeviceIdling and not KbdKeyPressed", and
        1.31 does not wait for the DMA to stop at all. The STI is undone by the
        POPF one byte later, so the pair is a no-op left behind when the loop
        between them went. }
      asm PUSHF; STI end;                        { 0458 }
      asm POPF end;                              { 045a }

      { [re] 045f -- CALLF 1d0c:02f0, which HARDWARE.PAS already names DMAReset.
        The release has this line COMMENTED OUT; 1.31 calls it. }
      DMAReset(SbDMAChan);                       { 045f }

      SetIRQVector(SbIrq, OldDMAIrq);            { 0470 }
      OldDMAIrq := nil
    end;
  DisableIRQ(SbIrq)                              { 0481 }
end;

{ ---------------------------------------------------------------------------
  048a..0650 -- FOUR DEVICE RECORDS FILLED AND REGISTERED.

  Every field is a far address written as two words, and reading them off is
  what produced the routine map at the top of this file.

  [re] Device 1's, in order:

    +$16 Name             1b22:0000
    +$1a Autodetect       1b22:02c2   SbMonoDetect
    +$1e InitRut          1b22:03c5   DMASBMonoInit
    +$22 ChgHzProc        1b22:0435   DMASBChgHz
    +$26 GetRealFreqProc  1b22:007f   DMASBGetRealFreq
    +$2a TimerHandler     **1bff:1008** -- the CORE's shared handler
    +$2e PollRut          1b22:002b   DevPoll
    +$32 EndRut           1b22:0442   DMASBEnd

  THE TIMER HANDLER IS THE CORE'S, NOT THIS UNIT'S, and that is the opposite of
  the GUS. CONTINUATION.md records that "1.39b's GUS driver points its
  TimerHandler at the core's shared handler where 1.31 points at its own" --
  here 1.31's SB driver points at the core's. A DMA card is driven by its own
  DMA interrupt and only needs the core's periodic tick; the GUS is polled.

  [re] THE STEREO DEVICES USE THE OTHER RATE CALCULATOR: device 2's
  GetRealFreqProc is 1b22:013c, DMASBProGetRealFreq, where device 1's is
  1b22:007f.

  REGISTRATION IS IN REVERSE DECLARATION ORDER -- $0aa2, $0a68, $0a2e, $09f4 --
  and `InitDevice` pushes onto the front of the list while selecting only when
  nothing is selected yet, so the FIRST to register wins. Mix2 is therefore the
  default Sound Blaster mode.
  --------------------------------------------------------------------------- }
begin
  DMASBData.Name             := @DMASBName;              { 048b }
  DMASBData.Autodetect       := @SbMonoDetect;           { 0498 }
  DMASBData.InitRut          := @DMASBMonoInit;          { 04a5 }
  DMASBData.ChgHzProc        := @DMASBChgHz;             { 04b2 }
  DMASBData.GetRealFreqProc  := @DMASBGetRealFreq;       { 04bf }
  DMASBData.TimerHandler     := @SoundDevices.SharedPoll;      { 04cc  1bff:1008 }
  DMASBData.PollRut          := @DevPoll;                { 04d9 }
  DMASBData.EndRut           := @DMASBEnd;               { 04e6 }

  DMASBSterData.Name             := @DMASBSterName;      { 04f3 }
  DMASBSterData.Autodetect       := @SbStereoDetect;     { 0500 }
  DMASBSterData.InitRut          := @DMASBSterInit;      { 050d }
  DMASBSterData.ChgHzProc        := @DMASBChgHz;         { 051a }
  DMASBSterData.GetRealFreqProc  := @DMASBProGetRealFreq;{ 0527 }
  DMASBSterData.TimerHandler     := @SoundDevices.SharedPoll;
  DMASBSterData.PollRut          := @DevPoll;
  DMASBSterData.EndRut           := @DMASBEnd;

  DMASBMixData.Name             := @DMASBMixName;
  DMASBMixData.Autodetect       := @SbStereoDetect;
  DMASBMixData.InitRut          := @DMASBMixInit;
  DMASBMixData.ChgHzProc        := @DMASBChgHz;
  DMASBMixData.GetRealFreqProc  := @DMASBProGetRealFreq;
  DMASBMixData.TimerHandler     := @SoundDevices.SharedPoll;
  DMASBMixData.PollRut          := @DevPoll;
  DMASBMixData.EndRut           := @DMASBEnd;

  DMASBMix2Data.Name             := @DMASBMix2Name;
  DMASBMix2Data.Autodetect       := @SbStereoDetect;
  DMASBMix2Data.InitRut          := @DMASBMix2Init;
  DMASBMix2Data.ChgHzProc        := @DMASBChgHz;
  DMASBMix2Data.GetRealFreqProc  := @DMASBProGetRealFreq;
  DMASBMix2Data.TimerHandler     := @SoundDevices.SharedPoll;
  DMASBMix2Data.PollRut          := @DevPoll;
  DMASBMix2Data.EndRut           := @DMASBEnd;

  SoundDevices.InitDevice(@DMASBMix2Data);               { 0630 }
  SoundDevices.InitDevice(@DMASBMixData);                { 063a }
  SoundDevices.InitDevice(@DMASBSterData);               { 0644 }
  SoundDevices.InitDevice(@DMASBData)                    { 064e }
end.
