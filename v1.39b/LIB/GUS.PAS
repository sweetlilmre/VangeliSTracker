{****************************************************************************}
{                                                                            }
{ MODULE:         GUS                                                        }
{                                                                            }
{ DESCRIPTION:    This UNIT implements an interface to the GUS sound card.   }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet... ;-)                                         }
{                                                                            }
{ HISTORY:        29-Aug-1993 Creation/definition.                           }
{                                                                            }
{ (C) 1992,93 VangeliSTeam                                                   }
{____________________________________________________________________________}

UNIT GUS;

INTERFACE

CONST
  GUSPort     : WORD = $FFFF;
  GUSIrq      : WORD = 11;
  GUSChannels : BYTE = 32;
  GUSDivisor  : WORD = 19293;

  grDRAMLowIO       = $43;
  grDRAMHighIO      = $44;
  grTimerControl    = $45;
  grTimer1Count     = $46;
  grTimer2Count     = $47;
  grReset           = $4C;
  grActiveVoices    = $0E;
  grVoiceIRQ        = $0F;

  grVoiceControl    = $00;
  grFreqControl     = $01;
  grStartAddrHigh   = $02;
  grStartAddrLow    = $03;
  grEndAddrHigh     = $04;
  grEndAddrLow      = $05;
  grRampRate        = $06;
  grRampStart       = $07;
  grRampEnd         = $08;
  grCurrentVol      = $09;
  grCurrentAddrHigh = $0A;
  grCurrentAddrLow  = $0B;
  grPanPosition     = $0C;
  grVolumeControl   = $0D;

  RampFastRate = $1F;




PROCEDURE StartUltrasound;
FUNCTION  DetectUltrasound : BOOLEAN;
PROCEDURE DumpToUltrasound(VAR Src; Size: WORD; Dest: LONGINT; Signed: BOOLEAN);
PROCEDURE ChangeVoiceParams(Channel: BYTE; Vol: BYTE; Freq: LONGINT; Panning: BYTE);
PROCEDURE TriggerVoice(Channel: BYTE; Vol: BYTE; Freq: LONGINT; Panning: BYTE;
                       VoiceStart, LoopStart, VoiceEnd: LONGINT);
PROCEDURE SetGusChannels(Channels: BYTE);


CONST
  GUSTimer1RutPtr : POINTER = NIL;
  GUSTimer2RutPtr : POINTER = NIL;
VAR
  GUSTimer1Rut    : PROCEDURE ABSOLUTE GUSTimer1RutPtr;
  GUSTimer2Rut    : PROCEDURE ABSOLUTE GUSTimer2RutPtr;

PROCEDURE GUSInitTimer1(val: BYTE);
PROCEDURE GUSInitTimer2(val: BYTE);
PROCEDURE GUSStopTimer2;
PROCEDURE GUSStopTimer1;

PROCEDURE InitGusIRQ;
PROCEDURE DoneGusIRQ;




IMPLEMENTATION

USES Hardware, Debugging;




{ Basic procedures }

PROCEDURE SetGusVoice (Voice: BYTE); ASSEMBLER;
  ASM
                MOV     DX,[GUSPort]
                ADD     DX,102h
                MOV     AL,[Voice]
                OUT     DX,AL
  END;

FUNCTION GetGusRegister8 (Reg : BYTE) : BYTE; ASSEMBLER;
  ASM
                MOV     DX,[GUSPort]
                ADD     DX,103h
                MOV     AL,[Reg]
                CMP     AL,$40
                JNC     @@c1
                 ADD    AL,80h
        @@c1:   OUT     DX,AL
                ADD     DX,2
                IN      AL,DX
  END;

PROCEDURE SetGusRegister8 (Reg, Val : BYTE); ASSEMBLER;
  ASM
                MOV     DX,[GUSPort]
                ADD     DX,103h
                MOV     AL,[Reg]
                OUT     DX,AL
                ADD     DX,2
                MOV     AL,[Val]
                OUT     DX,AL
  END;

FUNCTION GetGusRegister16 (Reg : BYTE) : WORD; ASSEMBLER;
  ASM
                MOV     DX,[GUSPort]
                ADD     DX,103h
                MOV     AL,[Reg]
                CMP     AL,$40
                JNC     @@c1
                 ADD    AL,80h
        @@c1:   OUT     DX,AL
                INC     DX
                IN      AX,DX
  END;

