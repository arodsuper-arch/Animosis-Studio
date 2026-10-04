# Scatter rules: how rocks, boulders, trees, bushes and grass are distributed, with numbers

Research for procedural placement in the Animosis terrain tool. Every number below has a source URL.
Confidence: **H** = read in the primary source (paper or slides); **M** = abstract or secondary summary, or a single-site study; **L** = popular article or search snippet only, not verified in the primary source.
**GAP** marks places where no citable number was found. Rules in the last section that rest on a GAP say so as `[design default]`.

---

## 1. Rocks and boulders

### 1.1 Size-frequency distribution (SFD)

| Finding | Numbers | Conf | Source |
|---|---|---|---|
| **Exponential model of rock cover** (fitted at Viking, Pathfinder, Spirit, Phoenix and InSight landing sites, and stated to fit "a wide variety of rocky surfaces on Earth") | `F_k(D) = k · exp(-q(k)·D)`, where F = cumulative fractional **area** covered by rocks of diameter ≥ D (m), k = total rock-cover fraction, `q(k) = 1.79 + 0.152/k`. Typical k: 0.6 %–10 % on the plains studied; curves "flatten out at small rock diameter at a total rock abundance of 5–40 %" | H | Golombek et al. 2021, ESS — https://authors.library.caltech.edu/records/d1t32-akr32 ; original model Golombek & Rapp 1997 JGR 102:4117, https://doi.org/10.1029/96JE03319 |
| Power laws "invariably overestimate the number (or area) covered by large and small rocks" and need a bounded size range. Plotted as cumulative number, the exponential model looks nearly straight (power-law-like) over a limited range. | — | H | same (Golombek 2021) |
| Fragmentation power laws (Hartmann 1969). Cumulative number vs **mass**: `N(>m) = C·m^-b` | single blow: b ≈ 0.5–0.7. Cumulative number vs **diameter**: simple fragmentation exponent −2.1 to −2.4; hypervelocity impact −3.6 | M | Hartmann 1969, Icarus 10:201, https://sic.lpl.arizona.edu/sites/sic.lpl.arizona.edu/files/collection/journal/136_Hartmann_CommLPL_1969.pdf (cited in https://arxiv.org/pdf/2009.00957) |
| Rockfall **volume**-frequency on subvertical cliffs (event catalogues, not deposits) | cumulative exponent b = 0.5 ± 0.2 over 10²–10¹⁰ m³ (vs 1.2 ± 0.3 for mixed landslides); later work gives 0.3–1.0, lower for massive rock than bedded rock | M | Dussauge et al. 2003 JGR, https://www.isterre.fr/IMG/pdf/DussaugeJGR-2003.pdf ; https://egusphere.copernicus.org/preprints/2025/egusphere-2025-6247/egusphere-2025-6247.pdf |
| "Talus" boulder SFD of about −3.9 (+0.2/−0.4) below cliffs | **Measured on comet 67P, not Earth.** Use only as a shape hint: talus is rich in small blocks. | M | Pajola et al., https://arxiv.org/pdf/1512.03193 |
| Felsenmeer (periglacial boulder field, Hickory Run, PA; 5.7 ha, >500,000 surface boulders) | boulder **length is log-normal**, geometric mean 0.51 m (variance 0.08); aspect ratio L/W log-normal, geometric mean 1.95; smaller clasts are rounder | M | GSA abstract, https://gsa.confex.com/gsa/2010AM/webprogram/Paper178867.html |
| Talus block volumes depend heavily on lithology (LiDAR, blocks > 0.5 m) | median block volume: gneiss 0.08 m³, dolomite 1.63 m³, basalt 3.38 m³, banked limestone 13.16 m³; max 2,029 m³ (dolomite) and 5,784 m³ (limestone) | H | Wegner et al. 2021 NHESS, https://nhess.copernicus.org/articles/21/1159/2021/ |
| Block shape (axial ratio a/c) | median 1.73 (basalt), 2.33–2.40 (limestone/dolomite), 2.63 (platy gneiss) | H | same |

