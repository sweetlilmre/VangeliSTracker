{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Make sure a directory string ends in a separator. One routine, and that is
  the whole unit.

  WHY IT EXISTS. DemoVT builds file names by concatenation -- directory plus
  name, with nothing between them -- so a directory that does not already end
  in a backslash produces `C:\MODSTUNE.MOD`. This is what stops that, and it is
  called on every configured directory before any of them is used.

  IT ACCEPTS THREE ENDINGS AS ALREADY-TERMINATED -- ':', '\' and '/' -- but
  only ever appends '\'. Accepting ':' leaves a bare drive like `C:` alone,
  which is correct: `C:TUNE.MOD` means the current directory of drive C, and
  turning it into `C:\TUNE.MOD` would silently change which file is opened.
  Accepting '/' matters because DOS itself takes a forward slash as a
  separator even though COMMAND.COM does not, so a path typed into VT.CFG with
  forward slashes still works.

  AN EMPTY STRING GETS A BACKSLASH APPENDED, which is a quirk rather than a
  decision: `Path[0]` is then the length byte itself, which is zero and matches
  none of the three. It is harmless -- an empty directory becomes '\', the
  root, which is where a bare file name would have been looked for anyway --
  but a caller passing '' and expecting '' back will not get it.}

unit FileUtil;

interface

uses
  Dos;   { for PathStr = String[79] -- the release declares this parameter
           as PathStr, not as a generic String }

procedure AddBar2Path(var Path : PathStr); far;

implementation

{ --------------------------------------------------------------------------
  Append a backslash to `Path` unless it already ends in a separator.

  The string is modified in place and grows by at most one character. There is
  no length check: a `PathStr` is `String[79]`, and a caller passing one that
  is already 79 characters long will have the 80th written past the declared
  end. Nothing in the program does that -- the directories come from VT.CFG
  and from the command line, both of which are shorter -- but it is not
  defended against.

  Twice, once on the read and once on the write, for six bytes. That was the
  whole remaining difference in this unit and it was parked for several
  sessions as "not source shape, cause open" -- correctly, as it turned out.
  **It is Turbo Pascal 6 against 7.** TP6 reloads exactly where the original
  does, and this unit was the cleanest single piece of evidence that the
  original's compiler was TP6: three divergent regions to none, with no change
  to the source at all. See docs/CONTINUATION.md.
  -------------------------------------------------------------------------- }
procedure AddBar2Path(var Path : PathStr);
begin
  case Path[Length(Path)] of
    ':', '\', '/' : ;
  else
    { Two statements, and the order matters: the character is written one past
      the current end FIRST, then the length byte is bumped to take it in. }
    Path[Length(Path) + 1] := '\';
    Inc(Path[0]);                                 { the length   }
  end;
end;

end.
