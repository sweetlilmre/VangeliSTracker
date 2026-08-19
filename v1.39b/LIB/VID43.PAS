UNIT Vid43;

INTERFACE

USES Dos;




CONST
  ScreenSizeX  : WORD = 90;
  ScreenBytesX : WORD = 180;
  ScreenSizeY  : WORD = 63;
  ScreenBytes  : WORD = 180 * 63;
  ScreenWords  : WORD = 90 * 63;
  ScrSegment   : WORD = $B800;
  ScrOffset    : WORD = $0000;

  ForceEGA     : BOOLEAN = TRUE;

  InVideoMode43 : BOOLEAN = FALSE;

VAR
  BIOSScrSize   : WORD ABSOLUTE 0:$44C;
  BIOSScrOffset : WORD ABSOLUTE 0:$44E;




PROCEDURE InitVid43;
PROCEDURE PoneVideoMode43;
PROCEDURE QuitaVideoMode43;




IMPLEMENTATION

USES Debugging, FileUtil, BiosVideo, Heaps, SwapManager, HexConversions, Kbd;

TYPE
  TChar = ARRAY[0..7] OF BYTE;

CONST
  OldMode         : BYTE    = $FF;
  SaveBufferRec   : TVideoStateSaved = (Mode: 3; FontSize: 16; Buffer: NIL);
  SaveBufferSize  : WORD    = 0;
  SaveBufferNotValid : BOOLEAN = TRUE;

VAR
  ScrImageHandle  : TSwapHandle;


CONST
  DefPalette : ARRAY[1..17] OF BYTE = ($00, $01, $02, $03, $04, $05, $14, $07,
                                       $38, $39, $3A, $3B, $3C, $3D, $3E, $3F,
                                       $00);

  Palette : ARRAY[1..17] OF BYTE = {($00, $01, $3B, $03, $04, $3F, $14, $07,
                                     $38, $39, $3A, $3B, $3C, $3D, $3E, $3F,
                                     $00);}

                                   ($00, $01, $3A, $07, $24, $38, $3E, $3F,
                                    $00, $14, $3A, $07, $24, $38, $3E, $3F,
                                    $00);

  { Negro, Azul, Verde,      , Rojo,       , Amarillo, Blanco }
  {  0       1     2      3     4      5         6       7    }

  { 0 -> 0 }
  { 1 -> 3 }
  { 2 -> 7 }
  { 3 -> 4 }
  { 4 -> 2 }
  { 5 -> 1 }
  { 6 -> 5 }
  { 7 -> 6 }


{$L FONT.OBJ}
PROCEDURE Font8x8; EXTERNAL;

TYPE
  TFont = ARRAY[0..256*8-1] OF BYTE;
VAR
  PixFont8x8   : ARRAY[0..255] OF TChar;
  Font8x8Array : ^TFont;


CONST
  CRTCTable    : ARRAY[0..$18] OF BYTE =
    (
{
      $6A, $4F, $50, $82,
      $55, $81, $BF, $1F,
      $00, $4F, $00, $0F,
      $00, $00, $07, $80,
      $9C, $0E, $8F, $28,
      $1F, $96, $B9, $A3,
      $FF

      $5F, $4F, $50, $82,
      $55, $81, $BF, $1F,
      $00, $47, $07, $00,
      $0F, $A0, $0F, $A0,
      $9C, $0E, $8F, $28,
      $1F, $96, $B9, $A3,
      $FF
}
      $6A, $59, $5A, $8D,
      $5F, $89, $2F, $B2,
      $00, $67, $07, $00,
      $16, $26, $0F, $A0,
      $04, $0E, $F7, $2D,
      $1F, $00, $29, $A3,
      $FF


    );




