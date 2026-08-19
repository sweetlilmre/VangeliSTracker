{****************************************************************************}
{                                                                            }
{ MODULE:         DevSB                                                      }
{                                                                            }
{ DESCRIPTION:    Device driver for the Sound Blaster sound card and         }
{                 compatibles, including the Sound Blaster Pro, Sound        }
{                 Booster, etc...                                            }
{                 Uses both: DMA and timer polling.                          }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        18-Oct-1992 Documentation. It doesn't allow the stereo     }
{                             of the SB Pro yet.                             }
{                 12-Nov-1992 SB Pro driver included. Speed-ups and fixes.   }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT DevSB;

INTERFACE

CONST
  SBDevID        = 'SBlaster-Mono';
  DMAPASDevID    = 'PAS';
  DMASBDevID     = 'DMA-SB-Mono';
  DMASBSterDevID = 'DMA-SB-Stereo';
  DMASBMixDevID  = 'Mix-DMA-SB-Stereo';
  DMASBMix2DevID = 'Mix2-DMA-SB-Stereo';

CONST
  SbProMixMasterVol : BYTE    = 255;   { Master volume of the SB Pro mixer.    }
  SbProMixDACVol    : BYTE    = 255;   { DAC volume.                           }
  SbProMixFMVol     : BYTE    = 255;   { FM music volume.                      }
  SbProMixFilter    : BOOLEAN = FALSE; { TRUE = Activate SB Pro output filter. }


PROCEDURE SBInit  (Hz: WORD);
PROCEDURE SBEnd;




IMPLEMENTATION

USES Dos,
     SoundDevices, StrConst,
     Kbd, Debugging, SoundBlaster, Hardware;





FUNCTION SBName : TDevName; FAR;
  BEGIN
    SBName := GetString(StrDevSBName);
  END;

FUNCTION DMAPASName : TDevName; FAR;
  BEGIN
    DMAPASName := GetString(StrDevDMAPASName);
  END;

FUNCTION DMASBName : TDevName; FAR;
  BEGIN
    DMASBName := GetString(StrDevDMASBName);
  END;

FUNCTION DMASBSterName : TDevName; FAR;
  BEGIN
    DMASBSterName := GetString(StrDevDMASBSterName);
  END;

FUNCTION DMASBMixName : TDevName; FAR;
  BEGIN
    DMASBMixName := GetString(StrDevDMASBMixName);
  END;

FUNCTION DMASBMix2Name : TDevName; FAR;
  BEGIN
    DMASBMix2Name := GetString(StrDevDMASBMix2Name);
  END;




PROCEDURE SetVars;
  BEGIN
    SoundDevices.DSPWritePort := DSPWritePort;
    SoundDevices.DSP8AckPort  := DSP8AckPort;
    SoundDevices.DSPLifePort  := DSPLifePort;
  END;




(******)

PROCEDURE SBInit(Hz: WORD);
  BEGIN
    Stereo    := FALSE;
    MixMethod := 0;
    SbRegInit;
    SetVars;
    DevInitSbNonDMA(FALSE, 8);
    CalcTimerData(Hz);
    InitTimer;
  END;


PROCEDURE SBChgHz(Hz: WORD); FAR;
  BEGIN
    CalcTimerData(Hz);
    InitTimer;
  END;

PROCEDURE DevPoll; FAR;
  BEGIN
  END;




PROCEDURE SBEnd; 
  BEGIN
{    SbRegDone;}
  END;


CONST
  SBData : TSoundDevice = (
    DevID      : SBDevID;
    DMA        : FALSE
  );





(******************* DMA Stuff *********************)




CONST
  OldDMAIrq : POINTER = NIL;

  DMAPlacedInBuf : WORD = 0;







PROCEDURE DMAIrq; ASSEMBLER;
  CONST
    Old83 : BYTE = 0;
  ASM
                CLI

                PUSH    AX
                PUSH    DS
                PUSH    DX

