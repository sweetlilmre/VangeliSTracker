{ Which source form makes Turbo Pascal 6 distribute an array's element scale
  across the TERMS of an index expression, rather than scaling the sum.

  The .STM loader's period lookup emits

      AND AX,0F / SHL AX,1 / MOV DX,AX ... IMUL DI,AX,18 / ADD DI,DX

  -- the note term scaled by 2 where it is computed and the octave term by 24
  in one multiply. The obvious transcription emits

      AND AX,0F / MOV DX,AX ... IMUL AX,AX,0C / ADD AX,DX / MOV DI,AX / SHL DI,1

  -- the same address, two bytes longer. Each routine below is one candidate
  form; the measurement is which one's bytes match the original's.

  V4 is the CONTROL and is expected to match: a two-subscript array produces
  per-term scaling by construction. It cannot be the answer -- MODCOMMANDS
  indexes NotePeriods with a single subscript and is byte-exact in v1.31b, so
  the array is flat -- but if V4 does NOT match, the reading of the original's
  bytes is wrong and everything else here is moot. }

unit IdxProbe;

interface

const
  Semis = 12;

type
  TFlat = array[0..83] of Word;
  TGrid = array[0..6, 0..11] of Word;

const
  Flat : TFlat = (
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
  Grid : TGrid = (
    (0,0,0,0,0,0,0,0,0,0,0,0), (0,0,0,0,0,0,0,0,0,0,0,0),
    (0,0,0,0,0,0,0,0,0,0,0,0), (0,0,0,0,0,0,0,0,0,0,0,0),
    (0,0,0,0,0,0,0,0,0,0,0,0), (0,0,0,0,0,0,0,0,0,0,0,0),
    (0,0,0,0,0,0,0,0,0,0,0,0));

procedure V1(p : Word; var r : Word);
procedure V2(p : Word; var r : Word);
procedure V3(p : Word; var r : Word);
procedure V4(p : Word; var r : Word);
procedure V5(p : Word; var r : Word);

implementation

{ The transcription as first written: octave term first, note term second. }
procedure V1(p : Word; var r : Word);
begin
  r := Flat[(p shr 4) * Semis + (p and $0F)]
end;

{ Operands the other way round. }
procedure V2(p : Word; var r : Word);
begin
  r := Flat[(p and $0F) + (p shr 4) * Semis]
end;

{ The multiplier written already scaled, indexing a byte-wide view. }
procedure V3(p : Word; var r : Word);
begin
  r := Flat[(p shr 4) * Semis + (p and $0F) * 1]
end;

{ CONTROL -- two subscripts, which scale per term by construction. }
procedure V4(p : Word; var r : Word);
begin
  r := Grid[p shr 4, p and $0F]
end;

{ The index built in a variable first. }
procedure V5(p : Word; var r : Word);
var
  k : Word;
begin
  k := (p shr 4) * Semis + (p and $0F);
  r := Flat[k]
end;

end.
