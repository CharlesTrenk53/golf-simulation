extends "res://scenes/poc31_isometric_construction.gd"

# POC-32A: Player-Facing Isometric Elevation
# -------------------------------------------
# Extends the POC-31 construction interface with economy-backed terrain
# sculpting. The authoritative grid still owns elevation. A small 3x3 weighted
# brush changes the selected tile most, then tapers into its neighbors so the
# existing continuous isometric renderer presents hills and swales rather than
# isolated stacked blocks.

const TERRAIN_STEP_YARDS: float = 0.25
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

	var changes: Array = []
	for offset_value in TERRAIN_BRUSH.keys():
		var offset: Vector2i = offset_value
		var affected := cell + offset
		if not grid.is_in_bounds(affected.x, affected.y):
			continue
		var weight: float = float(TERRAIN_BRUSH[offset])
		var current: float = float(grid.tile_at(affected.x, affected.y).get("elevation", 0.0))
		changes.append({
			"x": affected.x,
			"y": affected.y,
			"to_elevation": current + float(direction) * TERRAIN_STEP_YARDS * weight
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
		terrain_status_label.text = "3×3 tapered brush • %.2f yd center step" % TERRAIN_STEP_YARDS
