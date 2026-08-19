"""Compile the DemoVT reconstruction with the real Turbo Pascal 6.

    python v1.31b/build.py             compile every transcribed unit
    python v1.31b/build.py VTCTRL      compile one
    python v1.31b/build.py --tp7       ...with Turbo Pascal 7.01 instead
    python v1.31b/build.py --sw=/$G-   ...with an extra compiler switch

The five units written before this script existed had NEVER been through a
compiler -- "compilable Pascal" was an untested claim in the docs. This is
what makes it testable.

Reuses tools/dosbox/vt131.conf unchanged, which mounts D: on <root>/build and
runs D:\\BUILD.BAT. That means this script SHARES the build directory with
tools/dosbox/dosbuild.py and both wipe it on entry, so they cannot run at the
same time -- run one, read the result, then run the other.

Unlike the main project, no 8.3 renaming happens here: every DemoVT source is
already an 8.3 name and every unit identifier already matches its filename.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "v1.31b" / "src"
BUILD = ROOT / "build"
CONF = ROOT / "tools" / "dosbox" / "vt131.conf"
DOSBOX = Path(r"D:\DOSBox-X\dosbox-x.exe")

# Compile order. TP7 resolves `uses` against .TPU files, so a unit has to be
# built after everything it imports. Leaves first, VTMAIN last -- it is the
# PROGRAM (segment 1000), not a unit.
# The compiler switches the original was actually built with, taken verbatim
# from TPC.CFG in the VangeliSTracker 1.39b source release. They had been
# guessed at before this (only /$S-), which is a poor foundation for a
# byte-exact target: $G+ alone decides whether 286 instructions are emitted at
# all, and every unit except VTPLAYER was being compiled as plain 8086.
#
# Omitted deliberately:
#   /U /O   unit and object paths -- the build directory is flat here
#   /M      make -- this script drives the order itself. TRIED AND REVERTED: it
#           was added to let TPC resolve SongUnit's circular reference to the
#           two loader units on demand, and TP6 answers `Error 68: Circular unit
#           reference` rather than accepting it. TP7 tolerates the same shape,
#           which is how the 1.39b release builds. See SONGUNIT.PAS's note at
#           SongLoaders for what is done instead.
#   /GD     detailed .MAP -- add it back when the map becomes useful
#   /V      debug info in the .TPU; the shipped binary was run through
#           tdstrip, so it carries none
#
# $D+/$L+ are kept because they are in the original's configuration; they add
# debug information rather than code, and tdstrip removes it afterwards.
SWITCHES = "/$A+ /$B- /$D+ /$E+ /$F- /$G+ /$I- /$L+ /$N+ /$O- /$R- /$S- /$V- /$X+"

# Which compiler to invoke. TURBO PASCAL 6 IS THE DEFAULT, and that is a result
# rather than a preference: the standing suspicion that the original was not
# built with TP7 (docs/CONTINUATION.md, risk 2) was tested the moment a TP6
# install appeared beside it, and TP6 won. 116a goes from three divergent
# regions to BYTE-IDENTICAL -- including the reload of a string pointer that TP7
# elides and that had been parked as unreachable from source -- and 1a17 drops
# from ten regions to six, losing both halves of the inlined string copy. No
# unit got worse. `--tp7` builds with the other one for comparison.
#
# TP6's install is flat -- TPC.EXE sits in C:\TP6 rather than a BIN
# subdirectory -- and its own TPC.CFG beside it carries the unit path, so
# nothing else has to change. Its dialect does, though: see tp6_dialect.
# C:\TP61 is Turbo Pascal 6.01 (TPC.EXE dated 11-Jun-1991, 69,278 bytes) beside
# 6.0's 69,214 of 23-Oct-1990. Risk 2 in the handover names "a different TP6
# patch level" as one of the three candidate explanations for the divergences
# that survive both compilers, so it is worth one build: `--tp61`.
# Turbo Assembler, for units that link an object module with $L. 1a17's
# 0746..10c3 was built that way in the original (docs/06-transcription.md), and
# the 1.39b release builds the same unit that way. Any v1.31b/src/*.ASM is
# assembled before the Pascal, and its .OBJ is left in build/ for the $L to
# find.
TASM = r"C:\TASM\BIN\TASM.EXE"

COMPILERS = {
    "tp6": r"C:\TP6\TPC.EXE",
    "tp61": r"C:\TP61\TPC.EXE",
    "tp7": r"C:\TP\BIN\TPC.EXE",
}

ORDER = [
    "ASCIIZ.PAS",     # 1642  leaf
    "VTNOTES.PAS",    # 1650  leaf
    "FILTERS.PAS",    # 1544  leaf
    "VTCTRL.PAS",     # 14b7  leaf -- owns the control block
    "VTDOSRSZ.PAS",   # 188f  leaf
    "VTDOSMEM.PAS",   # 1880  leaf
    "FILEUTIL.PAS",   # 116a  leaf
    "VTSHELL.PAS",    # 1931  needs Dos
    "HARDWARE.PAS",   # 1b24  needs Dos (GetIntVec/SetIntVec)
    "VTDRIVER.PAS",   # --    no segment: the shared driver record
    "SOUNDDEV.PAS",   # 1a17  the player core -- complete
    "SOUNDBLA.PAS",   # 19a0  A DECLARED STUB -- four variables, no code
    "VTGLOBAL.PAS",   # --    no segment: the shared settings
    "DEVSB.PAS",      # 193a  the Sound Blaster device unit
    "GUS.PAS",        # 1723  the GUS hardware layer
    "DEVGUS.PAS",     # 1084
    "VTSILENC.PAS",   # 1065  BLOCKED on 1a17
    "VTRESID.PAS",    # 1b54
    "HEAPS.PAS",      # 17cf  the memory pool
    "SONGELEM.PAS",   # 165a  instrument, track, pattern -- IN PROGRESS
    "UNKLOADE.PAS",   # 164b  compiled against the BOOTSTRAP SongUnit
    "MODLOADE.PAS",   # 154d  ditto -- see the bootstrap note below
    "SONGUNIT.PAS",   # 14b9  the module object -- complete; needs the loaders
    "MODCOMMA.PAS",   # 142f  A STUB, and the home of TCanal
    "PLAYMOD.PAS",    # 12ba  IN PROGRESS -- transcribed from the top down
    "CMDLINE.PAS",    # 116e  the command line
    "VTCFG.PAS",      # 11bb  the config file
    "VTCMD.PAS",      # 109c  the switch table -- IN PROGRESS (needs VTCfg)
    "VTMAIN.PAS",     # 1000  the program -- BLOCKED, see below
]

# Transcribed but not yet compilable, because they call into units that have
# not been transcribed. This is a real dependency, not a defect: VTMAIN is the
# program and reaches into twelve segments that do not exist yet, through
# `Unit_<seg>_<ofs>` placeholders. Listing it here keeps the build honest --
# it is reported as blocked rather than counted as either passing or failing.
BLOCKED = {}


# Turbo Pascal 6 has no `far` DIRECTIVE on a unit's exported routines at all.
# It rejects one on the interface declaration (error 73, IMPLEMENTATION
# expected) and it rejects one on the implementation header of a routine the
# interface already declared (error 36, BEGIN expected). The calling model comes
# from {$F} at the point of declaration and nowhere else; TP7 relaxed that.
#
# So the rewrite is a SWITCH, not a moved directive: `{$F+}` from the interface
# keyword to the implementation keyword, where the state SWITCHES has set for
# the unit resumes. That reproduces our TP7 shape exactly -- the interface's
# routines far because they are declared under $F+, the implementation's private
# routines near because they are declared after it goes back off. Turning $F+ on
# for the whole unit instead would promote the private routines too.
#
# The staged copy only; v1.31b/src is untouched.
DECL_TAIL = r"(?:\s*\([^()]*\))?(?:\s*:\s*\w+)?\s*;"


def tp6_dialect(text, restore="{$F-}"):
    """Replace the interface's `far` directives with an {$F+} region."""
    iface = re.search(r"(?im)^interface\b[ \t]*$", text)
    impl = re.search(r"(?im)^implementation\b", text)
    if not (iface and impl):
        return text
    head, body = text[: impl.start()], text[impl.start():]

    n = 0

    def strip(m):
        nonlocal n
        n += 1
        return m.group(1)

    # The declaration is matched WHOLE rather than up to the first semicolon: a
    # parameter list separates its groups with semicolons too, so `[^;]*` stops
    # short on every routine that takes more than one group.
    head = re.sub(r"(?is)(\b(?:procedure|function)\s+\w+\b" + DECL_TAIL +
                  r")\s*far\s*;", strip, head)
    if not n:
        return text                       # nothing exported far -- leave alone

    head = head[: iface.end()] + "\n{$F+}" + head[iface.end():]
    return head + body.replace("implementation", "implementation\n" + restore, 1)


