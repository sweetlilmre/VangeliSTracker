PROGRAM ShellVT;

{$M 20000, 0, 655360}

USES Dos,
     VTSpecial, VTGlobal, VTCfg, VTCmd, 
     SoundDevices, {DevSB, DevSbDac, DevDAC, DevSpkr, DevAdlib, }DevGus,
     PlayMod, ModCommands, SongUnit, SongUtils,
     CmdLine, Heaps, Debugging, FileUtil;




VAR
  NoMods : BOOLEAN;

FUNCTION DoOneMOD(FName: PathStr; InsidePath: PathStr) : BOOLEAN; FAR;
  VAR
    Song     : TSong;
    HeapSize : LONGINT;
  BEGIN
    NoMods   := FALSE;
    DoOneMOD := TRUE;

    IF ShellLoopMod THEN
      BEGIN
        LoopMod      := TRUE;
        ForceLoopMod := TRUE;
      END;

    SetVTDevice;
    ActiveDevice^.Autodetect;
    SetVTFreq;
    MaxOutputFreq := DesiredHz;

    FillChar(UserVols, SIZEOF(UserVols), VtVolume);

    Song.Init;

    Song.SetInsidePath(InsidePath);

    IF VT1stPattern <> 0 THEN
      Song.SongStart := VT1stPattern;

    IF VTSongLen <> 0 THEN
      Song.SongLen := VTSongLen;

    StartSampling;

    Song.LoadFName(FName);

    IF Song.Status <= msFileTooShort THEN
      BEGIN
        DoOneMOD := FALSE;

        FirstPattern := VT1stPattern;
        RepStart     := VTRepStart;
        SongLen      := VTSongLen;

        PlayStart(Song);

        WriteLn('Type EXIT to uninstall ShellVT');

        HeapSize := Heap.HTotalAvail;
        ShrinkSystemHeap(0);
        SwapVectors;
        Exec(ShellPath, ShellParam);
        SwapVectors;
        ShrinkSystemHeap(HeapSize);

        PlayStop;
        EndSampling;

        WriteLn;
        WriteLn('ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿');
        WriteLn('³ ShellVT uninstalled. ³');
        WriteLn('ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ');
      END
    ELSE
      WriteLn(#13'Error en el fichero: '+FName);

    Song.Done;
  END;




CONST
  NombreApp = 'ShellVT';

  AppID : STRING[Length(NombreApp) + 2 + Length(Version) + Length(BetaStr)] =
            NombreApp+' v'+Version+BetaStr;

VAR
  s       : STRING;
  i, r    : WORD;

BEGIN

  WriteLn;
  WriteLn(    '     ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿');
  WriteLn(    '     ³ '+NombreApp+'. Resident version of VangeliSTracker, v'+Version+' ³');
  WriteLn(    '     ³               (C) 1992-93  VangeliSTeam             ³');
  WriteLn(    '     ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ');
  WriteLn(    '                            '+BetaStr);

  IF ParamCount = 0 THEN
    BEGIN
      WriteLn(' ÚÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ¿');
      WriteLn(' ³ ShellVT  <file.MOD|.OKT|.S3M|.STM|.669| etc] [<options>] [@<file.VTO>] ³');
      WriteLn(' ÀÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÙ');
      WriteLn('');
      WriteLn('   For a list of options, run the VT program without parameters.');
      HALT(1);
    END;

  VTResidentCheck(AppID);

  Debugging.Debug := FALSE;

  InitHeapVariables;
  InitUmbHeap;

  Cmd.Init;
  SongColl.Init(1, 1);

  InitSoundDevices;
  InitModUnit;

  DesiredHz  := ShellHz;
  OneModProc := DoOneMod;

  NoMods := TRUE;

  Cmd.ParseLine(GetDOSCmdLine);
  IF DoSongColl(Cmd.FileDir) THEN
    IF NoMods THEN
      WriteLn('No encuentro ninguna canci¢n.');
END.
