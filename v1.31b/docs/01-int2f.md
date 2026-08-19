# The INT 2Fh interface — the server side

This is the half of the handshake that `src/DEMOVT.PAS` in the main project
talks to. Read out of the unpacked image; every address is `seg:ofs` with
Ghidra's `0x1000` load base, so they are directly comparable with the
disassembly.

Two segments are involved: **`1b54`**, the residency unit (432 bytes, whole),
and **`1000:024c`**, the dispatcher, which lives in DemoVT's own program
segment.

---

## `1b54` — residency

```
1b54:0000   JMP FAR <old INT 2Fh>       a 5-byte stub, patched at install
1b54:0006   the INT 2Fh handler
1b54:002b   JMP 1b54:0000               "not for us" -- chain onwards
1b54:002f   the exit handler
1b54:0061   String  '\r\n    ­­Ojo, que está el '
1b54:007b   String  ' residente!!'
1b54:0088   Install(Name : String; Block : Pointer)
```

### The handler — `1b54:0006`

```
STI
CMP AX,5654h   'VT'    JNZ chain
CMP BX,5472h   'Tr'    JNZ chain
CMP CX,6163h   'ac'    JNZ chain
XOR AX,AX              AX := 0
XOR BX,6b65h           BX := 5472h xor 6b65h = 3F17h
XOR CX,7220h           CX := 6163h xor 7220h = 1343h
MOV DI,1caa / MOV ES,DI
MOV DI,432ch
IRET
```

The reply is computed, not stored: the two constants are XOR masks over the
request. `src/DEMOVT.PAS`'s `MusicDetect` matches this exactly — `AX = 0`,
`BX = $3F17`, `CX = $1343`.

`ES:DI` comes back as `1caa:432c`, and that is **DemoVT's own copy of its
name**, written by `Install`. The four bytes below it are the control block
pointer, which is why the client reads `ES:[DI-4]`.

### `1b54:0088` — Install

`RETF 8`, so two 4-byte parameters: `Name` at `[BP+0Ah]`, `Block` at `[BP+6]`.
The main body calls it as `Install(DS:$0004, DS:$22C6)`.

```
Name is copied to a 256-byte local
run the same INT 2Fh handshake a client would
if nothing answered then point at DS:$0C20 (a default name)
if something DID answer then
begin
  Write('\r\n    ­­Ojo, que está el ');  Write(<the resident's name>);
  Write(' residente!!');  WriteLn;  Halt(1)
end;
DS:$4328 := Block                     <- the control block pointer
DS:$432c := Name                      <- what ES:DI will point at
DS:$4324 := 1b54:0000                 <- the chain stub
patch the stub's target with the current IVT[$2F]
IVT[$2F] := 1b54:0006
DS:$442c := ExitProc                  ExitProc is DS:$0C58
ExitProc := 1b54:002f
```

`1b54:002f` undoes it: `ExitProc := DS:$442c`, then `IVT[$2F]` back from the
`JMP FAR` stub's own operand bytes (`+1` is the offset, `+3` the segment).
Chaining through a patched `JMP FAR` rather than a stored variable is why the
old vector is read out of `ES:[DI+1]` / `ES:[DI+3]`.

---

## The control block is `1caa:22C6`

Install is handed `DS:$22C6`, so:

| client sees | is | holds |
|---|---|---|
| `ES:DI` from INT 2Fh | `1caa:432c` | DemoVT's name, as a `String` |
| `ES:[DI-4]` | `1caa:4328` | far pointer to the control block |
| `CB` | `1caa:22c6` | |
| `CB+$121` | `1caa:23e7` | dispatcher offset |
| `CB+$123` | `1caa:23e9` | dispatcher segment |
| `CB+$203` | `1caa:24c9` | seek request pending — **write** |
| `CB+$204` | `1caa:24ca` | requested order position — **write** |
| `CB+$205` | `1caa:24cb` | requested row — **write** |

And the main body sets that pair directly, at `1000:058c`:

```
MOV AX,024ch / MOV DX,1000h
MOV [23e7],AX / MOV [23e9],DX
```

So **the routine every Psycho Neurosis part far-calls is `1000:024c`**.

---

## `1000:024c` — the dispatcher

