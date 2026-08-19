{****************************************************************************}
{                                                                            }
{ MODULE:         CmdLine                                                    }
{                                                                            }
{ DESCRIPTION:    This module implements a workframe for a command line      }
{                 options interpreter. You just have to make a desdendant    }
{                 object overriding the InterpretNoSwitch and                }
{                 InterpretSwitch methods.                                   }
{                                                                            }
{                 Also, the GetDOSCmdLine function is provided. It returns   }
{                 the command line written from the DOS prompt.              }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        14-Mar-1993 Design and implementation.                     }
{                                                                            }
{ (C) 1993 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT CmdLine;

INTERFACE

USES Dos, Objects;




TYPE
  TSwitch = STRING[4];

  PCmdLine = ^TCmdLine;
  TCmdLine = STRING[127];

  PCmdLineInterpreter = ^TCmdLineInterpreter;
  TCmdLineInterpreter =
    OBJECT(TObject)
      Line     : STRING;
      FileDir  : DirStr;
      Idx      : WORD;
      Aborting : BOOLEAN;

      PROCEDURE ParseLine (s: STRING);                                       VIRTUAL;
      PROCEDURE ParseFile (FName: PathStr);                                  VIRTUAL;
      FUNCTION  GetToken                                         : TCmdLine; VIRTUAL;
      FUNCTION  CmpSwitch (VAR Token: TCmdLine; Switch: TSwitch) : BOOLEAN;  VIRTUAL;
      FUNCTION  TokenParam(VAR Token: TCmdLine)                  : TCmdLine; VIRTUAL;
      PROCEDURE Abort;                                                       VIRTUAL;

      PROCEDURE InterpretNoSwitch(Token: TCmdLine); VIRTUAL;
      PROCEDURE InterpretSwitch  (Token: TCmdLine); VIRTUAL;
    END;




FUNCTION GetDOSCmdLine : TCmdLine;




IMPLEMENTATION




PROCEDURE TCmdLineInterpreter.ParseLine(s: STRING);
  VAR
    Token    : TCmdLine;
    SaveLine : STRING;
    SaveIdx  : WORD;
    i        : WORD;
  BEGIN
    i := Pos(';', s);
    IF i > 0 THEN
      s := Copy(s, 1, i-1);

    Line     := s;
    Idx      := 1;
    Aborting := FALSE;

    Token := GetToken;
    IF Token = '' THEN
      Token := GetToken;

    WHILE Token <> '' DO
      BEGIN
        IF Aborting THEN EXIT;

        IF      (Token[1] = '/') OR
                (Token[1] = '-') THEN
          InterpretSwitch(Copy(Token, 2, 255))
        ELSE IF (Token[1] = '@') THEN
          BEGIN
            SaveLine := Line;
            SaveIdx  := Idx;

            ParseFile(Copy(Token, 2, 255));

            Line := SaveLine;
            Idx  := SaveIdx;
          END
        ELSE
          InterpretNoSwitch(Token);

        Token := GetToken;
      END;
  END;


PROCEDURE TCmdLineInterpreter.ParseFile(FName: PathStr);
  VAR
    f    : TEXT;
    Name : NameStr;
    Ext  : ExtStr;
  BEGIN
    Aborting := FALSE;

    FSplit(FExpand(FName), FileDir, Name, Ext);

    Assign(f, FName);
    Reset(f);
    IF IOResult <> 0 THEN EXIT;

    WHILE NOT EoF(f) DO
      BEGIN
        IF Aborting THEN EXIT;

        ReadLn(f, Line);
        IF IOResult <> 0 THEN
          BEGIN
            Close(f);
            IF IOResult <> 0 THEN;
            EXIT;
          END;
        ParseLine(Line);
      END;

    Close(f);
    IF IOResult <> 0 THEN;
  END;


FUNCTION TCmdLineInterpreter.GetToken : TCmdLine;
  CONST
    Spaces = [#0, #9, ' ', ','];
  VAR
    i : WORD;
  BEGIN
    GetToken[0] := #0;
    FOR i := Idx TO Length(Line) DO
      BEGIN
        IF Line[i] IN Spaces THEN
          BEGIN
            WHILE (i <= Length(Line)) AND (Line[i] IN Spaces) DO
              INC(i);

            Idx := i;
            EXIT;
          END;

        GetToken[i - Idx + 1] := Line[i];
        GetToken[0]           := CHAR(i - Idx + 1);
      END;
    Idx := 255;
  END;


FUNCTION TCmdLineInterpreter.CmpSwitch(VAR Token: TCmdLine; Switch: TSwitch) : BOOLEAN;
  VAR
    i : WORD;
  BEGIN
    CmpSwitch := FALSE;
    FOR i := 1 TO Length(Switch) DO
      IF UpCase(Switch[i]) <> UpCase(Token[i]) THEN
        EXIT;

    CmpSwitch := TRUE;
    Token     := Copy(Token, Length(Switch) + 1, 255);

    IF Token[1] = ':' THEN
      Token   := Copy(Token, 2, 255);
  END;


FUNCTION TCmdLineInterpreter.TokenParam(VAR Token: TCmdLine) : TCmdLine;
  BEGIN
    IF Token = '' THEN
      Token := GetToken;

    TokenParam := Token;
  END;


PROCEDURE TCmdLineInterpreter.Abort;
  BEGIN
    Aborting := TRUE;
  END;


PROCEDURE TCmdLineInterpreter.InterpretNoSwitch(Token: TCmdLine);
  BEGIN
  END;


PROCEDURE TCmdLineInterpreter.InterpretSwitch(Token: TCmdLine);
  BEGIN
  END;




FUNCTION GetDOSCmdLine : TCmdLine;
  BEGIN
    GetDOSCmdLine := PCmdLine(Ptr(PrefixSeg, $80))^;
  END;




END.
