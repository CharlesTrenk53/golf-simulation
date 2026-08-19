extends Node2D

# POC-33E: Stylized Miniature Golfer Art
# ---------------------------------------
# Presentation-only replacement for the POC-33 placeholder stick glyphs. It
# consumes the already-projected golfer/ball snapshot and draws compact original
# miniature figures with group color, stance, club, shadow, and ball readability.
# No golfer state, shot result, or traffic state is authored here.

var source_layer = null
var construction_grid = null
var cached_snapshot: Dictionary = {}
var configured: bool = false


func configure(source_value, grid_value) -> bool:
	source_layer = source_value
	construction_grid = grid_value
	configured = source_layer != null and construction_grid != null and source_layer.has_method("snapshot")
	refresh_from_source()
	return configured


func _process(_delta: float) -> void:
	if configured:
		refresh_from_source()


func refresh_from_source() -> void:
	if not configured:
		cached_snapshot = {}
		queue_redraw()
		return
	cached_snapshot = source_layer.snapshot()
	queue_redraw()


func snapshot() -> Dictionary:
	var visible_golfers: int = 0
	var visible_balls: int = 0
	for value in cached_snapshot.get("records", []):
		var record: Dictionary = value
		if _on_property(record):
			visible_golfers += 1
	for value in cached_snapshot.get("balls", []):
		var record: Dictionary = value
		if bool(record.get("visible", true)) and _on_property(record):
			visible_balls += 1
	return {
		"configured": configured,
		"source_golfers": int(cached_snapshot.get("golfer_count", 0)),
		"source_balls": int(cached_snapshot.get("ball_count", 0)),
		"visible_golfers": visible_golfers,
		"visible_balls": visible_balls
	}


func _draw() -> void:
	if not configured:
		return
	var items: Array = []
	for value in cached_snapshot.get("records", []):
		var record: Dictionary = value
		if not _on_property(record):
			continue
		var copy := record.duplicate(true)
		copy["draw_kind"] = "GOLFER"
		items.append(copy)
	for value in cached_snapshot.get("balls", []):
		var record: Dictionary = value
		if not bool(record.get("visible", true)) or not _on_property(record):
			continue
		var copy := record.duplicate(true)
		copy["draw_kind"] = "BALL"
		items.append(copy)
	items.sort_custom(_projection_sort)

	for value in items:
		var record: Dictionary = value
		if str(record.get("draw_kind", "")) == "BALL":
			_draw_ball(record)
		else:
			_draw_golfer(record)


func _draw_ball(record: Dictionary) -> void:
	var base: Vector2 = record.get("iso_position", Vector2.ZERO)
	var flying: bool = bool(record.get("is_flying", false))
	var radius: float = 2.35 if flying else 1.85
	var shadow_offset := Vector2(2.0, 1.6)
	draw_circle(base + shadow_offset, radius + 1.1, Color(0.02, 0.03, 0.02, 0.25))
	draw_circle(base, radius + 0.8, Color(0.24, 0.25, 0.22, 0.88))
	draw_circle(base, radius, Color(1.0, 0.99, 0.94))
	if flying:
		draw_circle(base + Vector2(-0.6, -0.8), 0.7, Color(1.0, 1.0, 1.0, 0.95))


