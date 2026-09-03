{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  THE SOUND BLASTER HARDWARE LAYER: every port write and every DSP command,
  and nothing about when to make them.

  TALKING TO A SOUND BLASTER IS A CONVERSATION, not a register poke. The card
  has a DSP -- a small processor with its own command set -- reached through
  four ports, and every exchange has the same shape: wait until it says it is
  ready, write a byte, wait again. A command that takes arguments is several of
  those in a row. That handshake is why so much of this unit is loops.

  EVERYTHING HERE IS BOUNDED AND GIVES UP QUIETLY. Each wait counts down and
  proceeds anyway on exhaustion, because this code runs inside an interrupt on
  a machine where a card that never answers must not hang the music. A late
  sample is better than a locked machine.

  IT ALSO HAS TO FIND THE CARD. The base port, the IRQ and the DMA channel are
  not discoverable in any general way on an ISA machine, so detection is a
  matter of writing to a likely port and seeing whether anything replies --
  which is what the reset and copyright-string routines are for.

  WHAT IT DOES NOT DO is decide when to play anything. That is the device unit
  next door, which stands to this exactly as DevGus stands to the GUS layer.

  FIVE OF THE RELEASE'S NINETEEN ARE ABSENT, and the RETF counts are what say
  so: MixerSetVolume (RETF 6) and MixerGetVolume (RETF 10) appear nowhere, and
  SbProDone, SbProSetFilter and Sb16Done have no room between the returns that
  bracket them. A player sets a sample rate and starts DMA; it never touches a
  mixer volume, never toggles the output filter, and never tears the card
  down.
  =========================================================================== }

unit SoundBlaster;

interface

{ --------------------------------------------------------------------------
  THE PORT VARIABLES. Typed constants, as the release declares them, computed
  from a $220 base at compile time and rewritten by the detection code.

  ALL OF THEM ARE DECLARED, because SbRegDetect writes all of them. Their
  addresses are DGROUP fixups, so none of this is measurable byte by byte --
  the ADDRESSES below are what the instructions name and the VALUES are the
  release's.
  -------------------------------------------------------------------------- }
const
  CMS1DataPortOffset = $00;   CMS1AddrPortOffset = $01;
  CMS2DataPortOffset = $02;   CMS2AddrPortOffset = $03;
  MixAddrPortOffset  = $04;   MixDataPortOffset  = $05;
  FMStatPortOffset   = $08;   FMAddrPortOffset   = $08;
  FMDataPortOffset   = $09;
  LFMStatPortOffset  = $00;   LFMAddrPortOffset  = $00;
  LFMDataPortOffset  = $01;
  RFMStatPortOffset  = $02;   RFMAddrPortOffset  = $02;
  RFMDataPortOffset  = $03;
  DSPResetPortOffset = $06;   DSPReadPortOffset  = $0A;
  DSPLifePortOffset  = $0A;   DSPWStatPortOffset = $0C;
  DSPWritePortOffset = $0C;   DSPRStatPortOffset = $0E;
  DSP8AckPortOffset  = $0E;   DSP16AckPortOffset = $0F;
  CDDataPortOffset   = $10;   CDCmdPortOffset    = $10;
  CDStatPortOffset   = $11;   CDResetPortOffset  = $12;
  CDEnablePortOffset = $13;

{ --------------------------------------------------------------------------
  ALL TWENTY-EIGHT PORTS ARE PRESENT, AND `SbRegDetect` IS WHAT PROVES IT: the
  probe loop rewrites every one of them from the base it is trying, so each
  store names its variable's address outright. The block runs $0adc..$0b13:

    $0adc CMS1Data  $0ade CMS1Addr  $0ae0 CMS2Data  $0ae2 CMS2Addr
    $0ae4 MixAddr   $0ae6 MixData   $0ae8 FMStat    $0aea FMAddr   ...
    $0afa DSPReset  $0afc DSPRead   $0afe DSPLife   $0b00 DSPWStat
    $0b02 DSPWrite  $0b04 DSPRStat  ...             $0b12 CDEnable

  **AND $0adc + 27*2 IS $0b12, so the next Word is $0b14 -- which is SbPort.**
  The port block and the configuration block are contiguous and the arithmetic
  closes with nothing left over. One routine pinned this unit's whole DGROUP
  head, which no byte comparison could have done: every one of these is a
  fixup.

  1.31 KEEPS THE CD-ROM AND CM/S PORTS IT NEVER OTHERWISE USES. Nothing but the
  probe loop touches them; they are here because the release's loop sets them
  and 1.31's does too, store for store.
  -------------------------------------------------------------------------- }
