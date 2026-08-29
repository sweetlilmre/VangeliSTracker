{ ===========================================================================
  DemoVT v1.31 (beta) -- (C) 1992-93 VangeliSTeam (JCAB).
  NOT Asphyxia code. See demovt/docs/00-map.md.

  Segment 17cf -- THE MEMORY POOL. 2,832 bytes, 46 routines.

  COMPLETE. All 2,832 bytes; our code is 2,821 and the last eleven are padding.
  This file WAS a declared stub, written when 12ba needed something to call.

  ESSENTIALLY THE WHOLE UNIT CAME FROM THE RELEASE VERBATIM. Forty-three routines, and
  the only things that had to be measured rather than copied were three ABSENCES and one
  corrected signature:

      InitTempHeap, DoneTempHeap   absent -- ChangeSystemHeap has one caller, not three
      DoneHeapVariables            absent -- no `CALLF [DI+3c]` anywhere in the segment
      the `WriteLn` in HFreeMem    absent -- not one printable string in the segment
      SetMemTop(P : Pointer)       188f took a Pointer, not two Words

  **EVERY ONE OF THOSE FOUR WAS FOUND BY COUNTING RATHER THAN READING** -- callers,
  virtual-call sites, strings. See the notes at each.

  THE PAIRING WITH `LIB/HEAPS.PAS` WAS CONFIRMED FROM THE OTHER SIDE, BEFORE THIS
  SEGMENT WAS TOUCHED AT ALL, and it is the only one in the project that happened
  that way round. 12ba:1263 is `CALLF [DI+8]` on the object at DS:$39ae and 12ba:1261
  is `MOV DI,[DI]`, which between them fixed

    * that HGetMem is virtual method number two, so the declaration order below is
      the release's `Done, HGetMem, HFreeMem, HMemAvail, ...`;
    * that the VMT link is at object offset 0, so THeap descends from an ancestor
      with no fields of its own -- `OBJECT(TObject)` exactly as the release has it.

  A one-byte difference in the call site is what proved the second of those: a THeap
  declared as a BASE object carries its VMT link after its four Pointer fields, at
  +$10, and the call becomes `MOV DI,[DI+10]`. See the git history of this file.

  AND 46 ROUTINES IS THE RELEASE'S COUNT. `LIB/HEAPS.PAS` has three pointer helpers,
  five heap utilities, fifteen THeap methods, two TUmbHeap, fourteen THeapColl and
  two unit-level initialisers -- plus the nested closures ForEach and FirstThat need.
  The prologue scanner finds 46 frames.

  IT CALLS `Objects` AT SIX ENTRY POINTS (1891:0000, 0031, 03a7, 04ec, 0520, 055b),
  which is TCollection and its iterators -- THeapColl keeps its sub-heaps in one. It
  also calls 1880 (DOS $48/$49) and 188f (DOS $4A), both of which are transcribed.

  `TObject` IS DECLARED HERE rather than imported, and that is deliberate: it needs to
  be a fieldless object with one virtual method and nothing else, which is all the VMT
  geometry requires, and declaring it locally keeps this unit off whichever Turbo
  Vision the TP6 install happens to have. Segment 1891 IS Borland's `Objects` and is
  not in scope to reconstruct.
  =========================================================================== }

unit Heaps;

interface

uses
  VTDosRsz, VTDosMem, Objects;

