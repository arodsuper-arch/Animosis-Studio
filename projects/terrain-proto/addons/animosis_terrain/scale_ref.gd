@tool
extends Node3D
## Size references — crude massing models placed in the world to answer "how big
## is this actually?".
##
## Terrain has no inherent scale: a ridge looks identical at 40 m or 400 m until
## something of known size stands beside it. These are deliberately untextured,
## unshaded blockouts. They are measuring sticks, not set dressing, and making
## them pretty would invite mistaking them for content.
##
## Each is built from primitives at real-world dimensions. Numbers are stated so
## they can be argued with rather than silently assumed.

enum Kind { PERSON, BUILDING, DRAGON }

const SPECS := {
	Kind.PERSON:   { "label": "Person",   "height": 1.8,  "colour": Color("#F2F2F2") },
	Kind.BUILDING: { "label": "Building", "height": 11.0, "colour": Color("#C9D4DE") },
	Kind.DRAGON:   { "label": "Dragon",   "height": 6.5,  "colour": Color("#E8C88A") },
}

var kind: Kind = Kind.PERSON


func _init(p_kind: Kind = Kind.PERSON) -> void:
	kind = p_kind
	name = "ScaleRef_" + String(SPECS[kind]["label"])
	visible = false
	_build()


func label() -> String:
	return SPECS[kind]["label"]


func height() -> float:
	return SPECS[kind]["height"]


func place_at(world: Vector3) -> void:
	if world.is_finite():
		global_position = world
		visible = true


# ------------------------------------------------------------- primitives --

func _mat(alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var c: Color = SPECS[kind]["colour"]
	c.a = alpha
	m.albedo_color = c
	m.disable_receive_shadows = true
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _piece(mesh: Mesh, pos: Vector3, rot := Vector3.ZERO, alpha := 1.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(alpha)
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _box(sx: float, sy: float, sz: float) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(sx, sy, sz)
	return m


func _capsule(h: float, r: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.height = h
	m.radius = r
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


## Footprint disc, so a reference reads as standing ON a slope rather than
## hovering somewhere near it.
func _base(radius: float) -> void:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 0.03
	_piece(m, Vector3(0, 0.02, 0), Vector3.ZERO, 0.30)


func _build() -> void:
	match kind:
		Kind.PERSON:
			_build_person()
		Kind.BUILDING:
			_build_building()
		Kind.DRAGON:
			_build_dragon()


## 1.8 m adult.
func _build_person() -> void:
	_piece(_capsule(1.5, 0.19), Vector3(0, 0.75, 0))
	_piece(_sphere(0.15), Vector3(0, 1.65, 0))
	_base(0.38)


## Three storeys to a pitched ridge: 12 x 9 m footprint, 7.5 m eaves, 11 m ridge.
## A believable town building rather than a warehouse or a tower.
func _build_building() -> void:
	_piece(_box(12.0, 7.5, 9.0), Vector3(0, 3.75, 0))

	var roof := PrismMesh.new()
	roof.size = Vector3(12.0, 3.5, 9.0)
	_piece(roof, Vector3(0, 9.25, 0))

	# Floor lines, so storeys are countable at a glance and the scale reads
	# without measuring.
	for storey in [2.5, 5.0]:
		_piece(_box(12.2, 0.12, 9.2), Vector3(0, storey, 0), Vector3.ZERO, 0.55)

	_base(8.0)


## Large winged predator: ~16 m nose to tail, ~20 m wingspan, 6.5 m to the head.
## Sized as a serious boss creature -- big enough that terrain built for humans
## visibly fails to accommodate it, which is the point of checking.
func _build_dragon() -> void:
	# Body, lying along Z.
	_piece(_capsule(7.0, 1.3), Vector3(0, 3.0, 0), Vector3(PI * 0.5, 0, 0))

	# Neck rising forward, then the head.
	_piece(_capsule(4.0, 0.62), Vector3(0, 4.6, -4.0), Vector3(deg_to_rad(55), 0, 0))
	_piece(_box(1.5, 1.0, 2.4), Vector3(0, 6.0, -5.9))

	# Tail, tapering in two segments.
	_piece(_capsule(5.0, 0.72), Vector3(0, 2.9, 4.6), Vector3(deg_to_rad(80), 0, 0))
	_piece(_capsule(4.5, 0.30), Vector3(0, 2.4, 8.2), Vector3(deg_to_rad(70), 0, 0))

	# Wings: flat planes swept up and out, 20 m tip to tip.
	for side in [-1.0, 1.0]:
		_piece(_box(8.0, 0.18, 4.6), Vector3(side * 5.2, 4.6, -0.4),
			   Vector3(0, 0, side * deg_to_rad(-18)), 0.85)

	# Four legs.
	for sx in [-1.0, 1.0]:
		for sz in [-1.6, 2.4]:
			_piece(_capsule(3.0, 0.42), Vector3(sx * 1.5, 1.5, sz))

	_base(6.5)
