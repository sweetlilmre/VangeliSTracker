{****************************************************************************}
{                                                                            }
{ MODULE:         HexConversions                                             }
{                                                                            }
{ DESCRIPTION:    Implements data conversion functions number -> string.     }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-).                                           }
{                                                                            }
{ HISTORY:        01-Oct-1992 First documentation.                           }
{                 17-Oct-1992 Documentation finished.                        }
{                 24-Nov-1993 Added longint support.                         }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT HexConversions;

INTERFACE

TYPE
  THexPString = STRING[9]; { Hex POINTER string. }
  THexLString = STRING[8]; { Hex LONG    string. }
  THexWString = STRING[4]; { Hex WORD    string. }
  THexBString = STRING[2]; { Hex BYTE    string. }
  THexNString = CHAR;      { Hex nibble  string. }




FUNCTION HexPtr  (p: POINTER) : THexPString; { Converts POINTER to hexadecimal. }
FUNCTION HexLong (l: LONGINT) : THexLString; { Converts WORD    to hexadecimal. }
FUNCTION HexWord (w: WORD)    : THexWString; { Converts WORD    to hexadecimal. }
FUNCTION HexByte (b: BYTE)    : THexBString; { Converts BYTE    to hexadecimal. }
FUNCTION HexDigit(d: BYTE)    : THexNString; { Converts nibble  to hexadecimal. }




IMPLEMENTATION




{----------------------------------------------------------------------------}
{ Hex conversion routines.                                                   }
{____________________________________________________________________________}

CONST
  HexTabla : STRING[16] = '0123456789ABCDEF'; { Hex chars table. }


FUNCTION HexPtr(p: POINTER) : THexPString;
  BEGIN
    HexPtr := HexWord(SEG(p^)) + ':' + HexWord(OFS(p^));
  END;


FUNCTION HexLong(l: LONGINT) : THexLString;
  BEGIN
    HexLong := HexWord(SEG(POINTER(l)^)) + HexWord(OFS(POINTER(l)^));
  END;


FUNCTION HexWord(w: WORD) : THexWString;
  BEGIN
    HexWord[0] := #4;
    HexWord[1] := HexTabla[ (w SHR 12)         + 1];
    HexWord[2] := HexTabla[((w SHR  8) AND $F) + 1];
    HexWord[3] := HexTabla[((w SHR  4) AND $F) + 1];
    HexWord[4] := HexTabla[( w         AND $F) + 1];
  END;


FUNCTION HexByte(b: BYTE) : THexBString;
  BEGIN
    HexByte[0] := #2;
    HexByte[1] := HexTabla[((b SHR  4) AND $F) + 1];
    HexByte[2] := HexTabla[( b         AND $F) + 1];
  END;


FUNCTION HexDigit(d: BYTE) : THexNString;
  BEGIN
    HexDigit := HexTabla[(d AND $F) + 1];
  END;




END.
