@tool
extends RefCounted
## Landforms: the vocabulary a region is laid out in.
##
## Sculpting a mountain a brush stroke at a time does not scale, and it is not
## what strokes are for -- raise and lower are for adjusting ground that already
## has a shape. A region gets blocked out from landforms and refined afterwards.
##
## ## Tier 1: Rises
##
## Four kinds on two axes. The axes are the design, not the labels:
##
##                   point origin        line origin
##   small / local   Mounds              Bluffs
##   large / struct  Lone Mountains      Border Walls
##
## ORIGIN is the axis that matters to the code, because it decides the gesture
## and the whole application path. A point-origin landform is one oriented stamp
## where you clicked. A line-origin one is a path you draw, resampled, with a
## cross-section walked along it -- which is also, exactly, why a bluff reads as
## "merged lobes": the lobes are the stamps.
##
## SCALE decides nothing structurally. It is carried as the size each kind
## arrives at, so picking a kind is the setup.
##
## Later tiers (depressions, surface variation) slot in beside this one. Kinds
## that have no tier yet say so rather than being filed under a tier they do not
## belong to.
##
## ## What this deliberately does not do
##
## Nothing here blends one landform into its neighbour. Where two rises meet is
## its own problem with its own maths, and mixing it into the shapes would mean
## neither could be reasoned about alone.
##
## ## Why generated rather than drawn
##
## Parametric landforms vary per seed, need no import pipeline and no artist,
## and stay data instead of becoming assets. Each kind declares its own
## parameters, so the panel builds itself and a new kind costs no UI code.
##
## ## How a stamp reaches the terrain
##
## Terrain3D's brush is already a heightfield -- it multiplies stroke strength
## by an image, which is why the falloff shapes in sculpt.gd are images of
## circles. A landform is the same mechanism with a more interesting picture.
## No new write path, and the heightfield work happens in C++.

enum Origin {
	POINT,   ## one stamp where you click
	LINE,    ## a path you draw, built along
}

## Authored resolution, per kind, because cost is quadratic in it and the right
## answer depends on how much ground the stamp covers.
##
## sculpt.gd upsamples anything under 1024 for Terrain3D, so this is about how
## much shape there is to describe, not about the final texture. A 280 m group
## of mounds at 160 across is 1.75 m per pixel -- finer than the 2 m terrain it
## lands on, so more would be describing detail the ground cannot hold. A
## 1240 m mountain needs the full 256 and is still coarser than the terrain,
## which is fine: its ridges are tens of metres wide.
const RES_DEFAULT := 160
const RES_BY_KIND := {
	"lone_mountain": 256,
	"border_wall": 256,
}

## Images are a quarter to a megabyte each and a new one exists for every
## distinct combination of settings, so an afternoon of moving sliders would
## otherwise accumulate hundreds. Oldest out first.
const CACHE_LIMIT := 24

## Height in metres per unit of Terrain3D strength, from the measurement noted
## in sculpt.gd: strength is linear and unclamped, and ten applications at 100
## raised the ground 10 m. If stamps land at the wrong scale, this is the dial.
const STRENGTH_PER_METRE := 100.0

const VARIANTS := 3

## Spacing between stamps along a drawn path, as a fraction of the stamp's own
## length. Below about a third they merge into a continuous form; above it the
## lobes read as separate.
const LINE_STEP := 0.30


