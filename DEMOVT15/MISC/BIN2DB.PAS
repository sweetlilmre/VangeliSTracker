
CONST
   DataType: STRING = 'DB';
   DataLen          = 1;

VAR
   fo : TEXT;
   fi : FILE;

   nfi: STRING;
   i, j, k  : INTEGER;



CONST
   bc : INTEGER = 0;
PROCEDURE DoNum(b: WORD);

BEGIN
   IF bc = 0 THEN BEGIN
      WriteLn(fo);
      Write(fo, ' ',DataType, ' ', b: DataLen);
   END ELSE
      Write(fo, ',', b : DataLen);
   bc := (bc + 1) MOD 20;
END;




VAR
   buf : ARRAY [1..1024] OF BYTE;
   rez : INTEGER;

BEGIN
   IF ParamCount <> 2 THEN BEGIN
      WriteLn('Binary file to ASM/TP BASM source converter bye Iguana.');
      WriteLn('   Usage: BIN2DB <infile> <outfile>');
      HALT
   END;
   nfi := ParamStr(1);
   Assign(fo, ParamStr(2));
   ReWrite(fo);
   WriteLn(fo, '; (*----- File created with BIN2DB from file ', nfi, '. -----*)');

   Assign(fi, nfi);
   Reset(fi,1);
   REPEAT
      BlockRead(fi, buf, Sizeof(buf), rez);
      IF rez <> 0 THEN FOR i := 1 TO rez DO
         DoNum(buf[i]);
   UNTIL rez = 0;
   Close(fi);
   WriteLn(fo);
   Close(fo)
END.


