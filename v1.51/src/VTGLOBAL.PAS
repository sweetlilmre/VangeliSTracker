{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  NO SEGMENT OF ITS OWN. Declarations only, like `SONGUNIT.PAS` and `VTDRIVER.PAS`:
  nothing here compiles to an instruction, so this unit's `.TPU` has no code and
  `verify.py` has nothing to compare.

  THE RELEASE HAS A REAL `VTGLOBAL.PAS` and this is the same idea -- the settings every
  other unit reads and the configurator writes. It exists because **two transcribed units
  now need the same globals**: `11bb` (VTCfg) writes them from the config file and `109c`
  (VTCmd) writes them from the command line. They were declared privately inside
  `VTCFG.PAS` until `109c` landed, which is exactly the kind of thing a second caller
  exposes.

  **NO ADDRESS HERE IS LOAD-BEARING.** Every reference to a DGROUP variable is a linker
  fixup, so Turbo Pascal emits a zero and `verify.py` excuses it; moving a declaration
  between units cannot change a byte of either one's code. That is also what makes it
  dangerous -- the byte comparison cannot tell a right home from a wrong one -- so the
  addresses are quoted from the disassembly and each one says how well it is known.
  `VTCFG.PAS` proved this holds: it still verifies identical after losing all of these.
  =========================================================================== }
unit VTGlobal;

interface

uses
  Dos, VTDriver, SoundDevices;

{ EVERY ONE OF THESE IS A TYPED CONSTANT, AND THE LINKED IMAGE IS WHAT SAYS SO.
  They were plain `var`s, and that put 359 bytes of this unit's data nowhere: a plain
  `var` is reserved space the linker never writes, where a TYPED constant is
  initialised data stored in the EXE. `demovt/dgroup.py` reads the original's
  initialised DGROUP straight out of the image, and this block is simply THERE --
  `DMA-SB-Mono` at $0882 and `VT_Esp.Lng` at $0948, with real values in between.
  The release agrees: its own `VTGLOBAL.PAS` declares almost the whole unit in `CONST`
  sections, which is how 1993 Pascal gives a global a default.

  **THE ORDER AND THE WIDTHS ARE MEASURED, NOT COPIED.** DGROUP is laid out in link
  order and this unit's block sits between VTShell's and DevSB's, so every address
  below is fixed by its neighbours, and the release's declaration order lands on them
  exactly. Two independent arithmetic checks fell out of it:

    * `TDevID` is `String[20]`, so DevID runs $0882..$0896, and `StartupScr` is at
      $0898 rather than $0897 -- **TP WORD-ALIGNS EACH TYPED CONSTANT.** The same rule
      explains three more paddings in the image: $0897 here, $08c1 before VT1stPattern,
      and $0003 before VTMAIN's SelfName. Four cases, one rule.
    * `ShellParam` at $08c8 + 128 = $0948 = StringsFName, and $0948 + 80 = $0998 =
      ModPath, and $0998 + 80 = $09e8 = NoBanner. Three consecutive widths closing on
      three independently known addresses.

  **THE VALUES COME FROM THE IMAGE, NEVER FROM THE RELEASE** -- the standing rule, and
  it matters here because one of them differs. 1.39b has `DevID = GUSDevID`; 1.31 has
  `DMA-SB-Mono`, the Sound Blaster's. That is consistent with the other thing this
  tree found about the two drivers: DevSB registers BEFORE DevGus in the init chain,
  so the SB is 1.31's default, and the default device ID agrees.

  `VTDir` HAS AN ADDRESS AGAIN. This document withdrew one -- VTCFG.PAS had it at
  DS:$09e8, which turned out to be NoBanner, and the note was changed to "no measured
  address". Working back from DevPtr at $087e it is $083a, and it is a `DirStr` rather
  than the `PathStr` it was: 68 bytes is what closes the gap, where 80 would overrun
  into data that is not zero. }
