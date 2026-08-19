{****************************************************************************}
{                                                                            }
{ MODULE:         SoundBlaster                                               }
{                                                                            }
{ DESCRIPTION:    An UNIT that provides several routines for handling the    }
{                 Sound Blaster and Sound Blaster Pro cards and compatibles. }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        12-Nov-1992 Documentation.                                 }
{                 26-Nov-1992 Included SB 16 support.                        }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT SoundBlaster;

{$R-}

INTERFACE

USES SoundDevices;




{ I/O Port offsets. }

CONST
  CMS1DataPortOffset = $00;  { CM/S 1-6  Data port.             Write Only. }
  CMS1AddrPortOffset = $01;  { CM/S 1-6  Address port.          Write Only. }
  CMS2DataPortOffset = $02;  { CM/S 7-12 Data port.             Write Only. }
  CMS2AddrPortOffset = $03;  { CM/S 7-12 Address port.          Write Only. }

  MixAddrPortOffset  = $04;  { Mixer register port.             Write Only. }
  MixDataPortOffset  = $05;  { Mixer data port.                 Read/Write. }

  FMStatPortOffset   = $08;  { Mono FM Status port.             Read  Only. }
  FMAddrPortOffset   = $08;  { Mono FM Address port.            Write Only. }
  FMDataPortOffset   = $09;  { Mono FM Data port.               Write Only. }

  LFMStatPortOffset  = $00;  { Left FM Status port.             Read  Only. }
  LFMAddrPortOffset  = $00;  { Left FM Address port.            Write Only. }
  LFMDataPortOffset  = $01;  { Left FM Data port.               Write Only. }

  RFMStatPortOffset  = $02;  { Right FM Status port.            Read  Only. }
  RFMAddrPortOffset  = $02;  { Right FM Address port.           Write Only. }
  RFMDataPortOffset  = $03;  { Right FM Data port.              Write Only. }

  DSPResetPortOffset = $06;  { DSP Reset port.                  Write Only. }
  DSPReadPortOffset  = $0A;  { DSP Read data port.              Read  Only. }
  DSPLifePortOffset  = $0A;  { DSP Read data port.              Read  Only. }
  DSPWStatPortOffset = $0C;  { DSP Write buffer status port.    Write Only. }
  DSPWritePortOffset = $0C;  { DSP Write data port.             Write Only. }
  DSPRStatPortOffset = $0E;  { DSP Read buffer status port.     Read  Only. }
  DSP8AckPortOffset  = $0E;  {  8 bit DMA IRQ Acknowledge port. Write Only. }
  DSP16AckPortOffset = $0F;  { 16 bit DMA IRQ Acknowledge port. Write Only. }

  CDDataPortOffset   = $10;  { CD-ROM Data port.                Read  Only. }
  CDCmdPortOffset    = $10;  { CD-ROM Command port.             Write Only. }
  CDStatPortOffset   = $11;  { CD-ROM Status port.              Read  Only. }
  CDResetPortOffset  = $12;  { CD-ROM Reset port.               Write Only. }
  CDEnablePortOffset = $13;  { CD-ROM Enable port.              Write Only. }


{ I/O Ports. Same as above. }