type
  PFreeListRec = ^TFreeListRec;
  TFreeListRec = array[1..2] of LongInt;

  { --- `TObject`, `TCollection` AND `PString` COME FROM `Objects` ------------
    They used to be declared here as local stand-ins, and the header explained that
    as keeping the unit off whichever Turbo Vision the TP6 install happens to have.
    **That was untested and it was the wrong call.** A one-file probe -- `uses
    Objects; var C : TCollection; O : TObject;` -- compiles under this TP6 in five
    bytes, so Borland's unit is right there.

    AND USING IT MATTERS FOR MORE THAN TIDINESS. A locally declared `TObject` needs
    its two method BODIES compiled somewhere, and "somewhere" is this unit's code
    segment -- bytes that in the original live in segment 1891, Borland's `Objects`.
    Those phantom bodies would displace everything after them. Importing the real
    unit puts them where they belong and makes the VMT layout authoritative rather
    than reconstructed.

    The one caution the docs already record: the release's own map shows the author's
    `OBJECTS` differs from this install's by 74 bytes, so this is not necessarily the
    same Objects. Nothing here depends on more than `TObject`'s VMT link at offset 0
    and `TCollection`'s field layout, both of which are stable across versions. }

  PHeap = ^THeap;
  THeap = object(TObject)
    HHeapOrg  : Pointer;
    HHeapPtr  : Pointer;
    HHeapEnd  : Pointer;
    HFreeList : PFreeListRec;

    { The two constructors are NOT virtual and so take no VMT slot -- which is why
      adding them ahead of `Done` leaves every offset below unchanged. }
    constructor Init(Buffer : Pointer; Size : LongInt);
    constructor EmptyInit;

    destructor  Done; virtual;                                    { VMT +$04 }

    procedure HGetMem (var Buf : Pointer; Size : Word); virtual;   { VMT +$08 }
    procedure HFreeMem(var Buf : Pointer; Size : Word); virtual;   { VMT +$0c }

    function HMemAvail   : LongInt; virtual;                      { VMT +$10 }
    function HMaxAvail   : LongInt; virtual;                      { VMT +$14 }
    function HTotalAvail : LongInt; virtual;                      { VMT +$18 }

    procedure TransferToSystem;   virtual;                        { VMT +$1c }
    procedure TransferFromSystem; virtual;                        { VMT +$20 }
    procedure BeginOperation;     virtual;                        { VMT +$24 }
    procedure EndOperation;       virtual;                        { VMT +$28 }

    function InHeap(P : Pointer) : Boolean; virtual;              { VMT +$2c }

    { THESE TWO ARE CONFIRMED BY A CALL SITE THAT IS NOT EVEN THEIRS. See the note
      on THeapColl below: AddHeap can only land at +$38 if THeap's virtuals run to
      +$34, which takes exactly thirteen of them -- so the string pair is here and
      it is last. }
    function  HNewStr(S : String) : PString; virtual;             { VMT +$30 }
    procedure HDisposeStr(var S : PString);  virtual;             { VMT +$34 }
  end;

  { A heap living in upper memory. Two methods, both replacing THeap's, so it adds
    no VMT slot of its own. `InitUmbHeap` allocates these one at a time until the
    UMB provider stops giving them out. }
  PUmbHeap = ^TUmbHeap;
  TUmbHeap = object(THeap)
    constructor Init;
    destructor  Done; virtual;                                    { VMT +$04 }
  end;

  { --- A HEAP MADE OF OTHER HEAPS -----------------------------------------
    AND ITS FIRST NEW VIRTUAL IS WHAT FIXED THE WHOLE VMT LAYOUT. 17cf calls
    `CALLF [DI+38]` three times, and +$38 is one slot past THeap's last. AddHeap is
    the first virtual THeapColl adds, so it lands there -- but only if THeap has
    exactly THIRTEEN virtuals, running Done, HGetMem, HFreeMem, HMemAvail, HMaxAvail,
    HTotalAvail, TransferToSystem, TransferFromSystem, BeginOperation, EndOperation,
    InHeap, HNewStr, HDisposeStr. Drop the string pair and AddHeap would be at +$30.

    So a call site in a routine that has not been transcribed yet confirms the last
    two entries of a different object's method list. That is the same shape of
    evidence as `12ba:1263` proving the ancestry before this segment was touched. }
  PHeapColl = ^THeapColl;
  THeapColl = object(THeap)
    HeapColl : TCollection;

    constructor Init;
    destructor  Done; virtual;                                    { VMT +$04 }

    procedure AddHeap   (H : PHeap); virtual;                     { VMT +$38 }
    procedure RemoveHeap(H : PHeap); virtual;                     { VMT +$3c }

    procedure HGetMem (var Buf : Pointer; Size : Word); virtual;
    procedure HFreeMem(var Buf : Pointer; Size : Word); virtual;

    function HMemAvail   : LongInt; virtual;
    function HMaxAvail   : LongInt; virtual;
    function HTotalAvail : LongInt; virtual;

    procedure TransferToSystem;   virtual;
    procedure TransferFromSystem; virtual;
    procedure BeginOperation;     virtual;
    procedure EndOperation;       virtual;

    function InHeap(P : Pointer) : Boolean; virtual;
  end;

var
  { The release's five, in its declaration order. `FullHeap` at DS:$5d08 is the one
    12ba:125c reaches; it is a THeapColl here rather than the THeap the stub had,
    which changes no byte at that call site because HGetMem is at +$08 either way. }
  InitialHeapEnd : Pointer;
  Heap           : THeap;
  UmbHeap        : THeapColl;
  FullHeap       : THeapColl;
  TempHeap       : THeap;

{ --------------------------------------------------------------------------
  `InitTempHeap` AND `DoneTempHeap` ARE ABSENT FROM 1.31, and the proof is a call
  count rather than a search. Both of them call `ChangeSystemHeap`, and so does
  `ShrinkSystemHeap` -- so the release's ChangeSystemHeap has THREE callers inside its
  own segment. 17cf:010c has exactly ONE. Scanning every near call in the segment
  settles it without reading a byte of either routine.

  Which makes sense: the temporary heap is what the tracker's swap system carves out
  of the system heap when it needs scratch space, and a player that does nothing but
  play has nothing to swap. `TempHeap` is still declared above, and nothing in 1.31
  references it -- the same shape as `LoopMod` at $02c8 in PlayMod.
  -------------------------------------------------------------------------- }
procedure InitHeapVariables;

procedure InitUmbHeap;
procedure ChangeSystemHeap(Size : LongInt);
procedure ShrinkSystemHeap(Size : LongInt);

implementation

{ --------------------------------------------------------------------------
  17cf:0000, 0052, 0081 -- THE THREE POINTER HELPERS, and all three are one-liners
  that cost thirty to fifty bytes each because 8086 pointer arithmetic is 32-bit.

  A far pointer is a segment and an offset, and the same byte can be addressed many
  ways. NORMALISING one means moving as much as possible into the segment, so that the
  offset is always 0..15 -- which is what makes two pointers to the same byte compare
  equal, and what lets a heap span more than 64K without the offset ever wrapping.

      IncPtr(P, L)     P advanced by L bytes, renormalised
      NormalizePtr(P)  P renormalised in place
      LinealPtr(P)     P as a single 20-bit linear address

  `LinealPtr` IS WHY THE OTHER TWO EXIST: the heap compares and subtracts addresses,
  and it can only do that on the linear form. 17cf:0081 is called fourteen times from
  inside this segment, more than any other routine here.

  THE 32-BIT SHIFTS ARE RTL CALLS, not instruction sequences: 17cf:0016 calls
  1ba1:0a9c for `shr 4` on a LongInt and 17cf:0091 calls 1ba1:0aa8 for `shl 4`. An
  8086 has no 32-bit shift, so Turbo Pascal calls a helper -- which is why `IncPtr`'s
  one line is fifty bytes and why `NormalizePtr`, whose shift is on a WORD, gets the
  inline `SHR AX,4` instead and is twenty bytes shorter.
  -------------------------------------------------------------------------- }
function IncPtr(P : Pointer; L : LongInt) : Pointer;
begin
  IncPtr := Ptr(Seg(P^) + ((Ofs(P^) + L) shr 4), (Ofs(P^) + L) and 15)
end;

function NormalizePtr(P : Pointer) : Pointer;
begin
  NormalizePtr := Ptr(Seg(P^) + (Ofs(P^) shr 4), Ofs(P^) and 15)
end;

function LinealPtr(P : Pointer) : LongInt;
begin
  LinealPtr := (LongInt(Seg(P^)) shl 4) + Ofs(P^)
end;


{ --------------------------------------------------------------------------
  17cf:00b5 -- InitUmbHeap. Claim every upper-memory block the provider will give
  and add each one to `UmbHeap`.

  THE LOOP TERMINATES ON A FAILED ALLOCATION, not on a count. `New(UMB, Init)` always
  succeeds in the Pascal sense -- TUmbHeap.Init cannot fail -- so the test is whether
  the block it got has any room: `HTotalAvail = 0` means the provider is empty, and
  that block is disposed and the pointer nil'd to end the `repeat`. Using the same
  variable as both the result and the loop condition is what makes it one loop
  instead of two.
  -------------------------------------------------------------------------- }
procedure InitUmbHeap;
var
  UMB : PUmbHeap;                 { the whole of `ENTER 0004,0`                }
begin
  repeat
    New(UMB, Init);
    if UMB^.HTotalAvail <> 0 then
      UmbHeap.AddHeap(UMB)
    else
    begin
      Dispose(UMB, Done);
      UMB := nil;
    end;
  until UMB = nil
end;


{ --------------------------------------------------------------------------
  17cf:010c -- ChangeSystemHeap. Move Turbo Pascal's OWN heap boundary, clamped at
  both ends, and then let `Heap` take whatever that freed.

  IT IS CLAMPED IN LINEAR SPACE, WHICH IS WHY LinealPtr EXISTS. The floor is however
  much the system heap has already handed out (`HeapPtr - HeapOrg`) -- shrinking past
  that would strand live allocations -- and the ceiling is where the heap started
  (`InitialHeapEnd - HeapOrg`). Both are pointer SUBTRACTIONS, which only mean
  anything on the normalised linear form.

  `HeapEnd` AND `HeapPtr` ARE THE RTL's, not this unit's: the whole point is to
  reach into Turbo Pascal's heap variables and resize them under it, then tell
  `Heap` to absorb the difference.
  -------------------------------------------------------------------------- }
procedure ChangeSystemHeap(Size : LongInt);
begin
  if Size < LinealPtr(HeapPtr) - LinealPtr(HeapOrg) then
    Size := LinealPtr(HeapPtr) - LinealPtr(HeapOrg)
  else if Size > LinealPtr(InitialHeapEnd) - LinealPtr(HeapOrg) then
    Size := LinealPtr(InitialHeapEnd) - LinealPtr(HeapOrg);

  HeapEnd := IncPtr(HeapOrg, Size);
  Heap.TransferFromSystem
end;


{ShrinkSystemHeap. As above, and then hand the memory back to DOS by
  lowering the program's own memory top. Twenty-nine bytes for two statements, and
  the second is what makes this different from ChangeSystemHeap: `SetMemTop` is
  irreversible in a way that moving HeapEnd is not. }
{ --------------------------------------------------------------------------
  17cf:01d3 -- ShrinkSystemHeap. Move the boundary and then give the memory back to
  DOS, which is the irreversible half.

  IT IS THE RELEASE'S `SetMemTop(HeapEnd)` AFTER ALL, AND FINDING THAT CORRECTED
  ANOTHER UNIT. The call at 01e8 reaches 188f:0000, which the tree had declared as
  `VTDosRsz.SetBlockTop(TopSeg, ExtraBytes : Word)`. Written that way this line gives
  `LES DI,[..] / PUSH ES / LES DI,[..] / PUSH DI`; the original has
  `PUSH [0c4a] / PUSH [0c48]`, which is a POINTER VARIABLE pushed whole. So the callee
  takes one `Pointer` -- and read that way its arithmetic is Borland's
  `Memory.SetMemTop` exactly.

  **A PARAMETER LIST CAN BE WRONG IN A WAY ONLY A CALLER IN ANOTHER SEGMENT REVEALS.**
  Both spellings put the same four bytes on the stack, so 188f verified identical under
  the wrong one and still does under the right one -- nothing inside that unit could
  ever have caught it. See the note at its declaration.
  -------------------------------------------------------------------------- }
procedure ShrinkSystemHeap(Size : LongInt);
begin
  ChangeSystemHeap(Size);
  SetMemTop(HeapEnd)
end;


{ ==========================================================================
  EVERYTHING BELOW IS STILL A STUB, and they are in the RELEASE'S FILE ORDER, which
  the addresses confirm as far as they have been checked:

      0000  IncPtr            ENTER 0004   done
      0052  NormalizePtr      ENTER 0004   done
      0081  LinealPtr         ENTER 0004   done
      00b5  InitUmbHeap       ENTER 0004   done
      010c  ChangeSystemHeap  PUSH BP      done
      01d3  ShrinkSystemHeap  PUSH BP      done
      01f1  THeap.Init        PUSH BP      -- NOT InitTempHeap; see above. 01f6
                                          calls 1891:0000, which is TObject.Init,
                                          and a constructor is what calls that
      ...   the rest of the THeap methods, then TUmbHeap, then THeapColl, then the
            two unit-level initialisers

  The bodies below are deliberately wrong. `verify.py` reports the prefix, which is
  the right measure while the unit is built in address order.
  ========================================================================== }

{ --------------------------------------------------------------------------
  17cf:01f1 -- THeap.Init. Build a heap inside a caller-supplied buffer.

  IT ROUNDS THE BUFFER UP TO A PARAGRAPH AND THE END DOWN TO ONE, which is what makes
  every pointer in the heap normalisable: `HHeapEnd := Ptr(Seg(HHeapEnd^), 0)` throws
  away the offset, and the `if Ofs(Buffer^) <> 0` test bumps the start to the next
  paragraph rather than keeping a misaligned base. A heap whose ends are both
  paragraph-aligned can hand out normalised pointers, and only normalised pointers
  compare and subtract correctly across a 64K boundary.

  THE FREE LIST STARTS AT THE HEAP'S OWN BASE and is zeroed in place -- Turbo Pascal's
  heap keeps its free list inside the heap it manages, so there is no separate
  bookkeeping allocation.

  `Size > 0` GUARDS THE WHOLE BODY, which is what makes `EmptyInit` possible: a heap
  with no buffer is a valid object with four nil pointers.
  -------------------------------------------------------------------------- }
constructor THeap.Init(Buffer : Pointer; Size : LongInt);
begin
  TObject.Init;
  if Size > 0 then
  begin
    HHeapEnd  := IncPtr(Buffer, Size);
    HHeapEnd  := Ptr(Seg(HHeapEnd^), 0);

    Buffer   := NormalizePtr(Buffer);
    if Ofs(Buffer^) <> 0 then
      Buffer := Ptr(Seg(Buffer^) + 1, 0);
    HHeapOrg  := Buffer;
    HHeapPtr  := Buffer;
    HFreeList := Buffer;
    FillChar(HFreeList^, SizeOf(HFreeList^), 0);
  end;
end;

constructor THeap.EmptyInit;
begin
  TObject.Init
end;

destructor THeap.Done;
begin
  HHeapOrg  := nil;
  HHeapPtr  := nil;
  HHeapEnd  := nil;
  HFreeList := nil;
  TObject.Done
end;


{ --------------------------------------------------------------------------
  17cf -- THeap.HGetMem and HFreeMem, and the pair around them.

  EVERY ONE OF THE FIVE MEMORY OPERATIONS IS WRAPPED IN BeginOperation/EndOperation,
  and the call counts prove it before a byte is read: `CALLF [DI+24]` appears FIVE
  times in the segment and `CALLF [DI+28]` five times, which are exactly the five
  release methods that use them -- HGetMem, HFreeMem, HMemAvail, HMaxAvail and
  HTotalAvail.

  WHAT THE WRAPPER DOES is swap this heap into Turbo Pascal's OWN heap variables for
  the duration, so that `GetMem`, `FreeMem`, `MemAvail` and `MaxAvail` -- which only
  ever look at `HeapOrg`/`HeapPtr`/`HeapEnd`/`FreeList` -- operate on this heap
  instead. That is the whole trick of the unit: it does not reimplement an allocator,
  it lends the RTL's one a different set of pointers.

  AND THE DIAGNOSTIC IS GONE. The release's HFreeMem writes
  `WriteLn('Bad FreeMem: ', HexPtr(Buf))` on a pointer outside the heap. **There is not
  one printable string anywhere in segment 17cf**, so 1.31 drops the message and keeps
  the guard -- which is what a player with no console would do.
  -------------------------------------------------------------------------- }
procedure THeap.HGetMem(var Buf : Pointer; Size : Word);
begin
  BeginOperation;
  if MaxAvail < Size then
    Buf := nil
  else
    GetMem(Buf, Size);
  EndOperation
end;

procedure THeap.HFreeMem(var Buf : Pointer; Size : Word);
begin
  if Buf = nil then Exit;
  if not InHeap(Buf) then Exit;
  BeginOperation;
  FreeMem(Buf, Size);
  Buf := nil;
  EndOperation
end;

function THeap.HMemAvail : LongInt;
begin
  BeginOperation;
  HMemAvail := MemAvail;
  EndOperation
end;

function THeap.HMaxAvail : LongInt;
begin
  BeginOperation;
  HMaxAvail := MaxAvail;
  EndOperation
end;

function THeap.HTotalAvail : LongInt;
begin
  BeginOperation;
  HTotalAvail := LinealPtr(HHeapEnd) - LinealPtr(HHeapOrg);
  EndOperation
end;


{ --------------------------------------------------------------------------
  17cf -- the four-pointer swap, in both directions, and the guard around it.

  THE CALL COUNTS CONFIRM `EndOperation`'s TWO BRANCHES. TransferFromSystem is called
  FOUR times in the segment and TransferToSystem TWICE, and the release accounts for
  exactly that: BeginOperation calls one of each, EndOperation calls
  TransferFromSystem in BOTH of its branches plus Heap.TransferToSystem in one, and
  ChangeSystemHeap calls Heap.TransferFromSystem. 1+2+1 = 4 and 1+1 = 2. Written with
  a single unconditional `TransferFromSystem` before the `if`, the count would still
  be four but the code would be shorter -- so the duplication is the original's.

  `@Self <> @Heap` IS THE WHOLE GUARD. `Heap` IS the system heap's mirror, so swapping
  it in and out of itself would be pointless -- and worse than pointless in
  EndOperation, where it would copy stale values back. Comparing object addresses is
  how a method asks "am I the singleton?".
  -------------------------------------------------------------------------- }
procedure THeap.TransferToSystem;
begin
  HeapOrg  := HHeapOrg;
  HeapPtr  := HHeapPtr;
  HeapEnd  := HHeapEnd;
  FreeList := HFreeList
end;

procedure THeap.TransferFromSystem;
begin
  HHeapOrg  := HeapOrg;
  HHeapPtr  := HeapPtr;
  HHeapEnd  := HeapEnd;
  HFreeList := FreeList
end;

procedure THeap.BeginOperation;
begin
  if @Self <> @Heap then
  begin
    Heap.TransferFromSystem;
    TransferToSystem;
  end;
end;

procedure THeap.EndOperation;
begin
  if @Self <> @Heap then
  begin
    TransferFromSystem;
    Heap.TransferToSystem;
  end
  else
  begin
    TransferFromSystem;
  end;
end;

{ `HHeapPtr` AND NOT `HHeapEnd` IS THE UPPER BOUND, so a pointer into the heap's
  unallocated tail reads as NOT in the heap. That is the right answer for HFreeMem's
  guard -- nothing above the break has been handed out -- and it is why InHeap cannot
  be used to ask "is this address inside the buffer". }
function THeap.InHeap(P : Pointer) : Boolean;
begin
  InHeap := (LinealPtr(P) >= LinealPtr(HHeapOrg)) and
            (LinealPtr(P) <  LinealPtr(HHeapPtr))
end;

function THeap.HNewStr(S : String) : PString;
var
  NS : PString;
begin
  HGetMem(Pointer(NS), Length(S) + 1);
  if NS <> nil then
    NS^ := S;
  HNewStr := NS
end;

procedure THeap.HDisposeStr(var S : PString);
begin
  HFreeMem(Pointer(S), Length(S^) + 1)
end;


{ ==========================================================================
  EVERYTHING BELOW IS STILL A STUB, in the release's file order: TUmbHeap's two,
  THeapColl's fourteen, then InitHeapVariables and DoneHeapVariables, then the unit's
  own initialisation block.
  ========================================================================== }

{ --------------------------------------------------------------------------
  17cf:0698 -- TUmbHeap.Init. Ask for an upper-memory block and build a heap in it.

  `UMBAllocate(Buf, 1000000)` ASKS FOR A MEGABYTE AND TAKES WHAT IT GETS. Upper memory
  comes in whatever blocks the provider has left, so the request is deliberately
  absurd: the function returns the size it actually gave, which becomes the heap's
  size. Asking for more than exists is how you find out how much exists.

  AND FAILURE IS A VALID OBJECT, not an error. A nil buffer falls through to
  `EmptyInit`, which leaves a THeap with four nil pointers -- so `InitUmbHeap`'s loop
  can construct one, ask its `HTotalAvail`, and dispose it again without ever handling
  an exception. That is what makes the caller's `repeat ... until UMB = nil` work.

  `UMBAllocate` AND `UMBFree` ARE THE RELEASE'S NAMES for what this tree called
  `VTDosMem.Alloc` and `.Free`; see the note at their declaration -- 17cf's two calls
  into 1880 are what confirmed the pairing.
  -------------------------------------------------------------------------- }
constructor TUmbHeap.Init;
var
  L   : LongInt;
  Buf : Pointer;
begin
  L := UMBAllocate(Buf, 1000000);
  if Buf <> nil then
    THeap.Init(Buf, L)
  else
    EmptyInit
end;

{ The guard matters: `EmptyInit` leaves HHeapOrg nil, and freeing a nil UMB handle
  would hand the provider rubbish. Note it does NOT call `THeap.Done` -- the pointers
  are left as they are, because the block they point into has just been released. }
destructor TUmbHeap.Done;
begin
  if HHeapOrg <> nil then
    UMBFree(HHeapOrg)
end;

{ --------------------------------------------------------------------------
  17cf:071b -- THeapColl.Init. A heap made of other heaps: no buffer of its own, and
  a TCollection to keep the members in.

  `EmptyInit` RATHER THAN `Init`, which is the point of having two constructors. A
  THeapColl never owns memory directly -- its four inherited pointers stay nil for
  life and every allocation is delegated -- so the only inherited state it needs is
  TObject's VMT link.

  `HeapColl.Init(3, 2)` sizes the collection for three heaps growing by two, which is
  a guess about how many blocks upper memory comes in.
  -------------------------------------------------------------------------- }
constructor THeapColl.Init;
begin
  EmptyInit;
  HeapColl.Init(3, 2)
end;


{ --------------------------------------------------------------------------
  17cf -- THeapColl.Done, and the NESTED PROCEDURE is why the segment has more
  frames than the release has routines.

  `HeapColl.ForEach(@DoFree)` TAKES THE ADDRESS OF A LOCAL PROCEDURE, so `DoFree` is
  compiled as a routine in its own right -- one of the frames `scan_funcs.py` counts
  and the release's routine list does not mention. It has to be `far`, because ForEach
  calls it through a pointer, and it can still see `HeapColl` because Turbo Pascal
  passes the enclosing frame alongside. That is the "real TP7 nested-procedure closure"
  the reading pass noted when it first identified this segment.

  `if Seg(H^) <> Seg(Heap)` IS THE GUARD THAT SAVES THE SYSTEM HEAP. `Heap` is a
  static variable, not a `New`-allocated object, so disposing it would hand the RTL a
  pointer it never allocated. Comparing SEGMENTS rather than full addresses is enough
  because a static object and a heap-allocated one cannot share a segment here.

  AND IT DELETES WHILE IT ITERATES, which is normally a bug and is safe here only
  because Borland's `ForEach` walks the item array by index from the end -- so removing
  the current item cannot skip the next one. Worth knowing before touching it.
  -------------------------------------------------------------------------- }
destructor THeapColl.Done;

  procedure DoFree(H : PHeap); far;
  begin
    HeapColl.Delete(H);
    if Seg(H^) <> Seg(Heap) then
      Dispose(H, Done);
  end;

begin
  HeapColl.ForEach(@DoFree)
end;


{ Two one-liners, and they are the two virtuals THeapColl ADDS -- so they sit at
  VMT +$38 and +$3c, one and two slots past THeap's last. `CALLF [DI+38]` appearing
  three times in this segment is what fixed THeap's method list at thirteen. }
procedure THeapColl.AddHeap(H : PHeap);
begin
  HeapColl.Insert(H)
end;

procedure THeapColl.RemoveHeap(H : PHeap);
begin
  HeapColl.Delete(H)
end;

{ --------------------------------------------------------------------------
  17cf -- THeapColl's SIX DELEGATING METHODS, and every one is the same shape: a
  nested `far` procedure handed to `HeapColl.ForEach` or `.FirstThat`.

  THE CLOSURES READ THE ENCLOSING FRAME, which is what makes this work at all. `Get`
  assigns to its parent's `Buf`; `Add` increments its parent's `Sum`; `IsIn` reads its
  parent's `P`. None of those is a parameter of the closure -- Turbo Pascal passes the
  enclosing frame pointer alongside the code address, and `ForEach` hands it back. That
  is why each closure must be `far`, and why each is compiled as a routine in its own
  right: **the six of them plus DoFree are the seven frames `scan_funcs.py` counts
  beyond the release's routine list.**

  `FirstThat` VERSUS `ForEach` IS THE WHOLE ALGORITHM. Allocation stops at the first
  heap that can satisfy it, freeing stops at the heap that owns the pointer, and
  "is it in here" stops at the first yes -- all three are `FirstThat`. Summing free
  space and finding the largest block have to visit everything, so both are `ForEach`.

  AND THE FOUR TRANSFER/OPERATION OVERRIDES ARE EMPTY. A THeapColl owns no memory of
  its own, so there is nothing to swap into Turbo Pascal's heap variables -- each
  member does its own swapping inside its own HGetMem. Overriding them to do nothing is
  what stops the inherited THeap versions from writing this collection's four nil
  pointers over the RTL's live ones.
  -------------------------------------------------------------------------- }
procedure THeapColl.HGetMem(var Buf : Pointer; Size : Word);

  function Get(var H : THeap) : Boolean; far;
  begin
    H.HGetMem(Buf, Size);
    Get := Buf <> nil
  end;

begin
  Buf := nil;
  HeapColl.FirstThat(@Get)
end;

{ The result of `FirstThat` is discarded and `Buf` is nil'd unconditionally -- so a
  pointer belonging to no member heap is silently forgotten rather than reported. The
  member's own HFreeMem is where the InHeap guard lives. }
procedure THeapColl.HFreeMem(var Buf : Pointer; Size : Word);

  function DoFree(var H : THeap) : Boolean; far;
  begin
    if H.InHeap(Buf) then
    begin
      DoFree := True;
      H.HFreeMem(Buf, Size)
    end
    else
      DoFree := False
  end;

begin
  if Buf = nil then Exit;
  HeapColl.FirstThat(@DoFree);
  Buf := nil
end;

function THeapColl.HMemAvail : LongInt;
var
  Sum : LongInt;

  procedure Add(var H : THeap); far;
  begin
    Inc(Sum, H.HMemAvail)
  end;

begin
  Sum := 0;
  HeapColl.ForEach(@Add);
  HMemAvail := Sum
end;

{ `Sum` starts at zero and holds the running MAXIMUM here, not a total -- the name is
  the release's and it is reused from HMemAvail above. `Max` is a local of the closure
  rather than a second read of `H.HMaxAvail`, which matters because that call is not
  free: it swaps heap pointers in and out. }
function THeapColl.HMaxAvail : LongInt;
var
  Sum : LongInt;

  procedure FindMax(var H : THeap); far;
  var
    Max : LongInt;
  begin
    Max := H.HMaxAvail;
    if Max > Sum then
      Sum := Max
  end;

begin
  Sum := 0;
  HeapColl.ForEach(@FindMax);
  HMaxAvail := Sum
end;

function THeapColl.HTotalAvail : LongInt;
var
  Sum : LongInt;

  procedure Add(var H : THeap); far;
  begin
    Inc(Sum, H.HTotalAvail)
  end;

begin
  Sum := 0;
  HeapColl.ForEach(@Add);
  HTotalAvail := Sum
end;

procedure THeapColl.TransferToSystem;
begin
end;

procedure THeapColl.TransferFromSystem;
begin
end;

procedure THeapColl.BeginOperation;
begin
end;

procedure THeapColl.EndOperation;
begin
end;

{ `InHeap := True` IS A DEAD STORE and it is the original's -- the next line overwrites
  it unconditionally. Transcribed as found; the standing rule is that the binary decides
  and this is what the binary has. }
function THeapColl.InHeap(P : Pointer) : Boolean;

  function IsIn(var H : THeap) : Boolean; far;
  begin
    IsIn := H.InHeap(P)
  end;

begin
  InHeap := True;
  InHeap := HeapColl.FirstThat(@IsIn) <> nil
end;


{ --------------------------------------------------------------------------
  17cf -- the two unit-level initialisers, which is where the heaps get wired
  together.

  `FullHeap` ENDS UP CONTAINING `UmbHeap` AND `Heap`, in that order, and the order is
  the allocation policy: `HGetMem` walks the collection with `FirstThat` and stops at
  the first heap that can satisfy the request, so **upper memory is spent before
  conventional memory**. For a DOS program in 1993 that is exactly the right way round.

  `UmbHeap` IS ITSELF A THeapColl, not a TUmbHeap -- so FullHeap is a collection
  containing a collection. `InitUmbHeap` is what fills it, one TUmbHeap per block the
  provider yields, and it is called from outside this unit.

  `DoneHeapVariables` REMOVES `Heap` BEFORE CALLING `Done`, which is the other half of
  the guard in THeapColl.Done's closure: that closure refuses to dispose anything whose
  segment matches `Heap`'s, and taking it out of the collection first means the check
  never has to fire. Belt and braces, and the belt is here.
  -------------------------------------------------------------------------- }
procedure InitHeapVariables;
begin
  UmbHeap.Init;
  FullHeap.AddHeap(@UmbHeap);
  FullHeap.AddHeap(@Heap)
end;

{ `DoneHeapVariables` IS ABSENT FROM 1.31, and a MISSING CALL is what proved it. The
  release's version is `FullHeap.RemoveHeap(@Heap); FullHeap.Done; TempHeap.Done` --
  and `RemoveHeap` is virtual at VMT +$3c, so calling it emits `CALLF [DI+3c]`.
  **There is no `CALLF [DI+3c]` anywhere in segment 17cf.** The original's 0a93 begins
  `MOV AX,[0c48] / MOV DX,[0c4a]`, which is `InitialHeapEnd := HeapEnd` -- the
  initialisation block, sitting immediately after InitHeapVariables with nothing
  between.

  So a player that runs until the machine is switched off never tears its heaps down,
  which is the third routine this segment turns out not to have. `THeapColl.RemoveHeap`
  still exists and is still declared virtual: its slot is what puts `AddHeap` at +$38,
  and the two are declared as a pair. It simply has no caller. }


{ --------------------------------------------------------------------------
  THE UNIT'S INITIALISATION SECTION. It does not allocate anything: it takes a
  SNAPSHOT of Turbo Pascal's heap as the program starts, and wraps it in an object.

  `InitialHeapEnd := HeapEnd` IS THE HIGH-WATER MARK that `ChangeSystemHeap` clamps
  against, and it has to be read here because the very first `ShrinkSystemHeap` will
  lower `HeapEnd` and the original value would be gone.

  `Heap` IS BUILT BY HAND rather than by `Init`, and it must be: `THeap.Init` would
  carve a fresh heap out of the buffer and zero a free list, destroying whatever the
  RTL has already allocated. `EmptyInit` followed by four assignments adopts the
  existing heap instead. That is also exactly what `TransferFromSystem` does -- and
  `BeginOperation`'s `@Self <> @Heap` test is what keeps this one object in step with
  the RTL for the rest of the program's life.

  `TempHeap.EmptyInit` IS WHY THE VARIABLE STAYS DECLARED even though 1.31 has no
  `InitTempHeap` or `DoneTempHeap`: it is initialised here and destroyed in
  `DoneHeapVariables`, so it is live, just never filled.
  -------------------------------------------------------------------------- }
begin
  InitialHeapEnd := HeapEnd;

  Heap.EmptyInit;
  Heap.HHeapOrg  := HeapOrg;
  Heap.HHeapPtr  := HeapPtr;
  Heap.HHeapEnd  := HeapEnd;
  Heap.HFreeList := FreeList;

  FullHeap.Init;
  TempHeap.EmptyInit
end.
