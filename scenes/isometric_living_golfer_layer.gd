extends Node2D

# POC-33A / POC-33B / POC-33C: Isometric Living Golfer Projection Layer
# ----------------------------------------------------------------------
# Presentation-only bridge between authoritative course-space golfer/ball
# positions and the accepted POC-30/31/32 isometric renderer. This node never
# advances a golfer, chooses a shot, resolves a lie, or changes traffic. It only
# projects already-authoritative X/Z positions onto the visible player-authored
# terrain.
#
# POC-33B mirrors the proven POC-25 SpectatorGroupVisual directly. Golfer
# movement continues to be owned by the existing tee-dispersion and inter-hole
# transition presentation; resolved ball flight continues to be owned by
# RuntimeBallVisual. This layer simply re-projects those positions into 2D.
#
# POC-33C aggregates every SpectatorGroupVisual owned by SpectatorPopulationView
# into one painter-sorted isometric layer. Group status and traffic-hole metadata
# are carried through with each golfer/ball so the visible population remains a
# faithful projection of living-course authority rather than a second traffic
# model.

@export var shadow_radius_pixels: float = 5.0
@export var body_radius_pixels: float = 4.5
@export var body_height_pixels: float = 12.0
@export var ball_radius_pixels: float = 2.2

var course_renderer = null
var construction_grid = null
var golfer_records: Array = []
var projected_records: Array = []
var ball_records: Array = []
var projected_ball_records: Array = []


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
		ball_records.clear()
		projected_ball_records.clear()
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


func set_balls(records: Array) -> bool:
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
		var identity: String = str(record.get("ball_id", record.get("id", "")))
		if identity.is_empty():
			identity = "%s:%d:ball" % [str(record.get("group_id", "group")), int(record.get("member_index", normalized.size()))]
		var copy: Dictionary = record.duplicate(true)
		copy["ball_id"] = identity
		copy["world_position"] = position_value
		copy["visual_height_yards"] = maxf(float(record.get("visual_height_yards", 0.0)), 0.0)
		copy["visible"] = bool(record.get("visible", true))
		normalized.append(copy)
	ball_records = normalized
	refresh_projection()
	return true


func sync_from_group_visual(group_visual) -> bool:
	var extracted: Dictionary = _extract_group_visual_records(group_visual)
	if not bool(extracted.get("valid", false)):
		return false
	return _set_group_visual_records(extracted.get("golfers", []), extracted.get("balls", []))


func sync_from_population_view(population_view) -> bool:
	if population_view == null or not population_view.has_method("group_visual"):
		return false
	var visuals_value = population_view.get("group_visuals")
	if typeof(visuals_value) != TYPE_DICTIONARY:
		return false
	var visuals: Dictionary = visuals_value
	if visuals.is_empty():
		return false

	var ids: Array = visuals.keys()
	ids.sort()
	var golfers: Array = []
	var balls: Array = []
	for group_id_value in ids:
		var group_id: String = str(group_id_value)
		var visual = population_view.group_visual(group_id)
		var extracted: Dictionary = _extract_group_visual_records(visual)
		if not bool(extracted.get("valid", false)):
			return false
		golfers.append_array(extracted.get("golfers", []))
		balls.append_array(extracted.get("balls", []))
	return _set_group_visual_records(golfers, balls)