CONST
  CMS1DataPort : WORD    = $220 + CMS1DataPortOffset;
  CMS1AddrPort : WORD    = $220 + CMS1AddrPortOffset;
  CMS2DataPort : WORD    = $220 + CMS2DataPortOffset;
  CMS2AddrPort : WORD    = $220 + CMS2AddrPortOffset;

  MixAddrPort  : WORD    = $220 + MixAddrPortOffset;
  MixDataPort  : WORD    = $220 + MixDataPortOffset;

  FMStatPort   : WORD    = $220 + FMStatPortOffset;
  FMAddrPort   : WORD    = $220 + FMAddrPortOffset;
  FMDataPort   : WORD    = $220 + FMDataPortOffset;

  LFMStatPort  : WORD    = $220 + LFMStatPortOffset;
  LFMAddrPort  : WORD    = $220 + LFMAddrPortOffset;
  LFMDataPort  : WORD    = $220 + LFMDataPortOffset;

  RFMStatPort  : WORD    = $220 + RFMStatPortOffset;
  RFMAddrPort  : WORD    = $220 + RFMAddrPortOffset;
  RFMDataPort  : WORD    = $220 + RFMDataPortOffset;

  DSPResetPort : WORD    = $220 + DSPResetPortOffset;
  DSPReadPort  : WORD    = $220 + DSPReadPortOffset;
  DSPLifePort  : WORD    = $220 + DSPLifePortOffset;
  DSPWStatPort : WORD    = $220 + DSPWStatPortOffset;
  DSPWritePort : WORD    = $220 + DSPWritePortOffset;
  DSPRStatPort : WORD    = $220 + DSPRStatPortOffset;
  DSP8AckPort  : WORD    = $220 + DSP8AckPortOffset;
  DSP16AckPort : WORD    = $220 + DSP16AckPortOffset;

  CDDataPort   : WORD    = $220 + CDDataPortOffset;
  CDCmdPort    : WORD    = $220 + CDCmdPortOffset;
  CDStatPort   : WORD    = $220 + CDStatPortOffset;
  CDResetPort  : WORD    = $220 + CDResetPortOffset;
  CDEnablePort : WORD    = $220 + CDEnablePortOffset;


{ Configuration. }

CONST
  SbPort       : WORD    = $FFFF; { Base port. $FFFF Means Autodetect.      }
  SbIrq        : WORD    = 7;     { DMA IRQ level.                          }
  SbDMAChan    : WORD    = 1;     { DMA channel.                            }
  SbDefTimeout : WORD    = 5000;  { Default DSP timeout.                    }
  SbHiSpeed    : BOOLEAN = TRUE;  { User Desires HS DMA mode if TRUE.       }
  SbForce      : BOOLEAN = FALSE; { Force TRUE the detection of the SB.     }
  MixerForce   : BOOLEAN = FALSE; { Force TRUE the detection of the Mixer.  }
  SbProForce   : BOOLEAN = FALSE; { Force TRUE the detection of the SB Pro. }
  Sb16Force    : BOOLEAN = FALSE; { Force TRUE the detection of the SB 16.  }


{ Card information. }

CONST
  SbVersionMin : BYTE       = 0;
  SbVersionMaj : BYTE       = 0;
  SbVersionStr : STRING[ 5] = '';
  SbCopyright  : STRING[80] = '';
  SbResponse1  : BYTE       = 0;
  SbResponse2  : BYTE       = 0;

VAR
  SbVersion    : WORD    ABSOLUTE SbVersionMin;


{ Run-time information. }

CONST
  SbRegDetected     : BOOLEAN = FALSE;
  SbRegInited       : BOOLEAN = FALSE;
  SbProDetected     : BOOLEAN = FALSE;
  SbProInited       : BOOLEAN = FALSE;
  Sb16Detected      : BOOLEAN = FALSE;
  Sb16Inited        : BOOLEAN = FALSE;
  MixerDetected     : BOOLEAN = FALSE;

  SbWorksOk         : BOOLEAN = TRUE;  { Set to FALSE if DSP timeouts.         }
  HSBlockSpecified  : WORD    = 0;     { Set to the last hi-speed block size.  }
  Sb16BlockSpecified: WORD    = 0;     { Set to the last Sb 16 block size.     }
  SbStereo          : BOOLEAN = FALSE; { Stereo DMA mode if TRUE.              }
  SbFilter          : BOOLEAN = FALSE; { SB Pro output filter ON if TRUE.      }

  DoHiSpeed         : BOOLEAN = FALSE; { Hi speed DMA mode if TRUE.            }
  Sb16Bit           : BOOLEAN = FALSE; { 16 bit output if TRUE.                }

  TimeConst         : BYTE    = 0;

  DMAStart          : BOOLEAN = FALSE;
  DMAStop           : BOOLEAN = FALSE;
  DMAStopped        : BOOLEAN = FALSE;

  DMAIrqWatch       : BYTE    = 0;



{ DSP Commands. }

