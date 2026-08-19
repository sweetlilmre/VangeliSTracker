# Per-unit detail, from the line-by-line pass

Units are listed here once every routine in them has been read, not merely
their entry points. `00-map.md` carries the identification evidence; this file
carries the contents.

---

## `1065` — a UART used as a timing source

491 bytes, eight routines, all read. It registers as a driver (descriptor at
`DS:$001e`, slots from `DS:$0034`) but it drives nothing: the poll slot at
`+$2a` points at the core's shared `1a17:1008`.

### `1065:0046` — detect and install

```
DS:$0bc7 := 1;  DS:$0bbd := 0;  DS:$0bbf := 8;  DS:$0bbc := 0
if the saved vector at DS:[$1a] is nil then
begin
  DS:$0e36 := (IN $21 and $10) <> 0         was IRQ 4 already masked?
  DS:[$1a] := InstallIRQ(4, 1065:0005)      1b24:00d7
  UnmaskIRQ(4)                              1b24:0000
  DS:$0e2e := IN $3FC                       save the Modem Control Register
  DS:$0e30 := IN $3FB                       save the Line Control Register
  OUT $3FC, 8                               MCR: OUT2 -- lets the UART interrupt
  OUT $3FB, $83                             LCR: DLAB on, 8N1
  DS:$0e32 := (IN $3F9 shl 8) or IN $3F8    save the existing divisor
  OUT $3F8, $60;  OUT $3F9, 0               divisor := $0060
  OUT $3FB, 3                               LCR: DLAB off, 8N1
  DS:$0e34 := IN $3F9                       save the Interrupt Enable Register
  OUT $3F9, 0;  OUT $3F9, 2                 IER := transmit-holding-empty
end
```

Ports `$3F8`..`$3FC` are COM1's 8250/16450. Setting **IER bit 1** turns on the
transmit-holding-register-empty interrupt, and the handler writes a byte on
every one, so the UART free-runs as a periodic interrupt source at a rate set
by the divisor. It is a **clock**, not a sound card.

### `1065:0005` — the interrupt handler

```
CLI, save AX/DS/DX, then ES/BX/CX/DI/SI
OUT $3F8, 0                       keep the transmitter hungry
AL := DS:[$18] + 5
if AL >= 12 then begin AL := AL - 12;  Inc(DS:$0bc8) end
DS:[$18] := AL
restore, OUT $20,$20 (EOI), IRET
```

The mod-12 accumulator advancing by 5 divides the UART's interrupt rate down
by 12/5 to produce the tick that increments **`DS:$0bc8`** — the counter INT
2Fh function 3 snapshots.

### `1065:0110` — shutdown

Puts back the MCR, LCR, divisor and IER it saved, restores the IRQ 4 vector
through `1b24:00d7`, clears the saved vector, and re-masks IRQ 4 **only if it
was masked when we arrived** (`DS:$0e36`). A tidy uninstall.

The remaining routines are stubs: `0039` returns 1, `0104`/`010b` are empty
`RETF`s, `00f3` returns its argument.

---

## `1084` — the GUS driver

384 bytes, ten routines, all read. Eight of them are the driver record's
method slots (see `00-map.md`); the other two are its interrupt handler.

### `1084:0000` — the interrupt handler

```
Inc(DS:$005e)
DS:$4302 := SS;  DS:$4304 := SP
SS := DS;  SP := $4302                 switch to a private stack
if DS:$0bce <> 0 and DS:$0bd0 = DS:$0058 then
  (nothing)
else begin Inc(DS:$0058);  CALLF [DS:$4312] end
SS, SP := DS:$4302, DS:$4304
Dec(DS:$005e)
```

The same **private-stack switch** the core's shared poll uses, for the same
reason. `DS:$4312` is the hook `1a17:053c` installs, so both paths funnel into
one place. The guard compares `DS:$0bd0` (which the driver's poll slot
increments) against `DS:$0058`, so a tick that has already been serviced is
skipped.

---

## `1b24` — the PC's interrupt and DMA plumbing

768 bytes, eight routines, all read.

| | |
|---|---|
| `0000` | unmask IRQ N — clears the bit in `$21`, or in `$A1` plus the cascade |
| `0044` | mask IRQ N — sets it |
| `007e` | **is IRQ N enabled?** |
| `00d7` | install a handler, returning the displaced vector |
| `0128` | program a 16-bit DMA channel |

`007e` is the one worth writing out, because of the cascade:

```
if N < 8 then
  Result := (IN $21 and (1 shl N)) = 0
else if (IN $21 and 4) <> 0 then
  Result := False                       IRQ 2 is masked -- nothing on the
                                        slave can get through at all
else
  Result := (IN $A1 and (1 shl (N-8))) = 0
```

Checking the cascade before trusting the slave mask is exactly right and is
the sort of thing that gets left out.

---

## `1723` — the Gravis UltraSound hardware layer

2752 bytes, 24 routines. Everything below has been read; the sample-upload
loop and the IRQ handler are the substantial ones.

> **The probe result is an ERROR CODE, and the note elsewhere in this file is
> right: zero means the hardware answered.** Settled at `109c:0021`, the only
> site that tests it — `OR AL,AL / JNZ` skips selection on non-zero, so a
> driver is chosen only on zero. `1000:0302` calls the same slot but discards
> the result.
>
> This was briefly recorded here as the opposite, on the strength of three
> *producers* that all return 1 for "found" (`1723:045a`, `1723:04f1`,
> `1065:0039`). They are result codes, not booleans. Three inferences of the
> same kind agreeing is not independent evidence; the single consumer settled
> it. Left recorded because the mistake is an easy one to repeat.

### `1723:04f1` — find the card

Wraps the DRAM probe with a search. If `DS:$0582` is `$FFFF` the base port was
never configured, so it walks a table of candidates at `DS:$05a8`, entries 1
through `$0C`, writing each into `DS:$0582` and probing; otherwise it probes
the one configured value and nothing else.

### `1723:045a` — the DRAM probe

Two distinct patterns, `$16D8` and `$0F83`, written into register `$02` of
voices 0 and 1, read back, and both must match. Using two voices and two
values is what distinguishes real independent registers from a floating bus
that returns the last thing written. The read-back is masked with `$1FFF`
because the register is only thirteen bits wide.

The previous contents of both registers are saved on the way in and put back
on every exit path, so probing a card that is already playing does not disturb
it. `CLI` is held across the whole sequence.

### The register interface

```
1723:0000  SelectVoice(N)        OUT base+$102, N
1723:0013  ReadReg8(Reg)         Reg or $80 if < $40; select base+$103,
                                 read base+$105
1723:0030  Write(Reg, Val)       select base+$103, write base+$105
1723:004a  ReadReg16(Reg)        select base+$103, read base+$104 as a word
1723:0065  WriteWord(Reg, W)     select base+$103, write base+$104 as a word
1723:007d  Delay                 seven IN AL, base
```

All near (`RET`), all private to the unit.

### `1723:0089` — upload a sample into GUS DRAM

```
Write($44, HighByte(Addr shr 16))
WriteWord($43, LowWord(Addr))
BH := (Flag <> 1) ? $FF : $00 ;  BH := BH shl 7        so $80 or $00
repeat Count times
  OUT base+$103, $43;  OUT base+$104, DI (word)        DRAM address low
  OUT base+$107, LODSB xor BH                          the data port
  Inc(DI)
  if DI wrapped then
    begin Inc(BL); OUT base+$103,$44; OUT base+$105,BL end
```

Registers `$43` and `$44` are the DRAM address low word and high byte,
`base+$107` the DRAM data port. The `XOR` with `$80` converts signed samples
to the unsigned form the card wants, and `SBB BH,BH / SHL BH,7` builds that
mask branchlessly from a flag. The address-high register is only rewritten
when the low word wraps, which is what makes the loop cheap.

### The timers

```
1723:0100  start timer 1     Write($46, Count); set bit 2 of DS:$0592;
                             Write($45, ...); set bit 0 of DS:$0593;
                             OUT base+8, 4; OUT base+9, DS:$0593
1723:0140  start timer 2     the same with $47, bit 3, and bit 1
1723:0180  stop
1723:01b5  timer 1 fired     clear bit 2, rewrite $45, then CALLF [DS:$058a]
1723:01db  timer 2 fired     clear bit 3, rewrite $45, then CALLF [DS:$058e]
```

`DS:$058a` and `DS:$058e` are **callback pointers**, and `1084:008a` sets
`DS:$058e` to `1084:0000` — so the GUS driver's own interrupt handler is
registered as the timer 2 callback. That closes the loop between the driver
and its hardware.

### `1723:0201` — the interrupt handler

```
CLI, PUSHA, save ES/DS, load our data segment
OUT $20, $20                          EOI to the master PIC
if DS:$0584 >= 8 then OUT $A0, $20    and to the slave if needed
MaskIRQ(DS:$0584)                     mask our own line while we work
repeat
  CLI
  AL := IN (base+6)                   the GUS IRQ status
  if AL and $0C = 0 then break
  STI
  if AL and $04 then Timer1Fired
  if AL and $08 then Timer2Fired
forever
UnmaskIRQ(DS:$0584)
ReadReg8($0F)
restore, IRET
```

Masking its own IRQ for the duration and then **looping until the status
register reports nothing outstanding** is the right way to handle a card that
can raise a second interrupt while the first is being serviced.

### `1723:02d3` — mix control and IRQ/DMA setup

```
V := DS:[$059a + IRQ] + $40        translate the IRQ to the GUS's own code
PUSHF; CLI
OUT base+$0F, 5     OUT base+$00, $0B    OUT base+$0B, 0
OUT base+$0F, 0     OUT base+$00, $4B    OUT base+$0B, V
                    OUT base+$00, $4B    OUT base+$0B, V
OUT base+$102, 0    OUT base+$00, $0C    OUT base+$102, 0
POPF
```

`base+$00` is the mix control register and `base+$0B` the IRQ/DMA control.
The card encodes its IRQ in three bits rather than taking the number
directly, so `DS:$059a` is a **translation table** indexed by IRQ, and `+$40`
sets the combined-IRQ bit. Writing `$4B`/`V` twice is the documented
requirement, not a mistake.

### `1723:029f` — uninstall

```
if DS:$0599 <> 0 then
begin
  DS:$0599 := 0
  if DS:$0598 = 0 then MaskIRQ(DS:$0584)
  InstallIRQ(DS:$0584, DS:$0594)      put the displaced vector back
end
```

Guarded so a second call does nothing, and it only re-masks the line if it
was not in use before.

### `1723:0357` — full reset