PROCEDURE SetGusRegister16 (Reg: BYTE; Val : WORD); ASSEMBLER;
  ASM
                MOV     DX,[GUSPort]
                ADD     DX,103h
                MOV     AL,[Reg]
                OUT     DX,AL
                INC     DX
                MOV     AX,[Val]
                OUT     DX,AX
  END;

PROCEDURE GusDelay; ASSEMBLER;
  ASM
                MOV     DX,[GUSPort]
                IN      AL,DX
                IN      AL,DX
                IN      AL,DX
                IN      AL,DX
                IN      AL,DX
                IN      AL,DX
                IN      AL,DX
  END;









PROCEDURE DumpToUltrasound(VAR Src; Size: WORD; Dest: LONGINT; Signed: BOOLEAN);
  BEGIN
    SetGusRegister8 (grDRAMHighIO, Dest SHR 16);
    SetGusRegister16(grDRAMLowIO,  Dest AND $FFFF);

    ASM
                PUSH    DS
                MOV     CX,[Size]
                LES     DI,[Dest]
                MOV     BX,ES
                MOV     BH,[Signed]
                CMP     BH,1
                SBB     BH,BH
                SHL     BH,7
                MOV     DX,[GUSPort]
                LDS     SI,[Src]
                ADD     DX,103h
        @@loop:
                 MOV    AL,grDRAMLowIO
                 OUT    DX,AL
                 INC    DX
                 MOV    AX,DI
                 OUT    DX,AX

                 ADD    DX,3
                 LODSB
                 XOR    AL,BH
                 OUT    DX,AL
                 INC    DI
                 JNZ    @@c1
                  INC   BL
                  SUB   DX,4
                  MOV   AL,grDRAMHighIO
                  OUT   DX,AL
                  ADD   DX,2
                  MOV   AL,BL
                  OUT   DX,AL
                  ADD   DX,2
        @@c1:
                 SUB    DX,4
                 LOOP   @@loop

                POP     DS
    END;

  END;
















CONST
  TimerControl : BYTE = 0;
  TimerMask    : BYTE = 0;

PROCEDURE GUSInitTimer1(val: BYTE);
  BEGIN
    SetGusRegister8(grTimer1Count,  val);
    TimerControl := TimerControl OR 4;
    SetGusRegister8(grTimerControl, TimerControl);
    TimerMask := TimerMask OR 1;
    Port[GUSPort+8] := 4;
    Port[GUSPort+9] := TimerMask;
  END;


PROCEDURE GUSInitTimer2(val: BYTE);
  BEGIN
    SetGusRegister8(grTimer2Count,  val);
    TimerControl := TimerControl OR 8;
    SetGusRegister8(grTimerControl, TimerControl);
    TimerMask := TimerMask OR 2;
    Port[GUSPort+8] := 4;
    Port[GUSPort+9] := TimerMask;
  END;


PROCEDURE GUSStopTimer1;
  BEGIN
    TimerControl := TimerControl AND NOT 4;
    SetGusRegister8(grTimerControl, TimerControl);
    TimerMask := TimerMask AND NOT 1;
    Port[GUSPort+8] := 4;
    Port[GUSPort+9] := TimerMask;
  END;


PROCEDURE GUSStopTimer2;
  BEGIN
    TimerControl := TimerControl AND NOT 8;
    SetGusRegister8(grTimerControl, TimerControl);
    TimerMask := TimerMask AND NOT 2;
    Port[GUSPort+8] := 4;
    Port[GUSPort+9] := TimerMask;
  END;






PROCEDURE ServiceTimer1;
  BEGIN
    SetGusRegister8(grTimerControl, TimerControl AND NOT 4);
    SetGusRegister8(grTimerControl, TimerControl);
    IF GUSTimer1RutPtr <> NIL THEN
      GUSTimer1Rut;
  END;


PROCEDURE ServiceTimer2;
  BEGIN
    SetGusRegister8(grTimerControl, TimerControl AND NOT 8);
    SetGusRegister8(grTimerControl, TimerControl);
    IF GUSTimer2RutPtr <> NIL THEN
      GUSTimer2Rut;
  END;