const
  CMS1DataPort : Word = $220 + CMS1DataPortOffset;
  CMS1AddrPort : Word = $220 + CMS1AddrPortOffset;
  CMS2DataPort : Word = $220 + CMS2DataPortOffset;
  CMS2AddrPort : Word = $220 + CMS2AddrPortOffset;

  MixAddrPort  : Word = $220 + MixAddrPortOffset;
  MixDataPort  : Word = $220 + MixDataPortOffset;

  FMStatPort   : Word = $220 + FMStatPortOffset;
  FMAddrPort   : Word = $220 + FMAddrPortOffset;
  FMDataPort   : Word = $220 + FMDataPortOffset;

  LFMStatPort  : Word = $220 + LFMStatPortOffset;
  LFMAddrPort  : Word = $220 + LFMAddrPortOffset;
  LFMDataPort  : Word = $220 + LFMDataPortOffset;

  RFMStatPort  : Word = $220 + RFMStatPortOffset;
  RFMAddrPort  : Word = $220 + RFMAddrPortOffset;
  RFMDataPort  : Word = $220 + RFMDataPortOffset;

  DSPResetPort : Word = $220 + DSPResetPortOffset;
  DSPReadPort  : Word = $220 + DSPReadPortOffset;
  DSPLifePort  : Word = $220 + DSPLifePortOffset;
  DSPWStatPort : Word = $220 + DSPWStatPortOffset;
  DSPWritePort : Word = $220 + DSPWritePortOffset;
  DSPRStatPort : Word = $220 + DSPRStatPortOffset;
  DSP8AckPort  : Word = $220 + DSP8AckPortOffset;
  DSP16AckPort : Word = $220 + DSP16AckPortOffset;

  CDDataPort   : Word = $220 + CDDataPortOffset;
  CDCmdPort    : Word = $220 + CDCmdPortOffset;
  CDStatPort   : Word = $220 + CDStatPortOffset;
  CDResetPort  : Word = $220 + CDResetPortOffset;
  CDEnablePort : Word = $220 + CDEnablePortOffset;

{ --------------------------------------------------------------------------
  THE CONFIGURATION SETTINGS. These four were this file's whole contents while
  it was a declared stub, because `11bb`'s config keys and `109c`'s switches
  both write them. Their addresses are unchanged, and they now sit in the
  release's declaration order -- which the spacing corroborates: SbPort $0bbc,
  SbIrq $0bbe, SbDMAChan $0bc0, SbDefTimeout $0bc2, SbHiSpeed $0bc4 is the
  release's list with no gaps.
  -------------------------------------------------------------------------- }
const
  SbPort       : Word    = $FFFF;  { $FFFF means autodetect }
  SbIrq        : Word    = 7;
  SbDMAChan    : Word    = 1;
  SbDefTimeout : Word    = 5000;
  SbHiSpeed    : Boolean = True;

  { $0b1d..$0b20 -- FOUR "FORCE" FLAGS, and they were missing. The layout is what
    found them: SbHiSpeed is at $0b1c and SbVersionMin at $0b22, and the release
    declares exactly these four Booleans between the two, so the six bytes close with
    one pad at $0b21 for TP to word-align SbVersionMin. Each one forces a detection to
    succeed whether the hardware answers or not, which is what a beta player would want
    on a machine it cannot probe; all four are FALSE in the image.

    Nothing in the transcribed tree reads any of them -- 19a0's probes test the card,
    not these -- so they exist here for their four bytes and their names, and the names
    are the release's. A typed constant nothing references is normally smart-linked
    away; these survive because they sit inside a block whose neighbours are read. }
  SbForce      : Boolean = False;
  MixerForce   : Boolean = False;
  SbProForce   : Boolean = False;
  Sb16Force    : Boolean = False;  { pad at $0b21 }

const
  SbVersionMin : Byte       = 0;
  SbVersionMaj : Byte       = 0;
  SbVersionStr : String[ 5] = '';
  SbCopyright  : String[80] = '';
  SbResponse1  : Byte       = 0;
  SbResponse2  : Byte       = 0;
var
  SbVersion : Word absolute SbVersionMin;

