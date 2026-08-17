extends "res://scenes/isometric_rotatable_course_renderer.gd"

# POC-31A: Interactive Isometric Course Renderer
# -----------------------------------------------
# Adds presentation-only hover/selection and robust point-to-cell picking over
# the proven rotatable renderer. The authoritative construction grid remains the
# only owner of golf surfaces/elevation; this class never mutates it directly.

var hovered_cell := Vector2i(-1, -1)
var selected_cell := Vector2i(-1, -1)

const HOVER_FILL := Color(1.0, 1.0, 1.0, 0.16)
const HOVER_OUTLINE := Color(0.96, 0.97, 0.88, 0.92)
const SELECT_FILL := Color(1.0, 0.83, 0.22, 0.16)
const SELECT_OUTLINE := Color(1.0, 0.82, 0.18, 1.0)


func set_hovered_cell(cell: Vector2i) -> void:
	var normalized := _normalize_cell(cell)
	if normalized == hovered_cell:
		return
	hovered_cell = normalized
	queue_redraw()


func set_selected_cell(cell: Vector2i) -> void:
	var normalized := _normalize_cell(cell)
	if normalized == selected_cell:
		return
	selected_cell = normalized
	queue_redraw()


func clear_interaction() -> void:
	hovered_cell = Vector2i(-1, -1)
	selected_cell = Vector2i(-1, -1)
	queue_redraw()


func pick_cell_at_local_point(point: Vector2) -> Vector2i:
	if construction_grid == null:
		return Vector2i(-1, -1)

	# Search front-to-back so the cell that is visually on top wins if steep
	# terrain ever causes projected polygons to overlap.
	var cells: Array[Vector2i] = []
	for y in range(int(construction_grid.height)):
		for x in range(int(construction_grid.width)):
			cells.append(Vector2i(x, y))
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var depth_a: float = _view_depth(float(a.x) + 0.5, float(a.y) + 0.5)
		var depth_b: float = _view_depth(float(b.x) + 0.5, float(b.y) + 0.5)
		if not is_equal_approx(depth_a, depth_b):
			return depth_a > depth_b
		return _view_lateral(float(a.x) + 0.5, float(a.y) + 0.5) > _view_lateral(float(b.x) + 0.5, float(b.y) + 0.5)
	)

	for cell in cells:
		var polygon: PackedVector2Array = tile_corners_iso(cell.x, cell.y)
		if polygon.size() == 4 and Geometry2D.is_point_in_polygon(point, polygon):
			return cell
	return Vector2i(-1, -1)


func _draw() -> void:
	super._draw()
	_draw_cell_highlight(hovered_cell, HOVER_FILL, HOVER_OUTLINE, 2.0)
	_draw_cell_highlight(selected_cell, SELECT_FILL, SELECT_OUTLINE, 3.0)


func _draw_cell_highlight(cell: Vector2i, fill: Color, outline: Color, width: float) -> void:
	if not _cell_is_valid(cell):
		return
	var polygon: PackedVector2Array = tile_corners_iso(cell.x, cell.y)
	if polygon.size() != 4:
		return
	draw_colored_polygon(polygon, fill)
	for i in range(4):
		draw_line(polygon[i], polygon[(i + 1) % 4], outline, width, true)


func _normalize_cell(cell: Vector2i) -> Vector2i:
	if _cell_is_valid(cell):
		return cell
	return Vector2i(-1, -1)


func _cell_is_valid(cell: Vector2i) -> bool:
	return construction_grid != null and construction_grid.is_in_bounds(cell.x, cell.y)