func _extract_group_visual_records(group_visual) -> Dictionary:
	if group_visual == null or not group_visual.has_method("member_world_positions"):
		return {"valid": false}
	var positions: Array = group_visual.member_world_positions()
	if positions.is_empty():
		return {"valid": false}

	var group_id: String = ""
	var golfers: Array = []
	if group_visual.get("group") != null:
		var group = group_visual.get("group")
		group_id = str(group.get("group_id"))
		golfers = group.get("golfers")
	if group_id.is_empty():
		return {"valid": false}

	var visual_snapshot: Dictionary = group_visual.snapshot() if group_visual.has_method("snapshot") else {}
	var group_status: String = str(visual_snapshot.get("status", group_visual.get("projected_status")))
	var projected_hole_number: int = int(visual_snapshot.get("projected_hole_number", group_visual.get("projected_hole_number")))
	var traffic_hole_number: int = int(visual_snapshot.get("traffic_hole_number", group_visual.get_meta("traffic_hole_number", 0)))

	var records: Array = []
	for index in range(positions.size()):
		if typeof(positions[index]) != TYPE_VECTOR3:
			return {"valid": false}
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
			"group_status": group_status,
			"projected_hole_number": projected_hole_number,
			"traffic_hole_number": traffic_hole_number,
			"world_position": positions[index]
		})

	var ball_nodes: Array = group_visual.get("member_ball_visuals")
	var projected_balls: Array = []
	for index in range(ball_nodes.size()):
		var ball = ball_nodes[index]
		if ball == null:
			continue
		var course_position_value = ball.get("course_position")
		if typeof(course_position_value) != TYPE_VECTOR3:
			continue
		var course_position: Vector3 = course_position_value
		# RuntimeBallVisual keeps resolved course position separate from its
		# presentation-only Y lift. Mirror that lift over the isometric terrain.
		var visual_height: float = 0.0
		if ball is Node3D:
			visual_height = maxf(float(ball.position.y - course_position.y), 0.0)
		projected_balls.append({
			"ball_id": "%s:%d:ball" % [group_id, index],
			"golfer_id": "%s:%d" % [group_id, index],
			"group_id": group_id,
			"member_index": index,
			"group_status": group_status,
			"projected_hole_number": projected_hole_number,
			"traffic_hole_number": traffic_hole_number,
			"world_position": course_position,
			"visual_height_yards": visual_height,
			"visible": bool(ball.visible),
			"is_flying": bool(ball.get("is_flying")),
			"flight_progress": float(ball.get("flight_progress")),
			"trajectory_kind": str(ball.get_meta("trajectory_kind", "STATIONARY"))
		})
	return {"valid": true, "golfers": records, "balls": projected_balls}


func _set_group_visual_records(golfers: Array, balls: Array) -> bool:
	# Apply both snapshots together so one redraw cannot show golfers from a new
	# movement frame with balls from the previous frame.
	var normalized_golfers: Array = []
	for value in golfers:
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = value
		if typeof(record.get("world_position", null)) != TYPE_VECTOR3:
			return false
		normalized_golfers.append(record.duplicate(true))
	var normalized_balls: Array = []
	for value in balls:
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = value
		if typeof(record.get("world_position", null)) != TYPE_VECTOR3:
			return false
		normalized_balls.append(record.duplicate(true))
	golfer_records = normalized_golfers
	ball_records = normalized_balls
	refresh_projection()
	return true


func refresh_projection() -> void:
	projected_records.clear()
	projected_ball_records.clear()
	if course_renderer == null or construction_grid == null:
		queue_redraw()
		return
	for value in golfer_records:
		var record: Dictionary = value
		var world_position: Vector3 = record.get("world_position", Vector3.ZERO)
		var grid_position: Vector2 = world_to_grid(world_position)
		var terrain_elevation: float = float(course_renderer.terrain_height_at_grid_position(grid_position.x, grid_position.y))
		var iso_position: Vector2 = course_renderer.grid_to_iso(grid_position.x, grid_position.y, terrain_elevation)
		var projected: Dictionary = record.duplicate(true)
		_apply_projection_fields(projected, grid_position, terrain_elevation, iso_position)
		projected_records.append(projected)
	projected_records.sort_custom(_projection_sort)

	for value in ball_records:
		var record: Dictionary = value
		var world_position: Vector3 = record.get("world_position", Vector3.ZERO)
		var grid_position: Vector2 = world_to_grid(world_position)
		var terrain_elevation: float = float(course_renderer.terrain_height_at_grid_position(grid_position.x, grid_position.y))
		var lift: float = maxf(float(record.get("visual_height_yards", 0.0)), 0.0)
		var iso_position: Vector2 = course_renderer.grid_to_iso(grid_position.x, grid_position.y, terrain_elevation + lift)
		var projected: Dictionary = record.duplicate(true)
		projected["terrain_elevation"] = terrain_elevation
		projected["visual_height_yards"] = lift
		_apply_projection_fields(projected, grid_position, terrain_elevation, iso_position)
		projected_ball_records.append(projected)
	projected_ball_records.sort_custom(_projection_sort)
	queue_redraw()


