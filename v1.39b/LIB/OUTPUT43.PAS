UNIT OutPut43;

INTERFACE

USES Vid43;

TYPE
  AoW = ARRAY[0..32750] OF WORD;
  PAoW = ^AoW;

  PWindow = ^TWindow;
  TWindow = RECORD
    x, y, w, h : INTEGER;
    col        : STRING[8];
    vis, forz,
    act        : BOOLEAN;
  END;

CONST
  pwAttr : BYTE = $62;





PROCEDURE ClearScreen;
FUNCTION  BoxByte          (b: BYTE)        : CHAR;
FUNCTION  ByteBox          (b: CHAR)        : BYTE;
PROCEDURE PutWindow        (VAR w: TWindow);
PROCEDURE PutWindowBigFrame(VAR w: TWindow);


FUNCTION  ParseCoords    (x, y: WORD)                     : WORD;
PROCEDURE DirectWriteAttr(offs: WORD; s: STRING; a: BYTE);
PROCEDURE DirectWrite    (offs: WORD; s: STRING);
PROCEDURE DirectWriteBig (offs: WORD; VAR s: STRING);
PROCEDURE PutAttrs       (offs, n: WORD; a: BYTE);
PROCEDURE PutAttrsMask   (offs, n: WORD; a, m: BYTE);
FUNCTION  GetAsciiInScr  (offs: WORD)                     : CHAR;
PROCEDURE RectAttr       (offs, w, h: WORD; a: BYTE);
PROCEDURE RectAttrMask   (offs, w, h: WORD; a, m: BYTE);
PROCEDURE PutRotulo      (offs: WORD; s: STRING; a: BYTE);


FUNCTION  SaveWindow  (VAR p: PAoW; x, y, w, h: WORD) : BOOLEAN;
PROCEDURE StoreWindow     (p: PAoW; x, y, w, h: WORD);
PROCEDURE RestoreWindow   (p: PAoW);
PROCEDURE DoneWindow      (p: PAoW);
FUNCTION  SavedWindowSize (p: PAoW)                   : WORD;




IMPLEMENTATION

USES Heaps;




PROCEDURE ClearScreen; ASSEMBLER;
  ASM
        MOV     AX,ScrSegment
        MOV     ES,AX
        MOV     CX,ScreenWords
        MOV     DI,ScrOffset
        MOV     AX,$0120
        CLD
        REP STOSW
  END;



FUNCTION  ParseCoords(x, y: WORD) : WORD; ASSEMBLER;
  ASM
        MOV     AX,y
        MOV     BX,ScreenBytesX
        MUL     BX
        ADD     AX,x
        ADD     AX,x
        ADD     AX,ScrOffset
  END;




PROCEDURE DirectWriteAttr(offs: WORD; s: STRING; a: BYTE); ASSEMBLER;
  ASM
        MOV     BX,offs
        MOV     AX,ScrSegment
        MOV     ES,AX
        PUSH    DS
        LDS     SI,s
        MOV     AH,a
        MOV     CL,[DS:SI]
@@lp:    AND     CL,CL
         JZ      @@fin
         INC     SI
         MOV     AL,[DS:SI]
         MOV     [ES:BX],AX
         INC     BX
         INC     BX
         DEC     CL
         JMP     @@lp
@@fin:  POP     DS
  END;


PROCEDURE DirectWrite(offs: WORD; s: STRING); ASSEMBLER;
  ASM
        MOV     BX,offs
        MOV     AX,ScrSegment
        MOV     ES,AX
        PUSH    DS
        LDS     SI,s
        MOV     CL,[DS:SI]
@@lp:    AND     CL,CL
         JZ      @@fin
         INC     SI
         MOV     AL,[DS:SI]
         MOV     [ES:BX],AL
         INC     BX
         INC     BX
         DEC     CL
         JMP     @@lp
@@fin:  POP     DS
  END;



