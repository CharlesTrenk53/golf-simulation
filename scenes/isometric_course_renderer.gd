extends Node2D

# POC-30H: 64x32 Isometric Course Renderer
# -----------------------------------------
# Presentation-only projection of CourseConstructionGrid data. The authoritative
# construction grid remains the source of surface ownership, elevation, costs,
# save data, and simulation. This renderer exists only to answer whether the
# project reads better as a crisp SimGolf-like 2.5D management world.
#
# Surface ownership stays crisp and tile-authoritative. Terrain elevation is a
# separate presentation concern: tile centers preserve their exact authored
# elevations while shared edges/corners reconcile neighboring values into one
# continuous landform. That removes the stacked-step look without blending
# FAIRWAY/ROUGH/GREEN/BUNKER/WATER classifications.

const TILE_WIDTH: float = 64.0
const TILE_HEIGHT: float = 32.0
const HALF_WIDTH: float = TILE_WIDTH * 0.5
const HALF_HEIGHT: float = TILE_HEIGHT * 0.5
const ELEVATION_PIXELS_PER_YARD: float = 7.0
const BOUNDARY_WIDTH: float = 1.6

var construction_grid = null
var dressing_records: Array = []
var flag_cell := Vector2i(-1, -1)
var tee_cell := Vector2i(-1, -1)
var configured: bool = false


func configure(grid, dressing_plan: Array = [], flag_position: Vector2i = Vector2i(-1, -1), tee_position: Vector2i = Vector2i(-1, -1)) -> bool:
	construction_grid = grid
	dressing_records = dressing_plan.duplicate(true)
	flag_cell = flag_position
	tee_cell = tee_position
	configured = construction_grid != null and int(construction_grid.width) > 0 and int(construction_grid.height) > 0
	queue_redraw()
	return configured


func grid_to_iso(grid_x: float, grid_y: float, elevation_yards: float = 0.0) -> Vector2:
	return Vector2(
		(grid_x - grid_y) * HALF_WIDTH,
		(grid_x + grid_y) * HALF_HEIGHT - elevation_yards * ELEVATION_PIXELS_PER_YARD
	)


func cell_center_iso(x: int, y: int) -> Vector2:
	if construction_grid == null or not construction_grid.is_in_bounds(x, y):
		return Vector2.ZERO
	return grid_to_iso(float(x) + 0.5, float(y) + 0.5, _tile_elevation(x, y))


func rendered_surface_count(surface: String) -> int:
	if construction_grid == null:
		return 0
	return int(construction_grid.count_surface(surface))


func terrain_corner_elevation(corner_x: int, corner_y: int) -> float:
	if construction_grid == null:
		return 0.0
	var total: float = 0.0
	var count: int = 0
	for tile_y_value in [corner_y - 1, corner_y]:
		var tile_y: int = int(tile_y_value)
		for tile_x_value in [corner_x - 1, corner_x]:
			var tile_x: int = int(tile_x_value)
			if construction_grid.is_in_bounds(tile_x, tile_y):
				total += _tile_elevation(tile_x, tile_y)
				count += 1
	if count == 0:
		return 0.0
	return total / float(count)


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
	var nw: float = terrain_corner_elevation(cell_x, cell_y)
	var ne: float = terrain_corner_elevation(cell_x + 1, cell_y)
	var se: float = terrain_corner_elevation(cell_x + 1, cell_y + 1)
	var sw: float = terrain_corner_elevation(cell_x, cell_y + 1)

	if u <= 0.5 and v <= 0.5:
		return _bilinear(nw, north, west, center, u * 2.0, v * 2.0)
	if u > 0.5 and v <= 0.5:
		return _bilinear(north, ne, center, east, (u - 0.5) * 2.0, v * 2.0)
	if u > 0.5 and v > 0.5:
		return _bilinear(center, east, south, se, (u - 0.5) * 2.0, (v - 0.5) * 2.0)
	return _bilinear(west, center, sw, south, u * 2.0, (v - 0.5) * 2.0)


func terrain_height_at_grid_position(grid_x_value: float, grid_y_value: float) -> float:
	if construction_grid == null:
		return 0.0
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
	return terrain_height_at_cell_uv(cell_x, cell_y, u, v)


func tile_corners_iso(x: int, y: int) -> PackedVector2Array:
	if construction_grid == null or not construction_grid.is_in_bounds(x, y):
		return PackedVector2Array()
	return _tile_corners(x, y)


func visual_bounds() -> Rect2:
	if construction_grid == null:
		return Rect2()
	var min_x: float = INF
	var min_y: float = INF
	var max_x: float = -INF
	var max_y: float = -INF
	for y in range(int(construction_grid.height)):
		for x in range(int(construction_grid.width)):
			for corner in _tile_corners(x, y):
				min_x = minf(min_x, corner.x)
				min_y = minf(min_y, corner.y)
				max_x = maxf(max_x, corner.x)
				max_y = maxf(max_y, corner.y)
	if min_x == INF:
		return Rect2()
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


