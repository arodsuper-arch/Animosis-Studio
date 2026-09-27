@tool
extends RefCounted
## The Animosis world coordinate scheme.
##
## Derived from our own region model (docs/terrain-and-sites-spec.md §1), plain
## metric throughout, and deliberately NOT modelled on any existing game's tile
## system. Metres everywhere, one coordinate frame, Y up, right-handed.
##
## ## The hierarchy
##
##     region        4096 m   authored unit, own local origin (centre)
##     render chunk   512 m   Terrain3D region: what re-uploads when you sculpt
##     layer chunk    128 m   simulation tick + network delta granularity
##     layer cell       2 m   one per terrain vertex
##
## Every level divides cleanly into the one above, so every lookup is integer
## maths and no level can straddle a boundary of another.
##
## ## Why they differ
##
## Rendering wants large chunks -- fewer draw calls. Simulation and networking
## want small ones: a layer chunk is the unit that ticks and the unit that syncs
## as a delta, and at 2 m cells a 512 m chunk is 256x256 cells (~256 kB for four
## layers) while a 128 m chunk is 64x64 (~16 kB). Sixteen times cheaper per
## change. Forcing them to be the same size would mean picking which of the two
## to make wrong.
##
## ## Why the cell is 2 m
##
## It matches terrain vertex spacing exactly, so a layer texture samples with
## the same UV as the heightmap. No resampling, no interpolation mismatch, and
## no drift between where the ground is and where the frost on it is.

## One layer cell per terrain vertex. Must equal Region.vertex_spacing_m.
const LAYER_CELL_M := 2.0

## Ticks and syncs as a unit. 64 x 64 cells.
const LAYER_CHUNK_M := 128.0

## Terrain3D region: region_size (256 vertices) x vertex spacing (2 m).
## This is what re-uploads on a sculpt stroke.
const RENDER_CHUNK_M := 512.0


static func cells_per_layer_chunk() -> int:
	return int(LAYER_CHUNK_M / LAYER_CELL_M)            # 64


static func layer_chunks_per_render_chunk() -> int:
	return int(RENDER_CHUNK_M / LAYER_CHUNK_M)          # 4


## Verifies the hierarchy actually nests. Called on region setup: a misaligned
## grid means layer data that does not line up with what is rendered, and that
## failure is invisible until something looks wrong on screen.
static func validate(region_extent_m: float, vertex_spacing_m: float) -> PackedStringArray:
	var problems := PackedStringArray()

	if not is_equal_approx(vertex_spacing_m, LAYER_CELL_M):
		problems.append("vertex spacing %.2f m != layer cell %.2f m; layer textures will not share the heightmap UV"
			% [vertex_spacing_m, LAYER_CELL_M])
	if not is_zero_approx(fmod(LAYER_CHUNK_M, LAYER_CELL_M)):
		problems.append("layer chunk %.0f m is not a whole number of cells" % LAYER_CHUNK_M)
	if not is_zero_approx(fmod(RENDER_CHUNK_M, LAYER_CHUNK_M)):
		problems.append("render chunk %.0f m is not a whole number of layer chunks" % RENDER_CHUNK_M)
	if not is_zero_approx(fmod(region_extent_m, RENDER_CHUNK_M)):
		problems.append("region %.0f m is not a whole number of render chunks" % region_extent_m)

	return problems


# ----------------------------------------------------------------- region --

static func region_of(world: Vector3, extent_m: float) -> Vector2i:
	if extent_m <= 0.0:
		return Vector2i.ZERO
	return Vector2i(int(floorf(world.x / extent_m)), int(floorf(world.z / extent_m)))


## Metres within the region, measured from its CENTRE. Keeps float precision
## symmetrical about the thing being edited.
static func local_of(world: Vector3, extent_m: float) -> Vector2:
	if extent_m <= 0.0:
		return Vector2.ZERO
	var r := region_of(world, extent_m)
	return Vector2(
		world.x - (float(r.x) * extent_m) - extent_m * 0.5,
		world.z - (float(r.y) * extent_m) - extent_m * 0.5
	)


# ------------------------------------------------------------------ grids --

## Index from the region's corner, 0 .. (extent / size) - 1 on each axis.
static func _index_in_region(world: Vector3, extent_m: float, size_m: float) -> Vector2i:
	if extent_m <= 0.0 or size_m <= 0.0:
		return Vector2i.ZERO
	var l := local_of(world, extent_m) + Vector2(extent_m, extent_m) * 0.5
	var per_side := int(maxf(1.0, extent_m / size_m))
	return Vector2i(
		clampi(int(floorf(l.x / size_m)), 0, per_side - 1),
		clampi(int(floorf(l.y / size_m)), 0, per_side - 1)
	)


static func render_chunk_of(world: Vector3, extent_m: float) -> Vector2i:
	return _index_in_region(world, extent_m, RENDER_CHUNK_M)


## The unit that ticks and that syncs as a delta.
static func layer_chunk_of(world: Vector3, extent_m: float) -> Vector2i:
	return _index_in_region(world, extent_m, LAYER_CHUNK_M)


## Cell index WITHIN its layer chunk, 0 .. 63.
static func cell_of(world: Vector3, extent_m: float) -> Vector2i:
	var l := local_of(world, extent_m) + Vector2(extent_m, extent_m) * 0.5
	var per := cells_per_layer_chunk()
	return Vector2i(
		posmod(int(floorf(l.x / LAYER_CELL_M)), per),
		posmod(int(floorf(l.y / LAYER_CELL_M)), per)
	)


## Stable identifier for a layer chunk anywhere in the world. This is the
## locking granularity for multi-user editing, the save key, and the unit a
## network delta names.
static func layer_chunk_id(world: Vector3, extent_m: float) -> String:
	var r := region_of(world, extent_m)
	var c := layer_chunk_of(world, extent_m)
	return "r%d.%d/L%d.%d" % [r.x, r.y, c.x, c.y]