## Every kind declares its own parameters, and the panel is built from the
## declaration. A parameter is {key, label, min, max, step, value, suffix, hint}.
const KINDS := {
	# ---------------------------------------------------- point, small ------
	"mounds": {
		"label": "Mounds",
		"tier": 1,
		"origin": Origin.POINT,
		"raises": true,
		"radius": 140.0,
		"height": 32.0,
		"hint": "Scattered smooth bodies. Low and domed is a kopje; steep-sided is a mogote.",
		"params": [
			{"key": "steepness", "label": "Steepness", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.35, "suffix": "",
				"hint": "Low is a kopje, broad and domed. High is a mogote, steep-sided and abrupt."},
			{"key": "count", "label": "Count", "min": 1.0, "max": 7.0,
				"step": 1.0, "value": 4.0, "suffix": "",
				"hint": "How many bodies in the group. They merge where they overlap."},
			{"key": "scatter", "label": "Scatter", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.6, "suffix": "",
				"hint": "How far the group spreads. Zero stacks them into one mass."},
		],
	},

	# ---------------------------------------------------- point, large ------
	"lone_mountain": {
		"label": "Lone Mountain",
		"tier": 1,
		"origin": Origin.POINT,
		"raises": true,
		"radius": 620.0,
		"height": 300.0,
		"hint": "A massif standing alone: central peak, radiating ridges, gullies between. An inselberg.",
		"params": [
			{"key": "ridges", "label": "Ridges", "min": 3.0, "max": 12.0,
				"step": 1.0, "value": 7.0, "suffix": "",
				"hint": "Spurs radiating from the peak. The count reads clearly from above."},
			{"key": "gullies", "label": "Gullies", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.55, "suffix": "",
				"hint": "How deeply the ground between the ridges is cut."},
			{"key": "peak", "label": "Peak", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.5, "suffix": "",
				"hint": "Low is a broad summit. High draws it to a point."},
		],
	},

	# ----------------------------------------------------- line, small ------
	"bluff": {
		"label": "Bluff",
		"tier": 1,
		"origin": Origin.LINE,
		"raises": true,
		"radius": 110.0,
		"height": 55.0,
		"hint": "A steep face inside a zone, built from merged lobes. A bluff or scarp.",
		"params": [
			{"key": "face", "label": "Face", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.7, "suffix": "",
				"hint": "Steepness of the front. High is nearly a wall; low is a bank."},
			{"key": "lobes", "label": "Lobes", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.5, "suffix": "",
				"hint": "How much each body along the line stands out from its neighbours."},
			{"key": "back", "label": "Back slope", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.45, "suffix": "",
				"hint": "How far the ground behind the face runs before it comes down."},
		],
	},

	# ----------------------------------------------------- line, large ------
	"border_wall": {
		"label": "Border Wall",
		"tier": 1,
		"origin": Origin.LINE,
		"raises": true,
		"radius": 320.0,
		"height": 360.0,
		"hint": "A continuous barrier closing the playable space. An escarpment or cordillera.",
		"params": [
			{"key": "crest", "label": "Crest", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.6, "suffix": "",
				"hint": "Low is a plateau top. High is a jagged skyline of separate peaks."},
			{"key": "roughness", "label": "Roughness", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.5, "suffix": "",
				"hint": "Break-up of the flanks. Zero is a smooth ramp."},
			{"key": "skew", "label": "Skew", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.3, "suffix": "",
				"hint": "Leans the section, so the outer side falls away more steeply than the inner."},
		],
	},

	# ------------------------------------------------------- untiered -------
	# Not rises, so not Tier 1. They belong to tiers that do not exist yet --
	# depressions and surface variation -- and are kept because they work, not
	# because they have been placed.
	"basin": {
		"label": "Basin",
		"tier": 0,
		"origin": Origin.POINT,
		"raises": false,
		"radius": 320.0,
		"height": 45.0,
		"hint": "A bowl. Where a lake goes.",
		"params": [
			{"key": "flatness", "label": "Floor", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.6, "suffix": "",
				"hint": "How broad and flat the bottom is, as against coming to a point."},
		],
	},
	"dunes": {
		"label": "Dunes",
		"tier": 0,
		"origin": Origin.POINT,
		"raises": true,
		"radius": 420.0,
		"height": 20.0,
		"hint": "Low rolling variation. Breaks up flat ground.",
		"params": [
			{"key": "scale", "label": "Scale", "min": 0.0, "max": 1.0,
				"step": 0.05, "value": 0.5, "suffix": "",
				"hint": "Coarse and few, or fine and many."},
		],
	},
}


static var _cache: Dictionary = {}


static func has(kind: String) -> bool:
	return KINDS.has(kind)


static func label_of(kind: String) -> String:
	return String(KINDS[kind]["label"]) if KINDS.has(kind) else kind


static func raises(kind: String) -> bool:
	return bool(KINDS[kind]["raises"]) if KINDS.has(kind) else true


static func origin_of(kind: String) -> int:
	return int(KINDS[kind]["origin"]) if KINDS.has(kind) else Origin.POINT


static func is_line(kind: String) -> bool:
	return origin_of(kind) == Origin.LINE


