{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  THE PROGRAM ITSELF -- start here.

  WHAT DEMOVT DOES, END TO END. It reads the config file and the command line,
  finds a sound card and opens it, goes resident on INT 2Fh so a demo can find
  it, and then walks its playlist: load a module, play it, run whatever program
  the entry names, and move on. When the list is finished or a client sets the
  Abort flag, it unhooks everything and exits.

  ITS REAL JOB IS TO BE A BACKGROUND SERVICE. The player runs off the timer
  interrupt, so once a module is going this program has nothing to do -- and
  that is the point. It shells out to the demo, the demo draws, the music keeps
  playing underneath, and the two stay in step through the control block.

  THE INIT CHAIN IS THE OTHER HALF OF THE STORY. Turbo Pascal runs every unit's
  initialisation section before the body, in link order, and that is where the
  drivers register themselves and the resident handler is installed. By the
  time the first statement of the body runs, the program is already findable.

  NAMES ARE PROVISIONAL. The binary is Borland Pascal 6 with no debug
  information, so no unit or routine name survives. Everything here is named
  for what it does, and every name is followed by the address it was read
  from.

  DGROUP (segment 1caa)
    $0002  the poll re-entrancy guard     $0004  'DemoVT v1.31 (beta)'
    $009a  PlayModule, as a far pointer   $02d1  set when run as INCONEXI.EXE
    $09e8  "the banner has been shown"    $0b96  the sound driver object
    $0c6e  -> TimerChain                  $0c72  "say if no song was found"
    $22c6  THE CONTROL BLOCK              $23e7  CB+$121: the dispatcher
  =========================================================================== }

{ THE STACK IS 20,000 BYTES, NOT THE DEFAULT 16,384, AND THE EXE HEADER IS WHAT SAYS SO.
  The original's initial SP is $4E20 -- 20000 -- where a default build gives $4000, and its
  MINALLOC is 226 paragraphs larger than ours, which is 3,616 bytes, which is
  20000 - 16384 exactly. Two independent header fields agreeing on one number.

  HeapMin stays 0: if it differed, MINALLOC would be out by more than the stack delta and
  it is not. HeapMax is left at the default because the original's MAXALLOC is $FFFF, and
  that is almost certainly LZEXE's rather than TPC's -- the unpacker claims all available
  memory -- so it is a risk-3 question about the packer, not a compiler directive. }
{$M 20000,0,655360}

{$G+}   { PUSHA/POPA in the dispatcher and the timer handler }

program DemoVT;

{ EVERY `Unit_<seg>_<ofs>` PLACEHOLDER IS GONE. All twenty-six units this
  program reaches are transcribed and byte-exact, so the seventeen calls that
  were written as addresses are now written as names:

  so the clause below has to produce exactly that order. Units with no
  initialisation section never appear in the chain however they are listed.

  AND **DevSB REGISTERS BEFORE DevGus**, which decides the default device.
  DEVGUS.PAS records that InitDevice pushes onto the front of the list but
  selects only when nothing is selected yet, so the FIRST to register wins --
  and that note concluded "a machine with both ends up on the GUS" while
  comparing DevGus against VTSilenc alone. With 193a in the chain the SB
  registers first. Whether that changes the conclusion is not settled here;
  it is flagged because the note was written without this segment. }

uses
  Dos, VTResid, DevSB, VTGlobal, VTShell, Objects, Heaps, PlayMod, VTCfg,

  VTCmd, DevGus,

  SoundDevices, SongUnit, VTCtrl, CmdLine, VTNotes, Hardware, VTDosMem,
  ModCommands, VTSilenc;