CONST
  sdcSendOneSample  = $10;  { Send a sample to the DAC directly (mono mode only). }
  sdcStartLSpeedDMA = $14;  { Start a low-speed DMA transfer.                     }
  sdcSetTimeConst   = $40;  { Set the time constant.                              }
  sdcSetHSpeedSize  = $48;  { Set hi-speed DMA transfer length.                   }
  sdcStartHSpeedDMA = $91;  { Start a hi-speed DMA transfer.                      }
  sdcTurnOnSpeaker  = $D1;  { Turn on the SB speaker.                             }
  sdcTurnOffSpeaker = $D3;  { Turn off the SB speaker.                            }
  sdcGetDSPVersion  = $E1;  { Get the DSP version number.                         }
  sdcGetCopyright   = $E3;  { Get the card copyright string.                      }


{ Mixer registers. }

CONST
  mxrDataReset    = $00;
  mxrDACVolume    = $04;
  mxrMicMixing    = $0A;
  mxrInSetting    = $0C;
  mxrOutSetting   = $0E;
  mxrMasterVolume = $22;
  mxrFMVolume     = $26;
  mxrCDVolume     = $28;
  mxrLineVolume   = $2E;


{ Bit masks for the mixer registers. }

CONST
  mxiFilterVal = $38;
  mxiADCVal    = $06;
  mxoFilterNeg = $20;
  mxoStereoOn  = $02;

TYPE
  TMixerVolume = (mvMaster,
                  mvVoice,
                  mvFM,
                  mvLine,
                  mvMicrophone,
                  mvSpeaker,
                  mvCD);

CONST
  SbProRegs : ARRAY[mvMaster..mvCD] OF BYTE = ( $22, $04, $26, $2E, $0A, $00, $28 );
  Sb16Regs  : ARRAY[mvMaster..mvCD] OF BYTE = ( $30, $32, $34, $38, $3A, $3B, $34 );




{ SB basic }

FUNCTION  SbReset                                       : BOOLEAN;

PROCEDURE SbWriteLoop    (t: WORD);
PROCEDURE SbWriteByte    (t: WORD; b: BYTE);
PROCEDURE SbReadLoop     (t: WORD);
FUNCTION  SbReadByte     (t: WORD)                      : BYTE;


{ Mixer basic }

PROCEDURE SbWriteMixerReg (Reg, Val: BYTE);
FUNCTION  SbReadMixerReg  (Reg: BYTE)                    : BYTE;


{ SB Reg }

FUNCTION  SbRegDetect : BOOLEAN;
PROCEDURE SbRegInit;
PROCEDURE SbRegDone;

PROCEDURE SbGetDSPVersion;
PROCEDURE SbGetCopyrightString;
PROCEDURE SbSetTimeConst    (tc: BYTE);
PROCEDURE SbUpdateTimeConst;
PROCEDURE SbStartSampleLS   (Len: WORD; Cont: BOOLEAN);
PROCEDURE SbStartSampleHS   (Len: WORD; Cont: BOOLEAN);
PROCEDURE SbPlaySample      (Len: WORD; Cont: BOOLEAN);


{ Mixer }

FUNCTION MixerDetect : BOOLEAN;

PROCEDURE MixerSetVolume(Reg: TMixerVolume;     VolLeft, VolRight: BYTE);
FUNCTION  MixerGetVolume(Reg: TMixerVolume; VAR VolLeft, VolRight: BYTE) : BOOLEAN;


{ SB Pro }

FUNCTION  SbProDetect : BOOLEAN;
PROCEDURE SbProInit;
PROCEDURE SbProDone;

PROCEDURE SbProSetStereo (Stereo: BOOLEAN);
PROCEDURE SbProSetFilter (Filter: BOOLEAN);


{ SB 16 }

FUNCTION  Sb16Detect : BOOLEAN;
PROCEDURE Sb16Init;
PROCEDURE Sb16Done;

PROCEDURE Sb16StartSample(Len: WORD; Cont: BOOLEAN);




IMPLEMENTATION

USES Debugging;



{----------------------------------------------------------------------------}
{ Sound Blaster basic routines.                                              }
{____________________________________________________________________________}