def is_program(text):
    return re.search(r"(?im)^\s*program\s+\w+\s*;", text) is not None


def lint_sources(only):
    """Run tools/paslint.py's checker over v1.31b/src. Returns True if clean."""
    sys.path.insert(0, str(ROOT / "tools"))
    try:
        from paslint import check           # type: ignore
    except Exception as exc:                # paslint absent or unimportable
        print("paslint unavailable (%s) -- skipping lint" % exc)
        return True
    total = 0
    for name in ORDER:
        if only and name.split(".")[0] not in only:
            continue
        f = SRC / name
        if not f.exists():
            continue
        probs = check(f)
        if probs:
            print("\n=== %s ===" % f.name)
            for ln, msg in probs:
                print("  line %4d  %s" % (ln, msg))
            total += len(probs)
    return total == 0


def prepare(only, compiler="tp6", extra="", keep=False):
    """Stage the sources. `keep` leaves existing .TPUs in place.

    THE WIPE IS NORMALLY THE POINT -- a stale .TPU has produced a confidently
    wrong claim here twice, and verify.py reports STALE rather than lying only
    because build.py starts clean. `--keep` exists for ONE measurement that a
    clean build cannot make: SongUnit's implementation must use UnkLoader,
    whose interface uses SongUnit, and TP6 answers Error 68 compiling that from
    scratch because whichever goes first needs the other's .TPU. If the .TPUs
    already exist it may simply compile -- which is how a 1992 developer would
    have hit it and not noticed, since .TPUs accumulate and only a clean build
    deadlocks. See docs/CONTINUATION.md on SongLoaders.

    ANYTHING MEASURED UNDER `--keep` IS SUSPECT UNTIL A CLEAN BUILD AGREES.
    """
    BUILD.mkdir(exist_ok=True)
    if not keep:
        for f in BUILD.glob("*"):
            if f.is_file():
                f.unlink()

    staged = []
    for name in ORDER:
        if only and name.split(".")[0] not in only:
            continue
        if name in BLOCKED and not only:
            continue                      # reported separately, not compiled
        src = SRC / name
        if not src.exists():
            continue                      # not transcribed yet -- skip quietly
        text = src.read_text(encoding="utf-8", errors="replace")
        # TP7 is a DOS tool and chokes on anything above 7 bits in source.
        text = text.encode("cp437", errors="replace").decode("cp437")
        if compiler.startswith("tp6"):   # tp6 and tp61 share the dialect
            text = tp6_dialect(text)
        (BUILD / name).write_text(text, encoding="cp437", errors="replace")
        staged.append(name)

    # Assembler modules travel with the units too, and are assembled FIRST so
    # that the .OBJ exists when TPC reaches the $L. /la leaves a listing, which
    # is the quickest way to see what byte an instruction assembled to.
    asm = []
    for src in sorted(SRC.glob("*.ASM")):
        text = src.read_text(encoding="utf-8", errors="replace")
        text = text.encode("cp437", errors="replace").decode("cp437")
        (BUILD / src.name).write_text(text, encoding="cp437", errors="replace")
        asm.append(src.name)

    # Include files travel with the units. They are not compiled in their own
    # right, so they never appear in ORDER, but TP7 looks for them beside the
    # .PAS and will not find them otherwise.
    for inc in sorted(SRC.glob("*.INC")):
        text = inc.read_text(encoding="utf-8", errors="replace")
        text = text.encode("cp437", errors="replace").decode("cp437")
        (BUILD / inc.name).write_text(text, encoding="cp437", errors="replace")

    # The batch clears the .TPUs too, so `--keep` has to reach in here as well
    # -- wiping the directory from Python and then deleting them again inside
    # DOSBox are two separate erasures and the first fix missed the second.
    lines = ["@echo off"]
    if not keep:
        lines.append("del *.TPU > NUL")
    lines.append("echo === DemoVT build > BUILD.LOG")

    for name in asm:
        lines.append("echo. >> BUILD.LOG")
        lines.append("echo --- %s >> BUILD.LOG" % name)
        lines.append("%s /la /m2 %s >> BUILD.LOG" % (TASM, name))
    for name in staged:
        # THE BOOTSTRAP PASS, emitted immediately before the first loader.
        # SongUnit's implementation names UnkLoader's and ModLoader's entry
        # points, and both of those units `uses SongUnit` in their INTERFACE.
        # TP6 refuses that cycle from scratch (Error 68) because whichever unit
        # compiles first needs the other's .TPU -- but it accepts it once they
        # exist. So compile SongUnit once with /DBOOTSTRAP, which takes the
        # `uses` and the table's initialiser out and leaves the INTERFACE
        # unchanged; the loaders compile against that .TPU, and ORDER then
        # recompiles SongUnit for real.
        #
        # It has to sit HERE rather than at the top of the batch: SongUnit
        # needs Heaps, SongElements and the rest compiled first, so the
        # bootstrap cannot run before them.
        #
        # TP7 needs none of this and the 1.39b release does not do it, which is
        # itself a small piece of evidence for TP6.
        if name == "UNKLOADE.PAS" and "SONGUNIT.PAS" in staged:
            lines.append("echo. >> BUILD.LOG")
            lines.append("echo --- SONGUNIT.PAS (bootstrap) >> BUILD.LOG")
            lines.append(r"%s %s%s /Q /DBOOTSTRAP SONGUNIT.PAS >> BUILD.LOG"
                         % (COMPILERS[compiler], SWITCHES, extra))
        text = (SRC / name).read_text(encoding="utf-8", errors="replace")
        # /M rebuilds dependencies; $S- matches the original's no-stack-check
        flag = "" if is_program(text) else ""
        lines.append("echo. >> BUILD.LOG")
        lines.append("echo --- %s >> BUILD.LOG" % name)
        lines.append(r"%s %s%s /Q %s >> BUILD.LOG"
                     % (COMPILERS[compiler], SWITCHES, extra, name + flag))
    lines.append("exit")
    (BUILD / "BUILD.BAT").write_text("\r\n".join(lines) + "\r\n", encoding="ascii")
    return staged


