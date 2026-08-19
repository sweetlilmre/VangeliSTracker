PROGRAM MakeDoc;

USES Dos;


CONST
  MargenL = 8;
  MargenR = 72;




FUNCTION ReptStr(c: CHAR; n: INTEGER) : STRING;
  VAR
    i : WORD;
  BEGIN
    IF n > 255 THEN n := 255;
    IF n < 0   THEN n := 0;
    ReptStr[0] := CHAR(n);
    FOR i := 1 TO n DO
      ReptStr[i] := c;
  END;




PROCEDURE KillFinalSpaces(VAR s: STRING);
  BEGIN
    WHILE s[Length(s)] IN [' ', #9] DO DEC(s[0]);
  END;




PROCEDURE ConvertTabs(VAR s: STRING);
  CONST
    Sp : STRING[8] = '        ';
  VAR
    i : WORD;
  BEGIN
    REPEAT
      i := Pos(#9, s);
      IF i = 0 THEN EXIT;

      Sp[0] := CHAR(8 - ((i-1) MOD 8));

      s := Copy(s, 1, i-1) + Sp + Copy(s, i+1, 255);
    UNTIL FALSE;
  END;




PROCEDURE Justificar(VAR s: STRING; w: WORD);
  CONST
    PrioChars = ['.', ',', '''', '!', '?', '­', '¨', '-', ')', ']', '}', '"'];
  VAR
    SpPos    : ARRAY[1..100] OF WORD;
    SpPrio   : ARRAY[1..100] OF BOOLEAN;
    SpInsert : ARRAY[1..100] OF WORD;
    i, j, n  : INTEGER;
    target   : STRING;
  LABEL
    Ya;
  BEGIN

    KillFinalSpaces(s);

    j := w - Length(s);
    IF (j <= 0) OR (j = w) THEN EXIT;

    FillChar(SpPos,    SIZEOF(SpPos),    0);
    FillChar(SpPrio,   SIZEOF(SpPrio),   0);
    FillChar(SpInsert, SIZEOF(SpInsert), 0);

    n := 0;

    FOR i := 1 TO Length(s) DO
      IF s[i] = ' ' THEN

        IF ( (i = 1)         OR (s[i-1] <> ' ') ) AND
           ( (i = Length(s)) OR (s[i+1] <> ' ') ) THEN BEGIN

          INC(n);
          SpPos[n] := i;

          IF ((i > 1)         AND (s[i-1] IN PrioChars)) OR
             ((i < Length(s)) AND (s[i+1] IN PrioChars)) THEN BEGIN

             SpPrio[n] := TRUE;

          END;

        END;

    IF n = 0 THEN EXIT;

    WHILE j >= n DO BEGIN
      FOR i := 1 TO n DO INC(SpInsert[i]);
      DEC(j, n);
    END;

    FOR i := 1 TO n DO BEGIN
      IF j = 0 THEN GOTO Ya;
      IF SpPrio[i] THEN BEGIN
        INC(SpInsert[i]);
        DEC(j);
      END;
    END;

    FOR i := 1 TO n DO BEGIN
      IF j = 0 THEN GOTO Ya;
      IF NOT SpPrio[i] THEN BEGIN
        INC(SpInsert[i]);
        DEC(j);
      END;
    END;

Ya:
    Target := '';
    j      := 1;

    FOR i := 1 TO n DO BEGIN
      Target := Target + COPY(s, j, SpPos[i]-j) + ReptStr(' ', SpInsert[i] + 1);
      j := SpPos[i] + 1;
    END;

    s := Target + COPY(s, j, 255);

  END;



PROCEDURE ConvFile(fn : PathStr; VAR fo: TEXT);
  CONST
    StrMargenL : STRING[MargenL] = '                      ';
  VAR
    fi     : TEXT;
    si, so : STRING;
    i      : WORD;
    mode   : (mdNormal, mdIndent, mdInd2nd);
    Indent : WORD;
    NLin   : WORD;

    PROCEDURE WriteSO;
      BEGIN
        IF so <> '' THEN BEGIN
          IF mode = mdIndent THEN BEGIN
            so[MargenL + 1]          := ' ';
            so[MargenL + Indent - 2] := 'o';
          END;
          WriteLn(fo, so);
        END;
        so := '';
        mode := mdNormal;
      END;

  BEGIN

    fn := FExpand(fn);

    Assign (fi, fn);
    Reset  (fi);

    so     := '';
    mode   := mdNormal;
    Indent := 7;
    NLin   := 0;

    Write(#13'                                                                               ');

    WHILE NOT EoF(fi) DO BEGIN

      INC(NLin);
      Write(#13, fn, ' (', NLin, ')');

      ReadLn(fi, si);
      KillFinalSpaces(si);
      ConvertTabs(si);

      IF Length(si) = 0 THEN BEGIN

        IF (so[MargenL + 1] = '*') AND (Indent > 2) THEN BEGIN
          so[MargenL + 1]          := ' ';
          so[MargenL + Indent - 2] := 'o';
        END;

        WriteSO;

        mode := mdNormal;

        WriteLn(fo);

      END ELSE BEGIN

        IF si[1] > #175 THEN BEGIN

          WriteSO;

          WriteLn(fo, StrMargenL + si)

        END ELSE IF si[1] = '@' THEN BEGIN

          ConvFile(Copy(si, 2, 255), fo);

        END ELSE IF si = '-' THEN BEGIN

          WriteSO;

          WriteLn(fo, #12);

        END ELSE BEGIN

          IF ((si[1] = ' ') AND ((mode = mdIndent) OR (mode = mdInd2nd))) OR (si[1] = '*') THEN BEGIN

            IF si[1] = '*' THEN BEGIN
              WriteSO;

              Indent := 2;
              WHILE si[Indent] = ' ' DO INC(Indent);

              so := StrMargenL + '*' + ReptStr(' ', Indent - 3);

              mode := mdIndent;
            END;

            so := so + ' ' + COPY(si, Indent, 255);

            WHILE Length(so) > MargenR DO BEGIN

              mode := mdInd2nd;

              i := MargenR;
              WHILE (i > 0) AND (so[i] <> ' ') DO DEC(i);
              IF i = 0 THEN i := MargenR;
              si := Copy(so, i, 255);
              so[0] := CHAR(i-1);
              Justificar(so, MargenR);

              IF (so[MargenL + 1] = '*') AND (Indent > 2) THEN BEGIN
                so[MargenL + 1]          := ' ';
                so[MargenL + Indent - 2] := 'o';
              END;

              WriteLn(fo, so);
              KillFinalSpaces(si);
              IF si <> '' THEN BEGIN
                WHILE si[1] = ' ' DO si := Copy(si, 2, 255);
                si := StrMargenL + ReptStr(' ', Indent - 1) + si;
              END;
              so := si;

            END;

          END ELSE BEGIN

            IF si[1] = ' ' THEN BEGIN
              WriteSO;
            END;

            IF so = '' THEN so := StrMargenL
                       ELSE so := so + ' ';

            so := so + si;

            WHILE Length(so) > MargenR DO BEGIN

              i := MargenR;
              WHILE (i > 0) AND (so[i] <> ' ') DO DEC(i);
              IF i = 0 THEN i := MargenR;
              si := Copy(so, i, 255);
              so[0] := CHAR(i-1);
              Justificar(so, MargenR);
              WriteLn(fo, so);
              KillFinalSpaces(si);
              IF si <> '' THEN BEGIN
                WHILE si[1] = ' ' DO si := Copy(si, 2, 255);
                si := StrMargenL + si;
              END;
              so := si;

            END;

          END;

        END;

      END;

    END;

    Close(fi);

    WriteLn;

  END;


VAR
  fo : TEXT;

BEGIN

  WriteLn;
  WriteLn('Formateador de textos de VangeliSTracker.');
  WriteLn('(C) 1992 VangeliSTeam');
  WriteLn;

  Assign (fo, ParamStr(2));
  Rewrite(fo);

  ConvFile(ParamStr(1), fo);

  Close(fo);

END.
