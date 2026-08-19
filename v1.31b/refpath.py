"""Where the reference image lives, and what it is.

`ref/vt1.31b.bin` is the measurement target: the DemoVT v1.31b build that
shipped inside Psycho Neurosis as `NEUROSIS.008`, LZEXE-packed, run back
through `tools/unlzexe.py` to recover the load image. 58,176 bytes.

**It is deliberately NOT tracked** -- see the root `.gitignore`. It is a
third-party binary extracted from someone else's release, so the tree carries
it for convenience and git does not carry it at all. A fresh clone has to
unpack its own; `tools/unlzexe.py` is tracked and does that.

Two things the unpacked file CANNOT tell you, because our unpacker rather than
the original build decided them: `maxalloc` (we write $FFFF) and `minalloc` (we
recompute it from SS:SP, so its agreeing is partly circular). The relocation
table is re-encoded too, so only the set of LINEAR targets is comparable.

Override the location with the VT_REFIMG environment variable.
"""
import os
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT = HERE / 'ref' / 'vt1.31b.bin'

ORIG = pathlib.Path(os.environ.get('VT_REFIMG') or DEFAULT)

EXPECTED_SIZE = 58176


def read():
    """The reference image's bytes, with a diagnosis rather than a traceback."""
    if not ORIG.is_file():
        raise SystemExit(
            "reference image not found: %s\n"
            "It is untracked by design -- see refpath.py. Unpack NEUROSIS.008 with\n"
            "tools/unlzexe.py, or point VT_REFIMG at a copy you already have." % ORIG)
    blob = ORIG.read_bytes()
    if len(blob) != EXPECTED_SIZE:
        raise SystemExit(
            "reference image is %d bytes, expected %d: %s\n"
            "This should be the UNPACKED image, not the packed NEUROSIS.008."
            % (len(blob), EXPECTED_SIZE, ORIG))
    return blob
