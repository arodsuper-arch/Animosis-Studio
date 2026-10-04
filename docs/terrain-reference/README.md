# Terrain reference data

Measured numbers for calibrating the landform tool, prop scatter and world scale,
gathered without hand-sampling. Three sources, each with its own full report:

| Report | What it measured | How |
|---|---|---|
| [real-world-landforms.md](real-world-landforms.md) | Every landform kind in [landform.gd](../../projects/terrain-proto/addons/animosis_terrain/landform.gd), in metres and degrees | Copernicus GLO-30 elevation data, 13 sites, scripts in [tools/terrain-sampling/](../../tools/terrain-sampling/) |
| [scatter-rules.md](scatter-rules.md) | Rocks, boulders, trees, bushes, grass: sizes, spacing, slope limits | Geology and ecology literature, Horizon Zero Dawn GDC 2017 |
| [genshin-public-data.md](genshin-public-data.md) | Stamina, world size, waypoint/chest/oculus density, character heights | Wikis, KQM, GDC 2021 slides. No datamined files |

Every number in the reports carries a source and a confidence rating. This page
is the summary and the bits that connect them.

---

## The rule that ties it together

**Take shape from the real world. Take size from gameplay.**

Real landforms are far too big for a game world. Fuji is 30 km across; all of
Teyvat is about 15 km. Genshin, like every open world, compresses distance by
several times while keeping things *looking* natural. What survives compression
is proportion — slope, height-to-width, spacing-to-size, asymmetry — so those
are the numbers to copy. Absolute sizes come from what the player can traverse.

Scale-free ratios measured from real terrain:

| Ratio | Real value | Use |
|---|---|---|
| Mound height ÷ footprint | 0.14–0.22 (karst towers up to 0.4; true pillars ≥ 1) | mound steepness |
| Mound neighbour spacing ÷ footprint | 1.4–2.0 | mound scatter |
| Lone mountain height ÷ base width | 0.11–0.18 | mountain proportion |
| Mountain profile, height at half radius | 0.25 concave volcano → 0.5 cone → 0.78 dome | peak slider |
| Bluff lobe amplitude ÷ wavelength | ≈ 0.15–0.25 | lobes slider |
| Wall crest roughness ÷ height | 5–10 % (std) | roughness slider |
| Wall skew (side drop asymmetry) | 0.07 symmetric karst → 0.37 Dolomites → 0.59 fjord | skew slider |
| Basin depth ÷ width | 0.05–0.09 small hollows; 0.02 calderas | basin proportion |
| Dune height ÷ wavelength | 0.01–0.03 | dune proportion |
| Talus slope | 29–37° (steeper at top) | rock aprons |
| Dune slip face | ≈ 33° | dune clamp |

## Current landform defaults vs measured

Defaults are the `radius` / `height` in each `KINDS` entry of
[landform.gd](../../projects/terrain-proto/addons/animosis_terrain/landform.gd).
No code has been changed; these are recommendations.

| Kind | Default | Measured typical | Verdict |
|---|---|---|---|
| Mounds | 280 m across, 32 m high (H/D 0.11) | 120–350 m across, 20–150 m high, H/D 0.14–0.22 | Good. Sits at the kopje end; the steepness slider's top should reach near-vertical for Zhangjiajie-style pillars, which no 30 m DEM can resolve |
| Lone Mountain | 1240 m across, 300 m high (H/W 0.24, ~26° mean slope) | Uluru 1.9 km / 335 m; H/W 0.11–0.18, 12–20° mean | Steeper than nature — fine for stylised, but it is a choice. Real gullies are shallow (≈ 1–2 % of height on Fuji), so the gullies slider is already exaggerating, which is what it should do at this size. Ridges 3–12 covers Uluru (3–5) to Kata Tjuta (3–9); Fuji has 8–16 significant ones |
| Bluff | 55 m face | 150–400 m (DEM cannot see faces under ~100 m, so lower ones are real but unmeasured) | Good for a gameplay-scale bluff. Face slope should allow 80–90°; the DEM reads 45–70° only because it smooths walls |
| Border Wall | 360 m high | 250–450 m typical, up to 800 m | Good. Default skew 0.3 is close to the Dolomites' 0.37 |
| Basin | 640 m across, 45 m deep (0.07) | Depth/width 0.05–0.09 | Good. Floor 0.6 is flatter than any natural bowl (0.12–0.24) — reads as a filled lake bed, which matches the hint |
| Dunes | 20 m high | Superimposed dunes 710–800 m apart, 10–38 m high | Good. Normal 100–500 m dunes are below DEM resolution |

