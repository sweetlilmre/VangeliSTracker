{****************************************************************************}
{                                                                            }
{ MODULE:         DevDac                                                     }
{                                                                            }
{ DESCRIPTION:    Device driver for all DAC-type sound cards. This includes  }
{                 Uses timer polling.                                        }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        12-Nov-1992 Documentation.                                 }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT DevDAC;

INTERFACE

CONST                           { Device ID Strings. }
  DACDevID      = 'DAC-Mono';
  DAC2DevID     = 'DAC-Stereo';
  MixDAC2DevID  = 'Mix-DAC-Stereo';
  Mix2DAC2DevID = 'Mix2-DAC-Stereo';


{ Configuration. }

IMPLEMENTATION

USES SoundDevices, StrConst;




{----------------------------------------------------------------------------}
{ Name functions.                                                            }
{____________________________________________________________________________}

FUNCTION DACName : TDevName; FAR;
  BEGIN
    DACName := GetString(StrDevDACName);
  END;

FUNCTION DAC2Name : TDevName; FAR;
  BEGIN
    DAC2Name := GetString(StrDevDAC2Name);
  END;

FUNCTION MixDAC2Name : TDevName; FAR;
  BEGIN
    MixDAC2Name := GetString(StrDevMixDAC2Name);
  END;

FUNCTION Mix2DAC2Name : TDevName; FAR;
  BEGIN
    Mix2DAC2Name := GetString(StrDevMix2DAC2Name);
  END;




{----------------------------------------------------------------------------}
{ Autodetect routine. It's always present (can't be detected).               }
{____________________________________________________________________________}

FUNCTION DACDetect : BOOLEAN; FAR;
  BEGIN
    DACDetect := TRUE;
  END;




{----------------------------------------------------------------------------}
{ Device Initialisation routine.                                             }
{____________________________________________________________________________}

PROCEDURE Init(Hz: WORD); FAR; 
  BEGIN
    CalcTimerData(Hz);    { Standard polling initialisation. }
    InitTimer;
  END;

PROCEDURE InitMono(Hz: WORD); FAR;
  BEGIN
    Stereo    := FALSE;
    MixMethod := 0;
    DevInitDac(FALSE, 8);
    Init(Hz);
  END;

PROCEDURE InitSter(Hz: WORD); FAR;
  BEGIN
    Stereo    := TRUE;
    MixMethod := 1;
    DevInitDac(TRUE, 8);
    Init(Hz);
  END;

PROCEDURE InitSterMix(Hz: WORD); FAR;
  BEGIN
    Stereo    := TRUE;
    MixMethod := 2;
    DevInitDac(TRUE, 8);
    Init(Hz);
  END;

PROCEDURE InitSterMix2(Hz: WORD); FAR;
  BEGIN
    Stereo    := TRUE;
    MixMethod := 3;
    DevInitDac(TRUE, 8);
    Init(Hz);
  END;




{----------------------------------------------------------------------------}
{ Device deinitialisation routine.                                           }
{____________________________________________________________________________}

PROCEDURE DevEnd; FAR; ASSEMBLER;
  ASM
  END;




{----------------------------------------------------------------------------}
{ Accesory routines.                                                         }
{____________________________________________________________________________}

PROCEDURE DevChgHz(Hz: WORD); FAR;
  BEGIN
    CalcTimerData(Hz);
    InitTimer;
  END;

PROCEDURE DevPoll; FAR;
  BEGIN
  END;




{----------------------------------------------------------------------------}
{ Device records.                                                            }
{____________________________________________________________________________}

CONST
  DACData : TSoundDevice = (
    DevID      : DACDevID;
    DMA        : FALSE
  );

  DAC2Data : TSoundDevice = (
    DevID      : DAC2DevID;
    DMA        : FALSE
  );

  MixDAC2Data : TSoundDevice = (
    DevID      : MixDAC2DevID;
    DMA        : FALSE
  );

  Mix2DAC2Data : TSoundDevice = (
    DevID      : Mix2DAC2DevID;
    DMA        : FALSE
  );




{----------------------------------------------------------------------------}
{ Init code.                                                                 }
{____________________________________________________________________________}

BEGIN

  WITH DACData DO BEGIN
    Name            := DACName;
    AutoDetect      := DACDetect;
    InitRut         := InitMono;
    ChgHzProc       := DevChgHz;
    GetRealFreqProc := GetRealFreq;
    TimerHandler    := SoundDevices.TimerHandler;
    PollRut         := DevPoll;
    EndRut          := DevEnd;
  END;

  WITH DAC2Data DO BEGIN
    Name            := DAC2Name;
    AutoDetect      := DACDetect;
    InitRut         := InitSter;
    ChgHzProc       := DevChgHz;
    GetRealFreqProc := GetRealFreq;
    TimerHandler    := SoundDevices.TimerHandler;
    PollRut         := DevPoll;
    EndRut          := DevEnd;
  END;

  WITH MixDAC2Data DO BEGIN
    Name            := MixDAC2Name;
    AutoDetect      := DACDetect;
    InitRut         := InitSterMix;
    ChgHzProc       := DevChgHz;
    GetRealFreqProc := GetRealFreq;
    TimerHandler    := SoundDevices.TimerHandler;
    PollRut         := DevPoll;
    EndRut          := DevEnd;
  END;

  WITH Mix2DAC2Data DO BEGIN
    Name            := Mix2DAC2Name;
    AutoDetect      := DACDetect;
    InitRut         := InitSterMix2;
    ChgHzProc       := DevChgHz;
    GetRealFreqProc := GetRealFreq;
    TimerHandler    := SoundDevices.TimerHandler;
    PollRut         := DevPoll;
    EndRut          := DevEnd;
  END;

  InitDevice(@Mix2DAC2Data);
  InitDevice(@MixDAC2Data);
  InitDevice(@DAC2Data);
  InitDevice(@DACData);

END.
