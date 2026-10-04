# Genshin Impact open world: public numbers for terrain-tool calibration

Researched 2026-10-02 using web search and individual page reads only. No datamined files, extracted-data repositories or leak articles were used. Interactive maps were not scraped.

**Access caveat:** genshin-impact.fandom.com returned HTTP 402 to the fetcher (archive and proxy mirrors were blocked too). So every Fandom figure below was read from search-engine snippets of the named page, not from the page itself. Those figures are rated **medium** even where the wiki is normally reliable. Spot-check them in a browser before relying on them.

Confidence key: **high** = primary or official source read directly; **medium** = reputable community wiki or snippet of one; **low** = content-farm article, unexplained method, or contradicted elsewhere.

---

## 1. Movement and stamina: published facts

### 1a. Stamina (absolute values)

| Item | Value | Confidence | Source |
|---|---|---|---|
| Base max stamina | 100 | medium | Fandom *Stamina* (snippet) https://genshin-impact.fandom.com/wiki/Stamina |
| Max stamina cap | 240 (Statue of the Seven upgrades: +7, +7, then +8 ×7 = +70 per statue; any regions' statues since v5.0) | medium | same, and https://genshin-impact.fandom.com/wiki/Stamina/Change_History |
| Regen rate | 25 stamina/s | medium | Fandom *Stamina* / *Sprinting* (snippet) |
| Regen delay | 1.5 s after the last stamina-using action | medium | same |
| Dash (each) | 18 | medium | https://genshin-impact.fandom.com/wiki/Sprinting (snippet) |
| Continuous sprint | 18 /s | medium | same |
| Alternate sprint (Ayaka/Mona-type) | 10 to start, then 15 /s | medium | https://genshin-impact.fandom.com/wiki/Alternate_Sprint (snippet) |
| Glide | 3 /s (0 inside a wind current) | medium | https://genshin-impact.fandom.com/wiki/Gliding (snippet) |
| Climb (continuous) | **not found.** The wiki itself says "exact stamina consumption for regular climbing is unknown". | n/a | Fandom *Climbing* (snippet) |
| Minimum stamina to start a climb | 5 | medium | Fandom *Climbing* (snippet) |
| Climb jump | 25 per jump | medium | Fandom *Stamina* / *Climbing* (snippet) |
| Swim (normal stroke) | 4 per stroke (per animation, not per second) | medium | Fandom *Stamina* / *Water* (snippet) |
| Swim dash (fast swim) | 2 to start, then 10.2 /s | medium | same |
| Treading water | 0 cost, and no regen | medium | same |
| Stamina-reduction passives | typically −20% (e.g. Kaeya sprint, Amber glide, Xiao/Candace climb, Beidou swim) | medium | Fandom character pages via snippets |

### 1b. Speeds, jump and plunge

| Item | Value | Confidence | Source |
|---|---|---|---|
| Walk / run / sprint / swim / climb speed in m/s | **not found.** No non-datamined public source gives absolute m/s values. The KQM library works in "distance per frame" with an unstated unit. | n/a | https://library.keqingmains.com/evidence/general-mechanics/movement-and-physics |
| Relative ground speeds (KQM) | run (not sprinting) 1.0582 d/f; b-hop 1.7036 d/f; dash-chaining 1.8116 d/f | high (as published) | KQM *Movement and Physics* (above) |
| Dash re-trigger window | 0.8 s (96 frames at 120 fps) | high | KQM (above) |
| Sprint distance by model type | Tall male > tall female ≈ medium male > medium female > short female. The stamina cost per second is the same for all. | medium | Fandom *Sprinting* / *Model Type* (snippet) |
| Jump distance by model type | Medium male covers the most distance per jump | medium | Fandom *Model Type* (snippet) |
| Jump height (m) | **not found.** The Fandom *Jumping* page has a table, but it could not be retrieved. | n/a | https://genshin-impact.fandom.com/wiki/Jumping |
| Glide horizontal speed and sink rate | **not found** (wiki gives only modifiers: Red Feather Fan +30% glide speed; Xianyun +15%; Movement SPD does not affect gliding) | medium (for the modifiers) | Fandom *Gliding* / *Movement SPD* (snippet) |
| Plunge: low/high threshold | Low Plunge at ≤ 2.4 m drop; High Plunge above 2.4 m. Plunge DMG ticks every 0.3 s in a 1 m radius while falling. | medium | https://genshin-impact.fandom.com/wiki/Plunging_Attack (snippet) |
| A normal flat-ground jump is too low to plunge | stated qualitatively | medium | same |
| Auto-plunge when falling more than 1.5 m | 1.5 m | low | cyberpost.co article (search snippet), unverified |
| Fall damage | scales with fall height and horizontal speed at impact; opening the glider resets it. The height where damage starts was **not found**. | medium | https://genshin-impact.fandom.com/wiki/Fall_DMG (snippet) |

## 2. Derived figures (my arithmetic, not published)

Stamina-limited durations, 240 max and no buffs:

| Action | Arithmetic | Result |
|---|---|---|
| Continuous sprint | 240 / 18 | **13.3 s** (100 base: 5.6 s) |
| Swim dash | (240 − 2) / 10.2 | **23.3 s** |
| Glide | 240 / 3 | **80 s** (100 base: 33 s) |
| Climb jumps | 240 / 25 | **9 full jumps** (9.6) |
| Full refill from empty | 1.5 + 240 / 25 | **11.1 s** |
| Dash-chain speed vs run | 1.8116 / 1.0582 | **≈1.71× run speed** |
| B-hop speed vs run | 1.7036 / 1.0582 | **≈1.61× run speed** |

**Maximum climbable cliff height:** this cannot be computed from public data, because both the climb drain rate and the climb speed are unpublished. To calibrate it in your own game:

`H_max = (S_max / c_climb) × v_climb`, or with climb jumps, `H_max ≈ floor(S_max / 25) × h_jump + residual`.

**Maximum glide distance from a drop h:** this cannot be computed either, because the glide speeds are unpublished.

`D = v_h × min(h / v_sink, S / 3)`

With 240 stamina the stamina limit is 80 s. So a drop only becomes stamina-bound when `h > 80 × v_sink`.

## 3. World scale

| Claim | Value | Confidence | Source / notes |
|---|---|---|---|
| GDC 2021, miHoYo Lead AI Programmer Shuo Xu, slide "Open-world Constraint" | "Large map **70+ km²**". The same talk gives NavMesh 128 tile size, 0.125 m voxel, ~6 GB of data (6.7 GB on the pathfinding server). | **high** (read from the official slide PDF) | https://media.gdcvault.com/GDC+2021/20210528_+GDC21_shuo_presentation+_Final.pdf. Version ≈ 1.x. Probably the NavMesh/world bounds including sea and out-of-bounds, not walkable land. |
| Producer Da Wei, pre-launch interview | "a **20–30 km²** map … only two of the seven" nations (Mondstadt + Liyue) | medium | Quoted on Fandom *Genshin Impact/Background* (snippet) https://genshin-impact.fandom.com/wiki/Genshin_Impact/Background |
| Liyue vs Mondstadt | Liyue area = **1.5 ×** Mondstadt; Liyue took one year from white-box to finished art | high | https://en.wikipedia.org/wiki/Locations_of_Genshin_Impact (dev statement) |
| Width of Teyvat, v5.x | "just over **15 km**" from western Natlan to Narukami Island, measured with the in-game quest-tracker distance readout (Reddit user FloorGang-R2) | medium (good method, single measurement) | https://gamerant.com/genshin-impact-teyvat-size-calculation/ |
| v1.0 launch | ~15 km² explorable, ~25 km² including out-of-bounds | low | expertbeacon / GameFAQs (search snippets; the pages returned 403) |
| v2.2 | "31 sq mi / 81 km²" with ocean, "54 sq mi" mainland | low (internally inconsistent) | https://win.gg/news/how-big-is-genshin-impacts-map-leaked-world-map-reveals-all/ ; https://qnnit.com/genshin-impact-map-size/ |
| v3.4 | ~9.8 km² overworld | low | snippet, attributed to expertbeacon |
| v4.0 | 604.7 km², assuming "1 px = 1 m" on a 25572 × 23647 px map | **low, likely wrong.** It conflicts with the 15 km tracker width. | https://theglobalgaming.com/genshin-impact/genshin-impact-map-size |
| Combined Mondstadt to Fontaine walkable area 1.5–2 km², and Mondstadt to Liyue under 2 km | n/a | low (content-farm; the "<2 km" claim could not be traced to a source) | https://hoyogameshop.com/blog/how-big-is-teyvat/ |
| Per-region km² for Inazuma, Sumeru, Fontaine and Natlan | **not found** in any credible non-leak source | n/a | Sportskeeda leak articles were excluded on purpose |
| Dragonspine height | ~427 m (fan calculation) | low | Fandom discussion post (title only, page blocked) |

**Comparison games:**

| Game | Size | Confidence | Source |
|---|---|---|---|
| Breath of the Wild | 62.1 km² (Guinness, measured from Link's height by "EngineeringHyrule") | high | https://www.guinnessworldrecords.com/world-records/512703-largest-nintendo-made-world |
| Breath of the Wild | 72 km² (also quoted widely) | medium | laps4 / various |
| Elden Ring | 24 km² total, ~12 km² playable (also quoted as 79 km²) | low | laps4 / gamepro snippets |

**My derivations on scale:**
- Mondstadt + Liyue = M + 1.5M = 2.5M.
  - Using Da Wei's 20–30 km²: **Mondstadt ≈ 8–12 km², Liyue ≈ 12–18 km²** (these likely include non-walkable terrain).
  - Using the low-confidence 15 km² explorable figure: Mondstadt ≈ 6 km², Liyue ≈ 9 km².
- 15 km continental width implies a bounding box of roughly 15 × 15 = 225 km² including ocean. The land fraction is unknown. This is consistent in order of magnitude with "70+ km²" in 2021, when only about two nations existed.

## 4. Density and spacing

### Published counts

| Item | Value | Confidence | Source |
|---|---|---|---|
| Waypoints added: v1.0 Mondstadt + Liyue | 61 | medium | https://genshin-impact.fandom.com/wiki/Teleport_Waypoint/Change_History (snippet) |
| Waypoints added: v1.2 Dragonspine | 11 | medium | same |
| Waypoints added: v2.0 Inazuma (first 3 islands) | 26 | medium | same |
| Waypoints added: Tsurumi | 7 | medium | same |
| Waypoints added: Enkanomiya | 24 | medium | same |
| Waypoints added: v3.0 Sumeru, Dharma Forest | 46 | medium | same |
| Waypoints added: v4.0 Fontaine | 39 (19 surface / 7 underground / 13 underwater) | medium | same |
| Waypoints added: Chenyu Vale | 29 | medium | same |
| Waypoints added: Windrest Peak | 11 (10 + 1 underground) | medium | same |
| Waypoints added: v5.0 Natlan | 45 (30 surface / 15 underground) | medium | same |
| Waypoints added: Snezhnaya, Nod-Krai | 48 each | low (identical figures look suspicious) | same |
| Total permanent waypoints | 362 → 460 → 768 (snippets from different revisions) | low (version unclear) | https://genshin-impact.fandom.com/wiki/Teleport_Waypoint |
| Oculi: Anemo (Mondstadt) | 65 overworld (+1 quest) | medium | https://genshin-impact.fandom.com/wiki/Oculus (snippet) |
| Oculi: Geo (Liyue) | 131 | medium | same |
| Oculi: Electro (Inazuma) | 181 | medium | same |
| Oculi: Dendro (Sumeru) | 271 | medium | same |
| Oculi: Hydro (Fontaine) | 271 | medium | same |
| Oculi: Pyro (Natlan) | 271 | medium | same |
| Chests (achievement counters, max known) | Mondstadt 746; Liyue 1152; Dragonspine 234; Inazuma 731; Enkanomiya 185; Chasm 248; Sumeru 1475; Fontaine 945; Chenyu Vale 333; Natlan 999; Nod-Krai 752 | medium | https://genshin-impact.fandom.com/wiki/Chest (snippet) |
| Sumeru chests by sub-area | Dharma Forest 575; Great Red Sand 354; Desert of Hadramaveth 290; Girdle of the Sands 256 | medium | same |
| Statues of the Seven (incl. sub-areas, May 2025) | Mondstadt 5 (incl. Dragonspine); Liyue 8 (incl. Chasm, Chenyu ×2); Inazuma 6 (one per island); Sumeru 13; Fontaine 8; Natlan 8 | medium-low | https://www.thegamer.com/genshin-impact-every-statue-seven-map-location/ |
| Typical distance between waypoints | **not found** stated anywhere | n/a | n/a |

### My density derivations (v1.0 Mondstadt + Liyue, the only slice with both a count and an area estimate)

Area A = 15 km² (low-confidence explorable estimate) to 30 km² (upper end of Da Wei's range).

| Metric | Arithmetic | Result |
|---|---|---|
| Waypoint density | 61 / 30 … 61 / 15 | **2.0–4.1 per km²** |
| Area per waypoint | 30 / 61 … 15 / 61 | 0.25–0.49 km² |
| Square-grid spacing | √0.25 … √0.49 | **≈ 0.50–0.70 km** |
| Hex-grid nearest-neighbour spacing | 1.075 × √A | **≈ 0.53–0.75 km** |
| Oculi, Mondstadt (65 over 6–12 km²) | 65 / 12 … 65 / 6 | **≈ 5.4–10.8 per km²**, about one every 300–430 m on a square grid |
| Oculi, Liyue (131 over 9–18 km²) | 131 / 18 … 131 / 9 | **≈ 7.3–14.6 per km²** |
| Chests, Mondstadt (746 over 6–12 km²) | 746 / 12 … 746 / 6 | **≈ 62–124 per km²**, about one every 90–130 m |
| Chests, Liyue (1152 over 9–18 km²) | 1152 / 18 … 1152 / 9 | **≈ 64–128 per km²** |
| Statues of the Seven in base Mondstadt/Liyue | about 3 each in v1.0 | roughly 1 per 3–6 km² |

Caveats:
- The chest totals include chests added after v1.0, so they are an upper bound for that area.
- Later regions roughly doubled oculi (131 → 181 → 271) and chests. Without area figures, I can't tell whether that means a larger area, higher density, or both.

## 5. Developer talks and statements

**GDC 2021: "Genshin Impact: Crafting an Anime Style Open World", Haoyu Cai (CEO/producer).** Slides: https://media.gdcvault.com/GDC+2021/2021GDC+_+Haoyu+Cai+_+presentation+file.pdf ; video: https://www.youtube.com/watch?v=-JFyAdI_rO8
- The slides contain almost no prose. Points visible on them:
  - Concept paintings are rebuilt faithfully in-engine, shown as a layered "concept → game" sequence of floating-cliff islands.
  - There is a **"Terrain Tint"** paint tool. Its UI has tinted-layer swatches and a brush with size, strength and falloff, plus random spacing and offset.
  - **"Grass-filling"**: dense grass covers terrain so that tint and grass carry the large-scale colour read.
  - Rocks use a hand-painted albedo plus a **"Blur Slope"** term, giving slope-aware stylised rock and cliff shading. It is shown on layered sedimentary cliffs.
  - Tree canopies use custom normals/shading for a painterly silhouette.
  - Clouds are built from painted shape, depth and rim-mask channels packed into one RGB texture.
  - Characters and scenes use **separate render pipelines**, and the environment is real-time lit.
  - "Seven regions, seven ideas, long-term plan, open world advantage."
- Exact spoken design rules were not available, because there is no transcript.

**GDC 2021: "Genshin Impact: Building a Scalable AI System", Shuo Xu (Lead AI Programmer).** Slides: https://media.gdcvault.com/GDC+2021/20210528_+GDC21_shuo_presentation+_Final.pdf
- The world is "70+ km²".
- **NavMesh:** tile size 128, voxel 0.125 m, about 6 GB. The NavMesh is server-side, so it costs 0 memory on the client and 6.7 GB on the pathfinding server. Pathfinding is a remote service that handles dynamic obstacles.
- **Mobile budget:** target 60 fps with 30+ simultaneous NPCs. AI originally took 2–3 ms per frame and was optimised to 0.5 ms on an Apple A12.
- **AI LOD:** 3 tiers chosen by player distance and combat state. LOD1 runs at 50% tick rate; LOD2 is paused (animations paused, skinned meshes hidden). Sensing runs at 30 Hz, threat at 5 Hz. There are 200+ AI archetypes.

**Interviews (via Wikipedia, *Locations of Genshin Impact*):**
- Liyue is 1.5× Mondstadt and took one year from white-box to finished art.
- Inazuma's scene design had two key points: (1) build the element (Electro) into exploration, terrain and ecosystem; (2) give **each island a clear theme**.
- Natlan was meant to emphasise **vertical movement** more than earlier regions.

**Producer Da Wei (pre-launch):**
- The world balances "grandness" (a 20–30 km² map with monsters, domains, puzzles and resources) with "fineness" (believability built up from small details).
- BotW was an acknowledged inspiration.

**Not found:** any CEDEC or Unite talk by miHoYo/HoYoverse on terrain or level pipeline with stated rules. A Chinese search turned up only third-party Zhihu/CSDN analyses. One of them describes a community "triangle rule": tall terrain that blocks the view pulls the player to climb over it. That is community analysis, not a developer statement.

## 6. Character heights (community-measured)

| Model type | Example (cm) | Confidence | Source |
|---|---|---|---|
| Tall male | Itto 186–191; Zhongli 186–187; Kaeya 186; Diluc 185 | low-medium | https://genshin.aza.gg/db/height?l=en ("model height" vs "physical height"; method undisclosed) |
| Tall female | Raiden 175–177; Beidou 173 | low-medium | same |
| Medium male | Aether 162–163; Kazuha 162–164 | low-medium | same; Sportskeeda's fan estimate of ~160–163 cm agrees |
| Medium female | Lumine 156–157; Ganyu 160–162 | low-medium | same |
| Short female | Klee 127; Nahida 128; Qiqi 140 | low-medium | same |

Summary bands: tall ≈ 1.73–1.91 m, medium ≈ 1.56–1.64 m, short ≈ 1.27–1.40 m. The fan-measured figures from forum posts ("compared against fixed world objects") agree within a few cm.

## Not found (summary)

- Absolute m/s for walk, run, sprint, swim and climb.
- Glide horizontal speed and sink rate, and therefore glide ratio.
- Jump height in metres.
- Climb stamina per second.
- Fall-damage onset height.
- Per-region km² for Inazuma through Natlan.
- Stated typical waypoint spacing.
- Any terrain or level-pipeline talk beyond GDC 2021.

To fill the movement gaps without datamining, the cleanest route is to measure them yourself in-game. Use the quest-tracker distance readout (in metres) with a stopwatch or frame-counted video. That is the same method behind the 15 km Teyvat width.
