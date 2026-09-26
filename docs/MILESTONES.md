# VOWED — Milestone Plan

**Owner:** Ashwin
**Last updated:** 2026-09-27

This is the production roadmap. It is a *logical sequence*, not a promise that
every milestone completes before any supporting subsystem may exist.

Every milestone obeys the same contract:

```
BUILD → PLAYABLE STATE → AUDIT → FIX → DOCUMENT → NEXT MILESTONE
```

**Exit criteria are binding.** A milestone is not complete because the code was
written; it is complete when its exit criteria are demonstrably met and its
audit is recorded in `docs/AUDITS.md`.

---

## Status board

| # | Milestone | Status | Audit |
|---|---|---|---|
| **M0** | Architecture, repository, technology audit | ✅ **Complete** | `docs/INITIAL_AUDIT.md` |
| **M1** | Movement, input, combat foundation | 🔨 **In progress** | — |
| M2 | Enemy combat and AI | ⬜ Not started | — |
| M3 | Infiroar Soul | ⬜ Not started | — |
| M4 | First complete explorable region | ⬜ Not started | — |
| M5 | First dungeon + boss | ⬜ Not started | — |
| M6 | First cinematic / story arc | ⬜ Not started | — |
| M7 | Open-world architecture | ⬜ Not started | — |
| M8 | 12-race system | ⬜ Not started | — |
| M9 | Soul framework expansion | ⬜ Not started | — |
| M10 | Regional / city expansion | ⬜ Not started | — |
| M11 | Prime Beast architecture | ⬜ Not started | — |
| M12 | Full narrative + cinematic production | ⬜ Not started | — |
| M13 | World / content completion | ⬜ Not started | — |
| M14 | Gameplay balancing | ⬜ Not started | — |
| M15 | Performance + optimisation | ⬜ Not started | — |
| M16 | Full QA | ⬜ Not started | — |
| M17 | Release candidate | ⬜ Not started | — |

---

## The thesis gate (M1 → M3)

M1, M2 and M3 together answer one question:

> **Is the core of this game good?**
> Movement + mechanical Taijutsu + an intelligent enemy + the Infiroar Soul
> + Resonance + Manifestation.

**M4 is hard-gated behind M3.** If a skilled player does not enjoy fighting one
intelligent enemy with one Soul, no quantity of world content rescues the game —
it only multiplies the problem across twelve regions. Conversely, if that core
loop is excellent, every subsequent milestone is *content applied to a proven
system*, which is a tractable problem.

This is the most important structural decision in the plan and the one most
likely to be tempting to violate.

---

## M0 — Architecture, repository, technology audit ✅

**Complete 2026-09-27.** See `docs/INITIAL_AUDIT.md` and `docs/TECH_STACK.md`.

Delivered: environment audit, 10-item risk register with owners, engine/language/
renderer lock, the two irreversible combat decisions (fixed 60 Hz tick;
explicit shape queries), repository architecture with the `src/` ⟂ `data/`
rule, git initialised with a working remote.

---

## M1 — Movement, input, combat foundation 🔨

The most important milestone in the project. Combat is the highest-priority
system in production, and its architecture — not its tuning — decides whether it
can ever feel good.

### Scope

**Foundation**
- `project.godot` configured: Forward+, Jolt, 60 Hz physics tick, input map,
  collision layers per `docs/TECH_STACK.md` §5.3.
- Core autoload singletons: event bus, combat clock, debug service, perf monitor.
- The canonical skeleton definition, so all future animation retargets to one rig.

**Input**
- Raw device input → intent translation, keyboard **and** gamepad in parallel.
- **Input buffer**: ring buffer with per-action timestamps, ~6-frame queue
  window for natural follow-ups, separate tighter leniency for cancels.
- Rebindable actions from day one (feeds Settings and Accessibility later).

**Movement**
- Custom `CharacterBody3D` motion model: explicit acceleration, friction,
  turn rate, air control, dash with recovery, landing behaviour.
- Combat and exploration movement share one foundation with different tuning
  profiles — not two separate controllers.

**Combat core**
- `CombatClock`: fixed 60 Hz logical tick. Animation slaved via `seek()`.
- `AttackData` resource schema: startup / active / recovery, hitbox keyframes,
  cancel windows, hit and guard reactions, motion keyframes, hitstop, launch,
  aerial behaviour, interrupt rules.
- Hit resolution pass: explicit ordered shape queries, deterministic trade rules.
- Hitstop, hit reactions, stagger, launch, knockdown, wake-up.
- **Combo graph**: data-driven directed graph. Node = attack, edge = (input
  condition, situational condition, cancel window). This is the structure that
  makes 100+ authored routes tractable.
