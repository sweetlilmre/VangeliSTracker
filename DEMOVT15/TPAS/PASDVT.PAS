{
  PASDVT.TPU - TP(6.0) unit for interfacing to DEMOVT.EXE  //  ARM 12/93,4/94

  (based on original VTASM.INC by JCAB)

 - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
   Note: VTASM.INC nomenclature sounded a bit clumsy to me, so I decided
   not to follow it too closely O:-)

   The equivalence between VTASM.INC procedures and VTDEMO.TPU ones is
   as follows:

   VTDEMO.TPU          VTASM.INC
   ==========          =========
    VT_Init            InitMusic
    VT_Poll            CallMusic
    VT_AutoOff         VTDisconnectTimer
    VT_AutoOn          VTConnectTimer
    VT_Timer           VTGetTickCounter
    VT_Start           VTBeginSync
    VT_SyncStart       VTBeginSync + VTWaitForStart
    VT_GoTo            VTJumpPos
    VT_GetSem          VTCheckSemaphore (*)
    VT_SetSem          VTSetSemaphore
    VT_Resync          VTMiddleSync
    VT_SetVolume       VTSetSoundVolume
    VT_GetVolume       VTGetSoundVolume

    VT_Delay           (no equivalent)


(*) vtasm.inc's VTCheckSemaphore compares semaphore bx with value al,
while vtdemo.tpu's VT_GetSem simply returns the value of the semaphore
and leaves any comparison up to you.

 - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

4/94 -- New functions:

    VT_QueryCh       -- returns TRUE if note played since last query.
    VT_ChStatus      -- returns channel's tone, instrument, and volume.

    VT_ChannelCount  -- returns number of channels
    VT_CurrentPos    -- returns current pattern/note
    VT_Abort         -- tells DVT to quit on exit

}

UNIT PASDVT;

Interface

