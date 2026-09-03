{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Startup housekeeping: open the console, find the command interpreter, and
  arrange to tidy up on the way out.

  Three unrelated things live here, and they are together only because they
  all happen once at startup:

    * the console is opened AS A FILE, under the name 'CON'
    * COMSPEC is looked up and expanded, giving a fallback program to run
    * an exit handler is chained on, to close the console again

  OPENING 'CON' EXPLICITLY IS THE INTERESTING ONE. Writing through a Text
  variable assigned to 'CON' reaches the console even when the program's
  standard output has been redirected, so `DEMOVT @PLAY.CFG > LOG` still puts
  the banner on the screen and the log gets nothing. DemoVT is launched from
  batch files, where redirection is ordinary, so this is deliberate rather
  than incidental.

  THE PROGRAM NAME IS A DEFAULT, NOT A DECISION. What this unit puts in
  ProgName is the command interpreter; the playlist reader overwrites it per
  entry, and the player hands whatever is there to Dos.Exec. So an entry that
  names no program of its own falls back to the shell.

  [re] SEGMENT 1b19 -- 159 bytes, five routines, three of which do nothing.

  [re] DS:$3ade IS THE PROGRAM PSYCHO NEUROSIS ACTUALLY RUNS. 109c overwrites
  it per playlist entry and 1000:03af hands it to Dos.Exec.

  [re] NAMES ARE PROVISIONAL: Borland Pascal 6, no debug information.

  [re] 1b19 IN THIS IMAGE, NOT 1931. Charted in Ghidra by its two string
  constants, which pin the SEGMENT AND show the layout did not move: the
  the same offsets they hold in v1.31b. Init is confirmed separately -- one
  of only two `ENTER $200,0` in the image is at 1b19:0029, its v1.31b
  String[3] 'CON' is at 1b19:001d and the String[7] 'COMSPEC' at 1b19:0021,
  offset. The CS:$ offsets below are therefore unchanged.
  [re] ADDRESS MAP
    AtExit  1b19:0000     'CON'      CS:$001d, a String[3]
    Init    1b19:0029     'COMSPEC'  CS:$0021, a String[7]

  [re] DGROUP
    $39de  the console Text variable      $3ade  the program to run
    $3b2e  the displaced ExitProc         $0c58  ExitProc itself
  =========================================================================== }

unit VTShell;

interface

uses
  Dos;

var
  { The console, opened as an ordinary file. Everything the player prints goes
    through here rather than through Output, which is what makes it immune to
    redirection.

    [re] DS:$3ade -- a String[79]. 1d89:0aed truncates to $4f on the way in,
    which is what fixes the declared width.

    [re] THE ORDER HERE IS `ConFile`, THEN `ProgName`, THEN `SavedExit`, and it
    is measured: $39de + 256 is $3ade and $3ade + 80 is $3b2e, which are the
    three addresses the code names. `ConFile` is a `Text`, and a TP `TextRec` is
    256 bytes, so the three close on 340 -- this unit's whole data size -- with
    nothing over. `ProgName` was declared first and had to move below the file
    variable, which means `ConFile` is exported too. }
  ConFile   : Text;      { DS:$5d38  256 bytes }

  { The program to run when a playlist entry does not name one. Set here to the
    command interpreter and overwritten per entry by the playlist reader. }
  ProgName  : String[79];{ DS:$5e38 }

{ [re] ~~1b19:0090, 0095, 009a -- three empty far procedures~~ WITHDRAWN, AND
  THEY WERE NEVER IN THIS SEGMENT. This unit spans 144 bytes -- the next
  SEGMENT starts at 1b22, and 0x1b19*16 + 0x90 is 0x1b220, which IS 1b22:0000.
  (In v1.31b the same sum reads 0x1931*16 + 0x90 = 0x193a0 = 193a:0000. A bulk
  re-base rewrote the address on the right of "which IS" and left the
  arithmetic on the left, so this sentence contradicted itself for one commit:
  prose that DERIVES an address cannot be re-based one number at a time.)
  The three "stubs" are DevSB's first three Name functions read past the
  boundary, five bytes each at 1b22:0000, 0005 and 000a, with a fourth at 000f
  the scan stopped short of.

  [re] **A SEGMENT BOUNDARY IS NOT A SUGGESTION.** The note said they were
  "kept because they are in the SEGMENT"; they are in the next one. Check the
  span against the FOLLOWING SEGMENT's address before believing anything near
  the end of a unit -- the same arithmetic that confirmed 116e's 1,232 bytes
  are exact because 11bb begins at 1182:04d0. }

