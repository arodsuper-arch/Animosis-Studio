@tool
extends Node3D
## Animosis region — the authored unit from docs/terrain-and-sites-spec.md.
##
## A region has a FIXED extent and its own local origin. A world is a grid of
## regions, not one continuous surface. That is what keeps every local
## coordinate well inside the ~8 km where float32 still resolves centimetres,
## which is why the engine fork needs no `precision=double` build.
##
## Generation is deterministic: the same seed and the same grid coordinate
## always produce the same heightfield, on any machine. That is a hard rule
## inherited from the CycleBetSim regional-grid specs and it is what lets the
## simulation run headless against terrain the renderer never touched.

const HEIGHT_CHANNEL := 0  ## import_images() takes [height, control, colour]

@export_group("Region")
## Metres across. 4096 m matches the spec's tiling model: large enough to be a
## real play space, small enough that precision is never in question.
@export var extent_m: int = 2048:
	set(v):
		extent_m = maxi(256, v)
		_refresh_derived()

## Metres between heightfield samples. Larger = coarser terrain, faster
## generation, smaller data. 2 m is a reasonable authoring default.
@export var vertex_spacing_m: float = 2.0:
	set(v):
		vertex_spacing_m = maxf(0.25, v)
		_refresh_derived()

## Which tile of the world grid this region is. Feeds the noise domain so
## neighbouring regions line up instead of repeating.
@export var grid_coord: Vector2i = Vector2i.ZERO

@export_group("Generation")
@export var seed: int = 20260924
@export var max_height_m: float = 240.0
## Terrain3D's internal chunk size -- vertices per region AND pixels per map.
## 256 is Terrain3D's recommended default. Larger values are tempting but every
## sculpt stroke re-uploads whole maps, so 1024 costs 16x the pixel traffic of
## 256 for no authoring benefit.
@export_enum("64:64", "128:128", "256:256", "512:512", "1024:1024") var chunk_size: int = 256

@export_group("Run")
## When the project is RUN (not edited), build automatically and print a
## verification report. Terrain3D allocates GPU resources on first property
## write, so it cannot be driven from a SceneTree --script hook, which executes
## before the rendering server exists. A normal scene lifecycle is required.
@export var auto_build_on_run: bool = true
@export var quit_after_report: bool = true

@export_group("Actions")
## Tick to rebuild. Resets itself; this is a button, not state.
@export var generate: bool = false:
	set(v):
		if v:
			generate = false
			build()

@export var clear: bool = false:
	set(v):
		if v:
			clear = false
			_clear()

@export_group("Derived", "info_")
@export_storage var info_resolution: int = 2048
@export_storage var info_samples: String = ""


func _refresh_derived() -> void:
	info_resolution = int(round(float(extent_m) / maxf(vertex_spacing_m, 0.25)))
	info_samples = "%d x %d samples (%.1f M)" % [
		info_resolution, info_resolution, (info_resolution * info_resolution) / 1_000_000.0
	]


func _ready() -> void:
	_refresh_derived()
	if Engine.is_editor_hint() or not auto_build_on_run:
		return
	# One frame of headroom so the rendering device is fully up before
	# Terrain3D allocates its texture arrays.
	await get_tree().process_frame
	await get_tree().process_frame
	build()
	_report()


## Samples a deterministic lattice and prints the region profile. Running twice
## must produce identical numbers -- that is the determinism guarantee the
## simulation layer depends on.
func _report() -> void:
	var terrain := _terrain()
	if terrain == null:
		return
	var data := terrain.data
	var half := float(extent_m) * 0.5
	var lo := INF
	var hi := -INF
	var sum := 0.0
	var n := 0
	var transect: Array[String] = []

	for i in 9:
		for j in 9:
			var x := -half + (float(i) / 8.0) * float(extent_m)
			var z := -half + (float(j) / 8.0) * float(extent_m)
			var h: float = data.get_height(Vector3(x, 0.0, z))
			if is_nan(h):
				continue
			lo = minf(lo, h)
			hi = maxf(hi, h)
			sum += h
			n += 1
			if i == 4 and j % 2 == 0:
				transect.append("    (%7.0f, %7.0f)  %8.3f m" % [x, z, h])

	print("\n================ ANIMOSIS REGION ================")
	print("  extent          %d m" % extent_m)
	print("  vertex spacing  %.2f m" % vertex_spacing_m)
	print("  resolution      %s" % info_samples)
	print("  seed            %d    tile %s" % [seed, grid_coord])
	print("  chunk size      %d" % terrain.region_size)
	print("  regions active  %d" % data.get_region_count())
	print("  sampled         %d points" % n)
	if n > 0 and is_finite(lo):
		print("  min %.3f m   max %.3f m   mean %.3f m" % [lo, hi, sum / float(n)])
	print("\n  centre transect (determinism fingerprint):")
	for t in transect:
		print(t)

	if n == 0 or not is_finite(lo):
		printerr("FAIL: no valid heights -- terrain did not generate")
	elif absf(hi - lo) < 1.0:
		printerr("FAIL: flat (range %.3f m) -- heightfield not applied" % (hi - lo))
	else:
		print("\nPASS: region generated with real relief")
	print("================================================\n")

	if quit_after_report:
		get_tree().quit()


