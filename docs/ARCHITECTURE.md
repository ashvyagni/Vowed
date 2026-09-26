# VOWED — System Architecture

**Last updated:** 2026-09-27 (M0)
**Scope:** Reflects what exists plus the boundary contracts fixed at M0.
Sections describing not-yet-built systems are explicitly marked `[PLANNED]` so
this document can never be mistaken for a description of reality.

---

## 1. The governing rule

> **Code defines *how* a system behaves. Data defines *what* exists.**

`src/` holds systems. `data/` holds content. The boundary is enforced, not
aspirational:

| | `src/` | `data/` |
|---|---|---|
| Contains | Systems, rules, resolution logic | Attacks, Souls, races, enemies, combos, quests, dialogue, regions |
| Size | Small, reviewed, unit-tested | Large, authored, tool-validated |
| Scales with | Engineering time | Authoring time |
| Adding the 31st Prime Beast | No change | One new resource file |

This is the mitigation for the project's highest-severity content risk (R3 in
`docs/INITIAL_AUDIT.md`). A roster of 30 Prime Beasts, 12 races and 100+ combat
routes is only reachable if adding content is *authoring*, not *programming*.

**Any commit that hardcodes content into `src/` is a defect, even if it works.**

---

## 2. Module map

```
src/
├── core/            Foundations. Depends on nothing else in src/.
│   ├── autoload/    Singletons: event bus, combat clock, debug, perf
│   ├── util/        Pure helpers (math, curves, ring buffers)
│   └── debug/       Overlays, frame-step, visualisers
│
├── input/           Devices → buffered intent. Knows nothing about combat.
│
├── combat/          The frame-accurate combat model.
│   ├── data/        AttackData, HitboxKeyframe, CancelWindow, reactions
│   ├── resolve/     Per-frame hit resolution, trades, hitstop
│   ├── combo/       The combo graph and its traversal
│   └── states/      Combat state machine
│
├── actor/           Anything that fights or inhabits the world.
│   ├── base/        Shared Actor: body, health, stagger, combat component
│   ├── player/      Actor + input + camera ownership
│   ├── enemy/       Actor + AI driver
│   └── ai/          Goal/behaviour evaluation
│
├── soul/            Beast Soul framework: passive, techniques, resonance,
│                    manifestation. Modifies combat through defined hooks only.
├── race/            Race framework: attribute and rate modifiers, mechanics
├── world/           streaming/ region/ state/ — the open world
├── quest/  dialogue/  cinematic/  audio/  ui/  save/
```

### 2.1 Dependency direction

Dependencies point **downward only**. Upward calls are forbidden; upward
*notification* happens via signals.

```
        ui        cinematic      quest/dialogue
          \            |            /
           \           |           /
            +------ actor ------- world
                   /     \
              combat      soul / race
                   \       /
                    input |
                      \   |
                       core
```

Rules that follow from this:

- `core` depends on nothing. It is safe to use anywhere.
- `combat` does not know about `soul`, `race`, `ai` or `ui`. It exposes hooks;
  others register against them. This is what keeps combat testable in isolation.
- `soul` and `race` **modify** combat through declared extension points. They
  never reach into combat internals. A Soul that needed a special case inside
  `combat/resolve/` would be a design failure in the Soul, not a missing feature
  in combat.
- `world` owns regions and persistence. `actor` is placed *into* the world and
  does not manage streaming.
- `ui` reads state and never mutates gameplay.

### 2.2 Communication

| Direction | Mechanism | Rationale |
|---|---|---|
| System → observers | Signals / event bus | Decoupled; UI, audio and VFX can react without combat knowing they exist |
| Caller → system | Direct typed method call | Explicit, debuggable, statically checked |
| Cross-cutting notifications | `GameEvents` autoload | One place to find "what happened", and one place to hook debug logging |

The event bus is deliberately **not** a general-purpose message queue.
Commands are direct calls; only *notifications* are broadcast. A codebase where
everything talks through a bus is untraceable — the stack trace stops being the
answer to "how did we get here".

---

## 3. The combat foundation `[M1 — in progress]`

Two decisions here are locked and effectively irreversible
(`docs/TECH_STACK.md` §5). They are the reason combat can feel mechanical.

### 3.1 The tick is authoritative; animation follows

```
_physics_process(delta)                     60 Hz fixed
        │
        ▼
  CombatClock.tick()                        frame += 1
        │
        ├─► consume input buffer            intent for THIS frame
        ├─► advance combat state            startup / active / recovery
        ├─► resolve hitboxes                explicit ordered shape queries
        ├─► apply hitstop, reactions
        └─► AnimationPlayer.seek(frame/60)  animation is the SLAVE
```

Animation never drives combat state. The frame counter is truth.

Consequences, all of them the point rather than side effects:

- **Frame-rate independence.** "Active on frame 7" means frame 7 at 60 fps and
  at 144 fps.
- **Testability.** Combat becomes a pure function of (state, input, frame), so
  combo resolution and cancel windows are unit-testable headlessly with no
  renderer at all.