{ --------------------------------------------------------------------------
  THE RUN-TIME STATE BLOCK, AND TWO KNOWN ADDRESSES FILL IN EVERY BYTE OF IT.
  `SbRegDetected` is $0b7e (00fd, 0103, 012d), `SbWorksOk` is $0b85 (006f,
  00af) and `DoHiSpeed` is $0b8c (0284). Laying the release's declaration
  order between them lands on both endpoints with nothing left over:

    $0c26 SbRegDetected  $0c27 SbRegInited  $0c28 SbProDetected
    $0c29 SbProInited    $0c2a Sb16Detected $0c2b Sb16Inited
    $0c2c MixerDetected  $0c2d SbWorksOk    <- endpoint
    $0c2e HSBlockSpecified (Word)           $0c30 Sb16BlockSpecified (Word)
    $0c32 SbStereo       $0c33 SbFilter     $0c34 DoHiSpeed  <- endpoint
    $0c35 Sb16Bit        $0c36 TimeConst

  Seven Booleans and two Words between two fixed points, arriving exactly.
  Same instrument as the port block above: the layout is unmeasurable byte by
  byte, so it is pinned by SPACING between the addresses instructions do name.
  -------------------------------------------------------------------------- }
const
  SbRegDetected      : Boolean = False;
  SbRegInited        : Boolean = False;
  SbProDetected      : Boolean = False;
  SbProInited        : Boolean = False;
  Sb16Detected       : Boolean = False;
  Sb16Inited         : Boolean = False;
  MixerDetected      : Boolean = False;

  { Cleared when a DSP wait times out; both loops write it, and that write is
    the only reason they compute `OR BL,BH` at all. }
  SbWorksOk          : Boolean = True;

  HSBlockSpecified   : Word    = 0;
  Sb16BlockSpecified : Word    = 0;
  SbStereo           : Boolean = False;
  SbFilter           : Boolean = False;
  DoHiSpeed          : Boolean = False;
  Sb16Bit            : Boolean = False;
  TimeConst          : Byte    = 0;

  DMAStart           : Boolean = False;
  DMAStop            : Boolean = False;
  DMAStopped         : Boolean = False;
  DMAIrqWatch        : Byte    = 0;

{ DSP commands and the one mixer register 1.31 touches. }
const
  sdcStartLSpeedDMA = $14;
  sdcSetTimeConst   = $40;
  sdcSetHSpeedSize  = $48;
  sdcStartHSpeedDMA = $91;
  sdcTurnOnSpeaker  = $D1;
  sdcTurnOffSpeaker = $D3;
  sdcGetDSPVersion  = $E1;
  sdcGetCopyright   = $E3;

  mxrOutSetting     = $0E;
  mxoStereoOn       = $02;

function  SbReset : Boolean;                                  { 0000 RETF   }
procedure SbWriteLoop(t : Word);                              { 005b RETF 2 }
procedure SbWriteByte(t : Word; b : Byte);                    { 0077 RETF 4 }
procedure SbReadLoop(t : Word);                               { 009b RETF 2 }
function  SbReadByte(t : Word) : Byte;                        { 00bb RETF 2 }
procedure SbWriteMixerReg(Reg, Val : Byte);                   { 00ce RETF 4 }
function  SbReadMixerReg(Reg : Byte) : Byte;                  { 00e5 RETF 2 }

{ --------------------------------------------------------------------------
  THE TWENTY-THREE ROUTINES, IN ADDRESS ORDER, PAIRED AGAINST THE RELEASE'S
  NINETEEN BY THEIR `RETF` COUNTS. **FIVE OF THE RELEASE'S ARE ABSENT** --
  `MixerSetVolume` (RETF 6) and `MixerGetVolume` (RETF 10) do not appear at
  all, and `SbProDone`, `SbProSetFilter` and `Sb16Done` have no room between
  the returns that bracket them. 19 - 5 = 14 after `SbRegDetect`, which is the
  far-return count exactly, and the surviving order is the release's own.

  A player sets the sample rate and starts DMA; it never touches a mixer
  volume, never turns the output filter on or off, and never tears the card
  down -- which is precisely the five that are gone.
  -------------------------------------------------------------------------- }
