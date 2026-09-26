# VOWED — Technology Stack

**Status:** LOCKED as of 2026-09-27 (Milestone 0)
**Change policy:** see Section 12. Engine changes after M4 require a documented
design flaw, not a preference.

---

## 1. The locked stack at a glance

| Layer | Decision | Locked |
|---|---|---|
| Engine | **Godot 4.x** (stable channel) | ✅ Hard lock |
| Language | **GDScript**, single-language | ✅ Hard lock |
| Performance escape hatch | **GDExtension (C++)**, per-subsystem, profiler-triggered only | ✅ Policy locked |
| Renderer | **Forward+** | ✅ Hard lock |
| Physics | **Godot Jolt** (built-in 3D physics, Jolt backend) | ✅ Hard lock |
| Combat timing | **Fixed 60 Hz logical tick**, animation slaved to frame counter | ✅ Hard lock — see §5 |
| Hit detection | **Explicit per-frame shape queries**, not `Area3D` signals | ✅ Hard lock — see §5 |
| Animation | `AnimationTree` state machines + authored root motion | ✅ Locked |
| Navigation | Per-region chunked `NavigationRegion3D`, offline baked | ✅ Locked |
| Serialisation | Custom versioned dictionary → JSON (not `ResourceSaver` for saves) | ✅ Locked — see §8 |
| Content format | Godot `Resource` (`.tres`) authored in-editor | ✅ Hard lock |
| World streaming | Custom region streamer over `ResourceLoader` threaded loads | ✅ Locked |
| Dialogue | Custom data-driven graph, key-addressed for localisation | ✅ Locked |
| Cinematics | Real-time in-engine, `AnimationPlayer`-driven sequencer | ✅ Locked |
| Audio | Godot buses + custom adaptive music layer controller | ✅ Locked |
| Tests | **In-house headless harness** (`tests/framework/`) | ✅ Locked — see §10 |
| Tooling | Python 3.14 for pipeline scripts, GDScript for in-editor tools | ✅ Locked |
| VCS | Git + GitHub (`ashvyagni/Vowed`), SSH | ✅ Locked |
| Primary dev target | macOS arm64 (Apple Silicon) | ✅ |
| Ship targets | Windows x64, macOS universal, Linux x64 | ✅ Planned |

---

## 2. Engine — Godot 4.x

Full comparative reasoning is in `docs/INITIAL_AUDIT.md` §4.1. Condensed:

**Selected because** iteration speed on combat tuning is the highest-leverage
property for this specific project, and `Resource` is exactly the primitive
needed to make 12 races / 30 Beasts / 100+ combat routes *authorable content*
instead of *engineering work*.

**Rejected:** Unreal 5 (fidelity features unused by a stylised target; heavy on
an 8 GB machine; slower combat iteration), Unity 6 (licensing-history risk for a
commercial release; render-pipeline fragmentation with no payoff here), custom
engine (converts a game project into an engine project).

### 2.1 Version policy

- Track the **stable** channel. Never `dev`/`beta` for the production branch.
- Patch upgrades (4.x.y → 4.x.z): allowed any time, verified by the test suite.
- Minor upgrades (4.x → 4.y): only **between** milestones, never mid-milestone,
  and always in a dedicated commit that touches nothing else — so a regression
  is trivially bisectable.
- The exact version in use is recorded in `project.godot`
  (`config/features`) and is the single source of truth.

---

## 3. Language — GDScript only

**C# is explicitly rejected**, not merely unselected. Reasons in
`docs/INITIAL_AUDIT.md` §4.2. Summary: a second toolchain and a marshalling
boundary for zero existing .NET assets, added Apple-Silicon export friction,
and — decisively — where GDScript is genuinely too slow, GDExtension/C++ is the
better answer than C# anyway.

### 3.1 The GDExtension escape hatch (policy, not aspiration)

A subsystem may move to C++ **only** when all three hold:

1. A profiler capture shows it exceeding its documented frame budget.
2. The cost is algorithmic-floor, not a fixable GDScript mistake.
3. It sits behind an interface whose callers do not change.

Candidates, in expected order: enemy AI decision evaluation, region streaming
serialisation, broad-phase spatial queries at high actor counts.

**Not** a candidate: combat frame resolution. A handful of shape queries per
frame at 60 Hz is far inside GDScript's budget, and this is measured rather than
assumed.

### 3.2 GDScript conventions

- `class_name` on every type intended for use outside its own file.
- **Static typing everywhere.** Untyped variables are treated as defects: they
  forfeit both the compile-time check and the bytecode optimisation.
- `StringName` for all identifiers compared at runtime (attack ids, states,
  events). Never bare `String` for identity comparison.
- No `get_node()` by string path in gameplay code — `@export` the reference or
  use `%UniqueName`.
- Signals for outbound notification; direct calls for inbound commands. A
  system never reaches *into* another system's internals.

---

## 4. Renderer — Forward+

Forward+ is required by the visual direction (real-time shadows, volumetrics,
meaningful post-processing). Mobile cannot deliver the target; Compatibility
certainly cannot.