const
  Guard     : Byte = 0;  { the poll re-entrancy guard }


  Fill0003  : Byte = 0;  { 1.31b's alignment pad, now explicit }

  SongOpen  : Boolean = False;  { a module is loaded and not yet freed        }


  PlayerStarted : Boolean = False;  { the mixer has been started              }


  Banner1 = '    ' + #218 + #196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196 + #191;

  Banner2 = '    ' + #179 + '  DemoVT.  VangeliSTracker''s version for demos, v1.51  ' + #179;
  Banner3 = '    ' + #179 + '                (C) 1992-94  VangeliSTeam              ' + #179;
  Banner4 = '    ' + #192 + #196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
             #196#196#196#196#196#196#196#196#196 + #217;

  { three String[44] on a stride of 45. }
  UsageTop = ' ' + #218 + #196#196#196#196#196#196#196#196#196#196#196#196#196 +
                   #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
                   #196#196#196#196#196#196#196#196#196#196#196#196#196 + #191;
  UsageMid = ' ' + #179 + ' USAGE:  DemoVT <file>[<.Ext>] [options] ' + #179;
  UsageBot = ' ' + #192 + #196#196#196#196#196#196#196#196#196#196#196#196#196 +
                   #196#196#196#196#196#196#196#196#196#196#196#196#196#196#196 +
                   #196#196#196#196#196#196#196#196#196#196#196#196#196 + #217;


  AltName  = 'inconexi';

  { **AND IT IS IN ENGLISH IN v1.51.** 1.31b carries the Spanish
    `No encuentro ninguna canci' + #162 + 'n.` -- twenty-nine characters and a CP437
    o-acute; the original's is `12 "Can't find a song."`, eighteen. The length byte is
    what identifies it: $1d against $12, and the text follows immediately.

    THE STRING GOT SHORTER, WHICH IS WHY IT WAS NOT FOUND EARLIER. Everything after it
    in the code segment moves ELEVEN BYTES down, and a routine-size check that is
    already reporting the segment short by more than that has nothing to catch it on.
    Only an aligned byte diff of the segment shows a literal changing. }
  NoSong   = 'Can''t find a song.';


  { **String[13] AND 'DemoVT v1.51'.** The declared width is measured, not chosen:
    the field runs from $0006 to $0013 because DEVGUS's block -- whose first typed
    constant is the driver record beginning `03 'GUS'` -- starts at $0014, and
    $0014 - $0006 - 1 is 13. The release dropped the `(beta)` and the string got
    shorter with it. }
  SelfName : String[13] = 'DemoVT v1.51';

var
  {    `AltMode` IS PLAYMOD'S, at $02d1, between `DontExecute` and `Playing` in its
    address-ordered const block -- the one insertion 1.31 makes in the release's
    sequence. This program SETS it (when the executable is called INCONEXI.EXE) and
    12ba is the only reader, which is why it was declared in both. }



  ChainPtr  : Pointer;   { -> TimerChain }
  Complain  : Boolean;   { and a pad at $0c73 }
  Song      : TSong;     { the module currently loaded, if any             }

{ --------------------------------------------------------------------------
  EIGHT NAMES RESOLVED TO THE UNITS THAT OWN THEM, now that all of them are
  transcribed. These used to be `Var<addr>` placeholders here:

    $02c8 LoopMod        PlayMod        $02c9 ForceLoopMod   PlayMod
    $0bae DesiredHz      SoundDevices   $3ade ProgName       VTShell
    $08c8 ShellParam     VTGlobal       $397e Heap           Heaps
    $0bc8 Ticks          VTSilenc       $4306 DMABufferPtr   SoundDevices

  Each was already declared at that address by its owner, independently, so
  eight addresses agreeing is a cross-check rather than an assumption.

  THE REST ARE STILL DECLARED HERE AND STILL WRONG TO BE. Every one below is a
  DGROUP address this segment reads or writes whose OWNER has not been
  established -- some almost certainly belong to VTCmd or VTCfg. A DGROUP
  reference is a linker fixup, so the byte comparison cannot tell a right home
  from a wrong one; that is risk 1, and declaring them here is that risk taken
  deliberately rather than by accident. Compare DEVGUS, where three globals sat
  in the wrong unit and nothing could see it.
  -------------------------------------------------------------------------- }



  SavedCD   : LongInt;


  Str1208   : String;

  { FOUR BYTES THIS TRANSCRIPTION CANNOT NAME, between the string above and
    `Dir` at $0dda. Nothing references them. Filler, so the SIZE is right and the
    missing name is stated rather than invented. }
  { **FOUR BYTES, AND 1.31b HAS THE SAME FOUR.** There they are `Fill0DD6`, with
    a note that reads almost word for word like this one -- four bytes this
    transcription cannot name, between the string above and what follows. Two
    versions, two independent readings, the same silence.

    THAT IS THE END OF WHAT EVIDENCE CAN DO HERE. This build is byte-identical and
    its source names these bytes nowhere, so no instruction in the original names
    them either; the v1.39b release has no counterpart for this unit at all, since
    its main program is a tracker rather than a player. They are not a defect and
    not a gap in the transcription -- they are four bytes the program reserves and
    never uses. }
  Fill0E9E  : LongInt;



{ THE CONTROL BLOCK, is NOT declared here. It lives in VTCtrl,
  the unit for segment 14b7, which is the code that clears it. There must be
  exactly one of it: INT 2Fh publishes its address to every client, so a
  second copy would mean the demo talked to a block nothing was updating.
  See docs/06-transcription.md, "one DGROUP, many units". }

{ --------------------------------------------------------------------------
  Print the four-line startup banner -- ONCE. The flag that suppresses it is
  also SET here, so the second caller prints nothing.}
procedure ShowBanner;
begin
  if not NoBanner then
  begin
    WriteLn;
    WriteLn(Banner1);
    WriteLn(Banner2);
    WriteLn(Banner3);
    WriteLn(Banner4);
    NoBanner := True;
  end;
end;

{ --------------------------------------------------------------------------
the chain to whatever held INT 1Ch before us.

  HAND ASSEMBLER, and it has to be: this is not a routine that is called, it
  is a five-byte JMP FAR whose OPERAND is patched. HookTimer writes the old
  vector into the two words at +1 and +3, and UnhookTimer reads them back out.

  It is assembled pointing at itself so that a stray call before the patch
  spins rather than jumping into nothing; the body then zeroes both words.
  -------------------------------------------------------------------------- }

procedure TimerChain; far; assembler;
asm
  DB   0EAh              { JMP FAR seg:ofs -- the operand is data }
  DW   OFFSET TimerChain { patched with the old INT 1Ch offset    }
  DW   SEG TimerChain    { patched with the old INT 1Ch segment   }
                         { the epilogue's RETF, never reached     }
end;

{ --------------------------------------------------------------------------
poll the sound driver four times, non-reentrant.}
procedure PollDriver;
type
  TPoll = procedure;
begin
  if Guard = 0 then
  begin
    Inc(Guard);
    { LES DI,[0b96]; CALL DWORD PTR ES:[DI+$2a] }
    asm
      LES  DI, ActiveDevice
      CALL DWORD PTR ES:[DI+2Ah]         { the driver's poll method          }
      LES  DI, ActiveDevice
      CALL DWORD PTR ES:[DI+2Ah]
      LES  DI, ActiveDevice
      CALL DWORD PTR ES:[DI+2Ah]
      LES  DI, ActiveDevice
      CALL DWORD PTR ES:[DI+2Ah]
    end;
    Dec(Guard);
  end;
end;

{ --------------------------------------------------------------------------
the INT 1Ch handler. THIS is what drives the music.

  HAND ASSEMBLER, verbatim. It cannot be a Pascal `interrupt` procedure: it
  ends in a JMP FAR to the chain stub rather than an IRET, so the previous
  handler still runs and the BIOS tick is not swallowed.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      PollDriver;   -- then jump to the old handler

  -------------------------------------------------------------------------- }
procedure TimerHandler; assembler;
asm
  PUSHF                  { the chain expects the flags on top     }
  PUSHA
  PUSH DS
  PUSH ES
  MOV  AX, SEG @DATA     { the binary has MOV AX,1CAAh -- an
                                      absolute segment, and copying it would
                                      point us at somebody else's data       }
  MOV  DS, AX
  CLD
  STI                    { a poll is long; let the machine breathe}
  CALL PollDriver
  POP  ES
  POP  DS
  POPA
  POPF
  JMP  FAR PTR TimerChain{ and on to whoever had INT 1Ch          }
end;

{ --------------------------------------------------------------------------
FUNCTION 0, the one every Psycho Neurosis part calls
  "MusicStart".

  What it actually does is hook INT 1Ch. The music starts because the timer
  starts feeding the driver, not because anything is told to play.

  It does nothing if the stub already holds a vector, so calling it twice is
  harmless -- which is why parts can call MusicStart without checking.
  -------------------------------------------------------------------------- }
procedure HookTimer;
begin
  { the stub's operand is the "are we hooked" flag. }
  asm
    LES  DI, ChainPtr
    MOV  AX, ES:[DI+1]
    OR   AX, ES:[DI+3]
    JZ   @@NotHooked
    JMP  @@Done            { already hooked -- leave it alone     }
  @@NotHooked:
    { **`MOV SI,0000` AND NOT `XOR SI,SI`**, six times over in this file. Same value,
      three bytes against two, and the original has the long form -- `be 00 00`, not
      `31 f6`. It is the segment of the interrupt vector table being formed, and a
      1993 hand-assembler writes it out. This file already records the identical fix in
      VTRESID, where four of them cost four bytes; here it cost six. **The verbatim rule
      exists for exactly this.** }
    MOV  SI, 0000h
    MOV  ES, SI            { ES := 0000, the vector table         }
    MOV  AX, ES:[70h]      { INT 1Ch offset                       }
    MOV  SI, 0000h
    MOV  ES, SI
    MOV  DX, ES:[72h]      { INT 1Ch segment                      }
    LES  DI, ChainPtr
    MOV  ES:[DI+1], AX     { patch the chain stub                 }
    MOV  ES:[DI+3], DX
    MOV  AX, OFFSET TimerHandler   { the binary has 01A5h         }
    MOV  DX, SEG TimerHandler      { and 1000h                    }
    MOV  SI, 0000h
    MOV  ES, SI
    MOV  ES:[70h], AX
    MOV  SI, 0000h
    MOV  ES, SI
    MOV  ES:[72h], DX
  @@Done:
  end;
end;

{ --------------------------------------------------------------------------
FUNCTION 1, "MusicStop": put INT 1Ch back and clear the stub.

  Note that neither this nor HookTimer touches the sound hardware. Silence is
  a consequence of the driver no longer being polled.
  -------------------------------------------------------------------------- }
procedure UnhookTimer;
begin
  asm
    LES  DI, ChainPtr
    MOV  AX, ES:[DI+1]
    OR   AX, ES:[DI+3]
    JNZ  @@Hooked
    JMP  @@Done            { never hooked -- nothing to undo      }
  @@Hooked:
    LES  DI, ChainPtr
    MOV  AX, ES:[DI+1]
    MOV  DX, ES:[DI+3]
    MOV  SI, 0000h
    MOV  ES, SI
    MOV  ES:[70h], AX
    MOV  SI, 0000h
    MOV  ES, SI
    MOV  ES:[72h], DX
    LES  DI, ChainPtr
    XOR  AX, AX
    MOV  ES:[DI+1], AX     { and mark it unhooked                 }
    MOV  ES:[DI+3], AX
  @@Done:
  end;
end;

{ ==========================================================================
THE DISPATCHER.

  The PUSHA / PUSH DS / MOV DS pair is not decoration: the caller is a
  different program with a different data segment, so nothing may be assumed
  about any register on entry.

  The result is set to zero and never changed, so the demo is right to ignore
  it.
  -------------------------------------------------------------------------- }
function Dispatch(Func : Word) : Word; far;
begin
  asm
    PUSHA
    PUSH ES
    PUSH DS
    MOV  AX, SEG @DATA     { the binary has MOV AX,1CAAh          }
    MOV  DS, AX
  end;

  Dispatch := 0;

  case Func of
    0 : HookTimer;
    1 : UnhookTimer;
    2 : asm
          LES  DI, ActiveDevice    { one poll, where the timer does four}
          CALL DWORD PTR ES:[DI+2Ah]
        end;
    3 : begin
          { part 001 is the only caller. It marks where the
            player has got to in its output buffer and resets the counters;
            it does not stop anything. GetPlayPos returns a far pointer into
            that buffer. }
          { ONE STATEMENT, AND A 32-BIT `and` IS WHAT SAYS SO. This was written as two
            -- assign, then rebuild the pointer with `Ptr(Seg(..), Ofs(..) and $FFFC)`
            -- which round-trips through the variable and costs eighteen bytes the
            original has not got. The original masks in the REGISTERS the function
            returned in: `25 fc ff` is `AND AX,0FFFCh` and `81 e2 ff ff` is
            `AND DX,0FFFFh`.

            **THE REDUNDANT `AND DX,0FFFFh` IS THE TELL.** Masking a high word with
            all-ones does nothing, and no programmer writes it; a 32-bit `and` against
            $FFFFFFFC does, because Turbo Pascal splits the constant into two 16-bit
            ANDs and emits both halves whatever they hold. So the source is a LongInt
            AND over the whole pointer, aligning it down to a multiple of four. }
          LongInt(DMABufferPtr) := LongInt(GetPlayPos) and $FFFFFFFC;
                                                       { -> $4306 }
          TickSnapshot := Ticks;                    { $0bca := $0bc8 }
          LastTick := 0;                          { $0058 := 0     }
          DriverTicks := 0;                         { $0c78 := 0     }


          RingSlot  := 0;
          FlushSlot := 1;
        end;
  end;

  asm
    POP  DS
    POP  ES
    POPA
  end;
end;

{ --------------------------------------------------------------------------
  LOAD AND PLAY ONE MODULE, and then run whatever program the playlist entry
  named. This is the body of the playlist loop and the closest thing the
  program has to a main routine.

  RETF 8: two String parameters, both copied into String[79] locals.
  -------------------------------------------------------------------------- }
{ THE PARAMETERS ARE `PathStr`, AND THE TWO 80-BYTE SLOTS ARE THE COMPILER'S OWN
  COPIES OF THEM -- not locals, and not statements. `ENTER 00a2,0` is 162 bytes, which
  is 80 + 80 + `Ok` + one pad and nothing else; declared `String` the two value
  parameters get 256-byte copies each and the frame is 676. And `PathStr` is
  `String[79]`, so the `PUSH 4Fh` in each copy is `SizeOf - 1` exactly.}
{ --------------------------------------------------------------------------
  THE REGISTER-CONVENTION ENTRY POINT: take the command in AX rather than on
  the stack, and hand it to Dispatch.

  IT EXISTS TO MOVE THE FUNCTION NUMBER FROM A REGISTER TO THE STACK, which is
  what lets a client written in assembler and one written in Pascal both call
  this program without either having to know the other's convention.}
procedure DispatchEntry; far; assembler;
asm
  PUSH    AX
  CALL    FAR PTR Dispatch
end;


{ --------------------------------------------------------------------------
  STOP EVERYTHING: unhook the timer, silence the device, free the module.

  Called between playlist entries and again on the way out, so it has to be
  safe to call when nothing is playing -- which is what the SongOpen guard is
  for.}
procedure StopModule;
begin
  if PlayerStarted then
  begin
    UnhookTimer;
    FillChar(DMABuffer^, DMABufferSize, $80);

    { The range a caller ASKED for is put back, so the next module starts from the
      command line's own numbers rather than from whatever the last one left. }
    ReqStart := VT1stPattern;
    ReqEnd   := VTRepStart;
    ReqLen   := VTSongLen
  end;

  if SongOpen then
    Song.Done
end;


function PlayModule(Name, Params : PathStr) : Boolean; far;

begin

  StopModule;

  Complain := False;
  PlayModule := True;
  ShowBanner;

  if ShellLoopMod then
  begin
    LoopMod := True;
    ForceLoopMod := True;
  end;

  SetVTDevice;
  asm
    LES  DI, ActiveDevice
    CALL DWORD PTR ES:[DI+1Ah]         { a second driver method               }
  end;
  SetVTFreq;
  MaxOutputFreq := DesiredHz;                      { $02ce := $0bae }


  FillChar(UserVols, SizeOf(UserVols), VtVolume);
  Song.Init;
  Song.SetInsidePath(Params);

  if VT1stPattern <> 0 then Song.SongStart := VT1stPattern;
  if VTSongLen <> 0 then Song.SongLen := VTSongLen;
  StartSampling;
  Song.LoadFName(Name);

  SongOpen := True;

  PlayModule := False;
  if Song.Status <= 2 then
  begin
    PlayModule := True;

    { **NEW IN v1.51 -- THE CONTROL BLOCK IS RESET FOR THE NEW MODULE, and every
      address in the block confirms TCtrlBlock's layout from the outside.** $461a is
      CtrlBlock itself; $471a is CB+$100, the thirty-two `ChansTrig` flags; $4747 is
      CB+$12D, the 128-byte `ChansData` row; $473f is CB+$125, `TickCounter`; $47c7
      and $47c8 are CB+$1AD and CB+$1AE; $481d is CB+$203, `JumpNewPos`. Six fields
      measured one at a time in PlayMod and VTCtrl, all landing where this routine
      puts them -- and all six now confirmed by the client bindings the v1.5
      distribution ships.

      THE TWO INDICES START AT ONE, NOT ZERO, which is the same convention
      NotePlaying and SeqPlaying carry inside TPlayingNote -- row 1 of order position
      1, not a zero that would read as "before the start".

      THE 256 BYTES ARE THE SEMAPHORE ARRAY, and DEMOVT.DOC names this very
      instruction: "When DemoVT is started, all semaphores are set to zero." A
      client that polls a semaphore must not see the previous module's count.

      This paragraph called them "the 1.31b-era per-channel tally" and cleared
      them under the name `Filler1`, which is what a correct transcription of an
      un-understood field looks like: the byte count right, the site right, the
      meaning absent. Cleared BY NAME regardless, because `FillChar(CtrlBlock, ...)`
      with a length of $100 says the same thing to the compiler and something false
      to a reader -- and that much was right both before and after. }
    PlayerStarted := True;

    FillChar(CtrlBlock.Semaphores,
             SizeOf(CtrlBlock.Semaphores), 0);
    FillChar(CtrlBlock.ChansTrig,
             SizeOf(CtrlBlock.ChansTrig), 0);
    FillChar(CtrlBlock.ChansData,
             SizeOf(CtrlBlock.ChansData), 0);

    CtrlBlock.TickCounter     := 0;
    CtrlBlock.Pos := 1;
    CtrlBlock.Seq  := 1;
    CtrlBlock.JumpNewPos    := 0;
    PlayStart(Song);
    asm
      MOV  DI, OFFSET Heap
      PUSH DS
      PUSH DI
      MOV  DI, [DI]             { its VMT                         }
      { NO `ES:` HERE, AND THE DIFFERENCE IS WHICH REGISTER HOLDS THE OBJECT.
        `MOV DI, OFFSET Heap` puts a DGROUP offset in DI, so the VMT fetch and the
        call through it are both DS-relative and the original emits no prefix --
        `ff 5d 18`. The four calls in PollDriver and the one at 0302 DO carry `26`,
        because those reach the driver through `LES DI, ActiveDevice` and are
        ES-relative. Same instruction, two addressing bases, one byte apart. }
      CALL DWORD PTR [DI+18h]
      MOV  WORD PTR [OFFSET SavedCD], AX
      MOV  WORD PTR [OFFSET SavedCD+2], DX
    end;
    ShrinkSystemHeap(0);
    SwapVectors;
    Exec(ProgName, ShellParam);

    SwapVectors;
    ShrinkSystemHeap(SavedCD);
  end;


end;

{ ==========================================================================
  THE BODY: read the settings, open a device, go resident, walk the playlist.

  Everything the units set up for themselves has already happened by the time
  the first statement here runs -- the drivers are registered and the resident
  handler is installed by their initialisation sections, in link order.}

var

  Dir  : DirStr;
  Name : NameStr;
  Ext  : ExtStr;

begin
  if ParamCount = 0 then
  begin
    ShowBanner;
    { THREE `WriteLn`s, NOT SIX. Each bare `WriteLn` costs ten bytes -- five to push
      `Output` again and five for the call -- and the original has none of them: the
      three groups from 04fc to 0534 are each `[PUSH Output][PUSH CS:literal][PUSH 0]
      [CALL Write][CALL WriteLn]` and nothing between. `WriteLn(X)` already ends the
      line; the extra ones would print three blank ones. }
    WriteLn(UsageTop);
    WriteLn(UsageMid);
    WriteLn(UsageBot);
    Halt(1);
  end;

  FSplit(ParamStr(0), Dir, Name, Ext);


  if Name = AltName then AltMode := True;

  ChainPtr := @TimerChain;
  asm
    LES  DI, ChainPtr
    XOR  AX, AX
    MOV  ES:[DI+1], AX     { start out plainly unhooked           }
    MOV  ES:[DI+3], AX
  end;


  CtrlBlock.CtrlEntryPoint := @Dispatch;              { -> CB+$121   }
  CtrlBlock.RegEntryPoint := @DispatchEntry;         { -> CB+$129   }

  Install(SelfName, @CtrlBlock);

  InitHeapVariables;
  InitUmbHeap;

  Cmd.Init;
  SongColl.Init(1, 1);
  InitSoundDevices;
  BuildNoteTable;
  DesiredHz := ShellHz;
  OneModPtr := @PlayModule;                       { the playlist calls through here }
  Complain := True;

  Cmd.ParseLine(GetDOSCmdLine);

  {    THIS PARAGRAPH SAID TWICE THAT NOTHING WRITES $4821. It is CB+$207, a published
    control-block field, and the writers are outside this image: the whole point of
    the block is that another program reaches into it. Three reads and no writes is
    not an unfinished switch -- it is exactly what an INPUT looks like, and the shape
    that should have named it. See VTCtrl's declaration. }
  if (SongColl.Count <> 0) and DoSongColl(Cmd.FileDir) and Complain
     and not CtrlBlock.Abort then
    WriteLn(NoSong);

  StopModule;
  EndSampling;

  { **AND THE CLOSING BANNER IS SUPPRESSED WHEN THE PROGRAM HAS JUST COMPLAINED.**
 tests the same `Complain` byte the WriteLn above tests, with the sense
    reversed -- `JZ` there, `JNZ` here. One variable read twice in ten instructions
    to opposite ends, which is why the address had to be checked rather than the
    second test assumed to be a different flag. }
  if not Complain then
    ShowBanner;


end.
