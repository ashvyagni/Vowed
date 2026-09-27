# VOWED

> A martial-combat action RPG where an inherited Beast Soul changes the way you
> fight, in an interconnected fantasy world reacting to the legendary beings
> that threaten it.

You do not equip powers. You learn them, master them, combine them, and
eventually synchronise with them.

**Status:** In development. Milestone 1 of 17 — combat foundation playable.
**Not released.** There is no beta, no early access and no public demo — by
policy. The first public release will be the finished game.

---

## The design north star

> Master your body. Awaken your Soul. Explore the world.
> Face the beings that terrify civilisations.

The player should finish this game thinking:

> *"I didn't get strong because the game gave me bigger numbers.
> I got strong because I learned how to fight."*

Every system is measured against that sentence. The Beast Soul is an **extension
of the player's mastery, not a replacement for it** — base combat has to be
genuinely enjoyable before Manifestation is ever used.

---

## Pillars

| Pillar | What it means concretely |
|---|---|
| **Mechanical combat** | Fighting-game-grade frame data, cancel windows, input buffering, air combat. Skill is legible and rewarded. |
| **Beast Souls** | Souls change *how you fight*, never *your damage number*. Each one encourages a different style. |
| **Intelligent enemies** | Difficulty raises decision quality, not HP. An enemy can out-play you. |
| **A genuinely connected world** | You see a distant mountain, find the pass, cross the bridge, reach the next valley. Not a level select. |
| **Authored content** | One excellent city beats five empty ones. One excellent Prime Beast beats ten shallow ones. |

---

## Technology

| | |
|---|---|
| Engine | Godot **4.7.2-stable** |
| Language | GDScript, single-language, statically typed |
| Renderer | Forward+ |
| 3D physics | Jolt |
| Combat timing | Fixed **60 Hz** logical tick; animation slaved to the frame counter |
| Hit detection | Explicit per-frame shape queries (never `Area3D` signals) |
| Platforms | Windows x64, macOS universal, Linux x64 |

The full reasoning, including the rejected alternatives and the honest
weaknesses of each choice, is in **[docs/TECH_STACK.md](docs/TECH_STACK.md)**.

Two of those decisions are effectively irreversible and were therefore made
before any gameplay code was written — the fixed combat tick and the explicit
hit-detection model. Both exist because combat *feel* is decided by
architecture, not by tuning.

---

## Repository layout

```
src/      ALL code. Systems only — never content.
data/     ALL authored content as Godot Resources. Never code.
scenes/   Composed scenes. scenes/lab/ holds the Combat Lab.
assets/   Art, audio, VFX. assets/licenses/ records provenance.
tests/    Headless-runnable unit + integration tests.
tools/    Pipeline scripts (bakes, validators, generators).
docs/     Living documentation — see docs/README.md.
```

The `src/` ⟂ `data/` split is the project's most important structural rule:

> **Code defines *how* a system behaves. Data defines *what* exists.
> A new Soul, Beast, race, attack, combo route, enemy, region, quest or dialogue
> tree must be addable without writing a script.**

This is what makes a roster of 30 Prime Beasts, 12 races and 100+ combat routes
reachable by authoring rather than by engineering. Any commit that hardcodes
content into `src/` is a defect even if it works.

---

## Running the project

Requires Godot 4.7.2+ on `PATH` (`brew install --cask godot`) and Python 3.

### First-time setup after cloning

```bash
tools/import.sh
```

This is not optional. Godot registers `class_name` declarations during an editor
filesystem scan and caches them in `.godot/`, which is machine-local and
gitignored. A fresh clone has no registry, so every script referencing a project
class fails with `Could not find type X in the current scope` — an error that
looks like a code bug and is not one. Run it again whenever you add a new
`class_name`.

### Everyday commands

```bash
tools/check.sh          # full gate: import, boot self-check, tests, asset licences
```

```bash
tools/test.sh           # test suite only  (tools/test.sh buffer to filter)
```

```bash
godot --editor --path . # open the editor
```

```bash
godot --path .          # run the game
```

`tools/check.sh` is the pre-commit gate and exits non-zero on any failure.

Boot performs a configuration self-check (physics tick, renderer, physics
backend, input map, collision layers) and fails loudly if a locked decision has
drifted — see [src/core/Bootstrap.gd](src/core/Bootstrap.gd).

Regenerate the default input bindings (the binding table is authored as code in
that script):

```bash
godot --headless --path . -s tools/generate_input_map.gd
```

### Testing

Tests run headlessly on a project-owned harness in `tests/framework/` — not GUT.
The reasoning is recorded in [docs/TECH_STACK.md](docs/TECH_STACK.md) §10.1: what
this project needs to test is overwhelmingly pure logic (frame data, combo
resolution, input windows, save migrations), which needs discovery, assertions
and an exit code, and little else.

Write a test by extending `TestCase`, naming the file `*_test.gd` under `tests/`,
and naming methods `test_*`.

---

## Controls (default)

| Key | Action | Pad |
|---|---|---|
| `W A S D` | Move | Left stick |
| `J` | **Kick** | Y |
| `K` | **Punch** | X |
| `Space` | Jump | A |
| `Shift` | Dash | RB |
| `Q` | Guard / Parry | LB |
| `E` | Soul Technique | B |
| `R` | **Manifestation** | RT |
| `F` | Interact | D-pad ↑ |
| `Tab` | Lock on | Right stick click |

Combat verbs combine contextually (`J`, `K`, `J J`, `K K`, `K J`, `Space + K`,
`Shift + J`, `Q + K`, `E + J`, …) rather than occupying an MMO ability bar.
All gameplay bindings are rebindable; gamepad is supported in parallel from
Milestone 1 rather than retrofitted later.

`F1`–`F6` drive the debug overlays: overlay, hitboxes, frame-step, pause,
slow-motion, lab reset. In the Combat Lab, `1`–`5` set every training dummy's
behaviour (idle, block, parry, counter, aggressive).

Running the project opens the **Combat Lab** — an isolated arena with training
dummies, distance rings and a live frame-data readout. It exists before any real
level because tuning combat inside a real environment is slow and confounded.

---

## Development process

```
BUILD → PLAYABLE STATE → AUDIT → FIX → DOCUMENT → NEXT MILESTONE
```

Standing rules: every milestone leaves the repository runnable; every milestone
ends with a recorded audit; no expansion over a broken foundation; asset licences
are recorded at acquisition, never retroactively; documentation describes what
*exists*, not what is intended.

**Milestones 1–3 are the project's thesis** — movement, mechanical Taijutsu, one
intelligent enemy, and the Infiroar Soul with Resonance and Manifestation.
Milestone 4 (the first region) is hard-gated behind them. If fighting one enemy
with one Soul is not excellent, world content only multiplies the problem across
twelve regions.

Roadmap and exit criteria: **[docs/MILESTONES.md](docs/MILESTONES.md)**.

---

## Licensing and assets

Game code and original content: © Ashwin. All rights reserved.

External assets are used only under **CC0, public-domain or clearly documented
permissive commercial licences**, verified at the source rather than from search
snippets. Every asset's provenance is recorded in
[docs/ASSET_LICENSES.md](docs/ASSET_LICENSES.md) and
`assets/licenses/assets.json` **at acquisition time**.

If a licence cannot be established, the asset is not used. No ripped models,
animations, textures, logos or character designs — the visual identity belongs
entirely to this project.
