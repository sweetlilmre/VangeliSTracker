UNIT ExeLoader;

INTERFACE

USES Objects, SongUnit;




PROCEDURE LoadExeFileFormat(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);




IMPLEMENTATION

USES SongElements, SongUtils, S3mLoader, Heaps, AsciiZ;




TYPE
  TExeFileMagic = ARRAY[0..1] OF CHAR;

  TFCDir =
    RECORD
      Name : ARRAY[1..16] OF CHAR;
      Pos  : LONGINT;
      Size : LONGINT;
    END;

CONST
  ExeMagic : TExeFileMagic = ( 'M', 'Z' );

  ThereIsMore : BOOLEAN = FALSE;

VAR
  LastIndex : WORD;





PROCEDURE LoadExeFileFormat(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);
  CONST
    MaxDir = 100;
  VAR
    Dir   : ARRAY[1..MaxDir] OF TFCDir;
    Magic : TExeFileMagic ABSOLUTE Header;
    DirPos, l,
    NumEntrys : LONGINT;
    s         : STRING[12];
    i, j, siz : WORD;
    NumDir    : WORD;
  LABEL
    Error;
  BEGIN
    IF (Magic <> ExeMagic) OR (St.GetPos <> 0) THEN
      BEGIN
Error:
        ThereIsMore := FALSE;
        Song.Status := msNotLoaded;
        EXIT;
      END;

    St.Seek(St.GetSize - 4);
    St.Read(DirPos, 4);

    IF (DirPos > St.GetSize) OR (DirPos <= 0) THEN GOTO Error;

    St.Seek(DirPos);
    St.Read(l, 4);
    IF l <> 13119424 THEN GOTO Error;

    St.Read(NumEntrys, 4);
    St.Read(l, 4);

    IF Song.InsidePath <> NIL THEN
      FOR i := 1 TO Length(Song.InsidePath^) DO
        Song.InsidePath^[i] := UpCase(Song.InsidePath^[i]);

    DirPos := St.GetPos;

    FOR j := 0 TO (NumEntrys + MaxDir - 1) DIV MaxDir - 1 DO
      BEGIN

        NumDir := MaxDir;
        IF j*MaxDir + NumDir > NumEntrys THEN
          NumDir := NumEntrys MOD MaxDir;

        St.Seek(DirPos);
        St.Read(Dir, NumDir*24);
        DirPos := St.GetPos;

        IF ThereIsMore THEN i := LastIndex + 1
                       ELSE i := 1;

        IF i <= j*MaxDir THEN i := j*MaxDir;

        IF i < NumDir + j*MaxDir THEN
          FOR i := i - j*MaxDir TO NumDir DO
            BEGIN
              Song.Status := msNotLoaded;
              s           := StrAsciiZ(Dir[i].Name, 12);
              WHILE s[Length(s)] = ' ' DO
                DEC(s[0]);

              IF (Song.InsidePath  = NIL) OR
                 (Song.InsidePath^ = '')  OR
                 (Song.InsidePath^ = s)   THEN
                BEGIN
                  St.Seek(Dir[i].Pos);
                  St.Read(Header, SizeOf(Header));
                  St.Seek(Dir[i].Pos);

                  LoadS3mFileFormat(Song, St, Header);

                  St.Seek(0);
                  St.Read(Header, SizeOf(Header));
                  St.Seek(0);

                  IF (Song.Status <> msNotLoaded)    AND
                     (Song.Status <= msFileTooShort) THEN
                    BEGIN
                      Song.SetInsidePath(s);

                      Song.ThereIsMore := TRUE;
                      ThereIsMore      := TRUE;
                      LastIndex        := j*MaxDir + i;
                      EXIT;
                    END;
                END;
            END;
      END;

    ThereIsMore := FALSE;
  END;



END.
