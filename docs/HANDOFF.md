# VOWED — Handoff

**Written:** 2026-09-28 · **At commit:** `b23ddd8` · **Branch:** `main` ·
**Remote:** `git@github.com:ashvyagni/Vowed.git` (SSH working, 17 commits pushed)

This file exists so that an agent or developer arriving with **no prior context**
can pick the project up without re-deriving it. Read this first, then
`docs/MILESTONES.md` for the plan and `docs/COMBAT.md` for the system that
matters most.

> **Status in one line:** M1 (movement, input, combat foundation) is
> substantially built and green — 115 unit tests, 12 integration cases, all
> passing — but **M1 is NOT signed off**, because its final exit criterion is a
> human playtest verdict and the current answer to it is "not yet".

---

## 1. What this project is

**VOWED** is a stylised 3D open-world fantasy action RPG built in **Godot 4.7.2**
with **GDScript only**. Beast Souls change *how you fight*, not damage numbers.
Twelve races, ~30 Prime Beasts, twelve major regions, authored cinematics, a
full lore bible.

The owner is **Ashwin** (GitHub `ashvyagni`).

### Standing directives from the owner — these are not negotiable

These come from a master directive given at project start. They have been
followed throughout and must continue to be.

1. **This is a full-scale commercial game.** Not a prototype, portfolio piece,
   student project or indie experiment. **Never lower the quality bar because
   the team is small.**
2. **Never cut scope on grounds of ambition.** "Too ambitious for a solo dev" is
   not an acceptable response. Decompose intelligently instead.
3. **Combat is the highest-priority system**, at fighting-game grade: real frame
   data, cancel windows, input buffering, air combat, 100+ authored routes.
4. **The input language is a fighting game's, not an MMO ability bar:**
   `J` Kick · `K` Punch · `Space` Jump · `Shift` Dash · `Q` Guard/Parry ·
   `E` Soul Technique · `R` Manifestation · `Tab` Lock-on.
5. **No public beta, early access, demo or MVP launch.** The first public
   release is the finished game.
6. **Work in large milestones** using BUILD → PLAYABLE STATE → AUDIT → FIX →
   DOCUMENT. Every milestone leaves the repo runnable and ends with an audit.
7. **Commit and push to GitHub regularly** using the owner's account — they are
   actively building their contribution graph. This is an explicit instruction,
   not a nicety.
8. **Asset licensing is strict.** See §7. If a licence cannot be established,
   **do not ship it.**
9. Make reasonable decisions autonomously; document architectural reasoning;
   replace weak ideas with stronger ones rather than asking permission for
   every call.

### Owner's most recent instruction

> "try to find more open source libraries and you have my permission to download
> them if they are safe, no purchases have to be issued in any case"

Downloading permissively-licensed assets is authorised. **Purchases are not.**
See §8 for exactly where that search got to.

---

## 2. How to run and verify it

```bash
godot --path .
```

Boots straight into the Combat Lab (`res://scenes/lab/CombatLab.tscn`), which is
the main scene. The full verification gate:

```bash
bash tools/check.sh
```

That runs five stages: import/class registry, boot self-check, 115 unit tests,
12 integration cases, and the asset-licence register. **It must be green before
every commit.** As of `b23ddd8` it is.

Other entry points:

| Command | Purpose |
|---|---|
| `godot --headless --path . -s tests/framework/TestRunner.gd` | Unit tests only |
| `godot --headless --path . res://tests/integration/CombatPipeline.tscn` | Integration only |
| `godot --headless --path . -s tools/bootstrap_player_moveset.gd` | **Regenerate all attack/route data** from code |
| `godot --headless --path . -s tools/lab_builder.gd` | Rebuild the Lab scenes |
| `python3 tools/validate_assets.py` | Asset licence register check |

> **Important:** attack and route `.tres` files in `data/` are **generated** by
> `tools/bootstrap_player_moveset.gd`. Edit the bootstrap and re-run it; do not
> hand-edit the generated resources, they will be overwritten.