```
procedure Dispatch(Func : Word); far;        ENTER 2,0 ... RETF 2

PUSHA; PUSH ES; PUSH DS
DS := 1caa                        its own data segment
Result := 0                       [BP-2], and nothing ever changes it
case Func of
  0 : 1000:01bd                                     near call
  1 : 1000:020a                                     near call
  2 : LES DI,[0b96h]; CALLF [DI+2Ah]                a VIRTUAL method
  3 : begin
        P := 1a17:06ff;                             returns a far pointer
        DS:$4306 := Ptr(Seg(P), Ofs(P) and $FFFC);
        DS:$0bca := DS:$0bc8;
        DS:$0058 := 0;
        DS:$0bd0 := 0
      end
end
POP DS; POP ES; POPA
AX := Result
```

This settles the function numbers that `src/DEMOVT.PAS` had already worked out
from the client side, and confirms all three:

| function | the demo calls it | dispatches to |
|---|---|---|
| 0 | `MusicStart` | `1000:01bd` |
| 1 | `MusicStop` | `1000:020a` |
| 2 | `MusicPoll` | virtual method `+$2A` on the object at `DS:$0B96` |
| 3 | part 001 only, name unsettled | the inline block at `1000:0288` |

### What function 3 actually does

`1a17:06ff` builds a **far pointer into the output buffer** — it takes the
buffer base from `DS:$430a`, works out how far into it the player currently is
(`[0xba4]` is a buffer size, `[0xbbe]` a byte-per-something multiplier), and
returns base + that offset in `DX:AX`.

Function 3 then rounds that offset **down to a multiple of four**, keeps it at
`DS:$4306`, snapshots `DS:$0bc8` into `DS:$0bca`, and zeroes `DS:$0058` and
`DS:$0bd0`.

So it is a **"mark the current position in the output buffer and reset the
counters"** operation — a sync point, not a stop. `src/DEMOVT.PAS`'s note that
an early version calling it `FuncStop` was wrong is confirmed: it stops
nothing.

`1a17` has since been read line by line and the name can be firmed up:
`DS:$4306` is the **play position**, set to the start of the buffer by
`1a17:00a9` (Start) and set here to wherever the hardware has actually reached.
Function 3 is a **resync** — it re-anchors the play position to the present and
clears the counters that were measured from the old anchor. `src/DEMOVT.PAS`'s
"function 3 not established" note can now say `MusicResync`.

---

## The seek request — the one thing a client may WRITE

Everything above is a call interface, and everything else found in the control
block is output. `12ba:0693`, inside the sequencer's per-row work, reads three
bytes that nothing inside DemoVT ever writes:

```
if DS:$24c9 <> 0 then            CB+$203 -- a jump is pending
begin
  DS:$24c9 := 0;                 consumed
  DS:$034c := DS:$24ca;          CB+$204 -> the order position
  DS:$034a := DS:$24cb           CB+$205 -> the row within the pattern
end;
```

`DS:$034c` and `DS:$034a` are the sequencer's own position and row, so a client
that pokes the two bytes and then raises the flag makes the music **jump to
that point in the module** at the next row boundary. DemoVT clears the flag
itself, so the write is one-shot and there is no race to lose: the worst case
is that the jump lands a row later than intended.

Reached through the same `ES:DI` handshake — `CB` is `ES:[DI-4]`, so the three
bytes are `CB+$203..$205` — no INT 2Fh function is involved at all.

**Psycho Neurosis never uses it.** It is recorded because it is the only
documented way for a demo to drive the music rather than merely follow it: a
part that wanted to cut straight to a section on a scene change, or restart a
loop, would do it here. Nothing else in the control block accepts a write.

The order in which the bytes are set matters — position and row first, flag
last — because the sequencer tests only the flag.

---

## What this is worth to the main project

Nothing in `src/DEMOVT.PAS` has to change: every value it uses is confirmed
against the server. The gain is that the last "not established" note in that
file now has a documented answer behind it, and the control-block offsets
`$121`/`$123` are no longer magic numbers — they are `1caa:23e7` and
`1caa:23e9`, written by DemoVT's own main body.

The seek request is the one thing here that is genuinely new capability rather
than confirmation. If a part ever needs to sync a scene to a point in the
module, `CB+$203..$205` is how, and it needs no cooperation from DemoVT beyond
what the existing handshake already returns.