function  SbRegDetect : Boolean;                              { 00f9 RETF   }
procedure SbRegInit;                                          { 0257 RETF   }
procedure SbGetDSPVersion;                                    { 029c RETF   }
procedure SbGetCopyrightString;                               { 038f RETF   }
procedure SbSetTimeConst(tc : Byte);                          { 0422 RETF 2 }
procedure SbUpdateTimeConst;                                  { 048f RETF   }
procedure SbStartSampleLS(Len : Word; Cont : Boolean);        { 04a5 RETF 4 }
procedure SbStartSampleHS(Len : Word; Cont : Boolean);        { 04d3 RETF 4 }
procedure SbPlaySample(Len : Word; Cont : Boolean);           { 052b RETF 4 }
function  MixerDetect : Boolean;                              { 058b RETF   }
function  SbProDetect : Boolean;                              { 05e5 RETF   }
procedure SbProInit;                                          { 062f RETF   }
procedure SbProSetStereo(Stereo : Boolean);                   { 0643 RETF 2 }
function  Sb16Detect : Boolean;                               { 067c RETF   }
procedure Sb16Init;                                           { 06c6 RETF   }
procedure Sb16StartSample(Len : Word; Cont : Boolean);        { 06de RETF 4 }

implementation

{ **THE SOUNDBLASTER RESET, WHICH IS ALSO HOW THE CARD IS DETECTED.** There is
  no identifying register to read, so presence is established by resetting a card
  that may not be there and seeing whether anything answers. A DSP that is
  present pulls the reset line, waits, releases it, and then returns $AA on its
  read port; nothing else does.

  So the return value means "a SoundBlaster answered", and this same routine is
  called from SbRegDetect for exactly that purpose.

  TWO THINGS HERE LOOK LIKE MISTAKES AND ARE NOT:

  **The first read is thrown away.** `stat` is loaded from the status port and
  then immediately overwritten from the data port. That is the protocol, not a
  slip: the status port must be read before the data port is meaningful, and its
  value is of no interest once it has been read. Deleting the first line would
  change the sequence of bus cycles the card sees.

  **The empty `for` loop is the delay.** The card needs the reset line held for a
  short time and there is no timer available this early. It is CPU-speed
  dependent, which GUS.PAS's `GusDelay` deliberately is not -- that one uses `IN`
  because a bus cycle takes the same time whatever the processor does. The
  difference is worth knowing: this delay gets shorter on a faster machine, and
  the hundred iterations are a 1993 guess at "long enough".

  BOTH LOOPS ARE BOUNDED AND FAILURE IS SILENT. A hundred attempts, then give up
  and report False. A machine with no card must not hang here, and every caller
  treats a False as "no SoundBlaster" rather than as an error. }
function SbReset : Boolean;
const
  ready = $AA;                                     { what a live DSP answers }
var
  ct, stat : Byte;
begin
  Port[DSPResetPort] := 1;                         { assert reset }
  for ct := 1 to 100 do;                           { hold it -- see
                                                     the note above }
  Port[DSPResetPort] := 0;                         { release }

  stat := 0;
  ct   := 0;
  while (stat <> ready) and (ct < 100) do
    begin
      stat := Port[DSPRStatPort];                  { required, and
                                                     the value is discarded }
      stat := Port[DSPReadPort];                   { this is the one
                                                     that matters }
      Inc(ct)
    end;

  SbReset := stat = ready                          { True means a
                                                     card answered }
end;

{ Write one byte to the DSP, waiting for it to say it is ready.

  Equivalent Pascal, REFERENCE ONLY, never to be substituted for the asm:
    BX := t;  DX := DSPWritePort;
    repeat Dec(BX); until (BX = 0) or ((Port[DX] and $80) = 0);
    SbWorksOk := (BL or BH) <> 0; }
procedure SbWriteLoop(t : Word); assembler;
asm
                MOV     BX,t
                MOV     DX,[DSPWritePort]
@@lp:            DEC    BX
                 JZ     @@fin
                 IN     AL,DX
                 ADD    AL,AL
                 JC     @@lp
@@fin:          OR      BL,BH
                MOV     [SbWorksOk],BL
end;

{ Send a DSP command and its argument: two writes through the routine above.

  Note DX survives the second SbWriteLoop and carries DSPWritePort into the
  `OUT` at 0096 -- the value SbWriteLoop left in it. That is the routines
  cooperating through a register across a call, which no Pascal shape does. }
procedure SbWriteByte(t : Word; b : Byte); assembler;
asm
                MOV     AX,t
                PUSH    AX
                CALL    SbWriteLoop
                JNZ     @@ya

                MOV     DX,[DSPLifePort]
                IN      AL,DX

                MOV     AX,t
                PUSH    AX
                CALL    SbWriteLoop

