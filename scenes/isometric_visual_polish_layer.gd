extends Node2D

# POC-33E: Isometric Visual Polish Layer
# ---------------------------------------
# Presentation-only art pass inspired by the dense miniature-course readability
# target established during hands-on review. CourseConstructionGrid remains the
# sole surface/elevation authority. This layer adds deterministic texture,
# vegetation clusters, a small clubhouse landmark, and path dressing without
# changing construction, simulation, traffic, or shot outcomes.

var course_renderer = null
var construction_grid = null
var decorations: Array = []
var clubhouse_grid := Vector2(-1.0, -1.0)
var path_grid_points: Array = []
var configured: bool = false
var _last_rotation: int = -999


func configure(renderer_value, grid_value) -> bool:
	course_renderer = renderer_value
	construction_grid = grid_value
	configured = (
		course_renderer != null
		and construction_grid != null
		and int(construction_grid.width) > 0
		and int(construction_grid.height) > 0
		and course_renderer.has_method("grid_to_iso")
		and course_renderer.has_method("tile_corners_iso")
		and course_renderer.has_method("terrain_height_at_grid_position")
	)
	if not configured:
		decorations.clear()
		path_grid_points.clear()
		queue_redraw()
		return false
	clubhouse_grid = _find_clubhouse_site()
	_build_path()
	_build_decorations()
	_last_rotation = _rotation_quarters()
	queue_redraw()
	return true


func _process(_delta: float) -> void:
	if not configured:
		return
	var rotation := _rotation_quarters()
	if rotation != _last_rotation:
		_last_rotation = rotation
		queue_redraw()


func snapshot() -> Dictionary:
	var counts := {}
	for value in decorations:
		var record: Dictionary = value
		var kind: String = str(record.get("kind", "UNKNOWN"))
		counts[kind] = int(counts.get(kind, 0)) + 1
	return {
		"configured": configured,
		"decoration_count": decorations.size(),
		"counts": counts,
		"clubhouse_grid": clubhouse_grid,
		"path_points": path_grid_points.size(),
		"rotation_quarters": _rotation_quarters()
	}


func focus_center() -> Vector2:
	if not configured:
		return Vector2.ZERO
	var total := Vector2.ZERO
	var count: int = 0
	for y in range(int(construction_grid.height)):
		for x in range(int(construction_grid.width)):
			if str(construction_grid.surface_at(x, y)) == "ROUGH":
				continue
			total += course_renderer.cell_center_iso(x, y)
			count += 1
	if count == 0:
		return course_renderer.visual_bounds().get_center()
	return total / float(count)


func _draw() -> void:
	if not configured:
		return
	_draw_surface_texture()
	_draw_path()
	_draw_decorations()
	_draw_clubhouse()


func _draw_surface_texture() -> void:
	for y in range(int(construction_grid.height)):
		for x in range(int(construction_grid.width)):
			var surface: String = str(construction_grid.surface_at(x, y))
			var corners: PackedVector2Array = course_renderer.tile_corners_iso(x, y)
			if corners.size() != 4:
				continue
			var center: Vector2 = course_renderer.cell_center_iso(x, y)
			match surface:
				"FAIRWAY":
					var stripe_alpha: float = 0.055 if (y / 2) % 2 == 0 else 0.018
					draw_colored_polygon(_inset(corners, 0.08), Color(0.88, 0.98, 0.72, stripe_alpha))
					if _hash01(x, y, 5) > 0.62:
						_draw_grass_ticks(center, Color(0.16, 0.34, 0.11, 0.16), 0.72)
				"TEE":
					draw_colored_polygon(_inset(corners, 0.12), Color(0.94, 1.0, 0.84, 0.08))
				"GREEN":
					draw_colored_polygon(_inset(corners, 0.11), Color(0.92, 1.0, 0.82, 0.07))
					if (x + y) % 3 == 0:
						draw_arc(center, 8.5, 0.15, PI + 0.15, 16, Color(0.26, 0.52, 0.18, 0.12), 1.0, true)
				"FRINGE":
					draw_colored_polygon(_inset(corners, 0.10), Color(0.79, 0.94, 0.63, 0.035))
				"BUNKER":
					for i in range(4):
						var angle: float = TAU * _hash01(x, y, 40 + i)
						var radius: float = 3.0 + 8.0 * _hash01(x, y, 60 + i)
						var p := center + Vector2(cos(angle) * radius, sin(angle) * radius * 0.42)
						draw_circle(p, 0.9 + _hash01(x, y, 80 + i) * 0.7, Color(0.58, 0.43, 0.22, 0.32))
				"ROUGH":
					var h := _hash01(x, y, 17)
					if h > 0.73:
						_draw_grass_ticks(center + Vector2((_hash01(x, y, 18) - 0.5) * 12.0, (_hash01(x, y, 19) - 0.5) * 5.0), Color(0.10, 0.28, 0.09, 0.18), 0.86)
				_:
					pass


