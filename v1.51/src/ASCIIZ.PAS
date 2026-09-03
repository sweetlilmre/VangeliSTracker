{ ===========================================================================
  DemoVT v1.51 -- (C) 1992-94 VangeliSTeam (JCAB).

  Turn a NUL-terminated run of bytes into a Pascal String of EXACTLY the width
  asked for: copied up to the terminator, truncated if longer, space-padded if
  shorter.

  WHY A MODULE PLAYER NEEDS THIS. Module formats store their title and their
  sample names as fixed-length NUL-padded fields rather than as Pascal strings,
  so every name the player displays arrives as a run of bytes with no length
  byte in front of it. This unit is what turns one into something printable,
  and it is the whole unit -- one function, nothing else.

  [1.39b] "Converts the AsciiZ string 's' to a TP string with a maximum
  length."

  **THE RELEASE SAYS "MAXIMUM" AND THE CODE MEANS "EXACTLY".** A shorter source
  is padded out with spaces rather than left short, so the result is always `l`
  characters. That matters to a caller laying out a column: the width is a
  guarantee, not a ceiling.

  [re] SEGMENT 1830 -- one function, 144 bytes, all of it.

  [re] It is a FUNCTION returning String, so the call frame has the result
  pointer pushed above the parameters and `RETF 6` removes only the parameters
  -- the caller drops the result pointer. Same convention as part 007's
  UpCaseStr in the main project.

       [BP+$0c]  @Result      [BP+$08]  the ASCIIZ source
       [BP+$06]  the width

  [re] NAMES ARE THE 1.39b RELEASE'S. `LIB/ASCIIZ.PAS` is this unit line for
  line -- same untyped `var s`, same ABSOLUTE array, same repeat/until, same
  closing FOR -- so the unit, the function, the parameters and both locals
  carry the release's spellings, single letters included. Nothing proves 1.31
  spelled them the same way: the binary has no debug information.
  =========================================================================== }

unit AsciiZ;

interface

function StrAsciiZ(var s; l : Word) : String;

implementation

{ --------------------------------------------------------------------------
  Copy `l` characters out of the NUL-terminated buffer `s` and return them as
  a Pascal String, padded with spaces if the buffer ran out first.

  `s` is untyped, so the caller may pass any buffer at all -- an array of Char,
  a record field, a pointer dereference -- and the function reads it through an
  ABSOLUTE array laid over the parameter. There is no bounds checking of any
  kind: the caller promises the buffer holds either `l` characters or a NUL
  before then, and nothing here can tell if that promise is broken.

  THE LENGTH BYTE IS WRITTEN AS THE WIDTH, NOT AS HOWEVER MUCH WAS COPIED, and
  it is written before the padding loop runs. That is the "exactly l" guarantee
  in one instruction, and it is why the padding loop can be skipped entirely
  when the source was long enough.

  THE RESULT IS BUILT IN PLACE. `StrAsciiZ[i + 1] := ...` indexes the function's
  own result: inside the body a function identifier denotes the result variable
  and can be subscripted like any other string. No local is used and no copy is
  made at the end.

  [re] 1830:0000. Plain Pascal in the binary -- ENTER 4,0, which is ONE counter
  plus the compiler's temporary for the FOR limit, not two declared locals.

  [re] An earlier version of this file built the string in a local and assigned
  it at the end, recorded as a deviation forced by Turbo Pascal on the grounds
  that a function cannot alias its own result. ~~That was wrong~~ -- the
  deviation is withdrawn and the extra copy is gone. The untyped `var s` with
  an ABSOLUTE array over it is also how the original is written; a typed
  pointer parameter produces a different frame.
  -------------------------------------------------------------------------- }
function StrAsciiZ(var s; l : Word) : String;
var
  z : array[0..65520] of Char absolute s;
  i : Word;                       { [re] [BP-2] }
begin
  i := 0;                                         { 1830:0004 }

  { An empty source skips the copy entirely and falls through to the padding,
    which is what makes StrAsciiZ(empty, 8) eight spaces rather than ''. }
  if z[0] <> #0 then                              { 1830:000c }
    repeat
      StrAsciiZ[i + 1] := z[i];                   { 1830:001a, 1830:0026 }
      Inc(i);                                     { 1830:0029 }
    until (i > l) or (z[i] = #0);                 { 1830:002f, 1830:003c }

  { The loop leaves `i` one past the last character it copied, and on the
    truncation arm it has already gone one further than the width allows --
    hence the correction before the count is used as a position. }
  if i > l then Dec(i);                           { 1830:0045, 1830:004a }
  StrAsciiZ[0] := Chr(l);                         { 1830:004d  ALWAYS l     }

  if i < l then                                   { 1830:0056 }
    for i := i + 1 to l do                        { 1830:0068, 1830:006d }
      StrAsciiZ[i] := ' ';                        { 1830:007d }
end;

end.