Clears the per-voice state tables, then resets the card and silences every
voice:

```
FillChar(DS:$371a, $80, $FF)      32 voices x 4 bytes -- start addresses
FillChar(DS:$379a, $80, $FE)                          -- end addresses
FillChar(DS:$381a, $80, $FF)                          -- loop addresses
FillChar(DS:$389a, $20, $FF)      32 bytes, one per voice
FillChar(DS:$38ba, $80, $FF)
FillChar(DS:$393a, $20, $7F)      32 bytes of $7F  -- pan, centred
FillChar(DS:$395a, $20, $00)      32 bytes of zero -- volume
MixControl                        1723:02d3
OUT base, $0B
Write($4C,0); Delay; Write($4C,1)         reset and release
Write($0E, $DF)                           active voice count
WriteWord($43, 0);  Write($44, 0)         DRAM pointer to zero
for each voice: SelectVoice(I); Write($00,3); Write($0D, ...)
```

Voice control `$00` and volume control `$0D` both get bit 0 and 1 set, which
is stop-and-hold. The state tables are the driver's shadow of what it has told
each voice, four bytes per voice for the address registers and one byte each
for pan and volume.

### `1723:0662` — program a voice's addresses

```
V     := the voice number
Start := DS:[$371a + V*4]     as a LongInt
End   := DS:[$379a + V*4]
Loop  := DS:[$381a + V*4]
Write($00, ReadReg($00) or 3)             stop it first
Format(Start)                             1723:0539 -- shl 9, mask $1FFFFE00
WriteWord($0B, Low(Start));  WriteWord($0A, High(Start))
Format(End)
WriteWord($05, Low(End));    WriteWord($04, High(End))
```

The register numbers line up with the UltraSound's voice map throughout —
`$00` control, `$01` frequency, `$02`/`$03` start, `$04`/`$05` end, `$0A`/`$0B`
current position, `$0C` pan, `$0D` volume control. `1723:0539` is the address
formatter: shift left 9 and mask to `$1FFFFE00`, which is how the card wants a
DRAM address split across its two registers.

**`1723` is complete.** All 24 routines read.

---

## `19a0` — the Sound Blaster hardware layer

1905 bytes, 23 routines.

### The DSP primitives

```
19a0:0000  Reset : Boolean       OUT reset,1; delay 100; OUT reset,0;
                                 poll for $AA, up to 100 tries
19a0:005b  WaitWriteReady(N)     spin on bit 7 of DS:$0b02 (base+$C),
                                 N tries; leaves the timeout in DS:$0b85
19a0:0077  WriteDSP(Val, N)      wait; if it timed out, flush a byte from
                                 DS:$0afe and wait again; then OUT
19a0:009b  WaitReadReady(N)      spin on bit 7 of DS:$0b04 (base+$E)
19a0:00bb  ReadDSP(N) : Byte     wait, then IN from DS:$0afc (base+$A)
```

Bit 7 is tested with `ADD AL,AL` and a carry branch throughout — a byte
shorter than `TEST AL,$80`, and it is used consistently.

### The mixer

```
19a0:00ce  WriteMixer(Reg, Val)  OUT DS:$0ae4, Reg;  OUT DS:$0ae6, Val
19a0:00e5  ReadMixer(Reg) : Byte OUT DS:$0ae4, Reg;  IN  AL, DS:$0ae6
```

`DS:$0ae4`/`$0ae6` are base+4 and base+5, the Sound Blaster Pro mixer's
address and data ports. That is what `DACVol` and `FMVol` in the config
reach.

### `19a0:029c` — DSP version

```
WriteDSP($E1, timeout)               $E1 -- get DSP version
repeat
  DS:$0b23 := ReadDSP($FFFF)         the major number
  Inc(Tries)
until it answered, or the read timed out, or ten tries
DS:$0b22 := ReadDSP(...)             the minor number
build a version string at DS:$0b24
```

`DS:$0b22` ends up holding major*256+minor, which is what `19a0:0257` then
compares against `$200` — i.e. **"is this DSP 2.0 or later?"**, the test for
whether auto-init DMA is available.

### `19a0:0257` — start

```
if not DetectDSP then exit
if DS:$0b7f <> 0 then exit             already started
GetDSPVersion
DS:$0b8c := (DS:$0b22 > $200) and (DS:$0b1c <> 0)
WriteDSP($D1, DS:$0b1a)                $D1 -- speaker on
DS:$0b7f := 1
```

`$D1` is the DSP's speaker-enable command, and `DS:$0b7f` is the
already-started guard.

### `19a0:038f` — the DSP identification string

```
WriteDSP($E3, timeout)                $E3 -- return the copyright string
repeat
  Ch := ReadDSP($FFFF)
  append it to the String at DS:$0b2a, max $50
until Ch = $AA, or a read times out, or ten tries
if it timed out with room left, keep reading
Dec(DS:$0b2a)                         drop the terminator from the length
```

`$E3` makes the card hand back its own ASCIIZ identification string, which
ends up as a Pascal `String[80]` at `DS:$0b2a`.

### `19a0:058b` — is there a mixer?

```
if DS:$0b84 <> 0 then exit             already known
if not Reset then exit
Old := ReadMixer($22)
WriteMixer($22, $F3)
if ReadMixer($22) = $F3 then DS:$0b84 := 1
WriteMixer($22, Old)                   put it back either way
```

Mixer register `$22` is the SB Pro master volume. Writing a known value and
reading it back is the standard **"is this a Pro?"** test, and the original
value is restored whichever way it goes.

### `19a0:0422` — stop

```
if DS:$0b82 <> 0 then
  if DS:$0b8d <> 0 then WriteDSP($D9, ...)     exit auto-init, 16-bit
  else                  WriteDSP($DA, ...)     exit auto-init, 8-bit
```

### `19a0:052b` — the output dispatcher

This is what `193a`'s interrupt handler calls.

```
if Count < 10 then exit
if DS:$0b8a <> 0 then Count := Count*2 - 1        stereo: twice the bytes
if DS:$0b82 <> 0 and (DS:$0b8a = 0 or DS:$0b8d <> 0) then
  PlayAutoInit(Mode, Count)          19a0:0699
else if DS:$0b8c <> 0 then
  PlayHighSpeed(Mode, Count)         19a0:04d3
else
  PlaySingleCycle(Mode, Count)       19a0:04a5
```

Three DMA paths, chosen from capability flags worked out at detect time:
`DS:$0b82` auto-init available, `DS:$0b8a` stereo, `DS:$0b8c` DSP 2.0+,
`DS:$0b8d` 16-bit. The `Count*2 - 1` for stereo is the byte count the DMA
controller wants, which is one less than the transfer length.

**`19a0` is complete.** All 23 routines read.

---

## `193a` — the Sound Blaster driver

1617 bytes, 19 routines.

### `193a:0014` — hand the core the card's ports

```
DS:$0be8 := DS:$0b02      DS:$0bea := DS:$0b06      DS:$0bec := DS:$0afe
```

Those three are what `1a17:104d`'s direct-DAC path writes to and reads back,
which is why this driver's poll slot can point at the core's shared routine.

### `193a:0030` — the interrupt handler

```
CLI, save AX/DS/DX, load our data segment
IN from DS:$0b06 and DS:$0afe          acknowledge the card
DS:$0b92 := 0
if DS:$0b90 <> 0 then
  begin DS:$0b91 := AL;  DS:$0ba6 := AL end
else
  begin save the rest; 19a0:052b(1, -$600); restore end
if DS:$0b16 = 10 then OUT $A0, $20     EOI to the slave first
OUT $20, $20                           and always to the master
IRET
```

### `193a:007f` — the sample rate, and how it is rounded

```
if Rate < 4000 then Rate := 4000
if DSP >= 2.0 and stereo and not auto-init and Rate > 21800 then
  Rate := 21800
TC   := HighByte(-(256_000_000 div Rate))
RateA := 1_000_000 div (256 - TC)
RateB := 1_000_000 div (256 - TC - 1)
choose whichever of RateA, RateB is nearer the Rate asked for
```

The Sound Blaster takes a **time constant**, not a rate: `TC = 256 −
1000000/Rate`. Doing the division scaled by 256 (`256_000_000`) keeps a byte
of extra precision, and then it works out what rate each of the two candidate
constants would actually produce and **picks the closer one** rather than just
truncating. 4000 is the floor; 21800 is the SB Pro's stereo ceiling when
auto-init is not available.

### `193a:02c2` and `193a:02e7` — mono and stereo probes

Identical but for the flag: stop the card, reset it, set `DS:$0bbd` to 0 or 1,
and report whether it came back. The stereo one additionally checks two more
`19a0` entry points before answering, so a card that resets but cannot do
stereo answers false.

### `193a:031f` — install

```
if DS:$09ee <> nil then exit                  already installed
DS:$0b8a := DS:$0bbd                          stereo, as the probe found it
stop / reset / speaker off
193a:0014                                      wire the ports to the core
DS:$0bc4 := DS:$0b18
1a17:1090(8, DS:$0b8a)                         tell the core the format
DS:$09ee := InstallIRQ(DS:$0b16, 193a:0030)
```

`DS:$0b16` is the card's IRQ and `DS:$09ee` holds the vector it displaced.

---

## `17cf` — the memory pool (in progress)

2832 bytes, 46 entry points — the largest routine count in the program, most
of them small.

### Pointer normalisation

```
17cf:0000  Norm(P, Delta) : Pointer
             Lin   := LongInt(Ofs(P)) + Delta
             Result.Seg := Seg(P) + (Lin shr 4)
             Result.Ofs := Lin and $0F
17cf:0052  Norm(P) : Pointer            the same with no delta
17cf:0081  another variant
```

Real-mode pointer arithmetic that has to survive crossing 64 KB: add the
delta in 32 bits, push the overflow into the segment, and keep the offset in
0..15. Everything in the pool that walks past a segment boundary goes through
these.

`17cf:0081` and `17cf:010c` are the linearise-and-compare pair already
described in `00-map.md` — `Linear(DS:$0c44) - Linear(DS:$0c40)` against a
requested size.

### The block objects

```
17cf:0698  constructor
             Avail := 1880:0097(Free, 1_000_000)     largest block, capped
             if Avail <> 0 then 17cf:01f1(sizes, Self)
             else                17cf:02c7(Self, VMT $73a)
17cf:06f2  destructor
             if Self^[2..5] <> nil then 1880:00cb(@Self^[2])
             dispose
17cf:071b  a second constructor, VMTs $772 and $7da
```

So the pool is a family of objects wrapping DOS memory blocks: `1880`
allocates and frees the blocks, `17cf` owns them and hands out sub-ranges,
and the audio buffer at `DS:$430a` is carved out of one of them.