PROCEDURE GUSIrqHandler; ASSEMBLER;
  ASM

                CLI

                PUSHA
                PUSH    ES
                PUSH    DS
{
                MOV     AX,$B800
                MOV     DS,AX
                INC     [WORD PTR 10]
}
                MOV     AX,SEG @Data
                MOV     DS,AX

                MOV     AL,$20
                OUT     $20,AL
                MOV     AH,[BYTE PTR GUSIrq]
                CMP     AH,8
                JC      @@c1
                 OUT    $A0,AL
        @@c1:   MOV     AL,AH
                XOR     AH,AH
                PUSH    AX
                CALL    DisableIRQ

        @@loop: CLI
                MOV     DX,[GUSPort]
                ADD     DX,6
                IN      AL,DX

                TEST    AL,00001100b
                JZ      @@fin

                STI

                TEST    AL,00000100b
                JZ      @@no1
                 PUSH   AX
                 CALL   ServiceTimer1
                 POP    AX
        @@no1:  TEST    AL,00001000b
                JZ      @@no2
                 PUSH   AX
                 CALL   ServiceTimer2
                 POP    AX
        @@no2:  JMP     @@loop

        @@fin:  MOV     AL,[BYTE PTR GUSIrq]
                XOR     AH,AH
                PUSH    AX
                CALL    EnableIRQ

                PUSH    grVoiceIRQ
                CALL    GetGusRegister8

                POP     DS
                POP     ES
                POPA
                IRET

  END;


CONST

  OldIrqHandler : POINTER = NIL;
  OldIrqState   : BOOLEAN = FALSE;
{
  i : WORD = 0;
  OldIrqHandler : ARRAY[2..15] OF POINTER = ( NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL, NIL );
  OldIrqState   : ARRAY[2..15] OF BOOLEAN = ( FALSE,FALSE,FALSE,FALSE,FALSE,FALSE,FALSE,
                                              FALSE,FALSE,FALSE,FALSE,FALSE,FALSE,FALSE);
}
  GusIRQInited  : BOOLEAN = FALSE;

PROCEDURE InitGusIRQ;
  BEGIN
    IF GusIRQInited THEN EXIT;
    GusIRQInited := TRUE;
{
    FOR i := 2 TO 15 DO
      BEGIN
        OldIrqState[i]   := IRQState(i);
        OldIrqHandler[i] := SetIrqVector(i, @GUSIrqHandler);
        EnableIRQ(i);
      END;
}
    OldIrqState   := IRQState(GUSIrq);
    OldIrqHandler := SetIrqVector(GUSIrq, @GUSIrqHandler);
    EnableIRQ(GUSIrq);
    GetGusRegister8(grVoiceIRQ);

  END;

PROCEDURE DoneGusIRQ;
  BEGIN
    IF NOT GusIRQInited THEN EXIT;
    GusIRQInited := FALSE;
{
    FOR i := 2 TO 15 DO
      BEGIN
        IF NOT OldIrqState[i] THEN
          DisableIRQ(GUSIrq);
        SetIrqVector(GUSIrq, OldIrqHandler[i]);
      END;
}
    IF NOT OldIrqState THEN
      DisableIRQ(GUSIrq);
    SetIrqVector(GUSIrq, OldIrqHandler);

  END;




















VAR
  LastVoiceStart : ARRAY[0..31] OF LONGINT;
  LastLoopStart  : ARRAY[0..31] OF LONGINT;
  LastVoiceEnd   : ARRAY[0..31] OF LONGINT;
  LastVolumes    : ARRAY[0..31] OF BYTE;
  LastFreqs      : ARRAY[0..31] OF LONGINT;
  LastPans       : ARRAY[0..31] OF BYTE;
  VoicesChanged  : ARRAY[0..31] OF BOOLEAN;