func _apply_projection_fields(projected: Dictionary, grid_position: Vector2, terrain_elevation: float, iso_position: Vector2) -> void:
	var rotated: Vector2 = grid_position
	if course_renderer.has_method("rotated_grid_position"):
		rotated = course_renderer.rotated_grid_position(grid_position.x, grid_position.y)
	projected["grid_position"] = grid_position
	projected["terrain_elevation"] = terrain_elevation
	projected["iso_position"] = iso_position
	projected["view_depth"] = rotated.x + rotated.y
	projected["view_lateral"] = rotated.x - rotated.y


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


func project_ball_world_position(world_position: Vector3, visual_height_yards: float = 0.0) -> Vector2:
	if course_renderer == null or construction_grid == null:
		return Vector2.ZERO
	var grid_position: Vector2 = world_to_grid(world_position)
	var terrain_elevation: float = float(course_renderer.terrain_height_at_grid_position(grid_position.x, grid_position.y))
	return course_renderer.grid_to_iso(grid_position.x, grid_position.y, terrain_elevation + maxf(visual_height_yards, 0.0))


func projected_record(golfer_id: String) -> Dictionary:
	for value in projected_records:
		var record: Dictionary = value
		if str(record.get("golfer_id", "")) == golfer_id:
			return record.duplicate(true)
	return {}


func projected_ball_record(ball_id: String) -> Dictionary:
	for value in projected_ball_records:
		var record: Dictionary = value
		if str(record.get("ball_id", "")) == ball_id:
			return record.duplicate(true)
	return {}


func projected_group(group_id: String) -> Dictionary:
	var target: String = group_id.strip_edges()
	var group_records: Array = []
	for value in projected_records:
		var record: Dictionary = value
		if str(record.get("group_id", "")) == target:
			group_records.append(record)
	if group_records.is_empty():
		return {}
	var first: Dictionary = group_records[0]
	return {
		"group_id": target,
		"status": str(first.get("group_status", "")),
		"projected_hole_number": int(first.get("projected_hole_number", 0)),
		"traffic_hole_number": int(first.get("traffic_hole_number", 0)),
		"member_count": group_records.size()
	}


func snapshot() -> Dictionary:
	var group_ids: Dictionary = {}
	for value in projected_records:
		var record: Dictionary = value
		group_ids[str(record.get("group_id", ""))] = true
	var groups: Array = []
	var ids: Array = group_ids.keys()
	ids.sort()
	for group_id in ids:
		groups.append(projected_group(str(group_id)))
	return {
		"group_count": groups.size(),
		"golfer_count": projected_records.size(),
		"ball_count": projected_ball_records.size(),
		"groups": groups,
		"records": projected_records.duplicate(true),
		"balls": projected_ball_records.duplicate(true)
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
	var id_a: String = str(a.get("golfer_id", a.get("ball_id", "")))
	var id_b: String = str(b.get("golfer_id", b.get("ball_id", "")))
	return id_a < id_b


func _draw() -> void:
	# Build one painter-sorted stream so moving golfers and their balls remain
	# visually coherent when paths cross after a cardinal camera rotation.
	var draw_items: Array = []
	for value in projected_records:
		var item: Dictionary = value.duplicate(true)
		item["draw_kind"] = "GOLFER"
		draw_items.append(item)
	for value in projected_ball_records:
		var item: Dictionary = value.duplicate(true)
		if not bool(item.get("visible", true)):
			continue
		item["draw_kind"] = "BALL"
		draw_items.append(item)
	draw_items.sort_custom(_projection_sort)

	for value in draw_items:
		var record: Dictionary = value
		var base: Vector2 = record.get("iso_position", Vector2.ZERO)
		if str(record.get("draw_kind", "")) == "BALL":
			draw_circle(base + Vector2(1.5, 1.3), ball_radius_pixels + 0.8, Color(0.02, 0.03, 0.02, 0.22))
			draw_circle(base, ball_radius_pixels, Color(0.98, 0.98, 0.96))
			continue
		draw_circle(base + Vector2(3.0, 2.0), shadow_radius_pixels, Color(0.02, 0.03, 0.02, 0.28))
		draw_line(base + Vector2(0.0, -2.0), base + Vector2(0.0, -body_height_pixels), Color(0.94, 0.94, 0.90), 2.6, true)
		draw_circle(base + Vector2(0.0, -body_height_pixels - 3.0), body_radius_pixels, Color(0.82, 0.84, 0.80))