PROCEDURE DirectWriteBig(offs: WORD; VAR s: STRING);
  CONST
    Num1:STRING[10] = #000#001#002#003#004#005#006#007#008#009;
    Num2:STRING[10] = #224#225#226#227#228#227#224#229#224#231;
                      { A   B   C   D   E   F   G   H   I   J   K   L   M   N   O   P   Q   R   S   T   U   V   W   X   Y   Z }
    Let1:STRING[26] = #010#011#012#013#005#005#014#015#016#017#018#019#020#021#000#011#000#011#022#016#024#024#024#023#023#007;
    Let2:STRING[26] = #230#232#239#232#233#234#224#230#225#227#235#233#230#230#224#234#240#235#227#229#224#236#237#238#229#028;
  VAR
    s1, s2 : STRING[90];
    I      : WORD;
  BEGIN
    s1[0] := s[0];
    s2[0] := s[0];
    FOR i := 1 TO Length(s) DO BEGIN
      IF           (s[i] >= '0') AND (s[i] <= '9')  THEN BEGIN
        s1[i] := Num1[ORD(s[i]) - ORD('0') + 1];
        s2[i] := Num2[ORD(s[i]) - ORD('0') + 1];
      END ELSE IF ((s[i] >= 'A') AND (s[i] <= 'Z')) OR
                  ((s[i] >= 'a') AND (s[i] <= 'z')) THEN BEGIN
        s1[i] := Let1[ORD(UPCASE(s[i])) - ORD('A') + 1];
        s2[i] := Let2[ORD(UPCASE(s[i])) - ORD('A') + 1];
      END ELSE IF s[i] = '-' THEN BEGIN
        s1[i] := ' ';
        s2[i] := #029;
      END ELSE IF s[i] = '#' THEN BEGIN
        s1[i] := #026;
        s2[i] := #025;
      END ELSE IF s[i] = '=' THEN BEGIN
        s1[i] := #027;
        s2[i] := '-';
      END ELSE BEGIN
        s1[i] := ' ';
        s2[i] := ' ';
      END;
    END;
    DirectWrite(offs,   s1);
    DirectWrite(offs + ScreenBytesX, s2);
  END;




PROCEDURE PutAttrs(offs, n: WORD; a: BYTE); ASSEMBLER;
  ASM
        MOV     BX,offs
        MOV     AX,ScrSegment
        MOV     ES,AX
        INC     BX
        MOV     AL,a
        MOV     CX,n
        AND     CX,CX
        JZ      @@fin
@@lp:    MOV    [ES:BX],AL
         INC    BX
         INC    BX
         LOOP   @@lp
@@fin:  
  END;




PROCEDURE PutAttrsMask(offs, n: WORD; a, m: BYTE); ASSEMBLER;
  ASM
        MOV     BX,offs
        MOV     AX,ScrSegment
        MOV     ES,AX
        INC     BX
        MOV     AL,a
        MOV     CX,n
        AND     CX,CX
        MOV     AH,m
        JZ      @@fin
@@lp:    AND    [ES:BX],AH
         OR     [ES:BX],AL
         INC    BX
         INC    BX
         LOOP   @@lp
@@fin:  
  END;




FUNCTION GetAsciiInScr(offs: WORD) : CHAR; ASSEMBLER;
  ASM
        MOV     BX,offs
        MOV     AX,ScrSegment
        MOV     ES,AX
        MOV     AL,[ES:BX]
  END;




FUNCTION BoxByte(b: BYTE) : CHAR;
  CONST
    boxes : STRING[48] = '°¬¯À«³ÚÃ®ÙÄÁ¿´ÂÅ°¬¯È«ÌÉÇ®¼Ë°»°Ñ°°¬¯È«¹É°®¼ÊÏ»¶°°';
  BEGIN
    BoxByte := boxes[b+1];
  END;




FUNCTION ByteBox(b: CHAR) : BYTE;
  VAR
    i : WORD;
  BEGIN
    FOR i := 0 TO 47 DO
      IF b = BoxByte(i) THEN BEGIN
        ByteBox := i;
        EXIT;
      END;
    ByteBox := 0;
  END;




