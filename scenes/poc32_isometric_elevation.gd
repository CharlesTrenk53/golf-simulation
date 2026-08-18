extends "res://scenes/poc31_isometric_construction.gd"

# POC-32A / POC-32B: Player-Facing Isometric Elevation
# -----------------------------------------------------
# Extends the POC-31 construction interface with economy-backed terrain
# sculpting. The authoritative grid still owns elevation. A small 3x3 weighted
# brush changes the selected tile most, then tapers into its neighbors so the
# existing continuous isometric renderer presents hills and swales rather than
# isolated stacked blocks.
#
# POC-32B preserves the visually accepted normal brush exactly, while adding a
# physically interpretable safety rule for repeated edits: adjacent 10-yard
# terrain cells may not be driven beyond a 20% grade by a sculpt action. When a
# repeated raise/lower would create a cliff, the edit naturally propagates into
# surrounding cells instead of clipping the player's requested center height.

const TERRAIN_STEP_YARDS: float = 0.25
const MAX_ADJACENT_GRADE: float = 0.20
const TERRAIN_EPSILON: float = 0.000000001
const TERRAIN_BRUSH := {
	Vector2i(0, 0): 1.0,
	Vector2i(0, -1): 0.5,
	Vector2i(1, 0): 0.5,
	Vector2i(0, 1): 0.5,
	Vector2i(-1, 0): 0.5,
	Vector2i(-1, -1): 0.25,
	Vector2i(1, -1): 0.25,
	Vector2i(1, 1): 0.25,
	Vector2i(-1, 1): 0.25
}
const CARDINAL_OFFSETS := [
	Vector2i(0, -1),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 0)
]

var terrain_target_label: Label = null
var terrain_quote_label: Label = null
var terrain_status_label: Label = null


func _ready() -> void:
	super._ready()
	if not initialized:
		return
	_add_terrain_hud()
	_update_hud()


func quote_terrain_sculpt(cell: Vector2i, direction: int) -> Dictionary:
	if economy == null or grid == null:
		return {"valid": false, "reason": "NOT_INITIALIZED", "cost": 0}
	if direction != -1 and direction != 1:
		return {"valid": false, "reason": "INVALID_TERRAIN_DIRECTION", "cost": 0}
	if not grid.is_in_bounds(cell.x, cell.y):
		return {"valid": false, "reason": "OUT_OF_BOUNDS", "cost": 0}

	var target_elevations := {}
	for offset_value in TERRAIN_BRUSH.keys():
		var offset: Vector2i = offset_value
		var affected := cell + offset
		if not grid.is_in_bounds(affected.x, affected.y):
			continue
		var weight: float = float(TERRAIN_BRUSH[offset])
		var current: float = _elevation_at(affected)
		target_elevations[affected] = current + float(direction) * TERRAIN_STEP_YARDS * weight

	# Normal single-click edits remain the accepted tapered 3x3 shape. Only when
	# repeated sculpting would exceed the slope safety ceiling does the target map
	# spread outward to keep the authored terrain continuous and believable.
	var stabilized: Dictionary = _stabilize_terrain_targets(target_elevations, direction)
	var cells: Array = stabilized.keys()
	cells.sort_custom(func(a, b):
		var cell_a: Vector2i = a
		var cell_b: Vector2i = b
		return cell_a.y < cell_b.y or (cell_a.y == cell_b.y and cell_a.x < cell_b.x)
	)

	var changes: Array = []
	for cell_value in cells:
		var changed_cell: Vector2i = cell_value
		var from_elevation: float = _elevation_at(changed_cell)
		var to_elevation: float = float(stabilized[changed_cell])
		if absf(to_elevation - from_elevation) <= TERRAIN_EPSILON:
			continue
		changes.append({
			"x": changed_cell.x,
			"y": changed_cell.y,
			"to_elevation": to_elevation
		})
	return economy.quote_elevation_changes(changes)


func sculpt_terrain(cell: Vector2i, direction: int) -> Dictionary:
	var quote: Dictionary = quote_terrain_sculpt(cell, direction)
	if not bool(quote.get("valid", false)):
		current_status = "Terrain edit rejected: %s" % str(quote.get("reason", "UNKNOWN"))
		_update_hud()
		return quote

	var result: Dictionary = economy.build_elevation_changes(quote.get("changes", []))
	if bool(result.get("built", false)):
		selected_cell = cell
		renderer.set_selected_cell(cell)
		renderer.queue_redraw()
		var verb := "Raised" if direction > 0 else "Lowered"
		current_status = "%s terrain at (%d, %d) for $%d" % [
			verb,
			cell.x,
			cell.y,
			int(result.get("cost", 0))
		]
	else:
		current_status = "Terrain edit rejected: %s" % str(result.get("reason", "UNKNOWN"))
	_update_hud()
	return result


func max_cardinal_terrain_grade() -> float:
	if grid == null or float(grid.tile_size_yards) <= 0.0:
		return 0.0
	var maximum: float = 0.0
	for y in range(int(grid.height)):
		for x in range(int(grid.width)):
			var here := Vector2i(x, y)
			var here_elevation: float = _elevation_at(here)
			for offset in [Vector2i(1, 0), Vector2i(0, 1)]:
				var neighbor := here + offset
				if not grid.is_in_bounds(neighbor.x, neighbor.y):
					continue
				var grade: float = absf(here_elevation - _elevation_at(neighbor)) / float(grid.tile_size_yards)
				maximum = maxf(maximum, grade)
	return maximum


