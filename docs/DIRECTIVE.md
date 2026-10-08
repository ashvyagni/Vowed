# VOWED — Super Master Directive

> **Provenance.** Issued by the owner (Ashwin Dandotiya, `ashvyagni`) on
> 2026-10-09 as the highest project-level instruction. Committed verbatim so it
> lives in the repository rather than in a chat transcript (§58).
>
> **One known discrepancy, recorded rather than silently resolved:** §36 lists
> a 13-milestone sequence (M3 = "expanded combat + Soul foundations", M13 =
> release candidate). `docs/MILESTONES.md` defines 17 milestones (M3 = Infiroar
> Soul, M17 = release candidate). §36 itself says its list is "conceptual
> milestone directions, not permission to ignore the actual milestone
> document", so **`docs/MILESTONES.md` is authoritative for milestone numbering
> and scope.** The two agree on M1 and M2.

---

# 0. READ THIS FIRST

You are working on **VOWED**, a full-scale commercial-quality action RPG.

Before doing anything:

1. Read this directive completely.
2. Read `docs/HANDOFF.md`.
3. Read `docs/MILESTONES.md`.
4. Read `docs/COMBAT.md`.
5. Read `docs/ARCHITECTURE.md`.
6. Read `docs/TECH_STACK.md`.
7. Read `docs/AUDITS.md`.
8. Read `docs/KNOWN_ISSUES.md`.
9. Read `docs/ASSET_LICENSES.md`.

Then inspect the actual repository.

Do not assume that documentation is perfectly synchronized with the implementation. **The repository is the source of truth for what currently exists.**

If documentation and implementation disagree: measure, inspect, determine which is correct, fix the inconsistency, document the reasoning. Do not blindly preserve either side.

---

# 1. THE PRODUCT

VOWED is a stylised 3D open-world fantasy action RPG built around one central idea:

> **Your Beast Soul changes how you fight, not merely how much damage you deal.**

The game combines open-world exploration, authored fantasy regions, race identity, Beast Souls, mechanically expressive action combat, fighting-game-style input, aerial combat, authored combo routes, enemy combatants capable of mechanically interacting with the same combat system as the player, cinematic storytelling, exploration, quests, progression, lore, bosses, dungeons, towns and settlements, environmental storytelling, and a persistent world.

This is not an ability-bar RPG. This is not a damage-number simulator. This is not a Soulslike clone. This is not a student game. This is not a prototype. This is not a portfolio demo.

**It is a game intended to be publicly released as a finished product.**

---

# 2. THE OWNER'S QUALITY BAR

> **If a feature exists, it should eventually feel like it belongs in the finished game.**

Temporary implementation is allowed during development. Temporary *design quality* is not.

Do not confuse placeholder architecture with finished architecture, placeholder assets with finished assets, prototype content with shipped content, debug UI with game UI, or generated data with final authored content.

Every placeholder must be: identifiable, tracked, replaceable, and prevented from silently becoming permanent.

---

# 3. NON-NEGOTIABLE DIRECTIVES

## 3.1 No artificial scope reduction

Never respond with "This is too ambitious for a solo developer." Instead: decompose the problem, identify dependencies, establish milestones, build the hardest risk first, create reusable systems, automate repetitive work, measure performance, and proceed incrementally. Ambition is managed through architecture, not destroyed through premature scope reduction.

## 3.2 No MVP mindset

No public MVP, no public beta, no early access, no vertical slice presented as the finished product, no demo marketed as the game. Internal prototypes and development builds are acceptable. **The first public release is the finished game.**

## 3.3 Combat is the highest-priority system

Combat must eventually reach a fighting-game-grade standard: real frame data, deterministic timing, cancel windows, input buffering, hitstop, hit reactions, priority/trade resolution, aerial combat, launchers, juggles, directional attacks, dash attacks, guard, parry, Soul Techniques, Manifestations, lock-on, enemy combat competence, authored combo routes, and eventually **100+ meaningful authored routes**.

Do not allow combat to become: press ability → wait cooldown → watch animation → repeat. The player should be able to learn the combat language and become mechanically better.

---

