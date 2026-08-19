{****************************************************************************}
{                                                                            }
{ MODULE:         DevSpkr                                                    }
{                                                                            }
{ DESCRIPTION:    Device driver for the PC internal speaker.                 }
{                 It uses timer polling.                                     }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        11-Nov-1992 Description                                    }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT DevSpkr;

INTERFACE




{ Device ID String. }

CONST                    
  SpkrDevID = 'Speaker';




IMPLEMENTATION

USES SoundDevices, StrConst;




{----------------------------------------------------------------------------}
{ Name function.                                                             }
{____________________________________________________________________________}

FUNCTION SpkrName : TDevName; FAR;
  BEGIN
    SpkrName := GetString(StrDevSpkrName);
  END;




{----------------------------------------------------------------------------}
{ Autodetect routine. It's always present.                                   }
{____________________________________________________________________________}

FUNCTION DevDetect : BOOLEAN; FAR;
  BEGIN
    DevDetect := TRUE;
  END;




{----------------------------------------------------------------------------}
{ Routine for adjusting the conversion table to the new output freq.         }
{____________________________________________________________________________}

PROCEDURE AdjustTable;
  CONST
    i    : WORD = 0;
    TVal : WORD = 0;
  BEGIN
(*
    TVal := TimerVal SHR 1;
    FOR i := 0 TO 255 DO
      SpkrTabla[i] := (WORD((SpkrBaseTabla[i]-1) * TVal) DIV $39) + 1;
*)
  END;




{----------------------------------------------------------------------------}
{ Device Initialisation routine.                                             }
{____________________________________________________________________________}

PROCEDURE DevInit(Hz: WORD); FAR; 
  BEGIN
    ASM
        IN      AL,61h
        OR      AL,3      
        OUT     61h,AL    { Turn on speaker. }

        MOV     AL,0B6h
        OUT     43h,AL    

        MOV     AL,0B0h
        OUT     43h,AL
        MOV     AL,034h
        OUT     43h,AL

        XOR     AL,AL
        OUT     42h,AL
        OUT     42h,AL
        MOV     AL,10010000b
        OUT     43h,AL    { Select Speaker timer mode. }
    END;

    Stereo    := FALSE;
    MixMethod := 0;
    DevInitSpkr(FALSE, 8);
    CalcTimerData(Hz);    { Then do the standard polling initialisation. }
    InitTimer;
    AdjustTable;          { And adjust the table for initial freq.       }
  END;




{----------------------------------------------------------------------------}
{ Device deinitialisation routine.                                           }
{____________________________________________________________________________}

PROCEDURE DevEnd; FAR; ASSEMBLER;
  ASM
        IN      AL,61h
        AND     AL,11111100b 
        OUT     61h,AL       { Turn off speaker. }
  END;




{----------------------------------------------------------------------------}
{ Accesory routines.                                                         }
{____________________________________________________________________________}

PROCEDURE DevChgHz(Hz: WORD); FAR;
  BEGIN
    CalcTimerData(Hz);
    InitTimer;
    AdjustTable;
  END;

PROCEDURE DevPoll; FAR;
  BEGIN
  END;




{----------------------------------------------------------------------------}
{ Device record.                                                             }
{____________________________________________________________________________}

CONST
  SpkrData : TSoundDevice = (
    DevID      : SpkrDevID;
    DMA        : FALSE
  );




{----------------------------------------------------------------------------}
{ Init code.                                                                 }
{____________________________________________________________________________}

BEGIN

  WITH SpkrData DO BEGIN
    Name            := SpkrName;
    AutoDetect      := DevDetect;
    InitRut         := DevInit;
    ChgHzProc       := DevChgHz;
    GetRealFreqProc := GetRealFreq;
    TimerHandler    := SoundDevices.TimerHandler;
    PollRut         := DevPoll;
    EndRut          := DevEnd;
  END;

  InitDevice(@SpkrData);

END.
