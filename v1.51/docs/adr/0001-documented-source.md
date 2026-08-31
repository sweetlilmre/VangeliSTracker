# 1. `clean-src` becomes a documented source, not a stripped one

Date: 2026-08-30
Status: accepted — implemented across all 34 units, 2026-08-31.
Outcome: `../09-documentation-transform.md`.

## Context

`clean-src` was meant to be the v1.51 reconstruction with its reverse-engineering apparatus removed and explanatory documentation put in its place. What it became was the reconstruction with its **addresses** removed: 2,009 address-only comments dropped and 901 prefixes trimmed, and every word of reasoning behind them left standing.

Measured on the current tree:

| | |
|---|---|
| `clean-src/*.PAS` | 34 files, 20,710 lines, **59% of lines inside comments**, 2,209 comment blocks |
| Still apparatus | 628 name a segment or hex address, 397 compare against the release, 153 cite the image, 145 transcription talk, 112 withdrawn history, 61 name an instrument |
| Routines | 508 declarations; 366 have a comment above, but it is apparatus, not purpose |
| Assembler | ~96 inline BASM blocks, **18 carry an equivalent-Pascal block**; `PLAYMOD.ASM` 213/260 lines commented, `SOUNDDEV.ASM` 84/155 |

And in `src`, which is where the split has to happen — 4,218 comments:

| | |
|---|---|
| 2,121 | no apparatus signal at all; carry through untouched |
| 1,431 | short apparatus-only citations; drop mechanically, nothing lost |
| **666** | **tangled** — evidence and explanation in one comment, **499 of them full paragraphs** |

The tangle is the problem. This is surgery on ~666 comments, not a filter.

## Decision

### One tree of record

Explanatory prose is authored **in `src`**, alongside the apparatus, and the stripper carries one through and drops the other. `clean-src` stays derived and regenerable.

The alternative — seeding `clean-src` once and hand-editing it thereafter — strands it the moment `src` changes, and `src` changed six times in one day this week. The reconstruction of record must keep its evidence; that evidence is the expensive part of this project.

### The mark is a tagged paragraph

A blank-line-separated paragraph opening with **`[re]`** is apparatus and is stripped. A paragraph opening with **`[reading]`** is a claim resting only on someone's reading of the instructions; it is **kept**, so a reader can tell the author's fact from an inference at a glance, and so inferences can be counted.

Keep-by-default, not strip-by-default: 2,121 comments then need no edit at all. The precedent is `[1.39b]`, already in the tree and already surviving the stripper.

In the two `.ASM` files there are no blank-line paragraphs, so the tag goes immediately after the `;`, same spelling, and a run of consecutive tagged lines strips as one block.

### The mechanical dropper stays

Pattern-dropping of address-only comments continues alongside tagging. It handles the 1,431 pure citations for free; tags are needed only for the 666 tangled ones — a quarter of the work.

This is deliberately two mechanisms with two blind spots. That shape produced a real defect the same week: a trimmed prefix left `{$FFFF ... }`, which Turbo Pascal reads as the far-calls directive, and the stripper's self-check is structurally blind to it because it blanks every comment in both copies before comparing. What makes two mechanisms acceptable is the checker below and the build.

### A checker, in the same gate as the build

Flag any **untagged** paragraph carrying a `segment:offset`, a `DS:$` address, an instrument name, or a `~~withdrawn~~` marker. Mechanical tells only — it says nothing about prose style, and stays silent otherwise. Same shape as `dsverify.py`.

### What gets kept that looks like apparatus

* **The `[1.39b]` release quotes.** 397 comments. These are the author's own words about the author's own code, and they are the best explanatory content in the tree — `"If there is a loop, a small mess :-)"`, `"not sure this test is a good one"`. They are not apparatus.
* **`REFERENCE ONLY` labels** on equivalent-Pascal blocks. Required by `kit/WORKING.md:252`, and they read like transcription talk.

### What the documentation is

Written for **a competent DOS/Pascal programmer meeting this program for the first time**, who wants to understand the music player. Not a beginner — nothing explains what `PUSH` does. Not a historian — the reconstruction's history is in `src`.

* **Every one of the 508 routines gets a header**, free prose, whose **first sentence says what the routine is for**. Trivial accessors get one short line and are allowed to be obvious; no routine is left bare, so a missing header never means "not done yet".
* The 366 existing headers are **rewritten** purpose-first, with the apparatus sentence usually surviving one paragraph lower under a tag.
* Inline notes where mechanism is genuinely non-obvious.
* **Every assembler block** — 96 inline and both `.ASM` files — gets an equivalent-Pascal block above it labelled reference only, and per-line documentation, per the standing rule.

### Claims must be traceable

Every explanatory claim rests on something checkable: the 1.39b release source, the `DEMOVT15` client bindings and `DEMOVT.DOC`, format specifications, hardware documentation, the call sites, or the instructions. Release first. Anything resting only on a reading of the instructions is tagged `[reading]`.

No loader implementation source may be read, quoted or adapted — libmodplug, OpenMPT, MikMod, DUMB, XMP. Format facts only. Standing constraint, unchanged.

### `clean-src` must still build byte-identical

`build.py cleanbuild.toml` then `linkbytes.py`: 0 differing bytes. It does today, and that check has already caught a defect nothing else could see. Documentation that compiles differently from the program it documents is worse than none.

### Work order

One unit per batch. Gate for each: regenerate `clean-src`, directive count 18 of 18, build, `linkbytes` 0 differing bytes, checker clean.

**`ASCIIZ` and `FILTERS` first** — small and self-contained — to settle the tagging convention and the header voice against something cheap, then review before the spine (`PLAYMOD`, `SONGUNIT`, `MODCOMMA`). Getting the convention wrong on `PLAYMOD` costs 1,400 lines of rework.

v1.31b gets the same treatment **later, as a separate decision**, once the convention has survived contact with a spine unit.

## Consequences

* `src` grows: it carries both the evidence and the explanation. At 59% comments already, it becomes a heavily annotated tree. That is accepted — one tree of record is worth the bulk.
* Two mechanisms strip, which is a known risk, mitigated by the checker and the build rather than by argument.
* 508 headers and 96 assembler blocks is a large body of writing, and every header is a new claim in a project whose recurring failure is true-looking prose no checker reads. `[reading]` exists so those claims are countable rather than invisible.
* The name `clean-src` describes what was removed. What now distinguishes it is what was added. The name is kept for continuity, but it undersells the artefact.