## Defaults for a kind, as the panel and the tool both need them.
static func default_params(kind: String) -> Dictionary:
	var out: Dictionary = {}
	if not KINDS.has(kind):
		return out
	for p in KINDS[kind]["params"]:
		out[String(p["key"])] = float(p["value"])
	return out


# ------------------------------------------------------------- generation --

## Noise as a byte field, sampled by index rather than by call.
##
## FastNoiseLite.get_image builds the whole field in C++. Asking it for one
## value at a time instead means RES x RES calls across the binding for every
## octave of every brush, which was most of what generating one cost.
static func _field(p_seed: int, features: float, res: int) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = p_seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.frequency = features / float(res)
	return n.get_image(res, res, false, false, true).get_data()


static func res_for(kind: String) -> int:
	return int(RES_BY_KIND.get(kind, RES_DEFAULT))


static func _key(kind: String, variant: int, params: Dictionary) -> String:
	# Parameters are part of the identity: two mountains with different ridge
	# counts are different brushes, and caching them under one name would serve
	# whichever was asked for first.
	var parts := PackedStringArray()
	var keys := params.keys()
	keys.sort()
	for k in keys:
		parts.append("%s=%.3f" % [k, float(params[k])])
	return "%s|%d|%s" % [kind, variant, "&".join(parts)]


## [Image, ImageTexture] for one landform, generated on first use and kept.
static func brush_for(kind: String, variant: int, params: Dictionary) -> Array:
	if not KINDS.has(kind):
		kind = "mounds"
	var key := _key(kind, variant, params)
	if _cache.has(key):
		return _cache[key]

	var res := res_for(kind)
	var seed_v := hash(key)
	var coarse := _field(seed_v, 3.0, res)
	var fine := _field(seed_v ^ 0x9E3779B9, 8.0, res)

	var buf := PackedFloat32Array()
	buf.resize(res * res)

	# Mound centres are chosen once rather than per pixel.
	var centres := _mound_centres(kind, seed_v, params)

	var inv := 2.0 / float(res)
	var peak := 0.0
	for y in res:
		var v := (float(y) + 0.5) * inv - 1.0
		var row := y * res
		for x in res:
			var u := (float(x) + 0.5) * inv - 1.0
			var i := row + x
			var h := _profile(kind, u, v, params,
				float(coarse[i]) / 127.5 - 1.0, float(fine[i]) / 127.5 - 1.0, centres)
			buf[i] = h
			if h > peak:
				peak = h

	# Normalised so a profile actually reaches 1. Otherwise the Height control
	# lies: an envelope that crests at 0.77 makes a 340 m wall 263 m tall and
	# nothing on screen says so.
	if peak > 0.0 and not is_equal_approx(peak, 1.0):
		var k := 1.0 / peak
		for i in buf.size():
			buf[i] *= k

	var img := Image.create_from_data(res, res, false, Image.FORMAT_RF, buf.to_byte_array())
	var entry := [img, ImageTexture.create_from_image(img)]
	if _cache.size() >= CACHE_LIMIT:
		_cache.erase(_cache.keys()[0])
	_cache[key] = entry
	return entry


static func _mound_centres(kind: String, p_seed: int, params: Dictionary) -> PackedVector3Array:
	var out := PackedVector3Array()
	if kind != "mounds":
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	var count := int(params.get("count", 4.0))
	var scatter: float = params.get("scatter", 0.6)
	for i in count:
		# Polar placement, so the group stays round rather than filling a square.
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * scatter * 0.62
		# z carries each body's own size, so a group is not all one lump repeated.
		out.append(Vector3(cos(a) * d, sin(a) * d, rng.randf_range(0.42, 0.80)))
	return out