func _draw_grass_ticks(center: Vector2, color: Color, scale_value: float) -> void:
	var s := scale_value
	draw_line(center + Vector2(-2.0, 1.0) * s, center + Vector2(-3.5, -3.0) * s, color, 1.0, true)
	draw_line(center + Vector2(0.0, 1.0) * s, center + Vector2(0.0, -4.0) * s, color, 1.0, true)
	draw_line(center + Vector2(2.0, 1.0) * s, center + Vector2(3.5, -2.5) * s, color, 1.0, true)


func _build_decorations() -> void:
	decorations.clear()
	for y in range(int(construction_grid.height)):
		for x in range(int(construction_grid.width)):
			if not _deep_rough(x, y):
				continue
			if clubhouse_grid.x >= 0.0 and Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(clubhouse_grid) < 4.5:
				continue
			var cluster_x: int = floori(float(x) / 5.0)
			var cluster_y: int = floori(float(y) / 5.0)
			var cluster_strength: float = _hash01(cluster_x, cluster_y, 211)
			if cluster_strength < 0.38:
				continue
			var local: float = _hash01(x, y, 101)
			if local < 0.13:
				var type_roll: float = _hash01(x, y, 102)
				var kind := "TREE"
				if type_roll < 0.22:
					kind = "PINE"
				elif type_roll > 0.86:
					kind = "FLOWERING_TREE"
				decorations.append(_decoration_record(kind, x, y, 0.76 + _hash01(x, y, 103) * 0.38))
				if _hash01(x, y, 104) > 0.62:
					decorations.append(_decoration_record("SHRUB", x, y, 0.62 + _hash01(x, y, 105) * 0.28, Vector2(2.6, -1.8)))
			elif local < 0.175:
				decorations.append(_decoration_record("SHRUB", x, y, 0.62 + _hash01(x, y, 106) * 0.30))
			elif local > 0.965:
				var accent := "FLOWERS" if _hash01(x, y, 108) > 0.42 else "ROCK"
				decorations.append(_decoration_record(accent, x, y, 0.70 + _hash01(x, y, 109) * 0.35))

	if clubhouse_grid.x >= 0.0:
		for offset in [Vector2(-2.7, 0.4), Vector2(2.5, 0.6), Vector2(-2.1, -1.8), Vector2(2.2, -1.7)]:
			decorations.append({"kind": "FLOWERS", "grid_position": clubhouse_grid + offset, "scale": 1.0})
		for offset in [Vector2(-3.0, 2.0), Vector2(3.0, 2.0), Vector2(-3.4, -1.2), Vector2(3.4, -1.1)]:
			decorations.append({"kind": "SHRUB", "grid_position": clubhouse_grid + offset, "scale": 0.86})


func _decoration_record(kind: String, x: int, y: int, scale_value: float, pixel_jitter: Vector2 = Vector2.ZERO) -> Dictionary:
	var jitter_x: float = (_hash01(x, y, 301) - 0.5) * 0.52
	var jitter_y: float = (_hash01(x, y, 302) - 0.5) * 0.52
	return {
		"kind": kind,
		"grid_position": Vector2(float(x) + 0.5 + jitter_x, float(y) + 0.5 + jitter_y),
		"scale": scale_value,
		"pixel_jitter": pixel_jitter
	}