### The pool is a `TCollection` of blocks

`Self^[+$12]` is an embedded collection, and two routines walk it with
`Objects`' own iterators — `1891:055b` (`ForEach`) and `1891:0520`
(`FirstThat`). This is the firmest evidence yet for the `1891 = Objects`
identification: the pool does not merely have collection-shaped fields, it
calls the iterators and passes them TP7 nested-procedure closures.

```
17cf:09bc   function ...  : LongInt
              Sum := 0                            [BP-8]
              Self^.Blocks.ForEach(@17cf:099f)
              Result := Sum

17cf:099f     the iterator body, far, RETF 6
                Sum := Sum + Item^.<VMT+$18>
```

`17cf:099f` reaches `Sum` through `SS:[DI-8]` where `DI` came from `[BP+6]` —
the **static link**. TP7 passes the enclosing frame's `BP` as an extra hidden
parameter to a nested procedure, and `ForEach` passes it straight through.
That is why the iterator is `RETF 6` (item pointer plus link) and not `RETF 4`.

`17cf:0a34` is the same shape over `FirstThat`, with `17cf:0a10` as the
predicate and `Item^.<VMT+$2c>` as the test.

### The four empty methods

`17cf:09f4`, `09fb`, `0a02` and `0a09` are each exactly seven bytes:

```
PUSH BP / MOV BP,SP / LEAVE / RETF 4
```

They take a `Self` and do nothing. These are **base-class virtual methods with
empty bodies**, not the "small pointer helpers" an earlier pass took them for —
the placeholders a derived pool type overrides. Four consecutive identical
stubs is what a block of `procedure X; virtual; begin end;` declarations
compiles to, and it accounts for a good part of this unit's unusually high
routine count without adding any behaviour.

---

## `1a17` — the player core

4303 bytes, 19 framed routines plus the naked shared poll. The public face is
now fully named.

### The tick

```
1a17:005d  SetTickHandler(Rate, Proc)
             PUSHF; CLI
             DS:$4312 := Proc            <- the hook 1a17:1008 and 1084:0000 call
             POPF
             DS:$0be2 := Rate
             RecalcDivisor

1a17:0015  RecalcDivisor
             if Rate = 0 then
               begin DS:$0be4 := 0;  DS:$0be6 := 0 end
             else
               begin
                 DS:$0be4 := DS:$0ba8 div Rate      the divisor
                 if DS:$0be4 = 0 then DS:$0be4 := 1  never zero
                 DS:$0be6 := 1
               end
             DS:$0bb2 := DS:$0bb4

1a17:0176  SetSecondHook(P)     DS:$4316 := P, with interrupts off
```

`DS:$4312` is the one that matters: everything that polls — the core's shared
routine, the GUS driver's own handler — ends up calling through it. The
clamp to a minimum divisor of 1 is the sort of thing that stops a
divide-by-zero turning into a hung machine.

### The system timer

```
1a17:007b  restore PIT counter 0 to mode 3, reload 0     the BIOS default
1a17:0086  release the INT 8 hook
             if DS:$0c0a <> 0 then
             begin
               SetIntVec(8, DS:$0c06)     the vector it displaced
               RestorePIT
               DS:$0c0a := 0
             end
```

So the core can take **IRQ 0 itself** when a driver has no interrupt of its
own, reprogramming the PIT and putting both back on the way out.

### `1a17:013e` — Stop

```
if DS:$0b96 <> nil and running then
begin
  FillChar(Buffer^, DS:$0ba4, $80)     silence first, so nothing clicks
  CLI
  Driver^.Method_32                    the driver's stop
  ReleaseTimer                         1a17:0086
  STI
  DS:$0bb6 := 0
end
```

That names another driver slot: **`+$32` is Stop**, which matches `1084:00d5`
calling the GUS uninstall and reset. Filling the buffer with silence *before*
stopping rather than after is deliberate — whatever the card is still playing
out of it is quiet.

### The driver record, as far as it is now known

| offset | what |
|---|---|
| `+$16` | clear a byte through a pointer |
| `+$1a` | **probe** — false means the hardware answered |
| `+$1e` | **start** |
| `+$22` | (empty in the GUS driver) |
| `+$26` | returns its argument |
| `+$2a` | **poll** — the timer, and INT 2Fh function 2 |
| `+$2e` | (empty in the GUS driver) |
| `+$32` | **stop** |
| `+$36` | `Next` in the driver list |

`1a17:0001` returns a zero `LongInt` and is what the two hook slots are set to
before anything real is installed.

### `1a17:037f` — set the tick rate, and check what you got

```
Rate := ClampRate(Rate)                      1a17:02fb
if Rate = 0 then DS:$0bb4 := $FFFF
else
begin
  DS:$0bb4 := 1_193_180 div Rate             the PIT divisor
  DS:$0ba8 := 1_193_180 div DS:$0bb4         the rate that actually gives
  DS:$0bac := DS:$0ba8
end
```

The effective rate is computed **back from the divisor** rather than assumed
to be what was asked for — the same care `193a:007f` takes over the Sound
Blaster's time constant. Everything downstream that needs "how many ticks a
second" reads `DS:$0ba8`, not the request.

### `1a17:03d2` — the buffer queue

```
if DS:$0c0c > 0 then exit                    re-entrancy guard
Inc(DS:$0c0c)
if DS:$431a <> nil then DS:$0c0e := DS:$431a^[1]
DS:$431a := DS:$431e                         advance to the next block
if DS:$431a = nil then
begin
  DS:$431a := CALLF [DS:$4316]               ask the second hook for more
  if DS:$431a <> nil then DS:$431a^[0] := 1  and mark it in use
end
```

`DS:$431a` is the block being played and `DS:$431e` the one behind it; when
the queue empties, the **second hook** (`DS:$4316`, installed by
`1a17:0176`) is called to produce another. That is the double-buffering that
keeps a DMA card fed — one block playing while the next is mixed.

### `1a17:1087` and `1a17:1090` — choose the output routines

```
1a17:1087   P := $0d7c                       mono, unconditionally
1a17:1090   P := Stereo ? $0dfc : $0d7c
both        DS:$0c00 := P                    the mixing routine
            DS:$0bf8 := $0f64
            DS:$0bfa := $104d                <- the direct-DAC path
            DS:$0bfc := $1063
            DS:$0bfe := $107c
```

A four-entry jump table of output primitives plus the mixer selection, all by
address within `1a17` itself. `193a:0352` calls `1a17:1090(8, stereo)` when
the Sound Blaster comes up, which is how the card's stereo capability reaches
the mixer.

**`1a17` is complete** apart from the mixing routines at `$0d7c`/`$0dfc` and
their helpers, which are the naked (frameless) code the prologue scan does not
see.

### `17cf:01f1` — initialise a pool block

```
if not Allocate then exit nil
TObject.Init(Self)                       1891:0000
if Size <= 0 then exit
Self^[$0a] := Norm(Base, Size)           17cf:0000, then cleared again
P := Norm(Base)                          17cf:0052
if Ofs(P) <> 0 then
begin Seg(P) := Seg(P) + 1;  Ofs(P) := 0 end     round UP to a paragraph
Self^[2] := P                            base
Self^[6] := P                            current
```

So the block object is `+2` base, `+6` current, `+$0a` end — and the base is
**rounded up to a paragraph boundary**, never down, so the block never starts
before the memory it was given. Everything the pool hands out is therefore
paragraph-aligned, which is what the DMA buffer needs.

That completes the picture of `17cf`: `1880` gets blocks from DOS, `17cf`
wraps each in an object that normalises and aligns it, and sub-ranges are
handed out from `+6` onwards.

---

## `142f` — notes and effects

2176 bytes, 17 routines.

`142f:0000` (already described in `00-map.md`) turns a period into a rate via
the table `1650` built. The rest are per-effect handlers, and they share one
shape:

```
if Note^[5] <> 0 then
begin
  Voice^[$1f] := Note^[5]          remember this parameter
  Voice^[$22] := 0
end
else if Voice^[$22] <> 0 then
begin
  Voice^[4] := <the effect code>   $12 at 142f:00cc, $13 at 142f:011b
  Apply(Note, Voice, Channel)
end
```

That is the tracker convention where **a parameter of zero means "reuse the
last one"** — `+$1f` holds the remembered value and `+$22` says whether there
is one. Every effect that takes a parameter goes through this.

The frameless helper at `142f:016a` shows what one of them then does:

```
Voice^[1] := Voice^[1] - Voice^[$1f]     the period
Voice^[$0b] := Voice^[1]
```

Subtracting from the period **raises** the pitch, so that pair is portamento
up and its neighbour is portamento down.

---

## `14b9` — the module object

2224 bytes, 16 routines.

The object triple at the top (`0000` constructor, `002b` destructor, `004f`
header load) is in `00-map.md`. Two more are worth writing out.

### `14b9:0106` — set the file name

```
S := Name
SaveA, SaveB := Self^[2], Self^[4]        stash two fields
14b9:02c2 ; 14b9:0897 ; 14b9:02f5         clear the extension, reset state
Self^[2], Self^[4] := SaveA, SaveB        put them back
S := FExpand(S)                            1b6f:0178
FSplit(S, Self^[$16], Self^[$1f], ...)     1b6f:0241
```

The object keeps the path split into its own fields at `+$16` and `+$1f`
rather than holding the string whole, and it expands to a full path first so a
relative name given on the command line still resolves after a directory
change. That also pins `1b6f:0178` down as `FExpand`.

### `14b9:04b6` and `14b9:0404` — get item N, growing the list to reach it

The same routine written out twice, once per collection. An earlier pass read
`04b6` as "get channel N"; following `154d` and `165a` through shows it is the
**pattern** list, and that `0404` is its twin for **tracks**.

```
function GetOrMake(N : Word; Self) : Pointer;   far; RETF 6

if N < Count then                               already exists
  Result := At(N, @Coll)                        1891:0405
else
begin
  Want := N;  I := Count
  if Count > Want then Result := At(N, @Coll)
  else
    repeat
      Inc(I)
      Obj := nil
      Pool.Alloc(@Obj, <size>)                  the pool at DS:$397e, VMT+$08
      if Obj <> nil then
      begin
        <constructor>(Obj)
        Insert(I, Obj, @Coll)                   1891:047a
      end
    until I = Want;
  Result := Obj
end
```

