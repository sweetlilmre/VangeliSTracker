{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  Segment 1642 -- one function, 144 bytes, all of it.

  Turn an ASCIIZ run of bytes into a Pascal String of EXACTLY the width asked
  for: copied up to the terminator, truncated if longer, space-padded if
  shorter. Module formats store their title and sample names as fixed-length
  NUL-padded fields, and this is what turns one into something printable.

  It is a FUNCTION returning String, so the call frame has the result pointer
  pushed above the parameters and `RETF 6` removes only the parameters --
  the caller drops the result pointer. Same convention as part 007's
  UpCaseStr in the main project.

     [BP+$0c]  @Result      [BP+$08]  the ASCIIZ source
     [BP+$06]  the width

  NAMES ARE THE 1.39b RELEASE'S. `LIB/ASCIIZ.PAS` is this unit line for line --
  same untyped `var s`, same ABSOLUTE array, same repeat/until, same closing
  FOR -- so the unit, the function, the parameters and both locals carry the
  release's spellings, single letters included. Nothing proves 1.31 spelled
  them the same way: the binary has no debug information.
  =========================================================================== }

unit AsciiZ;

interface

function StrAsciiZ(var s; l : Word) : String;

implementation

{ --------------------------------------------------------------------------
  1642:0000. Plain Pascal in the binary -- ENTER 4,0, which is ONE counter
  plus the compiler's temporary for the FOR limit, not two declared locals.

  The length byte is written before the padding runs, and it is written as
  the WIDTH, not as however much was copied -- so the result is always `l`
  characters whatever the source held.

  IT WRITES STRAIGHT INTO THE RESULT. An earlier version of this file built
  the string in a local and assigned it at the end, recorded as a deviation
  forced by Turbo Pascal on the grounds that a function cannot alias its own
  result. That was wrong: `StrAsciiZ[i + 1] := ...` is ordinary Turbo Pascal --
  inside the body the function identifier denotes the result variable and can
  be indexed. The deviation is withdrawn and the extra copy is gone.

  The untyped `var s` with an ABSOLUTE array over it is also how the original
  is written; a typed pointer parameter produces a different frame.
  -------------------------------------------------------------------------- }
function StrAsciiZ(var s; l : Word) : String;
var
  z : array[0..65520] of Char absolute s;
  i : Word;                       { [BP-2] }
begin
  i := 0;
  if z[0] <> #0 then
    repeat
      StrAsciiZ[i + 1] := z[i];
      Inc(i);
    until (i > l) or (z[i] = #0);

  if i > l then Dec(i);
  StrAsciiZ[0] := Chr(l);                         {ALWAYS l     }

  if i < l then
    for i := i + 1 to l do
      StrAsciiZ[i] := ' ';
end;

end.