func _draw() -> void:
	if not configured:
		return
	_draw_property_tiles()
	_draw_dressing()
	_draw_markers()


func _draw_property_tiles() -> void:
	# Painter's order: back/northwest first, front/southeast last.
	for diagonal in range(int(construction_grid.width + construction_grid.height - 1)):
		for x in range(int(construction_grid.width)):
			var y: int = diagonal - x
			if y < 0 or y >= int(construction_grid.height):
				continue
			_draw_tile(x, y)


func _draw_tile(x: int, y: int) -> void:
	var corners: PackedVector2Array = _tile_corners(x, y)
	var surface: String = str(construction_grid.surface_at(x, y))

	# There are intentionally no internal vertical side walls anymore. Neighboring
	# tiles share the same smoothed edge heights, so the land reads as one rolling
	# surface rather than a stack of raised diamonds.
	draw_colored_polygon(corners, _surface_color(surface, x, y))
	_draw_surface_detail(surface, x, y, corners)
	_draw_surface_boundaries(x, y, surface, corners)


func _draw_surface_detail(surface: String, x: int, y: int, corners: PackedVector2Array) -> void:
	var center: Vector2 = cell_center_iso(x, y)
	match surface:
		"WATER":
			var line_a: Vector2 = corners[3].lerp(corners[0], 0.48)
			var line_b: Vector2 = corners[2].lerp(corners[1], 0.48)
			draw_line(line_a.lerp(center, 0.10), line_b.lerp(center, 0.10), Color(0.72, 0.89, 0.96, 0.70), 1.25, true)
			var line2_a: Vector2 = corners[3].lerp(corners[0], 0.68)
			var line2_b: Vector2 = corners[2].lerp(corners[1], 0.68)
			draw_line(line2_a.lerp(center, 0.20), line2_b.lerp(center, 0.20), Color(0.63, 0.84, 0.93, 0.46), 1.0, true)
		"BUNKER":
			for offset in [Vector2(-8.0, 1.0), Vector2(3.0, -3.0), Vector2(9.0, 3.0)]:
				draw_circle(center + offset, 1.15, Color(0.69, 0.57, 0.32, 0.65))
		"GREEN":
			var green_band: Color = Color(0.92, 1.0, 0.88, 0.08 if (x + y) % 2 == 0 else 0.0)
			if green_band.a > 0.0:
				draw_colored_polygon(_inset_diamond(corners, 0.12), green_band)
		"TEE":
			if x % 2 == 0:
				draw_colored_polygon(_inset_diamond(corners, 0.10), Color(0.94, 1.0, 0.90, 0.07))
		_:
			pass


func _draw_surface_boundaries(x: int, y: int, surface: String, corners: PackedVector2Array) -> void:
	var boundary_color := Color(0.08, 0.13, 0.07, 0.66)
	# corners: NW, NE, SE, SW. Draw each edge only when it is a property edge or
	# the adjacent authoritative surface is different. Same-surface cells have no seam.
	if y == 0 or str(construction_grid.surface_at(x, y - 1)) != surface:
		draw_line(corners[0], corners[1], boundary_color, BOUNDARY_WIDTH, true)
	if x == int(construction_grid.width) - 1 or str(construction_grid.surface_at(x + 1, y)) != surface:
		draw_line(corners[1], corners[2], boundary_color, BOUNDARY_WIDTH, true)
	if y == int(construction_grid.height) - 1 or str(construction_grid.surface_at(x, y + 1)) != surface:
		draw_line(corners[3], corners[2], boundary_color, BOUNDARY_WIDTH, true)
	if x == 0 or str(construction_grid.surface_at(x - 1, y)) != surface:
		draw_line(corners[0], corners[3], boundary_color, BOUNDARY_WIDTH, true)


func _draw_dressing() -> void:
	var sorted_records: Array = dressing_records.duplicate(true)
	sorted_records.sort_custom(func(a, b):
		var pa: Vector3 = a.get("position", Vector3.ZERO)
		var pb: Vector3 = b.get("position", Vector3.ZERO)
		var agx: float = (pa.x - float(construction_grid.origin.x)) / float(construction_grid.tile_size_yards)
		var agy: float = (pa.z - float(construction_grid.origin.y)) / float(construction_grid.tile_size_yards)
		var bgx: float = (pb.x - float(construction_grid.origin.x)) / float(construction_grid.tile_size_yards)
		var bgy: float = (pb.z - float(construction_grid.origin.y)) / float(construction_grid.tile_size_yards)
		return agx + agy < bgx + bgy
	)

	for record_value in sorted_records:
		var record: Dictionary = record_value
		var position: Vector3 = record.get("position", Vector3.ZERO)
		var gx: float = (position.x - float(construction_grid.origin.x)) / float(construction_grid.tile_size_yards)
		var gy: float = (position.z - float(construction_grid.origin.y)) / float(construction_grid.tile_size_yards)
		var terrain_elevation: float = terrain_height_at_grid_position(gx, gy)
		var base: Vector2 = grid_to_iso(gx, gy, terrain_elevation)
		var scale_value: float = float(record.get("scale", 1.0))
		if str(record.get("kind", "")) == "TREE":
			_draw_tree(base, scale_value)
		else:
			_draw_shrub(base, scale_value)


