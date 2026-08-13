extends RefCounted

# POC-22C: Construction Grid -> HoleDefinition
# ---------------------------------------------
# Converts the player-owned construction grid into the same authoritative
# HoleDefinition consumed by the autonomous golfer systems. Rendering remains
# downstream of this data; the construction grid is the source of truth.

const HoleAuthoringModel = preload("res://simulation/hole_authoring_model.gd")


func build_hole(
	grid,
	course_id: String,
	hole_number: int,
	hole_name: String,
	par: int,
	tee_cell: Vector2i,
	pin_cell: Vector2i,
	tee_id: String = "default",
	tee_name: String = "Tee"
):
	if grid == null or course_id.is_empty() or hole_number <= 0:
		return null
	if not grid.is_in_bounds(tee_cell.x, tee_cell.y) or not grid.is_in_bounds(pin_cell.x, pin_cell.y):
		return null
	if grid.surface_at(tee_cell.x, tee_cell.y) != "TEE":
		return null
	if grid.surface_at(pin_cell.x, pin_cell.y) != "GREEN":
		return null

	var green_outline := _surface_outline(grid, "GREEN")
	if green_outline.size() < 3:
		return null

	var tee_position: Vector3 = grid.tile_center_world(tee_cell.x, tee_cell.y)
	var pin_position: Vector3 = grid.tile_center_world(pin_cell.x, pin_cell.y)
	var yardage := Vector2(tee_position.x, tee_position.z).distance_to(Vector2(pin_position.x, pin_position.z))

	var author = HoleAuthoringModel.new()
	author.configure_identity(course_id, hole_number, hole_name, par, yardage)
	author.add_tee(tee_id, tee_name, tee_position, yardage)
	author.set_pin(pin_position)
	author.set_green(green_outline)

	var region_index: int = 0
	for y in range(grid.height):
		for x in range(grid.width):
			var surface: String = grid.surface_at(x, y)
			if surface == "ROUGH" or surface == "GREEN":
				_continue_region_elevation(author, grid, x, y)
				continue
			var polygon := _tile_polygon(grid, x, y)
			var region_id := "%s_%d_%d_%d" % [surface.to_lower(), x, y, region_index]
			region_index += 1
			match surface:
				"FAIRWAY", "TEE":
					author.add_surface_region(region_id, surface.capitalize(), surface, polygon)
				"BUNKER":
					author.add_hazard(region_id, "Bunker", "BUNKER", polygon, 0, "")
				"WATER":
					author.add_hazard(region_id, "Water", "WATER", polygon, 1, "lateral")
			_continue_region_elevation(author, grid, x, y)

	return author.build_definition()


func _continue_region_elevation(author, grid, x: int, y: int) -> void:
	var center: Vector3 = grid.tile_center_world(x, y)
	author.add_elevation_point(center, center.y)


func _tile_polygon(grid, x: int, y: int) -> PackedVector2Array:
	var size: float = grid.tile_size_yards
	var left: float = grid.origin.x + float(x) * size
	var near_z: float = grid.origin.y + float(y) * size
	var right: float = left + size
	var far_z: float = near_z + size
	return PackedVector2Array([
		Vector2(left, near_z),
		Vector2(right, near_z),
		Vector2(right, far_z),
		Vector2(left, far_z)
	])


# Traces the outside edge of one connected tile surface. This allows a green
# to be authored from many tiles without replacing it with a misleading
# bounding rectangle. Disconnected islands or holes are rejected for now; a
# future editor can expose validation before a hole is opened for play.
func _surface_outline(grid, surface: String) -> PackedVector2Array:
	var selected := {}
	for y in range(grid.height):
		for x in range(grid.width):
			if grid.surface_at(x, y) == surface:
				selected[Vector2i(x, y)] = true
	if selected.is_empty():
		return PackedVector2Array()

	var edges: Array = []
	var size: float = grid.tile_size_yards
	for cell_value in selected.keys():
		var cell: Vector2i = cell_value
		var left: float = grid.origin.x + float(cell.x) * size
		var near_z: float = grid.origin.y + float(cell.y) * size
		var right: float = left + size
		var far_z: float = near_z + size
		if not selected.has(Vector2i(cell.x, cell.y - 1)):
			edges.append([Vector2(left, near_z), Vector2(right, near_z)])
		if not selected.has(Vector2i(cell.x + 1, cell.y)):
			edges.append([Vector2(right, near_z), Vector2(right, far_z)])
		if not selected.has(Vector2i(cell.x, cell.y + 1)):
			edges.append([Vector2(right, far_z), Vector2(left, far_z)])
		if not selected.has(Vector2i(cell.x - 1, cell.y)):
			edges.append([Vector2(left, far_z), Vector2(left, near_z)])

	if edges.is_empty():
		return PackedVector2Array()

	var next_by_start := {}
	for edge in edges:
		if next_by_start.has(edge[0]):
			return PackedVector2Array()
		next_by_start[edge[0]] = edge[1]

	var start: Vector2 = edges[0][0]
	var current: Vector2 = start
	var outline := PackedVector2Array()
	var traversed: int = 0
	while traversed <= edges.size():
		outline.append(current)
		if not next_by_start.has(current):
			return PackedVector2Array()
		current = next_by_start[current]
		traversed += 1
		if current == start:
			break

	if current != start or traversed != edges.size():
		return PackedVector2Array()
	return _remove_collinear_points(outline)


func _remove_collinear_points(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() <= 3:
		return points
	var simplified := PackedVector2Array()
	for i in range(points.size()):
		var previous: Vector2 = points[(i - 1 + points.size()) % points.size()]
		var current: Vector2 = points[i]
		var next: Vector2 = points[(i + 1) % points.size()]
		var a := current - previous
		var b := next - current
		if absf(a.cross(b)) > 0.0001:
			simplified.append(current)
	return simplified
