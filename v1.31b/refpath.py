"""Where the reference image lives, and what it is.

`ref/vt1.31b.bin` is the measurement target: the DemoVT v1.31b build that
shipped inside Psycho Neurosis as `NEUROSIS.008`, LZEXE-packed, run back
through `tools/unlzexe.py` to recover the load image. 58,176 bytes.

It IS tracked, deliberately: the measurement target belongs with the
measurements, and a checkout that cannot measure itself is not much use.
`tools/unlzexe.py` can rebuild it from the shipped `NEUROSIS.008` if needed.

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
            "It is tracked, so a clean checkout has it -- something removed it here.\n"
            "Restore it with `git checkout -- v1.31b/ref/vt1.31b.bin`, rebuild\n"
            "it with tools/unlzexe.py, or point VT_REFIMG at a copy you have." % ORIG)
    blob = ORIG.read_bytes()
    if len(blob) != EXPECTED_SIZE:
        raise SystemExit(
            "reference image is %d bytes, expected %d: %s\n"
            "This should be the UNPACKED image, not the packed NEUROSIS.008."
            % (len(blob), EXPECTED_SIZE, ORIG))
    return blob