const
  VTDir             : DirStr        = '';            { DS:$083a  68 bytes      }
  DevPtr            : PSoundDevice  = nil;           { DS:$087e                }
  DevID             : TDevID        = 'DMA-SB-Mono'; { DS:$0882  MEASURED      }
  StartupScr        : String[32]    = '';            { DS:$0898  after a pad   }

  PermitFade        : Boolean       = True;          { DS:$08b9  01            }
  VtVolume          : Byte          = 127;           { DS:$08ba  7f            }
  ShellLoopMod      : Boolean       = True;          { DS:$08bb  01            }

  { DS:$08bc -- `e0 2e`, 12000. The release computes its default as
    `DefaultHz * 3 DIV 4`, so 1.31's DefaultHz is 16000. Read, not derived. }
  ShellHz           : Word          = 12000;

  FadeIncr          : Word          = 256;           { DS:$08be  00 01         }
  VTLoopMod         : Boolean       = False;         { DS:$08c0                }

  { $08c2..$08c7, after the pad at $08c1. All three are zero in the image, so the
    ORDER here is the release's rather than measured -- flagged for that reason. }
  VT1stPattern      : Word          = 0;             { DS:$08c2                }
  VTRepStart        : Word          = 0;             { DS:$08c4                }
  VTSongLen         : Word          = 0;             { DS:$08c6                }

  { DS:$08c8 -- A `String[127]`, AND THE WIDTH IS MEASURED TWICE OVER. `11bb:0d5c`
    pushes `6A 7F`, an immediate 127, as `SizeOf(ShellParam) - 1`; a full `String`
    would push 255 and take a byte more to do it. And $08c8 + 128 lands exactly on
    StringsFName. }
  ShellParam        : String[127]   = '';

  StringsFName      : PathStr       = 'VT_Esp.Lng';  { DS:$0948  MEASURED      }
  ModPath           : PathStr       = '';            { DS:$0998                }

  { 109c:05b2 SETS THIS AND `1000` READS IT, which is how the switch got its name.
    `1000:00fb` is `CMP byte [09e8],0 / JNZ +$67`, and the 103 bytes it skips are four
    WriteLns of four 62-byte string constants at `1000:0000`, `003e`, `007c` and
    `00ba` -- a four-line banner. `1000:0164` then sets the same flag itself, so the
    banner prints once however many times that path is taken. **`nb` is "no banner".**
    A typed constant like everything else here, and $0998 + 80 is what puts it at
    $09e8: the last byte of this unit's block, with DevSB's first device record
    eleven bytes further on. }
  NoBanner          : Boolean       = False;         { DS:$09e8  MEASURED      }

{ ~~A NEW BOOLEAN AT DS:$4821 WHOSE OWNER IS NOT YET PROVEN~~ -- **IT IS
  `VTCtrl.CtrlBlock.StopWant`, AND THE ARITHMETIC IS ONE SUBTRACTION.** $4821 minus
  CtrlBlock's $461a is $207, inside the published control block, one byte after
  MasterVol and four after SeekWant.

  THE NOTE THAT STOOD HERE HAD THE EVIDENCE RIGHT AND THE CONCLUSION BACKWARDS. It
  said "read in three places and written NOWHERE ... a switch wired up and never
  given a way to be turned on". Both facts hold. What does not follow is that nothing
  can set it: a field in a block this program PUBLISHES for other programs to write
  is supposed to have no writer here. **No writer inside the image is what an INPUT
  looks like.**

  Declaring it here also cost two bytes of DGROUP in the wrong place -- it landed
  between VTShell's variables and SoundDevices', putting 53 operands in one unit and
  13 in another two bytes high. }


{ ~~TWO `var`s USED TO SIT HERE~~ AND BOTH HAVE GONE TO THE UNIT THAT OWNS THEM,
  each because its ADDRESS is inside another unit's DGROUP block:

    ModOffset  DS:$03c0  is four bytes below SongUnit's `SongLoaders` at $03c4, so it
               is SONGUNIT's, and 14b9:0242 -- which pushes it into `St.Seek` -- is
               that unit's own `LoadFName`. Now a typed constant there.
    Rut_0bc6   DS:$0bc6  is between SoundDevices' `DMAChannel` at $0bc4 and its
               `IsDmaDevice` at $0bc7, so it is SOUNDDEVICES'. 109c sets it from the
               `nx` switch and nothing anywhere reads it, which is why it still has
               no name.

  So this unit is now entirely typed constants, with no variables at all -- which is
  what the release's `VTGLOBAL.PAS` is too, apart from a `StdErr` text file and a
  `ShellPath` that 1.31 keeps in VTShell. }

implementation

end.