{
                MOV     AX,$B800
                MOV     DS,AX
                INC     [WORD PTR DS:0]
}

                MOV     AX,SEG(@Data)
                MOV     DS,AX

                MOV     DX,[DSP8AckPort]
                IN      AL,DX

                MOV     DX,[DSPLifePort]
                IN      AL,DX

                XOR     AL,AL
                MOV     [DMAIrqWatch],AL

                MOV     AL,[DMAStop]
                AND     AL,AL
                JZ      @@nostop

                MOV     [DMAStopped],AL
                MOV     [DeviceIdling],AL
                JMP     @@Fin
@@nostop:
                PUSH    ES
                PUSH    BX
                PUSH    CX
                PUSH    DI
                PUSH    SI
{
                PUSH    100
                PUSH    sdcSetTimeConst
                CALL    SbWriteByte

                PUSH    100
                PUSH    232
                CALL    SbWriteByte
}{
                MOV     AL,232
                MOV     [TimeConst],AL
}
                CALL    SbUpdateTimeConst

                PUSH    10000 {DMABufferSize} {64000}
                PUSH    1
                CALL    SbPlaySample

                POP     SI
                POP     DI
                POP     CX
                POP     BX
                POP     ES
@@Fin:
                MOV     AX,[SbIrq]
                CMP     AL,10
                JNZ     @@not10

                MOV     AL,$20
                OUT     $A0,AL

@@not10:        MOV     AL,$20
                OUT     $20,AL

                POP     DX
                POP     DS
                POP     AX

                IRET
  END;













FUNCTION DMASBGetRealFreq(Hz: WORD) : WORD; FAR;
  VAR
    i    : WORD;
    NHz1 : WORD;
    NHz2 : WORD;
  BEGIN
    IF Hz < 4000 THEN Hz := 4000;
    IF (NOT DoHiSpeed) OR (SbStereo AND NOT Sb16Detected) THEN
      IF Hz > 21800 THEN Hz := 21800;

    i := Hi(65536 - (256000000 DIV Hz));
    NHz1 := 1000000 DIV (256 - i);
    NHz2 := 1000000 DIV (256 - i - 1);

    IF ABS(INTEGER(NHz1 - Hz)) > ABS(INTEGER(NHz2 - Hz)) THEN NHz1 := NHz2;

    DMASBGetRealFreq := NHz1;
  END;


FUNCTION DMASBProGetRealFreq(Hz: WORD) : WORD; FAR;
  VAR
    i    : WORD;
    NHz1 : WORD;
    NHz2 : WORD;
  BEGIN
    IF Sb16Detected THEN
      BEGIN
        DMASBProGetRealFreq := DMASBGetRealFreq(Hz);
        EXIT;
      END;

    IF Hz < 4000 THEN Hz := 4000;
    IF (NOT DoHiSpeed) OR SbStereo THEN
      IF Hz > 21800 THEN Hz := 21800;

    i := Hi(65536 - (128000000 DIV Hz));
    NHz1 :=  500000 DIV (256 - i);
    NHz2 :=  500000 DIV (256 - i - 1);

    IF ABS(INTEGER(NHz1 - Hz)) > ABS(INTEGER(NHz2 - Hz)) THEN NHz1 := NHz2;

    DMASBProGetRealFreq := NHz1;
  END;


PROCEDURE DMASBCalcTimerData(Hz: WORD);
  BEGIN
    CalcTimerData(PeriodicHz);

    Hz := ActiveDevice^.GetRealFreqProc(Hz);

    IF SbStereo AND NOT Sb16Detected THEN
      BEGIN
        TimeConst := Hi(65536 - 128000000 DIV Hz);
        SoundHz   :=  500000 DIV (256 - WORD(TimeConst));
      END
    ELSE
      BEGIN
        TimeConst := Hi(65536 - 256000000 DIV Hz);
        SoundHz   := 1000000 DIV (256 - WORD(TimeConst));
      END;
  END;



