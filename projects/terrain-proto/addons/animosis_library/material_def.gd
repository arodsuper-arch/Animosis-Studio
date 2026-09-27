@tool
extends RefCounted
## A library material.
##
## Animosis does NOT author materials. Substance does. This is a catalog entry:
## it points at imported maps, carries the properties runtime systems read, and
## declares how the material looks under each runtime effect.
##
## Three parts, consumed by three different things:
##
##   SOURCE      imported map paths. Read by the renderer and Terrain3D.
##               Never edited here -- reimport from Substance instead.
##
##   PROPERTIES  the block from terrain-and-sites-spec.md §3.2. Read HEADLESSLY
##               by fire, destruction, deformation and fluid, with no texture
##               ever loaded.
##
##   EFFECTS     how this material appears in each runtime state.
##
## The effects table is the important one. Fire on timber, fire on grass and
## fire on cloth all look different -- but the fire system must not know cloth
## exists. So fire sets the STATE, and the material declares the APPEARANCE.
## Adding a material gives it fire, wetness and freezing behaviour the moment it
## declares them, and adding an effect works across every material at once.
## That is Principle 1 applied to what you see rather than what you simulate.

## Simulation properties: key -> [label, min, max, default, unit].
const PROPERTIES := {
	"hardness":     ["Hardness",     0.0, 1.0, 0.50, ""],
	"flammability": ["Flammability", 0.0, 1.0, 0.00, ""],
	"ignitionTemp": ["Ignition",     0.0, 1200.0, 300.0, " °C"],
	"burnRate":     ["Burn rate",    0.0, 1.0, 0.00, ""],
	"integrity":    ["Integrity",    0.0, 1.0, 0.50, ""],
	"mass":         ["Density",      0.0, 8000.0, 1500.0, " kg/m³"],
	"porosity":     ["Porosity",     0.0, 1.0, 0.20, ""],
	"conductivity": ["Conductivity", 0.0, 1.0, 0.10, ""],
	"friction":     ["Friction",     0.0, 1.0, 0.60, ""],
}

## Runtime channels, written during play, never authored.
const RUNTIME_CHANNELS := ["wetness", "temperature", "charred"]

## The effect states a material may declare an appearance for. Driven by the
## capability that writes them, so a project with fire.spread disabled simply
## never reaches the burning entry.
const EFFECTS := {
	"burning": ["Burning", "fire.spread"],
	"charred": ["Charred", "fire.spread"],
	"wet":     ["Wet",     "weather.wetness"],
	"frozen":  ["Frozen",  "weather.wetness"],
}

## An effect appearance. Either a cheap shift of the base material, or a second
## imported material to blend toward when the shift is not enough -- burning
## cloth needs different maps, burning rock only needs to glow.
##   blend: 0 = base unchanged, 1 = fully the effect appearance
class EffectState:
	extends RefCounted
	var enabled: bool = false
	var tint: Color = Color.WHITE
	var emission: float = 0.0
	var roughness_shift: float = 0.0
	var material_ref: String = ""   ## optional imported material to blend toward

	func to_dict() -> Dictionary:
		return {
			"enabled": enabled,
			"tint": tint.to_html(false),
			"emission": emission,
			"roughnessShift": roughness_shift,
			"materialRef": material_ref,
		}


var id: String = "animosis.material.new"
var display_name: String = "New Material"
var category: String = "terrain"   ## terrain | model

## Where Substance output landed. Read-only in the tool.
var source_path: String = ""
var maps: Dictionary = { "albedo": "", "normal": "", "roughness": "", "height": "" }
var uv_scale: float = 0.10
var triplanar: bool = true

var properties: Dictionary = {}
var effects: Dictionary = {}

## What currently references this material. Populated by scanning consumers;
## a material nothing uses is a candidate for removal.
var used_by: Array = []   ## untyped: assigned from plain literals in defaults()


func _init(p_name: String = "New Material") -> void:
	display_name = p_name
	id = "animosis.material." + p_name.to_lower().replace(" ", "_")
	for key in PROPERTIES:
		properties[key] = PROPERTIES[key][3]
	for key in EFFECTS:
		effects[key] = EffectState.new()


func effect(key: String) -> EffectState:
	return effects.get(key)


## The shape that ships in the content manifest. Animosis Core parses this and
## must never need a renderer to do so.
func to_dict() -> Dictionary:
	var fx := {}
	for key in effects:
		fx[key] = effects[key].to_dict()
	return {
		"id": id,
		"name": display_name,
		"category": category,
		"source": source_path,
		"visual": { "maps": maps.duplicate(), "uvScale": uv_scale, "triplanar": triplanar },
		"properties": properties.duplicate(),
		"effects": fx,
	}


## Placeholder catalog until Substance import exists. These carry realistic
## effect appearances so the model is legible: note that burning grass, burning
## timber and burning cloth differ, while the fire system driving them does not.
static func defaults() -> Array:
	var out: Array = []

	var grass = new("Grass")
	grass.category = "terrain"
	grass.used_by = ["region 0,0", "region 1,0"]
	grass.properties["hardness"] = 0.15
	grass.properties["flammability"] = 0.65
	grass.properties["friction"] = 0.70
	grass.properties["mass"] = 400.0
	_fx(grass, "burning", Color("#FF7A3C"), 2.2, -0.15)
	_fx(grass, "charred", Color("#2A2622"), 0.0, 0.25)
	_fx(grass, "wet", Color("#8FA37F"), 0.0, -0.35)
	out.append(grass)

	var rock = new("Rock")
	rock.category = "terrain"
	rock.used_by = ["region 0,0"]
	rock.properties["hardness"] = 0.95
	rock.properties["flammability"] = 0.0
	rock.properties["integrity"] = 0.90
	rock.properties["mass"] = 2600.0
	# Rock does not burn, but it glows when hot -- the same effect key, a very
	# different appearance, declared by the material rather than by fire.
	_fx(rock, "burning", Color("#FF5A2A"), 1.1, 0.0)
	_fx(rock, "wet", Color("#6E7276"), 0.0, -0.45)
	out.append(rock)

	var timber = new("Timber")
	timber.category = "model"
	timber.used_by = ["building.cottage", "building.palisade"]
	timber.properties["hardness"] = 0.35
	timber.properties["flammability"] = 0.85
	timber.properties["ignitionTemp"] = 250.0
	timber.properties["burnRate"] = 0.60
	timber.properties["integrity"] = 0.45
	timber.properties["mass"] = 600.0
	_fx(timber, "burning", Color("#FF9440"), 3.0, -0.20)
	_fx(timber, "charred", Color("#1E1B19"), 0.0, 0.40)
	_fx(timber, "wet", Color("#5C4A38"), 0.0, -0.30)
	out.append(timber)

	var cloth = new("Cloth")
	cloth.category = "model"
	cloth.used_by = ["character.commoner"]
	cloth.properties["hardness"] = 0.05
	cloth.properties["flammability"] = 0.90
	cloth.properties["ignitionTemp"] = 200.0
	cloth.properties["burnRate"] = 0.85
	cloth.properties["integrity"] = 0.10
	cloth.properties["mass"] = 150.0
	_fx(cloth, "burning", Color("#FFB05A"), 2.6, -0.10)
	_fx(cloth, "charred", Color("#26211E"), 0.0, 0.30)
	_fx(cloth, "wet", Color("#6A6256"), 0.0, -0.50)
	out.append(cloth)

	return out


static func _fx(mat, key: String, tint: Color, emission: float, rough: float) -> void:
	var e = mat.effects[key]
	e.enabled = true
	e.tint = tint
	e.emission = emission
	e.roughness_shift = rough
