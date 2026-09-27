extends SceneTree
## Throwaway: cost of flooding a basin, against a synthetic bowl so it runs
## headless. Terrain3D cannot build without a renderer.

const Water := preload("res://addons/animosis_terrain/water.gd")


class FakeData:
	extends RefCounted
	## A bowl: 65 m at the centre rising to ~205 m at the rim, plus ripple so the
	## shoreline is not a perfect circle.
	func get_height(p: Vector3) -> float:
		var r: float = sqrt(p.x * p.x + p.z * p.z) / 2048.0
		return 65.0 + 140.0 * r * r + sin(p.x * 0.004) * cos(p.z * 0.005) * 6.0


class FakeTerrain:
	extends Node
	var data := FakeData.new()


func _initialize() -> void:
	var t := FakeTerrain.new()
	var layer = Water.new()
	get_root().add_child(layer)
	layer.configure(t, 4096.0)
	layer.set_visible_overlay(true)

	print("depth |   cells |   km2 |  fill ms | quads")
	for depth in [3.0, 10.0, 30.0, 80.0, 140.0]:
		var b = layer.bodies[1]
		b.auto_level = false
		b.levelled = true
		b.level = 65.0 + depth

		var t0 := Time.get_ticks_usec()
		var n: int = layer.fill(Vector3.ZERO, 1)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0

		var quads := 0
		for c in layer.get_children():
			var mi := c as MeshInstance3D
			if mi and mi.mesh and mi.mesh.get_surface_count() > 0:
				quads += mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 6
		print("%5.0f | %7d | %5.2f | %8.0f | %6d"
			% [depth, n, float(n) * 64.0 / 1e6, ms, quads])
	quit()