- Defence: guard, perfect parry, dodge, directional evasion, counter windows,
  stagger resistance.
- Air combat: launchers, aerial attacks and chains, aerial movement, air-to-
  ground finishers, ground-to-air routes.

**Debug tooling — built in M1, not later**
- Hitbox / hurtbox visualisation.
- Live frame-data readout: current frame, state, active windows.
- Input buffer and cancel-window visualiser.
- **Frame-step and slow-motion.**
- Performance HUD against the `docs/TECH_STACK.md` §4 budgets.

**The Combat Lab** (`scenes/lab/`)
An isolated arena with a training dummy, frame-data overlay and instant reset.
Combat is judged here, in isolation, before any real level exists — tuning
combat inside a real environment is slow and confounded by level variables.

### Exit criteria

Every one of these is a demonstration, not an opinion:

1. Player moves and it *feels good* in isolation, with no combat involved.
2. Punch, kick and their ground combo routes are implemented from `data/`,
   with no attack hardcoded in `src/`.
3. Frame data is authored in resource files and visible live in the debug HUD.
4. Cancel windows work; some routes cancel and some deliberately do not.
5. Input buffer makes follow-ups reliable without making cancels sloppy.
6. Guard, perfect parry and dodge all function with readable windows.
7. A launcher opens an aerial route that lands as an air-to-ground finisher.
8. Hitstop and hit reactions read clearly; hits are legible without audio.
9. Combat runs identically at 60 and 144 fps — proving the tick model works.
10. Headless tests pass for state transitions, combo resolution, input buffering.
11. Frame time within budget in the Lab.
12. **Human playtest verdict: is punching things, with no Soul and no enemy AI,
    already satisfying?** If no, M1 is not finished.

---

## M2 — Enemy combat and AI

Enemies share the player's combat philosophy: the same frame data, the same
combo graph, the same defensive options. An enemy is not a different kind of
object with a health bar — it is an actor running the same combat system.

### Scope
- `Actor` base shared by player and enemy; the player is "the actor with input".
- Enemy combat: attacks, combos, movement, guard, counters, dodges, interrupts,
  punish windows, attack variation, contextual reactions.
- AI architecture: goal/behaviour driven, authored per archetype —
  rushdown, defensive, zoner, ambusher, mobile, grappler, ranged caster,
  support, baiter, counter-puncher.
- **Difficulty changes decision quality, not stat multipliers**: reaction
  windows, attack selection, combo sophistication, spacing, punish recognition,
  resource use.
- Threat / aggro coordination so groups behave like a group.
- AI debug overlay: current goal, considered options, chosen action and why.

### Exit criteria
1. An enemy can *outplay the player mechanically* — punish a whiffed attack,
   block a predictable string, counter a repeated approach.
2. Difficulty tiers are distinguishable with **identical HP and damage**.
3. The player loses to mistakes, not to numbers.
4. Enemies use the same frame-data pipeline as the player (verified by test).
5. A 1v3 fight is readable and fair rather than chaotic.
6. **Playtest verdict: does beating this enemy feel earned?**

---

## M3 — Infiroar Soul

The first Beast Soul, and the reference implementation every later Soul is
measured against. Infiroar was a dragon that fought aggressively through
physical combat and fire; its Soul rewards Taijutsu mastery.

### Scope
- Soul framework: passive / techniques / partial resonance / Manifestation /
  true resonance, all data-driven.
- **`FURY IGNITION` passive** — after a clean three-hit melee sequence: fiery
  aura, changed melee properties, new combo branches unlocked, rising
  resonance, a more aggressive combat state that deepens with continued clean
  play. Explicitly **not** "+20% damage" — *the way the player fights changes*.
- Soul techniques usable while human, integrated into the combo graph.
- **Resonance resource**: built by skilled play (combos, perfect parries,
  perfect dodges, advanced techniques, hard enemy interactions).
- **Manifestation**: temporary full Beast state — new/stronger techniques,
  different combo trees, changed movement and defence, new animations, VFX,
  audio, camera behaviour, finishers.
- Manifestation cinematic: a signature moment — hear the Soul, see the power
  emerge, feel the transformation, music shift, environment reaction, smooth
  return to player control. Memorable without stopping the game for minutes.
- Contextual combat camera for Manifestation.

### Exit criteria
1. `FURY IGNITION` changes *how the player fights*, verifiable by pointing at
   the specific new options it grants.
2. Base combat remains genuinely fun and viable without Manifestation.
3. Manifestation feels transformative, not like a temporary buff.
4. Resonance economy makes Manifestation a *choice* with real timing tension.
5. The first Manifestation is memorable, and hands control back cleanly.
6. Two players can use Infiroar differently and both be effective.
7. **Playtest verdict: does the Beast feel earned?**

