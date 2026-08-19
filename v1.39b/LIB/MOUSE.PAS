unit Mouse;
{$S-,R-}

interface



                                         { Ð    Î    Ò    Ó    Ô    Õ    Ö    ×    Ø  }
const  MouseUDGs  : array[0..8] of byte= ($d0, $ce, $d2, $d3, $d4, $d5, $d6, $d7, $d8);
var    MouseAttrs : array[0..8] of byte;


const  mouPointer   = 0;
       mouWaitClock = 1;


{ Si la llamada se realiza despu‚s de InitEvents, no estar  disponible Mouse }
procedure InitMouse;
procedure DoneMouse;
procedure MOUReset(full: boolean);

procedure SetMouse(On: boolean);  { Muestra el cursor texto/cursor grafico }
function  MouseAvail: Boolean;    { El rat¢n gr fico puede ser utilizado   }


procedure RepaintMouse;            { Repinta el raton, puede ser llamado desde el idle }
                                   {  sirve par corregir la pega de que TV nos borrar  }


procedure SelectMouseCursor(mouCur: word);


PROCEDURE ShowMouse; 
PROCEDURE HideMouse; 



implementation

var
  DEFCHAR : array[0..8] of byte absolute MouseUDGs;

  mousex,              { Coordenadas del cursor         }
  mousey   : word;     {   .. en baja resolucion        }
  mousepx,             {   .. en alta resolucion        }
  mousepy  : word;



                        { Datos sobre video   }
  vseg      : word;     { Segmento de video   }
  vofs      : word;     { Offset   de video   }
  mcols,
  mrows     : word;
  points    : word;
  b_points  : byte absolute $40:$85;

  maxx,
  maxy      : word;



                        { Sprites para el cursor        }
  savechars : array[0..2, 0..2] of word;
  chardefs  : array[0..32*9-1] of byte;
  chardefsL  : array[0..8*9 -1] of longint absolute chardefs;



const
  cur_height  = 16;

  SecondaryFontOfs = 32*256*2;


var  
  mousecursormask : array[0..cur_height-1] of longint;
  mousescreenmask : array[0..cur_height-1] of longint;

const
  cur_Pointer_fore  : array[0..cur_height-1] of longint= (
    $00000000,  { 0000000000000000 }
    $40000000,  { 0100000000000000 }
    $60000000,  { 0110000000000000 }
    $70000000,  { 0111000000000000 }
    $78000000,  { 0111100000000000 }
    $7c000000,  { 0111110000000000 }
    $7e000000,  { 0111111000000000 }
    $7f000000,  { 0111111100000000 }
    $7f800000,  { 0111111110000000 }
    $7f000000,  { 0111111100000000 }
    $7c000000,  { 0111110000000000 }
    $66000000,  { 0110011000000000 }
    $06000000,  { 0000011000000000 }
    $03000000,  { 0000001100000000 }
    $03000000,  { 0000001100000000 }
    $00000000   { 0000000000000000 }
  );

  cur_Pointer_back  : array[0..cur_height-1] of longint= (
    $3fffffff,  { 0011111111111111 }
    $1fffffff,  { 0001111111111111 }
    $0fffffff,  { 0000111111111111 }
    $07ffffff,  { 0000011111111111 }
    $03ffffff,  { 0000001111111111 }
    $01ffffff,  { 0000000111111111 }
    $00ffffff,  { 0000000011111111 }
    $007fffff,  { 0000000001111111 }
    $003fffff,  { 0000000000111111 }
    $007fffff,  { 0000000001111111 }
    $01ffffff,  { 0000000111111111 }
    $00ffffff,  { 0000000011111111 }
    $90ffffff,  { 1001000011111111 }
    $f87fffff,  { 1111100001111111 }
    $f87fffff,  { 1111100001111111 }
    $fcffffff   { 1111110011111111 }
  );