FUNCTION  SbMonoDetect : BOOLEAN; FAR;
  BEGIN
    SbRegInit;
    SbProInit;
    Sb16Init;
    SbMonoDetect := SbRegDetect;
  END;


FUNCTION  SbStereoDetect : BOOLEAN; FAR;
  BEGIN
    SbRegInit;
    SbProInit;
    Sb16Init;
    SbStereoDetect := SbProDetect OR Sb16Detect;
  END;



PROCEDURE DMASBInit(Hz: WORD);
  BEGIN
    SbStereo := Stereo;

    SbRegInit;
    SbProInit;
    Sb16Init;

    SbWriteByte(SbDefTimeout, sdcTurnOnSpeaker);
{
    IF PORT[$22E] = 0 THEN;
}
    SetVars;

    DMAChannel := SbDMAChan;

    DevInitSbDMA(SbStereo, 8);

    IF OldDMAIrq = NIL THEN BEGIN
      OldDMAIrq := SetIRQVector(SbIrq, @DMAIrq);
      EnableIRQ(SbIrq);
    END;

    SbProSetStereo(SbStereo);
    DMASBCalcTimerData(Hz);

    DMASet(SbDMAChan, $58, DMABuffer, DMABufferSize);

    SbUpdateTimeConst;
    SbPlaySample(10 {DMABufferSize}, FALSE);

    InitTimer;

    DMAStopped := FALSE;
    DMAStop    := FALSE;
  END;


PROCEDURE DMASBMonoInit(Hz: WORD); FAR;
  BEGIN
    Stereo    := FALSE;
    DevBits   := 8;
    MixMethod := 0;
    DMASbInit(Hz);
  END;


PROCEDURE DMASBSterInit(Hz: WORD); FAR;
  BEGIN
    Stereo    := TRUE;
    DevBits   := 8;
    MixMethod := 1;
    DMASbInit(Hz);
  END;


PROCEDURE DMASBMixInit(Hz: WORD); FAR;
  BEGIN
    Stereo    := TRUE;
    DevBits   := 8;
    MixMethod := 2;
    DMASbInit(Hz);
  END;


PROCEDURE DMASBMix2Init(Hz: WORD); FAR;
  BEGIN
    Stereo    := TRUE;
    DevBits   := 8;
    MixMethod := 3;
    DMASbInit(Hz);
  END;


PROCEDURE DMASBChgHz(Hz: WORD); FAR;
  BEGIN
    DMASBCalcTimerData(Hz);
  END;


PROCEDURE DMASBEnd; FAR;
  BEGIN

    IF OldDMAIrq <> NIL THEN BEGIN
      DMAStopped := FALSE;
      DMAStop    := TRUE;

      ASM PUSHF; STI END;

      WHILE (NOT DMAStopped) AND (NOT DeviceIdling) AND (NOT KbdKeyPressed) DO;

      ASM POPF END;
{
      DMAReset(SbDMAChan);
}
      SetIRQVector(SbIrq, OldDMAIrq);
      OldDMAIrq := NIL;
{
      SbWriteByte($D3, 100);
}
    END;
    DisableIRQ(SbIrq);

  END;





VAR
  SaveHiSpeed : BOOLEAN;

PROCEDURE DMAPASMonoInit(Hz: WORD); FAR;
  BEGIN
    IF OldDMAIrq = NIL THEN
      BEGIN
        SaveHiSpeed := SbHiSpeed;
        SbHiSpeed := FALSE;
      END;

    Stereo     := FALSE;
    DevBits    := 8;
    MixMethod  := 0;
    DMASbInit(Hz);
  END;




