extends Node2D

# POC-33A: Isometric Living Golfer Projection Layer
# -------------------------------------------------
# Presentation-only bridge between authoritative course-space golfer positions
# and the accepted POC-30/31/32 isometric renderer. This node never advances a
# golfer, chooses a shot, resolves a lie, or changes traffic. It only projects
# already-authoritative X/Z positions onto the visible player-authored terrain.
#
# The layer can consume plain position records for focused tests or mirror the
# existing POC-25 SpectatorGroupVisual member positions. That keeps later POC-33
# movement work attached to the proven spectator playback instead of creating a
# second movement simulation.

@export var shadow_radius_pixels: float = 5.0
@export var body_radius_pixels: float = 4.5
@export var body_height_pixels: float = 12.0

var course_renderer = null
var construction_grid = null
var golfer_records: Array = []
var projected_records: Array = []


func configure(renderer_value, grid_value = null) -> bool:
	course_renderer = renderer_value
	construction_grid = grid_value
	if construction_grid == null and course_renderer != null:
		construction_grid = course_renderer.get("construction_grid")
	var valid: bool = (
		course_renderer != null
		and construction_grid != null
		and int(construction_grid.width) > 0
		and int(construction_grid.height) > 0
		and course_renderer.has_method("grid_to_iso")
		and course_renderer.has_method("terrain_height_at_grid_position")
	)
	if not valid:
		course_renderer = null
		construction_grid = null
		golfer_records.clear()
		projected_records.clear()
		queue_redraw()
		return false
	refresh_projection()
	return true


func set_golfers(records: Array) -> bool:
	if course_renderer == null or construction_grid == null:
		return false
	var normalized: Array = []
	for value in records:
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = value
		var position_value = record.get("world_position", record.get("position", null))
		if typeof(position_value) != TYPE_VECTOR3:
			return false
		var identity: String = str(record.get("golfer_id", record.get("id", "")))
		if identity.is_empty():
			identity = "%s:%d" % [str(record.get("group_id", "group")), int(record.get("member_index", normalized.size()))]
		var copy: Dictionary = record.duplicate(true)
		copy["golfer_id"] = identity
		copy["world_position"] = position_value
		normalized.append(copy)
	golfer_records = normalized
	refresh_projection()
	return true


func sync_from_group_visual(group_visual) -> bool:
	if group_visual == null or not group_visual.has_method("member_world_positions"):
		return false
	var positions: Array = group_visual.member_world_positions()
	if positions.is_empty():
		return false
	var group_id: String = ""
	var golfers: Array = []
	if group_visual.get("group") != null:
		var group = group_visual.get("group")
		group_id = str(group.get("group_id"))
		golfers = group.get("golfers")
	var records: Array = []
	for index in range(positions.size()):
		if typeof(positions[index]) != TYPE_VECTOR3:
			return false
		var golfer_name := "Golfer %d" % (index + 1)
		var golfer_id := "%s:%d" % [group_id, index]
		if index < golfers.size() and golfers[index] != null:
			var golfer = golfers[index]
			golfer_name = str(golfer.get("golfer_name"))
			if golfer_name.is_empty():
				golfer_name = "Golfer %d" % (index + 1)
		records.append({
			"golfer_id": golfer_id,
			"group_id": group_id,
			"member_index": index,
			"golfer_name": golfer_name,
			"world_position": positions[index]
		})
	return set_golfers(records)


func refresh_projection() -> void:
	projected_records.clear()
	if course_renderer == null or construction_grid == null:
		queue_redraw()
		return
	for value in golfer_records:
		var record: Dictionary = value
		var world_position: Vector3 = record.get("world_position", Vector3.ZERO)
		var grid_position: Vector2 = world_to_grid(world_position)
		var terrain_elevation: float = float(course_renderer.terrain_height_at_grid_position(grid_position.x, grid_position.y))
		var iso_position: Vector2 = course_renderer.grid_to_iso(grid_position.x, grid_position.y, terrain_elevation)
		var rotated: Vector2 = grid_position
		if course_renderer.has_method("rotated_grid_position"):
			rotated = course_renderer.rotated_grid_position(grid_position.x, grid_position.y)
		var projected: Dictionary = record.duplicate(true)
		projected["grid_position"] = grid_position
		projected["terrain_elevation"] = terrain_elevation
		projected["iso_position"] = iso_position
		projected["view_depth"] = rotated.x + rotated.y
		projected["view_lateral"] = rotated.x - rotated.y
		projected_records.append(projected)
	projected_records.sort_custom(_projection_sort)
	queue_redraw()


func world_to_grid(world_position: Vector3) -> Vector2:
	if construction_grid == null or float(construction_grid.tile_size_yards) <= 0.0:
		return Vector2.ZERO
	var size: float = float(construction_grid.tile_size_yards)
	return Vector2(
		(world_position.x - float(construction_grid.origin.x)) / size,
		(world_position.z - float(construction_grid.origin.y)) / size
	)


func project_world_position(world_position: Vector3) -> Vector2:
	if course_renderer == null or construction_grid == null:
		return Vector2.ZERO
	var grid_position: Vector2 = world_to_grid(world_position)
	var terrain_elevation: float = float(course_renderer.terrain_height_at_grid_position(grid_position.x, grid_position.y))
	return course_renderer.grid_to_iso(grid_position.x, grid_position.y, terrain_elevation)


func projected_record(golfer_id: String) -> Dictionary:
	for value in projected_records:
		var record: Dictionary = value
		if str(record.get("golfer_id", "")) == golfer_id:
			return record.duplicate(true)
	return {}


func snapshot() -> Dictionary:
	return {
		"golfer_count": projected_records.size(),
		"records": projected_records.duplicate(true)
	}


func _projection_sort(a_value, b_value) -> bool:
	var a: Dictionary = a_value
	var b: Dictionary = b_value
	var depth_a: float = float(a.get("view_depth", 0.0))
	var depth_b: float = float(b.get("view_depth", 0.0))
	if not is_equal_approx(depth_a, depth_b):
		return depth_a < depth_b
	var lateral_a: float = float(a.get("view_lateral", 0.0))
	var lateral_b: float = float(b.get("view_lateral", 0.0))
	if not is_equal_approx(lateral_a, lateral_b):
		return lateral_a < lateral_b
	return str(a.get("golfer_id", "")) < str(b.get("golfer_id", ""))


func _draw() -> void:
	# Painter's order is the same stable depth order exposed in projected_records.
	# The glyph is intentionally simple in POC-33A; motion and richer visual identity
	# arrive in later slices after the projection contract is proven.
	for value in projected_records:
		var record: Dictionary = value
		var base: Vector2 = record.get("iso_position", Vector2.ZERO)
		draw_circle(base + Vector2(3.0, 2.0), shadow_radius_pixels, Color(0.02, 0.03, 0.02, 0.28))
		draw_line(base + Vector2(0.0, -2.0), base + Vector2(0.0, -body_height_pixels), Color(0.94, 0.94, 0.90), 2.6, true)
		draw_circle(base + Vector2(0.0, -body_height_pixels - 3.0), body_radius_pixels, Color(0.82, 0.84, 0.80))