(*
  cur_WaitClock_fore : array[0..cur_height-1] of longint= (
    $00000000,  { 0..............0 }
    $3ffc0000,  { 0.111111111111.0 }
    $3ffc0000,  { 0.111111111111.0 }
    $14280000,  { 0..1.1....1.1..0 }
    $16680000,  { 00.1.11..11.1.00 }
    $17e80000,  { 00.1.111111.1.00 }
    $13c80000,  { 00.1..1111..1.00 }
    $11880000,  { 00.1...11...1.00 }
    $11880000,  { 00.1...11...1.00 }
    $12480000,  { 00.1..1..1..1.00 }
    $12480000,  { 00.1..1..1..1.00 }
    $14280000,  { 00.1.1....1.1.00 }
    $15a80000,  { 0..1.1.11.1.1..0 }
    $3ffc0000,  { 0.111111111111.0 }
    $3ffc0000,  { 0.111111111111.0 }
    $00000000   { 0.............00 }
  );

  cur_WaitClock_back : array[0..cur_height-1] of longint= (
    $8001ffff,  { 1..............1 }
    $8001ffff,  { 1.000000000000.1 }
    $8001ffff,  { 1.000000000000.1 }
    $8001ffff,  { 1..0.0....0.0..1 }
    $c003ffff,  { 11.0.00..00.0.11 }
    $c003ffff,  { 11.0.000000.0.11 }
    $c003ffff,  { 11.0..0000..0.11 }
    $c003ffff,  { 11.0...00...0.11 }
    $c003ffff,  { 11.0...00...0.11 }
    $c003ffff,  { 11.0..0..0..0.11 }
    $c003ffff,  { 11.0..0..0..0.11 }
    $c003ffff,  { 11.0.0....0.0.11 }
    $8001ffff,  { 1..0.0.00.0.0..1 }
    $8001ffff,  { 1.000000000000.1 }
    $8001ffff,  { 1.000000000000.1 }
    $8001ffff   { 1..............1 }
  );
*)


const
  prettymouseavail    : boolean= false;  { El gestor de raton esta inicializado }
  prettymousevisible  : boolean= false;  { El cursor grafico esta siendo usado  }


  mousefreeze  : word   = 0;     { Semaforo                  }
  saved        : boolean= false; { Hay fondo preservado?     }
  mousehidden  : word   = 0;     { Cuenta de hidden          }
  inhandler    : boolean= false;


                { Eventos de raton        }
  MOUSEMOVE      = 1;
  LEFTBPRESS     = 2;
  LEFTBRELEASE   = 4;
  RIGHTBPRESS    = 8;
  RIGHTBRELEASE  = 16;













{**********************************************************************
  INTERNA: pinta y salva la rejilla


             func== 0  -->  Restaura la pantalla
             func== 1  -->  Anota el contenido de la pantalla
             func== 2  -->  Pinta el cursor
**********************************************************************}
procedure plotegavgacursor(func: word);
var
  off      : word;
  width,
  height,
  i,
  j        : word;
  disp     : word;
  x,
  y        : word;
  p1       : pointer;
const
  lsavex   : integer= 0;
  lsavey   : integer= 0;
  savedcur : boolean= false;

begin
  case func of
    0: begin
         savedcur:= false;
         x:= lsavex;
         y:= lsavey;
       end;

    1: begin
         x:= mousex;
         y:= mousey;
       end;

    2: begin
         savedcur:= true;
         lsavex:= mousex; x:= mousex;
         lsavey:= mousey; y:= mousey;
       end;
  end;

  width:= mcols - x;
  if (width> 3) then width:= 3;
  height:= mrows - y;
  if (height> 3) then height:= 3;

  off:= y * (mcols * 2) + x * 2 + vofs;
  disp:= (mcols * 2) - width * 2;

  p1:= ptr(vseg, off);

  case func of
    0: asm
         push  ds
         push  es

         mov   bx, offset DEFCHAR
         les   di, p1
         mov   si, offset savechars
         mov   cx, height
         cld

@@l1:
         push  si
         push  bx
         push  cx
         mov   cx, width
@@l2:
         mov   al, ds:[bx]
         mov   ah, ds:[si+1]
         and   ah, 0F7h
         cmp   al, es:[di]
         jne   @@nx
         mov   dl, ds:[si]
         mov   es:[di], dl
