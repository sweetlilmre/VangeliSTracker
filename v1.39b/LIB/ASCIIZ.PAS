{****************************************************************************}
{                                                                            }
{ MODULE:         AsciiZ                                                     }
{                                                                            }
{ DESCRIPTION:    Provides a conversion function   AsciiZ -> string.         }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-).                                           }
{                                                                            }
{ HISTORY:        01-Oct-1992 First documentation.                           }
{                 17-Oct-1992 Documentation finished.                        }
{                                                                            }
{ (C) 1992 VangeliSTeam                                                      }
{____________________________________________________________________________}

UNIT AsciiZ;

INTERFACE




FUNCTION StrAsciiZ(VAR s; l: WORD) : STRING; { Converts the AsciiZ string 's' to a }
                                             { TP string with a maximum length.    }




IMPLEMENTATION




FUNCTION StrAsciiZ(VAR s; l: WORD) : STRING;
  VAR
    z : ARRAY[0..65520] OF CHAR ABSOLUTE s;
    i : WORD;
  BEGIN
    i := 0;

    IF z[0] <> #0 THEN
      REPEAT
        StrAsciiZ[i+1] := z[i];
        INC(i);
      UNTIL (i > l) OR (z[i] = #0);

    IF i > l THEN DEC(i);

    StrAsciiZ[0] := CHR(l);

    IF i < l THEN
      FOR i := i+1 TO l DO
        StrAsciiZ[i] := ' ';
  END;




END.
