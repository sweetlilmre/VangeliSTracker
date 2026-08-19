PROGRAM CCurs;

USES Video;




TYPE
   PVGA13Screen = ^TVGA13Screen;

   PCelHeader = ^TCelHeader;
   TCelHeader = RECORD
                  Ident : WORD;
                  HRez  : WORD;
                  VRez  : WORD;
                  Resto : ARRAY [3..15] OF WORD
               END;
   PCelFile = ^TCelFile;
   TCelFile = RECORD
                 Header : TCelHeader;
                 Pal    : TVGAPalette;
                 Scr    : PVGA13Screen
              END;



FUNCTION LoadCel(s: STRING) : PCelFile;
  VAR
    f : FILE;
    c : PCelFile;
  BEGIN

    NEW(c);
    Assign(f, s);
    Reset(f, 1);
    BlockRead(f, c^, SIZEOF(c^.Header) + SIZEOF(c^.Pal));
    GETMEM(c^.Scr, c^.Header.HRez * c^.Header.VRez);
    BlockRead(f, c^.Scr^, c^.Header.HRez * c^.Header.VRez);
    Close(f);
    LoadCel := c;

  END;




TYPE
  THexString = STRING[4];

FUNCTION HexWord(w: WORD) : THexString;
  CONST
    tabla : STRING[16] = '0123456789ABCDEF';
  BEGIN

    HexWord[0] := #4;
    HexWord[1] := tabla[ (w SHR 12)         + 1];
    HexWord[2] := tabla[((w SHR  8) AND $F) + 1];
    HexWord[3] := tabla[((w SHR  4) AND $F) + 1];
    HexWord[4] := tabla[( w         AND $F) + 1];

  END;


TYPE
  TArrayByte = ARRAY[0..64000] OF BYTE;
  PArrayByte = ^TArrayByte;

VAR
  cel,
  celx : PCelFile;
  f    : BOOLEAN;
  t    : FILE;
  v,
  i, j,
  k, l,
  cnt,
  dotx,
  doty,
  nx,
  ny,
  linl,
  acct,
  accm : WORD;
  p    : PArrayByte;
  a    : ARRAY[0..7] OF BYTE;
LABEL
  Do32, Fin;
BEGIN

  cel  := LoadCel(ParamStr(1));
{  celx := LoadCel(ParamStr(2));}
  nx   := (cel^.Header.HRez SHR 3);
  ny   := (cel^.Header.VRez SHR 3);
  linl := cel^.Header.HRez;

  Assign(t, ParamStr(3));
  Rewrite(t, 1);

{
  p   := PArrayByte(celx^.Scr);
  cnt := 0;

  FOR i := 1 TO 1 DO
    FOR j := 1 TO 32 DO BEGIN

      FOR k := 0 TO 7 DO BEGIN
        acct := 0;
        accm := 0;
        FOR l := 0 TO 7 DO BEGIN
          v := p^[(((i-1)*8) + k)*32*8 + (j-1)*8 + l];
          IF v = 31 THEN acct := acct + 1 SHL (7-l)
        END;
        a[k]    := NOT acct;
      END;

      BlockWrite(t, a[0], 8, v);
      INC(cnt);
      IF cnt >= 32 THEN GOTO Do32;

    END;

}
Do32:
  p   := PArrayByte(cel^.Scr);
  cnt := 0;

  FOR i := 1 TO ny DO
    FOR j := 1 TO nx DO BEGIN

      FOR k := 0 TO 7 DO BEGIN
        acct := 0;
        accm := 0;
        FOR l := 0 TO 7 DO BEGIN
          v := p^[(((i-1)*8) + k)*linl + (j-1)*8 + l];
          IF v = 31 THEN acct := acct + 1 SHL (7-l)
        END;
        a[k]    := NOT BYTE(acct);
      END;

      BlockWrite(t, a[0], 8, v);
      INC(cnt);
      IF cnt >= 256 THEN GOTO Fin;

    END;

Fin:
  Close(t)

END.