PROCEDURE StartUltrasound;
  VAR
    i : WORD;
  BEGIN
    FillChar(LastVoiceStart, SizeOf(LastVoiceStart), $FF);
    FillChar(LastLoopStart,  SizeOf(LastLoopStart),  $FE);
    FillChar(LastVoiceEnd,   SizeOf(LastVoiceEnd),   $FF);
    FillChar(LastVolumes,    SizeOf(LastVolumes),    $FF);
    FillChar(LastFreqs,      SizeOf(LastFreqs),      $FF);
    FillChar(LastPans,       SizeOf(LastPans),       $7F);
    FillChar(VoicesChanged,  SizeOf(VoicesChanged),  0);

    ASM
                MOV     DX,[GUSPort]
                MOV     AL,00001011b    ; { Turn off output, to avoid clicks. }
                OUT     DX,AL
    END;

    SetGusRegister8  (grReset, 0);          ; { Reset the GUS card. }
    GusDelay;
    SetGusRegister8  (grReset, 1);          ; { DAC turned off. }

    SetGusRegister8  (grActiveVoices, $C0+31);  ; { 32 voices }
    SetGusRegister16 (grDRAMLowIO, 0);
    SetGusRegister8  (grDRAMHighIO, 0);

    FOR i := 0 TO 31 DO
      BEGIN
        SetGusVoice(i);

        SetGusRegister8  (grVoiceControl , 3);     ; { Voice stopped }
        SetGusRegister8  (grVolumeControl, 3);
        IF GetGusRegister16(grCurrentVol) > $1800 THEN
          BEGIN
            SetGusRegister8  (grRampStart    , $18);
            SetGusRegister8  (grRampEnd      , HI(GetGusRegister16(grCurrentVol)));
            SetGusRegister8  (grRampRate     , RampFastRate);
            SetGusRegister8  (grVolumeControl, $40);   ; { Decreasing Ramp }
          END;
      END;

    SetGusRegister8  (grReset, 7);          ; { DAC turned on. }

    ASM
                MOV     DX,[GUSPort]
                MOV     AL,00001100b    ; { Turn on output }
                OUT     DX,AL
    END;

    SetGusChannels(GUSChannels);
  END;




FUNCTION ProbeUltrasound : BOOLEAN;
  VAR
    v0, v1 : WORD;
  LABEL
    Fin;
  BEGIN
    ProbeUltrasound := FALSE;

    ASM CLI END;

    SetGusRegister8  (grReset, 0);
    GusDelay;
    SetGusRegister8  (grReset, 7);
    SetGusRegister8  (grActiveVoices, $C0+31);

    SetGusVoice(0);
    v0 := GetGusRegister16(grStartAddrHigh);
    SetGusRegister16(grStartAddrHigh, $16D8);
    SetGusVoice(1);
    v1 := GetGusRegister16(grStartAddrHigh);
    SetGusRegister16(grStartAddrHigh, $0F83);

    SetGusVoice(0);
    IF (GetGusRegister16(grStartAddrHigh) AND $1FFF) <> $16D8 THEN GOTO Fin;
    SetGusVoice(1);
    IF (GetGusRegister16(grStartAddrHigh) AND $1FFF) <> $0F83 THEN GOTO Fin;

    ProbeUltrasound := TRUE;
Fin:
    SetGusVoice(0);
    SetGusRegister16(grStartAddrHigh, v0);
    SetGusVoice(1);
    SetGusRegister16(grStartAddrHigh, v1);

    ASM STI END;

  END;




FUNCTION DetectUltrasound : BOOLEAN;
  CONST
    GUSPorts : ARRAY[1..12] OF WORD = ( $220, $240, $200, $210, $230, $250,
                                        $260, $270, $280, $290, $2A0, $2B0 );
  VAR
    i : WORD;
  BEGIN
    DetectUltrasound := TRUE;

    IF GUSPort = $FFFF THEN
      FOR i := 1 TO 12 DO
        BEGIN
          GUSPort := GUSPorts[i];
          IF ProbeUltrasound THEN EXIT;
        END
    ELSE
      IF ProbeUltrasound THEN EXIT;

    DetectUltrasound := FALSE;

  END;

