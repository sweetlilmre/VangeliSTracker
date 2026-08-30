#!/usr/bin/env python3
r"""Compile the VangeliSTracker 1.39b RELEASE with TP 7.01, under DOSBox-X.

    python relbuild.py            stage + compile MAKESTR, VT, SHELLVT
    python relbuild.py VT.PAS     one program

This is the RELEASE source in `v1.39b/` -- JCAB / VangeliSTeam's own tracker,
the later version of the codebase this project reconstructs -- NOT the
reconstruction. Nothing here measures anything against the original; the output
is 49-odd `.TPU` files in `build/vt`, and `relmatch.py` beside this file is what
reads them.

WHY IT EXISTS. `relmatch.py` diffs the release's COMPILED code against each 1.31
segment, to rank which release unit a segment most likely derives from. That
needs the release BUILT, and until now nothing in this checkout could build it:
the recipe named `tools/dosbox/vtbuild.py`, a path that resolved when this tree
was `demovt/` inside the psycho checkout and that the split left behind.

ADAPTED FROM `<psycho>/tools/dosbox/vtbuild.py` on 28 Aug 2026, which is still
there and still cannot run: it computes its source as `<psycho>/VangeliSTracker`,
held out by that repository's .gitignore pending a licensing decision, and its
output as `<psycho>/build/vt`. The release sources are TRACKED HERE instead, 107
files under `v1.39b/`, so this version reads them directly. Four changes from the
original, all of them forced:

  * SRC is `v1.39b/` in this repository, not a gitignored sibling directory.
  * EVERY MACHINE PATH comes from `kit.local.toml` through the kit's `project`
    module -- DOSBox-X, the drive C: image, and TPC.EXE. The original hardcoded
    its DOSBox-X path and a `C:\TP\BIN` for the compiler, and this repository may
    not commit either. That `BIN` path is also simply wrong here -- this machine's
    TP 7.01 install is elsewhere, which `toolchain.tp7` in kit.local.toml knows
    and no committed file needs to.
  * THE UNIT PATH IS DERIVED from `toolchain.tp7` rather than written down, so
    the `/U` rewrite cannot drift from the install the build actually uses.
  * `install()` IS GONE. It copied the built .EXEs into `<psycho>/run/` beside
    the demo, so `run.bat` reached them as `E:\VT.EXE`. There is no `run/` here
    and no demo to launch; the .TPUs in `build/vt` are the whole point.

WHY TP 7.01 AND NOT TP6, when this project's headline finding is that DemoVT
1.31 was built with TP6. Because the release's own `TPC.CFG` is a TP7
configuration and the 1.39b tree is a TP7 tree -- that is what the author
shipped. `relmatch.py` reads its output as a SIMILARITY RANKING, not as
byte-exact evidence, so the compiler need only be the one the release expects.
Do not reach for these `.TPU`s as evidence about 1.31's toolchain.

THE ONE EDIT TO THE RELEASE IS TPC.CFG's `/U` LINE. The release's says

    /U.\LIB;D:\LENG\TP\TVISION

which is the author's own Turbo Vision path. Everything else in that file -- the
switches, `/O.\LIB` (which is why the unit output lands in `build/vt/LIB`), `/M`,
`/GD`, `/V` -- is the original's and is left exactly as found.

THE 1.31 BUILD DELETES build/vt, SO ORDER MATTERS. The kit's `build.py` wipes
its staging directory at the start of every run, and since psycho #36 that wipe
removes SUBDIRECTORIES too, not just files -- `build/vt` is a subdirectory of it.
So `build.py build.toml` destroys the release build, silently and completely.
Run this AFTER the reconstruction build, or run it again before `relmatch.py`.
Nothing warns you: `relmatch.py` would simply say it found no `.TPU`.

WHAT MAKE.BAT DOES THAT THIS DOES NOT. `MAKE.BAT`'s `:MakeVT` runs `FONT\MAKE`
first, which drives GETFONT.EXE over FONT.CEL and BINOBJ over the result to
produce `LIB\FONT.OBJ`. That object already ships in `v1.39b/LIB/`, so the step
is skipped. So are `tdstrip` and `lzexe`, which strip debug information and pack
the result: neither changes what the program does, and neither affects a `.TPU`.
"""
import re
import shutil
import subprocess
import sys
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
SRC = ROOT / "v1.39b"
BUILD = HERE / "build" / "vt"
# Generated, and they live with the build rather than beside anything tracked --
# build/ is gitignored and neither file is worth keeping.
CONF = BUILD / "DOSBUILD.CFG"

sys.path.insert(0, str(ROOT / "kit" / "tools"))
import project                                 # noqa: E402