@@nx:
         cmp   ah, es:[di+1]
         jne   @@nx1
         mov   dl, ds:[si+1]
         mov   es:[di+1], dl
@@nx1:
         inc   bx
         add   si, 2
         add   di, 2
         loop  @@l2
         pop   cx

         pop   bx
         pop   si
         add   si, 6
         add   bx, 3
         add   di, disp
         loop  @@l1


         pop   es
         pop   ds
       end;

    1: asm
         push  ds
         push  es

         mov   bx, offset savechars
         mov   si, offset DEFCHAR
         les   di, p1
         mov   cx, height
         cld
@@l1:
         push  si
         push  cx
         push  bx
         mov   cx, width
@@l2:
         lodsb
         inc   bx
         mov   ah,[bx]
         and   ah,0F7h
         stosw
         inc   bx
         loop  @@l2
         pop   bx
         add   bx, 6
         pop   cx

         pop   si
         add   si, 3
         add   di, disp
         loop  @@l1

         pop   es
         pop   ds
       end;

    2: asm
         push  ds
         push  es

         push  ds
         pop   es
         lds   si, p1
         mov   di, offset savechars
         mov   cx, height
         cld
@@l1:
         push  di
         push  cx
         mov   cx, width
@@l2:
         lodsw
         stosw
         loop  @@l2
         pop   cx

         pop   di
         add   di, 6
         add   si, disp
         loop  @@l1

         pop   es
         pop   ds
       end;
  end;
end;








{**********************************************************************
  INTERNA: calcula la rejilla, esta es la que de verdad pinta.
**********************************************************************}
procedure drawegavgacursor;
var
  off     : word;
  i,
  j       : word;
  s1,
  s2,
  s3      : word;
  defs    : ^longint;
  masks   : ^longint;
  shift   : word;
  addmask : longint;
  scan    : word;

begin
  plotegavgacursor(2);


  asm        { assembly time      }
    pushf            { disable interrupts    }
    cli
    mov   dx, 3c4h
    mov   ax, 0704h
    out   dx, ax

    mov   dx, 03ceh  { graf controller port    }
    mov   ax, 0204h  { map 2        }
    out   dx, ax
    mov   ax, 0005h  { disable odd-even adressing  }
    out   dx, ax
    mov   ax, 0406h  { map starts at A000:0000  }
    out   dx, ax
    popf
  end;

  off:= 0;      { copy the char definitions  }
  i:= 0;
  while i< 3 do begin
    s1:= LO(savechars[i][0])*32+((HI(savechars[i][0]) SHR 3) AND 1)*SecondaryFontOfs;
    s2:= LO(savechars[i][1])*32+((HI(savechars[i][1]) SHR 3) AND 1)*SecondaryFontOfs;
    s3:= LO(savechars[i][2])*32+((HI(savechars[i][2]) SHR 3) AND 1)*SecondaryFontOfs;
    for j:= 0 to points-1 do begin
      inc(off);
      chardefs[off]:= Mem[$a000:s3]; inc(off); inc(s3);
      chardefs[off]:= Mem[$a000:s2]; inc(off); inc(s2);
      chardefs[off]:= Mem[$a000:s1]; inc(off); inc(s1);
    end;
    inc(i);
  end;

  shift:= mousepx mod 8;    { Mask cursor      }
  scan:= mousepy mod points;
  asm
    push   ds
    pop    es
    lea    di, chardefsL
    add    di, scan
    add    di, scan
    add    di, scan
    add    di, scan
    lea    si, mousescreenmask
    lea    bx, mousecursormask
    mov    cx, cur_height
    cld

@@l1:
    push   cx

    lodsw
    xchg   ax, dx		{ ax= lo, dx= hi }
    lodsw
    xchg   ax, dx

    mov    cx, shift;
    jcxz   @@noshr1

@@l2:
    stc
    rcr    dx, 1
    rcr    ax, 1
    loop   @@l2