In-game debug keys: `F1` overlay · `F2` hitboxes · `F3` frame-step · `F4` pause ·
`F5` slow-mo · `F6` reset · `1`–`5` dummy behaviour mode.

---

## 3. Architecture — the load-bearing decisions

Full detail in `docs/ARCHITECTURE.md`, `docs/TECH_STACK.md` and
`docs/COMBAT.md`. The parts you cannot safely violate:

### `src/` ⟂ `data/`
Code is **systems**; data is **content**. Adding a Soul, Beast, race, attack or
route **must never require writing a script.** This has already been violated
once and caught (see §6, R12) — `HitReaction.float_frames` was authored,
validated, saved, and read by nothing while a hardcoded constant did the job.
Watch for that shape of bug specifically.

### Fixed 60 Hz logical combat tick
`CombatClock` (autoload, `process_physics_priority = -1000`) drives everything.
Frames are the only unit of time in combat. `delta` is never read there, timers
are never used. **Animation is *seeked* to the frame counter and paused** — it is
never played freely. Verified identical at 30 and 240 fps by an integration case.

### Explicit ordered shape queries
Hit detection uses `PhysicsDirectSpaceState3D.intersect_shape`, never `Area3D`
signals — signal order is not deterministic and combat must be.
Three phases: **GATHER → ADJUDICATE (priority/trades) → APPLY.**

### `CombatDirector` phase pipeline
Every actor, player and enemy alike, advances through
**INTENT → COMBAT → RESOLVE → MOTION** in that order, once per tick.

### Two independent gates on every action
1. **ROUTING** — does `ComboGraph` have an edge for this input in this
   situation? (*what may follow what*)
2. **TIMING** — does the current attack have a cancel window open right now,
   given what it has touched? (*when it may be left*)

Routing lives in the graph, timing lives in the attack, and **neither knows about
the other.** That separation is what keeps a large move set authorable.

### Other locked conventions
- **Authoring convention is +Z forward**, converted to Godot's −Z in exactly two
  places: `HitboxKeyframe.local_offset()` and `MotionKeyframe.apply()`.
- **Collision layer bit allocation is fixed for the project's lifetime** —
  `docs/TECH_STACK.md` §5.3.
- Input buffering runs on an **actionable-frame clock** that freezes during
  hitstop, with **peek-then-consume** semantics (a press is only spent when the
  action actually starts).
- Hit-dedup groups are scoped **per-attack on the attacker**, never on the
  victim.
- Enemies use the **identical** `CombatComponent` as the player. The only
  difference is where `ActorIntent` comes from. This is a design requirement:
  enemies must be able to out-play the player mechanically.

### Two Godot constraints worth knowing before you trip on them
- `-s` scripts compile **before** autoloads register → hence the thin-launcher +
  runtime-loaded-builder pattern used in `tools/`.
- Headless `Node3D`/`Skeleton3D` children report **identity** `global_transform`,
  and `AnimationMixer` needs `advance(0.0)` before anything is posed. Several
  tests were silently vacuous because of this; measure through the **model
  node's** basis from the **rest pose**.

---

## 4. What is actually built

### Systems (`src/`, 36 scripts)
- **Autoloads:** `GameEvents` (bus), `CombatClock`, `CombatDirector`,
  `HitEffects`, `CombatAudio`.
- **Combat:** `CombatComponent` (~600 lines, the engine), `CombatState`,
  `HitResolver`, `Hurtbox`, `HitResult`.
- **Data schema:** `AttackData`, `HitboxKeyframe`, `MotionKeyframe`,
  `CancelWindow`, `HitReaction`, `AttackLibrary`, `CombatTypes`.
- **Combo graph:** `ComboGraph`, `ComboEdge`, `ComboContext`.
- **Actors:** `Actor` (base, phase methods), `CombatAnimator`, `MotionProfile`,
  `PlayerController`, `PlayerCamera`, `TrainingDummyIntent`.
