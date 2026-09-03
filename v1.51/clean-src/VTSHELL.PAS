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
  names no program of its own falls back to the shell. }

unit VTShell;

interface

uses
  Dos;

var
  { The console, opened as an ordinary file. Everything the player prints goes
    through here rather than through Output, which is what makes it immune to
    redirection. }
  ConFile   : Text;      { 256 bytes }

  { The program to run when a playlist entry does not name one. Set here to the
    command interpreter and overwritten per entry by the playlist reader. }
  ProgName  : String[79];


implementation

var
  { Whatever was on the ExitProc chain before this unit joined it. }
  SavedExit : Pointer;

{ --------------------------------------------------------------------------
  Close the console file on the way out of the program.

  RESTORING THE CHAIN COMES FIRST AND THE CLEANUP SECOND, and the order is
  required rather than stylistic. Turbo Pascal's ExitProc convention is that
  each handler puts back the pointer it displaced and then does its own work;
  the runtime walks on to whatever ExitProc holds when the handler returns. If
  Close faulted with the restore still pending, the chain would be broken and
  every handler below this one would be skipped -- including the runtime's own. }
procedure AtExit; far;
begin
  ExitProc := SavedExit;
  Close(ConFile);
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

  That is Turbo Pascal's string-function convention: the result pointer is
  pushed by the CALLER and left for it to clear, so a nested call reuses the
  outer one's stack slot rather than copying. The same shape turns up in the
  main project's part 007, where FSplit reuses ParamStr's pushed result
  pointer. It reads like a missing push until you know to expect it. }
begin
  Assign(ConFile, 'CON');
  Rewrite(ConFile);

  SavedExit := ExitProc;
  ExitProc  := @AtExit;

  ProgName := FExpand(GetEnv('COMSPEC'))
end.