func _draw_decorations() -> void:
	var sorted: Array = decorations.duplicate(true)
	sorted.sort_custom(func(a_value, b_value) -> bool:
		var a: Dictionary = a_value
		var b: Dictionary = b_value
		return _view_depth(a.get("grid_position", Vector2.ZERO)) < _view_depth(b.get("grid_position", Vector2.ZERO))
	)
	for value in sorted:
		var record: Dictionary = value
		var gp: Vector2 = record.get("grid_position", Vector2.ZERO)
		if not _grid_point_on_property(gp):
			continue
		var base := _iso_at_grid(gp) + record.get("pixel_jitter", Vector2.ZERO)
		var s: float = float(record.get("scale", 1.0))
		match str(record.get("kind", "")):
			"PINE":
				_draw_pine(base, s)
			"FLOWERING_TREE":
				_draw_broadleaf(base, s, true)
			"TREE":
				_draw_broadleaf(base, s, false)
			"SHRUB":
				_draw_shrub(base, s)
			"FLOWERS":
				_draw_flowers(base, s)
			"ROCK":
				_draw_rock(base, s)


func _draw_broadleaf(base: Vector2, scale_value: float, flowering: bool) -> void:
	var s: float = clampf(scale_value, 0.58, 1.25)
	draw_colored_polygon(_ellipse_points(base + Vector2(8.0 * s, 2.5), 12.0 * s, 4.5 * s), Color(0.03, 0.05, 0.02, 0.24))
	draw_line(base, base + Vector2(0.0, -16.0 * s), Color(0.31, 0.20, 0.10), 3.2 * s, true)
	var crown := base + Vector2(0.0, -22.0 * s)
	var dark := Color(0.10, 0.30, 0.10)
	var mid := Color(0.15, 0.40, 0.13)
	var light := Color(0.24, 0.50, 0.18)
	if flowering:
		dark = Color(0.34, 0.24, 0.30)
		mid = Color(0.70, 0.39, 0.52)
		light = Color(0.91, 0.61, 0.71)
	draw_circle(crown + Vector2(-6.0 * s, 1.0), 9.0 * s, dark)
	draw_circle(crown + Vector2(6.0 * s, 0.0), 8.7 * s, mid)
	draw_circle(crown + Vector2(0.0, -7.0 * s), 10.0 * s, mid)
	draw_circle(crown + Vector2(-3.0 * s, -10.0 * s), 5.0 * s, light)
	if flowering:
		for p in [Vector2(-7, -4), Vector2(6, -8), Vector2(2, 3), Vector2(-1, -13)]:
			draw_circle(crown + p * s, 1.7 * s, Color(1.0, 0.78, 0.84, 0.90))


func _draw_pine(base: Vector2, scale_value: float) -> void:
	var s: float = clampf(scale_value, 0.60, 1.25)
	draw_colored_polygon(_ellipse_points(base + Vector2(7.0 * s, 2.5), 10.0 * s, 3.7 * s), Color(0.03, 0.05, 0.03, 0.24))
	draw_line(base, base + Vector2(0.0, -24.0 * s), Color(0.29, 0.19, 0.11), 2.6 * s, true)
	for layer in range(3):
		var y: float = -11.0 * s - float(layer) * 7.0 * s
		var width: float = (12.0 - float(layer) * 2.1) * s
		var height: float = 16.0 * s
		var tri := PackedVector2Array([
			base + Vector2(0.0, y - height * 0.62),
			base + Vector2(-width, y + height * 0.38),
			base + Vector2(width, y + height * 0.38)
		])
		draw_colored_polygon(tri, Color(0.09 + 0.025 * layer, 0.27 + 0.035 * layer, 0.13 + 0.02 * layer))


