# VOWED — Combat System

**Status:** Implemented and running. Milestone 1.
**Describes what exists**, not what is planned. Anything not yet built is
explicitly marked `[PLANNED]`.

Combat is the highest-priority system in this project. Everything else — Souls,
enemies, bosses, Prime Beasts — is built on top of it, which is why its
architecture was locked before any gameplay code was written.

---

## 1. The two decisions everything rests on

Both are effectively irreversible, and both were made at M0 rather than
discovered at M3. They exist because **combat feel is decided by architecture,
not by tuning.**

### 1.1 The tick is authoritative; animation follows

```
_physics_process (60 Hz, fixed)
        │
        ▼
  CombatClock.tick()  ──────────────────────►  frame += 1
        │
        ▼
  CombatDirector runs the phase pipeline
        │
        ├─ 1. INTENT   every actor decides what it wants
        ├─ 2. COMBAT   every actor's state machine advances ONE frame
        ├─ 3. RESOLVE  hits resolved in ONE ordered pass over all actors
        └─ 4. MOTION   every actor commits movement to physics
                 │
                 ▼
        AnimationPlayer.seek(frame / 60.0)   ← animation is the SLAVE
```

**Animation never drives combat state.** The frame counter is truth. If you ever
find yourself reading an animation's position to decide a combat outcome, the
architecture has been violated.

What this buys, each of which is the point rather than a side effect:

| Property | Why it matters |
|---|---|
| **Frame-rate independence** | "Active on frame 7" means frame 7 at 30 fps and at 240 fps. **Verified** by an integration case that runs the same sequence at both and asserts identical results. |
| **Determinism** | Combat is a pure function of (state, input, frame). **Verified**: identical inputs produce identical damage and combo length. A bug can be reproduced from an input log. |
| **Testability** | Combo resolution, cancel windows and state transitions are unit-testable headlessly with no renderer. |
| **Debuggability** | Frame-stepping works, so frame data can be *read* during tuning instead of guessed at. |
| **Authoring in real units** | Designers reason in frames, which is how frame data is expressed and compared across the genre. |

### 1.2 Hit detection is an explicit ordered pass

`PhysicsDirectSpaceState3D.intersect_shape()` called deliberately during the
combat tick, against a dedicated hurtbox layer.

`Area3D.body_entered` is **rejected**: signal ordering is not controllable, it
fires on the physics step rather than the combat frame, and same-frame trade
rules are effectively impossible to express through it.

The pass has three phases, and they are separate for a specific reason:

1. **GATHER** — collect every candidate contact. Apply nothing.
2. **ADJUDICATE** — resolve mutual contacts (A hits B while B hits A) by attack
   priority. Equal priority = a genuine trade; both land.
3. **APPLY** — commit outcomes and raise feedback.

Because nothing is applied during gathering, **an attack cannot be cancelled by
a hit it was simultaneously landing.** Collapsing these into one loop would make
the result depend on iteration order — "whoever is earlier in the scene tree
wins", a bug invisible until two players notice the game disagrees with itself.

---

## 2. Attacks are data

Every attack in the game — player normals, Soul techniques, enemy moves,
Manifestation attacks — is an `AttackData` resource in `data/attacks/`. **No
attack exists in code.**

```
frame:  0 ....... startup-1 | startup ... startup+active-1 | ... total-1
        └── STARTUP ────────┘└── ACTIVE ─────────────────┘└── RECOVERY ┘
          committed,           hitboxes can be live         vulnerable,
          no hitbox                                          cancellable
```

| Field group | Contents |
|---|---|
| Timing | startup, active, recovery, hitstop, guard hitstop |
| Volumes | `HitboxKeyframe[]` — frame-ranged shapes with a **hit group** |
| Effect | damage, stagger, chip, resonance, `HitReaction` on hit and on guard |
| Cancels | `CancelWindow[]` — frame range + permitted actions + contact requirement |
| Motion | `MotionKeyframe[]` — authored displacement |
| Properties | interrupt armour, invulnerable frames, resonance cost, Soul gating |