The cost is that Forward+ is the heavier renderer on 8 GB of *shared* memory.
That is paid for by budget enforcement, not by downgrading the renderer:

| Budget | Target | Enforced by |
|---|---|---|
| Frame time | **16.6 ms** (60 fps) minimum bar; 8.3 ms (120 fps) aspirational in combat | In-engine perf HUD from M1 |
| Draw calls | < 2000 in normal play | Perf HUD |
| Texture memory | < 1.5 GB resident | Streaming + budget monitor |
| Total process memory | < 3.5 GB | Budget monitor |

Rendering discipline: aggressive material reuse (a small, shared shader
library), texture atlasing, LODs on everything at distance, `VisibilityRange`
for HLOD swaps, occlusion culling per region.

> **Note on the stylised target:** stylisation is not only an art direction —
> it is a *performance strategy*. Readable silhouettes and flat-ish shading are
> far cheaper than photoreal materials, which is what makes an open world
> feasible on this hardware. Art direction and technical constraint agree here,
> which is why the visual target is not treated as a compromise.

---

## 5. Combat technology — the most consequential decisions

These two decisions are the reason combat will feel mechanical rather than
mushy. Both are architectural and effectively irreversible, which is why they
are locked at M0 rather than discovered at M3. Full design in `docs/COMBAT.md`.

### 5.1 Fixed 60 Hz logical tick; animation is the slave

```
_physics_process(delta)  →  CombatClock.tick()  →  frame += 1
                                                    ↓
                     resolve hitboxes, cancels, buffer, state for THIS frame
                                                    ↓
                     AnimationPlayer.seek(frame / 60.0)   ← animation follows
```

**Animation never drives combat state.** The frame counter is authoritative;
the animation is seeked to match it.

Why this matters enough to lock at M0:

- **Frame-rate independence.** Hitbox activation on frame 7 means frame 7 at
  any render rate. Animation-driven timing silently couples hitboxes to frame
  rate, and the resulting inconsistency is unfixable without this rewrite.
- **Testability.** Combat becomes a pure function of (state, input, frame).
  Combo resolution and cancel windows are unit-testable headlessly, with no
  renderer — directly serving the automated-test requirement.
- **Debuggability.** Frame-stepping is possible, so frame data can be *read*
  instead of guessed at. Without it, combat tuning is superstition.
- **Authoring in real units.** Designers reason in frames, which is how
  fighting-game frame data is expressed and compared.

### 5.2 Explicit shape queries, not `Area3D` signals

Hit detection uses `PhysicsDirectSpaceState3D.intersect_shape()` called
deliberately during the combat tick, against a dedicated hurtbox collision
layer.

`Area3D` `body_entered` is rejected because signal delivery order is not
controllable, it fires on the physics step rather than the combat frame, and it
makes clean trade/priority rules (who wins when two attacks connect on the same
frame) effectively impossible. Explicit queries make hit resolution an ordered,
deterministic, inspectable pass.

### 5.3 Collision layer allocation

Fixed now to avoid the classic late-project layer collision:

| Bit | Layer | Purpose |
|---|---|---|
| 1 | `world_static` | Terrain, architecture, static collision |
| 2 | `world_dynamic` | Movable props, destructibles |
| 3 | `player_body` | Player character body |
| 4 | `enemy_body` | Enemy character bodies |
| 5 | `player_hurtbox` | Player's receivable volume |
| 6 | `enemy_hurtbox` | Enemy receivable volumes |
| 7 | `hitbox` | Active attack volumes (query source, not a collider) |
| 8 | `projectile` | Projectiles and thrown tools |
| 9 | `interaction` | Interactables, triggers, pickups |
| 10 | `camera_collide` | Camera-only collision proxies |
| 11 | `nav_obstacle` | Dynamic navigation obstacles |
| 12 | `water` | Water volumes |
| 13–20 | reserved | Region/streaming/cinematic use, allocated on demand |

---

## 6. Physics — Godot Jolt

Jolt is the 3D backend. Chosen for stability and character-controller quality
over the legacy `GodotPhysics3D`, which has a longer history of
character-controller edge cases — precisely the area a precision action game
cannot afford to be flaky in.

Movement uses `CharacterBody3D` with a **fully custom motion model** (explicit
acceleration, friction, air control, dash and recovery curves), not
`move_and_slide` defaults. Physics provides collision resolution; it does not
decide how the character feels.

Combat hits do **not** go through the physics solver — see §5.2.

---

## 7. Animation — `AnimationTree` + authored root motion

- `AnimationNodeStateMachine` per actor, driven by the combat/locomotion state
  machine rather than by animation events.
- **Root motion is authored data, not animation-extracted**, for attacks: an
  attack's displacement is a `MotionKeyframe` array in its frame data. This
  keeps movement deterministic and tunable without re-exporting animation, and
  it makes attack spacing a *design* value.
- Locomotion blending uses `AnimationNodeBlendSpace2D` on velocity.
- **Retargeting matters:** external assets arrive on varied skeletons. A single
  canonical skeleton is defined at M1 and everything is retargeted to it. This
  is what prevents the project from looking like glued-together asset packs.

