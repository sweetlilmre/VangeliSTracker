PROGRAM MakeStr;

USES Objects, StrConst, VTStrConst;


CONST
  EspHeader : STRING = 'VT LNG. Fichero de lenguajes del VangeliSTracker. Espa¤ol.'#$1A;
  EngHeader : STRING = 'VT LNG. VangeliSTracker language file. English.'#$1A;

VAR
  Stream : TDosStream;
  List   : TStrListMaker;

BEGIN

  List.Init(65520, 65520);

  LibAddSpanishMsg(List);
  VTAddSpanishMsg (List);

  Stream.Init('VT_Esp.Lng', stCreate);
  Stream.Write(EspHeader[1], Length(EspHeader));
  List.Store(Stream);
  Stream.Done;
  List.Done;



  List.Init(65520, 65520);

  LibAddEnglishMsg(List);
  VTAddEnglishMsg (List);

  Stream.Init('VT_Eng.Lng', stCreate);
  Stream.Write(EngHeader[1], Length(EngHeader));
  List.Store(Stream);
  Stream.Done;
  List.Done;

END.