@@noshr1:
    and    word ptr [di], ax
    and    word ptr [di].2, dx

    xchg   bx, si
    lodsw
    xchg   ax, dx
    lodsw
    xchg   ax, dx

    mov    cx, shift
    jcxz   @@noshr2

@@l3:
    stc
    clc
    rcr    dx, 1
    rcr    ax, 1
    loop   @@l3

@@noshr2:
    or     word ptr [di], ax
    or     word ptr [di].2, dx

    xchg   bx, si
    add    di, 4

    pop    cx
    loop   @@l1
  end;

    

  asm        { copy the modified char set  }
    mov  dx, 03c4h
    mov  ax, 0402h
    out  dx, ax
  end;

  off:= 0;
  i:= 0;
  while i< 3 do begin
    s1:= DEFCHAR[3*i  ]*32;
    s2:= DEFCHAR[3*i+1]*32;
    s3:= DEFCHAR[3*i+2]*32;

    for j:= 0 to points-1 do begin
      inc(off);
      Mem[$a000:s3] := chardefs[off]; inc(off); inc(s3);
      Mem[$a000:s2] := chardefs[off]; inc(off); inc(s2);
      mem[$a000:s1] := chardefs[off]; inc(off); inc(s1);
    end;
    inc(i);
  end;


  asm        { put the sequencer = normal  }
    pushf            { disable interrupts    }
    cli
    mov   dx, 03c4h
    mov   ax, 0302h
    out   dx, ax
    mov   ax, 0304h
    out   dx, ax

    mov   dx, 03ceh  { program the controller  }
    mov   ax, 0004h
    out   dx, ax
    mov   ax, 1005h
    out   dx, ax
    sub   ax, ax
    mov   es, ax
    mov   ax, 0e06h
    mov   bl, 7
    cmp   es:[49h], bl
    jne   @@notmono
    mov   ax, 0806h
@@notmono:
    out   dx, ax
    popf
  end;

  plotegavgacursor(1);

end;



{**********************************************************************
  INTERNA: Rutina de atenci¢n al rat¢n;
**********************************************************************}
procedure old1c;  begin inline(0/0/0/0) end;
procedure old33;  begin inline(0/0/0/0) end;
procedure oldhandler;  begin inline(0/0/0/0) end;

procedure dummyhandler; far;
begin
end;

procedure mousehandler; far;
const
  evm  : word = 0;
  evx  : word = 0;
  evy  : word = 0;
  conditionmask  : word = 0;
  buttonstate    : word = 0;
begin
  asm
    push  ds

    push  ax
    xor   ax,ax
    mov   ds,ax
    inc   [word ptr ds:2]
    mov   ax, SEG @DATA
    mov   ds, ax
    pop   ax

    mov   conditionmask, ax
    mov   buttonstate, bx
  end;

  if (mousefreeze= 0) then begin
    asm
      mov   mousex, cx
      mov   mousey, dx
      mov   mousepx, cx
      mov   mousepy, dx
    end;

    inhandler:= true;

    if (prettymousevisible) then begin
      mousex:= mousex div 8;
      mousey:= mousey div points;

      if (conditionmask and MOUSEMOVE<> 0) then begin
        if (saved) then begin
          plotegavgacursor(0);
          saved:= false;
        end;


        if (mousehidden= 0) then begin
          drawegavgacursor;
          saved:= true;
        end;
      end;
    end else begin
      mousex:= mousex div 8;
      mousey:= mousey div 8;
    end;


    { Se intenta no enviar eventos repetido a Turbo Visi¢n      }
    { Como el cursor esta en alta resoluci¢n hay ocho eventos   }
    { horizontales y "b_points" verticales por cada evento TV   }
    if not((mousex= evx) and (mousey= evy) and (conditionmask and MOUSEMOVE<> 0)) then begin
      evx:= mousex;
      evy:= mousey;

      asm
        mov   ax, conditionmask
        mov   bx, buttonstate
        mov   cx, mousex
        shl   cx, 1
        shl   cx, 1
        shl   cx, 1
        mov   dx, mousey
        shl   dx, 1
        shl   dx, 1
        shl   dx, 1
        call  dword ptr cs:[oldhandler]
      end;
    end;

  end;

  inhandler:= false;
  
  asm
    pop   ds
  end;