PROCEDURE DMAPASEnd; FAR;
  BEGIN

    IF OldDMAIrq <> NIL THEN BEGIN
      DMAStopped := FALSE;
      DMAStop    := TRUE;

      ASM PUSHF; STI END;

      WHILE (NOT DMAStopped) AND (NOT DeviceIdling) AND (NOT KbdKeyPressed) DO;

      ASM POPF END;
{
      DMAReset(SbDMAChan);
}
      SetIRQVector(SbIrq, OldDMAIrq);
      OldDMAIrq := NIL;
{
      SbWriteByte($D3, 100);
}
      SbHiSpeed  := SaveHiSpeed;
    END;
    DisableIRQ(SbIrq);

  END;













CONST
  DMAPASData : TSoundDevice = (
    DevID      : DMAPASDevID;
    DMA        : TRUE
  );


  DMASBData : TSoundDevice = (
    DevID      : DMASBDevID;
    DMA        : TRUE
  );


CONST
  DMASBSterData : TSoundDevice = (
    DevID      : DMASBSterDevID;
    DMA        : TRUE
  );


CONST
  DMASBMixData : TSoundDevice = (
    DevID      : DMASBMixDevID;
    DMA        : TRUE
  );


CONST
  DMASBMix2Data : TSoundDevice = (
    DevID      : DMASBMix2DevID;
    DMA        : TRUE
  );




(******)

BEGIN

  WITH SBData DO BEGIN
    Name            := SBName;
    AutoDetect      := SbRegDetect;
    InitRut         := SBInit;
    ChgHzProc       := SBChgHz;
    GetRealFreqProc := GetRealFreq;
    TimerHandler    := SoundDevices.TimerHandler;
    PollRut         := DevPoll;
    EndRut          := SBEnd;
  END;

  WITH DMASBData DO BEGIN
    Name            := DMASBName;
    AutoDetect      := SbMonoDetect;
    InitRut         := DMASBMonoInit;
    ChgHzProc       := DMASBChgHz;
    GetRealFreqProc := DMASBGetRealFreq;
    TimerHandler    := DMATimerHandler;
    PollRut         := DevPoll;
    EndRut          := DMASBEnd;
  END;

  WITH DMAPASData DO BEGIN
    Name            := DMAPASName;
    AutoDetect      := SbMonoDetect;
    InitRut         := DMAPASMonoInit;
    ChgHzProc       := DMASBChgHz;
    GetRealFreqProc := DMASBGetRealFreq;
    TimerHandler    := DMATimerHandler;
    PollRut         := DevPoll;
    EndRut          := DMAPASEnd;
  END;

  WITH DMASBSterData DO BEGIN
    Name            := DMASBSterName;
    AutoDetect      := SbStereoDetect;
    InitRut         := DMASBSterInit;
    ChgHzProc       := DMASBChgHz;
    GetRealFreqProc := DMASBProGetRealFreq;
    TimerHandler    := DMATimerHandler;
    PollRut         := DevPoll;
    EndRut          := DMASBEnd;
  END;

  WITH DMASBMixData DO BEGIN
    Name            := DMASBMixName;
    AutoDetect      := SbStereoDetect;
    InitRut         := DMASBMixInit;
    ChgHzProc       := DMASBChgHz;
    GetRealFreqProc := DMASBProGetRealFreq;
    TimerHandler    := DMATimerHandler;
    PollRut         := DevPoll;
    EndRut          := DMASBEnd;
  END;

  WITH DMASBMix2Data DO BEGIN
    Name            := DMASBMix2Name;
    AutoDetect      := SbStereoDetect;
    InitRut         := DMASBMix2Init;
    ChgHzProc       := DMASBChgHz;
    GetRealFreqProc := DMASBProGetRealFreq;
    TimerHandler    := DMATimerHandler;
    PollRut         := DevPoll;
    EndRut          := DMASBEnd;
  END;

  InitDevice(@DMASBMix2Data);
  InitDevice(@DMASBMixData);
  InitDevice(@DMASBSterData);
  InitDevice(@DMASBData);
  InitDevice(@DMAPASData);
  InitDevice(@SBData);

END.
