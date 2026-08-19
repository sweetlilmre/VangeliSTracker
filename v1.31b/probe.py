#!/usr/bin/env python3
"""Compile v1.31b/probe/PROBE.PAS with every installed compiler and diff the code.

    python v1.31b/probe.py                 tp6, tp61 and tp7

The probe holds one routine per divergence that survives both recorded
compilers (see v1.31b/probe/PROBE.PAS). This drives it through each TPC and
compares the compiled code, so a codegen difference between two Turbo Pascal
releases is visible in seconds without touching the reconstruction.

Shares build/ with build.py and dosbuild.py, and wipes it on entry, so only one
of the three can run at a time.
"""
import subprocess
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from build import BUILD, CONF, DOSBOX, SWITCHES, COMPILERS, tp6_dialect  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent / "probe"
ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = HERE / "out"


def compile_with(compiler, extra=""):
    BUILD.mkdir(exist_ok=True)
    for f in BUILD.glob("*"):
        if f.is_file():
            f.unlink()
    text = (HERE / "PROBE.PAS").read_text(encoding="utf-8")
    if compiler.startswith("tp6"):
        text = tp6_dialect(text)
    (BUILD / "PROBE.PAS").write_text(text, encoding="cp437", errors="replace")
    bat = ["@echo off", "echo === probe > BUILD.LOG",
           r"%s %s%s /Q PROBE.PAS >> BUILD.LOG" % (COMPILERS[compiler], SWITCHES, extra),
           "exit"]
    (BUILD / "BUILD.BAT").write_text("\r\n".join(bat) + "\r\n", encoding="ascii")
    subprocess.run([str(DOSBOX), "-conf", str(CONF), "-silent", "-exit"],
                   cwd=str(ROOT), timeout=180,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log = (BUILD / "BUILD.LOG").read_text(encoding="latin1") if (BUILD / "BUILD.LOG").exists() else ""
    tpu = BUILD / "PROBE.TPU"
    if not tpu.exists():
        return None, log
    OUT.mkdir(parents=True, exist_ok=True)
    dest = OUT / ("PROBE_%s.TPU" % compiler)
    dest.write_bytes(tpu.read_bytes())
    return dest.read_bytes(), log


def code_of(blob):
    """The compiled code, located by the first routine's prologue.

    Every routine in the probe has a frame, so the code starts at the first
    `C8 nn nn 00` (ENTER) or `55 8B EC` and runs to the end of the code block.
    Rather than parse the .TPU format -- which differs between releases -- take
    from that prologue to the last RETF, which is what the comparison needs.
    """
    for i in range(len(blob) - 4):
        if blob[i] == 0xC8 and blob[i + 3] == 0x00:
            return i, blob[i:]
        if blob[i:i + 3] == b"\x55\x8b\xec":
            return i, blob[i:]
    return None, b""


def hexdump(b, base=0, limit=None):
    out = []
    b = b[:limit] if limit else b
    for i in range(0, len(b), 16):
        row = b[i:i + 16]
        out.append("%04x  %-47s  %s" % (
            base + i, " ".join("%02x" % c for c in row),
            "".join(chr(c) if 32 <= c < 127 else "." for c in row)))
    return "\n".join(out)


def main(argv):
    which = [a for a in argv if a in COMPILERS] or ["tp6", "tp61", "tp7"]
    codes = {}
    for c in which:
        blob, log = compile_with(c)
        if blob is None:
            print("=== %s: DID NOT COMPILE" % c)
            print(log)
            return 1
        at, code = code_of(blob)
        codes[c] = code
        print("=== %-5s %s  %d bytes, code found at +%04x" %
              (c, COMPILERS[c], len(blob), at or 0))
    print()
    ref = which[0]
    for c in which[1:]:
        a, b = codes[ref], codes[c]
        same = a == b
        print("%-5s vs %-5s : %s" % (ref, c, "IDENTICAL CODE" if same else "DIFFERS"))
        if not same:
            n = min(len(a), len(b))
            first = next((i for i in range(n) if a[i] != b[i]), n)
            print("  first difference at code offset +%04x (lengths %d / %d)"
                  % (first, len(a), len(b)))
            lo = max(0, first - 16)
            print("  --- %s" % ref)
            print(hexdump(a[lo:lo + 64], lo))
            print("  --- %s" % c)
            print(hexdump(b[lo:lo + 64], lo))
    print()
    print("code, %s:" % ref)
    print(hexdump(codes[ref][:400]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