| | patterns (`04b6`) | tracks (`0404`) |
|---|---|---|
| collection | `Self^[$41]` | `Self^[$4d]` |
| count | `Self^[$47]` | `Self^[$53]` |
| record size | 10 bytes | 14 bytes |
| VMT (DGROUP offset) | `$0576` | `$056e` |
| constructor | `165a:0baa(Self^[$28], …)` | `165a:081d(…)` |

The list is **extended lazily** — asking for an item that does not exist yet
creates it and everything before it, then returns it. That is why `154d` can
load patterns in file order without ever telling the module how many there
will be.

The two record sizes are an independent check on `165a`: a pattern is VMT,
pool handle, block pointer = 10 bytes, and a track is VMT, pool handle, note
stream, effect stream = 14. Both agree exactly.

**This also confirms the `Objects` field layout.** The count is read at
`Coll + 6` while the collection itself starts at `Coll + 0` — so `TCollection`
is VMT at `+0`, a far `Items` pointer at `+2`, and `Count` at `+6`, which is
precisely the layout `02-functions.md` inferred for `1891` from the
`Init(1,1)` call shape. Two unrelated sites now agree on it.

One correction to an earlier note: `Insert` is `1891:047a`, not `1891:048a`.
`At` at `1891:0405` was right.

Note also that `14b9` allocates through a **different pool object** —
`DS:$397e` — from the one `165a` uses for stream data, `DS:$39ae`. Both are
reached by the same `VMT+$08` / `VMT+$0c` pair, so they are the same class;
the module's structural records and the bulk note data come out of separate
arenas.

### Three collections, one template

`14b9:0352` is the same routine a third time, for samples. All three are
identical but for four constants:

| | samples (`0352`) | patterns (`04b6`) | tracks (`0404`) |
|---|---|---|---|
| collection | `+$29` | `+$41` | `+$4d` |
| count | `+$2f` | `+$47` | `+$53` |
| record size | 10 | 10 | 14 |

That is what `00-map.md` already called "make or fetch sample slot I" — it is
the same lazy-growth idiom, written out three times because the constants
differ and there is no way to parameterise them without an indirection this
code will not pay for.

### The module record

Assembled from every site that touches it:

| offset | |
|---|---|
| `+$02` | speed, reset to 1 |
| `+$04` | tempo-ish word, reset to `$100` |
| `+$06` | a pool handle |
| `+$0a` | pool handle for the **title** string |
| `+$0e` | a `$3d0`-byte pool block |
| `+$12` | a pool handle |
| `+$16` | the path, from `FSplit` |
| `+$1f` | the file name, from `FSplit` |
| `+$28` | **channel count**, 4..8 |
| `+$29` | sample collection — count at `+$2f` |
| `+$39` | far pointer to the **order table**, 256 bytes |
| `+$3d` | far pointer to a second 256-byte byte table |
| `+$41` | pattern collection — count at `+$47` |
| `+$4d` | track collection — count at `+$53` |
| `+$59` | status / error code |
| `+$5d` | format id |

### `14b9:059f` and `14b9:05d3` — the two byte tables

```
if Self^[$39] = nil then Result := 0
else Result := Self^[$39]^[Order - 1]
```

Both are the same three lines against different fields. The `- 1` matters:
these tables are indexed **one-based**, which is consistent with the track
numbering `154d` hands out starting at 1 and with `165a:0ab8` decrementing the
row before use. Positions, rows and track numbers are all one-based
throughout, and zero is reserved to mean "nothing".

`+$39` is the order table — `059f` feeds its result straight to `04b6` as a
pattern number. What `+$3d` holds is not settled by these two routines alone;
it is allocated and freed as another 256 bytes alongside the order table, and
read the same way. Left unnamed.

### `14b9:0607` — fetch one event

This is where the whole storage model pays off, and it is only six steps:

```
procedure GetEvent(Order, Row, Chan : Word; var Ev; Self);  far; RETF $0E

if Self^[$39] = nil then goto Empty
Pat := 14b9:0575(Order, Self)         { = 04b6(059f(Order)) -- order -> pattern }
if Pat = nil then goto Empty
H  := Pat^[+6]                        { the pattern block }
Track := 14b9:0404(H^[2 + Chan*2], Self)
if Track = nil then goto Empty
165a:0ab8(Row, @Ev, Track)            { the trimmed-stream row reader }
exit
Empty:
FillChar(Ev^, 6, 0)
```

`H^[2 + Chan*2]` is exactly the slot `154d` wrote at load time, and
`165a:0ab8` is exactly the inverse of `165a:08e2`. Loading and playing agree
on the layout at every step; neither owns it, which is why reading them
together is what made the format legible.

Every failure path lands on the same `FillChar`. A missing pattern, a missing
track, a module with no order table at all — all produce a silent empty row
rather than an error, so the player never has to check.

### `14b9:0687` — tear the module down

Interesting mainly for its brackets:

```
CLI
  Pool.Release(@Self^[$06])            VMT+$34
  Pool.Free(@Self^[$0e], $3d0)
  Pool.Release(@Self^[$12])
  Self^[$29].Done                      the sample collection, VMT+$04
  Pool.Free(@Self^[$39], $100)         the order table
  Pool.Free(@Self^[$3d], $100)         the second table
  Self^[$41].Done                      patterns
  Self^[$4d].Done                      tracks
STI
```

The `CLI`/`STI` is the point. The INT 1Ch hook is reading these same fields
four times a tick, so the teardown has to be atomic against it — there is no
"stop the player first" step, the interrupt is simply locked out for the
duration.

### `14b9:02c2` / `14b9:02f5` — the title

`02c2` reads it (`S := Self^[$0a]^`, or empty if the handle is nil) and `02f5`
writes it: copy to a local first, release the old handle through the pool's
`VMT+$34`, then — only if the new string is non-empty — acquire a new one
through `VMT+$30` and store it at `+$0a`.

Copying to a local before releasing is what makes `SetTitle(GetTitle)` safe.
It also pins down two more pool methods: **`VMT+$30` acquires**, **`VMT+$34`
releases**, which is the `Manager.Acquire(Title)` that `00-map.md` recorded
against `154d:09d7` without knowing what it was.

---

## `116e` — the command line

1232 bytes, eight routines.

### `116e:04b2` — fetch the tail

Copies from `PSP:$0080`, max `$7F`. Already noted in `00-map.md`.

### `116e:02dd` — the tokeniser

The parser state is a record: the text as a `String` at `+2`, and a **cursor
word at `+$146`** just past it.

```
Out[0] := 0                                empty the output token
Len := Length(Self^.Text)
if Cursor > Len then exit
I := Cursor
skip characters that appear in the delimiter set at CS:$02bd
collect characters that do not
copy them into Out, and leave Cursor just past the token
```

The delimiter test goes through the RTL's character-in-set helper, so the set
is data rather than a chain of comparisons.

### `116e:03a9` — match a keyword, case-insensitively

```
Key := the keyword, max 4 characters
for I := 1 to Length(Key) do
  if UpCase(Src[I]) <> UpCase(Key[I]) then exit False
Result := True
Src := Copy(Src, Length(Key) + 1, 255)      strip what matched
if Src[1] = ':' then Src := Copy(Src, 2, 255)   and an optional colon
```

`1ba1:1071` is the RTL's `UpCase`. Two things fall out of this.

The **four-character limit** is why `11bb`'s boolean words are stored as
four-character stems — `TRUE`, `FALS` beside `VERD`, `CIER`, `TAMB`, `TAMP`.
One comparison then covers `verdadero`, `cierto`, `falso`, `tampoco` and
`también` regardless of how they are spelled out.

And because the matcher **consumes what it matched**, including a following
colon, a config line can be written as `Port: 220` or `Port 220` and parse
the same way. That is the whole of `NEUROSIS.CFG`'s syntax.

**`116e` is complete.**

---

## `109c` — the playlist

3296 bytes, 25 routines. `109c:0000`, `0038`, `0048` and `0724` are in
`00-map.md`. **Complete.**

### `109c:07ae` — add a name to the playlist

```
S := Name
P := 1891:0963(S, Playlist.Count)      construct an entry object
Playlist.Insert(P)                     1891:047a
```

### `109c:07e1` — add an entry with its parameters

```
S := Name
DS:$3ade := S                                   max $4F
Tail := Copy(Self^.Text, Self^.Cursor, 255)     whatever is left on the line
DS:$08c8 := Tail                                max $7F
Self^.Method_10
```

That closes the shell-out loop. `PlayModule` at `1000:03af` calls
`1b6f:00df(DS:$3ade, DS:$08c8)` — `Dos.Exec` — so **`DS:$3ade` is the program
to run and `DS:$08c8` its command line**, and both are filled in here from a
config line: the name, then everything after it on the same line.

`1931`'s `COMSPEC` lookup writes into `DS:$3ade` too, so an entry with no
program of its own falls back to the command interpreter.

That is the whole mechanism by which `PSYCHO.EXE` gets each demo part run:
`NEUROSIS.CFG` names the file, DemoVT loads the module from it, and then
shells out to the same file as a program.

### `109c:03fb` .. `109c:06f0` — the option setters

The whole run is one table of handlers, one per config keyword — the
procedures the keyword matcher dispatches to. Three shapes, distinguishable by
their `RET`:

**`RET 4` — takes a `String`.** Copy it to a local, run `Val` (`1ba1:0f81`),
and store the number only if the conversion code came back zero:

| routine | stores to |
|---|---|
| `109c:0435` | `DS:$0bae` |
| `109c:047c` | `DS:$0b14` **and** `DS:$0582` |
| `109c:04ca` | `DS:$0b16` **and** `DS:$0584` |
| `109c:0518` | `DS:$0b18` |
| `109c:05bc` | `DS:$08ba`, clamped to `$FF` and stored as a byte |
| `109c:0645` | `DS:$08c2` |
| `109c:068c` | `DS:$08c6` |
| `109c:06dd` | `DS:$08c4` |

`109c:03fb` is the odd one: its value is kept as a **20-character string** at
`DS:$0882` rather than converted, and it then calls `109c:09c0`.

The three that write two places are the hardware settings, and one of them
pins the whole group down: **`DS:$0582` is the GUS base port**, because
`1723:0003` reads it as `MOV DX,[0x582] / ADD DX,$102 / OUT DX,AL`. So
`DS:$0b14`, `$0b16`, `$0b18` are where the config file's values are kept and
`DS:$0582`, `$0584` are the live copies the driver actually reads.

**`RET 2` — takes a byte, stores it, nothing else.**

```
109c:0611  -> DS:$08c0      109c:061e  -> DS:$02c9
109c:062b  -> DS:$0564      109c:0638  -> DS:$0bbb
```