PROCEDURE PoneVideoMode43;
  VAR
    i : WORD;
  BEGIN

    IF InVideoMode43 THEN EXIT;

    IF NOT SaveBufferNotValid THEN
      SaveVideoState(SaveBufferRec)
    ELSE
      OldMode := GetVideoMode;

    ScrImageHandle.Write(Ptr($B800, BIOSScrOffset)^, BIOSScrSize);

    SetVideoMode(3);

    SelectFont8x8(0);
    FOR i := 1 TO 7 DO
      SelectFontQuiet8x8(i);

    IF NOT Debug THEN
      BEGIN
        FillFont(0, #0, 256, 8, @Font8x8);
        FillFont(1, #0, 256, 8, @PixFont8x8);
        SelectFonts(0, 1);
      END;

    BlinkOff;

    NoCursor;
    FillVideoMemory(' ', $00);
    IF NOT Debug THEN
      SetPalette(@Palette);

    ScrOffset := ScreenBytes;

    InVideoMode43 := TRUE;

    IF NOT Debug THEN
      ASM
                MOV     DX,$3C4         { 8 dot characters. }
                MOV     AL,1
                OUT     DX,AL
                INC     DX
                IN      AL,DX
                OR      AL,1
                OUT     DX,AL

                MOV     DX,$3D4
                MOV     AL,$11
                OUT     DX,AL
                INC     DX
                IN      AL,DX
                AND     AL,$7F
                OUT     DX,AL
                DEC     DX

                MOV     SI,OFFSET CRTCTable + $18
                STD

                MOV     CX,$18
@@lp:           MOV     AL,CL
                OUT     DX,AL
                INC     DX
                LODSB
                OUT     DX,AL
                DEC     DX
                JCXZ    @@1
                DEC     CX
                JMP     @@lp
@@1:
                CLD

                MOV     DX,$3DA
@@l1:           IN      AL,DX
                AND     AL,8
                JNZ     @@l1

                MOV     DX,$3C0
                MOV     AL,$33
                OUT     DX,AL
                INC     DX
                IN      AL,DX

                MOV     AH,AL

                MOV     DX,$3DA         { VSync }
@@l2:           IN      AL,DX
                AND     AL,8
                JZ      @@l2


                MOV     DX,$3C0         { Pel panning. }
                MOV     AL,$33
                OUT     DX,AL
                MOV     AL,AH
                AND     AL,$F0
                OUT     DX,AL


                MOV     DX,$3CC         { Set clock and polarity. }
                IN      AL,DX
                MOV     DX,$3C2
                OR      AL,$C4
                OUT     DX,AL
      END;

    FillVideoMemory(' ', $07);

  END;


PROCEDURE QuitaVideoMode43;
  BEGIN
    IF NOT InVideoMode43 THEN EXIT;

    IF NOT SaveBufferNotValid THEN
      RestoreVideoState(SaveBufferRec)
    ELSE
      SetVideoMode(OldMode);

    ScrImageHandle.Read(Ptr($B800, BIOSScrOffset)^, BIOSScrSize);
    ScrImageHandle.Free;

    InVideoMode43 := FALSE;
  END;




VAR
  OldExitProc : POINTER;


PROCEDURE MyExitProc; FAR;
  BEGIN
{
    QuitaVideoMode43;
    ScrImageHandle.Done;
}
    ExitProc := OldExitProc;
  END;




PROCEDURE PokePixel(VAR Ch: TChar; w, i: BYTE);
  BEGIN

    CASE i OF
      1: BEGIN
           Ch[0] := Ch[0] OR w;
           Ch[1] := Ch[1] OR w;
           IF w <> $C0 THEN
             IF (Ch[3] AND (w SHL 2)) <> 0 THEN
               Ch[2] := Ch[2] OR (w SHL 1);
         END;
      2: BEGIN
           Ch[3] := Ch[3] OR w;
           Ch[4] := Ch[4] OR w;
           IF w <> $C0 THEN
             BEGIN
               IF (Ch[1] AND (w SHL 2)) <> 0 THEN
                 Ch[2] := Ch[2] OR (w SHL 1);
               IF (Ch[6] AND (w SHL 2)) <> 0 THEN
                 Ch[5] := Ch[5] OR (w SHL 1);
             END;
         END;
      3: BEGIN
           Ch[6] := Ch[6] OR w;
           Ch[7] := Ch[7] OR w;
           IF w <> $C0 THEN
             IF (Ch[4] AND (w SHL 2)) <> 0 THEN
               Ch[5] := Ch[5] OR (w SHL 1);
         END;
    END;

  END;




PROCEDURE InitVid43;
  VAR
    i, j, w: WORD;
  BEGIN
    OldExitProc := ExitProc;
    ExitProc    := @MyExitProc;

    FOR i := 0 TO 255 DO BEGIN
      FOR j := 0 TO 7 DO PixFont8x8[i][j] := 0;

      w := $C0;
      IF ( i SHR 6       ) > 0 THEN PokePixel(PixFont8x8[i], w,  i SHR 6);

      w := $30;
      IF ((i SHR 4) AND 3) > 0 THEN PokePixel(PixFont8x8[i], w, (i SHR 4) AND 3);

      w := $0C;
      IF ((i SHR 2) AND 3) > 0 THEN PokePixel(PixFont8x8[i], w, (i SHR 2) AND 3);

      w := $03;
      IF ( i        AND 3) > 0 THEN PokePixel(PixFont8x8[i], w,  i        AND 3);
    END;

    Font8x8Array := POINTER(@Font8x8);

    FOR i := 0 TO 256*8-1 DO
      Font8x8Array^[i] := Font8x8Array^[i] XOR $FF;

    ASM
                MOV     AX,$1C00
                MOV     CX,$07
                INT     $10
                SUB     AL,$1C
                MOV     [SaveBufferNotValid],AL

                MOV     [SaveBufferSize],BX
    END;

    IF NOT SaveBufferNotValid THEN
      FullHeap.HGetMem(SaveBufferRec.Buffer,  SaveBufferSize  * 64);

    ScrImageHandle.Init;
  END;




END.