func _draw_shrub(base: Vector2, scale_value: float) -> void:
	var s := clampf(scale_value, 0.5, 1.1)
	draw_colored_polygon(_ellipse_points(base + Vector2(3.0 * s, 1.5), 7.0 * s, 2.6 * s), Color(0.02, 0.05, 0.02, 0.18))
	draw_circle(base + Vector2(-4.0 * s, -4.0 * s), 5.2 * s, Color(0.13, 0.34, 0.11))
	draw_circle(base + Vector2(4.0 * s, -3.5 * s), 5.0 * s, Color(0.18, 0.40, 0.13))
	draw_circle(base + Vector2(0.0, -7.0 * s), 5.5 * s, Color(0.22, 0.46, 0.16))


func _draw_flowers(base: Vector2, scale_value: float) -> void:
	var s := clampf(scale_value, 0.55, 1.2)
	draw_colored_polygon(_ellipse_points(base, 8.0 * s, 3.0 * s), Color(0.11, 0.29, 0.10, 0.55))
	var colors := [Color(0.97, 0.68, 0.78), Color(0.93, 0.86, 0.45), Color(0.73, 0.66, 0.94), Color(0.96, 0.90, 0.88)]
	for i in range(7):
		var angle: float = TAU * float(i) / 7.0
		var p := base + Vector2(cos(angle) * 5.5 * s, sin(angle) * 1.8 * s)
		draw_circle(p, 1.4 * s, colors[i % colors.size()])


func _draw_rock(base: Vector2, scale_value: float) -> void:
	var s := clampf(scale_value, 0.55, 1.2)
	draw_colored_polygon(_ellipse_points(base + Vector2(3.0 * s, 1.5), 8.0 * s, 2.8 * s), Color(0.02, 0.03, 0.02, 0.20))
	var rock := PackedVector2Array([
		base + Vector2(-7.0, 0.0) * s,
		base + Vector2(-5.0, -7.0) * s,
		base + Vector2(1.0, -10.0) * s,
		base + Vector2(8.0, -5.0) * s,
		base + Vector2(7.0, 1.0) * s
	])
	draw_colored_polygon(rock, Color(0.46, 0.48, 0.43))
	draw_line(base + Vector2(-3.0, -6.0) * s, base + Vector2(3.0, -8.0) * s, Color(0.66, 0.67, 0.61, 0.65), 1.2 * s, true)


func _find_clubhouse_site() -> Vector2:
	var preferred := Vector2i(maxi(int(construction_grid.width) / 5, 4), maxi(int(construction_grid.height) / 4, 4))
	var best := Vector2(-1.0, -1.0)
	var best_distance := INF
	for y in range(3, int(construction_grid.height) - 3):
		for x in range(3, int(construction_grid.width) - 3):
			if not _rough_patch(x, y, 2):
				continue
			var d: float = Vector2(float(x), float(y)).distance_to(Vector2(preferred))
			if d < best_distance:
				best_distance = d
				best = Vector2(float(x) + 0.5, float(y) + 0.5)
	return best


func _rough_patch(cx: int, cy: int, radius: int) -> bool:
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if not construction_grid.is_in_bounds(x, y) or str(construction_grid.surface_at(x, y)) != "ROUGH":
				return false
	return true


func _deep_rough(x: int, y: int) -> bool:
	if str(construction_grid.surface_at(x, y)) != "ROUGH":
		return false
	for offset in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if str(construction_grid.surface_at(x + offset.x, y + offset.y)) != "ROUGH":
			return false
	return true


func _build_path() -> void:
	path_grid_points.clear()
	if clubhouse_grid.x < 0.0:
		return
	var tee := _nearest_surface_cell("TEE", clubhouse_grid)
	if tee.x < 0.0:
		return
	var midpoint := clubhouse_grid.lerp(tee, 0.48)
	midpoint += Vector2(1.5, -1.2)
	path_grid_points = [clubhouse_grid + Vector2(0.0, 1.7), clubhouse_grid.lerp(midpoint, 0.52), midpoint, midpoint.lerp(tee, 0.55), tee]


func _nearest_surface_cell(surface: String, origin_grid: Vector2) -> Vector2:
	var best := Vector2(-1.0, -1.0)
	var best_distance := INF
	for y in range(int(construction_grid.height)):
		for x in range(int(construction_grid.width)):
			if str(construction_grid.surface_at(x, y)) != surface:
				continue
			var gp := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d := gp.distance_to(origin_grid)
			if d < best_distance:
				best_distance = d
				best = gp
	return best