**`RET 0`** — a bare switch with no value: `109c:05b2` sets `DS:$09e8 := 1`
and `109c:06d3` sets `DS:$0bc6 := 1`.

A malformed number is silently ignored: `Val` fails, the store is skipped, and
the previous value stands. There is no diagnostic anywhere in the run.

### `109c:0c5e` / `109c:0c9d` — options are per playlist entry

The pair that makes the table above worth having. Each is `RETF 8` and copies
between the globals and a 26-byte block held on the playlist entry:

```
109c:0c5e   SAVE                        109c:0c9d   RESTORE
  Rec[$00]    := DS:$0564                 DS:$0564 := Rec[$00]
  Rec[$01..$15] := DS:$0882               DS:$0882 := Rec[$01..$15]   20 chars
  Rec[$16]    := DS:$0bae                 DS:$0bae := Rec[$16]        word
  Rec[$18]    := DS:$08ba                 DS:$08ba := Rec[$18]        byte
  109c:09c0                               109c:09c0
```

So the options are **global while a module plays but snapshotted per entry**:
the playlist saves the current settings into the entry it is leaving and
restores the ones belonging to the entry it is entering. That is how a single
config file gives each demo part its own settings without the player carrying
a context object around.

Both directions end in the same call to `109c:09c0`, which is therefore the
"the options changed, recompute" hook rather than part of either operation.
`109c:03fb` calls it too, for the same reason.

---

## `165a` — samples, patterns and tracks

3216 bytes, 15 routines. `005d`, `012a` and `07c0` are described in
`00-map.md`. **Complete.**

The unit's name in `00-map.md` is too narrow: it holds three things, not one —
the sample descriptor and its two conditioning passes, the **pattern** object,
and the **track** object. The last two are what `154d` builds the module out
of.

### The sample descriptor

Read out of `165a:037a` and `165a:0583` together, which index it identically:

| offset | |
|---|---|
| `+$00` | length, `LongInt` |
| `+$04` | loop start, `LongInt` |
| `+$08` | loop length, `LongInt` |
| `+$0c` | volume — `165a:012a` clamps it to 63 |
| `+$12` | far pointer to the sample data, 8-bit signed |

### `165a:037a` and `165a:0583` — the two conditioning passes

These are a **matched pair**, and reading them together is what settles what
each one is. Their guards are exact complements:

| | `165a:0583` | `165a:037a` |
|---|---|---|
| length | `< $80` | `> $80` |
| loop | loop length `> 0` | loop length `= 0`, or `>= $7d0` |

Every sample falls to one or the other or to neither; neither routine can see
a sample the other could.

**`165a:0583` triples the loop.** It allocates `LoopLen*3 + LoopStart` bytes
from the pool, copies the head and the first loop pass, then lays the loop
body down twice more:

```
New := Pool.Alloc(LoopLen*3 + LoopStart)
for I := 0 to LoopStart + LoopLen - 1 do New[I] := Old[I]
for I := LoopStart to LoopStart + LoopLen - 1 do
begin
  New[I + LoopLen]     := Old[I]
  New[I + LoopLen * 2] := Old[I]
end
```

With three consecutive copies of the loop in memory, the resampler can run
past the loop end — and interpolate across it — without a per-sample wrap
test, and only needs to subtract one loop length when it drifts too far. That
is why it is worth spending memory on, and why it is restricted to samples
**shorter than 128 bytes**: those are the ones where the loop is tight enough
that the test would cost more than the copies.

**`165a:037a` halves the sample.** This closes the question left open in the
earlier pass. It is a downsampler, not a peak scan and not a loop fixup:

```
N := (Length div 2) - 1
for I := 0 to N do
  Data[I] := (SignExtend(Data[I*2 + 1]) + SignExtend(Data[I*2])) div 2
```

It reads **pairs** of 8-bit signed samples and writes their average back at
index `I` — so the output index advances by one while the input advances by
two. The earlier reading of "16-bit samples, high byte taken" was wrong: both
bytes are used, and `CBW` appears twice because both are sign-extended before
being added. The `IDIV` by 2 rather than a shift is what makes it round toward
zero instead of toward negative infinity.

Afterwards it normalises `Data + Length div 2 + 7` to paragraph form with the
`17cf` idiom (`SHR AX,4` folded into the segment, offset masked), works out how
many bytes that released, and subtracts them from the length. So the sample is
halved **in place** and the tail handed back to the pool.

The cost is an octave of bandwidth on the big samples; the gain is half their
memory. The guard says exactly which samples that trade is made for: long ones
that either do not loop, or whose loop is at least 2000 bytes and so survives
being halved.

### `165a:081d` / `165a:083f` — the track object

A plain constructor/destructor pair. The constructor is the TP7 shape —
`XOR DI,DI`, `CALLF 1ba1:04f5`, bail out returning nil if that fails, then the
ancestor's `Init` at `1891:0000`. The destructor releases the pool handle at
`Self^[+2]`, calls `165a:0876`, runs the ancestor `Done` at `1891:0031`, and
finishes with `@ObjDispose`.

The track record:

```
+$00   VMT
+$02   a pool handle, released by the pool's method at VMT+$34
+$06   far pointer to the NOTE stream   (nil if the track has no notes)
+$0a   far pointer to the EFFECT stream (nil if it has no effects)
```

### `165a:08e2` — storing a track, and the stream format

Called by `154d` with the 256-entry event array. `RETF 8`. The frame is
`ENTER $606,0`: a `$402` byte staging buffer for notes and a `$202` one for
effects, both cleared first.

It walks all 256 rows once, building each stream as `FirstRow`, `Count`, then
the data:

```
for I := 0 to $FF do
begin
  if (Ev[I][0] = 0) and (word Ev[I][1] = 0) and (Ev[I][3] = 0) then
    { empty }  if Note.FirstRow = I then Inc(Note.FirstRow)
  else
  begin
    Note.Count := I - Note.FirstRow + 1;
    Note.Data[I - Note.FirstRow] := 4 bytes from Ev[I][0..3]
  end;
  { the same again for Ev[I][4..5] into the effect stream, 2 bytes wide }
end
```

`FirstRow` only advances while every row so far has been empty, and `Count`
only advances when a row is not — so each stream ends up **trimmed at both
ends**. A track whose only content is a note in row 0 and an effect in row 60
stores one note entry and one effect entry, not sixty-four of each.

The two streams are trimmed **independently**, which is the point: notes and
effects rarely occupy the same rows, and paying for the union of their ranges
would waste most of the saving.

Then it frees whatever was there (`165a:0876`), asks the pool for exactly
`Count*4 + 2` and `Count*2 + 2` bytes, and `Move`s the staging buffers in.

`165a:0876` is the matching release: it frees each stream using the size
recomputed from the stream's own `Count` byte, so the size never has to be
stored anywhere.

### `165a:0ab8` — reading a row back

`RETF $0A`; `Row` at `[BP+$e]`, the destination event at `[BP+$a]`, `Self` at
`[BP+6]`. The exact inverse:

```
Dec(Row)                                   rows arrive one-based
FillChar(Ev^, 6, 0)
if Notes <> nil then
  if (Notes^.FirstRow <= Row) and (Notes^.FirstRow + Notes^.Count > Row) then
    move 4 bytes from Notes^.Data[(Row - Notes^.FirstRow) * 4] into Ev^[0..3]
if Fx <> nil then
  if (Fx^.FirstRow <= Row) and (Fx^.FirstRow + Fx^.Count > Row) then
    move 2 bytes from Fx^.Data[(Row - Fx^.FirstRow) * 2] into Ev^[4..5]
```

The `FillChar` first is what makes the trimming free: a row outside either
range simply keeps the zeros, which is already the "nothing here" encoding
that `154d` established.

### `165a:0baa` / `165a:0c1c` / `165a:0c53` — the pattern object

The same constructor shape, but this class is the **pattern**, not the track —
`14b9:04b6` calls `165a:0baa`, and `14b9:04b6` is what `154d` calls to make
pattern *N*. Its one parameter is the channel count.

```
Pool.Alloc(@Self^[+6], Chans*2 + 4)
if it succeeded then
begin
  FillChar(that block, Chans*2 + 4, 0);
  Block^[1] := Chans
end
```

`Chans*2 + 4` is `2 + Chans*2 + 2`: the two header bytes, one word per
channel, and the unused word at `+2` that exists only because the channel
index is one-based. That is precisely the block `154d` then fills in with
`H[0] := $40`, `H[1] := NumChan` and `H[2 + Chan*2] := TrackNo`.

`165a:0c53` frees it with `Count*2 + 4` — the same formula read back from the
stored `Chans` byte, matching the allocation exactly.

The two classes are worth keeping apart: both keep a pool handle at `+2` and a
block at `+6`, and both were built from the same template, but the track's
block is `Count*4 + 2` and the pattern's is `Chans*2 + 4`. Reading one of them
with the other's formula makes it look like an allocation bug, and it is not.

---

## `154d` — the ProTracker loader

3920 bytes, five routines, all large. `154d:0bf7` (the signature check at
offset 1080) is in `00-map.md`. **Complete.**

One detail belongs with the signature check rather than below: `154d:0bf2`
holds the Pascal string `'.WOW'`, compared against the four bytes at offset
1080 alongside `M.K.`. A match sets `Song^[$28] := 8` and the format id
`Song^[$5d] := 7`; anything else falls back to `4` and `1`. That is Mod's
Grave Composer's eight-channel variant, and it is the only place the loader
admits more than four channels from the signature alone.

### `154d:04e2` — the sample headers

```
Move(Header^, Local, $43C)                     the whole 1084-byte header
for I := 1 to 31 do
begin
  FillChar(Desc, $1C, 0)                       a 28-byte descriptor
  Item := 14b9:0352(I, Song)                   make or fetch sample slot I
  if Item = nil then begin Song^[$59] := 4; exit end
  Name := ZToStr(Local + I*$1E, $16)           22 characters
  W := WordAt(Local + I*$1E + ...)
  XCHG AH, AL                                  <- byte swap
  W := W * 2
  ...
end
```

Two things here are the format, not the code. `$1E` is **30**, the size of a
MOD sample header, and `$16` is **22**, its name field. And the `XCHG AH,AL`
is there because **MOD stores its word fields big-endian** — the format came
off the Amiga — so every length and loop point has to be swapped on a PC. The
`* 2` after it is because those fields count **words, not bytes**.

### `154d:09d7` — recognising a module with no signature

A 15-sample module predates the `M.K.` marker, so there is nothing to compare
and it has to be identified by whether the header is plausible:

