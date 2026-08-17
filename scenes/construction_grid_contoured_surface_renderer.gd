extends Node3D

# POC-30G: Dense Course Surface Projection with Crisp Ownership
# --------------------------------------------------------------
# Presentation-only visual projection of the authoritative construction grid.
# The 10-yard construction cells remain the sole source of truth for surface
# ownership and authored elevation.
#
# One dense mesh spans the property so terrain can be smooth and well lit, but
# surface classification is intentionally NOT blended. Every presentation
# triangle inside an authoritative cell inherits that cell's exact surface type.
# Vertices are duplicated at cell boundaries, allowing FAIRWAY to end and ROUGH
# to begin at the same geometric edge with a hard, readable cut instead of a
# smeared gradient.
#
# BUNKER and WATER may depress visually inside their owner cells, but their depth
# fades back to the common terrain at the cell boundary to avoid cracks. None of
# this changes lie, hazard, scoring, construction cost, save data, or HoleDefinition
# authority.

const SUBDIVISIONS_PER_CELL: int = 6
const SURFACE_Y_OFFSET: float = 0.018
const NORMAL_SAMPLE_STEP_CELLS: float = 0.14
const HAZARD_EDGE_FADE_CELLS: float = 0.22
const SURFACE_ORDER := ["ROUGH", "FAIRWAY", "TEE", "FRINGE", "GREEN", "BUNKER", "WATER"]
const SURFACE_VISUAL_DEPTH := {
	"ROUGH": 0.000,
	"FAIRWAY": 0.000,
	"TEE": 0.000,
	"FRINGE": 0.000,
	"GREEN": 0.000,
	"BUNKER": -0.060,
	"WATER": -0.110
}

var construction_grid = null
var continuous_visual: MeshInstance3D = null
var continuous_surface_active: bool = false
var contoured_base_active: bool = false
var rendered_triangles: int = 0
var rendered_vertices: int = 0
var authoritative_surface_counts: Dictionary = {}
var authoritative_transition_edges: int = 0


func render_grid(grid) -> bool:
	clear_grid()
	if grid == null or grid.width <= 0 or grid.height <= 0 or grid.tile_size_yards <= 0.0:
		return false

	construction_grid = grid
	for surface_value in SURFACE_ORDER:
		var surface: String = str(surface_value)
		authoritative_surface_counts[surface] = int(grid.count_surface(surface))
	authoritative_transition_edges = _count_authoritative_transition_edges()

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	for cell_y in range(int(grid.height)):
		for cell_x in range(int(grid.width)):
			_append_dense_cell(vertices, normals, colors, cell_x, cell_y)

	if vertices.is_empty():
		return false

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _continuous_material())

	continuous_visual = MeshInstance3D.new()
	continuous_visual.name = "ContinuousCourseSurface"
	continuous_visual.mesh = mesh
	continuous_visual.set_meta("classification", "CONTINUOUS_COURSE_SURFACE")
	continuous_visual.set_meta("source", "construction_grid")
	continuous_visual.set_meta("authority", "presentation_only")
	continuous_visual.set_meta("visual_projection", "dense_crisp_authoritative_blocks")
	continuous_visual.set_meta("subdivisions_per_cell", SUBDIVISIONS_PER_CELL)
	continuous_visual.set_meta("triangle_count", rendered_triangles)
	continuous_visual.set_meta("transition_edge_count", authoritative_transition_edges)
	add_child(continuous_visual)

	continuous_surface_active = true
	contoured_base_active = true
	return true


func clear_grid() -> void:
	if continuous_visual != null:
		remove_child(continuous_visual)
		continuous_visual.queue_free()
	continuous_visual = null
	construction_grid = null
	continuous_surface_active = false
	contoured_base_active = false
	rendered_triangles = 0
	rendered_vertices = 0
	authoritative_surface_counts.clear()
	authoritative_transition_edges = 0


# Compatibility with the POC-30F proof contract. There is no longer a legacy
# ROUGH overlay plane at all; the dense mesh includes the visible rough base.
func rough_base_hidden() -> bool:
	return continuous_surface_active


func rendered_tile_count(surface: String) -> int:
	return int(authoritative_surface_counts.get(surface.to_upper(), 0))


func rendered_transition_edge_count() -> int:
	return authoritative_transition_edges


func rendered_triangle_count() -> int:
	return rendered_triangles


func rendered_vertex_count() -> int:
	return rendered_vertices


func surface_height_at_cell_uv(cell_x: int, cell_y: int, u_value: float, v_value: float) -> float:
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
	if elevations.is_empty():
		return 0.0
	var total: float = 0.0
	for elevation: float in elevations:
		total += elevation
	return total / float(elevations.size())