PROCEDURE PutWindowBigFrame(VAR w: TWindow);
  VAR
    s      : STRING[90];
    i      : WORD;
    ch     : CHAR;
    offs   : WORD;
  BEGIN
    WITH w DO BEGIN
      offs := ParseCoords(x, y);
      s[0] := CHR(w);

      IF h = 1 THEN BEGIN

        s[1] := BoxByte(ByteBox(GetAsciiInScr(offs)) OR 2);
        FOR i := 2 TO w-1 DO
          s[i] :=  BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*2)) OR $A);
        s[w] := BoxByte(ByteBox(GetAsciiInScr(offs + (w - 1)*2)) OR 8);
        DirectWriteAttr(offs, s, pwAttr);

      END ELSE IF w = 1 THEN BEGIN

        ch := BoxByte(ByteBox(GetAsciiInScr(offs)) OR 4);
        DirectWriteAttr(offs,         ch, pwAttr);
        ch := BoxByte(ByteBox(GetAsciiInScr(offs + (h - 1)*ScreenBytesX)) OR 1);
        DirectWriteAttr(offs + (h - 1)*ScreenBytesX,         ch, pwAttr);
        FOR i := 2 TO h - 1 DO BEGIN
          ch := BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*ScreenBytesX)) OR 5);
          DirectWriteAttr(offs + (i - 1)*ScreenBytesX,         ch, pwAttr);
        END;

      END ELSE BEGIN

        s[1] := BoxByte(ByteBox(GetAsciiInScr(offs)) AND $F OR $16);
        IF col[1] = #0 THEN
          FOR i := 2 TO w-1 DO
            s[i] :=  BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*2)) AND $F OR $1A)
        ELSE
          FOR i := 2 TO w-1 DO
            s[i] :=  BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*2)) AND $B OR $1A);
        s[w] := BoxByte(ByteBox(GetAsciiInScr(offs + (w - 1)*2)) AND $F OR $2C);
        DirectWriteAttr(offs, s, pwAttr);

        s[1] := BoxByte(ByteBox(GetAsciiInScr(offs + (h - 1)*ScreenBytesX)) AND $F OR $13);
        IF col[1] = #0 THEN
          FOR i := 2 TO w-1 DO
            s[i] := BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*2 + (h - 1)*ScreenBytesX)) AND $F OR $2A)
        ELSE
          FOR i := 2 TO w-1 DO
            s[i] := BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*2 + (h - 1)*ScreenBytesX)) AND $E OR $2A);
        s[w] := BoxByte(ByteBox(GetAsciiInScr(offs + (w - 1)*2 + (h - 1)*ScreenBytesX)) AND $F OR $29);
        DirectWriteAttr(offs + (h - 1)*ScreenBytesX, s, pwAttr);

        s[0] := CHR(w - 2);
        FillChar(s[1], w-2, ' ');
        FOR i := 2 TO h - 1 DO BEGIN
          IF col[1] <> #0 THEN BEGIN
            DirectWriteAttr(offs + 2 + (i - 1)*ScreenBytesX,     s,   BYTE(col[1]));
            ch := BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*ScreenBytesX)) AND $D OR $15);
            DirectWriteAttr(offs + (i - 1)*ScreenBytesX,         ch, pwAttr);
            ch := BoxByte(ByteBox(GetAsciiInScr(offs + (w - 1)*2 + (i - 1)*ScreenBytesX)) AND $7 OR $25);
            DirectWriteAttr(offs + (w - 1)*2 + (i - 1)*ScreenBytesX, ch, pwAttr);
          END ELSE BEGIN
            ch := BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*ScreenBytesX)) AND $F OR $15);
            DirectWriteAttr(offs + (i - 1)*ScreenBytesX,         ch, pwAttr);
            ch := BoxByte(ByteBox(GetAsciiInScr(offs + (w - 1)*2 + (i - 1)*ScreenBytesX)) AND $F OR $25);
            DirectWriteAttr(offs + (w - 1)*2 + (i - 1)*ScreenBytesX, ch, pwAttr);
          END;
        END;
      END;
    END;
  END;