```
Song^[$59] := 5                                assume unrecognised
for I := 0 to $7F do
  if Header[$3B8 + I] > $3F then fail          pattern order: 128 bytes, each <= 63
for I := 1 to $14 do
  if Header[I-1] < $20 and <> 0 then fail      title: 20 chars, printable or NUL
if Header[$3B6] > $80 or Header[$3B7] > $80 then fail    length and restart
Song^[$59] := 1                                it is a module
Title := ZToStr(Header, $14)
Song^[6..9] := Manager.Acquire(Title)
Song^[$25] := 6
Song^[$26] := $7D
```

Three independent sanity checks on fields that a non-module would almost
certainly violate, and then it commits. The two constants at the end are
**speed 6 and tempo 125** — ProTracker's defaults, which a module with no
header to state them in has to be given.

`ZToStr` here is `1642`, the fixed-width ASCIIZ converter read earlier: the
title is a 20-byte NUL-padded field and this is what makes it printable.

### `154d:0b72` — the 15-sample fallback

Short, and it settles what the older Soundtracker path does. `RET $0C`, three
far pointers; `Song` is `[BP+4]`, the stream `[BP+8]`.

```
Move(Song^ + $1d6, Song^ + $3b6, $82)          the pattern order, moved up
for I := $11 to $1f do
  FillChar(Song^ + I*$1e - $0a, $1e, 0)        sample slots 16..31, cleared
Pos := Stream^.GetPos                          the virtual at VMT+$10
Stream^.Seek(Pos - $43c + $258)                the virtual at VMT+$1c
154d:09d7(...)                                 hand on to the recogniser
```

Every constant is the format. A 31-sample module's header is
`20 + 31*30 + 130 = 950 = $3b6`; a 15-sample one is `20 + 15*30 + 130 = 600 =
$258`. The order block therefore sits at `$1d6` in the old layout and `$3b6`
in the new one, and moving those **130 bytes** — song length, restart, and the
128 order entries — is the whole conversion. The 15 slots that never existed
are zeroed rather than left holding whatever the read left there.

The seek is the same arithmetic from the other end: the caller has already
consumed `$43c` (1084) bytes looking for a signature it did not find, so
`Pos - $43c + $258` rewinds to exactly the start of the pattern data **as a
15-sample module measures it**. Nothing is re-read; the file pointer is simply
moved back to where the older format's data begins.

So the loader reads one layout, discovers it was the other, rearranges the
header in place and rewinds — rather than parsing twice.

### `154d:0000` — patterns into tracks

Near, `RET $0A`: `Song` at `[BP+$0a]`, `Stream` at `[BP+6]`, `PatCount` at
`[BP+4]`. The frame is `ENTER $0E20,0`, and almost all of it is two buffers —
a **2048-byte raw pattern buffer** at `[BP-$800]` (64 rows x 8 channels x 4
bytes) and a **1536-byte event buffer** at `[BP-$0E00]`.

`Song^[$28]` is the **channel count**, and this routine is where that is
proved: it is used as a loop bound of 1..8, as a read length, and as the
selector for the stride table below.

```
for Pat := 1 to PatCount do
begin
  P := 14b9:04b6(Pat, Song)                    make pattern Pat
  if P = nil then begin Song^[$59] := 4; exit end     out of memory
  H := P^[+6]                                  the pattern header
  H[0] := $40                                  64 rows
  H[1] := Song^[$28]                           channels
  H[2] := 0;  H[3] := 0
  Stream^.GetPos                               VMT+$10 -- RESULT DISCARDED
  Stream^.Read(Raw, Song^[$28] shl 8)          VMT+$18; NumChan*256 bytes
  if Stream^[2] <> 0 then begin Song^[$59] := 2; exit end   read error
  ...
```

`NumChan shl 8` is `64 * NumChan * 4` — the whole pattern in one read.

**The stride expansion.** On disk the cells of a row are packed at the module's
own channel count; in memory DemoVT wants a fixed stride of 32 so that indexing
never has to multiply by a variable. So it widens the buffer in place, walking
**backwards** — row 63 first, channel N first — so that the moves never
overtake themselves:

| `Song^[$28]` | source stride | how it is computed |
|---|---|---|
| 4 | 16 | `SHL DI,4` |
| 5 | 20 | `IMUL DI,$14` |
| 6 | 24 | `IMUL DI,$18` |
| 7 | 28 | `IMUL DI,$1c` |
| 8 | 32 | nothing to do — falls straight through |

The destination is always `SHL DI,5`, i.e. 32. Five separate code paths for
what is one multiply, because a multiply by a constant is a shift and a
variable one is not — the same instinct as the mixer's unrolled loop.

**The cell conversion.** Then, per channel, each 4-byte ProTracker cell becomes
a 6-byte event:

```
Event[0]   := (Cell[0] and $10) + (Cell[2] shr 4)      sample, split nibble
Event[1:2] := ((Cell[0] and 7) shl 8) + Cell[1]        the 12-bit period
Event[3]   := untouched -- left zero by the FillChar
Event[4]   := (Cell[2] and $0f) + 1                    effect, made 1-based
Event[5]   := Cell[3]                                  parameter
```

`Event[4]` being one-based is what makes **zero mean "no effect"**, and the
routine leans on that immediately: an arpeggio (`$0`, stored as 1) with a zero
parameter is rewritten to effect 0, so the player never has to test for it.

Effect `$E`, whose real identity is in its high parameter nibble, is unpacked
into the numbering rather than left to the player:

```
if Event[4] = $0f then                          PT effect $E
begin
  Event[5] := Cell[3] and $0f;
  Event[4] := (Cell[3] shr 4) + $11             $11 .. $20
end
```

So DemoVT's effect space is flat: 1..$10 are ProTracker `0`..`F`, and $11..$20
are the sixteen `E` sub-effects. `142f` dispatches on one number.

Three more fixups, all of them format quirks rather than code:

- `$0d` (PT `C`, set volume) is **clamped to $40**. A module may ask for more.
- `$0c` (PT `B`, position jump) has its parameter **BCD-decoded** —
  `(hi*10 + lo) + 1`. ProTracker wrote that position as if the hex digits were
  decimal, and this is where that is undone, once, at load.
- `$0e` (PT `D`, pattern break) is masked to `$3f` and made one-based.

And both of the jump effects **truncate the pattern**:

```
if (Event[4] = $0e) or (Event[4] = $0c) then
  if H[0] > Row+1 then H[0] := Row+1
```

A pattern that breaks at row 12 is stored as twelve rows long. The player then
needs no per-row test for the end of a pattern at all — it just runs out.

**Tracks, not patterns.** The last step is the one that shapes the whole
format:

```
  for Chan := 1 to Song^[$28] do
  begin
    T := 14b9:0404(TrackNo, Song)              make track number TrackNo
    if T = nil then begin Song^[$59] := 4; exit end
    165a:08e2(Events, T)                       hand the 64 events over
    H[2 + Chan*2] := TrackNo                   the pattern refers to it
    Inc(TrackNo)                               a single global counter
  end
end
```

A pattern is not a block of note data. It is a **header plus one track number
per channel**, and the track data lives in its own numbered collection. Track
numbers run from 1 across the whole module, never reset per pattern.

That is a tracker's data model rather than a MOD file's, and it explains the
`14b9` object's two parallel "make me item N" methods (`0404` and `04b6`) that
looked redundant from the outside.

One genuine oddity, recorded as found: the `Stream^.GetPos` at `154d:0093` has
its result stored to a local pair that nothing ever reads. It is a dead store,
not a disguised side effect — the same virtual is called for its value in
`0b72`.

---

## `12ba` — the mixer (in progress)

5968 bytes, 19 framed routines plus the frameless kernels. The unrolled
resampling loop at `14c9` is in `00-map.md`.

**Complete.**

The unit's name is too narrow, and this is the correction the last pass
produced. `12ba` holds **two independent output paths**, and which one runs
depends on the driver:

```
  software mixing (SB and the rest)      GUS
  ---------------------------------      ------------------------------
  0b29   per tick, per channel           0275   post a voice event
    │                                      │    into a 25-slot ring
    ▼                                      ▼
  0007   mix one voice                   02ea   flush one slot to the GUS
    │                                      │
    ▼                                      ▼
  1600   the frameless kernel            1723:08e6 / 1723:0980
    │
    ▼
  1544   the one-pole filters
```

The GUS plays from its own DRAM, so there is nothing to mix for it — `12ba`
schedules voice commands instead, and the ring is what gives that scheduling
its look-ahead. Everything documented before this pass (`132f`, `14c9`) is on
the software side.

### `12ba:0000` — an empty virtual

```
PUSH BP / MOV BP,SP / LEAVE / RET 6
```

Takes two parameters and does nothing with them — the same do-nothing-method
pattern as the four stubs in `17cf`, and worth noting only so that it is not
mistaken for a missed routine.

### `12ba:0007` — mix one voice

Not an event handler — `[BP+8]` is a **voice record** and `[BP+4]` the output
buffer. This is the loop that drives the frameless resampling kernel at
`12ba:1600`.

The voice record, as this routine indexes it:

| offset | |
|---|---|
| `+$00` | flags: bit 1 active, bit 2 looping, bit 6 finished |
| `+$01` | the kernel's own state block — passed by address |
| `+$03` | position within the current run, in samples |
| `+$0b` | the end position, for a voice that does not loop |
| `+$19` | sample position, low word of a **16.16 fixed point** |
| `+$1b` | ... and its high word |
| `+$1d` | a byte handed straight to the kernel |
| `+$1e` | the loop end |
| `+$20` | the loop length |

```
DS:$02ea := DS:$13a4                   samples still owed this call
if (V^[0] and $02) = 0 then exit       not active
if (V^[0] and $40) <> 0 then exit      finished
if (V^[0] and $04) <> 0 then
  repeat                               LOOPING
    if DS:$02ea = 0 then break
    DS:$02ea := 12ba:1600(0, DS:$0ba0 * 2, DS:$02ea,
                          V^[$1e] - V^[3],        distance to the loop end
                          V^[$19] + V^[$1b] * 65536,
                          V^[$1d], Dest, @V^[1])
    if DS:$02ea <> 0 then
      V^[3] := V^[3] - V^[$20]         wrap back by exactly one loop
  until DS:$02ea = 0
else
  the same, bounded by V^[$b] - V^[3], and stopping when it runs out
```

Two things worth having.

**The 16.16 position is assembled, not stored.** `V^[$1b]` is multiplied by
65536 (`1ba1:0a13` with `BX:CX = 1:0`) and added to `V^[$19]`. So the two
words are a genuine fixed-point pair, which is the other half of the
resampling arithmetic `00-map.md` records at `14c9`.

