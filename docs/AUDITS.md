# VOWED — Milestone Audit Records

Every milestone ends with an audit against the fixed 13-point checklist below.
A milestone is not complete until its audit is recorded here.

Audits record what is **actually true**, including failures. An audit that only
reports successes is worthless — its purpose is to catch the problem early
enough to be cheap.

## The fixed checklist

| # | Dimension | The question |
|---|---|---|
| 1 | Gameplay | Is it fun? |
| 2 | Combat | Is skill rewarded? |
| 3 | Input | Does it feel responsive? |
| 4 | AI | Do enemies behave intelligently? |
| 5 | Animation | Are state transitions clean? |
| 6 | Performance | Are frame times acceptable? |
| 7 | Architecture | Can the next system be built safely? |
| 8 | Content | Does the world feel authored? |
| 9 | Narrative | Does the story remain coherent? |
| 10 | Cinematics | Are scenes communicating rather than wasting time? |
| 11 | Audio | Is the feedback strong? |
| 12 | Assets | Are all licences documented? |
| 13 | Technical debt | What must be fixed before expansion? |

Dimensions that do not yet apply are recorded as **N/A with the milestone that
will make them applicable** — never silently skipped, so that a gap is always
visible as a gap.

---

## M0 — Architecture, repository, technology audit

**Date:** 2026-09-27
**Verdict:** ✅ **PASS.** Production proceeds to M1.
**Full detail:** [INITIAL_AUDIT.md](INITIAL_AUDIT.md)

### Checklist

| # | Dimension | Result |
|---|---|---|
| 1 | Gameplay | **N/A** — no gameplay exists yet. Applies at M1. |
| 2 | Combat | **N/A** as implementation. **However**, the two irreversible combat decisions were made and locked this milestone (fixed 60 Hz tick; explicit shape-query hit resolution). Deferring these to M1 would have meant discovering them at M3. |
| 3 | Input | **Partial.** Input map generated and verified: 23 actions, keyboard + gamepad in parallel, physical keycodes. Responsiveness is unmeasurable without movement — applies at M1. |
| 4 | AI | **N/A** — applies at M2. |
| 5 | Animation | **N/A** — applies at M1. Canonical-skeleton requirement recorded as an M1 obligation. |
| 6 | Performance | **N/A** as measurement. Budgets published (`TECH_STACK.md` §4): 16.6 ms frame, <2000 draw calls, <1.5 GB texture, <3.5 GB process. Enforcement monitor is an M1 deliverable. |
| 7 | Architecture | ✅ **PASS.** Greenfield. `src/` ⟂ `data/` rule established. Dependency direction fixed. Collision layers allocated for the project's lifetime. Save contract defined. Region boundary contract scheduled for M1. |
| 8 | Content | **N/A** — applies at M4. |
| 9 | Narrative | **N/A** — applies at M6. `LORE_BIBLE.md` gated to M6 deliberately: it must exist before narrative content is authored, and M6 is the first milestone that authors any. |
| 10 | Cinematics | **N/A** — applies at M6. |
| 11 | Audio | **N/A** — applies at M3. |
| 12 | Assets | ✅ **PASS (vacuously).** Zero external assets acquired, so zero undocumented. The record (`ASSET_LICENSES.md`, `assets/licenses/assets.json`) exists *before* the first asset, which is the only way this check stays cheap. |
| 13 | Technical debt | ✅ **PASS.** Zero inherited debt — the repository was empty. 10 risks registered with named mitigations and milestone owners. |

### What was verified by execution, not by assertion

The project was run headless and its self-check passed:

```
physics tick  : 60 Hz            ← locked value confirmed in force
renderer      : forward_plus     ← confirmed
3d physics    : Jolt Physics     ← confirmed active, not just configured
input actions : 15/15 present
layers        : 12/12 correct
configuration OK
```

This matters because every one of those settings fails *silently*. A project
that quietly runs at a different tick rate produces combat bugs that get
debugged as gameplay problems for days.

### Findings

| Finding | Severity | Resolution |
|---|---|---|
| SSH key present but unregistered on GitHub; remote unreachable | Low | **Resolved during milestone.** Key registered, `git@github.com` authenticates as `ashvyagni`. |
| Blender not installed; required for bespoke assets | Medium | **Deferred to M11** by decision. M1–M6 run on open-licence external assets and graybox geometry. Installing unused tooling now would be ceremony. Tracked as R6. |
| 8 GB unified memory is the binding hardware constraint | **Critical** | Accepted and designed around. Streaming is load-bearing from the first region rather than a later optimisation. Tracked as R1, enforced by the M1 budget monitor. |
| No CI configured | Low | **Accepted.** Local `--headless` runs suffice for a solo project. Revisited at M16. |

### Decisions worth revisiting later

Recorded so that future-me knows these were *chosen*, not defaulted into:

- **GDScript-only** (no C#). Escape hatch is GDExtension/C++ per subsystem,
  profiler-triggered. If AI or streaming misses budget at M15, that is the
  planned response — not a language migration.
- **`SOULS.md` written at M9, not M3.** Documenting one Soul as a framework
  would canonise an abstraction derived from a single example.
- **Gravity set to 24.0**, not 9.8. Tuned for readable air combos. Air routes
  authored at M1 depend on this value; changing it later means retuning them.

### Debt carried into M1

None. This is the cleanest state the project will ever be in, which is precisely
why the expensive-to-reverse decisions were made now.

---

## M1 — Movement, input, combat foundation

**Status:** 🔨 In progress. Audit pending.

Exit criteria are defined in [MILESTONES.md](MILESTONES.md#m1--movement-input-combat-foundation).
The criterion that decides the milestone: *is punching things, with no Soul and
no enemy AI, already satisfying?*