# Visual ownership is deliberately one-hot. Dense geometry improves the terrain;
# it does not invent fractional surface ownership between authoritative cells.
func visual_surface_weight_at_cell_uv(cell_x: int, cell_y: int, _u_value: float, _v_value: float, surface_value: String) -> float:
	if construction_grid == null or not construction_grid.is_in_bounds(cell_x, cell_y):
		return 0.0
	return 1.0 if str(construction_grid.surface_at(cell_x, cell_y)) == surface_value.to_upper() else 0.0


func visual_color_at_cell_uv(cell_x: int, cell_y: int, u_value: float, v_value: float) -> Color:
	if construction_grid == null or not construction_grid.is_in_bounds(cell_x, cell_y):
		return Color.BLACK
	var u: float = clampf(u_value, 0.0, 1.0)
	var v: float = clampf(v_value, 0.0, 1.0)
	var grid_x: float = float(cell_x) + u
	var grid_y: float = float(cell_y) + v
	return _visual_color_for_cell(cell_x, cell_y, grid_x, grid_y)


func _append_dense_cell(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, cell_x: int, cell_y: int) -> void:
	for sub_y in range(SUBDIVISIONS_PER_CELL):
		for sub_x in range(SUBDIVISIONS_PER_CELL):
			var u0: float = float(sub_x) / float(SUBDIVISIONS_PER_CELL)
			var u1: float = float(sub_x + 1) / float(SUBDIVISIONS_PER_CELL)
			var v0: float = float(sub_y) / float(SUBDIVISIONS_PER_CELL)
			var v1: float = float(sub_y + 1) / float(SUBDIVISIONS_PER_CELL)

			var gx0: float = float(cell_x) + u0
			var gx1: float = float(cell_x) + u1
			var gy0: float = float(cell_y) + v0
			var gy1: float = float(cell_y) + v1

			var p00: Vector3 = _grid_position_to_world_for_cell(cell_x, cell_y, gx0, gy0, u0, v0)
			var p10: Vector3 = _grid_position_to_world_for_cell(cell_x, cell_y, gx1, gy0, u1, v0)
			var p11: Vector3 = _grid_position_to_world_for_cell(cell_x, cell_y, gx1, gy1, u1, v1)
			var p01: Vector3 = _grid_position_to_world_for_cell(cell_x, cell_y, gx0, gy1, u0, v1)

			var n00: Vector3 = _smooth_normal_at_grid_position(gx0, gy0)
			var n10: Vector3 = _smooth_normal_at_grid_position(gx1, gy0)
			var n11: Vector3 = _smooth_normal_at_grid_position(gx1, gy1)
			var n01: Vector3 = _smooth_normal_at_grid_position(gx0, gy1)

			# These use the OWNER cell explicitly. Adjacent cells therefore duplicate
			# their shared boundary vertices with different colors when their surfaces
			# differ, producing a hard visual cut with no cross-boundary interpolation.
			var c00: Color = _visual_color_for_cell(cell_x, cell_y, gx0, gy0)
			var c10: Color = _visual_color_for_cell(cell_x, cell_y, gx1, gy0)
			var c11: Color = _visual_color_for_cell(cell_x, cell_y, gx1, gy1)
			var c01: Color = _visual_color_for_cell(cell_x, cell_y, gx0, gy1)

			_append_triangle(vertices, normals, colors, p00, n00, c00, p11, n11, c11, p10, n10, c10)
			_append_triangle(vertices, normals, colors, p00, n00, c00, p01, n01, c01, p11, n11, c11)
			rendered_triangles += 2


func _append_triangle(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	a: Vector3, na: Vector3, ca: Color,
	b: Vector3, nb: Vector3, cb: Color,
	c: Vector3, nc: Vector3, cc: Color
) -> void:
	vertices.append(a)
	vertices.append(b)
	vertices.append(c)
	normals.append(na)
	normals.append(nb)
	normals.append(nc)
	colors.append(ca)
	colors.append(cb)
	colors.append(cc)
	rendered_vertices += 3


func _grid_position_to_world_for_cell(cell_x: int, cell_y: int, grid_x_value: float, grid_y_value: float, u: float, v: float) -> Vector3:
	var gx: float = clampf(grid_x_value, 0.0, float(construction_grid.width))
	var gy: float = clampf(grid_y_value, 0.0, float(construction_grid.height))
	var size: float = float(construction_grid.tile_size_yards)
	var base_height: float = _height_at_grid_position(gx, gy)
	var surface: String = str(construction_grid.surface_at(cell_x, cell_y))
	var visual_depth: float = float(SURFACE_VISUAL_DEPTH.get(surface, 0.0)) * _interior_depth_factor(u, v)
	return Vector3(
		float(construction_grid.origin.x) + gx * size,
		base_height + visual_depth + SURFACE_Y_OFFSET,
		float(construction_grid.origin.y) + gy * size
	)


func _interior_depth_factor(u_value: float, v_value: float) -> float:
	var u: float = clampf(u_value, 0.0, 1.0)
	var v: float = clampf(v_value, 0.0, 1.0)
	var edge_distance: float = minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
	return _smoothstep01(edge_distance / HAZARD_EDGE_FADE_CELLS)