func _terrain() -> Terrain3D:
	var t := get_node_or_null("Terrain3D") as Terrain3D
	if t == null:
		push_error("Region: no Terrain3D child node found.")
	return t


func _clear() -> void:
	var terrain := _terrain()
	if terrain == null:
		return
	# remove_region() takes a Terrain3DRegion, not a location, so iterate the
	# active region objects. Same pattern the addon's own importer uses.
	var n := 0
	for region: Terrain3DRegion in terrain.data.get_regions_active():
		terrain.data.remove_region(region, false)
		n += 1
	print("[region] cleared %d region(s)" % n)


## Builds the authored baseline. Runtime deformation, when the terrain.deform
## capability is enabled, becomes a DELTA on top of this — never an edit to it.
func build() -> void:
	var terrain := _terrain()
	if terrain == null:
		return

	_refresh_derived()
	var t0 := Time.get_ticks_msec()

	terrain.region_size = chunk_size
	terrain.vertex_spacing = vertex_spacing_m
	terrain.material.world_background = Terrain3DMaterial.FLAT
	terrain.material.auto_shader = true
	terrain.material.set_shader_param("auto_slope", 6.0)
	terrain.material.set_shader_param("blend_sharpness", 0.95)

	if terrain.assets == null or terrain.assets.get_texture_count() == 0:
		terrain.assets = Terrain3DAssets.new()
		terrain.assets.set_texture(0, _texture_asset("Grass", Color.from_hsv(0.29, 0.34, 0.30), Color.from_hsv(0.31, 0.38, 0.40)))
		terrain.assets.set_texture(1, _texture_asset("Rock", Color.from_hsv(0.08, 0.16, 0.30), Color.from_hsv(0.07, 0.12, 0.42)))

	var img := _heightfield(info_resolution)

	# Centre the region on its own local origin. Offsets are world metres, so
	# half the extent puts (0,0,0) at the middle of the region.
	var half := float(extent_m) * 0.5
	terrain.data.import_images([img, null, null], Vector3(-half, 0.0, -half), 0.0, max_height_m)

	print("[region] %d m, %s, spacing %.2f m, seed %d, tile %s -- %d ms" % [
		extent_m, info_samples, vertex_spacing_m, seed, grid_coord, Time.get_ticks_msec() - t0
	])


## Deterministic heightfield. Noise is sampled in WORLD space using grid_coord,
## so tile (0,0) and tile (1,0) meet without a seam and without either knowing
## about the other.
func _heightfield(res: int) -> Image:
	var origin := Vector2(grid_coord) * float(extent_m)

	var base := FastNoiseLite.new()
	base.seed = seed
	base.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	base.frequency = 0.00035
	base.fractal_type = FastNoiseLite.FRACTAL_FBM
	base.fractal_octaves = 5
	base.fractal_gain = 0.48

	# Ridged pass for ranges and valleys; fbm alone reads as rolling lumps.
	var ridge := FastNoiseLite.new()
	ridge.seed = seed + 9173
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.frequency = 0.00085
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 4

	var img := Image.create_empty(res, res, false, Image.FORMAT_RF)
	var step := vertex_spacing_m

	for y in res:
		var wz := origin.y + y * step
		for x in res:
			var wx := origin.x + x * step
			var b := base.get_noise_2d(wx, wz) * 0.5 + 0.5          # 0..1
			var r := ridge.get_noise_2d(wx, wz) * 0.5 + 0.5          # 0..1
			# Ridges only assert themselves at altitude, so lowlands stay flat
			# enough to be buildable. Sites need buildable ground to exist.
			var h: float = b * 0.72 + (r * r) * b * 0.45
			img.set_pixel(x, y, Color(h, 0.0, 0.0, 1.0))

	return img


func _texture_asset(asset_name: String, low: Color, high: Color) -> Terrain3DTextureAsset:
	var gradient := Gradient.new()
	gradient.set_color(0, low)
	gradient.set_color(1, high)

	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.004
	fnl.seed = seed + asset_name.hash()

	var size := 512
	var img := Image.create_empty(size, size, true, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var n: float = fnl.get_noise_2d(x, y) * 0.5 + 0.5
			var c := gradient.sample(n)
			c.a = n          # albedo alpha carries height for blending
			img.set_pixel(x, y, c)
	img.generate_mipmaps()

	var ta := Terrain3DTextureAsset.new()
	ta.name = asset_name
	ta.albedo_texture = ImageTexture.create_from_image(img)
	ta.uv_scale = 0.08
	ta.detiling_rotation = 0.1
	return ta