(*
        SetGusRegister8  (grVoiceControl   , 3);
        SetGusRegister16 (grFreqControl    , 0);
        SetGusRegister16 (grStartAddrLow   , 0);
        SetGusRegister16 (grStartAddrHigh  , 0);
        SetGusRegister16 (grEndAddrLow     , 0);
        SetGusRegister16 (grEndAddrHigh    , 0);
        SetGusRegister8  (grRampStart      , 0);
        SetGusRegister8  (grRampEnd        , 0);
        SetGusRegister16 (grCurrentVol     , 0);
        SetGusRegister8  (grRampRate       , 00111111b);
        SetGusRegister16 (grCurrentAddrLow , 0);
        SetGusRegister16 (grCurrentAddrHigh, 0);
        SetGusRegister8  (grPanPosition    , 7);
        SetGusRegister8  (grVolumeControl  , 00000000b);
*)







PROCEDURE SwapGusAddress(VAR Addr: LONGINT);
  BEGIN
    Addr := (Addr SHL 9) AND $1FFFFE00;
  END;

PROCEDURE ChangeVol(Channel, Vol, Ramp: BYTE);
  CONST
    VolumeTable : ARRAY[0..127] OF WORD =
      (
6144,              
{ $01000 } {a$8FF0,}{ $01DFB } $9DF0,  { $02BF7 } $A5F0,  { $039F3 } $ACF0,
{ $047EF } $B1F0,  { $055EB } $B570,  { $063E7 } $B8F0,  { $071E3 } $BC70,  
{ $07FDF } $BFF0,  { $08DDB } $C1B0,  { $09BD7 } $C370,  { $0A9D3 } $C530,  
{ $0B7CF } $C6F0,  { $0C5CB } $C8B0,  { $0D3C7 } $CA70,  { $0E1C3 } $CC30,  
{ $0EFBF } $CDF0,  { $0FDBB } $CFB0,  { $10BB7 } $D0B0,  { $119B3 } $D190,  
{ $127AF } $D270,  { $135AB } $D350,  { $143A7 } $D430,  { $151A3 } $D510,  
{ $15F9F } $D5F0,  { $16D9B } $D6D0,  { $17B97 } $D7B0,  { $18993 } $D890,  
{ $1978F } $D970,  { $1A58B } $DA50,  { $1B387 } $DB30,  { $1C183 } $DC10,  
{ $1CF7E } $DCF0,  { $1DD7A } $DDD0,  { $1EB76 } $DEB0,  { $1F972 } $DF90,  
{ $2076E } $E030,  { $2156A } $E0A0,  { $22366 } $E110,  { $23162 } $E180,  
{ $23F5E } $E1F0,  { $24D5A } $E260,  { $25B56 } $E2D0,  { $26952 } $E340,  
{ $2774E } $E3B0,  { $2854A } $E420,  { $29346 } $E490,  { $2A142 } $E500,  
{ $2AF3E } $E570,  { $2BD3A } $E5E0,  { $2CB36 } $E650,  { $2D932 } $E6C0,  
{ $2E72E } $E730,  { $2F52A } $E7A0,  { $30326 } $E810,  { $31122 } $E880,  
{ $31F1E } $E8F0,  { $32D1A } $E960,  { $33B16 } $E9D0,  { $34912 } $EA40,  
{ $3570E } $EAB0,  { $3650A } $EB20,  { $37306 } $EB90,  { $38102 } $EC00,  
{ $38EFD } $EC70,  { $39CF9 } $ECE0,  { $3AAF5 } $ED50,  { $3B8F1 } $EDC0,  
{ $3C6ED } $EE30,  { $3D4E9 } $EEA0,  { $3E2E5 } $EF10,  { $3F0E1 } $EF80,  
{ $3FEDD } $EFF0,  { $40CD9 } $F030,  { $41AD5 } $F060,  { $428D1 } $F0A0,  
{ $436CD } $F0D0,  { $444C9 } $F110,  { $452C5 } $F140,  { $460C1 } $F180,  
{ $46EBD } $F1B0,  { $47CB9 } $F1F0,  { $48AB5 } $F220,  { $498B1 } $F260,  
{ $4A6AD } $F290,  { $4B4A9 } $F2D0,  { $4C2A5 } $F300,  { $4D0A1 } $F340,  
{ $4DE9D } $F370,  { $4EC99 } $F3B0,  { $4FA95 } $F3E0,  { $50891 } $F420,  
{ $5168D } $F450,  { $52489 } $F490,  { $53285 } $F4C0,  { $54081 } $F500,  
{ $54E7C } $F530,  { $55C78 } $F570,  { $56A74 } $F5A0,  { $57870 } $F5E0,  
{ $5866C } $F610,  { $59468 } $F650,  { $5A264 } $F680,  { $5B060 } $F6C0,  
{ $5BE5C } $F6F0,  { $5CC58 } $F730,  { $5DA54 } $F760,  { $5E850 } $F7A0,  
{ $5F64C } $F7D0,  { $60448 } $F810,  { $61244 } $F840,  { $62040 } $F880,  
{ $62E3C } $F8B0,  { $63C38 } $F8F0,  { $64A34 } $F920,  { $65830 } $F960,  
{ $6662C } $F990,  { $67428 } $F9D0,  { $68224 } $FA00,  { $69020 } $FA40,  
{ $69E1C } $FA70,  { $6AC18 } $FAB0,  { $6BA14 } $FAE0,  { $6C810 } $FB20,  
{ $6D60C } $FB50,  { $6E408 } $FB90,  { $6F204 } $FBC0,  { $70000 } $FC00

      );
  VAR
    Oldv : BYTE;
  BEGIN
    IF (Vol > 127) AND (Vol <> $FF) THEN Vol := 127;

    IF (Vol <> $FF) AND (LastVolumes[Channel] <> Vol) THEN
      BEGIN
        LastVolumes[Channel] := Vol;
        IF Channel = 2 THEN
          BEGIN
            WriteSNum(Channel, $4F);
            WriteSNum(Vol, $1F);
          END;
        SetGusRegister8(grVolumeControl, 3);
        Oldv := HI(GetGusRegister16(grCurrentVol));
        IF Oldv <> HI(VolumeTable[Vol]) THEN
          BEGIN
            IF Oldv > HI(VolumeTable[Vol]) THEN
              BEGIN
                SetGusRegister8(grRampEnd      , Oldv);
                SetGusRegister8(grRampStart    , HI(VolumeTable[Vol]));
              END
            ELSE
              BEGIN
                SetGusRegister8(grRampStart    , Oldv);
                SetGusRegister8(grRampEnd      , HI(VolumeTable[Vol]));
              END;

            SetGusRegister16(grCurrentVol  , WORD(Oldv) SHL 8);
            SetGusRegister8(grRampRate     , Ramp);

            IF Oldv > HI(VolumeTable[Vol]) THEN
              SetGusRegister8(grVolumeControl, GetGusRegister8(grVolumeControl) AND (NOT 3) OR $40)
            ELSE
              SetGusRegister8(grVolumeControl, GetGusRegister8(grVolumeControl) AND (NOT 3) AND NOT $40);
          END;

      END;

  END;