---

## 8. Serialisation and saves

**Saves do not use `ResourceSaver`/`.tres`.** That format is convenient but
couples the save file to class layout, so refactoring a script can invalidate
existing saves — unacceptable for a long game.

Instead:

- Each persistable system implements `save_state() -> Dictionary` and
  `load_state(d: Dictionary)`.
- The aggregate is written as **versioned JSON** with an explicit
  `save_version` integer and a migration chain (`v1 → v2 → …`). Old saves are
  migrated forward, never rejected.
- Writes are **atomic**: serialise to a temp file, `flush`, then rename over
  the target. An interrupted save can never corrupt the previous one.
- Rolling backups of the last N saves, so a bad state is recoverable.

`.tres` remains the format for *authored content* (`data/`), where coupling to
class layout is correct and desirable. The distinction is deliberate: content is
versioned by git; saves are versioned by the player's playthrough.

---

## 9. World streaming

Custom region streamer, because Godot has no world partition (Risk R4).

- The world is a grid of **regions**; each region is a scene plus a persistent
  state record.
- Loading via `ResourceLoader.load_threaded_request()` on a background thread —
  never a blocking load during play.
- Rings: `ACTIVE` (simulated) → `LOADED` (present, reduced simulation) →
  `SHALLOW` (state only, no scene) → `UNLOADED`.
- Unloaded regions keep their **state** (NPCs, quests, world changes) so the
  world persists without being resident. This is what allows world state to be
  permanent without being expensive.
- The **region boundary contract** — what a region owns and how it serialises —
  is fixed at M1 even though the streamer is built at M7, so nothing needs
  retrofitting.

---

## 10. Testing

### 10.1 In-house harness, not GUT

Tests run on a project-owned harness in `tests/framework/`:

```bash
godot --headless --path . -s tests/framework/TestRunner.gd
godot --headless --path . -s tests/framework/TestRunner.gd -- --filter=buffer
```

Exit code 0 on pass, 1 on failure, so it drops into a pre-commit hook or CI with
no wrapper.

**This reverses the M0 decision to use GUT.** The reasoning, recorded because
reversals should be arguable rather than silent:

What this project needs to test is overwhelmingly **pure logic** — frame-data
validity, combo-graph resolution, input-buffer windows, save migrations. That
needs three things: discovery, assertions, and an exit code. Roughly 250 lines,
entirely under project control.

Against that, an addon carries a dependency to version-track, a licence and
provenance record to maintain (per `ASSET_LICENSES.md` discipline), and upgrade
risk at every Godot minor release. For this test shape the dependency costs more
than it saves.

This is not a criticism of GUT, which is good at what this project does not yet
need: scene-tree integration fixtures, doubles and spies, parameterised tests.
`TestCase`'s assertion surface is deliberately kept close to GUT's so that if QA
needs those at **M16**, test bodies port largely unchanged. Revisit there.

### 10.2 Coverage

- Priority coverage: combat state transitions, combo graph resolution, input
  buffering, cancel windows, frame-data validity, Soul resonance
  accounting, save round-trip and migration, quest/world-state persistence,
  dialogue conditions.
- Plus **content validators** in `tools/`: scripts that walk `data/` and assert
  every resource is well-formed (no attack with negative startup, no combo edge
  pointing at a missing attack). Content bugs get caught without launching the
  game.
- Automated tests cannot judge whether combat is *fun*. Human playtests remain
  mandatory at every milestone audit and are recorded in `docs/AUDITS.md`.

---

## 11. Build and export

| Target | Priority | Notes |
|---|---|---|
| macOS arm64 | Primary dev | Development platform |
| Windows x64 | Primary ship | Largest audience |
| macOS universal | Ship | |
| Linux x64 | Ship | Low marginal cost from Godot |
| Console | Out of scope | Would require a porting partner; revisited post-release |

Input targets keyboard+mouse **and** gamepad from M1. The directive's default
binding (J/K/Space/Shift/Q/E/R) is the keyboard mapping; a gamepad map is
maintained in parallel from the start because retrofitting a second input device
onto a combat system is expensive.

---

## 12. Change policy

| Layer | Reversibility | Rule |
|---|---|---|
| Engine | Catastrophic after M4 | Requires a documented, demonstrated design flaw. Never a preference. |
| Language | Very expensive | Same bar as engine. |
| Renderer | Moderate | Changeable at a milestone boundary with a perf justification. |
| Combat tick model (§5.1) | Catastrophic at any time | Effectively permanent. Everything in combat assumes it. |
| Hit detection (§5.2) | Expensive | Changeable only with a full combat re-audit. |
| Save format (§8) | Cheap by design | Migration chain exists precisely so this can evolve. |
| Content schemas | Cheap by design | `data/` + validators exist precisely so this can evolve. |

The stack is split this way on purpose: the decisions that are expensive to
reverse are made once, at M0, with reasoning recorded. The decisions that will
certainly need to change are given migration paths up front, so changing them
later is routine rather than a crisis.
