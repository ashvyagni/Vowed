# VOWED — Asset Licences

Provenance and licence record for **every** external asset in the project.

## The rule

> **An asset with no licence record is treated as absent.**
> Records are written **at acquisition time**, never retroactively.

This is not bureaucracy. Retroactive licence archaeology at release time is the
standard way an otherwise finished game becomes unshippable: by then the
download page has changed, the licence has been revised, the author has
relicensed, and there is no way to prove what terms applied when the asset was
taken. Recording at acquisition costs thirty seconds and removes that failure
mode entirely.

## Acquisition procedure

Every external asset follows all seven steps, in order:

1. **Inspect the source.** Confirm the site is the creator's own distribution
   channel or an authorised library — not a re-upload aggregator.
2. **Verify the licence of the exact asset**, on its own page. Pack-level or
   site-level licence claims are not sufficient: packs frequently contain files
   under different terms.
3. **Never trust a search-result snippet.** Open the page. Read the terms.
4. **Download legitimately** from that source.
5. **Import and test** in-engine before committing.
6. **Normalise** — scale, orientation, pivot, naming, and skeleton retarget to
   the project's canonical rig.
7. **Record it** in the table below *and* in `assets/licenses/assets.json`.

If the licence cannot be established with certainty: **do not use the asset.**
Ambiguity is a rejection, not a risk to weigh.

## Acceptable licences

| Licence | Status | Attribution |
|---|---|---|
| CC0 / Public Domain | ✅ Preferred | Not required (recorded anyway) |
| CC-BY 4.0 / 3.0 | ✅ Acceptable | **Required** — see Attribution below |
| MIT / Apache-2.0 / BSD | ✅ Acceptable | Notice required |
| OFL (fonts) | ✅ Acceptable | Per licence terms |
| Explicitly commercial-permissive custom licence | ⚠️ Case by case | Terms archived verbatim in `assets/licenses/` |
| CC-BY-SA | ❌ Rejected | Share-alike is incompatible with a proprietary game |
| CC-NC (any non-commercial) | ❌ Rejected | Incompatible with commercial release |
| "Free to use" with no named licence | ❌ Rejected | Not a licence. No enforceable terms. |
| Ripped from any commercial game | ❌ Never | See below |

## Absolute prohibitions

No ripped models, animations, textures, audio or UI. No franchise assets, logos
or trademarks. No copied character designs. No AI-generated assets whose
training provenance cannot be established for commercial use.

The visual and audio identity of this game belongs entirely to this project.
External assets are a **scaffold** for prototyping, grayboxing, generic NPCs,
environment foundations and VFX/UI prototypes — and are progressively replaced
where identity matters.

## Asset strategy

External assets are used **aggressively** early and **selectively** late:

| Use | Policy |
|---|---|
| Prototypes, graybox, generic NPCs and creatures, environment foundation, VFX/UI prototypes | Use external assets freely. Building bespoke art before mechanics are proven is wasted work. |
| Prime Beasts, key characters, signature locations, the game's visual identity | **Bespoke.** These carry the game's identity and cannot be outsourced to an asset pack. |

The failure mode to avoid is a game that looks like five unrelated asset packs
glued together. Coherence is enforced through shared materials and a small
shader library, unified lighting and colour grading, scale normalisation,
skeleton and animation consistency, and deliberate composition — not by
sourcing everything from one pack.

## Vetted sources

Verified as reliably licensed, to be re-checked per asset regardless:

| Source | Typical licence | Notes |
|---|---|---|
| [Kenney](https://kenney.nl) | CC0 | Prototyping, UI, audio. Unusually reliable. |
| [Quaternius](https://quaternius.com) | CC0 | Low-poly 3D, characters and environments. Strong silhouette fit. |
| KayKit (Kay Lousberg) | CC0 (verify per pack) | Stylised 3D kits. Some packs differ — check each. |
| [OpenGameArt](https://opengameart.org) | **Mixed** | Per-asset verification is mandatory. Licences vary wildly and re-uploads occur. |
| [Freesound](https://freesound.org) | Mixed (CC0 / CC-BY) | Per-asset. Filter to CC0 where possible. |
| [Google Fonts](https://fonts.google.com) | OFL / Apache | Reliable. |
| [Poly Haven](https://polyhaven.com) | CC0 | HDRIs, textures. |
| [ambientCG](https://ambientcg.com) | CC0 | PBR textures. |

---

## Asset register

**Current count: 1.**

| ID | Asset | Creator | Source | Licence | Acquired | Modifications | Attribution | Commercial |
|---|---|---|---|---|---|---|---|---|
| `quaternius-universal-animation-library` | Universal Animation Library (free tier) + bundled `Mannequin` rig | Quaternius (Tom Laulhet) | [itch.io](https://quaternius.itch.io/universal-animation-library) | **CC0-1.0** | 2026-09-27 | None. Retimed at runtime by seeking, never re-exported | Not required (credited anyway) | ✅ Yes |

**Verification:** CC0 confirmed on the creator's own itch.io page *and* in the
full `CC0 1.0 Universal` legal text bundled with the download, archived at
[`assets/licenses/quaternius_universal_animation_library_CC0.txt`](../assets/licenses/quaternius_universal_animation_library_CC0.txt).
Not taken from a search snippet.

**Obtained via** the CC0 mirror at `github.com/J-Ponzo/gltf-universal-animation-library`,
which CC0 expressly permits — redistribution is the licence's entire point. The
canonical source is the itch.io page above and is what the register cites.

### ⚠️ Known gap: no kick animations

The free tier is **46 animations and contains no kicks whatsoever**. Kick is
half this game's input language (`J`), so **9 of 16 attacks currently play a
placeholder**:

`low_kick`, `roundhouse`, `uppercut`, `axe_kick`, `sweep`, `spin_kick`,
`air_kick`, `dive_kick`, `dash_kick`

They are mapped to `Sword_Attack` — a large committed arm swing — so they read as
*some* deliberate motion rather than a frozen bind pose. Each is flagged
`anim_is_placeholder = true` in its resource, and the move-set bootstrap prints
the count on every run, so the gap stays **measured rather than half-remembered**.

Resolving it needs a set that actually contains kicks — the PRO tier of the same
CC0 pack (120+ animations including combat combos) is the obvious candidate, and
carries the same licence, so nothing about the commercial position changes.

The authoritative machine-readable record is
[`assets/licenses/assets.json`](../assets/licenses/assets.json), validated by
`tools/` so a malformed or incomplete entry is caught automatically rather than
at release.

---

## Attribution

Assets requiring attribution are credited in-game (settings → credits) and in
this file. The generated credits screen is built from `assets.json`, so an asset
cannot ship uncredited without also being absent from the register — the two
cannot drift apart.