func _draw_path() -> void:
	if path_grid_points.size() < 2:
		return
	var points := PackedVector2Array()
	for gp_value in path_grid_points:
		var gp: Vector2 = gp_value
		points.append(_iso_at_grid(gp))
	draw_polyline(points, Color(0.12, 0.10, 0.06, 0.23), 8.5, true)
	draw_polyline(points, Color(0.72, 0.64, 0.46, 0.96), 5.5, true)
	draw_polyline(points, Color(0.88, 0.82, 0.64, 0.45), 1.3, true)


func _draw_clubhouse() -> void:
	if clubhouse_grid.x < 0.0:
		return
	var base := _iso_at_grid(clubhouse_grid)
	draw_colored_polygon(_ellipse_points(base + Vector2(10.0, 4.0), 34.0, 8.0), Color(0.02, 0.03, 0.02, 0.26))
	var left_wall := PackedVector2Array([
		base + Vector2(-27.0, -24.0), base + Vector2(0.0, -11.0), base + Vector2(0.0, 8.0), base + Vector2(-27.0, -5.0)
	])
	var right_wall := PackedVector2Array([
		base + Vector2(0.0, -11.0), base + Vector2(28.0, -25.0), base + Vector2(28.0, -6.0), base + Vector2(0.0, 8.0)
	])
	draw_colored_polygon(left_wall, Color(0.79, 0.72, 0.58))
	draw_colored_polygon(right_wall, Color(0.70, 0.63, 0.50))
	var roof := PackedVector2Array([
		base + Vector2(-32.0, -25.0), base + Vector2(0.0, -43.0), base + Vector2(33.0, -26.0), base + Vector2(0.0, -8.0)
	])
	draw_colored_polygon(roof, Color(0.37, 0.16, 0.12))
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[3], roof[0]]), Color(0.18, 0.09, 0.07, 0.85), 1.6, true)
	# front doors/windows
	draw_colored_polygon(PackedVector2Array([base + Vector2(-8,-12), base + Vector2(-1,-8), base + Vector2(-1,2), base + Vector2(-8,-2)]), Color(0.20, 0.25, 0.22))
	draw_colored_polygon(PackedVector2Array([base + Vector2(7,-14), base + Vector2(14,-17), base + Vector2(14,-9), base + Vector2(7,-6)]), Color(0.33, 0.53, 0.58))
	# chimney
	draw_rect(Rect2(base + Vector2(13.0, -46.0), Vector2(5.0, 15.0)), Color(0.43, 0.33, 0.25))


func _iso_at_grid(gp: Vector2) -> Vector2:
	var elevation: float = float(course_renderer.terrain_height_at_grid_position(gp.x, gp.y))
	return course_renderer.grid_to_iso(gp.x, gp.y, elevation)


func _view_depth(gp: Vector2) -> float:
	if course_renderer.has_method("rotated_grid_position"):
		var rotated: Vector2 = course_renderer.rotated_grid_position(gp.x, gp.y)
		return rotated.x + rotated.y
	return gp.x + gp.y


func _rotation_quarters() -> int:
	if course_renderer == null:
		return 0
	var value = course_renderer.get("rotation_quarters")
	return int(value) if value != null else 0


func _grid_point_on_property(gp: Vector2) -> bool:
	return gp.x >= 0.0 and gp.y >= 0.0 and gp.x <= float(construction_grid.width) and gp.y <= float(construction_grid.height)


func _inset(corners: PackedVector2Array, amount: float) -> PackedVector2Array:
	var center := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
	var result := PackedVector2Array()
	for corner in corners:
		result.append(corner.lerp(center, amount))
	return result


func _ellipse_points(center: Vector2, radius_x: float, radius_y: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(18):
		var angle := TAU * float(i) / 18.0
		points.append(center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	return points


func _hash01(x: int, y: int, salt: int) -> float:
	var value: float = sin(float(x * 127 + y * 311 + salt * 74) * 0.173) * 43758.5453
	return value - floor(value)
