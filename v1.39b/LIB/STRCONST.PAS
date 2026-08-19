{****************************************************************************}
{                                                                            }
{ MODULE:         StrConst                                                   }
{                                                                            }
{ DESCRIPTION:    Module that provides the constants for the Strings in the  }
{                 VT library, and the routines that export the different     }
{                 strings for the different languages.                       }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        11-Nov-1992 Documentation                                  }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT StrConst;

INTERFACE

USES Dos, Objects;




CONST

{ General purpose messages. }

  StrInitializing           = $0000;

{ ModUnit error messages. }

  StrFileNotExist           = $0100;
  StrFileTooShort           = $0101;
  StrFileOpenError          = $0102;
  StrOutOfMemory            = $0103;
  StrFileDamaged            = $0104;
  StrFileFormatNotSupported = $0105;

  StrFileFormats            = $0150; { 10+ File formats }

{ Device descriptions. }

  StrDevSpkrName            = $0200;

  StrDevSBDacName           = $0210;
  StrDevMixSBDacName        = $0211;
  StrDevMix2SBDacName       = $0212;

  StrDevSBName              = $0220;
  StrDevDMASBName           = $0221;
  StrDevDMASBSterName       = $0222;
  StrDevDMASBMixName        = $0223;
  StrDevDMASBMix2Name       = $0224;
  StrDevDMAPASName          = $0225;

  StrDevDACName             = $0230;
  StrDevDAC2Name            = $0231;
  StrDevMixDAC2Name         = $0232;
  StrDevMix2DAC2Name        = $0233;

  StrDevAdLibName           = $0240;

  StrDevFileName            = $0250;

  StrDevGUSName             = $0260;

{ Device descriptions. }

  StrSwapNotInit            = $0300;


FUNCTION  InitStrings(f: PathStr) : BOOLEAN; { Initialize the strings file.    }
FUNCTION  GetString  (Key: WORD)  : STRING;  { Used to get the desired string. }

PROCEDURE LibAddSpanishMsg(VAR List: TStrListMaker); { Spanish strings. }
PROCEDURE LibAddEnglishMsg(VAR List: TStrListMaker); { English Strings. }




IMPLEMENTATION




VAR
  Strings: TStringList; { The Turbo Vision string list object.              }
  Stream : TBufStream;  { The file stream where the string list is located. }




{----------------------------------------------------------------------------}
{ User routines.                                                             }
{____________________________________________________________________________}

FUNCTION InitStrings(f: PathStr) : BOOLEAN;
  CONST
    Hdr : ARRAY[0..5] OF CHAR = ( 'V', 'T', ' ', 'L', 'N', 'G' );
  VAR
    s : ARRAY[0..255] OF CHAR;
    h : ARRAY[0..5] OF CHAR ABSOLUTE s;
    i : LONGINT;
  LABEL
    Ya;
  BEGIN

    Stream.Init(f, stOpenRead, 1024);

    i := Stream.GetSize;
    IF i > 256 THEN i := 256;
    Stream.Read(s, i);

    IF h <> Hdr THEN
      BEGIN
        InitStrings := FALSE;
        Stream.Done;
        EXIT;
      END;

    FOR i := 0 TO i-1 DO
      IF s[i] = #$1A THEN GOTO Ya;
Ya:
    Stream.Seek(i+1);
    Strings.Load(Stream);

    InitStrings := TRUE;
  END;


FUNCTION  GetString(Key: WORD) : STRING;
  BEGIN
    GetString := Strings.Get(Key);
  END;




{----------------------------------------------------------------------------}
{ Routines that write the different streams to the list.                     }
{____________________________________________________________________________}

