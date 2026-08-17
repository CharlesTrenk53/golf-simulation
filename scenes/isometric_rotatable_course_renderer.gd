extends "res://scenes/isometric_course_renderer.gd"

# POC-30H: Rotatable 64x32 Isometric Projection
# ----------------------------------------------
# Adds four cardinal viewpoints to the proven isometric course renderer without
# changing construction/simulation authority. Surface ownership and elevation
# remain in the original grid; only the presentation basis rotates.

var rotation_quarters: int = 0


func set_view_rotation_quarters(value: int) -> void:
	rotation_quarters = posmod(value, 4)
	queue_redraw()


func rotate_view(step_quarters: int) -> void:
	set_view_rotation_quarters(rotation_quarters + step_quarters)


func grid_to_iso(grid_x: float, grid_y: float, elevation_yards: float = 0.0) -> Vector2:
	var rotated: Vector2 = _rotate_grid_point(grid_x, grid_y)
	return Vector2(
		(rotated.x - rotated.y) * HALF_WIDTH,
		(rotated.x + rotated.y) * HALF_HEIGHT - elevation_yards * ELEVATION_PIXELS_PER_YARD
	)


func rotated_grid_position(grid_x: float, grid_y: float) -> Vector2:
	return _rotate_grid_point(grid_x, grid_y)


func _rotate_grid_point(grid_x: float, grid_y: float) -> Vector2:
	if construction_grid == null:
		return Vector2(grid_x, grid_y)
	var width_value: float = float(construction_grid.width)
	var height_value: float = float(construction_grid.height)
	match rotation_quarters:
		1:
			# Clockwise: original north becomes screen-right-facing west edge.
			return Vector2(height_value - grid_y, grid_x)
		2:
			return Vector2(width_value - grid_x, height_value - grid_y)
		3:
			return Vector2(grid_y, width_value - grid_x)
		_:
			return Vector2(grid_x, grid_y)


func _view_depth(grid_x: float, grid_y: float) -> float:
	var rotated: Vector2 = _rotate_grid_point(grid_x, grid_y)
	return rotated.x + rotated.y


func _view_lateral(grid_x: float, grid_y: float) -> float:
	var rotated: Vector2 = _rotate_grid_point(grid_x, grid_y)
	return rotated.x - rotated.y


func _draw_property_tiles() -> void:
	# Re-sort the authoritative cells for the active cardinal viewpoint so raised
	# terrain details and boundaries paint back-to-front after every rotation.
	var cells: Array[Vector2i] = []
	for y in range(int(construction_grid.height)):
		for x in range(int(construction_grid.width)):
			cells.append(Vector2i(x, y))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var depth_a: float = _view_depth(float(a.x) + 0.5, float(a.y) + 0.5)
		var depth_b: float = _view_depth(float(b.x) + 0.5, float(b.y) + 0.5)
		if not is_equal_approx(depth_a, depth_b):
			return depth_a < depth_b
		return _view_lateral(float(a.x) + 0.5, float(a.y) + 0.5) < _view_lateral(float(b.x) + 0.5, float(b.y) + 0.5)
	)
	for cell in cells:
		_draw_tile(cell.x, cell.y)


func _draw_dressing() -> void:
	# Vegetation must use the same rotated depth basis as the terrain. The dressing
	# records themselves remain untouched world-space presentation data.
	var sorted_records: Array = dressing_records.duplicate(true)
	sorted_records.sort_custom(func(a, b):
		var pa: Vector3 = a.get("position", Vector3.ZERO)
		var pb: Vector3 = b.get("position", Vector3.ZERO)
		var agx: float = (pa.x - float(construction_grid.origin.x)) / float(construction_grid.tile_size_yards)
		var agy: float = (pa.z - float(construction_grid.origin.y)) / float(construction_grid.tile_size_yards)
		var bgx: float = (pb.x - float(construction_grid.origin.x)) / float(construction_grid.tile_size_yards)
		var bgy: float = (pb.z - float(construction_grid.origin.y)) / float(construction_grid.tile_size_yards)
		var depth_a: float = _view_depth(agx, agy)
		var depth_b: float = _view_depth(bgx, bgy)
		if not is_equal_approx(depth_a, depth_b):
			return depth_a < depth_b
		return _view_lateral(agx, agy) < _view_lateral(bgx, bgy)
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
