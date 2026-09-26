# VOWED — Initial Repository & Environment Audit

**Audit date:** 2026-09-27
**Auditor:** Project technical direction
**Milestone:** M0 — Architecture, repository and technology audit
**Status:** Complete. Production may begin on M1.

---

## 1. Executive summary

The repository was **empty**. There is no legacy code, no legacy scenes, and
therefore **no technical debt to inherit and no prior mistakes to preserve**.
This is the single most favourable starting condition available: every
architectural decision below is a greenfield decision, made once, deliberately.

Two findings materially shape the architecture and are treated as hard
constraints rather than notes:

1. **The development machine has 8 GB of unified memory** (Apple M3). On Apple
   Silicon, CPU and GPU share that pool. A genuinely open world therefore
   cannot be built on "load the world and see how it goes" — streaming is
   load-bearing from the first region, not a later optimisation pass.
2. **No engine was installed.** The stack is unconstrained by prior
   installation, so the choice was made on merit (Section 4) rather than
   inherited.

The verdict on preserving the existing project is trivial: **there is nothing
to preserve.** Full greenfield.

---

## 2. Environment inventory

| Item | Finding |
|---|---|
| Working directory | `~/Documents/Sidequests/Full Crazy Projects/Vowed` |
| Directory contents at audit start | Empty (0 files) |
| Version control at audit start | Not a git repository |
| Remote | `github.com/ashvyagni/Vowed` — exists, **zero refs (empty)** |
| Host OS | macOS 26.3.1 (build 25D2128) |
| CPU | Apple M3 |
| Unified memory | **8 GB (CPU + GPU shared)** |
| Free disk | 177 GB available of 460 GB |
| Git | 2.50.1 (Apple Git-155) |
| Homebrew | 6.0.21 (`/opt/homebrew`) |
| Python | 3.14.6 |
| Node | 26.3.1 |
| Godot | **Not installed** → installed during this audit |
| Unity / Unreal | Not installed |
| Blender | **Not installed** — required later for bespoke assets (see Risk R6) |
| .NET SDK | Not installed (not required; see Section 4.2) |
| `gh` CLI | Not installed (not required; SSH push is sufficient) |
| Git identity | `ashvyagni <ahemashwin@gmail.com>` — matches remote owner ✅ |
| SSH key | `~/.ssh/id_ed25519_github` present, correct `~/.ssh/config` entry, **not yet registered on the GitHub account** |

### 2.1 Notable absence: no engine, no legacy