PROCEDURE ChangeSample(Channel: BYTE);
  VAR
    VoiceStart,
    LoopStart,
    VoiceEnd: LONGINT;
  BEGIN
    VoiceStart := LastVoiceStart[Channel];
    LoopStart  := LastLoopStart[Channel];
    VoiceEnd   := LastVoiceEnd[Channel];

    SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) OR 3);
    SwapGusAddress(VoiceStart);
    SetGusRegister16 (grCurrentAddrLow , VoiceStart AND $FFFF);
    SetGusRegister16 (grCurrentAddrHigh, VoiceStart SHR 16);

    SwapGusAddress(VoiceEnd);
    SetGusRegister16 (grEndAddrLow     , VoiceEnd   AND $FFFF);
    SetGusRegister16 (grEndAddrHigh    , VoiceEnd   SHR 16);

    IF LoopStart = -1 THEN
      SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) AND NOT 8)
    ELSE
      BEGIN
        SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) OR 8);
        SwapGusAddress(LoopStart);
        SetGusRegister16 (grStartAddrLow   , LoopStart  AND $FFFF);
        SetGusRegister16 (grStartAddrHigh  , LoopStart  SHR 16);
      END;
  END;

PROCEDURE RestartChannels; FAR;
  CONST
    buf    : ARRAY[1..64] OF BYTE = (0, 0, 0, 0, 0, 0, 0, 0,
                                     0, 0, 0, 0, 0, 0, 0, 0,
                                     0, 0, 0, 0, 0, 0, 0, 0,
                                     0, 0, 0, 0, 0, 0, 0, 0,
                                     0, 0, 0, 0, 0, 0, 0, 0,
                                     0, 0, 0, 0, 0, 0, 0, 0,
                                     0, 0, 0, 0, 0, 0, 0, 0,
                                     0, 0, 0, 0, 0, 0, 0, 0);
  VAR
    i, 
    k, Vol : BYTE;
    j      : WORD;
    Scr    : WORD ABSOLUTE $B800:90*63*2;
    First  : BOOLEAN;
  BEGIN
    GUSStopTimer1;
{    INC(Scr);}
    FOR i := 0 TO GUSChannels-1 DO
      IF VoicesChanged[i] THEN
        BEGIN
          SetGusVoice(i);
          ChangeSample(i);
          Vol := LastVolumes[i];
          LastVolumes[i] := 0;
          ChangeVol(i, Vol, RampFastRate);
        END;


    j := 0;
    FOR i := 0 TO GUSChannels-1 DO
      IF VoicesChanged[i] THEN
        BEGIN
          INC(j, 2);
          buf[j-1] := i;
          buf[j]   := GetGusRegister8(grVoiceControl) AND NOT 3;
{          VoicesChanged[i] := FALSE;}
        END;