### 🚪 Thesis gate
**M4 does not begin until M1–M3 pass their audits.** This is the plan's
load-bearing constraint.

---

## M4 — First complete explorable region

One genuinely authored region. One excellent region is worth more than five
empty ones, and this region becomes the quality bar every later region is
measured against.

### Scope
Region boundary contract implemented (fixed at M1, built here). Terrain,
landmarks, readable traversal (roads, bridges, paths, cliffs, a cave). One
major settlement plus smaller settlements — no copy-paste villages. NPCs with
schedules and world-state responses. Enemy ecology that belongs to the biome.
Environmental storytelling. Region audio identity. A visual language that makes
the region *identifiable*. Exploration reward placement.

### Exit criteria
1. "I can actually go there" — a distant landmark is physically reachable.
2. No invisible walls where a physical solution was possible.
3. Exploration is rewarded without map markers doing all the work.
4. The region feels authored, not generated.
5. Frame time within budget across the whole region.
6. **Playtest verdict: is wandering here enjoyable with no quest active?**

---

## M5 — First dungeon + boss

Substantial dungeon: exploration, combat, environmental challenges, shortcuts,
secrets, lore, minibosses, a strong final encounter. Boss with a unique combat
identity, phases, readable tells, punish windows, environmental interaction,
escalation and narrative weight — never a giant health bar.

**Exit:** the boss is beatable through *understanding*, loseable through
mistakes, and memorable. The dungeon is not a corridor.

---

## M6 — First cinematic / story arc

The reusable cinematic framework (scripted camera, staging, animation playback,
dialogue, environment changes, VFX, music transitions, screen effects, gameplay
handoff) plus the dialogue framework (branching, conditional, quest/relationship/
world-state aware, localisation-ready) and the quest system. One complete
regional story arc demonstrating all of it.

**Exit:** cinematics *communicate* rather than consume time; they transition to
gameplay without loading screens; dialogue sounds like characters rather than
quest dispensers; the world visibly changes after the arc.

---

## M7 — Open-world architecture

The region streamer (Risk R4): ACTIVE / LOADED / SHALLOW / UNLOADED rings,
threaded background loads, object and NPC persistence, unloaded-region
simulation, chunked navmesh with seam linking, memory budget enforcement, save
synchronisation, world-state persistence, world map, fast travel if justified.

**Exit:** the player crosses several regions on foot with **no loading screen
and no hitch**, world state persists across unload/reload, and memory stays
inside budget. This is the milestone that proves the world is genuinely open
rather than a set of stages.

---

## M8–M17 — Expansion, completion, release

Held at summary level deliberately: their detailed scope is written when the
preceding milestones have taught us what these systems actually need. Planning
M13 in detail today would be planning fiction.

| # | Milestone | Core content |
|---|---|---|
| M8 | 12-race system | Race framework + 12 races, each with a real mechanical identity, none hard-locking a build |
| M9 | Soul framework expansion | Generalise from Infiroar; multiple Souls each encouraging a different way of fighting |
| M10 | Regional / city expansion | The remaining major civilisations, each with distinct biome, architecture, culture, palette, music, conflict, economy, dungeon, ecology, Beast connection, history |
| M11 | Prime Beast architecture | ~30 S-rank Prime Beasts as world entities affecting weather, geography, NPCs, rumours, economy; bespoke assets begin here (Risk R6 → install Blender) |
| M12 | Full narrative + cinematic production | The complete story arc through to the Relic Stone revelations |
| M13 | World / content completion | Remaining regions, dungeons, quests, characters |
| M14 | Gameplay balancing | Combat, Souls, races, difficulty, economy |
| M15 | Performance + optimisation | Profile-driven only: CPU, GPU, draw calls, memory, streaming, animation, VFX, AI, physics |
| M16 | Full QA | Full test suite, save/load matrix, accessibility, settings, platform passes, CI if warranted |
| M17 | Release candidate | The first public release *is* the finished game — no beta, no early access, no demo |

---

## Standing rules

1. **Every milestone leaves the repository runnable.**
2. **Every milestone ends with an audit** in `docs/AUDITS.md` against the fixed
   13-point checklist.
3. **No expansion over a broken foundation.** Fix the current layer first.
4. **No content hardcoded in `src/`.** Content lives in `data/`. Always.
5. **Asset licences recorded at acquisition**, never retroactively. An asset
   with no licence record is treated as absent.
6. **Unfixed audit findings are filed** in `docs/KNOWN_ISSUES.md` with an owner.
7. **Documentation describes what exists**, not what is intended. A doc that
   overstates reality is a defect.
8. **No public beta, early access, demo or MVP launch.** Internal development
   builds only until M17.
