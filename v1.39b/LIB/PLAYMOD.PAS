{****************************************************************************}
{                                                                            }
{ MODULE:         PlayMod                                                    }
{                                                                            }
{ DESCRIPTION:    This UNIT allows to play a music module (*.MOD) in any     }
{                 device supported in the SoundDevices sound system.         }
{                                                                            }
{                 Entrys:   PlayMod To begin playing the MOD.                }
{                           StopMod To stop playing the MOD.                 }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                 Luis Crespo (parts extracted from the JAMP 1.5 MOD Player) }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet... ;-)                                         }
{                                                                            }
{ HISTORY:        22-Jun-1992 Begins to use the SoundDevices sound system.   }
{                             Internal cleaning, which was quite needed.     }
{                             UnCanal routine made even faster.              }
{                 11-Nov-1992 Redocumentation. There have been really many   }
{                             enhancements since June, but they weren't      }
{                             documented. Mainly more speed-ups.             }
{                 24-Jan-1993 Added 8 voice support.                         }
{                                                                            }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT PlayMod;

INTERFACE

USES SongUnit, SongUtils, SongElements, ModCommands, SoundDevices, Filters, Kbd;




{ Definitions. }

TYPE
  TTickProc = PROCEDURE(VAR Song: TSong; note: BOOLEAN); { Procedure to execute every tick. }
  TVolumes  = ARRAY[1..MaxChannels] OF BYTE;             { Volume set (all channels). }




{ General definitions about the way of playing the music. }
{ Music player configuration.                             }

CONST
  PlayingSong        : PSong         = NIL;
  LoopMod            : BOOLEAN       = TRUE;   { TRUE if music can be played forever.                  }
  ForceLoopMod       : BOOLEAN       = FALSE;  { TRUE if music must be played forever.                 }
  CanFallBack        : BOOLEAN       = TRUE;   { TRUE if fall-back is allowed.                         }
  FilterOn           : TFilterMethod = fmNone; { Initial value of the ON  filter.                      }
  FilterOff          : TFilterMethod = fmNone; { Initial value of the OFF filter.                      }
  FilterIsOn         : BOOLEAN       = FALSE;  { Initial position of the filter (FALSE = OFF).         }
  MaxOutputFreq      : WORD          = 45000;  { Maximum frequency of the output sound.                }
                                               { Less means less memory for buffers.                   }
  DontExecute        : BOOLEAN       = FALSE;


VAR
  SplBuf             : ARRAY[1..MaxChannels] OF WORD;

                                                             
{ Exported variables. }

CONST
  Playing          : BOOLEAN = FALSE;       { (Read only) TRUE if the music is sounding right now.     }
  ModTickProcValid : BOOLEAN = FALSE;       { TRUE if the module tick procedure has been initialised.  }

VAR
  ActualHz        : WORD;                   { Desired freq. of the sound.                              }
  NoteHz          : WORD;                   { Freq. to be used in the current tick.                    }
  NoteCalcVal     : LONGINT;
  UserVols        : TVolumes;               { Channel volumes.                                         }
  Permisos        : ARRAY[1..MaxChannels] OF BOOLEAN; { Permissions for playing the channels.          }
  TickCount       : WORD;                   { Ticks counter. Increments each tick.                     }
  ModTickProc     : TTickProc;              { Tick procedure. A procedure to be executed every tick.   }
  MyCanFallBack   : BOOLEAN;                { Actual permission to fall-back.                          }
  FilterVal       : TFilterMethod;          { Method of the filter to be used.                         }
                                                             

{ Definition of the local stack. }

CONST
  PlayModStackSize = 500;   { Size of the stack. }

VAR
  PlayModStack     : ARRAY[1..PlayModStackSize] OF BYTE;     


{ Definitions concerning a note. Buffer of the last N notes. }

TYPE
  PPlayingNote = ^TPlayingNote;
  TPlayingNote = RECORD
    EoMod       : BOOLEAN;                 { TRUE if it is the note following the last.                }
    Tempo       : BYTE;                    { Number of ticks the note will last.                       }
    NotePlaying : BYTE;                    { Index of the note inside the pattern.                     }
    SeqPlaying  : BYTE;                    { Sequence number of the pattern to which the note belongs. }
    Volume      : TVolumes;                { Volumes of the channels.                                  }
    Note        : ARRAY[1..MaxChannels] OF TFullNote; { Notes of the channels.                       }
    NMuestras   : WORD;                    { Number of samples processed for each note.                }
    fill        : BYTE;                    { To make it a 32-byte record.                              }
  END;

CONST
  NoteBuffSize = 1;   { Number of note buffers. }

VAR
  NoteBuff      : ARRAY[0..NoteBuffSize-1] OF TPlayingNote;

CONST
  NoteTl        : WORD = 0;
  NoteHd        : WORD = 0;

  NoteSound     : PPlayingNote = NIL;
  NoteProcessed : PPlayingNote = NIL;

VAR
  Canales : ARRAY[1..MaxChannels] OF TCanal; { State of the channels. }




{----------------------------------------------------------------------------}
{ Definition of the buffers where the samples are placed.                    }
{____________________________________________________________________________}

CONST
  MaxSplPerTick : WORD = 880; { Maximum samples in the buffer. Means maximum samples per tick. }
  NumBuffers           = 3;   { Number of buffers.                                             }

VAR
  BuffIdx,         { Tail of the buffer. }
  BuffGive : WORD; { Head of the buffer. }

  Buffers       : ARRAY[1..NumBuffers] OF TSampleBuffer;
  SizeOfABuffer : WORD;



{----------------------------------------------------------------------------}
{ Exported procedures.                                                       }
{____________________________________________________________________________}

PROCEDURE PlayStart(VAR Song: TSong);
PROCEDURE PlayStop;

PROCEDURE ChangeSamplingRate(Hz: WORD);
PROCEDURE ProcessTickEntry;
PROCEDURE FillWithSamples   (VAR Buff; Size: WORD);




IMPLEMENTATION

USES Dos,
     Heaps,
     Output43,
     GUS,
     HexConversions,
     Debugging;




{----------------------------------------------------------------------------}
{ General definitions of the module player. They define its actual state.    }
{____________________________________________________________________________}

VAR
  DelaySamples    : BOOLEAN;     { TRUE means it couldn't fill the samples buffer.                }
  MuestrasPerTick : WORD;        { Number of samples that there are in a tick at the actual freq. }



{----------------------------------------------------------------------------}
{ Raw channel definitions.                                                   }
{____________________________________________________________________________}

TYPE
  PModRawChan = ^TModRawChan;
  TModRawChan = RECORD
    Flags      : BYTE;         { Channel flags (see below).                 }

    SplPosFrac : WORD;         { Position fraction.                         }
    SplPosInt  : WORD;         { Position offset.                           }
    SplPosSeg  : WORD;         { Position segment.                          }
                               
    SplOfs     : WORD;         { Actual sample part offset.                 }
    SplSeg     : WORD;         { Actual sample part segment.                }
    SplLimit   : WORD;         { Actual sample part size.                   }

    SplOfs1    : WORD;         { First  sample part offset.                 }
    SplSeg1    : WORD;         { First  sample part segment.                }
    SplLimit1  : WORD;         { First  sample part size.                   }

    SplOfs2    : WORD;         { Second sample part offset.                 }
    SplSeg2    : WORD;         { Second sample part segment.                }
    SplLimit2  : WORD;         { Second sample part size.                   }

    StepFrac   : WORD;         { Sample incement fraction.                  }
    StepInt    : WORD;         { Sample incement integer.                   }

    Volume     : BYTE;         { Volume to be used.                         }

    LoopEnd    : WORD;         { Offset of the end of the loop in its part. }
    LoopLen    : WORD;         { Size of the loop in its part.              }
  END;

CONST                      { TModRawChan.Flags }
  rcfLongSample     = $01; { Set if it's a long (more than 65520 bytes) sample.     }
  rcfActiveChannel  = $02; { Set if the channel is activated (permission to sound). }
  rcfDoesLoop       = $04; { Set of the sample has a loop.                          }
  rcfPlaying2nd     = $08; { Set if playing the 2nd part of the long loop.          }
  rcfLongLoopLen    = $10; { Loop size goes from the 2nd part to the 1st.           }
  rcfLongLoopEnd    = $20; { Loop ends in the 2nd part.                             }
  rcfSampleFinished = $40; { Set if the sample has already finished.                }

VAR                                                 { Raw channels. }
  RawChannels : ARRAY[1..MaxChannels] OF TModRawChan;




{----------------------------------------------------------------------------}
{ Basic, fast assembler routines.                                            }
{____________________________________________________________________________}



{$L PLAYMOD}

(*
FUNCTION DumpInstrument( VAR {FPointer} Src; VAR Dest: POINTER; Volume: BYTE;
                         Step: LONGINT; NumSrc, Max, ChanAdd: WORD; Empty: BOOLEAN)
                         : WORD; EXTERNAL;
*)

FUNCTION DumpInstrument(VAR {Pointer} Src; VAR {Pointer} Dest; Volume: BYTE;
                        Step: WORD; SrcLimit, Max, ChanAdd: WORD) : WORD; FAR; EXTERNAL;

FUNCTION DumpEmpty     (VAR {Pointer} Src; VAR {Pointer} Dest; Volume: BYTE;
                        Step: WORD; SrcLimit, Max, ChanAdd: WORD) : WORD; FAR; EXTERNAL;

PROCEDURE UnCanal(VAR Raw: TModRawChan; VAR Buf: POINTER);
  CONST
    Rest : WORD = 0;
  BEGIN

    Rest := MuestrasPerTick;

    IF ((Raw.Flags  AND rcfActiveChannel)  <> 0) AND
       ((Raw.Flags  AND rcfSampleFinished) =  0) {AND
       ( Raw.Volume                        <> 0) }{AND FALSE} THEN
      BEGIN
        IF (Raw.Flags AND rcfDoesLoop) <> 0 THEN
          WHILE Rest <> 0 DO
            BEGIN
              Rest := DumpInstrument( Raw.SplPosFrac, Buf, Raw.Volume,
                                      (Raw.StepFrac SHR 4) + (Raw.StepInt SHL 12){*65536},
                                      Raw.LoopEnd, Rest,
                                      NumChannels*2);
              IF Rest <> 0 THEN
                DEC(Raw.SplPosInt, Raw.LoopLen);
            END
        ELSE
          Rest := DumpInstrument( Raw.SplPosFrac, Buf, Raw.Volume,
                                  (Raw.StepFrac SHR 4) + (Raw.StepInt SHL 12){*65536},
                                  Raw.SplLimit, Rest,
                                  NumChannels*2);

      END;

    IF Rest > 0 THEN
      BEGIN
        IF (Raw.Flags AND rcfSampleFinished) = 0 THEN
          Rest := DumpEmpty     ( Raw.SplPosFrac, Buf, 0,
                                  (Raw.StepFrac SHR 4) + (Raw.StepInt SHL 12){*65536},
                                  Raw.SplLimit, Rest,
                                  NumChannels*2)
        ELSE
          Rest := DumpEmpty     ( Raw.SplPosFrac, Buf, 0,
                                  0,
                                  Raw.SplLimit, Rest,
                                  NumChannels*2);
        Raw.Flags := Raw.Flags OR rcfSampleFinished;
      END;

  END;





(*
{----------------------------------------------------------------------------}
{                                                                            }
{ ROUTINE: UnCanal                                                           }
{                                                                            }
{ Fills a buffer with 8 bit samples, calculated from a sample, a freq. and   }
{ a volume (a RawChannel).                                                   }
{ Implemented as several specialised routines, for speed's sake.             }
{ It doesn't play long samples yet.                                          }
{ This routine self-modifies, for speed's sake.                              }
{                                                                            }
{ IN:       CX    = Number of samples.                                       }
{           BX    = Offset of the channel data (TModRawChan).                }
{           DI    = Offset of the buffer to be filled.                       }
{                                                                            }
{ OUT:      The buffer will have been filled.                                }
{                                                                            }
{ MODIFIES: Every register except DS.                                        }
{                                                                            }
{............................................................................}

PROCEDURE UnCanal; ASSEMBLER;
  ASM
        MOV     AX,[SoundDevices.NumChannels]
        ADD     AX,AX
        MOV     WORD PTR [CS:@@dlData1-2],AX
        MOV     WORD PTR [CS:@@nlData1-2],AX
        MOV     WORD PTR [CS:@@Data1  -2],AX


        TEST    [TModRawChan(DS:BX).Flags],rcfActiveChannel  { ¨Active channel? }
        JZ      @@Desactivado                                { If not -> do the silent loop }

        TEST    [TModRawChan(DS:BX).Flags],rcfSampleFinished { ¨Already finished? }
        JNZ     @@Desactivado                                { If it is -> do the silent loop }

        TEST    BYTE PTR [TModRawChan(DS:BX).Volume],$FF     { Volumen }
        JZ      @@Desactivado

        PUSH    BX                                           { BX is saved for restoring data at the end }

        TEST    [TModRawChan(DS:BX).Flags],rcfDoesLoop       { ¨Does the sample have a loop? }
        JZ      @@NoDoesLoop                                 { If not -> do the loop-less routine }

{

  Sample with a loop (it doesn't check the end of the sample).

}

        MOV     AX,[TModRawChan(DS:BX).LoopEnd]              
        MOV     WORD PTR [CS:@@dlData2-2],AX                 { Puts the loop-end OFFSET in its instruction }

        MOV     AX,[TModRawChan(DS:BX).LoopLen]              
        MOV     WORD PTR [CS:@@dlData3-2],AX                 { Puts the loop-size in its instruction }

        MOV     DL,BYTE PTR [TModRawChan(DS:BX).Volume]      { Volume }
        MOV     AL,[TModRawChan(DS:BX).StepFrac]             { Increment fraction }
        MOV     BP,[TModRawChan(DS:BX).StepInt]              { Increment integer  }

        MOV     AH,[TModRawChan(DS:BX).SplPosFrac]           { Position OFFSET }

        LDS     SI,DWORD PTR [TModRawChan(DS:BX).SplPosInt]  { Pointer to the next sample to be read }

        MOV     BX,AX   { ­­­No tocar!!! (BX es el puntero al buffer) }
{

      Bucle. Se entra con:
        DL = Volumen
        BL = Parte fraccionaria del incremento.
        BP = Parte entera del incremento.
        BH = Parte fraccionaria de la posici¢n en el sample.
        SI = Parte entera de la posici¢n en el sample.
        ES = Segmento del buffer.
        DS = Segmento del sample.
        DI = Buffer donde se almacenan las muestras.
        CX = N£mero total de muestras a generar.

}

@@dlLoop:
        MOV     AL,[SI]                                      { Leo la muestra correspondiente }
        IMUL    DL                                           { Multiplico por el volumen }
        MOV     [ES:DI],AX                                   { Lo meto en el buffer (Instrucci¢n automodificada) }
        ADD     DI,$1234
@@dlData1:

        ADD     BH,BL                                        { A¤ade el incremento fraccionario }
        ADC     SI,BP                                        { A¤ade el incremento entero }
        JC      @@dlSplLoop                                  { Carry -> Ha pasado el l¡mite, seguro }
                                                             { (m ximo n§ de muestras = 65520) }
@@dlChkLoop:
        CMP     SI,$1234                                     { CMP BP,[TModRawChan(DS:BX).LoopEnd] }
@@dlData2:                                                   { ¨He llegado al pto. de retorno del loop? }
        JB      @@dlNoLoop

@@dlSplLoop:
        SUB     SI,$1234                                     { SUB BP,[TModRawChan(DS:BX).LoopLen] }
@@dlData3:                                                   { Si es as¡, vuelvo para atr s. Esto es muy importante hacerlo }
                                                             { restando el tama¤o del bucle, y conservando la parte frac. }

@@dlNoLoop:
        LOOP    @@dlLoop                                     { Y fin del bucle }

        JMP     @@Finish                                     { Salta al final, donde se almacenan los valores de por donde }
                                                             { han quedado los punteros y dem s }

{

  Sample sin loop (no comprueba el fin de loop).
  Filosof¡a igual al anterior.

}

@@NoDoesLoop:

        MOV     AX,[TModRawChan(DS:BX).SplLimit]             { Pone el OFFSET del fin del sample en la instrucci¢n }
        MOV     WORD PTR [CS:@@nlData2-2],AX

        MOV     DL,BYTE PTR [TModRawChan(DS:BX).Volume]      { Volumen }
        MOV     AL,[TModRawChan(DS:BX).StepFrac]             { Parte fraccionaria del incremento }
        MOV     AH,[TModRawChan(DS:BX).SplPosFrac]           { Parte fraccionaria del OFFSET del puntero a la muestra }

        MOV     BP,[TModRawChan(DS:BX).StepInt]              { Parte entera del incremento }

        LDS     SI,DWORD PTR [TModRawChan(DS:BX).SplPosInt]  { Puntero a la pr¢xima muestra a leer }

        MOV     BX,AX   { ­­­No tocar!!! (BX es el puntero al buffer) }

{

      Bucle. Se entra con:
        DL = Volumen
        BL = Parte fraccionaria del incremento.
        BP = Parte entera del incremento.
        BH = Parte fraccionaria de la posici¢n en el sample.
        SI = Parte entera de la posici¢n en el sample.
        ES = Segmento del buffer.
        DS = Segmento del sample.
        DI = Buffer donde se almacenan las muestras.
        CX = N£mero total de muestras a generar.

}

@@nlLoop:
        MOV     AL,[SI]                                      { Leo la muestra correspondiente }
        IMUL    DL                                           { Multiplico por el volumen }
        MOV     [ES:DI],AX                                   { Lo meto en el buffer }
        ADD     DI,$1234
@@nlData1:

        ADD     BH,BL                                        { A¤ade el incremento fraccionario }
        ADC     SI,BP                                        { A¤ade el incremento entero }
        JC      @@nlSeguroFin                                { Carry -> Ha pasado el l¡mite del sample, seguro }
                                                             { (m ximo n§ de muestras = 65520) }

        CMP     SI,$1234                                     { CMP BP,[TModRawChan(DS:BX).SplLimit] }
@@nlData2:                                                   { ¨He llegado al final del sample? }
        JNB     @@nlSeguroFin                                { Si es as¡, dejo de calcular }

@@nlNoLoop:
        LOOP    @@nlLoop                                     { Y fin del bucle }

        JMP     @@Finish                                     { Salta al final, donde se almacenan los valores de por donde }
                                                             { han quedado los punteros y dem s }

@@nlSeguroFin:                                               { Se ha terminado el sample }
        MOV     BX,SEG @Data                                 { Reinicializamos DS }
        MOV     DS,BX
        POP     BX                                           { Recupera el TModRawChan en BX }
        OR      BYTE PTR [TModRawChan(DS:BX).Flags],rcfSampleFinished                { Desactivo el canal }
        DEC     CX                                           { Decrementa el n£mero de muestras, no se ha podido hacer antes }
        JCXZ    @@Fin                                        { Si ya no hay m s -> bye }

{

  Bucle correspondiente a un sample vac¡o. No se puede eliminar
  porque tiene que, por lo menos, poner el buffer a cero.

}

@@Desactivado:
        XOR     AX,AX                                        { Todas las muestras a cero }
@@Data2:
        MOV     [ES:DI],AX                                   { Le meto el cero en el buffer }
        ADD     DI,$1234
@@Data1:
        LOOP    @@Data2                                      { Fin del bucle }

        JMP     @@Fin                                        { Y me vuelvo sin restaurar nada }







@@Finish:
        MOV     BP,SEG @Data                                 { Reinicializamos DS }
        MOV     DS,BP
        POP     BP                                           { Recupero el TModRawChan }
        MOV     [TModRawChan(DS:BP).SplPosInt],SI            { Y guardo el OFFSET del sample donde se ha quedado }
        MOV     [TModRawChan(DS:BP).SplPosFrac],BH

@@Fin:
        MOV     AX,SEG @Data                                 { Reinicializamos DS }
        MOV     DS,AX
  END;
*)




{----------------------------------------------------------------------------}
{ Rutinas que se dedican a interpretar la partitura.                         }
{____________________________________________________________________________}




{----------------------------------------------------------------------------}
{                                                                            }
{ RUTINA: SetNewSample                                                       }
{                                                                            }
{ Inicializa un nuevo sample en uno de los canales.                          }
{                                                                            }
{ ENTRADAS: Raw : TModRawChan correspondiente al canal.                      }
{           Spl : TSample correspondinte al canal.                           }
{                                                                            }
{ SALIDAS:  Ninguna.                                                         }
{                                                                            }
{............................................................................}

PROCEDURE SetNewSample(i: BYTE; VAR Raw: TModRawChan; Spl: PInstrumentRec; Offs: WORD);
  CONST
    _or : BYTE    = 0;
    f   : BOOLEAN = FALSE;
  BEGIN
{    FillChar(Raw, SizeOf(Raw), 0);}

    IF Spl = NIL THEN EXIT;

    ASM

        MOV     DI,WORD PTR Raw
        LES     SI,Spl

        MOV     AX,WORD PTR TInstrumentRec([ES:SI]).data
        MOV     TModRawChan([DI]).SplOfs1,AX
        MOV     AX,WORD PTR TInstrumentRec([ES:SI+2]).data
        MOV     TModRawChan([DI]).SplSeg1,AX                              { Inicializa los valores m¡nimos }
        MOV     _or,rcfActiveChannel

        MOV     AX,WORD PTR TInstrumentRec([ES:SI+1]).repl
        AND     AX,AX
        JNZ     @@1
         MOV    AL,BYTE PTR TInstrumentRec([ES:SI]).repl
         CMP    AL,4
         JNB    @@1
         MOV    f,1
         JMP    @@2
@@1:    MOV     f,0                                     { Si tiene loop (no s‚ si es buena la comprobaci¢n }
        OR      _or,rcfDoesLoop
@@2:

      END;

(*
    Raw.SplOfs1   := OFS(Spl^.data^);
    Raw.SplSeg1   := SEG(Spl^.data^);                                      { Inicializa los valores m¡nimos }
    _or           := rcfActiveChannel;

    f := Spl^.repl <= 4;
    IF NOT f THEN INC(_or, rcfDoesLoop);                { Si tiene loop (no s‚ si es buena la comprobaci¢n }
*)

    IF Spl^.len > MaxSample THEN BEGIN

      ASM

        MOV     DI,WORD PTR Raw                  { Entra aqu¡ si es un sample largo (mayor de 65520 bytes) }
        LES     SI,Spl

        OR      _or,rcfLongSample
        MOV     TModRawChan([DI]).SplLimit1,MaxSample

      END;

(*
      INC(_or, rcfLongSample);                   { Entra aqu¡ si es un sample largo (mayor de 65520 bytes) }

      Raw.SplLimit1 := MaxSample;
*)
      Raw.SplLimit2 := Spl^.len - MaxSample;                      { Inicializa valores para el sample largo }
      Raw.SplOfs2   := OFS(Spl^.xtra^);
      Raw.SplSeg2   := SEG(Spl^.xtra^);

      IF NOT f THEN BEGIN                                                   { Si hay loop, peque¤o l¡o :-) }
        IF (Spl^.reps > MaxSample) OR (Spl^.reps+Spl^.repl <= MaxSample) THEN
          Raw.LoopLen := Spl^.repl
        ELSE BEGIN
          Raw.LoopLen := Spl^.repl - MaxSample;
          INC(_or, rcfLongLoopLen);
        END;
        IF Spl^.reps+Spl^.repl <= MaxSample THEN
          Raw.LoopEnd := Spl^.reps + Spl^.repl
        ELSE BEGIN
          Raw.LoopEnd := Spl^.reps + Spl^.repl - MaxSample;
          INC(_or, rcfLongLoopEnd);
        END;
      END;
    END ELSE BEGIN

      ASM

        MOV     DI,WORD PTR Raw                { Entra aqu¡ si es un sample peque¤o (menor de 65520 bytes) }
        LES     SI,Spl

        MOV     AX,WORD PTR TInstrumentRec([ES:SI]).len
        MOV     TModRawChan([DI]).SplLimit1,AX

        MOV     AL,f
        AND     AL,AL
        JNZ     @@1
         MOV    AX,WORD PTR TInstrumentRec([ES:SI]).repl
         MOV    TModRawChan([DI]).LoopLen,AX
         ADD    AX,WORD PTR TInstrumentRec([ES:SI]).reps
         MOV    TModRawChan([DI]).LoopEnd,AX
{         MOV    TModRawChan([DI]).SplLimit1,AX}
@@1:

      END;

(*
      Raw.SplLimit1 := Spl^.len;                { Entra aqu¡ si es un sample peque¤o (menor de 65520 bytes) }

      IF NOT f THEN BEGIN                                                                    { Si hay loop }
        Raw.LoopEnd := Spl^.reps + Spl^.repl;
        Raw.LoopLen := Spl^.repl;
      END;
*)
    END;

    ASM

        MOV     DI,WORD PTR Raw                

        MOV     TModRawChan([DI]).SplPosFrac,0

        MOV     AX,TModRawChan([DI]).SplOfs1
        MOV     TModRawChan([DI]).SplPosInt,AX
        MOV     TModRawChan([DI]).SplOfs,AX

        MOV     AX,TModRawChan([DI]).SplSeg1
        MOV     TModRawChan([DI]).SplPosSeg,AX
        MOV     TModRawChan([DI]).SplSeg,AX

        MOV     AX,TModRawChan([DI]).LoopEnd
        ADD     AX,TModRawChan([DI]).SplOfs1
        MOV     TModRawChan([DI]).LoopEnd,AX

        MOV     AX,TModRawChan([DI]).SplLimit2
        ADD     AX,TModRawChan([DI]).SplOfs2
        MOV     TModRawChan([DI]).SplLimit2,AX

        MOV     AX,TModRawChan([DI]).SplLimit1
        ADD     AX,TModRawChan([DI]).SplOfs1
        MOV     TModRawChan([DI]).SplLimit1,AX
        MOV     TModRawChan([DI]).SplLimit,AX

        MOV     AL,_or
        MOV     TModRawChan([DI]).Flags,AL

    END;
(*
    Raw.SplPosFrac := 0;
    Raw.SplPosInt  := Raw.SplOfs1;
    Raw.SplPosSeg  := Raw.SplSeg1;

    Raw.SplOfs   := Raw.SplOfs1;
    Raw.SplSeg   := Raw.SplSeg1;
    Raw.SplLimit := Raw.SplLimit1;

    Raw.Flags  := _or;
*)
    IF UsingGUS THEN
      IF (Raw.Flags AND rcfDoesLoop) <> 0 THEN
        TriggerVoice(i-1, $FF, $FFFFFFFF, PlayingSong^.PanPositions[i],
                     LONGINT(Spl^.Data) + Offs,
                     LONGINT(Spl^.Data) + Spl^.Reps,
                     LONGINT(Spl^.Data) + Spl^.Reps + Spl^.Repl)
      ELSE
        TriggerVoice(i-1, $FF, $FFFFFFFF, PlayingSong^.PanPositions[i],
                     LONGINT(Spl^.Data) + Offs, -1,
                     LONGINT(Spl^.Data) + Spl^.Len);

  END;





PROCEDURE MyMove(VAR Src, Dest; Bytes: WORD); ASSEMBLER;
  ASM
                PUSH    DS

                LDS     SI,[Src]
                LES     DI,[Dest]
                MOV     CX,[Bytes]

                CLD

                AND     CX,CX
                JZ      @@Fin

                TEST    SI,1
                JZ      @@nobeg
                 MOVSB
                 DEC    CX
                 JZ     @@Fin

@@nobeg:        MOV     BX,CX
                SHR     CX,1
                REP MOVSW
                MOV     CX,BX
                AND     CL,1
                JZ      @@Fin

                MOVSB
@@Fin:
                POP     DS
  END;




PROCEDURE ConvertPeriod(VAR v: WORD);
  CONST
{
    NoteTable : ARRAY[0..11] OF WORD = ( $D600,$C9FD,$BEA7,$B3F4,
                                         $A9DA,$A052,$9752,$8ED4,
                                         $86D0,$7F3F,$781A,$715D );
    NoteTableF: ARRAY[0..11] OF WORD = ( $D600,$C9FD,$BEA7,$B3F4,
                                         $A9DA,$A052,$9752,$8ED4,
                                         $86D0,$7F3F,$781A,$715D );
}
    NoteTable : ARRAY[0..11] OF WORD = ( $D600,$CA00,$BE80,$B400,
                                         $A980,$A000,$9700,$8E80,
                                         $8680,$7F00,$7800,$7160 );
  VAR
    i, j, k, n, o : WORD;
  BEGIN
    IF v = 0 THEN EXIT;

    j := $6FA;
    o := 0;
    WHILE v < ((j+1) SHR 1) DO
      BEGIN
        j := j SHR 1;
        INC(o);
      END;

    k := 10000;
    FOR j := 0 TO 11 DO
      IF (v SHL (5+o)) >= NoteTable[j] THEN
        BEGIN
          IF k > (v SHL (5+o)) - NoteTable[j] THEN
            BEGIN
              k := (v SHL (5+o)) - NoteTable[j];
              n := j;
            END;
        END
      ELSE
        BEGIN
          IF k > NoteTable[j] - (v SHL (5+o)) THEN
            BEGIN
              k := NoteTable[j] - (v SHL (5+o));
              n := j;
            END;
        END;

    v := ((NoteTable[n] SHR (o+2))+1) SHR 1;
  END;





{----------------------------------------------------------------------------}
{                                                                            }
{ PROCEDIMIENTO: ProcessNewNote                                              }
{                                                                            }
{ Calcula y procesa la siguiente nota de la partitura.                       }
{                                                                            }
{ ENTRADAS: Ninguna.                                                         }
{                                                                            }
{ SALIDAS:  Ninguna.                                                         }
{                                                                            }
{............................................................................}

PROCEDURE ProcessNewNote(VAR Song: TSong);
  CONST
    i    : WORD        = 0;
    j    : WORD        = 0;
    n    : TFullNote   = (Instrument:0);
    can  : ^TCanal     = NIL;
    Patt : PPattern    = NIL;
    NewSample : BOOLEAN = FALSE;
  BEGIN

{    SetBorder($FF, 0, 0);}

    i := (NoteHd + 1) AND (NoteBuffSize - 1);
    NoteProcessed := @NoteBuff[i];
    MyMove(NoteBuff[NoteHd], NoteProcessed^, SIZEOF(NoteBuff[0]));
    NoteHd := i;
    WITH NoteProcessed^ DO BEGIN

      REPEAT
        EoMod       := NextNote = $FFFF;

        IF EoMod THEN
          IF MyLoopMod THEN BEGIN
            NextSeq := MyRepStart;

            IF NextSeq < MyFirstPattern THEN
              NextSeq := MyFirstPattern;

            NextNote  := 1;
            EoMod     := FALSE;
          END ELSE BEGIN
            Playing   := FALSE;
            EXIT;
          END;

        NotePlaying := NextNote;
        SeqPlaying  := NextSeq;
        Volume      := UserVols;

        IF Song.GetPatternSequence(SeqPlaying) >= Song.Patterns.Count THEN
          BEGIN
            INC(NextSeq);
            IF NextSeq > MySongLen THEN NextNote := $FFFF
                                   ELSE NextNote := 1;
          END;
      UNTIL Song.GetPatternSequence(SeqPlaying) < Song.Patterns.Count;


      Patt := Song.GetPatternSeq(SeqPlaying);

      IF NextNote < Patt^.Patt^.NNotes THEN
        INC(NextNote)
      ELSE BEGIN
        INC(NextSeq);
        IF NextSeq > MySongLen THEN NextNote := $FFFF
                               ELSE NextNote := 1;
      END;

      IF Song.GetPatternSequence(SeqPlaying)  = 0 THEN
        BEGIN
          FillChar(Canales, SIZEOF(Canales), 0);
          ModCommands.Tempo        := Song.InitialTempo;
          ModCommands.BPMIncrement := Song.InitialBPM;

          FOR i := 1 TO MaxChannels DO
            WITH Canales[i] DO BEGIN
              Note.Period     := 800;
              Note.Instrument := 1;
              Note.Command    := mcNone;
              Period          := 800;
            END;

          REPEAT
            INC(SeqPlaying);
            IF SeqPlaying > MySongLen THEN NextNote := $FFFF
                                      ELSE NextNote := 2;
          UNTIL (NextNote = $FFFF) OR (Song.GetPatternSequence(SeqPlaying) <> 0);

          NextSeq := SeqPlaying;
        END;

      IF NotePlaying = 1 THEN
        IF Song.GetPatternTempo(SeqPlaying) <> 0 THEN
          ModCommands.Tempo := Song.GetPatternTempo(SeqPlaying)
        ELSE IF Patt^.Patt^.Tempo <> 0 THEN
          ModCommands.Tempo := Patt^.Patt^.Tempo;

      FOR j := 1 TO Song.NumChannels DO BEGIN

        can := @Canales[j];

        Song.GetNote(SeqPlaying, NotePlaying, j, n);

        ConvertPeriod(n.Period);

        MyMove(n, Note[j], SIZEOF(n));

        NewSample := FALSE;
        IF ((n.Instrument <> 0)                     AND
            (can^.Note.Instrument <> n.Instrument)) OR
           ((0 <> n.Period)                         AND
            (n.Command <> mcNPortamento)            AND
            (n.Command <> mcT_VSlide))             THEN
          BEGIN
            IF n.Instrument <> 0 THEN
              BEGIN
                can^.Note.Instrument := n.Instrument;
                can^.Instrument      := PInstrument(Song.GetInstrument(n.Instrument))^.Instr;
              END;

            SetNewSample(j, RawChannels[j], can^.Instrument, 0);
            NewSample := TRUE;
          END;

        IF (n.Instrument <> 0) AND (can^.Instrument <> NIL) THEN
          can^.Volume := can^.Instrument^.Vol;

        IF n.Volume <> 0 THEN
          can^.Volume := n.Volume - 1;

        IF can^.Volume > 64 THEN can^.Volume := 64;

        CommandStart(Song, can^, n);

        IF NewSample AND can^.SOffs THEN
          SetNewSample(j, RawChannels[j], can^.Instrument, can^.SOffsVal);

        NoteProcessed^.Tempo := ModCommands.Tempo;

      END;

      MuestrasPerTick := ActualHz DIV TicksPerSecond;

      IF MuestrasPerTick > MaxSplPerTick THEN
        MuestrasPerTick := MaxSplPerTick;

      NMuestras       := MuestrasPerTick * Tempo;
      NoteHz          := ActualHz;
      IF NoteHz = 0 THEN NoteHz := 1;
{      NoteCalcVal     := ((65536*13900) DIV NoteHz) SHL 8;}
      NoteCalcVal     := ((LONGINT(13900) SHL 12) DIV NoteHz) SHL 11;
    END;

    NoteTl    := NoteHd;
    NoteSound := NoteProcessed;

{    SetBorder(0, 0, 0);}

  END;




PROCEDURE FillChannels(VAR Song: TSong);
  CONST
    FirstTick : BOOLEAN       = TRUE;
    i         : WORD          = 0;
    p         : ^TModRawChan  = NIL;
    q         : POINTER       = NIL;
    Buf       : PSampleBuffer = NIL;
  BEGIN

{    SetBorder($FF, $FF, $FF);}

    Buf := @Buffers[BuffIdx];

    DelaySamples := Buf^.InUse;
    IF DelaySamples THEN
      BEGIN
        EXIT;
      END;


    FOR i := 1 TO Song.NumChannels DO BEGIN
      p := @RawChannels[i];
      q := Addr(Buf^.IData^[i-1]);

      UnCanal(p^, q);

{
      ASM
        PUSH    BP
        PUSH    DI
        PUSH    SI
        PUSH    ES
        MOV     CX,MuestrasPerTick
        MOV     BX,WORD PTR p
        LES     DI,q
        CALL    UnCanal
        POP     ES
        POP     SI
        POP     DI
        POP     BP
      END;
}
      SplBuf[i] := FilterChunkWord(q^, MuestrasPerTick, Song.NumChannels, FilterVal, SplBuf[i]);
    END;

    Buf^.InUse    := TRUE;
    Buf^.NSamples := MuestrasPerTick;
    Buf^.RateHz   := NoteHz;
    Buf^.DataType := dtInteger;
    Buf^.Channels := Song.NumChannels;

    INC(BuffIdx);
    IF BuffIdx > NumBuffers THEN BuffIdx := 1;

{    SetBorder($FF, 0, 0);}

  END; { PROCEDURE FillChannels }

{----------------------------------------------------------------------------}
{                                                                            }
{ PROCEDIMIENTO: ProcessTick                                                 }
{                                                                            }
{ Procesa un tick de la m£sica. Normalmente, se usan 50 ticks por segundo,   }
{ pero puede cambiarse.                                                      }
{                                                                            }
{ ENTRADAS: Ninguna.                                                         }
{                                                                            }
{ SALIDAS:  Ninguna.                                                         }
{                                                                            }
{............................................................................}

PROCEDURE ProcessTick(VAR Song: TSong);
  CONST
    SOTCanal = SIZEOF(TCanal);
    incr     : INTEGER     = 0;
    OTempoCt : WORD        = 0;
    Can      : PCanal      = NIL;
    Raw      : PModRawChan = NIL;
    NoteHzFreq : LONGINT   = 0;
    i        : WORD        = 0;
    j        : WORD        = 0;
    t        : WORD        = 0;
    step     : LONGINT     = 0;
    FBCount  : WORD        = 0;
    NumChannels : BYTE     = 0;
  VAR
    ScrTrace : WORD ABSOLUTE $B800:20;
  LABEL
    Fin;
  BEGIN 

    IF DelaySamples AND NOT UsingGUS THEN BEGIN
      FillChannels(Song);

      IF DelaySamples THEN GOTO Fin;
    END;

    INC(TickCount);

    NumChannels := Song.NumChannels;

    OTempoCt := TempoCt;
    INC(BPMCount, BPMIncrement);
    INC(TempoCt, BPMCount DIV BPMDivider);
    IF TempoCt <> OTempoCt THEN
      BPMCount := BPMCount MOD BPMDivider;

    i := TempoCt - OTempoCt;
    TempoCt := OTempoCt;
    FOR t := i DOWNTO 1 DO
      BEGIN
        INC(TempoCt);

        IF TempoCt >= NoteProcessed^.Tempo THEN BEGIN
          ProcessNewNote(Song);

          IF NOT Playing THEN GOTO Fin;
          TempoCt := 0;
        END;

        IF (TempoCt > 0) OR Song.FirstTick THEN
          ASM
                    XOR     CH,CH
                    MOV     CL,[NumChannels]
    @@lp:            PUSH   CX
                     MOV    AL,CL
                     DEC    AL
                     MOV    BL,SOTCanal
                     MUL    BL
                     MOV    SI,OFFSET Canales
                     ADD    SI,AX
                     MOV    BL,TCanal([SI]).Note.Command
                     ADD    BL,BL
                     XOR    BH,BH
                     CALL   DoTickCommand
                     POP    CX
                     LOOP   @@lp
          END;

      END;

    IF NOT MyCanFallBack THEN
      PleaseFallBack := 0;

    IF PleaseFallBack > 0 THEN BEGIN
      PleaseFallBack := 0;
      i := ActualHz;
      WHILE (i = ActualHz) AND (i <> ActiveDevice^.GetRealFreqProc(0)) DO
        BEGIN
          DEC(DesiredHz, 100);
          i := ActiveDevice^.GetRealFreqProc(DesiredHz);
        END;
      ChangeSamplingRate(DesiredHz);
    END;

    FOR i := 1 TO Song.NumChannels DO
      BEGIN
        SetBorder(63, 0, 63);

        Can := @Canales[i];
        Raw := @RawChannels[i];

        IF NOT UsingGUS THEN
          Raw^.Volume := (Can^.Volume*WORD(UserVols[i]) SHR 4) DIV
                         ((Song.NumChannels + 1) AND $FFFE)
        ELSE
          Raw^.Volume := (((Can^.Volume*WORD(UserVols[i])) SHR 6) + 1) SHR 1;

        IF Raw^.Volume >= $80 THEN Raw^.Volume := $7F;

        IF Can^.Period > $7FFF THEN Can^.Period := $7FFF;

        IF Can^.Instrument <> NIL THEN
          ASM
                LES     SI,[Can]
                MOV     AX,TCanal([ES:SI]).Period
                LES     SI,TCanal([ES:SI]).Instrument
                MOV     DX,TInstrumentRec([ES:SI]).NAdj
                MUL     DX
                MOV     BX,TInstrumentRec([ES:SI]).DAdj
                DIV     BX

                LES     SI,[Can]
                MOV     TCanal([ES:SI]).RealPeriod,AX
          END
        ELSE
          BEGIN
            Can^.RealPeriod := Can^.Period;
            Raw^.Volume     := 0;
            Raw^.Flags      := Raw^.Flags AND NOT rcfActiveChannel;
          END;


        IF      Can^.RealPeriod <   $7F THEN Can^.RealPeriod :=   $7F
        ELSE IF Can^.RealPeriod > $7FFF THEN Can^.RealPeriod := $7FFF;

IF NOT UsingGUS THEN
        ASM

                MOV     AX,[WORD PTR NoteCalcVal]
                MOV     DX,[WORD PTR NoteCalcVal+2]
                LES     SI,[Can]
                MOV     BX,TCanal([ES:SI]).RealPeriod
                DIV     BX
                ADD     DX,DX
                CMP     DX,BX
                JC      @@1
                 INC    AX
        @@1:
                MOV     [WORD PTR step],AX

        END
ELSE
  step := $1000;

        Raw^.StepFrac := WORD(step SHL 4);
        Raw^.StepInt  := WORD(step SHR 12);

        IF FilterIsOn THEN FilterVal := FilterOn
                      ELSE FilterVal := FilterOff;

        IF Can^.doretrig AND (Can^.Instrument <> NIL) THEN
          SetNewSample(i, Raw^, Can^.Instrument, 0);

        IF NOT Permisos[i] THEN Raw^.Flags := Raw^.Flags AND NOT rcfActiveChannel
                           ELSE Raw^.Flags := Raw^.Flags OR      rcfActiveChannel;

        IF UsingGUS THEN
          IF Permisos[i] THEN
            ChangeVoiceParams(i-1, Raw^.Volume,
                                   (LONGINT(1024)*13900 + (Can^.RealPeriod SHR 1)) DIV Can^.RealPeriod,
                                   PlayingSong^.PanPositions[i])
          ELSE
            ChangeVoiceParams(i-1, 0,
                                   $FFFFFFFF, {(LONGINT(256)*13900) DIV Can^.RealPeriod,}
                                   PlayingSong^.PanPositions[i]);

        IF      Can^.Period <   $7F THEN Can^.Period :=   $7F
        ELSE IF Can^.Period > $7FFF THEN Can^.Period := $7FFF;

        SetBorder(0, 0, 0);

      END;

    IF NOT UsingGUS THEN
      FillChannels(Song);

Fin:
  END;

{----------------------------------------------------------------------------}
{                                                                            }
{ PROCEDIMIENTO: ProcessTickEntry                                            }
{                                                                            }
{ Entrada desde ensamblador de ProcessTick.                                  }
{                                                                            }
{ ENTRADAS: Ninguna.                                                         }
{                                                                            }
{ SALIDAS:  Ninguna.                                                         }
{                                                                            }
{............................................................................}

PROCEDURE ProcessTickEntry;
  CONST
    Semaphor : BYTE        = 0;
    _SS      : WORD        = 0;
    _SP      : WORD        = 0;
    SaveFlags: WORD        = 0;
  VAR
    ScrInc : WORD ABSOLUTE $B800:180;
  LABEL
    Fin1, Fin2;
  BEGIN
    IF DontExecute THEN EXIT;

{  INC(ScrInc);}

{
    ASM
        PUSHF
        POP     AX
        MOV     [SaveFlags],AX
        STI
    END;
}

    IF NOT Playing THEN
      BEGIN
        TempoCT := 1;
        GOTO Fin1;
      END;

    IF Semaphor <> 0 THEN
      GOTO Fin2;

    INC(Semaphor);

    ASM
        MOV     [_SS],SS
        MOV     [_SP],SP
        MOV     AX,DS
        MOV     SS,AX
        MOV     SP,OFFSET PlayModStack + PlayModStackSize
    END;
{DirectWrite(0, HexWord(ActualHz));}
    ProcessTick(PlayingSong^);

    ASM
        MOV     SS,[_SS]
        MOV     SP,[_SP]
    END;

    DEC(Semaphor);

Fin1:

    IF ModTickProcValid THEN 
      ModTickProc(PlayingSong^, TempoCt = 0);

Fin2:
{
    ASM
        MOV     AX,[SaveFlags]
        PUSH    AX
        POPF
    END;
}

  END;




FUNCTION IdleGiver : PSampleBuffer; FAR;
  BEGIN
    IdleGiver := NIL;
  END;


FUNCTION BufferGiver : PSampleBuffer; FAR;
  BEGIN
    BufferGiver := NIL;
    IF NOT Buffers[BuffGive].InUse THEN EXIT;
    BufferGiver := @Buffers[BuffGive];
    INC(BuffGive);
    IF BuffGive > NumBuffers THEN BuffGive := 1;
  END;




PROCEDURE FillWithSamples(VAR Buff; Size: WORD);
  CONST
    mBuff : PIntBuff = NIL;
  BEGIN
;EXIT;
    mBuff := DMABufferPtr;
    IF Stereo THEN
      BEGIN
        IF DMABufferEnd - WORD(mBuff) < Size*2 THEN
          mBuff := DMABuffer;

        ASM
                PUSH    DS

                CLD
                LES     DI,[Buff]
                MOV     CX,[Size]
                LDS     SI,[mBuff]

        @@lp1:
                LODSB
                XCHG    AL,AH
                LODSB
                XOR     AX,$8080
                ADD     AH,AL
                MOV     AL,0
                ROR     AX,1
                STOSW
                LOOP    @@lp1

                POP     DS

        END;

      END
    ELSE
      BEGIN
        IF DMABufferEnd - WORD(mBuff) < Size THEN
          mBuff := DMABuffer;

        ASM
                PUSH    DS

                CLD
                LES     DI,[Buff]
                MOV     CX,[Size]
                LDS     SI,[mBuff]

        @@lp2:
                LODSB
                XOR     AL,$80
                XCHG    AL,AH
                XOR     AL,AL
                STOSW
                LOOP    @@lp2

                POP     DS

        END;

      END;

  END;




PROCEDURE PlayStart(VAR Song: TSong);
  VAR
    i, j : WORD;
  BEGIN

    ASM CLI END;

    PlayingSong := @Song;

    MyFirstPattern := FirstPattern;
    MyRepStart     := RepStart;
    MySongLen      := SongLen;

    IF MySongLen = 0 THEN MySongLen := Song.SequenceLength;

    IF MyFirstPattern = 0 THEN NextSeq := 1
                          ELSE NextSeq := MyFirstPattern;

    IF NextSeq > MySongLen THEN
      BEGIN
        ASM STI END;
        EXIT;
      END;

    IF (MyRepStart              =  0)         AND
       (Song.SequenceRepStart   <= MySongLen) AND
       (Song.SequenceRepStart   <> 0)         THEN
      MyRepStart    := Song.SequenceRepStart;

    MyLoopMod       := (TRUE{LoopMod} AND (MyRepStart <> 0)) OR ForceLoopMod;
    TempoCt         := 254;
    Tempo           := Song.InitialTempo;
    BPMIncrement    := Song.InitialBPM;
    TickCount       := 0;
    NextNote        := 1;
    DelaySamples    := FALSE;
    MuestrasPerTick := 1;
    MaxSplPerTick   := MaxOutputFreq DIV TicksPerSecond;

    IF MyRepStart < NextSeq THEN MyRepStart := NextSeq;

    WITH NoteBuff[0] DO BEGIN
      EoMod       := FALSE;
      Tempo       := 6;
      NotePlaying := 0;
      SeqPlaying  := 0;
      Volume      := UserVols;
      NMuestras   := 0;
    END;

    NoteHd        := 0;
    NoteTl        := 0;
    NoteSound     := @NoteBuff[0];
    NoteProcessed := @NoteBuff[0];

    FillChar(Canales, SIZEOF(Canales), 0);

    FOR i := 1 TO MaxChannels DO
      WITH Canales[i] DO BEGIN
        Note.Period     := 800;
        Note.Instrument := 1;
        Note.Command    := mcNone;
        Period          := 800;
      END;

    SizeOfABuffer := MaxSplPerTick*MaxChannels*2;
    FillChar(Buffers, SIZEOF(Buffers),  0);
    IF NOT UsingGUS THEN
      FOR i := 1 TO NumBuffers DO
        BEGIN
          FullHeap.HGetMem(POINTER(Buffers[i].IData), SizeOfABuffer);
          IF Buffers[i].IData = NIL THEN
            BEGIN
              Song.Status := msOutOfMemory;
              PlayStop;
              ASM STI END;
              EXIT;
            END;
          FillChar(Buffers[i].IData^, SizeOfABuffer,  $7F);
        END;
    BuffIdx  := 1;
    BuffGive := 1;

    FillChar(RawChannels, SIZEOF(RawChannels), 0);

    ChangeSamplingRate(DesiredHz);

    ASM STI END;

    SetBufferAsker(IdleGiver);

    IF UsingGUS THEN
      DontExecute := TRUE;

    MyCanFallBack  := FALSE;
    Playing        := TRUE;

    IF NOT UsingGUS THEN
      FOR i := 1 TO NumBuffers DO
        ProcessTickEntry;

    IF UsingGUS THEN
      SetGusChannels(Song.NumChannels);

    StartSampling;
    ChangeSamplingRate(DesiredHz);

    DontExecute := FALSE;

    SetBufferAsker(BufferGiver);
{
    WHILE DeviceIdling AND (NOT KbdKeyPressed) DO;
}
    PleaseFallBack := 0;
    MyCanFallBack  := CanFallBack;
  END;




PROCEDURE ChangeSamplingRate(Hz: WORD);
  VAR
    MyHz : WORD;
  LABEL
    Otra;
  BEGIN
Otra:
    DesiredHz := Hz;
    MyHz      := ActiveDevice^.GetRealFreqProc(Hz);

    IF MyHz >  MaxSplPerTick * TicksPerSecond THEN
      BEGIN
        DEC(Hz, 100);
        GOTO Otra;
      END;

    IF MyHz < 1000 THEN
      BEGIN
        INC(Hz, 100);
        GOTO Otra;
      END;

    IF MyHz <> ActualHz THEN
      BEGIN
        ActualHz := MyHz;
        SetPeriodicProc(ProcessTickEntry, TicksPerSecond * 3 DIV 2{8} {DIV 3});
      END;

  END;




PROCEDURE PlayStop;
  VAR
    i  : WORD;
    ug : BOOLEAN;
  BEGIN
    Playing := FALSE;

    SetBufferAsker(IdleGiver);

{
    WHILE (NOT DeviceIdling) AND (NOT KbdKeyPressed) DO;
}

    ug := UsingGUS;

    EndSampling;

    IF NOT ug THEN
      FOR i := 1 TO NumBuffers DO
        FullHeap.HFreeMem(POINTER(Buffers[i].IData), SizeOfABuffer);

  END;




BEGIN
  Playing        := FALSE;
  LoopMod        := FALSE;
  ActualHz       := 0;

  IF FilterIsOn THEN FilterVal := FilterOn
                ELSE FilterVal := FilterOff;

  FillChar(UserVols, SIZEOF(UserVols), 255);
  FillChar(Permisos, SIZEOF(Permisos), TRUE);
  FillChar(SplBuf,   SIZEOF(SplBuf),      0);
END.