func _smoothstep01(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _height_at_grid_position(grid_x_value: float, grid_y_value: float) -> float:
	var gx: float = clampf(grid_x_value, 0.0, float(construction_grid.width))
	var gy: float = clampf(grid_y_value, 0.0, float(construction_grid.height))
	var cell_x: int = mini(int(floor(gx)), int(construction_grid.width) - 1)
	var cell_y: int = mini(int(floor(gy)), int(construction_grid.height) - 1)
	cell_x = maxi(cell_x, 0)
	cell_y = maxi(cell_y, 0)
	var u: float = gx - float(cell_x)
	var v: float = gy - float(cell_y)
	if gx >= float(construction_grid.width):
		u = 1.0
	if gy >= float(construction_grid.height):
		v = 1.0
	return surface_height_at_cell_uv(cell_x, cell_y, u, v)


func _smooth_normal_at_grid_position(grid_x: float, grid_y: float) -> Vector3:
	var step: float = NORMAL_SAMPLE_STEP_CELLS
	var left: float = _height_at_grid_position(grid_x - step, grid_y)
	var right: float = _height_at_grid_position(grid_x + step, grid_y)
	var north: float = _height_at_grid_position(grid_x, grid_y - step)
	var south: float = _height_at_grid_position(grid_x, grid_y + step)
	var world_step: float = maxf(float(construction_grid.tile_size_yards) * step * 2.0, 0.001)
	return Vector3(left - right, world_step, north - south).normalized()


func _visual_color_for_cell(cell_x: int, cell_y: int, grid_x: float, grid_y: float) -> Color:
	var size: float = float(construction_grid.tile_size_yards)
	var world_x: float = float(construction_grid.origin.x) + grid_x * size
	var world_z: float = float(construction_grid.origin.y) + grid_y * size
	var surface: String = str(construction_grid.surface_at(cell_x, cell_y))
	return _surface_color_with_variation(surface, world_x, world_z)


func _surface_color_with_variation(surface: String, world_x: float, world_z: float) -> Color:
	var variation: float = 1.0 + 0.022 * sin(world_x * 0.083) + 0.018 * cos(world_z * 0.071) + 0.012 * sin((world_x + world_z) * 0.117)
	match surface:
		"FAIRWAY":
			var stripe_index: int = int(floor((world_z + 10000.0) / 6.0))
			var stripe: float = 1.055 if stripe_index % 2 == 0 else 0.945
			return _scaled_color(Color(0.29, 0.58, 0.24), variation * stripe)
		"TEE":
			var tee_stripe_index: int = int(floor((world_x + 10000.0) / 4.5))
			var tee_stripe: float = 1.035 if tee_stripe_index % 2 == 0 else 0.965
			return _scaled_color(Color(0.34, 0.63, 0.29), variation * tee_stripe)
		"GREEN":
			var green_stripe_index: int = int(floor((world_x + 10000.0) / 4.0))
			var green_stripe: float = 1.025 if green_stripe_index % 2 == 0 else 0.975
			return _scaled_color(Color(0.40, 0.69, 0.32), variation * green_stripe)
		"FRINGE":
			return _scaled_color(Color(0.33, 0.61, 0.27), variation)
		"BUNKER":
			return _scaled_color(Color(0.78, 0.67, 0.45), 0.99 + (variation - 1.0) * 0.7)
		"WATER":
			var water_glint: float = 1.0 + 0.035 * sin(world_x * 0.16 + world_z * 0.10)
			return _scaled_color(Color(0.16, 0.45, 0.64), water_glint)
		_:
			return _scaled_color(Color(0.20, 0.43, 0.18), variation)


func _scaled_color(color: Color, factor: float) -> Color:
	return Color(
		clampf(color.r * factor, 0.0, 1.0),
		clampf(color.g * factor, 0.0, 1.0),
		clampf(color.b * factor, 0.0, 1.0),
		1.0
	)


func _count_authoritative_transition_edges() -> int:
	var count: int = 0
	for y in range(int(construction_grid.height)):
		for x in range(int(construction_grid.width)):
			var surface: String = str(construction_grid.surface_at(x, y))
			if x + 1 < int(construction_grid.width) and str(construction_grid.surface_at(x + 1, y)) != surface:
				count += 1
			if y + 1 < int(construction_grid.height) and str(construction_grid.surface_at(x, y + 1)) != surface:
				count += 1
	return count


func _tile_elevation(x: int, y: int) -> float:
	return float(construction_grid.tile_at(x, y).get("elevation", 0.0))


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


func _bilinear(nw: float, ne: float, sw: float, se: float, u: float, v: float) -> float:
	var north: float = lerpf(nw, ne, u)
	var south: float = lerpf(sw, se, u)
	return lerpf(north, south, v)


func _continuous_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 0.91
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