PROCEDURE PutWindow(VAR w: TWindow);
  VAR
    s      : STRING[90];
    i      : WORD;
    ch     : CHAR;
    offs   : WORD;
  BEGIN
    WITH w DO BEGIN
      offs := ParseCoords(x, y);

      s[0] := CHR(w);

      IF h = 1 THEN BEGIN

        s[1] := BoxByte(ByteBox(GetAsciiInScr(offs)) OR 2);
        FOR i := 2 TO w-1 DO
          s[i] :=  BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*2)) OR $A);
        s[w] := BoxByte(ByteBox(GetAsciiInScr(offs + (w - 1)*2)) OR 8);
        DirectWriteAttr(offs, s, pwAttr);

      END ELSE IF w = 1 THEN BEGIN

        ch := BoxByte(ByteBox(GetAsciiInScr(offs)) OR 4);
        DirectWriteAttr(offs,         ch, pwAttr);
        ch := BoxByte(ByteBox(GetAsciiInScr(offs + (h - 1)*ScreenBytesX)) OR 1);
        DirectWriteAttr(offs + (h - 1)*ScreenBytesX,         ch, pwAttr);
        FOR i := 2 TO h - 1 DO BEGIN
          ch := BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*ScreenBytesX)) OR 5);
          DirectWriteAttr(offs + (i - 1)*ScreenBytesX,         ch, pwAttr);
        END;

      END ELSE BEGIN

        s[1] := BoxByte(ByteBox(GetAsciiInScr(offs)) OR 6);
        IF col[1] = #0 THEN
          FOR i := 2 TO w-1 DO
            s[i] :=  BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*2)) OR $A)
        ELSE
          FOR i := 2 TO w-1 DO
            s[i] :=  BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*2)) AND $3B OR $A);
        s[w] := BoxByte(ByteBox(GetAsciiInScr(offs + (w - 1)*2)) OR $C);
        DirectWriteAttr(offs, s, pwAttr);

        s[1] := BoxByte(ByteBox(GetAsciiInScr(offs + (h - 1)*ScreenBytesX)) OR 3);
        IF col[1] = #0 THEN
          FOR i := 2 TO w-1 DO
            s[i] := BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*2 + (h - 1)*ScreenBytesX)) OR $A)
        ELSE
          FOR i := 2 TO w-1 DO
            s[i] := BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*2 + (h - 1)*ScreenBytesX)) AND $3E OR $A);
        s[w] := BoxByte(ByteBox(GetAsciiInScr(offs + (w - 1)*2 + (h - 1)*ScreenBytesX)) OR 9);
        DirectWriteAttr(offs + (h - 1)*ScreenBytesX, s, pwAttr);

        s[0] := CHR(w - 2);
        FillChar(s[1], w-2, ' ');
        FOR i := 2 TO h - 1 DO BEGIN
          IF col[1] <> #0 THEN BEGIN
            DirectWriteAttr(offs + 2 + (i - 1)*ScreenBytesX,     s,   BYTE(col[1]));
            ch := BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*ScreenBytesX)) AND $3D OR 5);
            DirectWriteAttr(offs + (i - 1)*ScreenBytesX,         ch, pwAttr);
            ch := BoxByte(ByteBox(GetAsciiInScr(offs + (w - 1)*2 + (i - 1)*ScreenBytesX)) AND $37 OR 5);
            DirectWriteAttr(offs + (w - 1)*2 + (i - 1)*ScreenBytesX, ch, pwAttr);
          END ELSE BEGIN
            ch := BoxByte(ByteBox(GetAsciiInScr(offs + (i - 1)*ScreenBytesX)) OR 5);
            DirectWriteAttr(offs + (i - 1)*ScreenBytesX,         ch, pwAttr);
            ch := BoxByte(ByteBox(GetAsciiInScr(offs + (w - 1)*2 + (i - 1)*ScreenBytesX)) OR 5);
            DirectWriteAttr(offs + (w - 1)*2 + (i - 1)*ScreenBytesX, ch, pwAttr);
          END;
        END;
      END;
    END;
  END;



