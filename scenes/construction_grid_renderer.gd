extends Node3D

# POC-22D / POC-30A / POC-30B: Construction Grid -> Course Renderer
# ------------------------------------------------------------------
# Visual projection of the authoritative player-buildable construction grid.
# The grid remains the source of truth. This renderer groups tiles by surface
# into lightweight meshes and derives corner heights from authored tile
# elevations so neighboring tiles share a continuous terrain edge.
#
# POC-30A adds FRINGE as a first-class rendered construction surface.
# POC-30B makes non-rough surface footprints neighborhood-aware: adjoining
# cells remain visually continuous, exposed edges pull inward slightly, and
# exposed outside corners are softened. Every generated footprint stays inside
# its authoritative source cell. ROUGH remains the continuous base terrain so
# presentation can soften overlays without creating a second course truth.

const SURFACE_ORDER := ["ROUGH", "FAIRWAY", "TEE", "FRINGE", "GREEN", "BUNKER", "WATER"]
const SURFACE_HEIGHT_OFFSET := {
	"ROUGH": 0.000,
	"FAIRWAY": 0.015,
	"TEE": 0.020,
	"GREEN": 0.025,
	"FRINGE": 0.022,
	"BUNKER": -0.030,
	"WATER": -0.060
}
const EDGE_INSET_RATIO: float = 0.12
const CORNER_SOFTEN_RATIO: float = 0.16

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


func softened_boundary_cell_count(surface: String) -> int:
	var visual: Node3D = surface_visual(surface)
	if visual == null:
		return 0
	return int(visual.get_meta("softened_boundary_cells", 0))


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