**The kernel is never asked to cross a loop point.** Each call is bounded by
the distance to the next boundary, and the outer loop re-enters after
subtracting one loop length. That is what lets the inner kernel be a
straight-line run with no wrap test at all — and it is exactly the invariant
`165a:0583` pays for by writing short loop bodies out three times. The two
decisions only make sense read together.

`DS:$02ea` doubles as the argument and the return: the kernel reports how many
samples are still owed, so "did anything happen" and "how much is left" are
one value.

### `12ba:0b29` — the software path, once per tick

What calls `0007`. Per channel, it mixes into that channel's own buffer and
then filters it:

```
for Chan := 1 to Song^[$28] do
begin
  Rec := @DS:$1384[Chan * $22]            a 34-byte channel record
  DS:$0310 := DS:$0314^[+7] + (Chan-1)*2  this channel's output buffer
  12ba:0007(Rec, @DS:$0310)               mix -- and it ADVANCES DS:$0310
  1544:004c(DS:$1eee[Chan*2], DS:$121f, Song^[$28],
            DS:$13a4, DS:$0310)           filter what was just produced
end
```

`DS:$0310` is passed **by reference** and comes back advanced, which is how
the filter knows where the new samples end. The filter coefficient is
per-channel, read from the word table at `DS:$11ee`.

`DS:$1389` is an array of 11-byte records — one per loaded module — and
`DS:$1390` indexes the current one. Its first byte is copied to `DS:$13a2` and
the routine gives up immediately if it is zero, so a slot with a zero first
byte means "empty".

### `12ba:0275` — post a GUS voice event

```
procedure Post(Voice : Byte; A : Byte; B : Word; C : Byte);   RET 8

E := @DS:$1646[ Slot*128 + Voice*16 ]        Slot = DS:$02f0
if E^[1..2] = 0 then                         the slot is free -- take it
begin
  E^[0] := A;  E^[1] := B;  E^[3] := C
end
else                                         already occupied -- MERGE
begin
  if A <> $FF   then E^[0] := A
  if B <> $FFFF then begin E^[1] := B;  E^[3] := C end
end
```

The ring is `DS:$1646`: **25 slots of 128 bytes, each slot 8 voices x 16
bytes**. `DS:$02f0` is the slot being written.

`$FF` and `$FFFF` are **"leave this alone" sentinels**. Two events landing on
the same voice in the same slot do not fight: the second merges into the
first, and a caller that only wants to change the volume passes `$FFFF` for
the pitch. That is what lets several effect handlers write to one voice in one
tick without any of them knowing about the others.

Note `E^[3]` rides along with `E^[1]` rather than being independently
settable — the pitch and whatever `+3` is are written as a unit.

### `12ba:02ea` — flush one ring slot to the GUS

```
CLD
Inc(Slot);  if Slot > $18 then Slot := Slot - $19       25 slots, wraps
for Voice := 0 to 7 do
begin
  E := @Ring[Slot][Voice]
  if E^[1..2] <> 0 then
    if E^[$c..$f] > 0 then
      1723:08e6(E^[$c..$f], E^[8..$b], E^[6], E^[4],
                E^[3], E^[1], E^[0], Voice)            the long form
    else
      1723:0980(E^[3], E^[1], E^[0], Voice)            the short form
end
FillChar(Ring[Slot], $80, 0)
```

Advance, apply, then wipe the slot — so a slot is always clean by the time the
ring comes round to it again, and `12ba:0275`'s "is it free" test needs no
separate valid flag.

The long form is taken when the 32-bit field at `+$c` is positive; that is the
loop information, so the two `1723` entry points are **start-looping-voice**
and **start-one-shot-voice**.

### `12ba:03cc` — a sample descriptor into GUS voice control

```
Dst^[$0d..$10] := Desc^[$12..$15]              the sample data pointer
DS:$02f4 := 2
if (Desc^[9] = 0) and (Desc^[8] < 4) then      loop length under 4 bytes
  DS:$02f5 := 1
else
begin
  DS:$02f5 := 0
  DS:$02f4 := DS:$02f4 or 4                    the "looping" control bit
end
```

`Desc` is the same sample descriptor `165a` fills in — `+8` is the loop
length, `+$12` the data pointer. A loop shorter than four bytes is treated as
no loop at all, which is the usual guard against a degenerate loop pinning a
GUS voice on a couple of samples.

### `12ba:0664` — a hand-written Move

```
if Count = 0 then exit
if Odd(Ofs(Src)) then begin MOVSB; Dec(Count); if Count = 0 then exit end
CX := Count shr 1;  REP MOVSW
if Odd(Count) then MOVSB
```

Word moves are twice the speed of byte moves on an 8086 but want alignment, so
this copies one leading byte when needed, runs `REP MOVSW`, and mops up the
trailing byte. It aligns on the **source** offset, not the destination —
`TEST SI,1`.

### `12ba:0693`'s buffer swap

The sequencer routine already documented for its seek request also carries a
double-buffer that never buffers:

```
DS:$02f6 := (DS:$02d6 + 1) and 0                       always 0
DS:$02dc := @DS:$1220[DS:$02f6 * $3f]
12ba:0664(@DS:$1220[DS:$02d6 * $3f], DS:$02dc, $3f)    copy current -> next
DS:$02d6 := DS:$02f6
```

`DS:$1220` is an array of 63-byte blocks and this is plainly meant to copy the
current one to the next and switch. But the `AND AX,0` noted earlier pins the
index at 0 permanently, so the source and destination are the same block and
the `Move` copies it onto itself. Harmless, and recorded as found rather than
tidied — the machinery is there, disabled by one instruction.

### `12ba:1049` and `12ba:105d` — the module enumerator

`1049` is a far function that sets its result to zero and returns. No
parameters, no body. An unimplemented stub.

`105d` is the one that works:

```
Result := nil
if DS:$1389[DS:$1392 * $0b] <> 0 then
begin
  Result := @DS:$1389[DS:$1392 * $0b]
  Inc(DS:$1392)
  if DS:$1392 > 1 then DS:$1392 := 1
end
```

It walks the same 11-byte module records `0b29` reads, but the index is
clamped to 1 — so it yields at most two and then repeats. An enumerator over a
list that never has more than one entry in practice.

### `12ba:10a1` — take a module and set the play range

`CLI`-guarded, like `14b9:0687` and for the same reason.

```
CLI
DS:$02c4 := Song                       the module being played
DS:$033c := DS:$0342                   loop start
DS:$033e := DS:$0344                   loop end
DS:$0340 := DS:$0346                   the range end
if DS:$0340 = 0 then DS:$0340 := Song^[$35]        default from the module
if DS:$033c = 0 then DS:$034c := 1 else DS:$034c := DS:$033c
```

`DS:$0342`/`$0344`/`$0346` are the requested range and `$033c`/`$033e`/`$0340`
the active one, with the module's own length at `Song^[$35]` as the fallback.
`DS:$034c` is the play position the seek request also writes — which is the
other end of the interface in `01-int2f.md`.

### `12ba:132f` — negotiate the rate, size the buffer, program the DMA

This is the routine that ties the whole output path together.

```
DS:$0bae := Rate
repeat
  N := Driver^.Method_26(Rate)                 ask the card what it can do
  if DS:$02e0 * DS:$0bcc >= N then Rate := Rate - 100
  else if N < 1000     then Rate := Rate + 100
until it settles
if N <> DS:$1200 then
begin
  DS:$1200 := N
  SetTickHandler(N * 3 div 2, 12ba:1008)       1a17:005d
  if stereo then DS:$0ba4 := DS:$1200
  else           DS:$0ba4 := DS:$1200 div 2
  DS:$0ba4 := DS:$0ba4 and $FFFC               round down to a multiple of 4
  if DS:$0bc4 <> $FF then
    ProgramDMA(DS:$0ba4, Buffer, $58, DS:$0bc4)     1b24:0276
  DS:$0bca := DS:$0bc8
end
```

Three things fall out of it.

**`+$26` is "what rate can you actually do?"** — the driver slot whose GUS
implementation (`1084:00e4`) just returns its argument, because a GUS can play
at any rate. A card that cannot would round here, and the loop then nudges the
request by 100 until the resulting buffer size sits in range.

**`12ba:1008` is the mixer's tick entry** — the routine `1a17:005d` installs
at `DS:$4312`, which is what every poll path eventually calls. The tick rate
is **one and a half times** the mixing rate.

**The buffer size is rounded down to a multiple of four**, which is why INT
2Fh function 3 rounds the play position down to a multiple of four as well.
Those two were read weeks apart in this analysis and agree.

### `12ba:0187` and `12ba:0202` — the event ring

The two tables the init clears turn out to be a ring buffer:

```
12ba:0187   Inc(DS:$02ec)                       the row counter
            if DS:$02ec > $18 then              24
            begin
              DS:$02ec := DS:$02ec - $19        25
              if DS:$02d1 <> 0 then begin DS:$02ec := 0; DS:$02ee := 0 end
              else Inc(DS:$02ee)
            end
            Rec := DS:$14b6 + DS:$02ec*16 + DS:$02ee*2
            if Rec^[1] <> 0 then Inc(DS:[$22c6 + Rec^[0]])
```

`DS:$14b6` is the 400-byte table (25 x 16) and `DS:$1646` the 3200-byte one
(25 x 128) — a **25-slot ring**, written by `12ba:0202` and consumed here.

Two details are worth keeping. The counters it bumps live at **`DS:$22c6`,
which is the control block published over INT 2Fh** — so a client could read
per-channel activity out of it. And the branch is taken on **`DS:$02d1`, the
flag set by the `'inconexi'` rename check** in the main body: renaming the
executable changes how this ring advances. That is the first place that flag
is actually read.

---

## `11bb` — the config file

4080 bytes, 19 routines. The init (`0f2e`) and the trimmer (`0020`) are in
`00-map.md`.

### The parsing layer

```
11bb:0020  Trim          strip leading characters in the set at CS:$0000
11bb:0097  Matches(Line, Key) : Boolean       the keyword matcher
11bb:05f2  ParseNumber(var L) : Boolean
11bb:0826  ReadWord(var W) : Boolean          ParseNumber, keep the low word
11bb:0850  ReadByte(var B) : Boolean          ParseNumber, keep the low byte
11bb:0131  a quoted value
```

`11bb:0131` is the only one with any subtlety:

```
Tail := Copy(Line, DelimPos + 1, 255)
Trim(Line)
if Line <> '' and Line[1] = '''' then         a leading apostrophe
begin
  Line := Copy(Line, 2, 255)
  P := Pos('''', Line)                        the closing quote
  if P = 0 then P := $FE                      unterminated: take the lot
  ...
end
```