# 4. THE INPUT LANGUAGE

| Input   | Function           |
| ------- | ------------------ |
| `J`     | Kick               |
| `K`     | Punch              |
| `Space` | Jump               |
| `Shift` | Dash               |
| `Q`     | Guard / Parry      |
| `E`     | Soul Technique     |
| `R`     | Soul Manifestation |
| `Tab`   | Lock-on            |

Directional input is part of the combat language: neutral, forward, backward, aerial and dash attacks, contextual transitions, combo routing, timing-dependent cancels, and eventually more advanced input patterns. Do not replace this philosophy with MMO-style skill-bar design.

---

# 5. COMBAT PRINCIPLES

Sacred unless measurement proves they must change.

## 5.1 Fixed logical combat clock

Combat operates on a fixed 60 Hz logical tick. Frames are the unit of combat time. No `delta`-based combat timing, Timer nodes, wall-clock timing, animation playback timing, or frame-rate-dependent combat logic. Animation is subordinate to combat state.

## 5.2 Deterministic hit detection

Explicit ordered shape queries: GATHER → ADJUDICATE → APPLY. Never unordered signal-based collision logic.

## 5.3 Combat phase ordering

Every actor progresses through INTENT → COMBAT → RESOLVE → MOTION once per logical tick — player, enemies, bosses, summons, and future special combat entities alike.

---

# 6. ROUTING VS TIMING

**ROUTING** — "What is allowed to follow this?" — `ComboGraph`.
**TIMING** — "When am I allowed to leave this action?" — `AttackData` / `CancelWindow`.

These remain conceptually independent. This separation is what makes hundreds of authored moves manageable.

---

# 7. PLAYER ≠ SPECIAL COMBAT ENTITY

```text
PLAYER  = CombatComponent + PlayerIntentSource
ENEMY   = CombatComponent + EnemyIntentSource
```

Never a special fake combat system for enemies. Enemies must eventually attack, defend, react, interrupt, parry, space, exploit openings, use movement and Soul mechanics, chain routes, and mechanically out-play the player — dangerous because of **decision quality**, not unfair statistical advantages.

---

# 8. BEAST SOULS

A Soul should fundamentally alter combat identity — movement, attack properties, routes, specials, defence, mobility, aerial behaviour, timing, resources, spacing, stance, transformation, environmental interaction — never merely +X% stats.

> **Soul choice changes how you play**, not your DPS number.

---

# 9. THE WORLD

Eventually: 12 major regions, settlements, villages, hubs, wilderness of every kind, caves, ruins, underground environments, dungeons, landmarks, traversal routes, hidden locations, NPC populations, quests, environmental storytelling, enemies, bosses, secrets and authored set pieces. The world must not feel like disconnected maps. Regions have history and visual, gameplay, enemy, cultural, ecological and narrative identity.

# 10. WORLD DESIGN PRINCIPLE

Not "large empty terrain + random NPCs + collectible spam". Each region: identity, geography, culture, conflict, economy, factions, wildlife, enemy ecosystem, main quest, side quests, secrets, dungeon, boss, environmental storytelling, traversal identity. Every region answers *why does this place exist?* and *why would the player remember it?*

# 11. RACES

12 races. Selection must matter beyond cosmetics — combat tendencies, passives, Soul compatibility, traversal, cultural relationships, dialogue, equipment, starting techniques — without artificial stat walls.

# 12. PROGRESSION

Multi-dimensional: combat mastery, Beast Soul, techniques, equipment, exploration, quest, world knowledge, narrative. Mechanical mastery should matter; not exclusively "bigger number = stronger".

# 13. CINEMATICS

Part of the game, not decoration: camera choreography, staging, animation, dialogue, environment, transitions, music/audio, pacing, reveals. Stage moments with the engine.

# 14. DIALOGUE AND LORE

Maintain a lore bible tracking chronology, factions, races, Beast Souls, Prime Beasts, regions, events, characters, politics, myths, terminology, reveals and contradictions. Never casually invent lore that conflicts with canon.

# 15. PRIME BEASTS

