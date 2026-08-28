# The measurement target

`vt1.51.bin` is **DemoVT v1.51**, April 1994 — the released version, shipped in `demovt15.zip` as `DEMOVT.EXE` and LZEXE 0.91-packed. It is the packed file unpacked back to a load image by

    python kit/tools/substrate/unlzexe.py DEMOVT15/DEMOVT.EXE v1.51/ref/vt1.51.bin

66,448 bytes: a 3,408-byte header and a 63,040-byte load image. It is TRACKED deliberately — a checkout that cannot measure itself is not much use.

## What the unpacking cannot tell you about it

The same two caveats the v1.31b image carries, for the same reasons, and both are about the MEASUREMENT rather than the build:

* **`maxalloc` and `minalloc` are the unpacker's, not the original's.** LZEXE preserves neither, so `unlzexe.py` writes `$FFFF` into maxalloc and recomputes minalloc from `SS:SP`. Neither field is evidence about how the original was built, and minalloc agreeing with a rebuild is partly circular. `SS:SP`, `CS:IP` and the relocation targets ARE preserved in the packed header.
* **The relocation table is re-encoded.** LZEXE flattens each fixup onto segment 0 while the linear address still fits in 16 bits; a linker emits it relative to the segment the reference sits in. The same linear address, two spellings. Comparing linear addresses is the only meaningful test.

`SS:SP` is `1530:4E20`. The initial SP of `$4E20` is 20,000 — the same stack size v1.31b's `{$M 20000,0,655360}` sets, and it is preserved through the packing, so it is real.

## Provenance

Third-party work by VangeliSTeam (JCAB), included here as the comparison target. The reconstruction is everything under `v1.51/` other than this directory.