@@ya:           MOV     AL,b
                OUT     DX,AL
end;

{ RETF 2.  SbWriteLoop's mirror -- the same loop against the READ
  status port, with the sense of the carry test inverted (JNC where the writer
  has JC), and it leaves DSPReadPort in DX for its caller. }
procedure SbReadLoop(t : Word); assembler;
asm
                MOV     BX,t
                MOV     DX,[DSPRStatPort]
@@lp:            DEC    BX
                 JZ     @@fin
                 IN     AL,DX
                 ADD    AL,AL
                 JNC    @@lp
@@fin:          OR      BL,BH
                MOV     [SbWorksOk],BL
                MOV     DX,[DSPReadPort]
end;

{ RETF 2. }
function SbReadByte(t : Word) : Byte; assembler;
asm
                MOV     AX,t
                PUSH    AX
                CALL    SbReadLoop
                JNZ     @@ya                    { displacement zero }
@@ya:           IN      AL,DX
end;

{ RETF 4.  Two ports, two writes, no frame arithmetic. }
procedure SbWriteMixerReg(Reg, Val : Byte); assembler;
asm
                MOV     DX,[MixAddrPort]
                MOV     AL,[Reg]
                OUT     DX,AL

                MOV     DX,[MixDataPort]
                MOV     AL,[Val]
                OUT     DX,AL
end;

{ RETF 2.  The same, reading. }
function SbReadMixerReg(Reg : Byte) : Byte; assembler;
asm
                MOV     DX,[MixAddrPort]
                MOV     AL,[Reg]
                OUT     DX,AL

                MOV     DX,[MixDataPort]
                IN      AL,DX
end;

{ ENTER 0006 -- Port, Lst and the Boolean result.

  THE PROBE LOOP, and the routine that pinned this unit's whole DGROUP head --
  see the note at the port declarations. `SbPort < $8000` at 010d is the
  release's autodetect test ($FFFF means "search", anything below $8000 means
  "use this one"), and the search range $210..$280 stepping $10 is the
  release's too. }
function SbRegDetect : Boolean;
var
  Port, Lst : Word;
begin
  SbRegDetect := SbRegDetected;
  if SbRegDetected then Exit;

  if SbPort < $8000 then
    begin
      Port := SbPort;
      Lst  := SbPort
    end
  else
    begin
      Port := $210;
      Lst  := $280
    end;

  while (not SbRegDetected) and (Port <= Lst) do
    begin
      CMS1DataPort := Port + CMS1DataPortOffset;
      CMS1AddrPort := Port + CMS1AddrPortOffset;
      CMS2DataPort := Port + CMS2DataPortOffset;
      CMS2AddrPort := Port + CMS2AddrPortOffset;

      MixAddrPort  := Port + MixAddrPortOffset;
      MixDataPort  := Port + MixDataPortOffset;

      FMStatPort   := Port + FMStatPortOffset;
      FMAddrPort   := Port + FMAddrPortOffset;
      FMDataPort   := Port + FMDataPortOffset;

      LFMStatPort  := Port + LFMStatPortOffset;
      LFMAddrPort  := Port + LFMAddrPortOffset;
      LFMDataPort  := Port + LFMDataPortOffset;

      RFMStatPort  := Port + RFMStatPortOffset;
      RFMAddrPort  := Port + RFMAddrPortOffset;
      RFMDataPort  := Port + RFMDataPortOffset;

      DSPResetPort := Port + DSPResetPortOffset;
      DSPReadPort  := Port + DSPReadPortOffset;
      DSPLifePort  := Port + DSPLifePortOffset;
      DSPWStatPort := Port + DSPWStatPortOffset;
      DSPWritePort := Port + DSPWritePortOffset;
      DSPRStatPort := Port + DSPRStatPortOffset;
      DSP8AckPort  := Port + DSP8AckPortOffset;
      DSP16AckPort := Port + DSP16AckPortOffset;

      CDDataPort   := Port + CDDataPortOffset;
      CDCmdPort    := Port + CDCmdPortOffset;
      CDStatPort   := Port + CDStatPortOffset;
      CDResetPort  := Port + CDResetPortOffset;
      CDEnablePort := Port + CDEnablePortOffset;

      SbRegDetected := SbReset;

      if not SbRegDetected then Inc(Port, $10)
    end;

  SbRegDetect := SbRegDetected