~30, each with distinct combat identity, behaviour, attacks, movement, encounter structure, environmental relationship, visual identity and lore significance — never "enemy with more HP".

# 16. ENEMY DESIGN

Basic enemies teach spacing, reaction, timing, defence, punish windows. Advanced enemies introduce mixups, movement, counters, defensive behaviour, combo disruption. Elites demand adaptation and precise timing. Bosses are mechanically authored encounters testing movement, Souls, timing, positioning, defence and pattern recognition.

# 17. AI PHILOSOPHY

Not random attack selection. AI reasons about distance, own and player state, available routes, punish windows, risk, defensive options, Souls, environment and the player's previous behaviour — under the same combat constraints as the player.

---

# 18. DATA-DRIVEN CONTENT

```text
src/  = systems
data/ = content
```

Adding a Soul, Beast, race, attack, route, enemy or reaction should require data authoring, not a new script. **Generated resources remain generated: modify the generator, then regenerate.** Never hand-edit generated output.

# 19. MEASURE BEFORE TUNING

Reproduce → instrument → observe → identify structural cause → fix the cause → measure → ablate → confirm → document. Never "change a number until the test passes".

# 20. TESTING PHILOSOPHY

A test is useful only if it can detect the defect it claims to guard. Negative-test important guards: pass → break the guarded behaviour → confirm fail → restore → pass. Beware zero-assertion tests, tests that never execute the path, tests measuring the wrong node, bind-pose transforms, accidental engine behaviour, and tests where expected and actual are both wrong.

# 21. PERFORMANCE

A design constraint. Measure frame time, physics, draw calls, memory, scene complexity, animation, AI, streaming, collision. Do not optimise on intuition; do not build what obviously cannot scale. Document target hardware as the project evolves.

---

# 22. OPEN-SOURCE AND ASSET POLICY

Downloading safe open-source resources is authorised. **No purchases** — of assets, plugins, software, subscriptions, licences or services.

Acceptable: CC0, public domain, CC-BY, MIT, Apache-2.0, BSD, OFL where appropriate.
Reject: CC-NC, CC-BY-SA where incompatible with a proprietary release, "free to use" without an actual licence, ripped commercial assets, uncertain provenance, AI-generated assets with unclear training provenance, anything whose licence cannot be independently verified.

The exact asset page is the authority; search snippets are not. Every asset added must be registered.

# 23. ASSET SEARCH STRATEGY

Search existing project assets → known permissive libraries → verify the exact licence → download only if clear → test compatibility → retarget if justified → register → integrate → test → document. If the licence cannot be established: reject it. Do not rationalise.

# 24. ANIMATION PHILOSOPHY

Combat animation communicates anticipation, startup, active frames, recovery, impact, hit reaction, cancel timing and movement. It must align with frame data. For important attacks reason explicitly about startup, active, recovery, impact, cancel, movement and hit reaction. Do not blindly retarget and assume combat-readiness; if a retarget reads poorly, replace or author it.

# 25. PLACEHOLDERS

Allowed; untracked placeholders are not. Every placeholder is discoverable through metadata, validation, a TODO registry, build output, or milestone tracking. The project must always know *what is still fake* and *what prevents this system from being finished*.

# 26. DEBUGGING TOOLS ARE FIRST-CLASS INFRASTRUCTURE

Hitbox visualisation, frame stepping, slow motion, state overlays, attack-frame display, input history, route visualisation, actor state, AI decision inspection, animation inspection, profiling, deterministic replay, combat recording. If a system is hard to inspect, improve the tooling instead of debugging blind.

# 27. DEBUG KEYS

`F1` overlay · `F2` hitboxes · `F3` frame-step · `F4` pause · `F5` slow-mo · `F6` reset · `1–5` dummy behaviour. Preserve unless there is a measured reason to change them.

# 28. DEVELOPMENT LOOP

BUILD → PLAYABLE STATE → AUDIT → FIX → DOCUMENT → COMMIT → PUSH. Do not skip the playable state. Do not declare success solely because tests pass, nor solely because it looks good.

# 29. HUMAN PLAYTESTING

