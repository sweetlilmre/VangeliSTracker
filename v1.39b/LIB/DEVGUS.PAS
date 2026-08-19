{****************************************************************************}
{                                                                            }
{ MODULE:         DevGUS                                                     }
{                                                                            }
{ DESCRIPTION:    Device driver for the Gravis Ultrasound.                   }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        29-Aug-1993 Design and implementation.                     }
{                                                                            }
{ (C) 1992,93 VangeliSTeam                                                   }
{____________________________________________________________________________}

UNIT DevGUS;

INTERFACE




{ Device ID String. }

CONST                    
  GUSDevID = 'GUS';




IMPLEMENTATION

USES SoundDevices, StrConst, GUS, Kbd;






PROCEDURE NullTimerHandler; FAR; ASSEMBLER;
  ASM
                MOV     [DevSS],SS
                MOV     [DevSP],SP
                MOV     DX,DS
                MOV     SS,DX
                MOV     SP,OFFSET DevStack + DevStkSize

                CALL    [PeriodicProc]

                MOV     SS,[DevSS]
                MOV     SP,[DevSP]
  END;






{----------------------------------------------------------------------------}
{ Name function.                                                             }
{____________________________________________________________________________}

FUNCTION DevName : TDevName; FAR;
  BEGIN
    DevName := GetString(StrDevGUSName);
  END;




{----------------------------------------------------------------------------}
{ Autodetect routine. It's always present.                                   }
{____________________________________________________________________________}

FUNCTION DevDetect : BOOLEAN; FAR;
  BEGIN
    IF DetectUltrasound THEN
      BEGIN
        StartUltrasound;
        DevDetect := TRUE;
        UsingGUS := TRUE;
      END
    ELSE
      DevDetect := FALSE;
  END;




{----------------------------------------------------------------------------}
{ Device Initialisation routine.                                             }
{____________________________________________________________________________}

PROCEDURE DevInit(Hz: WORD); FAR; 
  BEGIN
    InitGusIRQ;

    UsingGUS := TRUE;
(*
    CalcTimerData(TicksPerSecond);    { Then do the standard polling initialisation. }
    InitTimer;
*)

    GUSTimer2Rut := NullTimerhandler;
    GUSInitTimer2($100 - ((2000000 DIV (TicksPerSecond*320) + 1) SHR 1));
  END;




{----------------------------------------------------------------------------}
{ Device deinitialisation routine.                                           }
{____________________________________________________________________________}

PROCEDURE DevEnd; FAR; 
  BEGIN
    DoneGusIRQ;
    StartUltrasound;
  END;




{----------------------------------------------------------------------------}
{ Accesory routines.                                                         }
{____________________________________________________________________________}

FUNCTION DevGetRealFreq(Hz: WORD) : WORD; FAR;
  BEGIN
    DevGetRealFreq := Hz;
  END;

PROCEDURE DevChgHz(Hz: WORD); FAR;
  BEGIN
  END;

PROCEDURE DevPoll; FAR;
  BEGIN
  END;




{----------------------------------------------------------------------------}
{ Device record.                                                             }
{____________________________________________________________________________}

CONST
  DevData : TSoundDevice = (
    DevID      : GUSDevID;
    DMA        : FALSE
  );




{----------------------------------------------------------------------------}
{ Init code.                                                                 }
{____________________________________________________________________________}

BEGIN

  WITH DevData DO BEGIN
    Name            := DevName;
    AutoDetect      := DevDetect;
    InitRut         := DevInit;
    ChgHzProc       := DevChgHz;
    GetRealFreqProc := DevGetRealFreq;
    TimerHandler    := SoundDevices.NullTimerHandler;
    PollRut         := DevPoll;
    EndRut          := DevEnd;
  END;

  InitDevice(@DevData);

END.
