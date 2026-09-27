# VOWED — Known Issues

Open defects and unresolved audit findings. **Every entry has an owner
milestone.** An issue with no milestone is not tracked work; it is a worry, and
worries do not belong in a register.

Issues are removed only when fixed, never when merely tolerated. A tolerated
issue is moved to **Accepted** below, with the reason, so that "we decided to
live with this" is distinguishable from "we forgot about this".

---

## Open

| ID | Item | Severity | Owner |
|---|---|---|---|
| **I2** | On this machine (macOS 26 / Metal / M3) presentation is pinned to the 60 Hz display refresh even with `window/vsync/vsync_mode=0`, and `DisplayServer.window_get_vsync_mode()` reporting DISABLED. Raw frame time therefore always reads ~16.7 ms. | Low | M15 |
| **I1** | Every run prints `N ObjectDB instances were leaked at exit` / `N resources still in use at exit` / leaked RIDs on quit. N scales with loaded CONTENT, not with runtime lifetime. | Low | M16 |

**I1 detail.** Investigated with `--verbose` rather than assumed. As of the
animated build the leaked set is, precisely:

- **46 `Animation` resources**, each at refcount 5 — the 46 clips of the shared
  animation library, referenced by the 4 actors' `AnimationPlayer`s plus the
  cached `PackedScene`.
- The 4 instantiated character subtrees (`Skeleton3D`, `AnimationPlayer`,
  `MeshInstance3D`, `Node3D`) and their materials, mesh and skin.
- 7 `GDScript` resources for the scripts declaring typed arrays of custom
  classes (`Array[ComboEdge]` and similar), which Godot's script cache retains.

So the count scales with **how much content is loaded**, not with how long the
game runs. Nothing accumulates during play, and it is reported only at process
exit.

A fix was attempted and **reverted**: releasing the autoloads' references in
`_exit_tree()` changed the numbers by exactly zero, because the autoloads were
never the holder. The code was removed rather than kept, since code justified by
a rationale that measurement disproved is debt.

Still deliberately **not** filtered out of the test or run output. A command that
strips lines matching `ERROR` would hide the next leak too, and that one might be
real.

**I2 detail.** Measured rather than assumed: with 4 skinned actors the scene
draws 73 calls / 140k primitives and spends **1.6 ms** in the physics step, yet
reports 60.0 fps and ~17 ms "process" time. The present-wait is being attributed
to process time. Forcing `Engine.max_fps = 0` and
`DisplayServer.window_set_vsync_mode(VSYNC_DISABLED)` at runtime does not lift
the cap.

Consequence for tooling: the debug overlay now detects the display refresh rate
and reports frame time as *vsync-capped* in neutral colour rather than red, and
shows **physics-step time** as the honest CPU figure — that is real work, never
inflated by waiting, and the number that actually moves when combat or AI
regresses. A performance panel that is permanently red is a panel nobody reads.

Real GPU-cost profiling needs a tool that can see past the compositor, which is
an M15 concern. Until then, physics time and draw calls are the meaningful
signals.

## Accepted (deliberate, not forgotten)

| ID | Item | Why accepted | Revisit at |
|---|---|---|---|
| A1 | **Blender not installed.** No DCC tool for bespoke asset authoring. | M1–M6 run entirely on open-licence external assets and graybox geometry. Installing tooling before there is a use for it is ceremony, and unused tooling rots. | M11 (first bespoke Prime Beast assets) |
| A2 | **No CI runners.** Tests run locally via `--headless`. | For a solo project on a headless-testable engine, local runs cover the same ground. CI's real value is multi-contributor gating, which does not yet apply. | M16 (Full QA) |
| A3 | **No localisation pipeline.** | Only one decision here is expensive to reverse — key-addressed dialogue text — and that is locked from M6. Actual translation is a post-content concern. | Post-M13 |
| A4 | **Console platforms out of scope.** | Would require a porting partner and certification work orthogonal to making the game good. | Post-release |
| A5 | **8 GB unified memory on the dev machine** constrains world size, texture budget and editor headroom. | Cannot be engineered away; it is hardware. It is instead *designed around*: streaming is load-bearing from the first region, and memory budgets are enforced by a monitor from M1. Tracked as R1 in `INITIAL_AUDIT.md`. | Continuous |

---

## Resolved

| ID | Item | Resolution | Closed |
|---|---|---|---|
| R9 | GitHub SSH key present locally but not registered on the account; remote unreachable, so no off-machine backup existed. | Key registered on the account; `git@github.com` authenticates as `ashvyagni`. Pushes working. | 2026-09-27 (M0) |

---

## Severity definitions

| Severity | Meaning |
|---|---|
| **Critical** | Blocks the milestone, or will be catastrophically expensive to fix later. Fix now. |
| **High** | Materially damages a pillar (combat feel, world connectedness, Soul identity). Fix this milestone. |
| **Medium** | Real problem, contained. Fix before the system it affects is expanded on. |
| **Low** | Cosmetic, or an inconvenience with a workaround. Fix opportunistically. |

The severity that matters most is **"cheap now, catastrophic later"**. Those are
recorded as Critical regardless of how harmless they currently look — the
combat tick model was exactly this kind of issue, which is why it was resolved
at M0 rather than discovered at M3.
