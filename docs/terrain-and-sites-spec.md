# Terrain, Sites and Runtime Systems

Target: Noggit-class direct editing, over a definition/variant system, with every
runtime behaviour opt-in per project.

---

## 0. The two load-bearing principles

Everything else in this document follows from these. If a proposed change
violates either one, the change is wrong.

### Principle 1 — Systems act on properties, never on types

No system may branch on what a thing *is*. It branches on what a thing *exposes*.

- Fire does not know what a wooden house is. It reads `flammability` and
  `ignitionTemp`.
- A hammer does not know terrain exists. It applies displacement to anything
  exposing `hardness`.
- Water does not know about fire. It writes `wetness`; fire reads it.

**Consequence:** a new material gains behaviour in every system at once, and a
new system works on every existing material at once. Without this, every
system/material pair is bespoke code and the combination count kills the
project. Detail in §3.2.

### Principle 2 — Sites are the only contract between terrain and structures

Terrain and structures never reference each other. A site sits between them and
is the sole channel.

- Terrain changes → overlapping sites revalidate
- A site that fails validation → its structure enters `unsupported`
- What `unsupported` *does* is a capability decision, not a terrain concern

**Consequence:** ground can deform under a building without the building system
knowing terrain exists, and the reaction is configurable per project rather than
hardcoded. Detail in §3.3.

### Corollary — capabilities are the third leg

Both principles only hold if behaviour is opt-in. A capability that is off costs
no tick, no memory and no save bytes, and content authored with it on must still
load with it off. Detail in §5.

---

## 0.1 UX reference

Direct manipulation modelled on Noggit: brush on terrain, paint layers, drop
objects, see the result immediately, toggle layers independently. Noggit is the
reference for *feel and immediacy* only — it has no non-destructive stack, no
procedural base and no capability system, and every world built with it was
hand-placed by a team. The procedural and variant layers here are what Noggit
lacks and what makes one-person authoring possible.

Noggit Red is GPLv3. Study the design; never copy the code. See
[licensing-policy.md](licensing-policy.md).

---

## 1. Core concepts

| Concept | What it is |
|---|---|
| **Region** | The authored unit. Fixed extent, fixed chunk grid, own seed. One region = one file set. |
| **Terrain** | Chunked heightfield + per-chunk material layers, holes, water. |
| **Site** | A marked, validated location on terrain where structures may exist. Carries footprint, slope tolerance, foundation type, and a list of what may occupy it. |
| **Structure** | An instance of a building definition, occupying a site. |
| **Prop / Foliage** | Placed or scattered instances. Props are authored; foliage is density-driven. |
| **Definition** | Authored template (building, prop, material, effect). Never placed directly. |
| **Variant** | A resolved form of a definition (size, style, damage state, faction skin). |
| **Capability** | A runtime system that can be switched on or off per project. |

**Rule:** the editor authors definitions, regions, terrain and sites. It never
authors instances of runtime state.

---

## 2. Editor

### 2.1 Region setup

- Create region: extent in metres, chunk size, seed, biome set
- Regions are independent; no cross-region references except at declared border seams
- A region declares which **capabilities** its content must support (see §5)

### 2.2 Layer toggles

Independently visible and independently editable:

- Terrain (heightfield)
- Material layers (splat)
- Holes
- Water / liquid
- Sites
- Paths
- Structures
- Props
- Foliage
- Navigation
- Effect volumes
- Region/zone IDs
- Collision

Each layer: `visible`, `editable`, `solo`, `opacity`.

### 2.3 Terrain editing

- Brush sculpt: raise, lower, flatten, smooth, noise, ramp
- Brush shape + falloff curve + strength + size
- Heightmap import/export per region, with vertical scale
- Material painting with layer weights
- Hole cutting (cave and interior entrances — see §4.3)
- Vertex tint
- Water volume placement with level and flow direction
- Easy terrain button: one click generates a natural-looking base terrain mesh for the region to edit from

### 2.4 Site editing

- Place site: footprint polygon or rect, orientation, anchor point
- Site declares: `foundationType`, `maxSlope`, `allowedCategories[]`, `sizeClass`
- Auto-validate against terrain under it; invalid sites flag in the viewport
- Snap/align tools; grid and terrain-follow modes

### 2.5 Path tool

- Designate endpoints on sites or terrain; the tool generates the route between them
- Path types: `walkable`, `scalable`
- Routes follow terrain contour and blend into material layers so they read as natural, not drawn
- Paths revalidate with the sites and terrain they cross

### 2.6 Lock and bake

A region is **locked** when authoring ends. Locking produces:

- Baked terrain chunks
- Validated site table
- Static collision
- Base navigation
- Region manifest (hash of every input)

Locking does not prevent runtime change — it fixes the **authored baseline** that
runtime deltas apply on top of.

---

## 3. Scalability model

### 3.1 Definition → variant → instance

```
BuildingDefinition
  ├─ sizeClass: small | medium | large
  ├─ categories: [residential, military, ...]
  ├─ requires: { foundationType, maxSlope, footprint }
  ├─ parts[]: structural pieces, each with material + integrity
  ├─ variants[]: style / faction / era skins
  └─ damageStates[]: intact → damaged → ruined → rubble
```

One definition yields every variant. Placing a structure stores a definition id,
a variant id, a site id and a transform — never geometry.

**Consequence:** adding a faction, era or style adds variants, not buildings.
Adding a damage state applies to every building that shares the part materials.

### 3.2 Properties, not types

Runtime systems act on **material properties**, never on object types. This is
the mechanism that makes everything interact without per-pair code.

Every terrain material and every structural part carries:

| Property | Used by |
|---|---|
| `hardness` | deformation, impact |
| `flammability` | fire |
| `ignitionTemp` | fire |
| `burnRate` | fire |
| `integrity` | destruction |
| `mass` | collapse, debris |
| `porosity` | fluid, wetness |
| `wetness` | fire suppression, deformation |
| `conductivity` | heat spread |
| `friction` | movement, vehicles |

Fire does not know what a wooden house is. It knows `flammability` and
`ignitionTemp`. A hammer does not know about terrain. It applies displacement to
anything exposing `hardness`.

**Adding a new material adds behaviour across every system at once. Adding a new
system works on every existing material at once.**

### 3.3 Sites are the terrain/structure contract

Terrain and structures never reference each other directly. Sites sit between:

- Terrain changes → affected sites revalidate
- A site that fails validation → its structure enters `unsupported` state
- What `unsupported` does is a capability decision (collapse, sink, nothing)

This is what lets terrain deform under a building without the building system
knowing terrain exists.

---

## 4. Terrain at runtime

### 4.1 Authored baseline + delta

- Authored heightfield is immutable at runtime
- Runtime changes are stored as a **delta layer** per chunk
- Rendered/collided height = baseline + delta
- Saves store deltas only; a world with no deformation saves nothing extra
- Deltas are bounded per chunk; exceeding budget forces a bake

### 4.2 Deformation sources

All go through one displacement API, so a new source needs no new terrain code:

- Tool impact (hammer, shovel, drill)
- Explosion
- Vehicle rutting
- Structural collapse
- Erosion tick
- Scripted event

Each supplies: position, radius, falloff, displacement, and the material
properties it can affect.

### 4.3 Holes and interiors

Caves, mines and building interiors are **holes in the heightfield plus a placed
interior volume**. No voxels.

- Hole mask is per chunk
- Interiors are separate meshes with their own collision and navigation
- Interiors may be destructible independently of the terrain around them

### 4.4 What deformation invalidates

On any terrain change, in order:

1. Collision patch for affected chunks
2. Navigation patch for affected chunks
3. Site revalidation for overlapping sites
4. Foliage/prop re-grounding or removal
5. Water level resolve for affected basins

Each step is a capability and can be disabled.

---

## 5. Capabilities

A project enables only what it needs. A capability that is off costs nothing —
no tick, no memory, no save data.

| Capability | Enables | Requires |
|---|---|---|
| `terrain.deform` | Runtime heightfield change | delta layer, collision patch |
| `terrain.erosion` | Ongoing wear | `terrain.deform` |
| `structure.damage` | Damage states on structures | part integrity |
| `structure.collapse` | Physical collapse, debris | `structure.damage`, physics |
| `structure.rubble` | Collapse writes rubble to terrain | `structure.collapse`, `terrain.deform` |
| `fire.spread` | Fire propagates between flammables | flammability, heat field |
| `fire.terrain` | Fire spreads to and scars ground | `fire.spread`, terrain material state |
| `fluid.flow` | Water moves, floods, pools | heightfield query |
| `fluid.suppression` | Water extinguishes fire | `fluid.flow`, `fire.spread` |
| `weather.wetness` | Rain raises wetness | wetness channel |
| `nav.dynamic` | Navigation repairs after change | nav patching |
| `foliage.burn` | Foliage is flammable and removable | `fire.spread` |

**Dependency rule:** enabling a capability enables its requirements or fails at
project load with a named error. Never silently.

### 5.1 Configuration

Per project, a capability manifest:

```
capabilities:
  terrain.deform:    { enabled: true,  maxDeltaPerChunk: 4096, rebakeThreshold: 0.8 }
  terrain.erosion:   { enabled: false }
  structure.damage:  { enabled: true,  states: [intact, damaged, ruined, rubble] }
  structure.collapse:{ enabled: true,  debrisLifetime: 300 }
  structure.rubble:  { enabled: true,  displacementScale: 0.4 }
  fire.spread:       { enabled: true,  tickRate: 4, windInfluence: 0.6 }
  fire.terrain:      { enabled: true,  scarDepth: 0.05, regrowth: 900 }
  fluid.flow:        { enabled: false }
  nav.dynamic:       { enabled: true,  patchBudgetMs: 2 }
```

Content authored with a capability on must still load with it off. Structures
keep their intact state; terrain keeps its baseline. **Content never hard-depends
on a capability.**

---

## 6. Interaction matrix

What each system reads and writes. Every cell is a capability pair, not bespoke code.

| | Terrain | Site | Structure | Foliage | Fluid |
|---|---|---|---|---|---|
| **Deformation** | writes height delta | triggers revalidate | may unsupport | re-ground / remove | basin resolve |
| **Fire** | writes scar + material state | — | reads flammability, writes integrity | consumes, spreads | suppressed by |
| **Destruction** | writes rubble delta | frees site | writes damage state | crush | — |
| **Fluid** | reads height | may unsupport | writes wetness | writes wetness | — |
| **Weather** | writes wetness | — | writes wetness | writes wetness | adds volume |

Reading order per tick is fixed and declared, so results are deterministic:

```
weather → fluid → fire → destruction → deformation → nav/site revalidation
```

---

## 7. Data contracts

### Authored (in the editor, version-controlled)

- Region definition, extent, seed
- Baseline heightfield, material layers, holes
- Water volumes
- Site table
- Structure placements (definition + variant + site + transform)
- Prop placements, foliage density maps
- Material definitions
- Building definitions and variants
- Capability manifest

### Runtime (generated, not authored)

- Height deltas
- Material state (burned, wet, frozen)
- Structure damage states, debris
- Fire cells, heat field
- Fluid volumes
- Navigation patches
- Site validity flags

### Saved

Runtime only, as deltas against the region manifest hash. A save records which
region version it applies to; a region rebake invalidates or migrates saves.

---

## 7.1 Edits are operations, not pixel writes

Every authoring edit is recorded as an **ordered, deterministic operation**:

```
{ op: "sculpt", mode: "add", at: [x, z], radius: 15.0,
  strength: 2.0, falloff: "linear", seq: 1487, author: "alex" }
```

Not as the resulting heightfield bytes.

This is a decision that must be made before the first brush is written, because
retrofitting it means rewriting every tool that touches terrain.

**What it buys:**

| | Operations | Raw writes |
|---|---|---|
| Undo/redo | replay to `seq` | store full snapshots |
| Save size | kilobytes | megabytes per chunk |
| Network sync | send the op | send the chunk |
| Merge two authors | ordered replay | impossible, binary conflict |
| Audit / review | readable history | opaque diff |
| Reproduce a bug | replay the log | "it looked wrong" |

Operations are append-only and carry a monotonic `seq` per region, the same
ordering discipline `serial` gives the release manifest. Replaying the log from
the authored baseline must reproduce the current state exactly — that is the
determinism guarantee (§8) applied to authoring rather than generation.

A region's on-disk form is therefore **baseline + operation log**, with a baked
heightfield cached beside it for load speed. The cache is derived and can always
be discarded and rebuilt.

**Collaboration falls out of this for free.** Ordered operations are what makes
region ownership, presence and eventually live co-editing tractable; raw chunk
writes make all three impossible. Nothing here requires building networking now,
and skipping it forecloses networking later.

---

## 8. Determinism

- Fixed system order per tick (§6)
- Fixed-point or quantised displacement accumulation — no float drift
- Seeded RNG per system per tick, never shared
- Same authored region + same capability manifest + same input sequence → same result
- Headless execution with no renderer, for tests and server authority

---

## 9. Open decisions

Blocking. Each changes the architecture.

1. **Region extent in metres** — sets chunk size, LOD scheme, and whether
   float32 precision holds (breaks past ~8 km from origin)
2. **Delta storage granularity** — per vertex, per chunk tile, or sparse brush
   record. Sets save size and network cost
3. **Fire representation** — grid cells, particle agents, or flow field
4. **Structure parts** — pre-fractured meshes, or runtime fracture
5. **Navigation** — geometric navmesh, or the semantic grid from CycleBetSim
6. **Multiplayer authority** — if runtime terrain must sync, deltas need
   ordering and reconciliation, which constrains decision 2