end;






{**********************************************************************
  INTERNA: Reset mouse

             Full== true  --> se desconecta el gestor de eventos
                              (se utiliza cuando int 33h:ax=0)

             Full== false --> no se desconecta el gestor de eventos
                              (se utiliza cunado se cambia de modo
                               de video)

**********************************************************************}
procedure MOUReset(full: boolean);
var
  v         : byte;
  savevmode : byte;
  biosmode  : byte absolute $40:$49;

begin
  inc(mousefreeze);        { Semaforo                   }

  asm
    mov   ax, 0f00h
    int   10h
    mov   v, al
  end;

  if (v= 7) then
    vseg:= $0b000
  else begin
    vseg:= $0b800;
    v:= 3;
  end;

  vofs  := {0 } 90*63*2;
  mrows := {25} 63;
  mcols := {80} 90;
  points:= {16} 8;

  if (prettymousevisible) then begin
    savevmode:= biosmode;
    biosmode := 6;
    asm                         { Enga¤amos al driver de raton  }
      sub   ax, ax
      pushf
      call  dword ptr cs:[old33]
    end;
    biosmode:= savevmode;

    maxx:= mcols*8-1;
    maxy:= mrows*points-1;
  end else begin
    asm
      sub   ax, ax
      pushf
      call  dword ptr cs:[old33]
    end;

    maxx:= (mcols-1)*8;
    maxy:= (mrows-1)*8;
  end;  
      
  asm                           { Ajustamos el rango del raton  }
    mov   dx, maxx
    mov   ax, 7
    sub   cx, cx
    pushf
    call  dword ptr cs:[old33]

    mov   dx, maxy
    mov   ax, 8
    sub   cx, cx
    pushf
    call  dword ptr cs:[old33]

    mov   ax, cs                { Establecemos el gestor de eventos     }
    mov   es, ax
    mov   dx, offset mousehandler
    mov   cx, 0ffffh
    mov   ax, 12
    pushf
    call  dword ptr cs:[old33]
  end;

  mousex:= 0;
  mousey:= 0;
  mousepx:= 0;
  mousepy:= 0;

  asm                           { Colocamos el raton en el origen       }
    mov   cx, mousex
    mov   dx, mousey
    mov   ax, 4
    pushf
    call  dword ptr cs:[old33]
  end;


  if (full) then asm
    mov   ax, offset dummyhandler
    mov   word ptr cs:oldhandler, ax
    mov   ax, cs
    mov   word ptr cs:oldhandler+2, ax
  end;

  if (prettymousevisible) then begin
    if (saved) then drawegavgacursor;
  
    mousehidden:= 1;
    saved      := false;
  end;

  dec(mousefreeze);
end;








{**********************************************************************
  INTERNA: Hide mouse

             Esconde el raton

**********************************************************************}
procedure MOUHide;
begin
  inc(mousefreeze);     { Semaforo      }

  if(prettymousevisible) then begin
    inc(mousehidden);
    if(saved) then
      plotegavgacursor(0);
    saved:= false;

  end else asm
    mov   ax, 2
    pushf
    call  dword ptr cs:[old33]
  end;

  dec(mousefreeze);  
end;




{**********************************************************************
  INTERNA: Show mouse

             Muestra el raton

**********************************************************************}
procedure MOUShow;
begin
  inc(mousefreeze);     { Semaforo      }

  if (prettymousevisible) then begin
    if(mousehidden> 0) then
      dec(mousehidden)
    else begin
      dec(mousefreeze);
      exit;
    end;

    if(mousehidden> 0) then begin
      dec(mousefreeze);
      exit;
    end;

    drawegavgacursor;
    saved:= true;

  end else asm
    mov   ax, 0001
    pushf
    call  dword ptr cs:[old33]
  end;

  dec(mousefreeze);
end;





{**********************************************************************
  INTERNA: Int1c

             Gestor de la interrupcion 1c

**********************************************************************}
procedure int1c; interrupt;
label
  fin;