FUNCTION SbReset : BOOLEAN;
  CONST
    ready = $AA;
  VAR
    ct, stat : BYTE;
  BEGIN
    PORT[DSPResetPort] := 1;
    FOR ct := 1 TO 100 DO;
    PORT[DSPResetPort] := 0;

    stat := 0;
    ct   := 0;
    WHILE (stat <> ready) AND (ct < 100) DO BEGIN
      stat := PORT[DSPRStatPort];
      stat := PORT[DSPReadPort];
      INC(ct);
    END;

    SbReset := stat = ready;
  END;


PROCEDURE SbWriteLoop(t: WORD); ASSEMBLER;
  ASM

                MOV     BX,t
                MOV     DX,[DSPWritePort]
@@lp:            DEC    BX
                 JZ     @@fin
                 IN     AL,DX
                 ADD    AL,AL
                 JC     @@lp
@@fin:          OR      BL,BH
                MOV     [SbWorksOk],BL
  END;


PROCEDURE SbWriteByte(t: WORD; b: BYTE); ASSEMBLER;
  ASM

                MOV     AL,b
                XOR     AH,AH
                PUSH    AX
                PUSH    $60
                CALL    WriteSNum

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

                MOV     AL,[SbWorksOk]
                ADD     AL,'A'
                XOR     AH,AH
                PUSH    AX
                PUSH    $40
                CALL    WriteChar

  END;


PROCEDURE SbReadLoop(t: WORD); ASSEMBLER;
  ASM

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
  END;


FUNCTION SbReadByte(t: WORD) : BYTE; ASSEMBLER;
  ASM
                MOV     AX,t
                PUSH    AX
                CALL    SbReadLoop
                JNZ     @@ya
{
                MOV     DX,[DSPLifePort]
                IN      AL,DX

                MOV     AX,t
                PUSH    AX
                CALL    SbReadLoop
}
@@ya:           IN      AL,DX
  END;




{----------------------------------------------------------------------------}
{ Mixer basic routines.                                                      }
{____________________________________________________________________________}

PROCEDURE SbWriteMixerReg(Reg, Val: BYTE); ASSEMBLER;
  ASM

                MOV     DX,[MixAddrPort]
                MOV     AL,[Reg]
                OUT     DX,AL

                MOV     DX,[MixDataPort]
                MOV     AL,[Val]
                OUT     DX,AL

  END;


FUNCTION SbReadMixerReg(Reg: BYTE) : BYTE; ASSEMBLER;
  ASM

                MOV     DX,[MixAddrPort]
                MOV     AL,[Reg]
                OUT     DX,AL

                MOV     DX,[MixDataPort]
                IN      AL,DX

  END;




{----------------------------------------------------------------------------}
{ Regular Sound Blaster generic routines.                                    }
{____________________________________________________________________________}

FUNCTION SbRegDetect : BOOLEAN;
  VAR
    Port, Lst : WORD;
  BEGIN

    SbRegDetect := SbRegDetected;

    IF SbRegDetected THEN EXIT;

    IF SbPort < $8000 THEN
      BEGIN
        Port := SbPort;
        Lst  := SbPort;
      END
    ELSE
      BEGIN
        Port := $210;
        Lst  := $280;
      END;

    WHILE (NOT SbRegDetected) AND (Port <= Lst) DO BEGIN
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

      IF NOT SbRegDetected THEN INC(Port, $10);
    END;

    SbRegDetect := SbRegDetected;

  END;


PROCEDURE SbRegInit;
  BEGIN

    IF NOT SbRegDetect THEN EXIT;

    IF NOT SbRegInited THEN
      BEGIN
(*
        SbWriteByte(SbDefTimeout, $E0);
        SbWriteByte(SbDefTimeout, $AA);
        SbResponse1 := SbReadByte (SbDefTimeout); { $55 }
        SbWriteByte(SbDefTimeout, $E4);
        SbWriteByte(SbDefTimeout, $AA);
        SbWriteByte(SbDefTimeout, $E8);
        SbResponse2 := SbReadByte (SbDefTimeout); { $AA }
*)
        SbGetDSPVersion;

        DoHiSpeed := (SbVersion > $200) AND SbHiSpeed {AND FALSE};
{
        IF DoHiSpeed THEN
          BEGIN
            SbWriteByte(SbDefTimeout, $48);
            SbWriteByte(SbDefTimeout, $00);
            SbWriteByte(SbDefTimeout, $00);
            SbWriteByte(SbDefTimeout, $91);
          END;
}
        SbWriteByte(SbDefTimeout, sdcTurnOnSpeaker);

      END;

    SbRegInited := TRUE;

  END;


