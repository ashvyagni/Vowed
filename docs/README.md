# VOWED — Documentation index

Living documentation. **Every document here describes what actually exists**, not
what is intended. A document that overstates reality is treated as a defect, not
as optimism.

Documents are created **when their milestone begins**, not up front. An empty or
speculative document is worse than an absent one: it reads as authority while
containing fiction. The "planned" rows below are therefore deliberate absences,
each with the milestone that will create it.

---

## Current

| Document | Purpose | Status |
|---|---|---|
| [INITIAL_AUDIT.md](INITIAL_AUDIT.md) | M0 environment + repository audit, risk register, architecture recommendation | ✅ Complete |
| [TECH_STACK.md](TECH_STACK.md) | The locked technical stack, reasoning, rejected alternatives, change policy | ✅ Locked |
| [MILESTONES.md](MILESTONES.md) | Roadmap with binding exit criteria per milestone | ✅ Live |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System architecture, module boundaries, data flow | ✅ Live |
| [AUDITS.md](AUDITS.md) | Milestone audit records against the fixed 13-point checklist | ✅ Live |
| [KNOWN_ISSUES.md](KNOWN_ISSUES.md) | Open defects and unresolved audit findings, each with an owner | ✅ Live |
| [ASSET_LICENSES.md](ASSET_LICENSES.md) | Provenance and licence record for every external asset | ✅ Live |
| [COMBAT.md](COMBAT.md) | Frame-data model, combo graph, cancel rules, defence, air combat | ✅ Live |

## Planned

| Document | Purpose | Created at |
|---|---|---|
| `AUDIO.md` | Adaptive music architecture, combat feedback sound design | M3 |
| `WORLD.md` | World geography, regions, traversal, streaming contract | M4 |
| `QUESTS.md` | Quest system and authored quest content | M6 |
| `LORE_BIBLE.md` | Canonical world history, myth, races, Beasts, terminology | M6 |
| `CHARACTERS.md` | Character bibles: motivation, worldview, arc, speech style | M6 |
| `CINEMATICS.md` | Cinematic framework and scene inventory | M6 |
| `RACES.md` | The 12 races and their mechanical identities | M8 |
| `SOULS.md` | Soul framework and per-Soul design | M9 |

`SOULS.md` is a deliberate case worth explaining: Infiroar is implemented at M3,
but the *framework* document is written at M9 when there are several Souls to
generalise from. Writing it at M3 would document one example as if it were a
pattern, which is how bad abstractions get canonised.

`LORE_BIBLE.md` is gated at M6 for the opposite reason — it must exist **before**
any narrative content is authored, so that lore is never improvised
independently in multiple systems. M6 is the first milestone that authors
narrative, which makes it the correct and latest-safe moment.

---

## Conventions

- **Decisions record their reasoning**, including what was rejected and why. A
  decision without reasoning cannot be revisited intelligently later — it can
  only be re-argued from scratch.
- **Weaknesses are stated, not hidden.** Every technical choice in
  `TECH_STACK.md` lists its downsides and the plan for each. A document that
  only lists advantages is marketing, not engineering.
- **Risks have owners and milestones.** A risk without a named mitigation and a
  milestone is not a managed risk; it is a worry.
- **Exit criteria are demonstrations, not opinions.** "Combat feels good" is not
  an exit criterion; "combat runs identically at 60 and 144 fps" is.