### 2.1 Authoring convention: +Z is forward

Hitbox offsets and motion velocities are authored with **+Z = forward**, because
"0.72 metres in front" is what a designer means and should be able to write.
Godot's local forward is −Z, so conversion happens in exactly two places:
`HitboxKeyframe.local_offset()` and `MotionKeyframe.apply()`.

> This is not a stylistic note. An earlier version asked callers to handle the
> flip, and every hitbox in the game ended up placed **behind** its attacker
> while every lunge drove backwards. Asking each author to remember a sign flip
> is a defect generator.

### 2.2 Hit groups

Two hitbox keyframes sharing a `hit_group` connect **once** against the same
victim. This distinguishes:

- a **moving volume** (a sweeping kick — several keyframes, same group, one hit)
- a **multi-hit flurry** (several groups, several real hits)

Without it, a moving hitbox connects once per frame — the classic "my attack
does 900 damage" defect.

The record lives on the **attacker**, cleared when an attack begins, because the
scope of "already hit" is one *attack*. Holding it on the victim keyed by
attacker (as an earlier version did) meant that once `jab_1` landed with group 0,
every later attack reusing group 0 was rejected forever — a three-hit string
landed exactly one hit while the routing looked perfect.

### 2.3 Reactions are shared

`HitReaction` resources are shared between attacks on purpose, so "medium
stagger" means one consistent thing across the whole move set and the player can
build reliable intuition about what links into what.

**Pushback is a spacing budget, not flavour.** Light attacks barely move the
target so strings stay connected; heavy attacks push hard, which is what *ends* a
string and forces the attacker to re-establish position.

---

## 3. Routes are a graph

Combo routes form a **directed graph authored as data**. Nodes are attacks;
edges are `ComboEdge` resources in `data/combos/`.

```
neutral --PUNCH[neutral]-----> jab_1 --PUNCH--> jab_2 --PUNCH--> straight
                                 │                │                 │
                                 └--KICK--> low_kick                └--KICK--> axe_kick
                                                │
neutral --PUNCH[back]-----> uppercut  <---------┘ [back, on_hit]
   (launcher, 1 armour)        │
                               └--JUMP[on_hit]--> air_punch --KICK--> air_kick --KICK[target LAUNCHED]--> dive_kick
```

100+ routes means 100+ authored **edges**, which is tractable. The equivalent
branching code would be neither inspectable nor testable as a move set.

### 3.1 Conditions make routes situational

Every field beyond `from`/`to`/`action` is a condition. They are what separate a
route from an arbitrary button string:

| Condition | What it expresses |
|---|---|
| `require_direction` | One button, several attacks, selected by stick direction — how a large move set comes out of a 7-key input language instead of an ability bar |
| `require_contact` | `ON_HIT` / `ON_GUARD` / `ON_WHIFF`. The core risk mechanism: a connected attack is expressive, a whiff stays punishable |
| `require_stance` | Ground vs air |
| `require_target_state` | An aerial follow-up is legal *because* the launcher put the target in the air |
| `max_target_distance` | Spacing as a route condition |
| `min/max_combo_length` | Opens late routes; closes loops so one sequence cannot be optimal forever |
| `max_frames_since_dash` | Dash-cancel attacks, which launch from neutral and cannot use an attack-relative window |
| `require_soul`, `require_manifestation`, `require_passive_state`, `min_resonance` | Soul gating — see §6 |

### 3.2 Two independent gates

Starting an action passes two checks that do not know about each other:

1. **ROUTING** — does the graph have an edge for this input in this situation?
   (*what may follow what*)
2. **TIMING** — does the current attack have a cancel window open right now,
   given what it has touched? (*when it may be left*)

Routing lives in the graph, timing lives in the attack. So an attack can be
retimed without touching routes, and a move set rerouted without retiming
attacks. An edge may carry its own tighter window for a just-frame link.

### 3.3 The constraints are the content