implementation

var
  { Whatever was on the ExitProc chain before this unit joined it. }
  SavedExit : Pointer;   { DS:$5e88 }

{ --------------------------------------------------------------------------
  Close the console file on the way out of the program.

  RESTORING THE CHAIN COMES FIRST AND THE CLEANUP SECOND, and the order is
  required rather than stylistic. Turbo Pascal's ExitProc convention is that
  each handler puts back the pointer it displaced and then does its own work;
  the runtime walks on to whatever ExitProc holds when the handler returns. If
  Close faulted with the restore still pending, the chain would be broken and
  every handler below this one would be skipped -- including the runtime's own.

  [re] 1b19:0000. Plain Pascal.
  -------------------------------------------------------------------------- }
{ @asm 000 1b19:0000 +41 }
procedure AtExit; far;
begin
  ExitProc := SavedExit;                          { 1b19:0003 .. 1b19:000d }
  Close(ConFile);                                 { 1b19:0016  1d89:0673 }
end;

{ --------------------------------------------------------------------------
  Open the console, chain the exit handler, and find the command interpreter.

  This is the unit's initialisation section, so it runs once before the main
  program body, in the order the units are linked.

  `FExpand(GetEnv('COMSPEC'))` is the whole of the shell lookup: read the
  environment variable, then expand it to a full path so that the later Exec
  does not depend on the current directory. If COMSPEC is unset, GetEnv
  returns an empty string and FExpand turns it into the current directory --
  the Exec then fails, and nothing here checks.

  [re] 1b19:0029. Plain Pascal. The frame is `ENTER $200,0`, which is two
  256-byte String temporaries and nothing else -- they belong to the COMSPEC
  expression, not to any named local.

  [re] THE LAST LINE COMPILES TO SOMETHING WORTH RECOGNISING. The binary pushes
  three far pointers and then makes TWO calls with nothing in between:

      push @temp2          FExpand's result
      push @temp1          FExpand's argument, AND GetEnv's result
      push CS:$0021        GetEnv's argument, 'COMSPEC'
      call 1d57:02a5       GetEnv  -- fills temp1, drops its own argument
      call 1d57:0178       FExpand -- picks up what is still on the stack

  That is Turbo Pascal's string-function convention: the result pointer is
  pushed by the CALLER and left for it to clear, so a nested call reuses the
  outer one's stack slot rather than copying. The same shape turns up in the
  main project's part 007, where FSplit reuses ParamStr's pushed result
  pointer. It reads like a missing push until you know to expect it.

  [re] **IT IS THE UNIT'S INITIALISATION SECTION, NOT A PROCEDURE**, by the
  same reasoning as VTCTRL's: the original's init chain calls 1b19:0029,
  nothing else calls it, and a procedure nothing calls is discarded by the
  smart linker -- which is why our image had VTSHELL at ZERO bytes. It sits at
  0029 rather than 0000 because an initialisation section is the LAST code in a
  unit, and AtExit occupies 0000..0028 ahead of it.
  -------------------------------------------------------------------------- }
{ @asm 000 1b19:0029 Init }
begin
  Assign(ConFile, 'CON');                         { 1b19:0037  1d89:05a9 }
  Rewrite(ConFile);                               { 1b19:0041  1d89:061e }

  SavedExit := ExitProc;                          { 1b19:0046 .. 1b19:0050 }
  ExitProc  := @AtExit;                           { 1b19:0054 .. 1b19:005d }

  ProgName := FExpand(GetEnv('COMSPEC'))          { 1b19:0061 .. 1b19:0083 }
end.
