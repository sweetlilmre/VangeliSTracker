{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).

  Segment 1931 -- startup housekeeping. 159 bytes, five routines, three of
  which do nothing.

  Three things happen here, and they are only in the same segment because
  they all happen once at startup:

    * the console is opened AS A FILE, under the name 'CON'
    * COMSPEC is looked up and expanded, giving the fallback program to run
    * an exit handler is chained on, to close the console again

  OPENING 'CON' EXPLICITLY is the interesting one. Writing through a Text
  variable assigned to 'CON' reaches the console even when the program's
  standard output has been redirected -- `DEMOVT @NEUROSIS.CFG > LOG` still
  puts the banner on screen. DemoVT is run from a batch file by every part of
  the demo, so that matters.

  DS:$3ade IS THE PROGRAM PSYCHO NEUROSIS ACTUALLY RUNS. 109c overwrites it
  per playlist entry and 1000:03af hands it to Dos.Exec; what this unit does
  is give it a default, so an entry that names no program of its own falls
  back to the command interpreter.

  NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.

  ADDRESS MAP
    AtExit  1931:0000     'CON'      CS:$001d, a String[3]
    Init    1931:0029     'COMSPEC'  CS:$0021, a String[7]
    stubs   1931:0090, 1931:0095, 1931:009a

  DGROUP
    $39de  the console Text variable      $3ade  the program to run
    $3b2e  the displaced ExitProc         $0c58  ExitProc itself
  =========================================================================== }

unit VTShell;

interface

uses
  Dos;

var
  { DS:$3ade -- a String[79]. 1ba1:0aed truncates to $4f on the way in, which
    is what fixes the declared width. }
  { THE ORDER HERE IS `ConFile`, THEN `ProgName`, THEN `SavedExit`, and it is measured:
    $39de + 256 is $3ade and $3ade + 80 is $3b2e, which are the three addresses the code
    names. `ConFile` is a `Text`, and a TP `TextRec` is 256 bytes, so the three close on
    340 -- this unit's whole data size -- with nothing over. `ProgName` was declared first
    and had to move below the file variable, which means `ConFile` is exported too. }
  ConFile   : Text;      { DS:$39de  256 bytes }
  ProgName  : String[79];{ DS:$3ade }

{ ~~1931:0090, 0095, 009a -- three empty far procedures~~ WITHDRAWN, AND THEY
  WERE NEVER IN THIS SEGMENT. This unit spans 144 bytes -- the next segment
  starts at 193a, and 0x1931*16 + 0x90 is 0x193a0, which IS 193a:0000. The
  three "stubs" are DevSB's first three Name functions read past the boundary,
  five bytes each at 193a:0000, 0005 and 000a, with a fourth at 000f the scan
  stopped short of.

  **A SEGMENT BOUNDARY IS NOT A SUGGESTION.** The note said they were "kept
  because they are in the segment"; they are in the next one. Check the span
  against the FOLLOWING segment's address before believing anything near the
  end of a unit -- the same arithmetic that confirmed 116e's 1,232 bytes are
  exact because 11bb begins at 116e:04d0. }

implementation

var
  { ~~ConFile~~ has moved to the interface, above `ProgName` -- see the note there. }
  SavedExit : Pointer;   { DS:$3b2e }

{ --------------------------------------------------------------------------
  1931:0000 -- the exit handler.

  Plain Pascal. The ExitProc chain is Turbo Pascal's own convention: put back
  whatever was there before, do your cleanup, and the runtime walks on to it.
  Restoring FIRST and cleaning up second is the required order -- if Close
  faulted, the chain would still be intact.
  -------------------------------------------------------------------------- }
procedure AtExit; far;
begin
  ExitProc := SavedExit;                          { 1931:0003 .. 1931:000d }
  Close(ConFile);                                 { 1931:0016  1ba1:0673 }
end;

{ --------------------------------------------------------------------------
  1931:0029 -- open the console, find the shell, chain the exit handler.

  Plain Pascal. The frame is `ENTER $200,0`, which is two 256-byte String
  temporaries and nothing else -- they belong to the COMSPEC expression
  below, not to any named local.

  THE LAST LINE COMPILES TO SOMETHING WORTH RECOGNISING. The binary pushes
  three far pointers and then makes TWO calls with nothing in between:

      push @temp2          FExpand's result
      push @temp1          FExpand's argument, AND GetEnv's result
      push CS:$0021        GetEnv's argument, 'COMSPEC'
      call 1b6f:02a5       GetEnv  -- fills temp1, drops its own argument
      call 1b6f:0178       FExpand -- picks up what is still on the stack

  That is Turbo Pascal's string-function convention: the result pointer is
  pushed by the CALLER and left for it to clear, so a nested call reuses the
  outer one's stack slot rather than copying. The same shape turns up in the
  main project's part 007, where FSplit reuses ParamStr's pushed result
  pointer. It reads like a missing push until you know to expect it.
  -------------------------------------------------------------------------- }
{ **IT IS THE UNIT'S INITIALISATION SECTION, NOT A PROCEDURE**, by the same
  reasoning as VTCTRL's: the original's init chain calls 1931:0029, nothing
  else calls it, and a procedure nothing calls is discarded by the smart
  linker -- which is why our image had VTSHELL at ZERO bytes.

  It sits at 0029 rather than 0000 because an initialisation section is the
  LAST code in a unit, and AtExit occupies 0000..0028 ahead of it. }
begin
  Assign(ConFile, 'CON');                         { 1931:0037  1ba1:05a9 }
  Rewrite(ConFile);                               { 1931:0041  1ba1:061e }

  SavedExit := ExitProc;                          { 1931:0046 .. 1931:0050 }
  ExitProc  := @AtExit;                           { 1931:0054 .. 1931:005d }

  ProgName := FExpand(GetEnv('COMSPEC'))          { 1931:0061 .. 1931:0083 }
end.