An unterminated quoted value is not an error — it simply runs to the end of
the line, capped at 254 characters. That is forgiving in the way a
hand-written config format usually is.

### The dispatcher

`11bb:089f` onwards is a chain of key comparisons, each followed by a read of
the matching type:

```
if Matches(Line, 'IRQ')  then ReadWord(DS:$0b16)
if Matches(Line, 'Port') then ReadWord(...)
...
```

**`DS:$0b16` is the Sound Blaster's IRQ number** — the same variable
`193a:031f` hands to `InstallIRQ` and `193a:0030` checks against 10 to decide
whether to EOI the slave PIC. So the path from a line in `NEUROSIS.CFG` to the
interrupt controller is now complete end to end:

```
NEUROSIS.CFG  ->  11bb:0097 matches the key
              ->  11bb:0826 reads the number into DS:$0b16
              ->  193a:031f  InstallIRQ(DS:$0b16, 193a:0030)
              ->  1b24:00d7  SetIntVec(IRQ + 8, handler)
```

Each key in the list catalogued in `00-map.md` — `IRQ`, `Port`, `LPort`,
`DMA`, `SbSplTimeout`, `MasterVol`, `DACVol`, `FMVol`, `PermitFade`,
`FadeSpeed`, `LoopMod`, `ForceLoopMod` — lands in a variable this way.

---

## The mixing kernels — `1a17:0d7c` (mono) and `1a17:0dfc` (stereo)

These are the routines `1a17:1090` selects between and stores at `DS:$0c00`.
They are frameless, so the prologue scan never saw them; they were reached by
following that store.

```
        INC  CX
        JMP  into the body            computed entry, as in 12ba:14c9
body:
        ADD  AX, [SI+$3E]
        ADD  BX, [SI+$3C]
        ADD  BX, [SI+$3A]
        ADD  AX, [SI+$38]
        ...  alternating down to [SI+$04]
        ADD  SI, $1234                <- PATCHED: the channel stride
        ADD  AX, BX                   combine the two accumulators
        JO   clamp
        XOR  AH, $80                  signed -> unsigned
        MOV  ES:[DI], AH              store the HIGH byte only
        INC  DI
        MOV  AX, [SI]
        MOV  BX, [SI+2]               reload for the next sample
        LOOP body
        RET
clamp:  JNS  negative
        MOV  AX, $7FFF                positive saturation
        JMP  back
negative:
        MOV  AX, $8001                negative saturation
        JMP  back
```

Three things worth keeping.

**It saturates rather than wraps.** `JO` after the combine sends it to a clamp
that picks `$7FFF` or `$8001` on the sign. Wrapping would turn a loud passage
into a burst of noise; this just flattens it. The `$8001` rather than `$8000`
makes the clamp symmetric.

**Two accumulators, alternating.** The adds go AX, BX, BX, AX, AX, BX… rather
than all into one register. Splitting the sum halves the magnitude each
accumulator has to hold, so the only place overflow can bite is the single
`ADD AX,BX` at the end — one overflow test for the whole mix instead of one
per channel.

**The output is the high byte of a 16-bit accumulator.** `MOV ES:[DI], AH`
after `XOR AH,$80` — the sum is kept at 16 bits throughout and only narrowed
to the 8 bits the card wants at the final store.

The stride at `ADD SI,$1234` is patched, exactly as the resampling loop's step
is in `12ba:14e1`. Both loops keep their one variable quantity in the
instruction stream because every register is already committed.

### `12ba:1008` — the tick entry

The routine `1a17:005d` installs, and therefore what every poll path reaches:

```
if DS:$02d0 <> 0 then exit                 disabled
if DS:$02d2 = 0 then DS:$034e := 1
else 12ba:0c4e(Song)                       advance the pattern position
if DS:$02d3 <> 0 then
  CALLF [DS:$121a](Song, DS:$034e = 0)     and mix
```

So one tick is: advance the row if the sequencer is running, then call through
`DS:$121a` to produce audio. The Boolean it passes is "the sequencer did not
run this tick", which is how a paused module still gets its buffer filled with
silence rather than stalling the card.

### `12ba:0c4e` — the sequencer tick, and how tempo is kept

```
if DS:$0bc7 <> 0 and DS:$0bca = DS:$0bc8 then exit     nothing new since last time
Inc(DS:$0bca)
if DS:$13a2 <> 0 and DS:$0bce = 0 then
begin  12ba:0b29(Song);  if DS:$13a2 <> 0 then exit  end
if DS:$0bce <> 0 then 12ba:02ea
12ba:0187                             the event ring
Inc(DS:$1218)
Inc32(DS:$23eb)                       a 32-bit counter INSIDE the control block
Prev := DS:$034e                      the current row
DS:$033a := DS:$033a + DS:$0338       accumulate
DS:$034e := DS:$034e + (DS:$033a div DS:$0336)
if DS:$034e <> Prev then
begin
  DS:$033a := DS:$033a mod DS:$0336   keep the remainder
  if DS:$034e >= Pattern^[1] then 12ba:0693(Song)    next pattern
end
```

The middle of that is **the tempo engine**, and it is done without a single
division of the row number: `DS:$033a` is a running fractional accumulator,
`DS:$0338` the amount added per tick and `DS:$0336` the divisor. Each tick the
row advances by the whole part and the remainder is carried. That is how a
tracker gets a non-integer ticks-per-row ratio — arbitrary BPM — out of
integer arithmetic only.

`DS:$23eb` is `$22c6 + $125`, i.e. **a 32-bit tick counter inside the control
block published over INT 2Fh**. Together with the per-channel counters
`12ba:0187` bumps, that is a small block of live state any client can read.
Psycho Neurosis never does; it is there for a demo that wanted to sync to the
music.

---

## `109c:0890` — the per-entry options

The dispatcher for the keyword list catalogued in `00-map.md`:

```
S := the parameter text
if S = '' then begin (default handling); exit end
if Matches(S, 'nobf') then SetBufferFill(False)
if Matches(S, 'bfil') then SetBufferFill(True)
if Matches(S, 'nolp') then SetLoop(False)
if Matches(S, 'loop') then SetLoop(True)
if Matches(S, 'nofl') ... 'flp' ... 'port' ... 'irq' ... 'dma' ... 'off'
```

Each keyword goes through the entry object's `+$18` method (the matcher) and
then a small setter — `109c:0ff8` for the on/off pairs, `109c:0fd1` for the
others. The on/off pairs are spelled out as two separate keywords rather than
parsed as a negation, which is why the table has both halves of each.

### `142f:0360` and `142f:03cd` — the volume slide

The setter splits the parameter byte the usual way, but signs it:

```
if Note^[5] <> 0 then
begin
  Voice^[$23] := 0
  if Note^[5] > $0F then Voice^[$21] :=  Note^[5] shr 4      up
  else                   Voice^[$21] := -(Note^[5] and $0F)  down
end
else if Voice^[$23] <> 0 then
begin
  Voice^[$23] := 0;  ApplySlide(Voice);  Voice^[$23] := 1
end
```

and the applier, frameless with `SI` holding the voice, does the clamping in
one comparison:

```
AL := Voice^[$0a] + Voice^[$21]      volume plus the signed step
if AL > $40 then                     unsigned -- catches BOTH directions
begin
  AL := 0
  if (Voice^[$21] and $80) = 0 then AL := $40
end
Voice^[$0a] := AL
```

Volume runs 0..64, and a single **unsigned** `CMP AL,$40` catches both
overflows at once: sliding up past 64 exceeds it directly, and sliding down
past zero wraps to a large unsigned value and exceeds it too. The sign of the
step then picks which limit to snap to. Two clamps, one comparison, no
branches on the arithmetic itself.

### `165a:08e2` — find a run of free slots

```
clear two local tables ($402 and $202 bytes)
for I := 0 upwards do
begin
  Rec := Table + I*6
  if Rec^[0] <> 0 or Rec^[1..2] <> 0 or Rec^[3] <> 0 then
    (occupied -- reset the run)
  else if Start = I then Inc(Start)
  else Len := I - Start + 1
  ...
end
```

A scan over **six-byte records** for a run of wholly zero ones, tracking where
the run started and how long it is. That is a free-space search, which fits
`165a`'s job of placing sample descriptors — on a GUS the samples live in the
card's own DRAM and something has to decide where each one goes.

### `12ba:0693` — advance to the next pattern, and the seek request

```
12ba:0000(0, 0, -1)
if DS:$24c9 <> 0 then                    a pending jump
begin
  DS:$24c9 := 0
  DS:$034c := DS:$24ca                   requested order position
  DS:$034a := DS:$24cb                   requested row
end
Next := (DS:$02d6 + 1) and 0             see the note below
DS:$02f6 := Next
DS:$02dc := DS:$1220 + Next * $3F
copy the current $3F-byte record into it        12ba:0664
DS:$02d6 := Next
if DS:$034a = $FFFF then Rec^[0] := 1 else Rec^[0] := 0
if Rec^[0] <> 0 and DS:$0334 <> 0 then
begin
  DS:$034c := DS:$033e                   the end position
  if DS:$034c < DS:$033c then DS:$034c := DS:$033c    clamp to the start
  DS:$034a := 1
end
```

**`DS:$24c9`, `$24ca` and `$24cb` are `$22c6 + $203/$204/$205` — inside the
control block published over INT 2Fh.** So a resident client can ask the
player to jump: set the order position and row, raise the flag, and the next
time the sequencer crosses a pattern boundary it honours the request and
clears the flag. That is a **seek interface**, and it is the only part of the
control block that is written by the client rather than read.

Psycho Neurosis never uses it — its parts only ever call functions 0..3 — but
it is there, and it is the natural way a demo would have synchronised a scene
change to a particular point in the music.

One oddity, recorded as found: `INC AX` is immediately followed by
`AND AX,0`, so `Next` is always zero and the `$3F`-byte records at `DS:$1220`
never use more than the first slot. The shape is a two-slot rotation with the
rotation disabled.

### `11bb:05f2` — where does the number end?

```
A := Pos(<char at CS:$05e8>, Line) + 1
B := Pos(<char at CS:$05ea>, Line)
C := Pos(<char at CS:$05ec>, Line)
if C <> 0 and B > C then B := C
D := Pos(<char at CS:$05ee>, Line)
if D <> 0 and B > D then B := D
...
```

Four candidate terminator characters, each searched for separately, and the
**earliest non-zero position wins**. A found-nothing result of zero has to be
excluded explicitly each time, which is why every comparison is guarded. The
value is then whatever lies between the start and that position.