func _draw_golfer(record: Dictionary) -> void:
	var base: Vector2 = record.get("iso_position", Vector2.ZERO)
	var group_id: String = str(record.get("group_id", "group_1"))
	var golfer_id: String = str(record.get("golfer_id", ""))
	var shirt: Color = _group_color(group_id)
	var pants: Color = _pants_color(group_id)
	var skin := Color(0.79, 0.60, 0.43)
	var cap := shirt.darkened(0.18)
	var swinging: bool = _golfer_has_flying_ball(golfer_id)
	var waiting: bool = str(record.get("group_status", "")) == "WAITING"
	var finished: bool = str(record.get("group_status", "")) == "FINISHED"
	var alpha: float = 0.70 if finished else 1.0

	# Soft oval footprint sells the miniature-diorama scale while remaining small.
	draw_colored_polygon(_ellipse_points(base + Vector2(4.0, 2.5), 8.5, 3.2), Color(0.02, 0.03, 0.02, 0.28 * alpha))

	var hip := base + Vector2(0.0, -9.0)
	var shoulder := base + Vector2(-0.5, -18.0)
	var head := base + Vector2(-1.0, -25.0)

	# Legs. Waiting golfers stand relaxed; moving/playing figures read with a wider
	# stance so motion remains visible even at management-game zoom.
	var stride: float = 2.6 if waiting else 4.1
	if swinging:
		stride = 5.0
	draw_line(hip + Vector2(-1.0, 0.0), base + Vector2(-stride, -1.0), _with_alpha(pants.lightened(0.03), alpha), 2.8, true)
	draw_line(hip + Vector2(1.0, 0.0), base + Vector2(stride, 0.0), _with_alpha(pants.darkened(0.08), alpha), 2.8, true)
	draw_line(base + Vector2(-stride, -1.0), base + Vector2(-stride - 1.5, 0.0), Color(0.13, 0.12, 0.10, alpha), 2.4, true)
	draw_line(base + Vector2(stride, 0.0), base + Vector2(stride + 1.6, 1.0), Color(0.13, 0.12, 0.10, alpha), 2.4, true)

	# Torso, deliberately broader than the old stick figure so shirt color reads.
	var torso := PackedVector2Array([
		shoulder + Vector2(-5.0, 0.0),
		shoulder + Vector2(5.0, 0.8),
		hip + Vector2(3.6, 0.0),
		hip + Vector2(-3.8, -0.3)
	])
	draw_colored_polygon(torso, _with_alpha(shirt, alpha))
	draw_line(shoulder + Vector2(-4.0, 1.0), hip + Vector2(-3.0, -0.5), _with_alpha(shirt.darkened(0.16), alpha), 1.2, true)

	# Head and cap.
	draw_circle(head, 4.4, Color(0.20, 0.14, 0.10, 0.18 * alpha))
	draw_circle(head + Vector2(-0.6, -0.6), 3.8, _with_alpha(skin, alpha))
	draw_colored_polygon(PackedVector2Array([
		head + Vector2(-4.0, -3.4), head + Vector2(3.0, -3.3), head + Vector2(5.0, -1.6), head + Vector2(-3.4, -1.5)
	]), _with_alpha(cap, alpha))

	# Arms and club. A live RuntimeBallVisual flight produces a follow-through pose;
	# otherwise the club rests naturally beside the golfer.
	if swinging:
		var hand := shoulder + Vector2(7.0, 2.0)
		draw_line(shoulder + Vector2(2.5, 1.5), hand, _with_alpha(skin, alpha), 2.1, true)
		draw_line(shoulder + Vector2(-2.2, 1.6), hand + Vector2(-1.0, 1.0), _with_alpha(skin, alpha), 2.0, true)
		draw_line(hand, hand + Vector2(12.0, -12.0), Color(0.34, 0.34, 0.31, alpha), 1.35, true)
		draw_line(hand + Vector2(12.0, -12.0), hand + Vector2(15.0, -13.0), Color(0.18, 0.18, 0.16, alpha), 2.0, true)
	else:
		var hand := shoulder + Vector2(4.5, 4.0)
		draw_line(shoulder + Vector2(2.3, 1.4), hand, _with_alpha(skin, alpha), 1.9, true)
		draw_line(hand, base + Vector2(7.0, -1.0), Color(0.34, 0.34, 0.31, alpha), 1.25, true)
		draw_line(base + Vector2(7.0, -1.0), base + Vector2(10.0, -0.3), Color(0.17, 0.17, 0.15, alpha), 1.8, true)


func _golfer_has_flying_ball(golfer_id: String) -> bool:
	for value in cached_snapshot.get("balls", []):
		var ball: Dictionary = value
		if str(ball.get("golfer_id", "")) == golfer_id and bool(ball.get("is_flying", false)):
			return true
	return false


func _on_property(record: Dictionary) -> bool:
	var gp_value = record.get("grid_position", null)
	if typeof(gp_value) != TYPE_VECTOR2:
		return false
	var gp: Vector2 = gp_value
	return gp.x >= 0.0 and gp.y >= 0.0 and gp.x <= float(construction_grid.width) and gp.y <= float(construction_grid.height)


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


func _group_color(group_id: String) -> Color:
	match group_id:
		"group_1":
			return Color(0.22, 0.47, 0.78)
		"group_2":
			return Color(0.79, 0.31, 0.22)
		"group_3":
			return Color(0.85, 0.66, 0.18)
		_:
			return Color(0.31, 0.60, 0.45)


func _pants_color(group_id: String) -> Color:
	if group_id == "group_2":
		return Color(0.30, 0.29, 0.27)
	return Color(0.83, 0.81, 0.72)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _ellipse_points(center: Vector2, radius_x: float, radius_y: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(16):
		var angle := TAU * float(i) / 16.0
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points