At milestone exits, distinguish **machine verified** (tests), **developer verified** (observed in development) and **human-playtest verified** (judged by playing). Do not mark a milestone complete while a human verdict is outstanding. The owner is the final authority on subjective exit criteria.

# 30. DOCUMENTATION

Explain what exists, why, what it assumes, what was measured, what failed, why a decision was made and what remains uncertain. If a mechanism is disproven: remove it, update the docs, remove the false comment.

# 31. GIT

Commit and push regularly. `bash tools/check.sh` must be green before every commit. Subject = the actual change or defect; body = reasoning and measurement. No "fix stuff" / "update" / "final".

# 32. BRANCH DISCIPLINE

Work on the intended branch. Check `git status` and `git log` before substantial changes. Never assume a clean tree, never overwrite unrelated owner work, never reset or rewrite history without explicit authorisation.

# 33. AUTONOMOUS ENGINEERING

When one option is clearly superior: identify, compare, choose, implement, document. Ask the owner only when the decision changes the game's identity, there is a genuine product-direction conflict, a destructive irreversible action is required, or the preference is genuinely unknowable.

# 34. REPLACE WEAK IDEAS

If a system is fundamentally wrong: identify, explain, measure, design the replacement, migrate safely, remove the old system.

# 35. DO NOT GAME THE CHECKS

Never weaken assertions, remove failing cases, skip tests, fake data, hardcode expected outputs, hide warnings, suppress errors, or redefine success around what currently works. If the test is wrong, prove it and fix the test; if the implementation is wrong, fix the implementation.

# 36. MILESTONE PHILOSOPHY

Milestones produce meaningful playable capability: *what can the player do now that they could not before?* Conceptual directions: M1 movement/input/combat foundation · M2 enemy combat AI · M3 expanded combat + Soul foundations · M4 first complete region · M5 traversal + progression · M6 quest/NPC · M7 Prime Beast/boss · M8 dungeons · M9 narrative/cinematics · M10 world expansion · M11 content integration · M12 polish/optimisation/accessibility/UX · M13 release candidate. *(See the provenance note at the top: `docs/MILESTONES.md` is authoritative for numbering.)*

# 37. MILESTONE EXIT CRITERIA

Complete only when IMPLEMENTED + TESTED + PLAYABLE + AUDITED + DOCUMENTED + PERFORMANCE ACCEPTABLE + KNOWN ISSUES ACCOUNTED FOR + OWNER EXIT CRITERION SATISFIED.

# 38. CURRENT PRIORITY (as of issue)

M1 substantially implemented, **not signed off**; blocked on the human-playtest verdict. Biggest content problem: kick animations — 9 of 16 attacks played a placeholder sword swing. **First priority: resolve kick animation presentation properly**, then playtest M1, audit exit criteria, fix, sign off only when justified, begin M2.

# 39. KICK ANIMATION OPTIONS

**A — KayKit** (CC0 lead, confirmed kick, requires `Rig_Medium` retarget). **B — author original animation** against the existing rig (zero licensing dependency, exact frame control, no retarget uncertainty). Choose on combat readability, technical quality, timing control, consistency, licensing and maintainability — not on speed alone.

# 40. FUTURE COMBAT EXPANSION

Core (punches, kicks, launchers, aerial strings, dash attacks, command normals) → Defensive (guard, parry, guard recovery, punish states, perfect defence windows) → Advanced (Soul Techniques, Manifestation, movement cancels, air recovery, advanced juggling, counters, stances where justified) → Authoring toward 100+ *meaningful* routes, never inflated by trivial permutations.

# 41. SOUL SYSTEM EXPANSION

System first, then content. Data-driven definitions for identity, passives, techniques, manifestations, movement and attack modifiers, routes, resources, VFX, audio and lore. Adding Soul #31 must be dramatically easier than Soul #1.

# 42. CONTENT PIPELINE

Design Definition → Validation → Generated Resource → Runtime Registration → Automated Tests → Playtest. Every generated asset is reproducible; a fresh checkout rebuilds generated resources from source.

# 43. SAVE / PERSISTENCE