PROCEDURE RectAttr(offs, w, h: WORD; a: BYTE);
  VAR
    i : WORD;
  BEGIN
    FOR i := 1 TO h DO
      PutAttrs(offs + (i - 1)*ScreenBytesX, w, a);
  END;



PROCEDURE RectAttrMask(offs, w, h: WORD; a, m: BYTE);
  VAR
    i : WORD;
  BEGIN
    FOR i := 1 TO h DO
      PutAttrsMask(offs + (i - 1)*ScreenBytesX, w, a, m);
  END;



PROCEDURE PutRotulo(offs: WORD; s: STRING; a: BYTE);
  VAR
    i : WORD;
    b : BYTE;
  BEGIN

    IF offs > ScrOffset THEN BEGIN
      b := ByteBox(GetAsciiInScr(offs-2));
      IF b <> 0 THEN DirectWrite(offs-2, BoxByte(b AND $D));
    END;

    IF offs + Length(s)*2 < ScreenBytes + ScrOffset - 1 THEN BEGIN
      b := ByteBox(GetAsciiInScr(offs+2*Length(s)));
      IF b <> 0 THEN DirectWrite(offs+2*Length(s), BoxByte(b AND 7));
    END;

    IF offs >= ScrOffset + ScreenBytesX THEN
      FOR i := 1 TO Length(s) DO BEGIN
        b := ByteBox(GetAsciiInScr(offs + (i - 1)*2 - ScreenBytesX));
        IF b <> 0 THEN DirectWrite(offs + (i - 1)*2 - ScreenBytesX, BoxByte(b AND $B));
      END;

    IF offs < ScreenBytes - ScreenBytesX THEN
      FOR i := 1 TO Length(s) DO BEGIN
        b := ByteBox(GetAsciiInScr(offs + (i - 1)*2 + ScreenBytesX));
        IF b <> 0 THEN DirectWrite(offs + (i - 1)*2 + ScreenBytesX, BoxByte(b AND $E));
      END;

    DirectWriteAttr(offs, s, a);

  END;




FUNCTION SaveWindow(VAR p: PAoW; x, y, w, h: WORD) : BOOLEAN;
  VAR
    i, j,
    beg  : WORD;
  BEGIN
    SaveWindow := TRUE;

    IF p = NIL THEN
      FullHeap.HGetMem(POINTER(p), w*h*2 + 2*3)
    ELSE IF (p^[1] * p^[2]) <> (w * h) THEN BEGIN
      SaveWindow := FALSE;
      EXIT;
    END;

    beg := y * ScreenBytesX + x*2;
    p^[0] := beg;
    p^[1] := w;
    p^[2] := h;
    FOR i := 0 TO h-1 DO
      FOR j := 0 TO w-1 DO
        p^[3 + i*w + j] := MEMW[ScrSegment:ScrOffset+(beg + i*ScreenBytesX + j*2)];
  END;


PROCEDURE StoreWindow(p: PAoW; x, y, w, h: WORD);
  VAR
    i, j,
    beg  : WORD;
  BEGIN
    beg := y * ScreenBytesX + x*2;
    p^[0] := beg;
    p^[1] := w;
    p^[2] := h;
    FOR i := 0 TO h-1 DO
      FOR j := 0 TO w-1 DO
        p^[3 + i*w + j] := MEMW[ScrSegment:ScrOffset+(beg + i*ScreenBytesX + j*2)];
  END;


PROCEDURE RestoreWindow(p: PAoW);
  VAR
    i, j : WORD;
  BEGIN
    FOR i := 0 TO p^[2]-1 DO
      FOR j := 0 TO p^[1]-1 DO
        MEMW[ScrSegment:ScrOffset+(p^[0] + i*ScreenBytesX + j*2)] := p^[3 + i*p^[1] + j];
  END;


PROCEDURE DoneWindow(p: PAoW);
  BEGIN
    FullHeap.HFreeMem(POINTER(p), p^[1]*p^[2]*2 + 2*3);
  END;


FUNCTION SavedWindowSize(p: PAoW) : WORD;
  BEGIN
    SavedWindowSize := p^[1]*p^[2]*2 + 2*3;
  END;




END.
