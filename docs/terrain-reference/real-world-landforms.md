# Real-world landform measurements for terrain-tool parameter ranges

Data: **Copernicus GLO-30 DEM** (30 m, float32 COG, EGM2008 heights), from the public AWS bucket
`https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_{N|S}lat_00_{E|W}lon_00_DEM/...tif`.
The naming scheme in the brief works as given: all 15 tiles returned HTTP 200 (lat/lon in the name = the tile's lower-left corner), so no fallback was needed.
Above 50° latitude the longitude spacing widens (Geiranger, 62°N, uses 2"), so pixel size is read from each tile's GeoTIFF tags.
Metres: `dx = dlon * 111320 * cos(lat_centre)`, `dy = dlat * 110574`. Pixel sizes per site are listed below (21–30 m × 30.7 m).

Scripts, cached tiles (533 MB), JSON outputs and hillshade previews are in [tools/terrain-sampling/](../../tools/terrain-sampling/) (tiles and previews are regenerated, not committed) (see the last section).

> **Read this first: resolution limits.**
> * GLO-30 is a **DSM**: it includes forest canopy and buildings, which adds roughly 5–30 m in vegetated sites (Bohol, Guilin, Zhangjiajie, Aso).
> * At 30 m posting, anything narrower than about 3 pixels (about 90 m) cannot be measured. **The Zhangjiajie sandstone pillars are tens of metres wide, so this DEM does not resolve them.** What it does resolve at Wulingyuan is the dissected plateau and its pillar *clusters* or blocks. UNESCO describes "over 3,000 narrow sandstone pillars and peaks, many over 200 m high"; treat that as the real pillar scale and use the DEM numbers for cluster and massif scale only.
> * Slopes are taken over 30–60 m baselines, so vertical walls show up as **55–75° at most**. Real cliff faces in Geiranger, the Dolomites, Uluru and the Guilin towers are locally 70–90°. Dune slip faces (about 32–34° in reality) come out at ≤ 29°.
> * A 40° face must be at least 3–4 px wide to be detected, so the automatic bluff extraction **misses faces lower than about 100 m**. The low end of the bluff-height ranges is a detection floor, not a property of nature.
> * Dunes with crest spacing under about 150 m (5 px per cycle) cannot be measured. Only draa and megadunes are captured.
> * "p10 / p50 / p90" are percentiles over all detected features at a site. "Max" is the largest single feature.

## Sites

| key | bbox (lat, lon) | landform illustrated |
|---|---|---|
| zhangjiajie | 29.30–29.40N, 110.38–110.55E | Mounds: sandstone pillar field (Wulingyuan), cluster/massif scale only |
| yangshuo | 24.70–24.92N, 110.35–110.60E | Mounds: Guilin/Yangshuo karst towers (fenglin on plains + fengcong clusters) |
| chocolate | 9.78–9.92N, 124.06–124.20E | Mounds: Chocolate Hills cone karst, Bohol (classic mound field) |
| kata_tjuta | 25.25–25.35S, 130.68–130.79E | Mounds (large): conglomerate dome cluster; also a Lone Mountain variant |
| fuji | 35.15–35.57N, 138.50–138.98E | Lone Mountain: stratovolcano |
| uluru | 25.29–25.40S, 130.97–131.10E | Lone Mountain / Bluff: inselberg |
| geiranger | 62.05–62.15N, 7.00–7.25E | Bluff / Border Wall: fjord walls |
| dolomites | 46.45–46.66N, 11.65–11.95E | Border Wall / Bluff: Sella, Sassolungo, Odle, Puez |
| aso | 32.76–33.04N, 130.94–131.22E | Basin: caldera (4 tiles) |
| liwa | 23.00–23.30N, 53.55–53.95E | Dunes: Liwa megabarchans / draa (Rub' al Khali NE edge) |
| rub_al_khali | 20.25–20.65N, 50.15–50.65E | Dunes: low draa with small superimposed dunes |
| namib / namib_south | 24.62–24.90S / 24.78–24.90S, 15.15–15.50E | Dunes: Sossusvlei star/linear dunes (namib_south excludes the pan) |

---

## General terrain statistics (all sites)

Method: slope = `atan(|grad z|)` from `np.gradient` with the true dx/dy. Local relief = max − min in a square window of side 100 m, 500 m or 1 km, shown as p50 / p90 over all pixels. The 100 m window is only 3×3–5×3 px, so it effectively measures pixel-scale relief.

| site | px (m) | slope p50 (°) | p90 | p99 | relief 100 m p50/p90 (m) | relief 500 m p50/p90 | relief 1 km p50/p90 | elev p1–p99 (m) |
|---|---|---|---|---|---|---|---|---|
| zhangjiajie | 27×31 | 27.2 | 41.6 | 53.2 | 54 / 94 | 238 / 332 | 372 / 487 | 344–1162 |
| yangshuo | 28×31 | 14.3 | 34.4 | 48.0 | 30 / 70 | 126 / 220 | 187 / 289 | 106–494 |
| chocolate | 30×31 | 9.1 | 25.0 | 36.0 | 14 / 35 | 58 / 100 | 83 / 131 | 141–369 |
| kata_tjuta | 28×31 | 1.2 | 13.5 | 48.4 | 2 / 28 | 12 / 147 | 20 / 222 | 544–856 |
| fuji | 25×31 | 13.0 | 35.0 | 42.8 | 24 / 69 | 116 / 299 | 204 / 478 | 18–2537 |
| uluru | 28×31 | 1.2 | 4.7 | 28.2 | 3 / 8 | 12 / 18 | 17 / 23 | 510–750 |
| geiranger | 29×31 | 25.3 | 47.2 | 66.8 | 36 / 83 | 284 / 543 | 542 / 923 | 0–1609 |
| dolomites | 21×31 | 23.4 | 40.9 | 61.7 | 40 / 79 | 247 / 431 | 440 / 695 | 1198–2850 |
| aso | 26×31 | 11.9 | 27.3 | 40.8 | 22 / 49 | 78 / 197 | 131 / 327 | 348–1215 |
| rub_al_khali | 29×31 | 2.9 | 6.0 | 11.9 | 4 / 8 | 18 / 25 | 25 / 33 | 213–261 |
| liwa | 28×31 | 5.6 | 12.1 | 21.9 | 11 / 20 | 41 / 69 | 55 / 97 | 90–186 |
| namib_south | 28×31 | 5.3 | 16.7 | 29.0 | 11 / 32 | 53 / 120 | 88 / 176 | 511–829 |
| namib | 28×31 | 6.8 | 20.0 | 29.6 | 14 / 39 | 70 / 144 | 114 / 211 | 527–887 |

(Uluru and Kata Tjuta crops are mostly flat plain, so their p50 values describe the plain. Use p99 for the rock itself.)

---

## 1. Mounds (pillar or tower clusters)

Method (`mounds.py`):
* **Peaks:** exact 8-connected topographic prominence from a descending union-find (watershed merge). Minimum prominence is 10 m at Bohol and 20 m elsewhere. Peaks within 3 px of the crop edge are dropped.
* **Height:** prominence, i.e. relief above the key col. On a plain this equals the height above the plain.
* **Local height:** peak minus the minimum in a 1 km window, i.e. the full tower height above the surrounding valley floor.
* **Footprint diameter:** equivalent diameter `2*sqrt(A/pi)` of the connected region above `col + 10% of prominence`.
* **Steepness:** mean and p90 slope inside that footprint.
* **Scatter:** nearest-neighbour distance between peaks.
* **Count per cluster:** single-linkage clusters with link distance = 1.5 × median nearest-neighbour distance, counting clusters with ≥ 2 members.

| parameter | min (p5/p10) | typical (p50) | max (p95 / max) | unit | site | notes |
|---|---|---|---|---|---|---|
| Footprint diameter | 77 | 138 | 360 / 1290 | m | Chocolate Hills | n = 1652 hills, 6.9 per km² |
| Footprint diameter | 105 | 230 | 743 / 1380 | m | Yangshuo towers | n = 1492, 2.4 per km² |
| Footprint diameter | 108 | 223 | 677 / 1400 | m | Zhangjiajie | cluster/block scale; individual pillars (tens of m) not resolved |
| Footprint diameter | 180 | 347 | 943 / 1730 | m | Kata Tjuta domes | n = 36 |
| Height (prominence) | 11 | 20 | 44 / 112 | m | Chocolate Hills | published heights are 30–50 m; canopy plus 30 m smoothing lowers small cones |
| Height (prominence) | 22 | 48 | 142 / 277 | m | Yangshuo | |
| Height (prominence) | 21 | 35 | 108 / 161 | m | Zhangjiajie | real pillars are often > 200 m tall (UNESCO), not captured |
| Height (prominence) | 21 | 52 | 171 / 205 | m | Kata Tjuta | the whole massif is 466 m above the plain (see §2) |
| Height above local base (1 km window) | 28 | 67 | 112 / 139 | m | Chocolate Hills | |
| Height above local base | 48 | 139 | 275 / 392 | m | Yangshuo | best "tower height" figure |
| Height above local base | 142 | 298 | 439 / 503 | m | Zhangjiajie | gorge-floor-to-summit relief of the pillar plateau |
| Height above local base | 63 | 165 | 309 / 415 | m | Kata Tjuta | |
| Aspect H/D (prominence ÷ footprint) | 0.06 | 0.14 | 0.24 | – | Chocolate Hills | |
| Aspect H/D | 0.10 | 0.22 | 0.37 (p99 0.42) | – | Yangshuo | real towers are often H/D ≥ 1; the DEM widens their bases |
| Aspect H/D | 0.10 | 0.17 | 0.26 | – | Zhangjiajie | |
| Aspect H/D | 0.05 | 0.19 | 0.28 | – | Kata Tjuta | |
| Steepness: mean slope in footprint | 9 | 17 | 26 | ° | Chocolate Hills | |
| Steepness: mean slope in footprint | 14 | 26 | 37 | ° | Yangshuo | |
| Steepness: mean slope in footprint | 15 | 22 | 29 | ° | Zhangjiajie | |
| Steepness: mean slope in footprint | 7 | 25 | 34 | ° | Kata Tjuta | |
| Steepness: p90 slope in footprint | 13 | 24 | 35 | ° | Chocolate Hills | |
| Steepness: p90 slope in footprint | 22 | 36 | 48 (p99 53) | ° | Yangshuo | real tower walls 60–90° |
| Steepness: p90 slope in footprint | 23 | 33 | 43 | ° | Zhangjiajie | real pillar walls about 85–90° |
| Steepness: p90 slope in footprint | 12 | 40 | 52 | ° | Kata Tjuta | |
| Scatter: nearest-neighbour spacing | 127 | 193 | 372 | m | Chocolate Hills | |
| Scatter: nearest-neighbour spacing | 193 | 338 | 630 | m | Yangshuo | |
| Scatter: nearest-neighbour spacing | 210 | 448 | 930 | m | Zhangjiajie | |
| Scatter: nearest-neighbour spacing | 391 | 590 | 1332 | m | Kata Tjuta | |
| Count per cluster (p10 / p50 / p90 / max) | 2 | 4 | 16 / 582 | members | Chocolate Hills | the field percolates into one giant cluster |
| Count per cluster | 2 | 4 | 17 / 128 | members | Yangshuo | |
| Count per cluster | 2 | 3 | 8 / 13 | members | Zhangjiajie | |
| Count per cluster | 3.6 | 6 | 20 / 23 | members | Kata Tjuta | 36 domes in 3 groups |

**Suggested slider mapping**
* footprint 60–1200 m (typical 120–350)
* height 10–300 m (typical 20–150); allow up to about 400 m for a pillar or massif look
* mean flank slope 10–40°; steepest-part slope 25–55° from the DEM. Let the top of the steepness slider reach near-vertical (85–90°) for Zhangjiajie-style pillars, which the DEM cannot show.
* spacing 120–1300 m (typical 200–450)
* members per cluster 2–20 (typical 3–6)

---

## 2. Lone Mountain

Method (`lone_mountain.py`):
* The summit is the maximum of a σ = 1 px smoothed DEM. 180 radial profiles (every 2°) are sampled every 30 m.
* **Base elevation:** median over all azimuths of the profile minimum beyond 0.7 R_max. **Height** H = summit − base.
* **Base radius:** per azimuth, the first radius where z ≤ base + 5% H. **Base width** = 2 × median radius.
* **Concavity:** median normalised profile z/H at r/R = 0.5. A straight cone gives 0.5; < 0.5 is concave (volcano); > 0.5 is convex (dome).
* **Band slopes:** along-profile slope in the top 10%, middle and bottom 30% of the height range.
* **Summit curvature:** least-squares fit of `z = z0 − r²/(2Rc)` within 600 m (Fuji), 300 m (Uluru) or 200 m (Kata Tjuta).
* **Ridges and gullies:** residual = ring elevation − ring mean at r = 0.3, 0.5 and 0.7 R. Ridges are maxima of the residual against azimuth (`find_peaks`, minimum prominence 5, 20 or 50 m). Gully depth is the prominence of the minima.

| parameter | Mt Fuji | Uluru (inselberg) | Kata Tjuta (Mt Olga massif) | unit | notes |
|---|---|---|---|---|---|
| Height above surroundings | 3287 (summit 3768, base 482) | 335 | 466 | m | official Uluru figure is 348 m |
| Base width (median diameter) | 29.9 (radius p10–p90 10.3–21.2 km) | 1.86 (radius 0.78–1.35 km; real outline about 3.6 × 1.9 km) | 3.06 | km | |
| H / base width | 0.11 | 0.18 | 0.15 | – | |
| Mean overall slope atan(H/R) | 12.4 | 19.8 | 16.9 | ° | |
| Slope, top 10% of height | 28 | 5 | 11 | ° | Fuji is steepest near the top; Uluru has a flat top |
| Slope, middle band | 20 | 17 | 24 | ° | |
| Slope, bottom 30% | 6.6 | 33 | 6.9 | ° | Uluru: wall rises straight off the plain |
| Concavity z/H at r/R = 0.5 | 0.25 | 0.78 | 0.30 | – | 0.25 concave volcano; 0.78 convex dome |
| Summit radius of curvature | 770 (crater-influenced) | 980 | 200 | m | smaller = sharper peak |
| Radial ridges, prominence ≥ 5 m (at 0.3 / 0.5 / 0.7 R) | 37 / 42 / 61 | 3 / 4 / 8 | 3 / 9 / 7 | count | |
| Radial ridges, prominence ≥ 20 m | 12 / 9 / 16 | 3 / 3 / 5 | – | count | |
| Radial ridges, prominence ≥ 50 m | 7 / 4 / 5 | – | – | count | |
| Gully depth (p25 / p50 / p90) | 7 / 10–16 / 40–77 | 12–33 / 22–70 / 94–241 | 17–230 / 72–346 / 245–366 | m | Uluru and Kata Tjuta values are mostly outline lobes and gaps between domes, not erosional gullies |

**Suggested slider mapping**
* base width 1.5–30 km
* height 150–3300 m, with H/W of 0.1–0.2 throughout
* radial ridges 3–60. Use about 8–16 for "significant" ridges with gully depth 20–80 m. Fuji's typical gullies are only 10–15 m deep.
* peak sharpness: map to the concavity index (0.25 concave and sharp, about 0.5 cone, 0.8 dome) and/or summit radius of curvature (about 200 m sharp to about 1000 m rounded)

---

## 3. Bluff (one-sided steep face)

Method:
* **Automatic faces (`walls.py: bluffs`):** the face mask is slope ≥ 40° on a σ = 1 px smoothed DEM, closed and labelled. Only faces ≥ 300 m long are kept. Each face is described in its PCA frame (u along the face, v across it).
* **Length:** p98 − p2 of u.
* **Face height:** median over 60 m along-face bins of max − min z in the face dilated by 2 px.
* **Face slope:** mean and p90 of raw slope over face pixels.
* **Lobes** (faces ≥ 1 km only): mean v offset per 60 m bin, quadratic detrend to remove the overall bend, then amplitude = p95 − p5 and wavelength = 2 × length ÷ zero crossings.
* **Back slope:** mean slope of a 1–10 px ring outside the face where z > the face's p90 elevation. **Foot slope** uses z < p10.
* **Fjord cross-profiles (`transects.py`):** four N–S profiles across Geirangerfjord at 7.06, 7.10, 7.15 and 7.20E. Each side reports the rim (maximum within 2.5 km) above the water.

| parameter | min (p10) | typical (p50) | max (p90 / max) | unit | site | notes |
|---|---|---|---|---|---|---|
| Length | 340 | 554 | 2260 / 9930 | m | Geiranger (47 faces) | faces follow the fjord for kilometres |
| Length | 343 | 563 | 1470 / 7140 | m | Dolomites (186 faces) | |
| Length | 330–360 | 380–590 | 670–1700 / 1100–3500 | m | Zhangjiajie, Yangshuo, Uluru, Kata Tjuta, Aso | |
| Face height (contiguous ≥ 40°) | 134 | 194 | 403 / 910 | m | Geiranger | |
| Face height | 115 | 167 | 355 / 805 | m | Dolomites | e.g. Sella walls |
| Face height | 107–155 | 137–197 | 172–247 / 182–338 | m | Aso, Yangshuo, Zhangjiajie, Uluru, Kata Tjuta | about 100 m is the detection floor |
| Total wall height, water to rim | 780 | 1050 | 1320 | m | Geirangerfjord, 8 sides | horizontal run 1.7–2.5 km |
| Face slope, mean over face pixels | 44 | 46.6–50.7 | 50–52 | ° | all sites | ≥ 40° by construction |
| Face slope, p90 within face | 48 | 53–60 | 62–69 | ° | all sites | DEM-limited; real walls 70–90° |
| Face slope, overall mean (rim ÷ run) | 17.5 | 24 | 37 | ° | Geirangerfjord transects | max over a 90 m baseline: 47–73° |
| Lobe amplitude (p95 − p5 offset) | 70–95 | 100–235 | 119–1560 | m | all faces ≥ 1 km | typical 100–250; large values are fjord bends |
| Lobe wavelength | 400–570 | 570–1080 | 900–2200 / 3600 | m | all faces ≥ 1 km | Dolomites p50 730 m, Geiranger 1080 m, Zhangjiajie 570 m |
| Back slope (above the rim) | 16–22 | 23–29 | 27–34 / 53 | ° | all sites | plateau tops are not flat at 30 m (Sella about 20–28°) |
| Foot slope (below the face) | 4 (Uluru) | 17–27 | 24–33 | ° | | Uluru 7° (plain); Yangshuo and Kata Tjuta 17°; mountain sites 25–27° (talus) |

**Suggested slider mapping**
* length 0.3–10 km (typical 0.5–2 km)
* face height 30–1300 m. Real bluffs below 100 m exist; the DEM just cannot see them. Typical values are 150–400 m, with fjord walls about 1000 m.
* face slope 35–90°: the DEM gives 45–70°, real rock faces reach 80–90°
* lobe wavelength 0.4–3 km, amplitude 50–300 m
* back slope 0–35° (typical 15–30°)

---

## 4. Border Wall (two-sided ridge or crest)

Method (`walls.py: walls`):
* **Ridge mask:** TPI = z − Gaussian(z, σ = 500 m) ≥ 60 m, opened and then skeletonised. Skeleton components ≥ 1 km are kept.
* **Length:** skeleton path length (includes branches) and straight span along the PCA axis.
* **Roughness:** crest elevations ordered along the axis, minus a 1 km running median; std and p95 − p5.
* **Cross-sections:** taken every 150 m, perpendicular to the local ridge direction (PCA of skeleton within 200 m), over ±1.5 km. The crest is snapped to the maximum within ±150 m.
* **Side drops** hA ≥ hB = crest − minimum on each side. **Height** = (hA + hB) / 2. **Skew** = |hA − hB| / (hA + hB): 0 is symmetric, 1 is a one-sided bluff.
* **Flank slope:** atan(drop ÷ distance to the minimum). Also the maximum slope within 300 m of the crest.
* **Crest width:** width of the contiguous part of the profile within 25 m of the crest. This is sharpness; the floor is about 90 m at 30 m posting.

| parameter | min (p10) | typical (p50) | max (p90 / p99 or max) | unit | site | notes |
|---|---|---|---|---|---|---|
| Length, straight span | 870 | 1830 | 4960 / 12040 | m | Dolomites (63 ridges) | |
| Length, straight span | 1090 | 2010 | 5540 / 7660 | m | Geiranger (16 ridges) | |
| Length, straight span | 700–970 | 1000–1570 | 1700–3600 / 3700–6800 | m | Zhangjiajie, Aso rim, Yangshuo | |
| Length, path with branches | 1300 | 2400–3400 | 6500–15700 / 31300 | m | all sites | longest connected crest networks |
| Height, mean of both sides | 194 | 344 | 581 / 805 | m | Dolomites | 2544 sections |
| Height, mean of both sides | 218 | 423 | 652 / 776 | m | Geiranger | 625 sections |
| Height, mean of both sides | 180 | 285 | 393 / 480 | m | Zhangjiajie | |
| Height, mean of both sides | 162 | 232 | 336 / 524 | m | Aso caldera rim | |
| Height, mean of both sides | 152 | 208 | 272 / 327 | m | Yangshuo ridges | |
| Height, higher side | 277–320 | 495–636 | 763–1071 / 974–1343 | m | Dolomites, Geiranger | |
| Crest width (within 25 m of crest) | 90–120 | 135–210 | 270–690 | m | Yangshuo, Zhangjiajie, Aso, Dolomites | Dolomites p50 180 m; ≤ 90 m is unresolvable |
| Crest width (within 25 m of crest) | 120 | 315 | 1490 | m | Geiranger | upper tail is plateau-topped ridges (Sella, Puez) |
| Roughness: crest std | 7–12 | 16–25 | 31–127 / 47–189 | m | all sites | Dolomites p50 25, p90 90; Geiranger p50 23, p90 127; Yangshuo p50 21, p90 31 |
| Roughness: crest p95 − p5 | 23–40 | 54–89 | 105–480 | m | all sites | |
| Skew \|hA − hB\| / (hA + hB) | 0.01–0.12 | 0.07–0.59 | 0.34–1.0 | – | all sites | Yangshuo 0.07, Zhangjiajie 0.24, Dolomites 0.37, Aso 0.37, Geiranger 0.59 |
| Flank slope, steep side | 9–16 | 14–27 | 21–39 / 30–52 | ° | all sites | crest to valley floor |
| Flank slope, gentle side | 0–6 | 8–12.5 | 13–23 | ° | all sites | |
| Max slope within 300 m of crest, steep side | 24–31 | 39–43 | 46–63 / 74 | ° | all sites | |
| Max slope within 300 m of crest, gentle side | 8–21 | 23–31 | 38–44 / 64 | ° | all sites | |

**Suggested slider mapping**
* length 1–12 km straight (typical 2–5 km)
* height 150–800 m (typical 250–450 m), with a one-sided maximum of about 1300 m
* crest width 30–1500 m (typical 100–300 m; below about 90 m is a knife-edge, which the DEM shows as 90–120 m)
* roughness, as crest std, 5–130 m (typical 15–40 m)
* skew 0–1 (typical 0.1–0.6). 1 means the wall degenerates into a bluff.

---

## 5. Basin

Method (`basins.py`):
* **Caldera (Aso):** rays every 2° from the hand-picked centre 32.898N 131.072E. The rim is the maximum z along each ray between 6 and 16 km. The interior is the polygon through the rim points.
  * Floor = p2 of interior z. Depth = median rim − floor. Spill depth = lowest rim point (the outlet gorge) − floor.
  * Flatness = fraction of the interior with z ≤ floor + f × depth, for f = 0.1 and 0.25.
* **Closed depressions:** priority-flood fill (Barnes 2014; crop edges drain), depth = filled − z.
  * Kept if max depth ≥ 5 m and area ≥ 10 px; the 5 m cutoff removes DSM noise and canopy pits.
  * W = equivalent diameter. Flatness = fraction of the depression within 10% or 25% of its depth above its own minimum.

| parameter | min (p10) | typical (p50) | max (p90 / max) | unit | site | notes |
|---|---|---|---|---|---|---|
| Width | – | 22.9 (min–max diameter 12.6–29.6) | – | km | Aso caldera | published size about 18 × 25 km; measured area 401 km² |
| Depth (median rim − floor) | – | 511 | – | m | Aso | rim p10 / p50 / p90 = 793 / 901 / 1122 m; floor 390 m |
| Spill depth (lowest rim − floor) | – | 134 | – | m | Aso | Tateno gorge outlet |
| Depth / width | – | 0.022 | – | – | Aso | very shallow relative to its size |
| Floor flatness, within 10% / 25% of depth | – | 0.06 / 0.28 | – | fraction | Aso | central cones are inside the rim; the floor is two sloping valleys |
| Width | 108–124 | 136–283 | 298–1220 / 1.3–10 km | m | closed depressions: Yangshuo, Bohol, Zhangjiajie, Liwa, Namib | Namib p50 283 m; Liwa p50 153 m |
| Depth | 5.7–6.9 | 10–15 | 21–56 / 40–198 | m | closed depressions | Namib interdune pans deepest (max 198 m) |
| Depth / width | 0.02–0.05 | 0.054–0.086 | 0.09–0.16 / 0.23 | – | closed depressions | karst dolines highest (Zhangjiajie p50 0.086) |
| Floor flatness, within 10% of depth | 0.01–0.04 | 0.06–0.10 | 0.14–0.21 / 0.69 | fraction | closed depressions | natural closed basins are bowl-shaped |
| Floor flatness, within 25% of depth | 0.04–0.09 | 0.12–0.24 | 0.27–0.38 / 0.74 | fraction | closed depressions | |

**Suggested slider mapping**
* width 0.1–25 km
* depth 5–500 m, with depth/width of about 0.02–0.15
* floor flatness 0–0.75: natural bowls sit at 0.05–0.25; above about 0.4 reads as a filled lake or sediment plain such as the Sossusvlei pan

---

## 6. Dunes

Method (`dunes.py`, `dunes_1d.py`):
* Resample to an isotropic 30 m grid and high-pass with z − Gaussian(σ = 4 km).
* **2-D FFT** (Hann window): the dominant peak gives spacing and orientation. Also report the power-weighted median wavelength (150 m–6 km band).
* **Autocorrelation:** first peak along the dominant direction.
* **Profiles:** taken every 300 m along the dominant direction. Crests and troughs come from `find_peaks` (distance ≥ 0.5 λ, prominence ≥ 2 m). Dune height = crest − mean of the adjacent troughs. Crest spacing comes from the same profiles.
* **1-D row spectra** (E–W and N–S) as a check, because a Hann-windowed 2-D FFT on a narrow crop can lock onto regional relief.
* **Superimposed dunes:** spectral peak restricted to 150–800 m, plus p95 − p5 of a σ = 150 m high-pass.

| parameter | min (p10) | typical (p50) | max (p90 / p99) | unit | site | notes |
|---|---|---|---|---|---|---|
| Wavelength (crest spacing) | 1260 | 1740 (FFT 2370, autocorrelation 2190, N–S spectrum 2550) | 2520 | m | Liwa megabarchans | E–W crest rows |
| Wavelength | 2880 | 3750 (spectral power median 1800) | 5880 | m | Namib (Sossusvlei, includes pan) | |
| Wavelength | 2000 | 2000–2900 (E–W spectrum secondary peaks) | – | m | Namib south (linear dunes) | 2-D peak (4.8–7 km) is regional, rejected |
| Wavelength | 1620 | 2100 (autocorrelation 2250, FFT 3100) | 3000 | m | Rub' al Khali, 20.45N 50.4E | |
| Superimposed dune wavelength | – | 710–800 | – | m | all four | anything under 150 m is not measurable |
| Height (crest − adjacent troughs) | 18 | 35 | 80 / 107 | m | Liwa | n = 2334 |
| Height | 41 | 101 | 195 / 276 | m | Namib (with pan) | star dunes about 300 m above the pan |
| Height | 40–47 | 77–79 | 162–172 / 262–277 | m | Namib south | |
| Height | 12 | 18 | 27 / 35 | m | Rub' al Khali site | low draa |
| Superimposed dune amplitude (p95 − p5) | – | 10 (Rub' al Khali), 20 (Liwa), 30–38 (Namib) | – | m | | |
| Slope distribution (p50 / p90 / p99) | – | 2.6–6.6 / 5.5–19.5 / 11–29 | – | ° | all four | real slip faces about 32–34° |

**Suggested slider mapping**
* wavelength 0.1–3 km. 0.1–0.5 km is "normal" dunes, below this DEM's resolution. 1–3 km is megadunes or draa.
* height 2–300 m (typical 15–100 m), with height/wavelength of about 0.01–0.05
* for slip faces, clamp at about 33° (angle of repose) rather than using DEM slopes

---

## Files and reproduction

All in [tools/terrain-sampling/](../../tools/terrain-sampling/). `tiles/`, `png/` and `out/` are gitignored and rebuilt by running the scripts.

| file | purpose |
|---|---|
| `download.py` | `python download.py N29E110 S25E015 ...` fetches GLO-30 tiles to `tiles/` (cached; `demlib` auto-downloads missing ones) |
| `demlib.py` | tile loading and mosaicking, crop to metres, slope, local relief, hillshade PNG with lat/lon graticule, exact prominence (union-find), priority-flood fill, profile sampling |
| `sites.py` | site bounding boxes; edit to add places |
| `preview.py` | hillshade PNGs to `png/`, used to check each crop |
| `general.py` | slope percentiles and local relief per site, written to `out/general.json` |
| `mounds.py` | peaks, prominence, footprint, steepness, spacing and clusters, written to `out/mounds.json` |
| `lone_mountain.py` | radial-profile analysis, written to `out/lone_mountain.json` |
| `walls.py` | automatic bluff faces and ridge cross-sections, written to `out/walls.json` |
| `transects.py` | manual cross-profiles (Geirangerfjord) |
| `basins.py` | caldera rim analysis and closed-depression statistics, written to `out/basins.json` |
| `dunes.py`, `dunes_1d.py` | FFT, autocorrelation and profile dune wavelength and height, written to `out/dunes.json` |

Dependencies: numpy, scipy, tifffile, imagecodecs, scikit-image and Pillow (installed with `pip install --user`). The whole pipeline runs in under 2 minutes once the tiles are cached.