PROCEDURE LibAddSpanishMsg(VAR List: TStrListMaker);
  BEGIN

    List.Put(StrInitializing           , 'Inicializando ');


    List.Put(StrFileNotExist           , 'No hubo ninguna canci¢n');
    List.Put(StrFileTooShort           , 'Fin de fichero antes de tiempo');
    List.Put(StrFileOpenError          , 'Error al abrir el fichero');
    List.Put(StrOutOfMemory            , 'No hay memoria');
    List.Put(StrFileDamaged            , 'El fichero no tiene canciones');
    List.Put(StrFileFormatNotSupported , 'Formato no soportado: ');

    List.Put(StrFileFormats+0          , 'formato desconocido');
    List.Put(StrFileFormats+1          , 'ProTracker "M.K."');
    List.Put(StrFileFormats+2          , 'ProTracker "FLT4"');
    List.Put(StrFileFormats+3          , 'SoundTracker');
    List.Put(StrFileFormats+4          , 'JMPlayer');
    List.Put(StrFileFormats+5          , 'Oktalizer');
    List.Put(StrFileFormats+6          , 'Composer 669');
    List.Put(StrFileFormats+7          , 'Grave');
    List.Put(StrFileFormats+8          , 'Triton FasTracker');
    List.Put(StrFileFormats+9          , 'Scream Tracker 3.0');
    List.Put(StrFileFormats+10         , 'Scream Tracker 3.0 beta');
    List.Put(StrFileFormats+11         , 'Scream Tracker 2.x');

    List.Put(StrDevSpkrName            , 'Altavoz interno del PC');

    List.Put(StrDevSbDACName           , 'DAC + SB est‚reo');
    List.Put(StrDevMixSbDACName        , 'DAC + SB est‚reo (mezcla suave)');
    List.Put(StrDevMix2SbDACName       , 'DAC + SB est‚reo (mezcla fuerte)');

    List.Put(StrDevSBName              , 'Sound Blaster mono sin DMA');
    List.Put(StrDevDMASBName           , 'Sound Blaster mono con DMA');
    List.Put(StrDevDMASBSterName       , 'SB-Pro est‚reo con DMA');
    List.Put(StrDevDMASBMixName        , 'SB-Pro est‚reo con DMA (mezcla suave)');
    List.Put(StrDevDMASBMix2Name       , 'SB-Pro est‚reo con DMA (mezcla fuerte)');
    List.Put(StrDevDMAPASName          , 'Emulaci¢n Sound Blaster DMA en la PAS');

    List.Put(StrDevDACName             , 'DAC mono en LPT1');
    List.Put(StrDevDAC2Name            , 'DAC est‚reo en LPT1 - LPT2');
    List.Put(StrDevMixDAC2Name         , 'DAC est‚reo en LPT1 - LPT2 (mezcla suave)');
    List.Put(StrDevMix2DAC2Name        , 'DAC est‚reo en LPT1 - LPT2 (mezcla fuerte)');

    List.Put(StrDevAdLibName           , 'Tarjeta de sonido AdLib o compatible');

    List.Put(StrDevFileName            , 'Fichero SBDSP$ (driver OS/2)');

    List.Put(StrDevGUSName             , 'Gravis Ultrasound');


    List.Put(StrSwapNotInit            , 'Error al inicializar el fichero de swap.');

  END;


PROCEDURE LibAddEnglishMsg(VAR List: TStrListMaker);
  BEGIN

    List.Put(StrInitializing           , 'Initializing ');


    List.Put(StrFileNotExist           , 'Didn''t find any songs');
    List.Put(StrFileTooShort           , 'Unexpected end of file');
    List.Put(StrFileOpenError          , 'File open error');
    List.Put(StrOutOfMemory            , 'Out of memory');
    List.Put(StrFileDamaged            , 'File had no songs');
    List.Put(StrFileFormatNotSupported , 'Unsupported file format: ');

    List.Put(StrFileFormats+0          , 'unknown format');
    List.Put(StrFileFormats+1          , 'ProTracker "M.K."');
    List.Put(StrFileFormats+2          , 'ProTracker "FLT4"');
    List.Put(StrFileFormats+3          , 'SoundTracker');
    List.Put(StrFileFormats+4          , 'JMPlayer');
    List.Put(StrFileFormats+5          , 'Oktalizer');
    List.Put(StrFileFormats+6          , 'Composer 669');
    List.Put(StrFileFormats+7          , 'Grave');
    List.Put(StrFileFormats+8          , 'Triton FasTracker');
    List.Put(StrFileFormats+9          , 'Scream Tracker 3.0');
    List.Put(StrFileFormats+10         , 'Scream Tracker 3.0 beta');
    List.Put(StrFileFormats+11         , 'Scream Tracker 2.x');


    List.Put(StrDevSpkrName            , 'PC Internal Speaker');

    List.Put(StrDevSbDACName           , 'DAC + SB stereo');
    List.Put(StrDevMixSbDACName        , 'DAC + SB stereo (mild mix)');
    List.Put(StrDevMix2SbDACName       , 'DAC + SB stereo (tough mix)');

    List.Put(StrDevSBName              , 'NON-DMA Sound Blaster');
    List.Put(StrDevDMASBName           , 'DMA Sound Blaster');
    List.Put(StrDevDMASBSterName       , 'DMA Stereo SB-Pro');
    List.Put(StrDevDMASBMixName        , 'DMA Stereo SB-Pro (mild mix)');
    List.Put(StrDevDMASBMix2Name       , 'DMA Stereo SB-Pro (tough mix)');
    List.Put(StrDevDMAPASName          , 'Sound Blaster DMA emulation on the PAS');

    List.Put(StrDevDACName             , 'mono DAC in LPT1');
    List.Put(StrDevDAC2Name            , 'stereo DAC in LPT1 - LPT2');
    List.Put(StrDevMixDAC2Name         , 'stereo DAC in LPT1 - LPT2 (mild mix)');
    List.Put(StrDevMix2DAC2Name        , 'stereo DAC in LPT1 - LPT2 (tough mix)');

    List.Put(StrDevAdLibName           , 'AdLib sound card or compatible');

    List.Put(StrDevFileName            , 'SBDSP$ file (OS/2 driver)');

    List.Put(StrDevGUSName             , 'Gravis Ultrasound');


    List.Put(StrSwapNotInit            , 'Error initializing the swap file.');

  END;




END.
