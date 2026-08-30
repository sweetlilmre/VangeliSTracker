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
  guarantee, not a ceiling.}

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
  made at the end.}
function StrAsciiZ(var s; l : Word) : String;
var
  z : array[0..65520] of Char absolute s;
  i : Word;                       
begin
  i := 0;

  { An empty source skips the copy entirely and falls through to the padding,
    which is what makes StrAsciiZ(empty, 8) eight spaces rather than ''. }
  if z[0] <> #0 then
    repeat
      StrAsciiZ[i + 1] := z[i];
      Inc(i);
    until (i > l) or (z[i] = #0);

  { The loop leaves `i` one past the last character it copied, and on the
    truncation arm it has already gone one further than the width allows --
    hence the correction before the count is used as a position. }
  if i > l then Dec(i);
  StrAsciiZ[0] := Chr(l);                         { ALWAYS l     }

  if i < l then
    for i := i + 1 to l do
      StrAsciiZ[i] := ' ';
end;

end.