If every attack cancelled into everything at any time, execution would be free
and there would be nothing to master. Mastery comes from knowing *which* attack
cancels into *what*, *when*, and *only if it hit*. The denials are the design.

---

## 4. Input

| Layer | Responsibility |
|---|---|
| `CombatAction` | The combat verbs. Gameplay refers to these, never to device strings — so an AI *intends* PUNCH rather than pressing K |
| `InputBuffer` | Frame-stamped ring buffer, zero allocation |
| `IntentSource` | Player (devices), AI `[PLANNED M2]`, Scripted (tests, replays) |

### 4.1 Buffer windows

| Window | Frames | Purpose |
|---|---|---|
| `NATURAL_WINDOW` | 6 (100 ms) | The next attack in a string — the player is entitled to this once committed |
| `PRECISE_WINDOW` | 3 (50 ms) | Advanced cancels, where precision *is* the skill being tested |

Buffering makes combat feel **responsive without making it easy**: a press
slightly early is remembered and fires as soon as it becomes legal, while cancel
windows — the actual execution skill — are unchanged.

Two rules that matter more than they look:

- **Consuming an action clears every matching press in the window.** A player
  who mashes punch three times wants one attack, not three queued over the next
  half second.
- **A press is only spent when the action actually starts.** Peek, attempt,
  consume on success. Consuming first and discarding on failure throws away a
  press made during an attack's startup — precisely the moment buffering exists
  to cover, and the source of the "the game ate my input" complaint.

---

## 5. States and defence

```
NEUTRAL ──► ATTACKING ──► (cancel window) ──► ATTACKING
   │            │
   │            └──► NEUTRAL
   ├──► GUARDING ◄──► PARRYING
   ├──► DODGING
   └──◄── HITSTUN / LAUNCHED / STAGGERED / KNOCKDOWN ──► WAKEUP ──► NEUTRAL
```

The state set is kept small on purpose: every added state multiplies the
transition surface, and combat bugs overwhelmingly live in transitions. Anything
expressible as a *property* of an existing state (hitstop, armour,
invulnerability) is a property, not a state.

| Mechanic | Behaviour | Reasoning |
|---|---|---|
| **Guard / parry** | The same input. Pressing guard opens a 5-frame parry window first, then falls through to guard | Perfect parry is a skill expression, not a separate resource. A mistimed parry costs the *reward*, not the *defence* |
| **Parry reward** | Attacker frozen 22 frames | That freeze *is* the punish window. The highest-skill defensive action needs a reward worth the risk |
| **Dodge** | 22 frames, invulnerable 1–11 | Frame 0 is vulnerable, so dodge cannot answer everything reactionlessly |
| **Armour** | Absorbs the *reaction*, not the damage | Lets a heavy attack be **committed** rather than merely slow |
| **Wake-up** | 18 frames, invulnerable 0–12 | Getting up must not be a guaranteed free punish |
| **Unblockable** | Defeats guard and parry | The answer to turtling |
| **Hitstop** | Freezes attack frame, hitboxes and movement | What gives a hit weight. An attack that advances through hitstop reads as a hit that did not land |

---

## 5.1 Air combat: a juggle is a shared fall

Air combat is a first-class system, not a flourish, and it is the part of the
move set with the most ways to be silently broken. The rule that makes it work
is one sentence: **attacker and victim descend at the same rate.**

A launched victim floats — `HitReaction.float_frames` frames at
`float_gravity_scale`, refreshed by each hit of the juggle and bounded by the
graph's `max_combo_length` rather than by gravity. The attacker gets the same
reduced rate through `MotionProfile.air_attack_fall_scale` while performing an
airborne attack, so the pair holds its relative position for the length of the
string. The two numbers are deliberately equal (0.30).

Three properties are non-obvious and each was a bug first:

- **The attacker's hang applies to DESCENT ONLY.** Weaker gravity against an
  upward velocity buys *height*, not time. Scaling both directions made the
  player levitate to 3.5 m mid-string. Hang time and jump height are different
  quantities and an air attack buys exactly one of them.