# The three PROGRAMs, in MAKE.BAT's order. MAKESTR comes first there because
# running it regenerates VT_ESP.LNG and VT_ENG.LNG from VTSTRCON/STRCONST; both
# files already ship, so building it is a check on the string units rather than
# a necessity.
PROGRAMS = ["MAKESTR.PAS", "VT.PAS", "SHELLVT.PAS"]

# Copied so a built VT.EXE could actually start: its config, the two language
# files MAKESTR produces, and the three bundled modules.
#
# NOT *.MAP. The release ships VT.MAP and SHELLVT.MAP and VTSRC.LST lists them
# beside VT.CFG as though they were data, but they are linker maps -- TPC.CFG
# has /GD, so the compiler writes VT.MAP itself and would overwrite a staged
# copy anyway.
DATA = ["*.CFG", "*.LNG", "*.VTO"]


def machine(key, fallback=None):
    """A machine path, from kit.local.toml. Never from a committed file."""
    try:
        return project.get(key)
    except project.Missing:
        if fallback is not None:
            return fallback
        raise


def dos_dir(dos_exe):
    r"""C:\TP701\BIN\TPC.EXE -> its directory, and the install root above it."""
    parts = dos_exe.replace("/", "\\").split("\\")
    binpath = "\\".join(parts[:-1])
    root = "\\".join(parts[:-2]) if len(parts) > 2 else binpath
    return binpath, root


def on_image(dos_path):
    """Does a C:-qualified DOS path exist on the mounted drive image?

    WHY THIS IS NOT PARANOIA, and the kit's build.py carries the same check for
    the same reason: DOS does not set ERRORLEVEL when it cannot find a command.
    It prints "Bad command or filename" and carries on with errorlevel zero, so
    the batch file's `if errorlevel 1` can never catch a missing compiler. On
    this very repository a config naming an old install path produced a build
    that stamped every unit ** OK and exited 0 while TPC.EXE was never invoked.
    """
    if not dos_path or len(dos_path) < 3 or dos_path[1] != ":":
        return True                       # not drive-qualified; leave it alone
    if dos_path[0].upper() != "C":
        return True                       # only C: is the mounted image
    try:
        hdd = pathlib.Path(machine("dosbox.hdd"))
    except Exception:
        return True                       # no mapping to check against
    return (hdd / dos_path[3:].replace("\\", "/")).exists()


def stage(units_path):
    """Binary-copy the release tree into build/vt, then fix TPC.CFG's /U path.

    NOTHING IS RENAMED. Turbo Pascal 7 finds a unit by the first EIGHT
    characters of its identifier, which is why the release's filenames are
    already truncations -- `UNIT SoundDevices` lives in SOUNDDEV.PAS and
    `uses SoundDevices` finds it. So this stages by straight binary copy. The
    sources are latin-1 with Spanish text in the comments and string constants;
    copying bytes keeps them intact.
    """
    if BUILD.exists():
        shutil.rmtree(BUILD)
    (BUILD / "LIB").mkdir(parents=True)

    n = 0
    for pat in ("*.PAS", "*.EXE"):
        for f in sorted(SRC.glob(pat)):
            shutil.copy(f, BUILD / f.name.upper())
            n += 1
    for pat in ("*.PAS", "*.ASM", "*.OBJ", "*.INC"):
        for f in sorted((SRC / "LIB").glob(pat)):
            shutil.copy(f, BUILD / "LIB" / f.name.upper())
            n += 1
    for pat in DATA:
        for f in sorted(SRC.glob(pat)):
            shutil.copy(f, BUILD / f.name.upper())

    # The author's Turbo Vision path becomes this install's. Read and written as
    # latin-1 bytes so nothing else in the file is disturbed.
    cfg = (SRC / "TPC.CFG").read_text(encoding="latin-1")
    fixed = re.sub(r"(?im)^/U.*$", r"/U.\\LIB;" + units_path.replace("\\", "\\\\"), cfg)
    if fixed == cfg:
        raise SystemExit("TPC.CFG: no /U line found -- refusing to guess")
    (BUILD / "TPC.CFG").write_text(fixed, encoding="latin-1")
    return n