## Gameplay scale (Genshin, public data)

| Thing | Value | Confidence |
|---|---|---|
| Teyvat width | ~15 km | medium |
| Mondstadt / Liyue area | ~8–12 / ~12–18 km² (Liyue = 1.5× Mondstadt) | medium |
| One Animosis region (4096 m) | 16.8 km² ≈ a Liyue | — |
| Waypoint spacing | 0.5–0.75 km (2–4 per km²) | derived, medium |
| Oculi | 5–15 per km² (one every 300–430 m) | derived, medium |
| Chests | 60–130 per km² (one every 90–130 m) | derived, medium |
| Stamina | 240 max; sprint 18/s, glide 3/s, climb jump 25 | medium |
| On a full bar | 13 s sprint, 80 s glide, 9 climb jumps | derived |
| Character heights | tall ~1.8 m, medium ~1.6 m, short ~1.3 m | low-medium |

Scaled to one region, Genshin's density would be roughly 35–70 waypoints,
90–250 oculus-type collectibles and 1000–2200 chests. Treat that as an upper
bound — Genshin is unusually dense.

## Prop placement (short form)

Full rules R1–R8 with formulas are in [scatter-rules.md §6](scatter-rules.md).

- **Soil vs slope:** `soil = exp(-3·ln2·tan²(slope))` — half at 30°, ~0.13 at 45°. Multiply all vegetation density by it.
- **Bare rock** starts showing above ~30° mean slope.
- **Talus** collects on 29–37° slopes at cliff bases. Fallen boulders stop where the angle back to the cliff apex drops below ~27.5°.
- **Rock sizes:** Golombek exponential, `q = 1.79 + 0.152/k` for rock cover `k`. More cover → relatively more big rocks.
- **Footprints** (Horizon): conifers 6 m, bushes 3 m, grass clumps 1 m, as blue-noise radii. Undergrowth density = inverse of tree density.
- **Trees:** mature canopy near-random to slightly even (Clark–Evans R 1.05–1.3); young trees and treeline trees clump (R < 1). 50–870 stems/ha by forest type.
- **Water:** most streamside plants within 10–30 m. **Forest edge** effect 8–33 m deep.

## What still needs your own sampling

Nothing public covers these. All are quick in-game with a stopwatch:

| Measure | Why | How |
|---|---|---|
| Climb speed | Max climbable cliff height = stamina ÷ drain × speed | Time a full climb up a cliff, note stamina used |
| Glide speed and sink rate | Glide reach from a drop | Glide off a known height, time to land, distance on the map |
| Sprint speed in m/s | Converts every timed distance | Time a sprint between two map points |
| Rock/tree size vs character | Stylisation factor | Screenshots with a character beside props |
| Prop clustering at points of interest | Not in any literature | Count props within a radius of chests/camps |

## Licensing

Copernicus GLO-30 data is free to use; only derived statistics are kept here,
never the elevation data itself. If any DEM ever ships, it needs the attribution
"produced using Copernicus WorldDEM-30 © DLR e.V. 2010–2014 and © Airbus Defence
and Space GmbH 2014–2018 provided under COPERNICUS by the European Union and ESA".
Genshin numbers are facts gathered from public pages for calibration; no game
data or assets were used. See [licensing-policy.md](../licensing-policy.md).