PROCEDURE SbRegDone;
  BEGIN
    IF NOT (SbRegDetected AND SbRegInited) THEN EXIT;
{    SbWriteByte(SbDefTimeout, sdcTurnOffSpeaker);}
    SbRegDetected := FALSE;
    SbRegInited   := FALSE;
  END;




PROCEDURE SbGetDSPVersion;
  VAR
    i : WORD;
    t : WORD;
    s : STRING[2];
  BEGIN
    SbWriteByte(SbDefTimeout, sdcGetDSPVersion); { Send command. }
    t := 0;
    REPEAT
      SbVersionMaj := SbReadByte($FFFF);
      INC(t);
    UNTIL ((SbVersionMaj <> $AA) AND SbWorksOk) OR (t >= 10);
    SbVersionMin := SbReadByte(SbDefTimeout);

    STR(SbVersionMaj, SbVersionStr);
    SbVersionStr := SbVersionStr + '.';
    STR(SbVersionMin, s);
    IF SbVersionMin > 9 THEN SbVersionStr := SbVersionStr +       s
                        ELSE SbVersionStr := SbVersionStr + '0' + s;
  END;


PROCEDURE SbGetCopyrightString;
  VAR
    t : WORD;
  BEGIN
    SbWriteByte(SbDefTimeout, sdcGetCopyright); { Send command. }
    t := 0;
    REPEAT
      SbCopyright := CHAR(SbReadByte($FFFF));
      INC(t);
    UNTIL ((SbCopyright[1] <> #$AA) AND SbWorksOk) OR (t = 10);

    WHILE SbWorksOk AND (Length(SbCopyright) < 80) DO
      SbCopyright := SbCopyright + CHAR(SbReadByte(SbDefTimeout));

    DEC(SbCopyright[0]);
  END;


PROCEDURE SbSetTimeConst(tc: BYTE);
  BEGIN
    IF Sb16Detected THEN
      BEGIN
        IF Sb16Bit THEN
          SbWriteByte(SbDefTimeout, $D9)  { Send time constant command.             }
        ELSE
          SbWriteByte(SbDefTimeout, $DA); { Send time constant command.             }
      END;
    SbWriteByte(SbDefTimeout,   sdcSetTimeConst); { Send time constant command.             }
    SbWriteByte(SbDefTimeout*4, tc);              { Send the time constant.                 }
    TimeConst := 0;                               { Reset time constant to already changed. }
    IF Sb16Detected THEN
      IF Sb16Bit THEN
        SbWriteByte(SbDefTimeout, $47)  { Send time constant command.             }
      ELSE
        SbWriteByte(SbDefTimeout, $45); { Send time constant command.             }
  END;


PROCEDURE SbUpdateTimeConst;
  BEGIN
    IF TimeConst = 0 THEN EXIT;                 { If not changed then do nothing.         }
    SbSetTimeConst(TimeConst);
  END;


PROCEDURE SbStartSampleLS(Len: WORD; Cont: BOOLEAN);
  BEGIN
    HSBlockSpecified := 0;   { Reset Hi-speed block specifier, just in case. }

    SbWriteByte(SbDefTimeout, sdcStartLSpeedDMA); { Start DMA low speed command.   }
    SbWriteByte(SbDefTimeout, LO(Len));           { Low & high bytes of size.      }
    SbWriteByte(SbDefTimeout, HI(Len));
  END;


PROCEDURE SbStartSampleHS(Len: WORD; Cont: BOOLEAN);
  BEGIN
    IF HSBlockSpecified <> Len THEN Cont := FALSE;
    IF NOT Cont THEN
      BEGIN
        SbWriteByte(SbDefTimeout, sdcSetHSpeedSize);  { Set hi speed DMA block command. }
        SbWriteByte(SbDefTimeout, LO(Len));           { Low & high bytes of size.       }
        SbWriteByte(SbDefTimeout, HI(Len));
        HSBlockSpecified := Len;
      END;

    IF NOT (Sb16Detected AND Cont) THEN
      SbWriteByte(SbDefTimeout, sdcStartHSpeedDMA); { Start DMA in hi speed mode.    }
  END;


PROCEDURE SbPlaySample(Len: WORD; Cont: BOOLEAN);
  BEGIN

    IF Len < 10 THEN EXIT;   { Too short -> Discard. It wouldn't sound anyway. }

    IF SbStereo THEN INC(Len, Len); { Twice as big a buffer if stereo mode. }
    DEC(Len);                       { DMA sizes are always size - 1.        }

    IF Sb16Detected AND (SbStereo OR Sb16Bit) THEN
      Sb16StartSample(Len, Cont)
    ELSE IF DoHiSpeed THEN
      SbStartSampleHS(Len, Cont)
    ELSE
      SbStartSampleLS(Len, Cont);
  END;




{----------------------------------------------------------------------------}
{ Mixer generic routines.                                                    }
{____________________________________________________________________________}

FUNCTION MixerDetect : BOOLEAN;
  VAR
    SaveReg : WORD;
    NewReg  : WORD;
  BEGIN
    MixerDetect := MixerDetected;
    IF NOT SbRegDetect OR MixerDetected THEN EXIT;

    SaveReg := SbReadMixerReg($22);
    SbWriteMixerReg($22, 243);
    NewReg  := SbReadMixerReg($22);

    IF NewReg = 243 THEN
      MixerDetected := TRUE;

    SbWriteMixerReg($22, SaveReg);

    MixerDetect := MixerDetected;
  END;




PROCEDURE MixerSetVolume(Reg: TMixerVolume; VolLeft, VolRight: BYTE);
  VAR
    Addr   : BYTE;
    VolMax : BYTE;
  BEGIN
    IF NOT MixerDetected THEN EXIT;

    IF Sb16Detected THEN Addr := Sb16Regs [Reg]
                    ELSE Addr := SbProRegs[Reg];

    IF VolLeft > VolRight THEN VolMax := VolLeft
                          ELSE VolMax := VolRight;

    CASE Reg OF
      mvMicrophone : BEGIN
                       IF Sb16Detected THEN SbWriteMixerReg(Addr, VolMax)
                                       ELSE SbWriteMixerReg(Addr, VolMax SHR 5);
                     END;
      mvSpeaker    : BEGIN
                       IF Sb16Detected THEN SbWriteMixerReg(Addr, VolMax);
                     END;
    ELSE

      IF Sb16Detected THEN
        BEGIN
          SbWriteMixerReg(Addr,     VolLeft);
          SbWriteMixerReg(Addr + 1, VolRight);
        END
      ELSE
        SbWriteMixerReg(Addr, (VolLeft  AND $F0) +
                              (VolRight SHR   4));

    END;

  END;


FUNCTION MixerGetVolume(Reg: TMixerVolume; VAR VolLeft, VolRight: BYTE) : BOOLEAN;
  VAR
    Addr   : BYTE;
    VolMax : BYTE;
  BEGIN
    MixerGetVolume := FALSE;

    IF NOT MixerDetected THEN EXIT;

    IF Sb16Detected THEN Addr := Sb16Regs [Reg]
                    ELSE Addr := SbProRegs[Reg];

    VolLeft  := 0;
    VolRight := 0;

    MixerGetVolume := TRUE;

    CASE Reg OF
      mvMicrophone : BEGIN
                       IF Sb16Detected THEN VolLeft := SbReadMixerReg(Addr)
                                       ELSE VolLeft := SbReadMixerReg(Addr) SHL 5;
                       VolRight := VolLeft;
                     END;
      mvSpeaker    : BEGIN
                       IF Sb16Detected THEN VolLeft := SbReadMixerReg(Addr)
                                       ELSE MixerGetVolume := FALSE;
                       VolRight := VolLeft;
                     END;
    ELSE

      IF Sb16Detected THEN
        BEGIN
          VolLeft  := SbReadMixerReg(Addr);
          VolRight := SbReadMixerReg(Addr + 1);
        END
      ELSE
        BEGIN
          VolLeft  := SbReadMixerReg(Addr);
          VolRight := VolLeft SHL 4;
          VolLeft  := VolLeft AND $F0;
        END;

    END;

  END;




{----------------------------------------------------------------------------}
{ Sound Blaster Pro generic routines.                                        }
{____________________________________________________________________________}

FUNCTION SbProDetect : BOOLEAN;
  BEGIN
    SbProDetect := SbProDetected;
    IF SbProDetected THEN EXIT;

    IF NOT SbRegInited THEN SbRegInit;

    SbProDetected := SbRegDetect AND MixerDetect AND (SbVersion < $400);
    SbProDetect   := SbProDetected;
  END;


PROCEDURE SbProInit;
  BEGIN
    IF NOT SbProDetect THEN EXIT;
    SbProInited := TRUE;
  END;


PROCEDURE SbProDone;
  BEGIN
    SbRegDone;
  END;




PROCEDURE SbProSetStereo(Stereo: BOOLEAN);
  VAR
    i : BYTE;
  BEGIN
    IF NOT SbProDetected THEN EXIT;
    SbStereo := Stereo;
    i := SbReadMixerReg(mxrOutSetting);
    SbWriteMixerReg(mxrOutSetting, (i      AND NOT mxoStereoOn) +
                                   (BYTE(Stereo) * mxoStereoOn));
  END;


PROCEDURE SbProSetFilter(Filter: BOOLEAN);
  VAR
    i : BYTE;
  BEGIN
    IF NOT SbProDetected THEN EXIT;
    SbFilter := Filter;
    i := SbReadMixerReg(mxrOutSetting);
    SbWriteMixerReg(mxrOutSetting, (i      AND NOT mxoFilterNeg) +
                                   (BYTE(Filter) * mxoFilterNeg));
  END;




{----------------------------------------------------------------------------}
{ Sound Blaster 16 generic routines.                                         }
{____________________________________________________________________________}

FUNCTION Sb16Detect : BOOLEAN;
  BEGIN
    Sb16Detect := Sb16Detected;
    IF Sb16Detected THEN EXIT;

    IF NOT SbRegInited THEN SbRegInit;

    Sb16Detected := SbRegDetect AND MixerDetect AND (SbVersion >= $400);
    Sb16Detect   := Sb16Detected;
  END;


PROCEDURE Sb16Init;
  BEGIN
    IF NOT Sb16Detect THEN EXIT;

    SbGetCopyrightString;

    Sb16Inited := TRUE;
  END;


PROCEDURE Sb16Done;
  BEGIN
    SbRegDone;
  END;




PROCEDURE Sb16StartSample(Len: WORD; Cont: BOOLEAN);
  BEGIN

    IF (NOT Cont) OR (Sb16BlockSpecified <> Len){ OR TRUE }THEN
      BEGIN
        IF Sb16Bit THEN
          SbWriteByte(SbDefTimeout, $B6)    { Set 16 bit DMA transfer command. }
        ELSE
          SbWriteByte(SbDefTimeout, $C6);   { Set  8 bit DMA transfer command. }
        IF SbStereo THEN
          SbWriteByte(SbDefTimeout, $20)    { Set stereo mode.                 }
        ELSE
          SbWriteByte(SbDefTimeout, $00);   { Set mono mode.                   }
        SbWriteByte(SbDefTimeout, LO(Len));
        SbWriteByte(SbDefTimeout, HI(Len)); { Low & high bytes of size.        }
        Sb16BlockSpecified := Len;
      END
    ELSE
      BEGIN
        IF Sb16Bit THEN
          SbWriteByte(SbDefTimeout, $47)    { 16 bit DMA continue command. }
        ELSE
          SbWriteByte(SbDefTimeout, $45);   {  8 bit DMA continue command. }
      END;

  END;




END.