func _stabilize_terrain_targets(initial_targets: Dictionary, direction: int) -> Dictionary:
	var stabilized: Dictionary = initial_targets.duplicate(true)
	if grid == null or stabilized.is_empty():
		return stabilized

	var maximum_delta: float = float(grid.tile_size_yards) * MAX_ADJACENT_GRADE
	var work_queue: Array = stabilized.keys()
	var cursor: int = 0

	# Raising is monotonic upward and lowering is monotonic downward, so this
	# relaxation cannot oscillate. A strong edit can propagate several cells, but
	# only as far as needed to satisfy the grade ceiling.
	while cursor < work_queue.size():
		var cell: Vector2i = work_queue[cursor]
		cursor += 1
		var cell_elevation: float = float(stabilized.get(cell, _elevation_at(cell)))

		for offset in CARDINAL_OFFSETS:
			var neighbor := cell + offset
			if not grid.is_in_bounds(neighbor.x, neighbor.y):
				continue
			var neighbor_elevation: float = float(stabilized.get(neighbor, _elevation_at(neighbor)))

			if direction > 0 and cell_elevation - neighbor_elevation > maximum_delta + TERRAIN_EPSILON:
				var raised_neighbor: float = cell_elevation - maximum_delta
				if raised_neighbor > neighbor_elevation + TERRAIN_EPSILON:
					stabilized[neighbor] = raised_neighbor
					work_queue.append(neighbor)
			elif direction < 0 and neighbor_elevation - cell_elevation > maximum_delta + TERRAIN_EPSILON:
				var lowered_neighbor: float = cell_elevation + maximum_delta
				if lowered_neighbor < neighbor_elevation - TERRAIN_EPSILON:
					stabilized[neighbor] = lowered_neighbor
					work_queue.append(neighbor)

	return stabilized


func _elevation_at(cell: Vector2i) -> float:
	return float(grid.tile_at(cell.x, cell.y).get("elevation", 0.0))


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_sculpt_current_target(1)
		elif event.keycode == KEY_F:
			_sculpt_current_target(-1)


func _process(delta: float) -> void:
	super._process(delta)
	_update_terrain_hud()


func _update_hud() -> void:
	super._update_hud()
	_update_terrain_hud()


func _add_terrain_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TerrainHUD"
	layer.layer = 20
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(318.0, 16.0)
	panel.size = Vector2(250.0, 172.0)
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	margin.add_child(stack)

	var title := Label.new()
	title.text = "TERRAIN SCULPTING"
	title.add_theme_font_size_override("font_size", 17)
	stack.add_child(title)

	terrain_target_label = Label.new()
	stack.add_child(terrain_target_label)
	terrain_quote_label = Label.new()
	stack.add_child(terrain_quote_label)

	var button_row := HBoxContainer.new()
	var raise_button := Button.new()
	raise_button.text = "Raise (R)"
	raise_button.pressed.connect(_sculpt_current_target.bind(1))
	button_row.add_child(raise_button)
	var lower_button := Button.new()
	lower_button.text = "Lower (F)"
	lower_button.pressed.connect(_sculpt_current_target.bind(-1))
	button_row.add_child(lower_button)
	stack.add_child(button_row)

	terrain_status_label = Label.new()
	terrain_status_label.text = "Right click a tile to select terrain."
	terrain_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(terrain_status_label)


func _sculpt_current_target(direction: int) -> void:
	var target := _terrain_target_cell()
	if target == INVALID_CELL:
		current_status = "Select a tile before sculpting terrain"
		_update_hud()
		return
	sculpt_terrain(target, direction)


func _terrain_target_cell() -> Vector2i:
	if selected_cell != INVALID_CELL and grid != null and grid.is_in_bounds(selected_cell.x, selected_cell.y):
		return selected_cell
	if hovered_cell != INVALID_CELL and grid != null and grid.is_in_bounds(hovered_cell.x, hovered_cell.y):
		return hovered_cell
	return INVALID_CELL


func _update_terrain_hud() -> void:
	if terrain_target_label == null or terrain_quote_label == null:
		return
	var target := _terrain_target_cell()
	if target == INVALID_CELL or grid == null:
		terrain_target_label.text = "Target: —"
		terrain_quote_label.text = "Raise: —   Lower: —"
		return
	var elevation: float = float(grid.tile_at(target.x, target.y).get("elevation", 0.0))
	var raise_quote: Dictionary = quote_terrain_sculpt(target, 1)
	var lower_quote: Dictionary = quote_terrain_sculpt(target, -1)
	terrain_target_label.text = "Target: (%d, %d)   Elev: %.2f yd" % [target.x, target.y, elevation]
	terrain_quote_label.text = "Raise: $%d   Lower: $%d" % [
		int(raise_quote.get("cost", 0)),
		int(lower_quote.get("cost", 0))
	]
	if terrain_status_label != null:
		terrain_status_label.text = "3×3 tapered brush • %.2f yd center step • slope-safe" % TERRAIN_STEP_YARDS