## Height profile over the unit square, 0 at the rim and 1 at the peak.
##
## For a LINE kind, u runs along the path and v across it, so the same function
## describes a cross-section walked along a curve.
##
## Everything is masked to zero before the edge. A stamp that does not reach
## zero leaves a cliff at the brush boundary, and that one artefact is what
## makes placed terrain read as placed.
static func _profile(kind: String, u: float, v: float, params: Dictionary,
		n_coarse: float, n_fine: float, centres: PackedVector3Array) -> float:
	var h := 0.0

	match kind:
		"mounds":
			# Maximum over the group, not a sum: overlapping bodies should merge
			# into one mass with a saddle between, the way rock actually does,
			# rather than piling into a single taller heap where they cross.
			var steep: float = params.get("steepness", 0.35)
			var exp_k := 0.75 + steep * 2.6
			for c in centres:
				var dx := u - c.x
				var dy := v - c.y
				var d := sqrt(dx * dx + dy * dy) / maxf(0.08, c.z * 0.55)
				if d >= 1.0:
					continue
				h = maxf(h, pow(1.0 - d, exp_k))
			h *= 1.0 + n_fine * 0.10

		"lone_mountain":
			var r := sqrt(u * u + v * v)
			var ridges: float = params.get("ridges", 7.0)
			var gullies: float = params.get("gullies", 0.55)
			var pk: float = params.get("peak", 0.5)

			# Spurs are angular, so they come from the angle rather than from
			# noise. Noise only wobbles the phase, which is what stops the
			# result looking like a cog.
			var ang := atan2(v, u) + n_coarse * 0.55
			var spur := 0.5 + 0.5 * cos(ang * ridges)
			# Flanks only. A summit crossed by spokes looks like a starfish.
			var flank := smoothstep(0.0, 0.42, r)

			h = pow(maxf(0.0, 1.0 - r), 1.15 + pk * 1.5)
			h *= 1.0 - gullies * 0.42 * (1.0 - spur) * flank
			h *= 1.0 + n_fine * 0.13 * flank

		"bluff":
			# Line kind: u along the path, v across it.
			var face: float = params.get("face", 0.7)
			var back: float = params.get("back", 0.45)
			var lobes: float = params.get("lobes", 0.5)
			var t := (v + 1.0) * 0.5

			# Front rises hard, top runs, back comes down gently. The width of
			# the rise IS the face steepness.
			var rise := smoothstep(0.46 - 0.20 * face, 0.48, t)
			var fall := 1.0 - smoothstep(0.62 + back * 0.30, 1.0, t)
			h = rise * fall

			# Along the line: a flat run that tapers at each end so consecutive
			# stamps merge, modulated so the lobes read as separate bodies.
			h *= smoothstep(1.0, 0.70, absf(u))
			h *= 1.0 - lobes * 0.34 * (0.5 + 0.5 * cos(u * PI * 2.2 + n_coarse * 2.0))
			h *= 1.0 + n_fine * 0.10

		"border_wall":
			var crest: float = params.get("crest", 0.6)
			var rough: float = params.get("roughness", 0.5)
			var skew: float = params.get("skew", 0.3)

			# Leaned across the section, so the outer face is the steeper one.
			var vv := clampf(v + skew * 0.22, -1.0, 1.0)
			var a := clampf(1.0 - absf(vv) / 0.90, 0.0, 1.0)

			var plateau := smoothstep(0.90, 0.56, absf(vv))
			var jag := pow(a, 1.45) * (0.60 + 0.55 * (1.0 - absf(n_coarse)))
			h = lerp(plateau, jag, crest)

			# Summits along the ridge rather than one unbroken roof.
			h *= 0.80 + 0.30 * (0.5 + 0.5 * sin(u * PI * 2.6 + n_coarse * 2.4))
			h *= 1.0 + n_fine * 0.22 * rough
			h *= smoothstep(1.0, 0.74, absf(u))

		"basin":
			var r2 := sqrt(u * u + v * v)
			var flat: float = params.get("flatness", 0.6)
			h = pow(maxf(0.0, 1.0 - r2 * r2), 1.15 - flat * 0.70)
			h *= 1.0 + n_coarse * 0.10

		"dunes":
			var sc: float = params.get("scale", 0.5)
			var g := lerp(n_coarse, n_fine, sc)
			h = 0.5 + 0.5 * g
			h = h * h

		_:
			h = maxf(0.0, 1.0 - (u * u + v * v))

	# Hard mask to zero before the rim, whatever the profile did. Line kinds
	# taper along their own axis above, so only the across-axis needs it here.
	var mask := 0.0
	if is_line(kind):
		mask = smoothstep(1.0, 0.90, absf(v))
	else:
		mask = smoothstep(1.0, 0.88, sqrt(u * u + v * v))
	return clampf(h, 0.0, 1.0) * mask