- **Debuggability.** Frame-stepping is possible, so frame data can be *read*.
  Without it, combat tuning degenerates into superstition.
- **Authoring in real units.** Design reasons in frames, which is how frame data
  is expressed and compared across the genre.

### 3.2 Hit resolution is an explicit ordered pass

`PhysicsDirectSpaceState3D.intersect_shape()` is called deliberately during the
combat tick against the hurtbox layer.

`Area3D.body_entered` is rejected: signal ordering is not controllable, it fires
on the physics step rather than the combat frame, and it makes trade/priority
rules — who wins when two attacks connect on the same frame — effectively
impossible. An ordered pass makes hit resolution deterministic and inspectable.

### 3.3 Frame data as authored resources `[PLANNED M1]`

`AttackData` (a `Resource`) carries startup / active / recovery, hitbox
keyframes, cancel windows, hit and guard reactions, motion keyframes, hitstop,
launch and aerial behaviour, and interrupt rules.

Because it is a `Resource`, it is editor-authorable, serialisable and
diffable — and validatable by a `tools/` script that can assert every attack in
the game is well-formed without launching it.

### 3.4 The combo graph `[PLANNED M1]`

Routes are a **directed graph authored as data**, not `if` chains:

- **Node** = an attack.
- **Edge** = (input condition, situational condition, cancel window).

100+ authored routes then means 100+ authored *edges*, which is tractable.
Expressing the same thing as branching code would not be.

Situational conditions are what make routes meaningful rather than arbitrary:
grounded/airborne, target state (hit / blocked / countered / launched),
Soul state, resonance level, facing, spacing.

---

## 4. Actors `[PLANNED M2]`

One `Actor` base for player and enemy. The player is *the actor whose intent
comes from input*; an enemy is *the actor whose intent comes from AI*. Both run
the identical combat model.

This is a design requirement, not an optimisation: enemies must share the
player's combat philosophy — frame data, cancel windows, defensive options — or
they cannot out-play the player mechanically, and combat becomes solitaire.

---

## 5. Soul framework `[PLANNED M3]`

Souls modify combat through **declared hooks only**:

| Hook | Effect |
|---|---|
| Passive state | Alters melee properties and unlocks combo edges |
| Combo edges | Adds Soul-gated routes to the graph |
| Techniques | New attacks, authored as ordinary `AttackData` |
| Resonance | A resource fed by skilled play |
| Manifestation | A state swap: different animation set, combo subgraph, movement and defence profile |

The rule that keeps Souls interesting: **a Soul changes behaviour, never a
damage multiplier.** `+25% attack` is a failed Soul design. "After three clean
melee hits, close-range attack behaviour changes and new branches open" is a
Soul.

---

## 6. World `[PLANNED M7; contract fixed M1]`

Region rings: `ACTIVE` (simulated) → `LOADED` (present, reduced simulation) →
`SHALLOW` (state only, no scene) → `UNLOADED`.

The **region boundary contract** — what a region owns and how it serialises — is
fixed at M1 even though the streamer is built at M7, specifically so that no
scene authored between M1 and M6 has to be retrofitted.

`SHALLOW` is the load-bearing state: it is how world changes stay permanent
without staying resident, which is what lets an 8 GB machine hold a persistent
open world.

---

## 7. Persistence `[PLANNED, contract fixed M0]`

Every persistable system implements:

```gdscript
func save_state() -> Dictionary
func load_state(state: Dictionary) -> void
```

Aggregated into **versioned JSON** with a migration chain. Writes are atomic
(temp file → flush → rename), so an interrupted save cannot corrupt the previous
one.

Saves deliberately do **not** use `ResourceSaver`: that format couples the save
file to class layout, so refactoring a script would invalidate existing saves.
`.tres` remains correct for authored content in `data/`, where coupling to class
layout is desirable. Content is versioned by git; saves are versioned by the
player's playthrough.

---

## 8. Debug infrastructure `[PLANNED M1]`

Built during M1, not deferred, because combat cannot be tuned without it:
hitbox/hurtbox visualisation, live frame-data readout, input-buffer and
cancel-window visualisers, frame-step and slow-motion, AI decision overlay,
performance HUD against the budgets in `docs/TECH_STACK.md` §4.

Treating these as a luxury is how projects end up tuning combat by feel and
shipping combat that feels arbitrary.

---

## 9. Architectural rules

1. **Dependencies point downward.** Signals go up; calls go down.
2. **No content in `src/`.**
3. **Static types everywhere.** Untyped declarations are defects.
4. **`StringName` for runtime identity comparisons**, never bare `String`.
5. **Combat knows nothing of Souls, races, AI or UI.** It exposes hooks.
6. **One canonical skeleton.** All animation retargets to it, so the project
   reads as one game rather than as assembled asset packs.
7. **Systems are testable headlessly** or they are wrongly coupled to rendering.
8. **Every persistable system implements the save contract** from the moment it
   holds state — never retrofitted, because retrofitting persistence is how
   world state quietly becomes non-persistent.