CONST
  Semaph : BOOLEAN = FALSE;
var
  off      : word;
  width,
  height,
  disp     : word;
  x,
  y        : word;
  p1       : pointer;
  repaint  : word;

begin
  asm
    STI
    pushf
    call     dword ptr cs:[old1c]
  end;  

  IF Semaph THEN EXIT;
  Semaph := TRUE;

  if not prettymousevisible then exit;
  
  if(mousefreeze<> 0) then goto fin;
  if(inhandler) then goto fin;

  plotegavgacursor(0);
  drawegavgacursor;

fin:
  Semaph := FALSE;
end;





{**********************************************************************
  INTERNA: Int33

             Gestor de la interrupcion 33h

**********************************************************************}
procedure int33; far; assembler;
asm
  push  ds
  push  ax
  mov   ax, seg @data
  mov   ds, ax
  pop   ax

{
        cmp     MouseEvents,0
        jz      @@bypass
}        

  or    ax, ax          { Discriminamos los servicios que vamos a usar  }
  je    @@doit
  cmp   ax, 1
  je    @@doit
  cmp   ax, 2
  je    @@doit
  cmp   ax, 3
  je    @@doit
  cmp   ax, 4
  je    @@doit
  cmp   ax, 7
  je    @@doit
  cmp   ax, 8
  je    @@doit
  cmp   ax, 0ch
  je    @@doit

@@bypass:
  pop   ds
  jmp   dword ptr cs:[old33]


@@doit:
  push  es              { Salvar los registros                          }
  push  ax
  push  bx
  push  cx
  push  dx
  push  si
  push  di
  push  bp

{
  push  ax

  mov   ax, seg @data
  mov   ds, ax

  pop   ax
}

  mov   bp, sp

  or    ax, ax
  je    @@reset
  cmp   ax, 1
  je    @@show
  cmp   ax, 2
  je    @@hide
  cmp   ax, 3
  je    @@getinfo
  cmp   ax, 4
  je    @@setpos
  cmp   ax, 7
  je    @@rangeX
  cmp   ax, 8
  je    @@rangeY
  jmp   @@defuser

@@show:
  call  MOUShow;
  jmp   @@out

@@hide:
  call  MOUHide;
  jmp   @@out

@@reset:
  xor   ax, ax
  pushf
  call  dword ptr cs:[old33]
  mov   ss:[bp].12, ax
  mov   ss:[bp].10, bx

  mov   ax, 1
  push  ax
  call  MOUReset

  jmp   @@out

@@getinfo:
  pushf
  call  dword ptr cs:[old33]
  mov   ss:[bp].10, bx
  and   cx, 0fff8h
  mov   ss:[bp].8,  cx
  mov   ax, dx
  shl   ax, 1
  shl   ax, 1
  shl   ax, 1
  mov   bx, points
  xor   dx, dx
  div   bx
  mov   ss:[bp].6, ax
  jmp   @@out

@@setpos:
  push  ax
  mov   ax, dx
  mov   bx, points
  mul   bx
  shr   ax, 1
  shr   ax, 1
  shr   ax, 1
  mov   dx, ax
  pop   ax

  pushf
  call  dword ptr cs:[old33]
  jmp   @@out

@@rangeX:
{
  mov   dx, maxx
  pushf
  call  dword ptr cs:[old33]
}  
  sub   ax, ax
  push  ax
  call  MOUReset
  
  jmp   @@out

@@rangeY:
{
  mov   dx, maxy
  pushf
  call  dword ptr cs:[old33]
}
  sub   ax, ax
  push  ax
  call  MOUReset

  jmp   @@out

@@defuser:
  push  es
  push  dx
  pop   word ptr cs:oldhandler
  pop   word ptr cs:oldhandler+2

  push  cs
  pop   es
  mov   dx, offset mousehandler
  pushf
  call  dword ptr cs:[old33]




@@out:
  pop   bp
  pop   di
  pop   si
  pop   dx
  pop   cx
  pop   bx
  pop   ax
  pop   es
  pop   ds
  retf  2