(*
    IF j > 0 THEN
      BEGIN
        i := buf[j-1];
        k := buf[j];

        ASM
                MOV     DX,[GUSPort]
                ADD     DX,102h
                MOV     AL,[i]
                OUT     DX,AL
                INC     DX

                MOV     AL,grVoiceControl+$80
                OUT     DX,AL
                ADD     DX,2
                IN      AL,DX
                MOV     BH,AL
                SUB     DX,2

                MOV     AL,grCurrentAddrLow+$80
                OUT     DX,AL
                INC     DX
                IN      AX,DX
                MOV     SI,AX
                DEC     DX

                MOV     AL,grCurrentAddrHigh+$80
                OUT     DX,AL
                INC     DX
                IN      AX,DX
                MOV     DI,AX
                DEC     DX

                MOV     AL,grVoiceControl
                OUT     DX,AL
                ADD     DX,2
                MOV     AL,[k]
                OUT     DX,AL
                SUB     DX,2

                MOV     CX,000
        @@lp:    MOV    AL,grCurrentAddrLow+$80
                 OUT    DX,AL
                 INC    DX
                 IN     AX,DX
                 DEC    DX
                 CMP    AX,SI
                 JNZ    @@nof
                 LOOP   @@lp
        @@nof:  
                MOV     AL,grVoiceControl
                OUT     DX,AL
                ADD     DX,2
                MOV     AL,BH
                OUT     DX,AL
                SUB     DX,2

                MOV     AL,grCurrentAddrLow
                OUT     DX,AL
                MOV     AX,SI
                INC     DX
                OUT     DX,AX
                DEC     DX

                MOV     AL,grCurrentAddrHigh
                OUT     DX,AL
                MOV     AX,DI
                INC     DX
                OUT     DX,AX


                MOV     CX,[j]
                SHR     CX,1
                MOV     SI,OFFSET buf
        @@lp2:   MOV    AL,[SI]
                 INC    SI

                 MOV    DX,[GUSPort]
                 ADD    DX,102h
                 OUT    DX,AL

                 INC    DX
                 MOV    AL,grVoiceControl
                 OUT    DX,AL
                 ADD    DX,2
                 MOV    AL,[SI]
                 INC    SI
                 OUT    DX,AL

                 LOOP   @@lp2




{
                MOV     AL,[First]
                JZ      @@nof
                 XOR    AL,AL
                 MOV    [First],AL
                 SUB    DX,2
                 MOV    AL,grCurrentAddrLow+$80
                 OUT    DX,AL
                 INC    DX
                 IN     AX,DX
                 MOV    SI,AX
                 MOV    CX,10000
        @@lp:     IN    AX,DX
                  CMP   AX,SI
                  JNZ   @@nof
                  LOOP  @@lp
        @@nof:
}




        END;
    END;
*)


    First := TRUE;
    FOR i := 0 TO GUSChannels-1 DO
      IF VoicesChanged[i] THEN
        BEGIN
