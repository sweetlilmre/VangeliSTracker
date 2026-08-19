# ref/ — the measurement target

`vt1.31b.bin` is the file every comparison in this tree runs against, and **it is not in git.** See the root `.gitignore` and `../refpath.py`.

## What it is

| | |
|---|---|
| origin | `NEUROSIS.008`, shipped inside the Psycho Neurosis demo |
| identity | DemoVT v1.31 (beta) © 1992-93 VangeliSTeam (JCAB) |
| as shipped | LZEXE 0.91 packed |
| here | that file run through `tools/unlzexe.py`, i.e. the recovered load image |
| size | 58,176 bytes = 3,120 header + 55,056 load image |

## Recreating it

    python tools/unlzexe.py <path to NEUROSIS.008> v1.31b/ref/vt1.31b.bin

Or point `VT_REFIMG` at a copy you keep elsewhere; every script resolves the path through `refpath.py`, so there is one place to change.

## What it cannot tell you

`unlzexe.py` writes `maxalloc` as `$FFFF` itself and recomputes `minalloc` from SS:SP, because LZEXE preserves neither — so those two header fields are the unpacker's rather than the original build's, and `minalloc` agreeing is partly circular. The relocation table is re-encoded as well, so only the set of **linear** targets is meaningful, not its order. Everything else in the header, and the whole 55,056-byte image, is the original's.