- **Input:** `IntentSource`, `PlayerIntentSource`, `ScriptedIntentSource`,
  `InputBuffer`, `CombatAction`, `ActorIntent`.
- **Debug:** `DebugOverlay`, `HitboxVisualizer`, `AutoCapture`, `Bootstrap`.

### Content (`data/`, all generated)
**16 attacks:** `jab_1`, `jab_2`, `straight`, `lunge_punch`, `uppercut`,
`counter_palm`, `dash_punch`, `low_kick`, `roundhouse`, `axe_kick`, `sweep`,
`spin_kick`, `dash_kick`, `air_punch`, `air_kick`, `dive_kick`.

**26 routes**, including:
- `K,K,K` → jab, jab, straight (→ `J` for axe kick)
- `J,J,J` → low kick, roundhouse, axe kick
- `K,K,J` → jab, jab, spin kick
- **Launcher:** `back+K` uppercut (also off `K,K` or `J`, on hit)
- **Air combo:** land the launcher → `Space` → `K` `K` `J` `J`
- Command normals: `fwd+K` lunge, `fwd+J` spin kick, `back+J` sweep
- Dash attacks: `Shift` then `K`/`J` within a few frames

**7 reactions:** light, medium, heavy, launch, knockdown, crumple, spin.

### Verification
- **115 unit tests / 238 assertions** across 4 files (combat component, combo
  graph, input buffer, camera-relative movement).
- **12 integration cases** running real scenes in a real tree with real physics.
- The test harness is **in-house** (`tests/framework/`), replacing M0's GUT
  decision. It fails zero-assertion tests, guards `can_instantiate()`, and
  reconciles discovered-vs-run counts — because a parse-error file was once
  silently skipped while the suite reported ALL PASS.

### Measured, not assumed
- Frame-rate independence: identical at 30 and 240 fps.
- Determinism: same inputs, same outcome, twice.
- Impact-frame alignment: `jab_1` extends on exactly frame 4.
- Budget: 2.2 ms frame / 1.6 ms physics / 61 draw calls in the Lab.
- Full aerial route: 5 hits, 49.2 damage, one combo.

---

## 5. The rule that has served this project best

**Measure before tuning. Then ablate the fix to confirm it was the fix.**

This was learned expensively. The aerial-chain integration case failed with
"combo 2, expected 3" and survived **four rounds of tuning** — all of it wasted,
because the failure was five separate structural defects, not a number. A
frame-by-frame probe printing both actors' positions, states and attack frames
side by side found all five in one run.

Two mechanics added during that period (`juggle_lift`, a symmetric attacker
gravity scale) were later **ablated, shown to change nothing, and deleted** —
rather than kept as plausible-looking code carrying a false comment. The same
call was made at M0 over an autoload exit-leak "fix" that measured zero change.

**Corollary, applied throughout:** a test that cannot fail is worse than no test.
Every guard added here has been **negative-tested** by reverting the thing it
guards and confirming the suite goes red. Do this. An earlier orientation test
sampled the striking hand mid-punch and always read the bind pose — reporting
the same value whether the model was right or wrong.

---

## 6. Recently fixed — do not reintroduce

All five of these were live in the last three commits. Each is now individually
guarded and negative-tested. Full write-ups in `docs/AUDITS.md`;
closed entries R10–R14 in `docs/KNOWN_ISSUES.md`.