func _draw_tree(base: Vector2, scale_value: float) -> void:
	var s: float = clampf(scale_value, 0.65, 1.25)
	draw_colored_polygon(_ellipse_points(base + Vector2(7.0 * s, 2.0), 10.0 * s, 4.0 * s), Color(0.05, 0.08, 0.04, 0.22))
	draw_line(base + Vector2(0.0, -1.0), base + Vector2(0.0, -15.0 * s), Color(0.31, 0.20, 0.10), 3.0 * s, true)
	var crown: Vector2 = base + Vector2(0.0, -20.0 * s)
	draw_circle(crown + Vector2(-4.0 * s, 1.0), 8.0 * s, Color(0.16, 0.39, 0.14))
	draw_circle(crown + Vector2(5.0 * s, 0.0), 7.5 * s, Color(0.13, 0.34, 0.12))
	draw_circle(crown + Vector2(0.0, -5.0 * s), 8.5 * s, Color(0.19, 0.44, 0.16))
	draw_circle(crown + Vector2(-2.0 * s, -8.0 * s), 4.0 * s, Color(0.30, 0.54, 0.23, 0.55))


func _draw_shrub(base: Vector2, scale_value: float) -> void:
	var s: float = clampf(scale_value, 0.55, 1.1)
	draw_circle(base + Vector2(-3.0 * s, -3.0 * s), 4.5 * s, Color(0.19, 0.42, 0.15))
	draw_circle(base + Vector2(3.0 * s, -3.0 * s), 4.0 * s, Color(0.16, 0.37, 0.14))
	draw_circle(base + Vector2(0.0, -6.0 * s), 4.5 * s, Color(0.24, 0.47, 0.18))


func _draw_markers() -> void:
	if construction_grid != null and construction_grid.is_in_bounds(flag_cell.x, flag_cell.y):
		var flag_base: Vector2 = cell_center_iso(flag_cell.x, flag_cell.y)
		draw_line(flag_base, flag_base + Vector2(0.0, -27.0), Color(0.95, 0.95, 0.91), 2.0, true)
		var flag_top: Vector2 = flag_base + Vector2(0.0, -27.0)
		draw_colored_polygon(PackedVector2Array([flag_top, flag_top + Vector2(13.0, 5.0), flag_top + Vector2(0.0, 10.0)]), Color(0.86, 0.13, 0.10))

	if construction_grid != null and construction_grid.is_in_bounds(tee_cell.x, tee_cell.y):
		var tee_base: Vector2 = cell_center_iso(tee_cell.x, tee_cell.y)
		draw_circle(tee_base + Vector2(-7.0, -2.0), 3.0, Color(0.94, 0.94, 0.90))
		draw_circle(tee_base + Vector2(7.0, -2.0), 3.0, Color(0.94, 0.94, 0.90))


func _tile_corners(x: int, y: int) -> PackedVector2Array:
	return PackedVector2Array([
		grid_to_iso(float(x), float(y), terrain_corner_elevation(x, y)),
		grid_to_iso(float(x + 1), float(y), terrain_corner_elevation(x + 1, y)),
		grid_to_iso(float(x + 1), float(y + 1), terrain_corner_elevation(x + 1, y + 1)),
		grid_to_iso(float(x), float(y + 1), terrain_corner_elevation(x, y + 1))
	])


func _inset_diamond(corners: PackedVector2Array, amount: float) -> PackedVector2Array:
	var center: Vector2 = (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
	var result := PackedVector2Array()
	for corner in corners:
		result.append(corner.lerp(center, amount))
	return result


func _ellipse_points(center: Vector2, radius_x: float, radius_y: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(16):
		var angle: float = TAU * float(i) / 16.0
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points


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


func _surface_color(surface: String, x: int, y: int) -> Color:
	var base: Color
	match surface:
		"FAIRWAY":
			base = Color(0.38, 0.61, 0.25)
			if int(floor(float(y) / 2.0)) % 2 == 0:
				base = base.lightened(0.045)
		"TEE":
			base = Color(0.45, 0.68, 0.31)
		"GREEN":
			base = Color(0.49, 0.72, 0.34)
		"FRINGE":
			base = Color(0.40, 0.63, 0.27)
		"BUNKER":
			base = Color(0.82, 0.71, 0.43)
		"WATER":
			base = Color(0.24, 0.54, 0.70)
		_:
			base = Color(0.25, 0.48, 0.20)
	var variation: float = 0.018 * sin(float(x * 17 + y * 29))
	return base.lightened(maxf(variation, 0.0)).darkened(maxf(-variation, 0.0))