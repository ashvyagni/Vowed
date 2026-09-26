# VOWED — Known Issues

Open defects and unresolved audit findings. **Every entry has an owner
milestone.** An issue with no milestone is not tracked work; it is a worry, and
worries do not belong in a register.

Issues are removed only when fixed, never when merely tolerated. A tolerated
issue is moved to **Accepted** below, with the reason, so that "we decided to
live with this" is distinguishable from "we forgot about this".

---

## Open

*None.*

The project is at the end of M0 with a greenfield codebase. The first entries
will arrive with the first real system.

---

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