Design early enough that systems don't assume session-only state: progression, Souls, equipment, quests, world state, discoveries, defeated bosses, NPC state. Versioned save data; migrations possible.

# 44. WORLD STREAMING

Design toward region streaming, scene boundaries, asset lifetime, background loading, persistent state, transitions — but do not build a massive streaming framework before the world demands it. Measure first.

# 45. UI/UX

The finished game must not look like a developer tool. Final UI communicates health, Soul state, resources, combat state, quests, navigation, inventory and settings without overwhelming.

# 46. AUDIO

Part of combat readability: distinct startup, swing, impact, block, parry, perfect defence, launch, knockdown, Soul activation, Manifestation, enemy attacks, environment. Not one generic impact for everything.

# 47. VISUAL EFFECTS

VFX communicate gameplay state. Readability first; not every attack is a particle explosion.

# 48. CAMERA

Supports combat: lock-on, framing, aerial, large enemies, bosses, narrow spaces, traversal, cinematic transitions. **Camera must never become a prerequisite for combat legality.** World facts belong to combat; presentation belongs to the camera.

# 49. ACCESSIBILITY

Before release: remapping, sensitivity, camera options, subtitles, text and colour readability, motion options, difficulty where appropriate, audio controls. Part of the product, not an afterthought.

# 50. RELEASE QUALITY

Evaluate gameplay, technical stability and performance, content, product (UI, settings, onboarding, credits, licensing) and QA (regression, integration, playtesting, edge cases, long sessions, save corruption, performance).

# 51. THE STANDARD FOR "DONE"

> It works, is understandable, is testable, is maintainable, is performant enough, fits the game's design, has appropriate content, and survives actual play.

# 52. THE STANDARD FOR "GOOD"

> Would a player notice that this was made as a shortcut?

If yes: improve it, replace it, or explicitly track it as unfinished.

# 53. THE STANDARD FOR AGENT WORK

Act as gameplay engineer, systems engineer, technical designer, QA engineer, tools engineer, technical director and implementation partner. Think in systems, protect invariants, measure assumptions, build tools that make future work cheaper, document reasoning.

# 54. WHEN SOMETHING GOES WRONG

STOP → REPRODUCE → OBSERVE → INSTRUMENT → ROOT CAUSE → HYPOTHESIS → CHANGE ONE THING → MEASURE → ABLATE → TEST → DOCUMENT. No shotgun fixes, no stacked speculative changes, no celebrating a green test you can't explain.

# 55. WHEN AN IDEA IS BAD

Say so — whether it came from the owner or a previous agent — and propose a better alternative.

# 56. WHEN DOCUMENTATION IS WRONG

Fix the docs. When code is wrong, fix the code. Both: fix both. Neither certain: measure.

# 57. WHEN A FEATURE IS TOO LARGE

Decompose, don't shrink. Large features become milestones, not excuses for reduced quality.

# 58. PROJECT MEMORY

Important decisions live in the repository — architecture docs, audits, milestones, comments, commit history — not in chat.

# 59. FINAL PRINCIPLE

> **Build the game that VOWED is supposed to become, not merely the easiest version that can be made today.**

Be ambitious. Be empirical. Be ruthless about weak engineering and equally ruthless about fake polish. Do not hide uncertainty, manufacture progress, or optimise for impressive reports. Optimise for a real game.

# 60. EXECUTION ORDER (as of issue)

1. Read repository + handoff · 2. Verify branch/state · 3. Run the gate · 4. Resolve the kick animation gap · 5. Playtest M1 · 6. Audit M1 exit criteria · 7. Fix · 8. Document the audit · 9. Commit · 10. Push · 11. Begin M2 · 12. Enemy Intent system · 13. Reuse CombatComponent · 14. First genuinely competent enemy · 15. Player-vs-enemy tests · 16. Playtest · 17. Audit M2 · 18. Toward the Soul system · 19. Expand combat authoring · 20. World/content systems · 21. Continue milestone by milestone.

At every stage: BUILD → PLAYABLE → AUDIT → FIX → DOCUMENT → COMMIT → PUSH. Never skip the audit; never skip the playtest where a human judgement is required. **The final judge is the player.**