- **The attacker's hang is not optional.** The four-attack aerial route is ~98
  frames of frame data before any hitstop; a 2.0 m jump is airborne for ~36.
  Without a shared descent the numbers simply do not permit an air combo.
- **A victim hit in midair stays airborne.** Reactions are authored for a
  standing target, so applying one verbatim in midair drops the victim into a
  *grounded* state — which stops the float applying and makes every
  target-state-gated route illegal mid-juggle.

**Jumping out of an attack goes through the combat component.** Jump is the one
action that moves the actor without `try_action`, because it is locomotion rather
than a routed combat action. It must still call
`CombatComponent.cancel_for_jump`, or the body leaves the ground while the attack
keeps executing — and since every aerial route is authored from *no* predecessor,
a stale ground attack leaves no edge to take and the whole air game becomes
unreachable with no error. Combo survival is left to `_finish_attack`: cancelling
a connected attack keeps the combo, cancelling a whiff drops it, so a jump is not
a way to launder a missed launcher.

**Launch height is bounded by the player's jump**, not chosen for spectacle. A
launcher is an invitation to follow, so the victim's apex sits just under the
player's own (about 2.1 m against 2.1 m) and the player hangs slightly above,
striking downward. The horizontal component is near zero: pushing the target away
costs the attacker the reach the launcher just earned.

### What counts as "the target" for routing

`ComboContext.target_state` describes the opponent about to be hit. It is **not**
the lock-on target. Lock-on is a camera and steering affordance set by an explicit
press; an opponent's state is a fact about the world. Tying them together made
every `require_target_state` route dead unless the player had found the lock-on
key, and made one button produce different moves depending on a camera toggle.
The context falls back to the nearest actor within
`Actor.COMBAT_AWARENESS_RANGE`; lock-on still wins when engaged, so deliberately
fighting one opponent in a crowd does not route off whoever happens to be
nearest. `Actor._local_direction` keeps using the lock-on target and only that,
because "forward means toward the enemy" genuinely *is* steering.

## 6. Soul integration `[PLANNED M3]`

Souls extend combat through **declared hooks only** — they never special-case
anything inside `combat/`:

- Contribute edges via `ComboGraph.included_graphs`
- Contribute attacks via `AttackLibrary.included_libraries`
- Gate routes on `require_soul`, `require_manifestation`, `require_passive_state`,
  `min_resonance`

`require_passive_state` is the mechanism behind the project's central Soul rule.
**FURY IGNITION does not raise a damage number** — it sets a passive state that
makes a set of gated edges legal, so the same button takes a different route.
That is what "the Soul changes how you fight" means mechanically, and there is a
unit test asserting exactly it, because it is the design rule most likely to be
quietly violated later.

---

## 7. Debug tooling

Built during M1, not deferred. Combat cannot be tuned without it, and treating
it as a luxury is how projects end up tuning combat by feel and shipping combat
that feels arbitrary.

| Key | Tool |
|---|---|
| `F1` | Overlay: state, frame data, cancel windows, combo, available routes |
| `F2` | Hitbox / hurtbox visualisation |
| `F3` | Frame step |
| `F4` | Pause |
| `F5` | Slow motion |
| `F6` | Reset arena |

The overlay draws a **frame-data timeline** — startup, active and cancel windows
as a bar with a playhead. Reading a bar is far faster than reading three numbers
when the thing being judged is whether a window feels right.

The hitbox visualiser is not optional: hitboxes have **no node in the scene
tree** (they are authored shapes queried during the tick), so Godot's built-in
collision view cannot show them.

**The Combat Lab** (`scenes/lab/`) is an isolated arena with dummies, distance
rings every 2 m, and instant reset. It exists *before* any real level, because
tuning combat inside a real environment is slow and confounded — terrain, props
and lighting all change how a hit feels, so a change cannot be attributed.

---

## 8. Current move set

16 attacks, 26 routes. `godot --headless --path . -s tools/bootstrap_player_moveset.gd`
prints the full frame-data table and route graph.