{ ==============================================================

                      T H E   P R O C ' S                                       }

  function  VT_Init : boolean;                { detect and initialize DEMOVT    }
  procedure VT_Poll;                          { ò 50Hz DEMOVT manual polling    }
  procedure VT_AutoOff;                       { switch to manual polling        }
  procedure VT_AutoOn;                        { switch to auto (IRQ0) polling   }
  function  VT_Timer : longint;               { get music timer count (50Hz)    }
  procedure VT_Start;                         { setup to start playing          }
  procedure VT_SyncStart;    { Like start, but then waits 1/2 sec till music sounds }
  procedure VT_GoTo( pattern, note : byte );  { jump to given pattern/note within score }
  function  VT_GetSem( sem : byte ) : byte;   { get semaphore "sem" value       }
  procedure VT_SetSem( sem, va : byte );      { set semaphore "sem" to "va"     }
  procedure VT_Resync( sem, pattern, note : byte ); { wait for sync point       }
  procedure VT_SetVolume( level : byte );     { set volume level                }
  function  VT_GetVolume : byte;              { get volume level                }

  procedure VT_Delay( h : word );             { delay h hundredths of a second  }
                                              {  while still updating music     }

  function VT_QueryCh( ChanNo : byte ) : boolean;  { TRUE if new note     }
  procedure VT_ChStatus( ChanNo : byte; var per : word; var inst, volu : byte);
  function VT_ChannelCount : byte;                 { get # of channels    }
  procedure VT_CurrentPos( var pat, note : byte ); { current pattern/note }
  procedure VT_Abort;

{ ==============================================================

     ...AND THINGS FOR ALL YOU SHOW-OFF DO-IT-YOURSELF TYPES  ;->
                                                                        }
Type
  TChanData =
    RECORD
      Period  : WORD;
      Ins     : BYTE;
      Vol     : BYTE;
    END;
  TChansData = ARRAY[1..32] OF TChanData;
  TChansTrig = ARRAY[1..32] OF BOOLEAN;

TYPE
  TVTRunInfo =
    RECORD

      { Out }

      Semaphores     : ARRAY[0..255] OF BYTE;
      ChansTrig      : TChansTrig;

      NumChannels    : BYTE;

      CtrlEntryPoint : POINTER;

      TickCounter    : LONGINT;

      RegEntryPoint  : POINTER;

      ChansData      : TChansData;

      Pos            : BYTE;
      Seq            : BYTE;

      fill2          : ARRAY[1..81] OF BYTE;

      { In }

      fill3       : ARRAY[1..3] OF BYTE;

      JumpNewPos  : BOOLEAN;
      JumpPosSeq  : BYTE;
      JumpPosNote : BYTE;

      Volume      : BYTE;

      Abort       : BOOLEAN;

      fill4       : ARRAY[1..248] OF BYTE;

    END;

  VT_PInfo = ^TVTRunInfo;
  VT_RInfo =  TVTRunInfo;

  VTIdString = ARRAY [0..255] OF BYTE;

var
  VT_Info    : VT_PInfo;    { points to VT_RInfo record within DEMOVT }
  AppIDFound : ^VTIdString; { dunno, ask JCAB... ;-) }



Implementation

const
  VTOK : boolean = False;  { = True if DEMOVT installed and initialized }

var
  VTControl : procedure ( command : word );

                           { VTInfo^.VTCtrlEntry for quick access }
                           { (hope DEMOVT never changes it!) }


procedure CLI; inline( $fa );
procedure STI; inline( $fb );

{ // VT_init }

function VT_Init : boolean; assembler;
Const
  MagicAX    = $5654;  {'VT'}
  MagicBX    = $5472;  {'Tr'}
  MagicCX    = $6163;  {'ac'}
  MagicXorBX = $6B65;  {'ke'}
  MagicXorCX = $7220;  {'r '}
asm
  mov ax, MagicAX
  mov bx, MagicBX
  mov cx, MagicCX
  xor di,di
  mov es, di
  int 2fh
  xor dl,dl
  and ax,ax
  jnz @no
  cmp bx, MagicBX xor MagicXorBX
  jne @no
  cmp cx, MagicCX xor MagicXorCX
  jne @no

  inc dl                   { DEMOVT detected! }
  mov [word ptr AppIdFound+2], es
  mov [word ptr AppIdFound  ], di   { save this... but for what ? }

  les di, [es:di-4]
  mov [word ptr VT_Info+2], es
  mov [word ptr VT_Info], di

  les di, [es:di+256+33]  { read VTCtrlEntry vector }
  mov [word ptr VTControl+2], es
  mov [word ptr VTControl],   di   { ...and copy it to VTControl }

@no:
  xor ah, ah
  mov al, dl
  mov [VTOK], al
end;


{ // VT_Poll }

procedure VT_Poll;
begin
  if VTOK then VTControl( 2 );
end;


{ // VT_AutoOff }

procedure VT_AutoOff;
begin
  if VTOK then VTControl( 1 );
end;


{ // VT_AutoOn }

procedure VT_AutoOn;
begin
  if VTOK then VTControl( 0 );
end;


{ // VT_Timer }

function  VT_Timer : longint;
begin
  if VTOK then begin
    CLI;
    VT_Timer := VT_Info^.TickCounter;
    STI;
  end else
    VT_Timer := 0;
end;


{ // VT_Start }

procedure VT_Start;
begin
  if VTOK then VTControl( 3 );
end;


{ // VT_SyncStart }

procedure VT_SyncStart;
begin
  if VTOK then begin
    VTControl( 3 );
    CLI;
    VT_Info^.TickCounter := 0;
    STI;
    repeat  VT_Poll  until  VT_Timer >= 25;   { 25/50ths = 1/2 second }
    VT_Info^.TickCounter := 0;
  end;
end;


{ // VT_GoTo }

procedure VT_GoTo( pattern, note : byte );
begin
  if VTOK then with VT_Info^ do begin
    JumpNewPos  := TRUE;
    JumpPosSeq  := pattern;
    JumpPosNote := note;
  end;
end;


{ // VT_GetSem }

function  VT_GetSem( sem : byte ) : byte;
begin
  if VTOK then
     VT_GetSem := VT_Info^.Semaphores[ sem ]
  else
     VT_GetSem := 0;
end;


{ // VT_SetSem }

procedure VT_SetSem( sem, va : byte );
begin
  if VTOK then VT_Info^.Semaphores[ sem ] := va;
end;


{ // VT_Sync }

procedure VT_Resync( sem, pattern, note : byte );
begin
  if VTOK then begin
    if VT_GetSem( sem ) = 0 then VT_Goto( pattern, note );
    inc( sem );
    repeat VT_Poll until VT_GetSem( sem ) <> 0;
  end;
end;


{ // VT_SetVolume }

procedure VT_SetVolume( level : byte );
begin
  if VTOK then VT_Info^.Volume := level;
end;


{ // VT_GetVolume }

function  VT_GetVolume : byte;
begin
  if VTOK then
    VT_GetVolume := VT_Info^.Volume
  else
    VT_GetVolume := 0;
end;


{ // VT_Delay }

procedure VT_Delay( h : word );
var l : longint;
begin
  if VTOK then begin
    l := VT_Timer + h shr 1;
    repeat VT_Poll until VT_Timer >= l;
  end;
end;


{ // VT_QueryCh }

function VT_QueryCh( ChanNo : byte ) : boolean;
begin
  VT_QueryCh := false;
  if VTOK then
  if VT_Info^.ChansTrig[ ChanNo ] then begin
     VT_QueryCh := true;
     VT_Info^.ChansTrig[ ChanNo ] := false;
  end;
end;


{ // VT_ChStatus }

procedure VT_ChStatus( ChanNo : byte; var per : word; var inst, volu : byte);
begin
  if VTOK then
    with VT_Info^.ChansData[ ChanNo ] do begin
      per  := period;
      inst := ins;
      volu := vol;
    end
  else begin
    per  := 0;
    inst := 0;
    volu := 0;
  end;
end;


{ // VT_Channels }

function VT_ChannelCount : byte;
begin
  if VTOK then
    VT_ChannelCount := VT_Info^.NumChannels
  else
    VT_ChannelCount := 0;
end;


{ // VT_CurrentPos }

procedure VT_CurrentPos( var pat, note : byte );
begin
  if VTOK then
    with VT_Info^ do begin
      pat  := seq;
      note := pos;
    end
  else begin
    pat  := 0;
    note := 0;
  end;
end;


{ // VT_Abort }

procedure VT_Abort;
begin
  if VTOK then VT_Info^.Abort := true;
end;


END.

