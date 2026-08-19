{****************************************************************************}
{                                                                            }
{ MODULE:         FileUtil                                                   }
{                                                                            }
{ DESCRIPTION:    Several file handling utilities. Enhancement of the Dos    }
{                 UNIT.                                                      }
{                                                                            }
{ AUTHOR:         Juan Carlos Ar‚valo                                        }
{                                                                            }
{ MODIFICATIONS:  Nobody (yet ;-)                                            }
{                                                                            }
{ HISTORY:        03-Nov-1992 Creation                                       }
{                 17-Jan-1993 SaveFile, LoadFile, MakePath.                  }
{                                                                            }
{ (C) 1992,93 VangeliSTeam                                                   }
{____________________________________________________________________________}

UNIT FileUtil;

{$I-}

INTERFACE

USES Dos;




PROCEDURE AddBar2Path  (VAR Path: PathStr);
PROCEDURE KillBar2Path (VAR Path: PathStr);

FUNCTION  FileExists (f: PathStr) : BOOLEAN;
PROCEDURE DeleteFiles(FName: PathStr);

PROCEDURE MakePath   (f: PathStr);

FUNCTION  SaveFile(FName: PathStr; VAR Buffer; Size: WORD) : WORD;
FUNCTION  LoadFile(FName: PathStr; VAR Buffer; Size: WORD) : WORD;




IMPLEMENTATION




PROCEDURE AddBar2Path  (VAR Path: PathStr);
  BEGIN

    CASE Path[Length(Path)] OF
      ':',
      '\',
      '/': ;
    ELSE
      Path[Length(Path)+1] := '\';
      INC(Path[0]);
    END;

  END;


PROCEDURE KillBar2Path (VAR Path: PathStr);
  BEGIN

    CASE Path[Length(Path)] OF
      '\',
      '/': IF NOT ((Length(Path) > 2) AND (Path[Length(Path)-1] = ':')) THEN
             DEC(Path[0]);
    END;

  END;




FUNCTION FileExists(f: PathStr) : BOOLEAN;
  VAR
    i   : WORD;
    Fil : FILE;
  BEGIN
    Assign(Fil, f);
    GetFAttr(Fil, i);
    FileExists := DosError = 0;
  END;


PROCEDURE DeleteFiles(FName: PathStr);
  VAR
    i    : WORD;
    f    : FILE;
    s    : SearchRec;
    Dir  : DirStr;
    Name : NameStr;
    Ext  : ExtStr;
  BEGIN

    FSplit(Fname, Dir, Name, Ext);

    FindFirst(FName, Archive, s);

    WHILE (DosError = 0) DO
      BEGIN
        Assign(f, Dir+s.Name);
        Erase(f);
        FindNext(s);
      END;

  END;




PROCEDURE MakePath(f: PathStr);
  CONST
    Dir  : DirStr  = '';
    Name : NameStr = '';
    Ext  : ExtStr  = '';
    i    : WORD    = 0;
  BEGIN

    KillBar2Path(f);

    f := FExpand(f);

    FSplit(f, Dir, Name, Ext);
    IF Name = '' THEN
      EXIT
    ELSE
      BEGIN
        KillBar2Path(Dir);
        MakePath(Dir);
        FSplit(f, Dir, Name, Ext);
        MkDir(f);
        i := IOResult;
      END;

  END;




FUNCTION SaveFile(FName: PathStr; VAR Buffer; Size: WORD) : WORD;
  VAR
    f : FILE;
    w : WORD;
  BEGIN
    w := 0;

    Assign(f, FName);
    Rewrite(f, 1);

    IF IOResult = 0 THEN
      BEGIN
        BlockWrite(f, Buffer, Size, w);
        Close(f);
      END;

    SaveFile := w;

    w := IOResult;
  END;


FUNCTION LoadFile(FName: PathStr; VAR Buffer; Size: WORD) : WORD;
  VAR
    f : FILE;
    w : WORD;
  BEGIN
    w := 0;

    Assign(f, FName);
    Reset(f, 1);

    IF IOResult = 0 THEN
      BEGIN
        BlockRead(f, Buffer, Size, w);
        Close(f);
      END;

    LoadFile := w;

    w := IOResult;
  END;




END.