def run_dosbox(timeout=180):
    log = BUILD / "BUILD.LOG"
    if log.exists():
        log.unlink()
    cmd = [str(DOSBOX), "-conf", str(CONF), "-silent", "-exit"]
    try:
        subprocess.run(cmd, cwd=str(ROOT), timeout=timeout,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None, "TIMEOUT - dosbox-x did not exit"
    if not log.exists():
        return None, "no BUILD.LOG produced - autoexec did not run"
    return log.read_text(encoding="latin1"), None


def main(argv):
    only = [a.upper().replace(".PAS", "") for a in argv if not a.startswith("-")]

    compiler = "tp6"
    for name in ("tp7", "tp61"):
        if "--" + name in argv:
            compiler = name
    # `--sw=/$G-` appends to SWITCHES, for testing one switch against the
    # binary without editing the recorded configuration.
    extra = "".join(" " + a[5:] for a in argv if a.startswith("--sw="))

    # Lint FIRST. TP7 reports a nested-comment defect dozens of lines from its
    # cause, so catching it here saves a wild goose chase. paslint's own main()
    # hardcodes the main project's src/, so import its checker instead of
    # shelling out.
    if not lint_sources(only):
        print("build refused: fix the above first")
        return 2

    staged = prepare(only, compiler, extra, keep="--keep" in argv)
    if not staged:
        print("nothing staged")
        return 1
    print("compiler: %s (%s)%s" % (compiler, COMPILERS[compiler],
                                    "  extra switches:" + extra if extra else ""))
    print("staged: %s" % " ".join(staged))

    out, err = run_dosbox()
    if err or out is None:
        print(err or "no output")
        return 1
    print(out)

    # TASM prints "Error messages:    None" on every clean assembly, so a bare
    # substring test reports a successful build as a failure.
    bad = [l for l in out.splitlines()
           if ("Error" in l or "error" in l) and "messages:    None" not in l]
    print("-" * 62)
    if bad:
        print("%d line(s) reporting errors" % len(bad))
        return 1
    tpus = sorted(p.name for p in BUILD.glob("*.TPU"))
    print("OK: %d unit(s) compiled -- %s" % (len(tpus), " ".join(tpus)))
    if not only:
        for name, why in sorted(BLOCKED.items()):
            print("BLOCKED: %-14s %s" % (name, why))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
