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

### Air combat: five defects behind one symptom

The aerial-chain integration case failed with *"combo 2, expected 3"* and stayed
failing through several rounds of tuning. The tuning was the mistake. Five
separate defects were hiding behind one number, and none of them was a tuning
value:

1. **`Actor._jump` cancelled an attack's BODY without cancelling the attack.**
   An attack's JUMP cancel window granted permission, the player left the
   ground — and the attack kept executing. Jump was the one action that moved the
   actor without going through `CombatComponent.try_action`, so nothing ended the
   attack. Because every aerial route is authored from *no* predecessor
   (`"" -> air_punch`), a stale ground attack left no edge to take and the entire
   aerial game was silently unreachable. Fixed with
   `CombatComponent.cancel_for_jump`.

2. **Combo routing's target state was gated on lock-on.**
   `ComboContext.target_state` was filled only when `Actor.target` was set, and
   that is set exclusively by an explicit lock-on press. So every route carrying
   `require_target_state` — including the air-combo finisher — was dead for any
   player who had not found the Tab key, and the same button produced a different
   move depending on a camera toggle. Lock-on is a camera and steering concern;
   an opponent's state is a fact about the world. The context now falls back to
   the nearest actor within `Actor.COMBAT_AWARENESS_RANGE`, with lock-on still
   winning when engaged.

3. **`HitReaction.float_frames` and `float_gravity_scale` were dead data.**
   Authored, validated by the bootstrap, written into `launch.tres` — and read by
   nothing. `Actor._apply_gravity` used a hardcoded `0.45` for the whole LAUNCHED
   state, so retuning launch float in the data changed nothing and reported no
   error. A textbook `src/` ⟂ `data/` violation: content that looks authorable
   while the real value lives in a script.

4. **An airborne victim was put into GROUND hitstun.** Reactions are authored for
   a standing target, so applying one verbatim in midair made the victim read as
   grounded, which stopped the launch float applying and made target-state-gated
   routes illegal mid-juggle.

5. **The attacker had no share of the juggle's hang time.** The arithmetic is not
   close: the four-attack aerial route is ~98 frames of frame data before any
   hitstop, and a 2.0 m jump is airborne for ~36. The attacker sank while the
   victim hung, so by the finisher the player was 1.5 m *below* a target it dives
   downward at. Fixed with `MotionProfile.air_attack_fall_scale`, applied to
   **descent only** — scaling gravity in both directions was tried first and was
   wrong, because weaker gravity against an upward velocity buys *height*, and
   the player levitated to 3.5 m mid-string. Hang time and jump height are
   different quantities.

**Two mechanics were reverted after measurement disproved their rationale.** A
per-reaction `juggle_lift` impulse and a symmetric attacker gravity scale were
both added while the diagnosis was wrong. Ablating each against the four-hit
route changed nothing — the authored launch float already does that work. Both
were removed rather than kept as harmless-looking code with a false comment
attached, which is the same call made at M0 over the autoload exit-leak cleanup.

**The launch retune was kept, but reclassified.** `launch_velocity` went from
`(0, 9.0, 1.5)` to `(0, 5.8, 0.25)`. Measured: at 9.0 m/s the victim climbs to
~3.9 m and is still rising a second later while the player's jump apex is ~2.1 m.
The follow-ups still connected — 1.5 m of vertical error is inside a humanoid
hurtbox capsule — so no test ever objected; it simply looked absurd. This is a
feel choice and is now recorded as one, not as a fix.

**Process lesson.** Every one of these five was found by a frame-by-frame probe
printing both actors' positions, states and attack frames side by side, and none
was found by reasoning about the failing assertion. Four rounds of tuning were
spent before the first measurement. *Measure before tuning* — and when a fix
lands, ablate it to confirm it was the fix.

**Each of the five is now individually guarded**, verified by reverting each one
in turn and confirming the suite goes red:

| Mechanism | Guarded by |
|---|---|
| Jump cancels the attack | `the full aerial chain executes end to end` |
| Target state independent of lock-on | same case (the finisher is unreachable without it) |
| Authored launch float is live | `a launched actor floats at the rate its reaction authored` |
| Airborne victims stay airborne | `the full aerial chain executes end to end` |
| Attacker shares the descent | same case |

The float case asserts the *relationship* — one float frame must change the
victim's vertical velocity by exactly `gravity × directional × float_scale × dt`
— rather than a number, so retuning any input cannot make it wrong while a
hardcoded multiplier still fails it.

### Two checks that were not checking

- **`tools/check.sh` reported "OK — 0 class(es)" on every run.** It counted
  `class=` in a Godot config file that writes `"class": &"Name"`, so the number
  was always zero and the step passed unconditionally. It now asserts a floor of
  25 registered classes.
- **The Combat Lab's control list advertised `SOUL E` and `MANIFEST R`** beside
  the working keys, with nothing marking them as M3 features whose keys are bound
  and inert. A control list is a promise; listing an unimplemented key next to a
  working one means the reader's next conclusion is that combat is broken rather
  than unfinished. It also listed only individual buttons and none of the 26
  authored routes, so the string game — most of what the move set *is* — was
  invisible unless you happened to mash the right sequence.
