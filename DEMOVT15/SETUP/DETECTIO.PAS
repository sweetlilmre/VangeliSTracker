{$A+,B-,D+,E-,F-,G+,I-,L+,N-,O-,R-,S-,V-,X+}
UNIT Detections;

   (* Copyright by Jare/Iguana in 1993, but given to the public domain. *)
   (* Want more comments? Write'em!                                     *)

   (*   Several detections are performed here. I prefer giving the user *)
   (* a choice instead of plainly aborting the demo.                    *)

INTERFACE

FUNCTION IsVGA: BOOLEAN;

FUNCTION Is386: BOOLEAN;

FUNCTION IsProtMode: BOOLEAN;

FUNCTION HasMouse : BOOLEAN;

PROCEDURE CheckFilesOk;


   (* ========================================= *)

IMPLEMENTATION

USES Objects, Gfx;

FUNCTION IsVGA: BOOLEAN;
BEGIN
   ASM
        XOR     BX,BX
        MOV     AX,01A00h
        INT     10h
        MOV     AX,1
        CMP     BL,7
        JNC     @@ok
        CMP     BL,0Dh
        JNC     @@ok
         XOR     AX,AX
    @@ok:
   END
END;

{$L detecasm.obj }

FUNCTION Is386: BOOLEAN; EXTERNAL;
FUNCTION IsProtMode: BOOLEAN; EXTERNAL;
FUNCTION HasMouse : BOOLEAN; EXTERNAL;




FUNCTION GetFileSize(n: STRING) : LONGINT;
  VAR
    f : TDosStream;
  BEGIN
    GetFileSize := -1;
    f.Init(n, stOpenRead);
    IF f.Status <> stOk THEN EXIT;
    GetFileSize := f.GetSize;
    f.Done;
  END;

PROCEDURE CheckFilesOk;
  TYPE
     TFil = RECORD
        Name : STRING[80];
        Size : LONGINT
     END;

  CONST
     NFILES = 1;

     files : ARRAY [1..NFILES] OF TFil = (
        (Name:'DVT.NFO';Size:   3930)
     );

  VAR
     i : INTEGER;
     l : LONGINT;

  BEGIN
      (* Uncomment the following to perform file size checking. *)
    FOR i := 1 TO NFILES DO BEGIN
       l := GetFileSize(files[i].Name);
       IF (l < 0) THEN
          WriteLn('The file ', files[i].Name, ' is required for the demo, but I can''t see it.')
       ELSE IF (l <> files[i].Size) THEN
          WriteLn('The file ', files[i].Name, ' should be ', files[i].Size,
                  ' bytes, but is ', l, ' bytes.');
       IF (l < 0) OR (l <> files[i].Size) THEN BEGIN
          Write(' Do you still want to try the demo? (y/N)');
          IF UpCase(CHAR(GetKey)) <> 'Y' THEN BEGIN
             WriteLn;
             WriteLn('Get a clean copy of the demo from BlasterSound BBS, +34-58-293583.');
             HALT(1)
          END;
          WriteLn(#13'                                              ')
       END
    END;
    WriteLn
  END;

END.