| | Defect | Fix |
|---|---|---|
| **R10** | `Actor._jump` cancelled an attack's **body** without cancelling the **attack**. Player went airborne with a ground attack still executing; since every aerial route is authored from *no* predecessor, there was no edge to take. **The entire air game was silently unreachable.** | `CombatComponent.cancel_for_jump()` |
| **R11** | Combo routing's target state was gated on **lock-on**. Every `require_target_state` route — including the air-combo finisher — was dead unless the player had found `Tab`. Lock-on is a *camera* concern; an opponent's state is a fact about the world. | Falls back to nearest actor within `Actor.COMBAT_AWARENESS_RANGE`; lock-on still wins when engaged |
| **R12** | `HitReaction.float_frames` / `float_gravity_scale` were **dead data** — a hardcoded `0.45` sat in their place. Retuning launch float in the data did nothing and said nothing. | Wired via `CombatComponent.float_frames_left` |
| — | Airborne victims were put into **ground** hitstun, killing their float and making target-state routes illegal mid-juggle. | Airborne branch in `_enter_hitstun` |
| — | The attacker had **no share of the juggle's hang time**. The aerial route is ~98 frames of frame data; a 2.0 m jump lasts ~36. | `MotionProfile.air_attack_fall_scale`, **descent only** |
| **R13** | `tools/check.sh` reported "OK — 0 class(es)" every run — it grepped `class=` in a file that writes `"class": &"Name"`. The gate's first stage passed unconditionally. | Counts the real key, asserts a floor of 25 |
| **R14** | The Lab's HUD advertised `SOUL E` / `MANIFEST R` as working controls and listed **none** of the 26 routes. | Unimplemented keys marked; every route listed |
| — | **The character model faced backward.** Reported as four separate bugs (W moved away from camera, A/D swapped, dash backward, jump animation forward while body went back). One defect: the mesh faces +Z, the project uses −Z. It moonwalked. | `model.rotation.y = PI` in `tools/lab_builder.gd` |

**The organising rule now documented for air combat: a juggle is a shared fall.**
Attacker and victim descend at the same rate (both `0.30`). The attacker's hang
applies to **descent only** — scaling gravity both ways buys *height*, not time,
and made the player levitate to 3.5 m mid-string.

---

## 7. Asset licensing — read before touching `assets/`

Full policy in `docs/ASSET_LICENSES.md`. The short version:

> **An asset with no licence record is treated as absent.**
> Records are written **at acquisition time**, never retroactively.

- **Acceptable:** CC0 / public domain, CC-BY (attribution required), MIT /
  Apache-2.0 / BSD, OFL for fonts.
- **Rejected:** CC-BY-SA (share-alike is incompatible with a proprietary game),
  any CC-NC, **"free to use" with no named licence** (not a licence — no
  enforceable terms), anything ripped from a commercial game, and **AI-generated
  assets whose training provenance cannot be established.**
- Verify the licence **on the exact asset's own page**, never from a search
  snippet. Pack-level claims are insufficient.
- Record in **both** `docs/ASSET_LICENSES.md` and `assets/licenses/assets.json`.
  `tools/validate_assets.py` enforces both directions — an unregistered file in
  `assets/` fails the gate.
- **If licensing cannot be established: do not use it.** Ambiguity is a
  rejection, not a risk to weigh.

**Currently registered (2 assets, both CC0, both verified in-bundle):**
Quaternius Universal Animation Library (free tier) + its Mannequin rig, and a
curated subset of Kenney Impact Sounds.

---

## 8. Where the work stands right now

### The blocking content gap: no kick animations

**9 of 16 attacks play a placeholder** (`Sword_Attack`, a large committed arm
swing): `low_kick`, `roundhouse`, `uppercut`, `axe_kick`, `sweep`, `spin_kick`,
`air_kick`, `dive_kick`, `dash_kick`. Each is flagged
`anim_is_placeholder = true` and the bootstrap prints the count every run, so the
gap stays measured rather than half-remembered.

This is **the largest outstanding problem in the project**, and it is not
cosmetic. Kick is half the input language (`J`). The owner reported the kick
string as *missing entirely* when in fact `J,J,J` works perfectly — because with
a sword-swing clip playing, **a working route is indistinguishable from a broken
one by eye.**

### Asset search — in flight, incomplete

The owner authorised downloading safe open-source libraries (no purchases). The
search so far, with licences verified at source:

