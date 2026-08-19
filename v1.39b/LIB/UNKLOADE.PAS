UNIT UnkLoader;

INTERFACE

USES Objects,
     SongUnit;




PROCEDURE LoadJMFileFormat  (VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);




IMPLEMENTATION

TYPE
  TModJMIdString  = ARRAY[1..6] OF CHAR; { JMPlayer Id string (at the start of the file). }

CONST
  ModJMIdString  : TModJMIdString = ('J', 'M', 'P', 'L', 'A', 'Y');




PROCEDURE LoadJMFileFormat(VAR Song: TSong; VAR St: TStream; VAR Header: TSongHeader);
  VAR
    ModJM : TModJMIdString ABSOLUTE Header;
  BEGIN
    Song.FileFormat := mffJMPlayer;

    IF ModJM = ModJMIdString THEN
      Song.Status := msFileFormatNotSupported
    ELSE
      Song.Status := msNotLoaded;
  END;




END.