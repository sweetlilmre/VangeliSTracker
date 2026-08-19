UNIT VTSpecial;

INTERFACE

CONST
  MagicAX    = $5654;  {'VT'}
  MagicBX    = $5472;  {'Tr'}
  MagicCX    = $6163;  {'ac'}
  MagicXorBx = $6B65;  {'ke'}
  MagicXorCX = $7220;  {'r '}




PROCEDURE VTResidentCheck(MyAppID: STRING);




IMPLEMENTATION

TYPE
  PString = ^STRING;



{ ------ }

PROCEDURE CSOldInt2F; ASSEMBLER;
  ASM
        JMP FAR PTR CSOldInt2F;
  END;

TYPE
  PCSOldInt = ^TCSOldInt;
  TCSOldInt = RECORD
    JMP : BYTE;
    Int : POINTER;
  END;

VAR
  _CSOldInt2F : PCSOldInt;
  Int2fVector : POINTER ABSOLUTE 0:$2F*4;

{ ------ }

VAR
  AppID : STRING;

PROCEDURE MyInt2F; ASSEMBLER;
  ASM

                STI
                CMP     AX,MagicAX
                JNZ     @@Fin
                CMP     BX,MagicBX
                JNZ     @@Fin
                CMP     CX,MagicCX
                JNZ     @@Fin
                XOR     AX,AX
                XOR     BX,MagicXorBX
                XOR     CX,MagicXorCX
                MOV     DI,SEG(AppID)
                MOV     ES,DI
                MOV     DI,OFFSET AppID
                IRET
@@Fin:
                JMP     CSOldInt2F

  END;

{ ------ }

VAR
  OldExitProc : POINTER;

PROCEDURE MyExitProc; FAR;
  BEGIN
    ExitProc := OldExitProc;
    Int2FVector := _CSOldInt2F^.Int;
  END;

{ ------ }


PROCEDURE VTResidentCheck(MyAppID: STRING);
  CONST
    NoAppID : STRING[10] = '¨?¨?¨? :-(';
  VAR
    AlreadyInShell : BOOLEAN;
    AppIDFound     : PString;
  BEGIN

    ASM
                MOV     AX,MagicAX
                MOV     BX,MagicBX
                MOV     CX,MagicCX
                XOR     DI,DI
                MOV     ES,DI
                INT     $2F
                XOR     DL,DL
                AND     AX,AX
                JNZ     @@no
                CMP     BX,MagicBX XOR MagicXorBX
                JNZ     @@no
                CMP     CX,MagicCX XOR MagicXorCX
                JNZ     @@no
                INC     DL
@@no:           MOV     [AlreadyInShell],DL
                MOV     WORD PTR [AppIDFound+2],ES
                MOV     WORD PTR [AppIDFound],DI
    END;

    IF AppIDFound = NIL THEN
      AppIDFound := @NoAppID;

    IF AlreadyInShell THEN
      BEGIN
        WriteLn(#13#10'    ­­Ojo, que est  el '+AppIDFound^+' residente!!');
        HALT(1);
      END;

    AppID := MyAppID;

    _CSOldInt2F := @CSOldInt2F;

    _CSOldInt2F^.Int := Int2FVector;
    Int2FVector      := @MyInt2F;

    OldExitProc := ExitProc;
    ExitProc    := @MyExitProc;
  END;




END.