end;

{ RETF.  The release's body with BOTH of its commented-out blocks
  absent: 1.39b has a seven-line DSP handshake commented out at the top and a
  four-line hi-speed block commented out in the middle, and neither leaves a
  trace here.

  **`SbRegDone` IS ABSENT ENTIRELY.** The release puts it immediately after this
  routine. 0297 is this one's RETF, 0298..029b is four bytes of literal, and
  029c is SbGetDSPVersion's ENTER -- there is no room for it, and nothing in the
  SEGMENT calls it. }
procedure SbRegInit;
begin
  if not SbRegDetect then Exit;

  if not SbRegInited then
    begin
      SbGetDSPVersion;
      DoHiSpeed := (SbVersion > $200) and SbHiSpeed;
      SbWriteByte(SbDefTimeout, sdcTurnOnSpeaker)
    end;

  SbRegInited := True
end;

{ RETF, ENTER 0108 -- i, t, the String[2] and a 256-byte temporary
  for STR's result. The four bytes at 0298..029b are this routine's literal:
  the '.' and the '0' the version string is built from. }
procedure SbGetDSPVersion;
var
  i : Word;
  t : Word;
  s : String[2];
begin
  SbWriteByte(SbDefTimeout, sdcGetDSPVersion);
  t := 0;
  repeat
    SbVersionMaj := SbReadByte($FFFF);
    Inc(t)
  until ((SbVersionMaj <> $AA) and SbWorksOk) or (t >= 10);
  SbVersionMin := SbReadByte(SbDefTimeout);

  Str(SbVersionMaj, SbVersionStr);
  SbVersionStr := SbVersionStr + '.';
  Str(SbVersionMin, s);
  if SbVersionMin > 9 then SbVersionStr := SbVersionStr +       s
                      else SbVersionStr := SbVersionStr + '0' + s
end;

{ Read the card's copyright string, which is how its model is identified: an
  original, a Pro and a 16 answer differently, and there is no other way to
  ask. The string comes back one byte per DSP read until a NUL. }
procedure SbGetCopyrightString;
var
  t : Word;