end;  




{**********************************************************************
  PUBLICA: Conexi¢n del rat¢n

             Inicializacion y terminacion del raton

**********************************************************************}
var
  SaveExit: POINTER;

procedure ExitMOU; far;
begin
  DoneMouse;
  ExitProc := SaveExit;
end;


procedure InitMouse;
begin
  if (prettymouseavail) then exit;

  prettymousevisible:= false;

{
  if not MouseAvail then Exit;
}

  asm
    sub   ax,ax;          { Mouse driver function 0 -- reset and detect }
    int   33h
    mov   prettymouseavail,AL;
  end;

  if not prettymouseavail then Exit;

  asm
    mov   ax, 3533h                     { driver de raton               }
    int   21h
    mov   word ptr cs:old33, bx
    mov   word ptr cs:old33+2, es

    mov   ax, 351ch			{ reloj 			}
    int   21h
    mov   word ptr cs:old1c, bx
    mov   word ptr cs:old1c+2, es

    push  ds

    mov   ax, 2533h
    mov   dx, offset int33
    push  cs
    pop   ds
    int   21h
    
    mov   ax, 251ch
    mov   dx, offset int1c
    int   21h

    pop   ds
  end;

  MOUReset(TRUE);

  SelectMouseCursor(mouPointer);
  
  SaveExit := ExitProc;
  ExitProc := @ExitMOU;
end;


procedure DoneMouse;
begin
  if (prettymouseavail) then asm
    push  ds
    mov   ax, word ptr cs:[old33].2
    mov   ds, ax
    mov   dx, word ptr cs:[old33]
    mov   ax, 2533h
    int   21h
    pop   ds
    
    push  ds
    mov   ax, word ptr cs:[old1c].2
    mov   ds, ax
    mov   dx, word ptr cs:[old1c]
    mov   ax, 251ch
    int   21h
    pop   ds
  end;

  MOUHide;

  prettymouseavail:= false;
end;


procedure SetMouse(On: boolean);
begin
  if not MouseAvail then Exit;

  InitMouse;               { Garantiza que el raton grafico esta inicializado }

  if prettymousevisible = On then Exit; { Optimiza el funcionamiento }

  MOUHide;                 { Esconde el rat¢n }
  prettymousevisible:= On; { Conmuta al tipo de rat¢n requerido }
  MOUReset(false);         { Reajusta los par metros del rat¢n }
  MOUShow;                 { Visualiza el rat¢n }
end;



function MouseAvail:boolean;
begin
  MouseAvail := TRUE;
  if prettymouseavail then Exit;

  MouseAvail := FALSE;
(*
  if DeskViewPresent or                  { DeskView no permite rat¢n grafico }
     (WindowsPresent=386) then Exit;     { Windows /3 no permite en ventana  }
  MouseAvail := TRUE;
*)
end;



procedure RepaintMouse;            { Repinta el raton, puede ser llamado desde el idle }
begin
end;  


procedure SelectMouseCursor(mouCur: word);
begin
  if(prettymouseavail) then begin
    inc(mousefreeze);
    MOUHide;
    case mouCur of
      mouPointer: begin
        move(cur_Pointer_fore, mousecursormask, cur_height*sizeof(longint));
        move(cur_Pointer_back, mousescreenmask, cur_height*sizeof(longint));
      end;
      mouWaitClock: begin
{
        move(cur_WaitClock_fore, mousecursormask, cur_height*sizeof(longint));
        move(cur_WaitClock_back, mousescreenmask, cur_height*sizeof(longint));
}
      end else begin
        move(cur_Pointer_fore, mousecursormask, cur_height*sizeof(longint));
        move(cur_Pointer_back, mousescreenmask, cur_height*sizeof(longint));
      end;
    end;
    MOUShow;
    dec(mousefreeze);
  end;
end;


PROCEDURE ShowMouse; ASSEMBLER;
  ASM
                MOV     AH,1
                INT     $33
  END;



PROCEDURE HideMouse; ASSEMBLER;
  ASM
                MOV     AH,2
                INT     $33
  END;



end.