# Returns a convex local-space X/Z footprint for one authoritative cell.
# The polygon never leaves [0, tile_size] in either axis. Same-surface cardinal
# neighbors keep their shared edge flush; different-surface edges pull inward.
# When two adjacent edges are exposed, the outside corner becomes a two-point
# bevel instead of a square 90-degree corner. POC-30C can later replace this
# simple deterministic bevel with richer transition geometry without changing
# grid ownership or the public topology contract.
func visual_footprint_for_cell(x: int, y: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	if construction_grid == null or not construction_grid.is_in_bounds(x, y):
		return points

	var size: float = float(construction_grid.tile_size_yards)
	var surface: String = str(construction_grid.surface_at(x, y))
	if surface == "ROUGH":
		return PackedVector2Array([
			Vector2(0.0, 0.0),
			Vector2(size, 0.0),
			Vector2(size, size),
			Vector2(0.0, size)
		])

	var same: Dictionary = construction_grid.same_surface_neighbors(x, y)
	var north_same: bool = bool(same.get("N", false))
	var east_same: bool = bool(same.get("E", false))
	var south_same: bool = bool(same.get("S", false))
	var west_same: bool = bool(same.get("W", false))
	var inset: float = size * EDGE_INSET_RATIO
	var soften: float = size * CORNER_SOFTEN_RATIO

	var left: float = 0.0 if west_same else inset
	var right: float = size if east_same else size - inset
	var top: float = 0.0 if north_same else inset
	var bottom: float = size if south_same else size - inset
	var max_soften: float = minf((right - left) * 0.45, (bottom - top) * 0.45)
	soften = minf(soften, max_soften)

	# Clockwise when viewed from above in the renderer's X/Z coordinate plane.
	if not north_same and not west_same:
		points.append(Vector2(left + soften, top))
		points.append(Vector2(left, top + soften))
	else:
		points.append(Vector2(left, top))

	if not north_same and not east_same:
		points.append(Vector2(right - soften, top))
		points.append(Vector2(right, top + soften))
	else:
		points.append(Vector2(right, top))

	if not south_same and not east_same:
		points.append(Vector2(right, bottom - soften))
		points.append(Vector2(right - soften, bottom))
	else:
		points.append(Vector2(right, bottom))

	if not south_same and not west_same:
		points.append(Vector2(left + soften, bottom))
		points.append(Vector2(left, bottom - soften))
	else:
		points.append(Vector2(left, bottom))

	return points


func _add_surface_mesh(surface: String, tile_count: int) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var size: float = float(construction_grid.tile_size_yards)
	var offset_y: float = float(SURFACE_HEIGHT_OFFSET.get(surface, 0.0))
	var softened_cells: int = 0

	for y in range(int(construction_grid.height)):
		for x in range(int(construction_grid.width)):
			if str(construction_grid.surface_at(x, y)) != surface:
				continue

			var footprint: PackedVector2Array = visual_footprint_for_cell(x, y)
			if footprint.size() < 3:
				continue
			if surface != "ROUGH" and _has_exposed_cardinal_edge(x, y):
				softened_cells += 1
			_append_cell_footprint(vertices, normals, x, y, footprint, offset_y, size)

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
	visual.set_meta("softened_boundary_cells", softened_cells)
	visual.set_meta("source", "construction_grid")
	visual.set_meta("visual_projection", "topology_softened" if surface != "ROUGH" else "authoritative_base")
	add_child(visual)
	rendered_surfaces.append({
		"classification": surface,
		"tile_count": tile_count,
		"softened_boundary_cells": softened_cells,
		"node": visual
	})


func _append_cell_footprint(vertices: PackedVector3Array, normals: PackedVector3Array, cell_x: int, cell_y: int, footprint: PackedVector2Array, offset_y: float, size: float) -> void:
	var center_local := Vector2.ZERO
	for point: Vector2 in footprint:
		center_local += point
	center_local /= float(footprint.size())
	var center_world: Vector3 = _cell_local_to_world(cell_x, cell_y, center_local, offset_y, size)

	for i in range(footprint.size()):
		var current: Vector3 = _cell_local_to_world(cell_x, cell_y, footprint[i], offset_y, size)
		var next: Vector3 = _cell_local_to_world(cell_x, cell_y, footprint[(i + 1) % footprint.size()], offset_y, size)
		_append_triangle(vertices, normals, center_world, next, current)


func _cell_local_to_world(cell_x: int, cell_y: int, local_point: Vector2, offset_y: float, size: float) -> Vector3:
	var world_x: float = float(construction_grid.origin.x) + float(cell_x) * size + local_point.x
	var world_z: float = float(construction_grid.origin.y) + float(cell_y) * size + local_point.y
	var elevation: float = _terrain_height_inside_cell(cell_x, cell_y, local_point.x / size, local_point.y / size)
	return Vector3(world_x, elevation + offset_y, world_z)


func _terrain_height_inside_cell(cell_x: int, cell_y: int, tx_value: float, tz_value: float) -> float:
	var tx: float = clampf(tx_value, 0.0, 1.0)
	var tz: float = clampf(tz_value, 0.0, 1.0)
	var h00: float = terrain_height_at_grid_corner(cell_x, cell_y)
	var h10: float = terrain_height_at_grid_corner(cell_x + 1, cell_y)
	var h11: float = terrain_height_at_grid_corner(cell_x + 1, cell_y + 1)
	var h01: float = terrain_height_at_grid_corner(cell_x, cell_y + 1)
	var near_height: float = lerpf(h00, h10, tx)
	var far_height: float = lerpf(h01, h11, tx)
	return lerpf(near_height, far_height, tz)


func _has_exposed_cardinal_edge(x: int, y: int) -> bool:
	var same: Dictionary = construction_grid.same_surface_neighbors(x, y)
	for direction in ["N", "E", "S", "W"]:
		if not bool(same.get(direction, false)):
			return true
	return false


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
		"FRINGE":
			return Color(0.32, 0.62, 0.27)
		"ROUGH":
			return Color(0.19, 0.42, 0.18)
		"BUNKER":
			return Color(0.76, 0.65, 0.43)
		"WATER":
			return Color(0.16, 0.39, 0.61)
		_:
			return Color(0.22, 0.46, 0.20)