(*
          ASM

                MOV     DX,[GUSPort]
                ADD     DX,102h
                MOV     AL,[i]
                OUT     DX,AL

                INC     DX
                MOV     AL,grVoiceControl+$80
                OUT     DX,AL
                ADD     DX,2
                IN      AL,DX
                MOV     AH,AL

                SUB     DX,2
                MOV     AL,grVoiceControl
                OUT     DX,AL
                ADD     DX,2
                MOV     AL,AH
                AND     AL,NOT 3
                OUT     DX,AL
{
                MOV     AL,[First]
                JZ      @@nof
                 XOR    AL,AL
                 MOV    [First],AL
                 SUB    DX,2
                 MOV    AL,grCurrentAddrLow+$80
                 OUT    DX,AL
                 INC    DX
                 IN     AX,DX
                 MOV    SI,AX
                 MOV    CX,10000
        @@lp:     IN    AX,DX
                  CMP   AX,SI
                  JNZ   @@nof
                  LOOP  @@lp
        @@nof:
}
          END;
*)

          SetGusVoice(i);
          SetGusRegister8(grVoiceControl, GetGusRegister8(grVoiceControl) AND NOT 3);

          VoicesChanged[i] := FALSE;
        END;


  END;


PROCEDURE TriggerVoice(Channel: BYTE; Vol: BYTE; Freq: LONGINT; Panning: BYTE;
                       VoiceStart, LoopStart, VoiceEnd: LONGINT);
  BEGIN
    SetGusVoice(Channel);

    ChangeVoiceParams(Channel, 0, Freq, Panning);

    ASM PUSHF; CLI END;

    IF Channel = 2 THEN
      BEGIN
        WriteSNum(VoiceStart SHR 16,    $3F);
        WriteSNum(VoiceStart AND $FFFF, $3F);

        WriteSNum(LoopStart SHR 16,    $5F);
        WriteSNum(LoopStart AND $FFFF, $5F);

        WriteSNum(VoiceEnd SHR 16,    $F0);
        WriteSNum(VoiceEnd AND $FFFF, $F0);
      END;

    LastVoiceStart[Channel] := VoiceStart;
    LastLoopStart[Channel]  := LoopStart;
    LastVoiceEnd[Channel]   := VoiceEnd;
    VoicesChanged[Channel]  := TRUE;
    LastVolumes[Channel]    := Vol;

    ASM POPF END;

    GUSTimer1Rut := RestartChannels;
    GUSInitTimer1($F6);
  END;

PROCEDURE ChangeVoiceParams(Channel: BYTE; Vol: BYTE; Freq: LONGINT; Panning: BYTE);
  BEGIN
    SetGusVoice(Channel);
{
IF Vol = 0 THEN
  Vol := 127
ELSE IF Vol <> $FF THEN
  Vol := 0;
}

    IF VoicesChanged[Channel] THEN
      BEGIN
        IF Vol <> $FF THEN
          BEGIN
            IF Vol > 127 THEN Vol := 127;
            LastVolumes[Channel] := Vol;
          END;
      END
    ELSE
      ChangeVol(Channel, Vol, RampFastRate);

    IF (Freq <> $FFFFFFFF) AND (LastFreqs[Channel] <> Freq) THEN
      BEGIN
        LastFreqs[Channel] := Freq;
        SetGusRegister16(grFreqControl, ((LONGINT(Freq) SHL 9) + (GUSDivisor SHR 1)) DIV
                                        (GUSDivisor SHR 1));
      END;

    IF LastPans[Channel] <> Panning THEN
      BEGIN
        LastPans[Channel] := Panning;
        SetGusRegister8(grPanPosition, Panning SHR 4);
      END;

  END;



PROCEDURE SetGusChannels(Channels: BYTE);
  BEGIN
    IF Channels > 32 THEN
      Channels := 32
    ELSE IF Channels < 20 THEN
      Channels := 20;

    SetGusRegister8  (grActiveVoices, $C0+Channels-1);

    GUSDivisor  := 617400 DIV Channels;
    GUSChannels := Channels;
  END;




END.
