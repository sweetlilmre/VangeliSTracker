{****************************************************************************}
{                                                                            }
{ MODULE:         SoundDevices                                               }
{                                                                            }
{ DESCRIPTION:    Implements a common interface to access the different      }
{                 sampled audio devices possible on a PC, wether they work   }
{                 with DMA or polling.                                       }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo Baeza                                  }
{                                                                            }
{ MODIFICATIONS:  Nobody yet.                                                }
{                                                                            }
{ HISTORY:        xx-May-1992 Conception.                                    }
{                 xx-Jun-1992 Development.                                   }
{                 21-Jul-1992 Documentation (this mess).                     }
{                 07-Oct-1992 Redo from start :-( (DMA Affairs).             }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT SoundDevices;

INTERFACE

USES {SongElements, }Hardware;



{----------------------------------------------------------------------------}
{ Device configuration definitions.                                          }
{____________________________________________________________________________}

TYPE
  TDevName = STRING[50];                    { Name/description of device.                                    }
  TDevID   = STRING[20];                    { Device identification string.                                  }

  TProc            = PROCEDURE;                       { Generic procedure without parameters.                }
  TNameProc        = FUNCTION             : TDevName; { Procedure that returns the name of a device.         }
  TInitDevProc     = PROCEDURE (Hz: WORD);            { Device initialisation procedure.                     }
  TChgHzProc       = PROCEDURE (Hz: WORD);            { Sample rate change procedure.                        }
  TGetRealFreqProc = FUNCTION  (Hz: WORD) : WORD;     { Returns the real sampling freq. when Hz is selected. }
  TDetectProc      = FUNCTION             : BOOLEAN;  { Device autodetection procedure.                      }

TYPE
  PSoundDevice = ^TSoundDevice;   { Device record for including in a linked list.                            }
  TSoundDevice = RECORD
    DevID         : TDevID;       { Device ID string.                                                        }
    DMA           : BOOLEAN;      { TRUE if the device uses DMA output (shouldn't be needed).                }

    Name            : TNameProc;        { Device name.                                                       }
    Autodetect      : TDetectProc;      { Autodetection procedure.                                           }
    InitRut         : TInitDevProc;     { Initialisation procedure.                                          }
    ChgHzProc       : TChgHzProc;       { Sample rate change procedure.                                      }
    GetRealFreqProc : TGetRealFreqProc; { Real sampling freq.                                                }
    TimerHandler,
    PollRut         : TProc;            { Routine to be executed for active polling (hand made).             }
    EndRut          : TProc;            { Device closing procedure.                                          }

    Next          : PSoundDevice;     { Next record in the list.                                             }
  END;

CONST
  NumDevices   : BYTE         = 0;   { Count of the number of installed devices.    }
  ActiveDevice : PSoundDevice = NIL; { Device being used right now.                 }




{----------------------------------------------------------------------------}
{ Device Stack.                                                              }
{____________________________________________________________________________}

CONST
  DevStkSize = 1000;
VAR
  DevStack : ARRAY[1..DevStkSize] OF BYTE;
  DevSS    : WORD;
  DevSP    : WORD;

{----------------------------------------------------------------------------}
{ Sample buffers definition.                                                 }
{____________________________________________________________________________}

TYPE
  TDataType = (dtShortInt, dtInteger);        { Data type of the samples. }

  TIntBuff   = ARRAY[0..32760] OF INTEGER;    { Data types for big arrays. }
  TShortBuff = ARRAY[0..65520] OF SHORTINT;

  PIntBuff   = ^TIntBuff;                     { Idem. }
  PShortBuff = ^TShortBuff;

  PSampleBuffer = ^TSampleBuffer;   { PCM Buffer. }
  TSampleBuffer = RECORD
    InUse    : BOOLEAN;             { TRUE while it's being used by the device.       }
    NSamples,                       { Size of the buffer in samples.                  }
    RateHz   : WORD;                { Sampling frequency.                             }
    Channels : BYTE;                { 1 or 4, channels contained in the buffer.       }
    CASE DataType : TDataType OF
      dtInteger:  ( IData : PIntBuff );   { Pointer to the buffer.                    }
      dtShortInt: ( SData : PShortBuff );
  END;

CONST
  MaxChannels     = 32;
  Sounding     : POINTER = NIL;  { Buffer that is actually sounding (NON-DMA only). }
  SoundLeft    : WORD    = 0;    { Number of samples left in the buffer.            }
  NumChannels  : WORD    = 1;    { Number of channels in the buffer.                }
  ChannelIncr  : WORD    = 1;    { Size of one sample in the buffer.                }




{----------------------------------------------------------------------------}
{ DMA buffers definition.                                                    }
{____________________________________________________________________________}

CONST
  DMABufferSize = 4096;      { Size of the buffer. }

VAR
  DMABufferPtr : POINTER;                         { Pointers for the }
  DMABuffer    : POINTER;                         { DMA buffer.      }
  DMABufferEnd : WORD;

  DMABufferYet : BOOLEAN;

CONST
  FinalBufferSize = 4096;
  FinalBufferPos  : WORD = 0;

VAR
  FinalBuffer : ARRAY[0..FinalBufferSize-1] OF INTEGER;




{----------------------------------------------------------------------------}
{ Hardware parameters.                                                       }
{____________________________________________________________________________}

CONST
  DefaultHz                   = 16000;     { Default sampling rate.                                }
  DeviceIdling      : BOOLEAN = TRUE;      { TRUE if there are no samples sounding.                }
  TimerHz           : WORD    = DefaultHz; { Clock frequency of the INT 8 timer.                   }
  LastHz            : WORD    = 0;         { Older INT 8 frequency (for detecting change).         }
  SoundHz           : WORD    = DefaultHz; { Sampling frequency of the sound.                      }
  DesiredHz         : WORD    = DefaultHz; { Desired sampling frequency of the sound.              }
  SystemClockCount  : WORD    = 0;         { Clock count for calling the original INT 8.           }
  SystemClockIncr   : WORD    = 0;         { Increment for calling the original INT 8.             }
  TimerVal          : WORD    = 0;         { Value given to the INT 8 timer.                       }
  DeviceInitialized : BOOLEAN = FALSE;     { TRUE if a device has already been initialized.        }
  DMAOffset         : WORD    = 1;         { Number of samples to discard in DMA transferences.    }
  HzChanged         : BOOLEAN = FALSE;
  DoBassPower       : BOOLEAN = FALSE;
  MixMethod         : BYTE    = 3;         { Mono/stereo mixing algorithm.                         }
  Stereo            : BOOLEAN = FALSE;
  BytesPerSample    : BYTE    = 1;
  DevBits           : BYTE    = 8;
  DMAStop           : BOOLEAN = FALSE;
  DMAStopped        : BOOLEAN = FALSE;
  DMAIrqWatch       : BYTE    = 0;
  DMAChannel        : WORD    = 0;
  UsingGUS          : BOOLEAN = FALSE;
  TicksPerSecond    : WORD    = 50;     { Number of ticks per second, 50 = Europe, 60 = USA.    }

  TrebleFilterVal_Left   : WORD =  6;
  TrebleFilterMult_Left  : WORD =  3;
  BassFilterVal_Left     : WORD = 13;
  BassFilterMult_Left    : WORD =  0;
  TrebleFilterVal_Right  : WORD =  6;
  TrebleFilterMult_Right : WORD =  3;
  BassFilterVal_Right    : WORD = 13;
  BassFilterMult_Right   : WORD =  0;



{----------------------------------------------------------------------------}
{ Periodic process.                                                          }
{____________________________________________________________________________}

VAR
  PeriodicProc  : TProc;    { Periodic process (normally a music interpreter).           }

CONST
  PeriodicHz    : BYTE = 0; { Frequency for calling the periodic process.                }
  PeriodicStart : WORD = 1; { Countdown starting point (NON-DMA only).                   }
  PeriodicCount : WORD = 0; { Countdown.               (idem).                           }




{----------------------------------------------------------------------------}
{ Buffer provider definitions.                                               }
{____________________________________________________________________________}

TYPE
  TAskBufferProc = FUNCTION : PSampleBuffer; { Buffer provider function. }

VAR
  AskBufferProc  : TAskBufferProc; { Pointer to the buffer provider.             }
  ActualBuffer,                    { Buffer being used.                          }
  NextBuffer     : PSampleBuffer;  { Buffer that will be used next.              }
  PleaseFallback : WORD{BOOLEAN};        { Set TRUE if there are no buffers available. }




{----------------------------------------------------------------------------}
{ Sound Blaster device variables.                                            }
{____________________________________________________________________________}

CONST
  DSPWritePort : WORD    = 0;
  DSP8AckPort  : WORD    = 0;
  DSPLifePort  : WORD    = 0;
  SbCmdTimeout : WORD    = 100;   { $10 DSP Command timeout.   }
  SbSplTimeout : WORD    = 10;    { $10 DSP Parameter timeout. }




{----------------------------------------------------------------------------}
{ DAC device ports.                                                          }
{____________________________________________________________________________}

CONST
  DacPort  : WORD = $378;
  LDacPort : WORD = $378;
  RDacPort : WORD = $378;





{----------------------------------------------------------------------------}
{ Functions in the ASM portion.                                              }
{____________________________________________________________________________}

CONST
  DeviceStartRut   : WORD = 0;
  DeviceRut1       : WORD = 0;
  DeviceRut2       : WORD = 0;
  DeviceKickRut    : WORD = 0;
  DeviceFillRut    : WORD = 0;

PROCEDURE MixChannels;
{PROCEDURE DumpSamples;}
PROCEDURE DMAFillBuffer;
PROCEDURE DMADoGetBuff;
PROCEDURE NullTimerHandler;
PROCEDURE TimerHandler;
PROCEDURE DMATimerHandler;

PROCEDURE DevInitSbNonDMA(Ster: BOOLEAN; Bits: BYTE);
PROCEDURE DevInitSbDMA   (Ster: BOOLEAN; Bits: BYTE);
PROCEDURE DevInitSpkr    (Ster: BOOLEAN; Bits: BYTE);
PROCEDURE DevInitDac     (Ster: BOOLEAN; Bits: BYTE);




{----------------------------------------------------------------------------}
{ Functions to be used by devices only.                                      }
{____________________________________________________________________________}

FUNCTION  InitDevice   (Device: PSoundDevice) : WORD; { Used to declare a device.                            }
PROCEDURE PollDevice;                                 { Used to manually poll the device, if it is required. }
PROCEDURE CalcTimerData(Hz: WORD);                    { Used to calculate the different Hz variables.        }
PROCEDURE DefaultChgHz (Hz: WORD);                    { Used as a default TChgHzProc.                        }
FUNCTION  GetRealFreq  (Hz: WORD)             : WORD; { Used as a default TRealFreqProc.                     }
PROCEDURE InitTimer;                                  { Used to reinitialise the timer after a freq. change. }
FUNCTION  DoGetBuffer                         : WORD; { Used to get the next buffer prepared.                }




{----------------------------------------------------------------------------}
{ Functions to be used by the sound generators only.                         }
{____________________________________________________________________________}

PROCEDURE SetDevice      (p: PSoundDevice);                             { Used to initialise a buffer for output.  }
FUNCTION  IndexDevice    (i: WORD)                      : PSoundDevice; { Used to index the devices.               }
FUNCTION  LocateDevice   (ID: STRING)                   : PSoundDevice; { Used to find a given device.             }
PROCEDURE SetPeriodicProc(Proc: TProc; PerSecond: WORD);                { Used to initialise the periodic process. }
PROCEDURE SetBufferAsker (Proc: TAskBufferProc);                        { Used to initialise the buffer asker.     }
PROCEDURE StartSampling;                                                { Used to start the sound output.          }
PROCEDURE EndSampling;                                                  { Used to end the sound output.            }


PROCEDURE InitSoundDevices;




IMPLEMENTATION

USES Dos,
     Debugging, Output43;




{----------------------------------------------------------------------------}
{ Internal data.                                                             }
{____________________________________________________________________________}

CONST
  DeviceList       : PSoundDevice = NIL;   { Linked list of all devices.                     }
  OldTimerHandler  : POINTER      = NIL;   { Pointer to the original INT 8.                  }
  IntInstalled     : BOOLEAN      = FALSE; { TRUE if the INT 8 handler is already installed. }




{----------------------------------------------------------------------------}
{ Null procedures used in the unit.                                          }
{____________________________________________________________________________}

PROCEDURE NullProcedure;                  FAR; ASSEMBLER; ASM END;
FUNCTION  NullBufferProc : PSampleBuffer; FAR; BEGIN NullBufferProc := NIL; END;


PROCEDURE NullInt; ASSEMBLER;
  ASM
        PUSH    AX
        MOV     AL,$20
        OUT     $20,AL
        POP     AX
        IRET
  END;




{----------------------------------------------------------------------------}
{ Periodic process implementation.                                           }
{____________________________________________________________________________}

PROCEDURE InitPeriodic;
  BEGIN
    IF PeriodicHz = 0 THEN BEGIN
      PeriodicStart   := 0;
      PeriodicCount   := 0;
      SystemClockIncr := TimerVal;
    END ELSE BEGIN
      PeriodicStart := TimerHz DIV PeriodicHz;
      IF PeriodicStart = 0 THEN PeriodicStart := 1;
      PeriodicCount := 1;
      SystemClockIncr := TimerVal {* PeriodicStart};
    END;
  END;


PROCEDURE SetPeriodicProc(Proc: TProc; PerSecond: WORD);
  BEGIN
    ASM
        PUSHF
        CLI
        LES     BX,[Proc]
        MOV     WORD PTR [PeriodicProc],BX;
        MOV     WORD PTR [PeriodicProc+2],ES;
        POPF
    END;
    PeriodicHz   := PerSecond;
    InitPeriodic;
  END;




{----------------------------------------------------------------------------}
{ Hardware and interrupt handling procedures.                                }
{____________________________________________________________________________}

PROCEDURE OriginalHwTimer; ASSEMBLER;
  ASM
        MOV     AL,54       { Selct timer 0, secuential access and cont¡nuous mode. }
        OUT     43h,AL
        XOR     AL,AL       { Set the counter to 0 (65536). }
        OUT     40h,AL      { Lower byte of the counter.    }
        OUT     40h,AL      { Higher byte.                  }
  END;


PROCEDURE SetHwTimer(value: WORD); ASSEMBLER;
  ASM
        MOV     AL,54       { Selct timer 0, secuential access and cont¡nuous mode. }
        OUT     43h,AL
        MOV     AX,value
        OUT     40h,AL      { Lower byte of the counter.    }
        XCHG    AH,AL
        OUT     40h,AL      { Higher byte.                  }
  END;


PROCEDURE RestoreTimer;
  BEGIN
    IF IntInstalled THEN
      BEGIN
        SetIntVec(8, OldTimerhandler);
        OriginalHwTimer;
        IntInstalled := FALSE;
      END;
  END;


PROCEDURE InitTimer;
  BEGIN
    InitPeriodic;

    IF NOT IntInstalled THEN
      BEGIN
        IntInstalled := TRUE;
        GetIntVec(8, OldTimerHandler);
        SetIntVec(8, @ActiveDevice^.TimerHandler);
      END;

{    SetHwTimer(2980);}
    SetHwTimer(TimerVal);
  END;




{----------------------------------------------------------------------------}
{ Procedures exported for the sound generator.                               }
{____________________________________________________________________________}

PROCEDURE StartSampling;
  BEGIN
    IF NOT DeviceInitialized THEN RestoreTimer;

    ActualBuffer      := NIL;
    NextBuffer        := NIL;
    SoundLeft         := 0;
    PleaseFallBack    := 0;
    DeviceIdling      := TRUE;
    DMABufferPtr      := DMABuffer;
    DMABufferYet      := TRUE;
    Stereo            := FALSE;
    DevBits           := 8;
    BytesPerSample    := 1;

    FillChar(DMABuffer^, DMABufferSize, $80);

    IF (ActiveDevice <> NIL) {AND (NOT DeviceInitialized)} THEN
      BEGIN
        ASM CLI END;

        DeviceInitialized := TRUE;

        ActiveDevice^.InitRut(DesiredHz);

        ASM STI END;
      END;

    BytesPerSample := (DevBits + 7) DIV 8 *  (BYTE(Stereo) + 1);
  END;


PROCEDURE EndSampling;
  BEGIN
    IF (ActiveDevice <> NIL) AND DeviceInitialized THEN
      BEGIN
        ASM CLI END;
        FillChar(DMABuffer^, DMABufferSize, $80);
        ActiveDevice^.EndRut;
        RestoreTimer;
        ASM STI END;
        DeviceInitialized := FALSE;
      END;
  END;


PROCEDURE SetBufferAsker (Proc: TAskBufferProc);
  BEGIN
    ASM CLI END;
     AskBufferProc := Proc;
    ASM STI END;
  END;


PROCEDURE SetDevice(p: PSoundDevice);
  BEGIN
    IF p <> NIL THEN
      BEGIN
        IF DeviceInitialized THEN
          BEGIN
            EndSampling;
            ActiveDevice := p;
            StartSampling;
          END
        ELSE
          ActiveDevice := p;
      END;
  END;


FUNCTION LocateDevice(ID: STRING) : PSoundDevice;

  FUNCTION NotInStr(VAR s, ss: STRING) : BOOLEAN;
    VAR
      i : WORD;
    BEGIN
      NotInStr := TRUE;
      IF Length(ss) > Length(s) THEN EXIT;
      FOR i := 1 TO Length(ss) DO
        IF UpCase(s[i]) <> UpCase(ss[i]) THEN EXIT;
      NotInStr := FALSE;
    END;

  VAR
    p : PSoundDevice;
  BEGIN
    p := DeviceList;
    WHILE (p <> NIL) AND NotInStr(p^.DevID, ID) DO p := p^.Next;
    LocateDevice := p;
  END;


FUNCTION IndexDevice(i: WORD) : PSoundDevice;
  VAR
    p : PSoundDevice;
  BEGIN
    p := DeviceList;
    DEC(i);
    WHILE (p <> NIL) AND (i > 0) DO
      BEGIN
        p := p^.Next;
        DEC(i);
      END;

    IndexDevice := p;
  END;




{----------------------------------------------------------------------------}
{ Implementation of some procedures exported to the device controllers.       }
{____________________________________________________________________________}

FUNCTION InitDevice(Device: PSoundDevice) : WORD;
  BEGIN
    Device^.Next := DeviceList;
    DeviceList   := Device;
    IF ActiveDevice = NIL THEN SetDevice(Device);
    INC(NumDevices);
  END;


PROCEDURE PollDevice;
  BEGIN
    ActiveDevice^.PollRut;
  END;


FUNCTION GetRealFreq(Hz: WORD) : WORD;
  VAR
    i    : WORD;
    NHz1 : WORD;
    NHz2 : WORD;
  BEGIN
    IF Hz = 0 THEN Hz := 1;
    i := 1193180 DIV Hz;

    NHz1 := 1193180 DIV  i;
    NHz2 := 1193180 DIV (i + 1);
    IF ABS(INTEGER(NHz1 - Hz)) > ABS(INTEGER(NHz2 - Hz)) THEN NHz1 := NHz2;

    GetRealFreq := NHz1;
  END;


PROCEDURE CalcTimerData(Hz: WORD);
  BEGIN
    Hz := GetRealFreq(Hz);

    IF Hz = 0 THEN TimerVal := $FFFF
              ELSE TimerVal := 1193180 DIV Hz;

    TimerHz         := 1193180 DIV TimerVal;
    SoundHz         := TimerHz;
{    SystemClockIncr := TimerVal;}
  END;


PROCEDURE DefaultChgHz(Hz: WORD);
  BEGIN
    CalcTimerData(Hz);
    InitTimer;
  END;


FUNCTION DoGetBuffer : WORD;
  CONST
    Semaphore : BYTE    = 0;
    Size      : WORD    = 1;
  BEGIN
    DoGetBuffer := 0;
    IF Semaphore > 0 THEN EXIT;
    INC(Semaphore);

    IF ActualBuffer <> NIL THEN
      BEGIN
        Size := ActualBuffer^.NSamples;
        ActualBuffer^.InUse := FALSE; { It must be already finished using. }
      END;

    ActualBuffer := NextBuffer;

    IF ActualBuffer = NIL THEN BEGIN     { If there had not been next buffer before. }
      ActualBuffer := AskBufferProc;
      IF ActualBuffer <> NIL THEN BEGIN  { If there has just been one more buffer. }
        ActualBuffer^.InUse := TRUE;
      END;
    END;

    IF ActualBuffer = NIL THEN
      BEGIN                                  { If there is no buffer :-( }
        IF (Size <> 1) AND (NOT ActiveDevice^.DMA) THEN
          INC(PleaseFallBack);
        SoundLeft      := 0;
        IF NOT ActiveDevice^.DMA THEN
          BEGIN
            PeriodicCount := 1;
            LastHz        := PeriodicHz;
            ActiveDevice^.ChgHzProc(LastHz);
          END;
      END
    ELSE
      BEGIN
        Sounding     := ActualBuffer^.IData;
        SoundLeft    := ActualBuffer^.NSamples;
        NumChannels  := ActualBuffer^.Channels;
        ChannelIncr  := ActualBuffer^.Channels * (ORD(ActualBuffer^.DataType)+1);

        IF (LastHz <> ActualBuffer^.RateHz) THEN BEGIN
          LastHz := ActualBuffer^.RateHz;
          ActiveDevice^.ChgHzProc(LastHz);

          HzChanged := TRUE;

        END;

        IF ActiveDevice^.DMA THEN
          BEGIN
            IF SoundLeft > DMAOffset + 5 THEN
              DEC(SoundLeft, DMAOffset)
            ELSE
              SoundLeft := 5;
          END;

        NextBuffer   := AskBufferProc; { Get the buffer, if there is one. }
        IF NextBuffer <> NIL THEN
          NextBuffer^.InUse := TRUE;


      END;

    DoGetBuffer := SoundLeft;

{
    WriteNum(40, SoundLeft, $70);
}

    DEC(Semaphore);
  END;




{----------------------------------------------------------------------------}
{ Unit initialisation.                                                       }
{____________________________________________________________________________}

PROCEDURE InitSoundDevices;
  TYPE
    PFreeBlock = ^TFreeBlock;
    TFreeBlock =
      RECORD
        Next : PFreeBlock;
        Size : POINTER;
      END;
  VAR
    l        : LONGINT;
    PtrFree  : POINTER;
    OldHPtr  : POINTER;
    p        : PFreeBlock;
    OffsFree : WORD;
  BEGIN

    PeriodicProc  := NullProcedure;
    AskBufferProc := NullBufferProc;

    { Calc. for the DMA buffers. This messes with the heap, but works. }

    DMABuffer := HeapPtr;

    l := (LONGINT(SEG(DMABuffer^)) SHL 4) + OFS(DMABuffer^); { l = linear address. }

    PtrFree  := HeapPtr;
    OffsFree := 0;

    IF LONGINT(WORD(l)) + DMABufferSize > 65536 THEN { If address doesn't match,    }
      BEGIN                                          { get an address that matches  }
        OffsFree := 65536 - LONGINT(WORD(l));        { by incrementing to a 64 Kb   }
        l := (l AND $F0000) + $10000;                { boundary.                    }
      END;

    DMABuffer    := Ptr((l SHR 4)  AND $F000, WORD(l));
    DMABufferPtr := DMABuffer;
    DMABufferEnd := OFS(DMABuffer^) + DMABufferSize;

    OldHPtr      := HeapPtr;
    HeapPtr      := Ptr((l + DMABufferSize + 16) SHR 4, 0); { Manually, allocate the }
    IF OldHPtr = FreeList THEN                              { buffer.                }
      BEGIN
        FreeList   := HeapPtr;
      END
    ELSE
      BEGIN
        p := FreeList;
        WHILE p^.Next <> OldHPtr DO
          p := p^.Next;
        p^.Next := HeapPtr;
      END;

    FillChar(HeapPtr^, 8, 0); { Clear the Heap Pointer contents. }

    IF OffsFree > 0 THEN              { Update the Heap by freeing  }
      FreeMem(PtrFree, OffsFree);     { manually the unused memory. }
  END;




FUNCTION GetDMACount : WORD;
  BEGIN
    GetDMACount := Hardware.GetDMACount(DMAChannel);
  END;

{$L SOUNDDEV}

PROCEDURE MixChannels;                                EXTERNAL;
{PROCEDURE DumpSamples;                                EXTERNAL;}
PROCEDURE DMAFillBuffer;                              EXTERNAL;
PROCEDURE DMADoGetBuff;                               EXTERNAL;
PROCEDURE NullTimerHandler;                           EXTERNAL;
PROCEDURE TimerHandler;                               EXTERNAL;
PROCEDURE DMATimerHandler;                            EXTERNAL;
                                                      
PROCEDURE DevInitSbNonDMA(Ster: BOOLEAN; Bits: BYTE); EXTERNAL;
PROCEDURE DevInitSbDMA   (Ster: BOOLEAN; Bits: BYTE); EXTERNAL;
PROCEDURE DevInitSpkr    (Ster: BOOLEAN; Bits: BYTE); EXTERNAL;
PROCEDURE DevInitDac     (Ster: BOOLEAN; Bits: BYTE); EXTERNAL;




END.

