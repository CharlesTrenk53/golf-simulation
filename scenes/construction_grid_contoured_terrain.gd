extends Node3D

# POC-30D: Center-Anchored Contoured Terrain
# -------------------------------------------
# Presentation-only terrain projection of CourseConstructionGrid elevation data.
# The construction grid remains authoritative. Each authored tile elevation is
# preserved exactly at its tile center, while shared edges and corners are
# averaged deterministically so adjacent rendered cells cannot split apart.
#
# This mesh is deliberately independent of surface ownership. POC-30F can place
# it beneath the topology-softened surface layer as the common landform without
# allowing visual terrain to become lie, hazard, scoring, or shot authority.

const SUBDIVISIONS_PER_CELL: int = 2
const TRIANGLES_PER_CELL: int = SUBDIVISIONS_PER_CELL * SUBDIVISIONS_PER_CELL * 2

var construction_grid = null
var terrain_visual: MeshInstance3D = null
var rendered_cells: int = 0
var rendered_triangles: int = 0


func render_grid(grid) -> bool:
	clear_terrain()
	if grid == null or grid.width <= 0 or grid.height <= 0 or grid.tile_size_yards <= 0.0:
		return false

	construction_grid = grid
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for y in range(int(grid.height)):
		for x in range(int(grid.width)):
			_append_cell(vertices, normals, x, y)
			rendered_cells += 1

	if vertices.is_empty():
		return false

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _terrain_material())

	terrain_visual = MeshInstance3D.new()
	terrain_visual.name = "ContouredTerrain"
	terrain_visual.mesh = mesh
	terrain_visual.set_meta("classification", "CONTOURED_TERRAIN")
	terrain_visual.set_meta("source", "construction_grid_elevation")
	terrain_visual.set_meta("visual_projection", "center_anchored_contours")
	terrain_visual.set_meta("cell_count", rendered_cells)
	terrain_visual.set_meta("triangles_per_cell", TRIANGLES_PER_CELL)
	terrain_visual.set_meta("triangle_count", rendered_triangles)
	add_child(terrain_visual)
	return true


func clear_terrain() -> void:
	if terrain_visual != null:
		remove_child(terrain_visual)
		terrain_visual.queue_free()
	terrain_visual = null
	construction_grid = null
	rendered_cells = 0
	rendered_triangles = 0


func terrain_height_at_grid_corner(corner_x: int, corner_y: int) -> float:
	if construction_grid == null:
		return 0.0
	var elevations: Array[float] = []
	for tile_y_value in [corner_y - 1, corner_y]:
		var tile_y: int = int(tile_y_value)
		for tile_x_value in [corner_x - 1, corner_x]:
			var tile_x: int = int(tile_x_value)
			if construction_grid.is_in_bounds(tile_x, tile_y):
				elevations.append(_tile_elevation(tile_x, tile_y))
	return _average(elevations)


func terrain_height_at_cell_uv(cell_x: int, cell_y: int, u_value: float, v_value: float) -> float:
	if construction_grid == null or not construction_grid.is_in_bounds(cell_x, cell_y):
		return 0.0

	var u: float = clampf(u_value, 0.0, 1.0)
	var v: float = clampf(v_value, 0.0, 1.0)
	var center: float = _tile_elevation(cell_x, cell_y)
	var north: float = _edge_midpoint_height(cell_x, cell_y, "N")
	var east: float = _edge_midpoint_height(cell_x, cell_y, "E")
	var south: float = _edge_midpoint_height(cell_x, cell_y, "S")
	var west: float = _edge_midpoint_height(cell_x, cell_y, "W")
	var nw: float = terrain_height_at_grid_corner(cell_x, cell_y)
	var ne: float = terrain_height_at_grid_corner(cell_x + 1, cell_y)
	var se: float = terrain_height_at_grid_corner(cell_x + 1, cell_y + 1)
	var sw: float = terrain_height_at_grid_corner(cell_x, cell_y + 1)

	if u <= 0.5 and v <= 0.5:
		return _bilinear(nw, north, west, center, u * 2.0, v * 2.0)
	if u > 0.5 and v <= 0.5:
		return _bilinear(north, ne, center, east, (u - 0.5) * 2.0, v * 2.0)
	if u > 0.5 and v > 0.5:
		return _bilinear(center, east, south, se, (u - 0.5) * 2.0, (v - 0.5) * 2.0)
	return _bilinear(west, center, sw, south, u * 2.0, (v - 0.5) * 2.0)


func rendered_vertex_count() -> int:
	if terrain_visual == null or terrain_visual.mesh == null:
		return 0
	var arrays: Array = terrain_visual.mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return 0
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return vertices.size()


func _append_cell(vertices: PackedVector3Array, normals: PackedVector3Array, cell_x: int, cell_y: int) -> void:
	for sub_y in range(SUBDIVISIONS_PER_CELL):
		for sub_x in range(SUBDIVISIONS_PER_CELL):
			var u0: float = float(sub_x) / float(SUBDIVISIONS_PER_CELL)
			var u1: float = float(sub_x + 1) / float(SUBDIVISIONS_PER_CELL)
			var v0: float = float(sub_y) / float(SUBDIVISIONS_PER_CELL)
			var v1: float = float(sub_y + 1) / float(SUBDIVISIONS_PER_CELL)
			var p00: Vector3 = _cell_uv_to_world(cell_x, cell_y, u0, v0)
			var p10: Vector3 = _cell_uv_to_world(cell_x, cell_y, u1, v0)
			var p11: Vector3 = _cell_uv_to_world(cell_x, cell_y, u1, v1)
			var p01: Vector3 = _cell_uv_to_world(cell_x, cell_y, u0, v1)
			_append_triangle(vertices, normals, p00, p11, p10)
			_append_triangle(vertices, normals, p00, p01, p11)
			rendered_triangles += 2


func _cell_uv_to_world(cell_x: int, cell_y: int, u: float, v: float) -> Vector3:
	var size: float = float(construction_grid.tile_size_yards)
	return Vector3(
		float(construction_grid.origin.x) + (float(cell_x) + u) * size,
		terrain_height_at_cell_uv(cell_x, cell_y, u, v),
		float(construction_grid.origin.y) + (float(cell_y) + v) * size
	)


func _edge_midpoint_height(cell_x: int, cell_y: int, direction: String) -> float:
	var neighbor := Vector2i(cell_x, cell_y)
	match direction:
		"N":
			neighbor.y -= 1
		"E":
			neighbor.x += 1
		"S":
			neighbor.y += 1
		"W":
			neighbor.x -= 1
	var own: float = _tile_elevation(cell_x, cell_y)
	if not construction_grid.is_in_bounds(neighbor.x, neighbor.y):
		return own
	return (own + _tile_elevation(neighbor.x, neighbor.y)) * 0.5


func _tile_elevation(x: int, y: int) -> float:
	return float(construction_grid.tile_at(x, y).get("elevation", 0.0))


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / float(values.size())


func _bilinear(nw: float, ne: float, sw: float, se: float, u: float, v: float) -> float:
	var north: float = lerpf(nw, ne, u)
	var south: float = lerpf(sw, se, u)
	return lerpf(north, south, v)


func _append_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)


func _terrain_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.39, 0.16)
	material.roughness = 0.98
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
