{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Every setting the player shares: what device to use, how loud, which module,
  which directory, whether to print the banner.

  WHY THEY ARE IN A UNIT OF THEIR OWN. Two places write these and everything
  else reads them -- the config-file reader and the command-line parser -- so
  neither can own them. That is the only reason this unit exists; it holds no
  code at all, and a reader looking for behaviour should look at its writers.

  THEY ARE TYPED CONSTANTS, WHICH IS HOW 1993 PASCAL GAVE A GLOBAL A DEFAULT.
  Each declaration below carries the value the program starts with, so the list
  doubles as the settings' documentation: DevID starts as the Sound Blaster,
  the volume starts at 127 of 255, fading is permitted, the banner prints. }
unit VTGlobal;

interface

uses
  Dos, VTDriver, SoundDevices;

const
  VTDir             : DirStr        = '';
  DevPtr            : PSoundDevice  = nil;
  DevID             : TDevID        = 'DMA-SB-Mono';
  StartupScr        : String[32]    = '';

  PermitFade        : Boolean       = True;
  VtVolume          : Byte          = 127;
  ShellLoopMod      : Boolean       = True;

  { The rate used when a shelled-out program plays, three quarters of the
    player's own 16000. Lower because the shell is not the thing being
    listened to. }
  ShellHz           : Word          = 12000;

  FadeIncr          : Word          = 256;
  VTLoopMod         : Boolean       = False;

  { Where in the module to start, where to loop back to, and how much of the
    sequence to play. All three default to zero, meaning "the whole thing from
    the beginning". }
  VT1stPattern      : Word          = 0;
  VTRepStart        : Word          = 0;
  VTSongLen         : Word          = 0;

  { The command line handed to the shelled-out program. 127 characters, which
    is DOS's own limit for a command tail. }
  ShellParam        : String[127]   = '';

  StringsFName      : PathStr       = 'VT_Esp.Lng';
  ModPath           : PathStr       = '';

  { Suppress the four-line startup banner. Set by the `nb` switch, and the
    player also sets it itself after printing once, so the banner appears at
    most once however many times that path is taken. }
  NoBanner          : Boolean       = False;




implementation

end.
