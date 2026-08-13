extends Node3D

# POC-22D: Construction Grid -> Course Renderer
# ----------------------------------------------
# Visual projection of the authoritative player-buildable construction grid.
# The grid remains the source of truth. This renderer groups tiles by surface
# into lightweight meshes and derives corner heights from authored tile
# elevations so neighboring tiles share a continuous terrain edge.

const SURFACE_ORDER := ["ROUGH", "FAIRWAY", "TEE", "GREEN", "BUNKER", "WATER"]
const SURFACE_HEIGHT_OFFSET := {
	"ROUGH": 0.000,
	"FAIRWAY": 0.015,
	"TEE": 0.020,
	"GREEN": 0.025,
	"BUNKER": -0.030,
	"WATER": -0.060
}

var construction_grid = null
var rendered_surfaces: Array = []


func render_grid(grid) -> bool:
	clear_grid()
	if grid == null or grid.width <= 0 or grid.height <= 0 or grid.tile_size_yards <= 0.0:
		return false

	construction_grid = grid
	for surface_value in SURFACE_ORDER:
		var surface: String = str(surface_value)
		var tile_count: int = int(grid.count_surface(surface))
		if tile_count <= 0:
			continue
		_add_surface_mesh(surface, tile_count)
	return not rendered_surfaces.is_empty()


func clear_grid() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	rendered_surfaces.clear()
	construction_grid = null


func surface_visual(surface: String) -> Node3D:
	var normalized: String = surface.to_upper()
	for child in get_children():
		if child is Node3D and str(child.get_meta("classification", "")) == normalized:
			return child
	return null


func rendered_tile_count(surface: String) -> int:
	var visual: Node3D = surface_visual(surface)
	if visual == null:
		return 0
	return int(visual.get_meta("tile_count", 0))


func terrain_height_at_grid_corner(corner_x: int, corner_y: int) -> float:
	if construction_grid == null:
		return 0.0
	var elevations: Array[float] = []
	for tile_y_value in [corner_y - 1, corner_y]:
		var tile_y: int = int(tile_y_value)
		for tile_x_value in [corner_x - 1, corner_x]:
			var tile_x: int = int(tile_x_value)
			if construction_grid.is_in_bounds(tile_x, tile_y):
				elevations.append(float(construction_grid.tile_at(tile_x, tile_y).get("elevation", 0.0)))
	if elevations.is_empty():
		return 0.0
	var total: float = 0.0
	for elevation: float in elevations:
		total += elevation
	return total / float(elevations.size())


func _add_surface_mesh(surface: String, tile_count: int) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var size: float = float(construction_grid.tile_size_yards)
	var offset_y: float = float(SURFACE_HEIGHT_OFFSET.get(surface, 0.0))

	for y in range(int(construction_grid.height)):
		for x in range(int(construction_grid.width)):
			if str(construction_grid.surface_at(x, y)) != surface:
				continue

			var x0: float = float(construction_grid.origin.x) + float(x) * size
			var x1: float = x0 + size
			var z0: float = float(construction_grid.origin.y) + float(y) * size
			var z1: float = z0 + size

			var p00: Vector3 = Vector3(x0, terrain_height_at_grid_corner(x, y) + offset_y, z0)
			var p10: Vector3 = Vector3(x1, terrain_height_at_grid_corner(x + 1, y) + offset_y, z0)
			var p11: Vector3 = Vector3(x1, terrain_height_at_grid_corner(x + 1, y + 1) + offset_y, z1)
			var p01: Vector3 = Vector3(x0, terrain_height_at_grid_corner(x, y + 1) + offset_y, z1)

			_append_triangle(vertices, normals, p00, p11, p10)
			_append_triangle(vertices, normals, p00, p01, p11)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material_for_surface(surface))

	var visual := MeshInstance3D.new()
	visual.name = "%sSurface" % surface.capitalize()
	visual.mesh = mesh
	visual.set_meta("classification", surface)
	visual.set_meta("tile_count", tile_count)
	visual.set_meta("source", "construction_grid")
	add_child(visual)
	rendered_surfaces.append({
		"classification": surface,
		"tile_count": tile_count,
		"node": visual
	})


func _append_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)


func _material_for_surface(surface: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = _surface_color(surface)
	material.roughness = 0.95
	# Construction terrain is a visual projection of authoritative grid data.
	# Render both sides so camera orientation cannot accidentally make the entire
	# property disappear because of triangle winding/back-face culling.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _surface_color(surface_value: String) -> Color:
	match surface_value.to_upper():
		"TEE":
			return Color(0.30, 0.60, 0.27)
		"FAIRWAY":
			return Color(0.27, 0.58, 0.24)
		"GREEN":
			return Color(0.38, 0.68, 0.31)
		"ROUGH":
			return Color(0.19, 0.42, 0.18)
		"BUNKER":
			return Color(0.76, 0.65, 0.43)
		"WATER":
			return Color(0.16, 0.39, 0.61)
		_:
			return Color(0.22, 0.46, 0.20)