**Takeaway for implementation.** Sample boulder diameters from a bounded distribution: either the Golombek exponential (area-based, with one knob, k) or a log-normal. Do not use an unbounded power law. Use lithology to set median size and axial ratio.

### 1.2 Where rocks accumulate

| Finding | Numbers | Conf | Source |
|---|---|---|---|
| Angle of repose of dry granular debris | 33–37° | M | https://en.wikipedia.org/wiki/Angle_of_repose |
| Talus profile is concave: steep upper slope, gentler lower slope | upper 35–37° → lower 31–34°; a break at about 33–34° separates the proximal and distal segments | M | https://en.wikipedia.org/wiki/Scree ; https://geoguide.scottishgeologytrust.org/page/2138 |
| Measured mean talus-cone inclination at 4 sites | 29°, 32°, 32°, 36° | H | Wegner et al. 2021 |
| **Fall sorting** (big blocks at the distal foot, small near the apex) is the classic model (Statham 1973; Kirkby & Statham 1975; Jomelli & Francou 2000; Sanders 2009; Messenzehl & Dikau 2017). Serrano 2019: the distal part of a slope is defined by an accumulation of large blocks. | qualitative | H | literature review in Wegner et al. 2021 (preprint https://nhess.copernicus.org/preprints/nhess-2020-322/nhess-2020-322.pdf) |
| **But** Wegner et al. found **no clear block-size/runout correlation** at 4 sites. Sphericity mattered more: rounder blocks roll farther (at 2 of 4 sites). Messenzehl & Dikau found size **and** sphericity both increase downslope. | weak Spearman correlations | H | same |
| Maximum runout past the talus foot: **minimum shadow angle**, i.e. the angle from the talus apex to the farthest boulder (Evans & Hungr 1993) | usually ≥ 27°. Reach classes for rockfalls < 1000 m³: very high > 33°, high 32–33°, medium 30–32°, low 27.5–30°, very low 25.5–27.5° | M | https://grass.osgeo.org/grass84/manuals/addons/r.droka.html ; USGS Yosemite https://pubs.usgs.gov/of/1998/ofr-98-0467 |
| Rock exposure vs slope (San Gabriel Mts, 1 m LiDAR) | catchment-mean slope < 30°: little bedrock exposure. > 30°: rock exposure "increases strongly"; debris wedges at angle of repose hold modal slopes near **37°** | H | DiBiase et al. 2012 ESPL, abstract at https://authors.library.caltech.edu/records/xtr9y-at332 |
| Threshold hillslopes worldwide | modal slopes 30 ± 5° (SE Tibet: 82 % of slopes; also Olympic Mts, Southern Alps, E. Himalaya); globally modal steep slopes cluster at 35–40° | H/M | https://www.frontiersin.org/journals/earth-science/articles/10.3389/feart.2021.684365/full ; https://serc.carleton.edu/vignettes/collection/37906.html |
| Surface rock cover vs slope (Bitterroot Mts, MT) | rock cover roughly doubles from **40 % to 80 %** as hillslope angle goes from about **24° to 42°**. Soil cover: forested 94.4 ± 2.6 % vs non-forested 88.3 ± 1.9 % (local plots) | L (search snippet; the repository page timed out) | https://scholarworks.montana.edu/items/1a73be37-a209-4fc7-93ed-02b35c1662af |

### 1.3 Clustering, burial, orientation

| Finding | Numbers | Conf | Source |
|---|---|---|---|
| Felsenmeer boulders are **not random** (p < 0.0001): clusters spaced **3–7 m** apart, linear trends | — | M | https://gsa.confex.com/gsa/2010AM/webprogram/Paper178867.html |
| Glacial erratics: clusters of the same lithology; one regional density figure of **about 300 erratics/km² (≈3/ha)** | — | L (snippet, Polish Tri-City study; not verified) | https://geojournals.pgi.gov.pl/pg/article/view/27560 |
| Moraine boulders: spatial distribution "effectively random" (no preference for crest, ice-proximal or distal slope) | — | M | https://scholars.uky.edu/en/publications/moraine-crest-or-slope-an-analysis-of-the-effects-of-boulder-posi/ |
| Erratics, NY (700 km²): no map pattern by size; larger erratics (0.5–1 m) more common in high tributaries | — | M | https://gsa.confex.com/gsa/2006NE/webprogram/Paper100913.html |
| **Burial / protrusion.** Hillslope boulders protrude about 0.5–1 m in Chilean granite. Protrusion height **increases with slope** (significant linear relation at La Campana). Boulder widths 0–5 m; joint spacing 2–15 m. | no general embedded-fraction statistic | M | Lodes et al. 2023 ESurf, https://esurf.copernicus.org/articles/11/305/2023/ |
| **GAP:** no citable "fraction of boulder volume buried" distribution was found. | — | — | — |
| **Orientation on talus.** Most blocks are aligned in the downslope direction (long axis roughly parallel to slope, dipping downslope). Upper talus: long axes parallel to the slope (sliding). Base: more isotropic (rockfall impact). | qualitative | M | https://www.erudit.org/en/revue/gpq/1999/v53/n1/004881ar.pdf ; https://deepblue.lib.umich.edu/bitstream/2027.42/25798/1/0000360.pdf |
| Felsenmeer preferred orientation | 58°/238° (site-specific, aligned with linear features) | M | Hickory Run abstract above |

---

## 2. Vegetation

### 2.1 Spacing and pattern (Clark–Evans R)

R = observed mean nearest-neighbour distance ÷ the value expected for a random pattern, `0.5/sqrt(λ)` (λ = trees per m²). R < 1 is clumped, R = 1 is random (Poisson), R > 1 is regular; the maximum is 2.149 for a hexagonal lattice.

| Finding | Numbers | Conf | Source |
|---|---|---|---|
| Mature pedunculate oak stands | R = 0.89–1.28 (all trees); 1.02–1.51 (oaks only) | M | https://seefor.eu/vol-4-no-1-krunoslav-indir-et-al-spatial-structure-indices-of-mature-pedunculate-oak-stands-in-nw-croatia.html |
| Growing-up stage | mean R = 0.96 | M | https://portal.fis.tum.de/en/publications/quantitative-analysis-of-forest-structure-at-growing-up-volume-st/ |
| Natural juniper forest | mean R = 1.05 | M | https://doaj.org/article/539c1d6074494fbebad7059e1bea1782 |
| Old-growth beech (Krkonoše). Low-altitude stand (740 m): moderately regular, and regular at < 4 m. Codominant/dominant trees R = **1.102**; suppressed lower storey R = **0.945** (aggregated). **Regeneration is distinctly aggregated** (recruits cluster in canopy gaps). **Near the timberline (1030 m) trees grow in "biogroups"**, aggregated at 4 m and again from 8 m. Aggregation increases with altitude and with tree count. Crowns are more regular than stems. Snags are random. | densities: 236 trees/ha (mature two-storey), 716 trees/ha (disintegrating stand with regeneration) | H | Vacek et al. 2015, Dendrobiology 73:33, https://www.idpan.poznan.pl/images/stories/dendrobiology/vol73/denbio.073.004.pdf |
| General rule (forestry): juvenile/natural regeneration is mostly clustered; established tree layer is random to moderately regular | — | M | https://jfs.agriculturejournals.cz/pdfs/jfs/2010/11/04.pdf |
| Fire-frequent pine and mixed conifer (review of 50 studies): mosaic of **openings, single trees, and clumps** with interlocking crowns, usually at scales < 0.4 ha (up to 4 ha) | — | M | Larson & Churchill 2012, https://mountainscholar.org/handle/10217/235722 |
| Historical ponderosa/dry mixed conifer (Blue Mts) | 53–197 trees/ha (> 15 cm DBH); basal area 11–24 m²/ha; isolated trees (no neighbour within **6 m**) 10–53 %; large clumps 10–30 trees; **openings 15–72 % of area, 18–45 m across**, sinuous/linear | H (abstract) | https://research.fs.usda.gov/treesearch/55418 |

### 2.2 Density by forest type

| Forest | Stems/ha | Conf | Source |
|---|---|---|---|
| Tropical (DBH ≥ 10 cm) | mean about 530 (Pasoh, Malaysia); plots 281–874 | M | https://pmc.ncbi.nlm.nih.gov/articles/PMC6647473/table/Tab2 ; https://jtfs.frim.gov.my/jtfs/article/download/2027/1727/2215 |
| Temperate old-growth, SE Europe (DBH ≥ 10 cm) | 261–338 | M | (search summary of old-growth stand tables; see Lund link below) |
| Temperate/boreal old-growth, large trees | 10–20/ha with DBH > 70 cm (central Europe); ≥ 20/ha with DBH > 40 cm (boreal) | M | https://lup.lub.lu.se/record/145587 |
| Old-growth beech | 236 (mature) to 716 (mixed with young) | H | Vacek 2015 above |
| Open dry pine (historical) | 53–197 (> 15 cm DBH) | H | treesearch 55418 |

Spacing conversion: mean spacing ≈ `sqrt(10000/N)` m. 100/ha ≈ 10 m, 300/ha ≈ 5.8 m, 700/ha ≈ 3.8 m. Random nearest-neighbour expectation is `0.5·sqrt(10000/N)`.

### 2.3 Altitude, treeline, edges, water

| Finding | Numbers | Conf | Source |
|---|---|---|---|
| Climatic treeline sits at a growing-season mean **soil** temperature (10 cm) of **6.7 °C ± 0.8** (46 sites, 68°N–42°S). Later refinements give about 6.4 °C. | — | M | Körner & Paulsen 2004, https://edoc.unibas.ch/8594 |
| Treeline forms: **diffuse** (gradual drop in height and density), **abrupt**, **island** (clustered patches), **krummholz** (stunted). Measured as height change in 5 m bands and a logistic fit to tree cover. | logistic transition | M | Bader et al. 2021 framework, https://www.utupub.fi/handle/11111/42983 ; https://diposit.ub.edu/dspace/bitstream/2445/220960/1/893460.pdf |
| **Nurse rocks.** On harsh S-facing slopes in Glacier NP, **63 %** of trees and bushes > 0.5 m grew beside boulders. Rocks lengthen the snow-free season and shelter seedlings; the effect is strongest at forest edges and treeline. | — | L (popular) | https://www.montananaturalist.org/?p=70150 ; facilitation at treeline: https://bioone.org/journals/arctic-antarctic-and-alpine-research/volume-48/issue-2/AAAR0015-055 |
| Forest edge influence depth (microclimate/abiotic) | 8.2–33 m in one study; open edges show 2–5× deeper penetration than closed edges | M | Harper et al. 2005 concept; https://link.springer.com/article/10.1186/s41610-017-0051-2 ; https://repositorio.inpa.gov.br/items/c900e5c5-ae0d-49b2-a2a5-70e8d6042d91/full |
| Riparian zone | a few-metre band is fully distinct; 10–30 m captures 90 % of riparian plant species; valley-scale influence up to about 100 m. Riparian tree density per metre of channel **drops with channel gradient and curvature** and is higher on inside bends. | M | https://friresearch.ca/data/null/FWP_2002_11_Qknte1_HowWideisaRiparianArea.pdf ; https://www.cambridge.org/core/journals/journal-of-tropical-ecology/article/how-wide-is-the-riparian-zone-of-small-streams-in-tropical-forests-a-test-with-terrestrial-herbs/F747BDF5496852BD27308BE10F0BF4B2 |
| Topography vs vegetation: TWI and aspect explained about 78 % of NDVI vs 17 % for slope and elevation (one region). Conifers favour steep slopes; broadleaf rises with TWI and falls with solar radiation. Tree cover is often highest on slopes (partly from land-use). | — | L/M | https://eco.confex.com/eco/2012/webprogram/Paper37129.html ; search summaries |
| Far Cry 5 art-direction observations (Montana): grasslands on exposed hills, ponderosa forests in valleys, **thicker forest on north-facing slopes** (moister) | qualitative | M | https://blog.playstation.com/2018/03/22/the-procedural-world-generation-of-far-cry-5/ |
| Understory vs canopy: only weak correlation between overhead canopy cover and understory cover (r = 0.22–0.35, aspen); multi-variable models reach R² ≈ 0.79 | — | M | https://era.library.ualberta.ca/items/cc92bd5c-8b36-4e71-94c1-dc657b80334b/download/7c7cd95e-1780-42b5-af0d-975c8fa5f1c4 |
| Canopy cover definition of "forest" (FAO FRA) | > 10 % canopy cover, trees > 5 m, area > 0.5 ha | M (standard definition, not fetched) | FAO FRA terms and definitions |
| **GAP:** no citable shrub-per-hectare or grass-cover-by-slope numbers. | — | — | — |

---

## 3. Terrain-driven rules (soil, rock, wetness)

| Rule | Numbers | Conf | Source |
|---|---|---|---|
| **Initial soil/humus thickness vs slope** (graphics paper validated against real terrain): `H(s) = exp(-α·s²)` with s = gradient (rise/run) and **α = 3·ln 2**, so H(tan 30°) = ½. Function reconstructed from a garbled PDF extraction; the constants and φ(tan 30°) = ½ were read directly. | half soil at 30°, about 0.13 at 45° | H | Cordonnier et al. 2017 TOG, https://cs.purdue.edu/homes/bbenes/papers/Cordonnier17ToG.pdf |
| Same paper: plant viability = **min** over (temperature, moisture, sunlight) suitability. Self-thinning when canopy density d > 1. Shrubs shaded in proportion to tree density. Woody establishment rate **0.24 saplings/m²** (Prentice 1993). Rockfalls destroy vegetation. Vegetation raises the friction angle (stabilises slopes). Hilltops are drier and carry less cover. | — | H | same |
| Bedrock exposure begins above about 30° mean slope; repose debris at about 37° | see 1.2 | H | DiBiase 2012 |
| Rock-cover doubling 40 %→80 % between 24° and 42° | see 1.2 | L | Bitterroot |
| Topographic Wetness Index (standard, Beven & Kirkby 1979): `TWI = ln(a / tan β)`, where a = upslope contributing area per unit contour width and β = slope | formula | H (standard) | https://passer.garmian.edu.krd/article_192393.html (usage) |

---

## 4. Game-dev practice

### 4.1 Horizon Zero Dawn: GPU procedural placement (van Muijden, GDC 2017). Read from slides, **H**
Source: https://www.guerrilla-games.com/media/News/Files/GDC2017_VanMuijden_GPUBasedProceduralPlacementInHorizonZeroDawn.pdf

- All nature is placed procedurally: 500+ asset types, 100,000+ objects in scene, about 250 µs average GPU load. Nature assets were made by 3 people and ecotopes by 1.
- **Ecotope** (biome recipe) sets the asset types, distribution, colourisation, weather, effects, sound and wildlife.
- **WorldData** is a set of 2D maps, all generated and all paintable, about 4 MB/km²:
  - Height_Terrain, Height_Objects and Height_Water at 0.5 m
  - Erosion_Wear, Erosion_Flow, Erosion_Deposition, Terrain_Cavity, Water_Flow and Water_Vorticity at 0.5 m
  - Topo_Roads, Topo_Water and Topo_Objects at 0.5 m, i.e. **generated distance/mask maps to roads, water and placed objects**
  - Placement_Trees, Placement_BlockBush, Placement_Undergrowth and Placement_StealthPlants at 1.0 m
  - Variance_* maps at 1–2 m, plus Ecotopes A–H at 2.0 m
- A painted Placement_Trees value is **decoded through curves** into layers: low values give "Sparse trees", mid values give "Forest Edge", high values give "Inner Forest". Undergrowth uses the **inverse** of tree density ("Clearing undergrowth").
- Density logic graph: Placement_Trees is combined with Topo_Roads, Topo_Water and Topo_Objects into the final density map.
- **Footprints** listed per asset (metres): Lodgepole Pine **6.0**, Douglas Fir **6.0**, Greasewood (bush) **3.0**, Carex grass **1.0**, Payson's sedge **1.0**, fern **1.0**.
- Pipeline: density map → **dither-based discretisation** using a precomputed point pattern. Pattern rules: even spread of thresholds, maximise 2D distance, uniform 2D distance w, **pattern scaled so w = footprint**. Then placement (normal, basis, bounding box).
- Collision between layers: if footprints are the same, use **layered dithering** (two-sided threshold test on stacked density, so layers partition the same pattern and never overlap). If footprints differ, read back with dependencies (costly), using ordering heuristics.

### 4.2 Far Cry 5 (Carrier, GDC 2018; Houdini)
https://blog.playstation.com/2018/03/22/the-procedural-world-generation-of-far-cry-5/ , https://gdcvault.com/play/1025557/ (**M**). Tools covered biomes, terrain texturing, freshwater networks and cliff rocks, with biome "recipes" reacting to terrain features and layered biome maps. Rules quoted: grasslands on exposed hills, forests in valleys, denser forest on north slopes, wind vector map orienting grass, terrain humidity map. **GAP:** the numeric thresholds are in the Vault video only.

### 4.3 Ghost of Tsushima grass (Wohllaib, GDC 2021)
https://gdcvault.com/play/1027214/ (**L** for numbers). Individual GPU-generated blades. Inputs: grass type map, height map, ground texture. **Voronoi clumping** gives a shared facing, height and colour per clump. Distant LOD uses blades twice as wide and half as many. Snippet numbers (unverified): 512×512 render tile; about 1 M blades generated and 83 k drawn at 2.5 ms on PS4.

### 4.4 The Witcher 3 (Gollent, GDC 2014, REDengine 3)
https://www.gdcvault.com/play/1020394/ (**M/L**). Vegetation coverage can be generated offline or in real time. Reported practice: base foliage layer generated from terrain texture type; trees, bushes and flowers largely **hand-placed**. About 20 tree/bush species, 40 grass varieties (SpeedTree, https://store.speedtree.com/?p=2530).

### 4.5 BotW / TotK, Genshin
"Change and Constant" (GDC 2017, https://gdcvault.com/play/1024562/) covers design and systems. **GAP:** no public placement or density numbers were found for BotW, TotK or Genshin.

### 4.6 Generic tools and algorithms
- **Bridson 2007** Poisson disk sampling: minimum distance r, k = 30 candidates per active point, background grid cell r/√n, O(N). https://www.cs.ubc.ca/~rbridson/docs/bridson-siggraph07-poissondisk.pdf (**H**)
- Lagae & Dutré 2008 compare Poisson-disk generators: https://diglib.eg.org/items/19b32179-fc46-4efd-9aea-5794320cac13 . Density from r: a hexagonal lattice at spacing r has `2/(√3·r²) ≈ 1.155/r²` points. A maximal random Poisson-disk set reaches only part of that. **GAP:** exact fraction not verified; measure it in your own sampler.
- **Unreal Procedural Foliage Spawner**: per-type **CollisionRadius** (instances overlap → competition), **ShadeRadius** (ignored if the species can grow in shade), Num Steps (ageing and seeding iterations), Initial Seed Density (seeds per 10 m, squared over 10×10 m). https://dev.epicgames.com/documentation/unreal-engine/open-world-tools-property-reference-in-unreal-engine (**H**). This is the Deussen et al. 1998 competition model: https://algorithmicbotany.org/papers/ecosys.sig98.html
- **Exclusion radii between classes** (e.g. "no tree within X m of a boulder"): **GAP.** No published game value found. HZD handles it through footprints and density subtraction via Topo_Objects. Nature argues the opposite near treeline (nurse rocks attract trees).

---

## 5. Scale for a stylised world
- Level-design lore holds that real-life scale feels claustrophobic, so worlds are scaled up (doors taller and wider than real). Source is a forum discussion, **L**: https://polycount.com/discussion/comment/1064400 . Pearl Abyss (Crimson Desert) judges scale from eye-level player view, not a drone camera: https://www.invenglobal.com/articles/25076/ (**L**).
- **GAP:** no published scale factor for rocks or trees in BotW, Genshin, HZD and similar games. Treat any factor (e.g. 1.2–1.5×) as an art decision to playtest, not a sourced fact.

---

## 6. Recommended placement rules (implementable)

Inputs per sample point: `slope` (degrees; `g = tan(slope)`), `h` (height), `dCliff` (horizontal distance from the talus apex or cliff base, m), `Hc` (cliff height above apex, m), `wet` (normalised TWI or flow accumulation, 0–1), `dWater` (m), `landform` ∈ {cliff, talus, hillslope, valley floor, ridge, riparian, moraine/erratic field}, `aspect`, `treeline` height `hT`.

### R1. Ground cover (soil vs rock), all classes
```
soil  = exp(-3*ln2 * g*g)                 // Cordonnier 2017: 1 at 0°, 0.5 at 30°, ~0.13 at 45°
rockExposure = smoothstep(30°, 42°, slope) // DiBiase: exposure starts at ~30°; Bitterroot: 40→80% cover at 24–42° [L]
vegCap = soil * (1 - rockExposure)        // multiply every vegetation density by this
```

### R2. Talus aprons and boulders below cliffs
- Talus zone: cells below a cliff where slope is 29–37° (H). The apron surface should itself relax to 31–37°, concave, with the steeper part on top.
- Rock **outer runout limit**: place a rock only if `atan(Hc_apex / dCliff) ≥ 27.5°` (shadow-angle "low reach" class). Allow a rare tail to 25.5° (very-low class). Beyond that, no rockfall boulders.
- Size by position. Let `t = dCliff / runoutMax` in [0,1]. Classic fall sorting: `medianSize(t) = lerp(0.5, 2.0, t) × lithologyMedian` `[design default; direction H, magnitude GAP]`. Wegner 2021 shows the trend is weak and noisy, so use **at least ±1σ log-normal jitter** and bias **rounder blocks (axial ratio < 1.8) to larger t**, angular/platy ones near the apex.
- Size sampling: log-normal (felsenmeer geometric mean 0.51 m, aspect ratio about 1.95), or the Golombek exponential with cover k (0.05–0.40 on talus/boulder fields, 0.006–0.10 on rocky plains). Lithology presets for median volume: gneiss 0.08 m³ (platy, a/c ≈ 2.6), dolomite 1.6 m³, basalt 3.4 m³ (a/c ≈ 1.7), massive limestone 13 m³ (a/c ≈ 2.4).
- Orientation on slopes > 25°: long axis aligned to the downslope vector ±25° on the upper talus (sliding), rotation randomised near the toe `[jitter angles: design default]`. Dip roughly with the slope.
- Burial: `embedFrac` is **GAP**. Suggested default `[design default]`: hillslope boulders 20–40 % of height buried, with deeper burial on gentle slopes, because Lodes 2023 found protrusion **increases** with slope. Fresh talus blocks are 0–15 % buried, resting on other blocks.

### R3. Boulders on open hillslopes and fields
- Clustered, not Poisson. Use a two-level process: cluster centres (Poisson disk, spacing about 3–7 m in felsenmeer, H/M) with child rocks around them, plus a sparse random background `[background ratio: design default]`.
- Moraine/erratic fields: near-random placement; regional erratic density on the order of 1–3 per ha `[L]`. Group erratics by lithology (shared mesh/material per cluster).
- Rock cover fraction k from R1 `rockExposure`, then sizes from the Golombek `q(k) = 1.79 + 0.152/k`. **Larger k automatically yields relatively more large rocks.**

### R4. Trees
```
treeDensity = baseDensity(ecotope)        // stems/ha: dry pine 50–200, temperate 250–350 (DBH≥10cm), mature beech ~240,
                                          // tropical 280–870 (DBH≥10cm)
            * vegCap                      // R1
            * treelineFactor(h)           // logistic: 1 below hT-Δ, 0 above hT; Δ ≈ ecotone width [GAP: width]
            * moisture(wet, aspect)       // more on wetter / poleward-facing slopes (FC5, TWI studies) [shape: design default]
            * (1 - roadMask)(1 - objectMask)  // HZD Topo_* maps
```
- **Pattern by stratum** (Vacek 2015, H): canopy trees use Poisson disk with r ≈ 0.8–1.0 × crown radius, giving Clark–Evans R ≈ 1.05–1.3 (validate by computing R). Sub-canopy, saplings and regeneration use a **clustered** process (R ≈ 0.9) **inside canopy gaps**. Snags are random.
- Dry, open forest (Larson & Churchill; Blue Mts): mosaic of singles (10–50 % of trees with no neighbour within 6 m), clumps of 2–30 trees, and sinuous **openings 18–45 m across covering 15–70 %** of area.
- **Treeline**: the density falloff is a logistic function. Switch from regular to **clumped "biogroups"** (aggregation at about 4 m and 8 m), shrink height (krummholz), and **attract trees to boulders** (nurse-rock bias, e.g. a placement-probability multiplier near rocks; the 63 % beside-boulder figure is L).
- **Edge band**: HZD-style decode of a single density value into Sparse → Edge → Inner layers. Edge-effect depth for microclimate (and so for edge shrubs and lighter understory) is about 8–33 m, deeper on open (meadow) edges.
- Footprints (HZD): conifers **6 m**. Use as Poisson radius and as the dither-pattern scale.

### R5. Bushes and undergrowth
- Footprint about **3 m** (HZD Greasewood).
- Density driven by the **inverse** of tree density, as in HZD "Clearing undergrowth" (strong in openings and forest edge, weaker under closed canopy); Cordonnier shades shrubs in proportion to tree density.
- Riparian boost when `dWater < 10–30 m` (90 % of riparian plant species within this band); the strongest distinct band is the first few metres. Reduce riparian density on steep or highly curved channel reaches.

### R6. Grass and ground cover
- Footprint about **1 m** for clumps (HZD Carex/sedge/fern). Blade-level grass uses Voronoi clumps for shared facing, height and colour (GoT).
- `grassDensity = vegCap * (1 - 0.x * canopy)`. The shading coefficient is **GAP**; the literature correlation is weak (r 0.22–0.35), so keep it mild.
- Exposed hills and ridges favour grassland over forest (FC5). Hilltops are drier (Cordonnier).

### R7. Inter-class exclusion (implementation)
- Use HZD's approach. Each class has a footprint. Layers with the same footprint share one dither pattern via **layered (stacked) density thresholds**, so no overlap is possible. Classes with different footprints get processed big-to-small (boulders → trees → bushes → grass), and each placed object stamps a mask (Topo_Objects) into the density of later layers.
- Suggested stamp radius `[design default; GAP in literature]`: `rStamp = max(footprint_a, footprint_b)/2 + objectRadius`. **Exception:** near the treeline or in harsh exposures, apply a positive (attract) term around boulders instead of exclusion.

### R8. Verification metrics to compute in the tool
- Clark–Evans R per class: target > 1 for canopy trees, < 1 for regeneration and treeline groups.
- Rock cumulative fractional area vs D: check it follows `k·exp(-qD)`.
- Rock count vs slope: near zero on slopes < 20° away from cliffs; peak on 29–37° aprons below cliffs.

---

### Main gaps
1. Embedded fraction of boulders. Only the qualitative trend (protrusion increases with slope) is sourced.
2. Exclusion radii between object classes in shipped games.
3. Treeline ecotone width in metres.
4. Shrub density per ha by forest type; grass vs canopy shading coefficient.
5. Published scale-exaggeration factors for stylised games.
6. Far Cry 5, Witcher 3 and GoT numeric thresholds (behind the GDC Vault login).