def write_batch(targets, tpc):
    r"""TPC picks up the STAGED TPC.CFG because it sits in the current directory.

    That matters: a TPC.CFG in the current directory REPLACES the one beside
    TPC.EXE rather than adding to it, so C:\TP701\BIN\TPC.CFG's own
    /UC:\TP701\UNITS does not apply and the staged file has to carry it. This is
    why stage() rewrites the /U line instead of appending a second one.
    """
    lines = ["@echo off", "echo === VangeliSTracker 1.39b > D:\\BUILD.LOG"]
    for t in targets:
        lines += [
            "echo. >> D:\\BUILD.LOG",
            f"echo ---- {t} >> D:\\BUILD.LOG",
            f"{tpc} {t} >> D:\\BUILD.LOG",
            "if errorlevel 1 echo ** FAILED >> D:\\BUILD.LOG",
            "if not errorlevel 1 echo ** OK >> D:\\BUILD.LOG",
        ]
    (BUILD / "BUILD.BAT").write_text("\r\n".join(lines) + "\r\n", encoding="ascii")


CONF_TEMPLATE = """\
# DOSBox-X configuration for building VangeliSTracker 1.39b with TP 7.01.
# GENERATED by v1.31b/relbuild.py -- edit that, not this.
#
# Drives:
#     C:  the drive image from kit.local.toml, holding the TP 7.01 install
#     D:  {build}    the staged release source

[sdl]
autolock    = false
waitonerror = false

[dosbox]
machine  = svga_s3
memsize  = 16
captures = capture
title    = {title}

[cpu]
core    = auto
cputype = pentium_ii
cycles  = max

[render]
frameskip = 0
aspect    = false

[mixer]
nosound = true

[dos]
xms = true
ems = true
umb = true
lfn = false

[autoexec]
mount C {hdd}
mount D {build}
set PATH=%PATH%;{binpath}
D:
call D:\\BUILD.BAT
exit
"""


def write_conf(binpath):
    CONF.write_text(CONF_TEMPLATE.format(
        build=BUILD, hdd=machine("dosbox.hdd"), binpath=binpath,
        title="VangeliSTracker 1.39b build"), encoding="ascii")


def run_dosbox(timeout):
    cmd = [str(machine("dosbox.exe")), "-conf", str(CONF), "-silent", "-exit"]
    try:
        subprocess.run(cmd, cwd=str(ROOT), timeout=timeout,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "TIMEOUT - dosbox-x did not exit"
    return None


def report(log):
    """Print the log and summarise. TPC writes one line per unit it compiles."""
    print(log.rstrip())
    ok, bad = log.count("** OK"), log.count("** FAILED")
    errs = re.findall(r"(?im)^(.*\(\d+\):\s*(?:Error|Fatal).*)$", log)
    print("\n" + "-" * 62)
    for e in dict.fromkeys(errs):
        print("  " + e.strip())
    tpus = list(BUILD.glob("*.TPU")) + list((BUILD / "LIB").glob("*.TPU"))
    exes = sorted(p.name for p in BUILD.glob("*.EXE")
                  if p.name not in ("MAKESTR.EXE", "GETFONT.EXE"))
    print("  %d program(s) OK, %d failed" % (ok, bad))
    print("  %d .TPU in build/vt -- what relmatch.py reads" % len(tpus))
    print("  executables: %s" % (", ".join(exes) or "none"))
    return bad == 0 and len(tpus) > 0


def main(argv):
    targets = [a.upper() for a in argv if not a.startswith("-")] or PROGRAMS
    for t in targets:
        if not (SRC / t).exists():
            raise SystemExit("no such source: v1.39b/%s" % t)

    try:
        tpc = machine("toolchain.tp7")
        dosbox = pathlib.Path(machine("dosbox.exe"))
        hdd = pathlib.Path(machine("dosbox.hdd"))
    except project.Missing as exc:
        return project.complain(exc)

    if not dosbox.exists():
        raise SystemExit("DOSBox-X not found at %s (dosbox.exe)" % dosbox)
    if not hdd.is_dir():
        raise SystemExit("no drive image at %s (dosbox.hdd)" % hdd)
    if not on_image(tpc):
        raise SystemExit("TPC.EXE not on the drive image at %s -- fix "
                         "toolchain.tp7 in kit.local.toml. A build cannot "
                         "detect this itself; see on_image()." % tpc)

    binpath, install = dos_dir(tpc)
    units = install + "\\UNITS"
    print("staging v1.39b -> %s" % BUILD)
    print("  %d source file(s)" % stage(units))
    print("  TPC.CFG /U rewritten to .\\LIB;%s" % units)
    write_batch(targets, tpc)
    write_conf(binpath)

    print("compiling %s with %s ..." % (", ".join(targets), tpc))
    err = run_dosbox(timeout=600)
    if err:
        raise SystemExit(err)
    log = BUILD / "BUILD.LOG"
    if not log.exists():
        raise SystemExit("no BUILD.LOG -- the autoexec did not run")
    good = report(log.read_text(encoding="latin-1"))
    if good:
        print("\n  now: python relmatch.py")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