Because the repository was empty, the usual M0 question ("is the existing
foundation worth keeping?") does not apply. The more useful question — *what
foundation should exist?* — is answered in Sections 4 and 5.

---

## 3. Technical risk register

Risks are ordered by expected damage, not by likelihood. Each has a named
mitigation that is either already in place or scheduled to a specific
milestone. A risk without a mitigation owner is not a managed risk.

| ID | Risk | Severity | Mitigation | Owed by |
|---|---|---|---|---|
| **R1** | **8 GB unified memory.** A large open world plus the editor plus a running game will exhaust the shared pool. Symptoms would appear late (in M7) and be expensive to fix. | **Critical** | Streaming-first world architecture. A published memory budget enforced by an in-engine monitor from the moment the first region exists. Region payloads capped. No "load everything" path is ever written, not even as a stopgap. | M1 (monitor), M7 (streaming) |
| **R2** | **Combat feel is decided by architecture, not by tuning.** If animation drives combat timing, hitboxes become frame-rate dependent and timing becomes unfixably mushy. This is the most common fatal mistake in action games and cannot be patched later. | **Critical** | Fixed 60 Hz logical combat tick; animation is *driven by* the frame counter, never the reverse. Explicit per-frame shape queries instead of physics callback signals. See `docs/COMBAT.md`. | M1 |
| **R3** | **Content volume vs. solo authoring.** 12 regions, 30 Prime Beasts, 12 races, 100+ combat routes. Hand-coding any of these categories makes the target unreachable arithmetically. | **High** | Everything in those categories is **data, not code**: authored as Godot `Resource` files consumed by one generic system each. Adding the 31st Beast must never mean writing a script. Enforced by the `src/` ⟂ `data/` split. | M1 onward, permanently |
| **R4** | **Godot has no built-in world partition / streaming.** Unlike UE5, this must be authored. Building it late means retrofitting every scene. | **High** | Region streaming is designed in M0 and built in M7, but the *region boundary contract* (what a region owns, how it saves) is fixed in M1 so nothing has to be retrofitted. | M1 (contract), M7 (impl) |
| **R5** | **Navigation on a large world.** A single monolithic navmesh will not bake or fit in memory. | **Medium** | Per-region chunked navmeshes, baked offline via a tool script, linked at region seams. Never a global bake. | M7 |
| **R6** | **No DCC tool installed (Blender).** Bespoke Prime Beast assets eventually need one. | **Medium** | Not blocking: M1–M6 run entirely on open-licence external assets and graybox geometry. Blender is installed when the first bespoke asset is scheduled. Deliberately deferred to avoid unused tooling. | M11 |
| **R7** | **Asset licence drift.** Assets accumulated casually become unshippable, and the problem is discovered at release. | **Medium** | `docs/ASSET_LICENSES.md` + `assets/licenses/assets.json` are populated *at acquisition time*, never retroactively. An asset with no licence record is treated as absent. | Permanent |
| **R8** | **Scope-driven paralysis.** A world this size invites building breadth before the core thesis is proven. | **Medium** | Milestone gating: no second Soul until Infiroar is mechanically excellent; no second region until the first is genuinely authored. Enforced by milestone audits. | Permanent |
| **R9** | **GitHub push credentials.** The SSH key is not yet registered, so the remote cannot receive commits. | **Low** | Commits are authored locally with correct identity regardless; history is preserved and pushes once the key is added. Zero work is blocked. | Immediate |
| **R10** | **Single-machine, single-copy project.** No off-machine backup until pushes work. | **Low** | Resolved by R9. Until then, local commits are frequent so nothing exists only in the working tree. | Immediate |

### 3.1 Risks explicitly *not* mitigated (accepted)

- **No CI runners configured.** For a solo project with a headless-testable
  engine, local `--headless` test runs are sufficient. CI is revisited at M16
  (Full QA), not before. Setting it up now would be unused ceremony.
- **No localisation pipeline yet.** Dialogue is authored data-driven and
  key-addressed from M6 onward, which is the only decision that would be
  expensive to reverse. Actual translation is a post-content concern.

---

## 4. Architecture recommendation

### 4.1 Engine: Godot 4.x

Selected. The reasoning, including the honest weaknesses:

**Why it fits this project**

- **Iteration speed.** For a solo developer, the compile-free GDScript loop is
  the single largest multiplier on combat tuning, and combat tuning is where
  this project lives or dies. Godot's sub-second reload beats a C++ or C#
  rebuild cycle by an order of magnitude on the exact loop that matters most.
- **`Resource` is a first-class, editor-authorable, serialisable data type.**
  This is not a minor convenience — it is precisely the primitive that makes
  the data-driven mitigation for R3 practical. Attacks, Souls, races, combo
  edges and regions all become `.tres` files with editor UI for free.
- **Scene composition and `AnimationTree`** map cleanly onto actor
  construction and animation state machines.
- **Deterministic fixed tick** (`_physics_process`) is available and reliable,
  which R2's mitigation depends on.
- **Headless mode** makes combat-state and combo-resolution tests runnable in
  CI without a display — directly serving the automated-test requirement.
- **No royalties, no seat cost, full engine source** if a hot path ever needs
  patching.

**Honest weaknesses, and the plan for each**

| Weakness | Consequence | Plan |
|---|---|---|
| No built-in world partition | Streaming must be written | Accepted; R4. Godot's streaming needs are modest because the visual target is stylised, not photoreal. |
| Navmesh baking is not chunk-aware by default | Manual chunking | Accepted; R5. Tool script does the bake. |
| GDScript is slower than C++ per-op | Matters only in hot loops | Combat frame resolution is cheap (tens of shape queries/frame). The genuine hot paths are AI and streaming; both are budgeted and both have a **GDExtension (C++) escape hatch** if profiling demands it. Profiling decides — not assumption. |
| Smaller 3D ecosystem than Unity/Unreal | Fewer off-the-shelf solutions | Largely irrelevant: the systems this project needs (a specific combat model, a specific Soul model) would be custom in any engine. |

**Why not the alternatives**

- **Unreal 5** — Nanite/Lumen and World Partition are genuinely superior for
  large worlds, but the target is *stylised*, so the headline features are
  mostly unused. Against that: a heavyweight editor and shader-compile cycle on
  an **8 GB** machine (R1) is a poor match, C++/Blueprint iteration is slower
  for combat tuning, and the engine's strengths are aimed at a fidelity target
  this game is not chasing.
- **Unity 6** — Credible, and its animation tooling is strong. Rejected on
  two grounds: the runtime-fee/licensing history is an unnecessary structural
  risk for a project intended for commercial release, and the render-pipeline
  fragmentation adds a decision surface with no payoff here.
- **Custom engine** — Categorically wrong. It converts a game project into an
  engine project.

### 4.2 Language: GDScript, single-language

GDScript only. **C# is explicitly rejected**, not merely unselected:

- Mixing two languages in one codebase adds a marshalling boundary and a
  second toolchain for no gain in a project with no existing .NET assets.
- The C# export path on Apple Silicon adds real friction for zero benefit
  here.
- The performance argument for C# is weaker than it appears: where GDScript is
  genuinely too slow, the correct answer is GDExtension/C++ for that specific
  system, which is faster than C# anyway.

**Escape hatch, stated now so it is a decision and not a scramble later:** if
profiling (M15, or earlier if a milestone audit flags it) shows AI or streaming
exceeding budget, that subsystem — and only that subsystem — moves to
GDExtension behind its existing interface. The interfaces are designed to make
this substitution possible without touching callers.

### 4.3 Renderer: Forward+

Forward+, not Mobile, not Compatibility. The visual direction calls for strong
lighting and dramatic effects (real-time shadows, volumetrics, decent
post-processing); Mobile cannot deliver that. Forward+ on Apple Silicon is
well-supported.

The cost is that Forward+ is the heavier renderer on an 8 GB machine, which is
accepted and paid for by R1's enforced budget. Texture streaming and strict
material discipline are what make this affordable — not a lighter renderer.

### 4.4 The structural decision that matters most: `src/` ⟂ `data/`

This is the mitigation for R3, and it is worth stating as a rule rather than a
folder layout:

> **Code defines *how* a system behaves. Data defines *what* exists.
> A new Soul, Beast, race, attack, combo route, enemy, region, quest or
> dialogue tree must be addable without writing a script.**

Consequences, all deliberate:

- `src/` contains systems. It is small, reviewed, and tested.
- `data/` contains content. It is large, authored, and validated by tooling.
- Content volume therefore scales with *authoring* time, not *engineering*
  time — which is the only way the target roster is reachable solo.
- Content becomes testable: a validator can check every attack resource for
  frame-data sanity without running the game.

Any commit that hardcodes content into `src/` is a defect, regardless of
whether it works.

---

## 5. Repository structure (established this milestone)

```
Vowed/
├── project.godot
├── docs/                 Living documentation (see docs/README.md)
├── addons/               Third-party editor plugins only
├── src/                  ALL code. Systems, never content.
│   ├── core/             Foundations: autoloads, utilities, debug tooling
│   ├── input/            Raw input → buffered intent
│   ├── combat/           Frame data, resolution, combo graph, states
│   ├── actor/            Shared actor base → player, enemy, AI
│   ├── soul/             Beast Soul framework
│   ├── race/             Race framework
│   ├── world/            Streaming, regions, persistent world state
│   ├── quest/ dialogue/ cinematic/ audio/ ui/ save/
├── data/                 ALL authored content as Resources. Never code.
│   ├── attacks/ combos/ souls/ races/ enemies/
│   └── dialogue/ quests/ regions/
├── scenes/
│   ├── actors/ world/ ui/
│   └── lab/              Isolated test arenas (the Combat Lab lives here)
├── assets/               External + bespoke art, audio, VFX
│   └── licenses/         assets.json — licence record per asset
├── tests/                unit/ + integration/, headless-runnable
└── tools/                Pipeline scripts (bakes, validators, importers)
```

The `scenes/lab/` directory deserves specific mention: **a dedicated combat
testing arena is built in M1, before the first real level.** Tuning combat
inside a real environment is slow and confounded by level-specific variables.
The lab exists so combat can be judged in isolation.

---

## 6. Production strategy

### 6.1 The loop

```
BUILD → PLAYABLE STATE → AUDIT → FIX → DOCUMENT → NEXT MILESTONE
```

Non-negotiable rules:

1. **Every milestone ends with the repository runnable.** A milestone that
   ends with a broken project is not finished, regardless of code written.
2. **Every milestone ends with an audit** recorded in `docs/AUDITS.md`,
   covering the fixed checklist (gameplay, combat, input, AI, animation,
   performance, architecture, content, narrative, cinematics, audio, assets,
   technical debt).
3. **No expansion over a broken foundation.** If combat is mediocre, no new
   Souls are built. If the first region is hollow, no second region is built.
4. **Audit findings are filed, not remembered.** Anything unfixed goes to
   `docs/KNOWN_ISSUES.md` with a milestone owner.

### 6.2 What is deliberately *not* being built yet

Stated explicitly so that deferral is a plan rather than an oversight:

- **Not** all 30 Prime Beasts. **One** Soul (Infiroar) proven excellent first.
- **Not** all 12 races. The race *framework* comes at M8; the roster follows.
- **Not** 12 regions. **One** genuinely authored region first.
- **Not** a public beta, early access, demo, or MVP launch — per project
  policy, the first public release is the finished game.

Deferral is not scope reduction. The final vision in the master directive is
unchanged; the *order* is chosen so each system is validated before it is
multiplied.

### 6.3 Commit discipline

Commits land on meaningful completed units of work with messages describing the
architectural or product change, not the file list. Never committed: secrets,
generated files, unlicensed assets, machine-local clutter (enforced by
`.gitignore`).

---

## 7. Major milestones

Full detail in `docs/MILESTONES.md`. Summary:

| # | Milestone | Core question it answers |
|---|---|---|
| 0 | Architecture + repo + tech audit | *Can we build safely?* ← **this document** |
| 1 | Movement, input, combat foundation | *Is fighting, by itself, fun?* |
| 2 | Enemy combat and AI | *Is there a worthy opponent?* |
| 3 | Infiroar Soul | *Does the Soul change how you fight?* |
| 4 | First complete explorable region | *Does the world feel authored?* |
| 5 | First dungeon + boss | *Does escalation land?* |
| 6 | First cinematic / story arc | *Do we care?* |
| 7 | Open-world architecture | *Is the world genuinely connected?* |
| 8 | 12-race system | |
| 9 | Soul framework expansion | |
| 10 | Regional / city expansion | |
| 11 | Prime Beast architecture | |
| 12 | Full narrative + cinematic production | |
| 13 | World / content completion | |
| 14 | Gameplay balancing | |
| 15 | Performance + optimisation | |
| 16 | Full QA | |
| 17 | Release candidate | *Is it finished?* |

M1–M3 are the project's thesis. If a skilled player does not enjoy fighting a
single intelligent enemy with one Soul, no amount of world content rescues the
game. That is why they come first, and why M4 is gated behind them.

---

## 8. Milestone 0 verdict

| Check | Result |
|---|---|
| Existing foundation worth preserving? | **N/A — repository was empty.** Full greenfield. |
| Engine selected and justified? | ✅ Godot 4.x — `docs/TECH_STACK.md` |
| Language locked? | ✅ GDScript, single-language, GDExtension escape hatch documented |
| Renderer locked? | ✅ Forward+ |
| Critical risks identified with owners? | ✅ 10 risks, all mitigated or explicitly accepted |
| Repository structure established? | ✅ `src/` ⟂ `data/` separation enforced |
| Version control initialised? | ✅ `main`, correct identity, remote configured |
| Push credentials working? | ⚠️ Blocked on SSH key registration (R9). Does not block development. |
| Runnable project? | ✅ `project.godot` present and opens |

**M0 is complete. Production proceeds to M1 — movement, input and the combat
foundation.**

The one open item (R9, push credentials) is external to the codebase and
blocks nothing but the mirror to GitHub.