| Source | Licence | Verdict |
|---|---|---|
| Quaternius UAL **1** free tier (in use) | CC0 ✅ | 46 animations, **no kicks** |
| Quaternius UAL **2** free tier | CC0 ✅ | Downloaded and inspected: **43 animations, no kicks.** Also a *different rig* (65 joints, UE naming `root`/`pelvis`/`spine_01`) vs UAL1's Mannequin (53 joints, Rigify `DEF-` naming) — would need retargeting. Has `Melee_Hook`, `Sword_Regular_A/B/C`, `Hit_Knockback`, `Slide`, `NinjaJump`. |
| KayKit Character Animations (OpenGameArt mirror) | CC0 ✅ | Mirror is **v1.2 from 2022** — older/smaller, **no kicks** |
| **KayKit Character Animations v1.1 (itch.io, 161 anims)** | CC0 ✅ | **`Unarmed_Melee_Attack_Kick` confirmed to exist.** Best known lead. Download **not completed** — itch.io needs the interactive name-your-price flow ("No thanks, just take me to the downloads"); driving it via the browser pane got as far as the signed download page (upload_id `15799903`, file "Free 1.1", 14 MB) before the attempt stalled. Rig is KayKit's own `Rig_Medium` → will need retargeting. |
| Motifect Martial Arts Motion Pack | ❌ **Rejected** | Advertises taekwondo kicks, but it is an **AI motion generator** with **no named licence** — rejected on two independent policy grounds |
| Quaternius UAL PRO tier | CC0 | Has kicks, but **$9.99 — purchases are not authorised** |
| CMU mocap database | Permissive custom | Has martial arts, but **BVH only**; Godot cannot import BVH and **Blender is not installed** (tracked as A1) |

**Two viable paths forward, pick one:**

1. **Finish the KayKit download** (CC0, confirmed kicks) and retarget from
   `Rig_Medium` to the Mannequin using Godot's built-in `BoneMap` /
   `SkeletonProfileHumanoid` retargeting — no Blender required.
2. **Author the kicks as original Godot `Animation` resources** keyed directly to
   the existing rig. Zero licensing risk, and — because this game seeks
   animation to the frame counter — it gives *exact* impact-frame alignment,
   which a retargeted mocap clip does not. Stiffer-looking, but arguably the
   better fit for a fighting game.

A scratch copy of the UAL2 zip and the KayKit 1.2 zip are in the session
scratchpad, **not** in the repo. Nothing has been added to `assets/` — so
nothing needs unwinding if you take a different path.

### Immediate next steps

1. **Resolve the kick animations** (above). Highest value; it is what stands
   between the owner and a fair judgement of M1.
2. **M1 audit + exit-criteria review.** Criteria 1–11 are demonstrably met.
   Criterion 12 — *"is punching things, with no Soul and no enemy AI, already
   satisfying?"* — is a **human verdict**, and the owner's current answer is no.
   It should be re-asked once kicks read correctly.
3. **Then M2: enemy AI.** Enemies reuse the identical `CombatComponent`; only
   the `ActorIntent` source differs.

### Open issues carried

`docs/KNOWN_ISSUES.md` has the full register. Live ones: **I1** exit-time
resource leaks (Godot-side, cosmetic; an attempted autoload cleanup measured
*zero* change and was reverted), **I2** vsync, **A1** Blender not installed,
**A5** 8 GB unified memory on the dev machine (designed around, not engineered
away).

---

## 9. Working agreements that are already in force

- **Commit style:** subject states the *defect or the change*, body explains the
  *reasoning and the measurement*. Commits here are long and they should stay
  long — the reasoning is the valuable part, and several of these commits are the
  only record of why a number is what it is.
- Commits are co-authored: `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- **`bash tools/check.sh` green before every commit.** No exceptions.
- **Document the reasoning, not just the change.** `docs/AUDITS.md` records
  decisions that were *chosen* rather than defaulted into, including the ones
  later reversed and why.
- When a rationale is disproven, **delete the code or rewrite the comment.**
  Do not leave a correct-looking mechanism with a false justification attached.
- Report outcomes faithfully. If something is unverified, say so.