| Attack | s/a/r | Role |
|---|---|---|
| `jab_1` | 4/2/8 | Fastest option. Contests neutral |
| `jab_2` | 5/2/10 | String filler |
| `straight` | 7/3/15 | String ender. Cancels **only on hit** |
| `low_kick` | 6/3/12 | Low. Spacing tool |
| `roundhouse` | 9/3/19 | Big reward, full punish on whiff |
| `uppercut` | 12/4/22 | **Launcher.** 1 armour — committed, not merely slow |
| `axe_kick` | 14/3/24 | Overhead, knockdown. Answer to a crouching turtle |
| `spin_kick` | 10/4/18 | Spins without reorienting — opens back-hit routes |
| `lunge_punch` | 10/3/18 | Forward+K. Authored 9.5 m/s lunge |
| `sweep` | 11/3/22 | Back+J. Low knockdown. A read, not a poke |
| `air_punch` / `air_kick` | 5/3/12, 7/3/14 | Aerial string |
| `dive_kick` | 8/6/20 | Air-to-ground finisher. Requires a LAUNCHED target |
| `dash_punch` / `dash_kick` | 6/3/16, 8/3/20 | Dash cancels |
| `counter_palm` | 5/3/16 | Only from guard. Invulnerable startup, crumples |

### Verifying a link

The relationship that decides whether a combo is real:

```
frame advantage = victim hitstun − attacker's remaining frames at contact
```

Positive means the follow-up is **guaranteed**. Worked example — `jab_1` into
`jab_2`: `jab_1` is 4/2/8 and connects on frame 4; its cancel window opens on
frame 6, so the player cancels 2 frames after contact with 14 − 2 = 12 frames of
hitstun left; `jab_2` has 5 startup, so it connects 5 frames later. 12 > 5 →
guaranteed.

Frame data alone is not sufficient, though — **spacing must also work**. The
integration suite caught a case where the arithmetic was correct and the string
still could not connect, because pushback moved the target past the reach of its
own follow-up.

---

## 9. Testing

| Suite | Command | Covers |
|---|---|---|
| Unit | `tools/test.sh` | Buffer windows, graph resolution, state transitions, cancel gating, frame data |
| Integration | `godot --headless --path . res://tests/integration/CombatPipeline.tscn` | The real scenes, real physics queries, real damage |

Both run in `tools/check.sh`.

The integration suite exists because **a green unit suite structurally cannot
see whether the parts are wired together.** On its first run it failed all five
cases with 102 unit tests passing, and caught three real bugs: an inverted
forward axis, wrongly scoped hit deduplication, and buffered input being
discarded on failure. None were visible to the unit tests.

Two cases guard the architecture itself rather than a feature: combat producing
identical results at 30 and 240 fps, and identical inputs producing identical
outcomes.

---

## 10. Not yet built

| Item | Milestone |
|---|---|
| Kick animations (9 of 16 attacks play a placeholder sword swing) | M1 remainder — blocked on a licensed source containing kicks |
| Crouch state, crouching guard, true overhead/low mixups | M2 |
| Enemy AI (goal-driven archetypes) | M2 |
| Soul techniques, resonance, Manifestation | M3 |
| Weapons and auxiliary tools | M9 |
| Magic | M9 |

**Animation is wired, but nine of the sixteen attacks play a placeholder clip.**
The free tier of the licensed animation library contains no kicks at all, so
every kick currently plays a sword swing: it reads as *something* happening
rather than as a frozen pose, and it is honest about being wrong. This is the
largest outstanding readability problem in the move set — a correct kick is
mechanically indistinguishable from an incorrect one to the systems, and entirely
distinguishable to the player. See `docs/ASSET_LICENSES.md`.

Mechanics are deliberately proven before art is committed, so that art does not
get made for mechanics that then change. That ordering is holding, but it has a
cost worth naming: with the wrong clip playing, a working route is
indistinguishable from a broken one by eye, and a genuinely working three-hit
kick string was reported as missing entirely.
