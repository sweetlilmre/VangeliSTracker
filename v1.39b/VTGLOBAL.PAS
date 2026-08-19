{****************************************************************************}
{                                                                            }
{ MODULE:         VTGlobal                                                   }
{                                                                            }
{ DESCRIPTION:    Provides definitions of constants and global variables     }
{                 of the VangeliSTracker. To be used by all of the VT units. }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        17-Oct-1992 Documentation.                                 }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT VTGlobal;

INTERFACE

USES Dos,
     SoundDevices, DevGUS;

CONST
  NombreApp = 'VangeliSTracker';              { El nombre de la aplicaci¢n (para            }
                                              { usarlo en unos cuantos sitios).             }
  Version       = '1.39';                     { N£mero de versi¢n, en formato X.Yz          }
  NoBetaPadding ={'    v'}'v'             ;
  BetaStr       ={''     }' (á 18)'       ;
  BetaPadStr    ={'    ' }'  ('#127' 18)' ;
  Beta          ={FALSE  }TRUE            ;   { TRUE si es una versi¢n beta.                }

  VTDir        : DirStr       = '';           { Directorio donde se encontraba el VT.EXE    }



  DevPtr       : PSoundDevice = NIL;          { Puntero al device que se usa.               }
  DevID        : TDevID       = GUSDevID;     { Identificador del device que se usa.        }

  StartupScr   : STRING[32]   = '';           { Pantalla con la que comienza VT.            }

  PermitFade   : BOOLEAN      = TRUE;         { TRUE si se permite el fade-out.             }
  VTVolume     : BYTE         = 127;          { Volumen general del programa.               }

  ShellLoopMod : BOOLEAN      = TRUE;         { TRUE si se quere que el m¢dulo haga loops   }
                                              { cuando est s en el shell, en vez de pararse.}

  DefShellHz = DefaultHz * 3 DIV 4;
  ShellHz      : WORD         = DefShellHz;   { Sample freq when exiting to DOS shell.      }

  FadeIncr     : WORD         = 256;          { Velocidad del fade-out.                     }
  VTLoopMod    : BOOLEAN      = FALSE;

  VT1stPattern : WORD = 0;
  VTRepStart   : WORD = 0;
  VTSongLen    : WORD = 0;


VAR
  StdErr       : TEXT;                        { Standard error. Salida no redireccionable.  }

  ShellPath    : PathStr;                     { Shell executable.                           }
CONST
  ShellParam   : STRING[127]  = '';           { Shell parameters.                           }
  StringsFName : PathStr      = 'VT_Esp.Lng'; { Fichero de lenguaje.                        }
  ModPath      : PathStr      = '';
  FirstSong    : STRING[20]   = '';     { First song to be loaded }




IMPLEMENTATION




{----------------------------------------------------------------------------}
{ Module initialization and exit.                                            }
{____________________________________________________________________________}

VAR
  OldExitProc : POINTER;

PROCEDURE MyExitProc; FAR;
  BEGIN
    ExitProc := OldExitProc;

    Close(StdErr);            { Close the standard error. Not necesarily needed, but }
                              { included for cleanliness.                            }
  END;

BEGIN

  Assign(StdErr, 'CON');      { The standard error will always be the console. }
  Rewrite(StdErr);            { Opened for writing. }

  OldExitProc := ExitProc;
  ExitProc    := @MyExitProc; { Set the exit procedure. }

  ShellPath := FExpand(GetEnv('COMSPEC'));

END.