begin
  SbWriteByte(SbDefTimeout, sdcGetCopyright);
  t := 0;
  repeat
    SbCopyright := Char(SbReadByte($FFFF));
    Inc(t)
  until ((SbCopyright[1] <> #$AA) and SbWorksOk) or (t = 10);

  while SbWorksOk and (Length(SbCopyright) < 80) do
    SbCopyright := SbCopyright + Char(SbReadByte(SbDefTimeout));

  Dec(SbCopyright[0])
end;

{ RETF 2.  Note `SbDefTimeout*4` on the data byte -- the time
  constant takes four times as long to accept as the command does. }
procedure SbSetTimeConst(tc : Byte);
begin
  if Sb16Detected then
    begin
      if Sb16Bit then
        SbWriteByte(SbDefTimeout, $D9)
      else
        SbWriteByte(SbDefTimeout, $DA)
    end;
  SbWriteByte(SbDefTimeout,   sdcSetTimeConst);
  SbWriteByte(SbDefTimeout*4, tc);
  TimeConst := 0;
  if Sb16Detected then
    if Sb16Bit then
      SbWriteByte(SbDefTimeout, $47)
    else
      SbWriteByte(SbDefTimeout, $45)
end;

{ RETF.  `TimeConst = 0` means "already applied". }
procedure SbUpdateTimeConst;
begin
  if TimeConst = 0 then Exit;
  SbSetTimeConst(TimeConst)
end;

{ RETF 4.  `Cont` is declared and never read -- the low-speed path
  cannot continue a block, so it restarts every time. }
procedure SbStartSampleLS(Len : Word; Cont : Boolean);
begin
  HSBlockSpecified := 0;

  SbWriteByte(SbDefTimeout, sdcStartLSpeedDMA);
  SbWriteByte(SbDefTimeout, Lo(Len));
  SbWriteByte(SbDefTimeout, Hi(Len))
end;

{ RETF 4. }
procedure SbStartSampleHS(Len : Word; Cont : Boolean);
begin
  if HSBlockSpecified <> Len then Cont := False;
  if not Cont then
    begin
      SbWriteByte(SbDefTimeout, sdcSetHSpeedSize);
      SbWriteByte(SbDefTimeout, Lo(Len));
      SbWriteByte(SbDefTimeout, Hi(Len));
      HSBlockSpecified := Len
    end;

  if not (Sb16Detected and Cont) then
    SbWriteByte(SbDefTimeout, sdcStartHSpeedDMA)
end;

{ RETF 4.  Called from 193a -- one of its nine entry points into
  this unit. `DEC(Len)` because a DMA count is always size minus one. }
procedure SbPlaySample(Len : Word; Cont : Boolean);
begin
  if Len < 10 then Exit;

  if SbStereo then Inc(Len, Len);
  Dec(Len);

  if Sb16Detected and (SbStereo or Sb16Bit) then
    Sb16StartSample(Len, Cont)
  else if DoHiSpeed then
    SbStartSampleHS(Len, Cont)
  else
    SbStartSampleLS(Len, Cont)
end;

{ RETF.  Writes 243 into the master-volume register and reads it
  back; a mixer that echoes it is present. The saved value is restored, so the
  probe is non-destructive. }
function MixerDetect : Boolean;
var
  SaveReg : Word;
  NewReg  : Word;
begin
  MixerDetect := MixerDetected;
  if not SbRegDetect or MixerDetected then Exit;

  SaveReg := SbReadMixerReg($22);
  SbWriteMixerReg($22, 243);
  NewReg  := SbReadMixerReg($22);

  if NewReg = 243 then
    MixerDetected := True;

  SbWriteMixerReg($22, SaveReg);

  MixerDetect := MixerDetected
end;

{ RETF.  A Pro is a card with a mixer and a DSP older than 4.00;
  a 4.00 or later with a mixer is a 16. The two detectors are the same test
  with the comparison reversed. }
function SbProDetect : Boolean;
begin
  SbProDetect := SbProDetected;
  if SbProDetected then Exit;

  if not SbRegInited then SbRegInit;

  SbProDetected := SbRegDetect and MixerDetect and (SbVersion < $400);
  SbProDetect   := SbProDetected
end;

{ RETF.  Called from 193a. }
procedure SbProInit;
begin
  if not SbProDetect then Exit;
  SbProInited := True
end;

{ RETF 2.  Called from 193a. `SbProDone` and `SbProSetFilter`
  bracket this routine in the release and neither is here -- 0642 is
  SbProInit's RETF and 067c is Sb16Detect's first byte, so there is no room. }
procedure SbProSetStereo(Stereo : Boolean);
var
  i : Byte;
begin
  if not SbProDetected then Exit;
  SbStereo := Stereo;
  i := SbReadMixerReg(mxrOutSetting);
  SbWriteMixerReg(mxrOutSetting, (i      and not mxoStereoOn) +
                                 (Byte(Stereo) * mxoStereoOn))
end;

{ RETF.  Called from 193a. }
function Sb16Detect : Boolean;
begin
  Sb16Detect := Sb16Detected;
  if Sb16Detected then Exit;

  if not SbRegInited then SbRegInit;

  Sb16Detected := SbRegDetect and MixerDetect and (SbVersion >= $400);
  Sb16Detect   := Sb16Detected
end;

{ RETF.  Called from 193a. The only caller of
  SbGetCopyrightString anywhere -- which is why that routine survives at all. }
procedure Sb16Init;
begin
  if not Sb16Detect then Exit;

  SbGetCopyrightString;

  Sb16Inited := True
end;

{ RETF 4.  The last routine in the SEGMENT; 076a..0770 is padding.
  `Sb16Done` is absent, as `SbProDone` is. }
procedure Sb16StartSample(Len : Word; Cont : Boolean);
begin
  if (not Cont) or (Sb16BlockSpecified <> Len) then
    begin
      if Sb16Bit then
        SbWriteByte(SbDefTimeout, $B6)
      else
        SbWriteByte(SbDefTimeout, $C6);
      if SbStereo then
        SbWriteByte(SbDefTimeout, $20)
      else
        SbWriteByte(SbDefTimeout, $00);
      SbWriteByte(SbDefTimeout, Lo(Len));
      SbWriteByte(SbDefTimeout, Hi(Len));
      Sb16BlockSpecified := Len
    end
  else
    begin
      if Sb16Bit then
        SbWriteByte(SbDefTimeout, $47)
      else
        SbWriteByte(SbDefTimeout, $45)
    end
end;

end.
