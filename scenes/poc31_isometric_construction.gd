extends Node2D

# POC-31: Player-Facing Isometric Construction
# ----------------------------------------------
# First actual construction-game surface over the POC-30 isometric architecture.
# Input selects authoritative grid cells; paid changes route through the existing
# construction economy; presentation never becomes golf-rule authority.

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const CourseConstructionEconomy = preload("res://simulation/course_construction_economy.gd")
const ConstructionGridHoleBuilder = preload("res://simulation/construction_grid_hole_builder.gd")
const InteractiveRenderer = preload("res://scenes/isometric_interactive_course_renderer.gd")

const GRID_WIDTH := 24
const GRID_HEIGHT := 24
const TILE_SIZE_YARDS := 10.0
const STARTING_CASH := 30000
const INVALID_CELL := Vector2i(-1, -1)
const DEFAULT_SAVE_PATH := "user://poc31_player_course.json"
const SURFACE_KEYS := {
	KEY_1: "ROUGH",
	KEY_2: "FAIRWAY",
	KEY_3: "TEE",
	KEY_4: "FRINGE",
	KEY_5: "GREEN",
	KEY_6: "BUNKER",
	KEY_7: "WATER"
}

var grid = null
var economy = null
var renderer = null
var camera: Camera2D = null
var selected_surface: String = "FAIRWAY"
var hovered_cell := INVALID_CELL
var selected_cell := INVALID_CELL
var tee_anchor := INVALID_CELL
var cup_cell := INVALID_CELL
var current_status: String = "Ready"
var initialized: bool = false

var funds_label: Label = null
var tool_label: Label = null
var hover_label: Label = null
var marker_label: Label = null
var status_label: Label = null
var palette_buttons := {}


func _ready() -> void:
	if not initialize_property():
		push_error("POC-31 construction property failed to initialize")
		return
	_add_background()
	_add_camera()
	_add_hud()
	_update_hud()


func initialize_property() -> bool:
	if initialized and grid != null and economy != null and renderer != null:
		return true

	grid = CourseConstructionGrid.new()
	if not grid.configure(GRID_WIDTH, GRID_HEIGHT, TILE_SIZE_YARDS, Vector2(-120.0, -120.0)):
		return false
	_author_starting_landform()

	economy = CourseConstructionEconomy.new()
	if not economy.configure(grid, STARTING_CASH):
		return false

	renderer = InteractiveRenderer.new()
	renderer.name = "InteractiveIsometricCourseRenderer"
	add_child(renderer)
	if not renderer.configure(grid, [], INVALID_CELL, INVALID_CELL):
		return false

	initialized = true
	return true


func _author_starting_landform() -> void:
	# A gentle undeveloped property. Elevation is authoritative even though the
	# player-facing terrain-shaping tools arrive in POC-32.
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var elevation := (
				0.90 * sin(float(y) * 0.20)
				+ 0.55 * cos(float(x) * 0.24)
				+ 0.25 * sin(float(x + y) * 0.13)
			)
			grid.set_elevation(x, y, elevation)


func set_selected_surface(surface: String) -> bool:
	var normalized := surface.to_upper()
	if not CourseConstructionGrid.SURFACE_TYPES.has(normalized):
		return false
	selected_surface = normalized
	current_status = "Tool: %s" % normalized.capitalize()
	_update_hud()
	return true


func quote_build(cell: Vector2i, surface: String = "") -> Dictionary:
	if economy == null:
		return {"valid": false, "reason": "NOT_INITIALIZED", "cost": 0}
	var target_surface := selected_surface if surface.is_empty() else surface.to_upper()
	return economy.quote_surface_change(cell.x, cell.y, target_surface)


func build_at_cell(cell: Vector2i, surface: String = "") -> Dictionary:
	if economy == null or renderer == null:
		return {"built": false, "reason": "NOT_INITIALIZED"}
	var target_surface := selected_surface if surface.is_empty() else surface.to_upper()
	var result: Dictionary = economy.build_surface(cell.x, cell.y, target_surface)
	if bool(result.get("built", false)):
		selected_cell = cell
		renderer.set_selected_cell(cell)
		_reconcile_hole_markers_after_build(cell)
		renderer.queue_redraw()
		current_status = "%s built at (%d, %d) for $%d" % [
			target_surface.capitalize(),
			cell.x,
			cell.y,
			int(result.get("cost", 0))
		]
	else:
		current_status = "Build rejected: %s" % str(result.get("reason", "UNKNOWN"))
	_update_hud()
	return result


func set_tee_anchor(cell: Vector2i) -> bool:
	if grid == null or not grid.is_in_bounds(cell.x, cell.y):
		return false
	if grid.surface_at(cell.x, cell.y) != "TEE":
		current_status = "Tee marker requires a Tee surface"
		_update_hud()
		return false
	tee_anchor = cell
	renderer.tee_cell = cell
	renderer.queue_redraw()
	current_status = "Tee start set at (%d, %d)" % [cell.x, cell.y]
	_update_hud()
	return true


func set_cup_cell(cell: Vector2i) -> bool:
	if grid == null or not grid.is_in_bounds(cell.x, cell.y):
		return false
	if grid.surface_at(cell.x, cell.y) != "GREEN":
		current_status = "Cup requires a Green surface"
		_update_hud()
		return false
	cup_cell = cell
	renderer.flag_cell = cell
	renderer.queue_redraw()
	current_status = "Cup set at (%d, %d)" % [cell.x, cell.y]
	_update_hud()
	return true


func build_current_hole(par: int = 4, hole_name: String = "Player Hole"):
	if tee_anchor == INVALID_CELL or cup_cell == INVALID_CELL:
		return null
	var builder = ConstructionGridHoleBuilder.new()
	return builder.build_hole(
		grid,
		"player_course",
		1,
		hole_name,
		par,
		tee_anchor,
		cup_cell,
		"player_tee",
		"Player Tee"
	)


func validate_current_hole(par: int = 4) -> Dictionary:
	var hole = build_current_hole(par, "Player Hole")
	if hole == null:
		return {
			"valid": false,
			"reason": "Build a Tee, mark it with T, build a connected Green, and mark the Cup with C."
		}
	return {
		"valid": true,
		"reason": "",
		"yardage": float(hole.nominal_yardage),
		"par": int(hole.par),
		"hole": hole
	}


func snapshot() -> Dictionary:
	if economy == null:
		return {}
	return {
		"schema_version": 1,
		"economy": economy.to_dictionary(),
		"selected_surface": selected_surface,
		"tee_anchor": [tee_anchor.x, tee_anchor.y],
		"cup_cell": [cup_cell.x, cup_cell.y],
		"rotation_quarters": int(renderer.rotation_quarters) if renderer != null else 0
	}


func restore_snapshot(data: Dictionary) -> bool:
	if int(data.get("schema_version", -1)) != 1:
		return false
	var restored_economy = CourseConstructionEconomy.from_dictionary(data.get("economy", {}))
	if restored_economy == null:
		return false
	economy = restored_economy
	grid = economy.grid
	selected_surface = str(data.get("selected_surface", "FAIRWAY")).to_upper()
	if not CourseConstructionGrid.SURFACE_TYPES.has(selected_surface):
		selected_surface = "FAIRWAY"
	tee_anchor = _array_to_cell(data.get("tee_anchor", [-1, -1]))
	cup_cell = _array_to_cell(data.get("cup_cell", [-1, -1]))
	selected_cell = INVALID_CELL
	hovered_cell = INVALID_CELL

	if tee_anchor != INVALID_CELL and grid.surface_at(tee_anchor.x, tee_anchor.y) != "TEE":
		tee_anchor = INVALID_CELL
	if cup_cell != INVALID_CELL and grid.surface_at(cup_cell.x, cup_cell.y) != "GREEN":
		cup_cell = INVALID_CELL

	if renderer == null:
		renderer = InteractiveRenderer.new()
		renderer.name = "InteractiveIsometricCourseRenderer"
		add_child(renderer)
	renderer.configure(grid, [], cup_cell, tee_anchor)
	renderer.set_view_rotation_quarters(int(data.get("rotation_quarters", 0)))
	renderer.clear_interaction()
	current_status = "Construction restored"
	initialized = true
	_update_hud()
	return true


func save_to_path(path: String = DEFAULT_SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(snapshot()))
	file.close()
	current_status = "Saved course construction"
	_update_hud()
	return true


func load_from_path(path: String = DEFAULT_SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		current_status = "No saved construction found"
		_update_hud()
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return false
	return restore_snapshot(parsed)


func rotate_view(step_quarters: int) -> void:
	if renderer == null:
		return
	var focus_cell := selected_cell
	if focus_cell == INVALID_CELL:
		focus_cell = hovered_cell
	if focus_cell == INVALID_CELL:
		focus_cell = Vector2i(int(grid.width / 2), int(grid.height / 2))
	renderer.rotate_view(step_quarters)
	if camera != null:
		camera.position = renderer.cell_center_iso(focus_cell.x, focus_cell.y)
	current_status = "View rotation: %d°" % (int(renderer.rotation_quarters) * 90)
	_update_hud()


func update_hover_from_local_point(local_point: Vector2) -> Vector2i:
	if renderer == null:
		return INVALID_CELL
	hovered_cell = renderer.pick_cell_at_local_point(local_point)
	renderer.set_hovered_cell(hovered_cell)
	_update_hud()
	return hovered_cell


func select_cell(cell: Vector2i) -> bool:
	if grid == null or not grid.is_in_bounds(cell.x, cell.y):
		return false
	selected_cell = cell
	renderer.set_selected_cell(cell)
	_update_hud()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if SURFACE_KEYS.has(event.keycode):
			set_selected_surface(str(SURFACE_KEYS[event.keycode]))
		elif event.keycode == KEY_Q:
			rotate_view(-1)
		elif event.keycode == KEY_E:
			rotate_view(1)
		elif event.keycode == KEY_T and selected_cell != INVALID_CELL:
			set_tee_anchor(selected_cell)
		elif event.keycode == KEY_C and selected_cell != INVALID_CELL:
			set_cup_cell(selected_cell)
		elif event.keycode == KEY_F5:
			save_to_path()
		elif event.keycode == KEY_F9:
			load_from_path()
		elif event.keycode == KEY_H:
			_show_hole_validation()
	elif event is InputEventMouseButton and event.pressed and camera != null:
		if event.button_index == MOUSE_BUTTON_LEFT and hovered_cell != INVALID_CELL:
			select_cell(hovered_cell)
			build_at_cell(hovered_cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT and hovered_cell != INVALID_CELL:
			select_cell(hovered_cell)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.10).clamp(Vector2(0.35, 0.35), Vector2(2.5, 2.5))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.10).clamp(Vector2(0.35, 0.35), Vector2(2.5, 2.5))


func _process(delta: float) -> void:
	if camera == null or renderer == null:
		return
	var local_mouse: Vector2 = renderer.to_local(get_global_mouse_position())
	update_hover_from_local_point(local_mouse)
	var direction := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction.length_squared() > 0.0:
		camera.position += direction * 420.0 * delta / maxf(camera.zoom.x, 0.1)


func _add_background() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	add_child(layer)
	var background := ColorRect.new()
	background.color = Color(0.08, 0.13, 0.08)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(background)


func _add_camera() -> void:
	camera = Camera2D.new()
	camera.name = "ConstructionCamera"
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	add_child(camera)
	camera.enabled = true
	camera.make_current()
	_fit_camera_to_property()


func _fit_camera_to_property() -> void:
	if camera == null or renderer == null:
		return
	var bounds: Rect2 = renderer.visual_bounds().grow(120.0)
	camera.position = bounds.get_center()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var usable_width: float = maxf(viewport_size.x - 300.0, 400.0)
	var usable_height: float = maxf(viewport_size.y - 80.0, 320.0)
	var zoom_factor: float = minf(
		usable_width / maxf(bounds.size.x, 1.0),
		usable_height / maxf(bounds.size.y, 1.0)
	)
	zoom_factor = clampf(zoom_factor, 0.45, 1.25)
	camera.zoom = Vector2(zoom_factor, zoom_factor)


func _add_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ConstructionHUD"
	layer.layer = 20
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.size = Vector2(286.0, 500.0)
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	margin.add_child(stack)

	var title := Label.new()
	title.text = "COURSE CONSTRUCTION"
	title.add_theme_font_size_override("font_size", 20)
	stack.add_child(title)

	funds_label = Label.new()
	stack.add_child(funds_label)
	tool_label = Label.new()
	stack.add_child(tool_label)
	hover_label = Label.new()
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(hover_label)
	marker_label = Label.new()
	stack.add_child(marker_label)
	stack.add_child(HSeparator.new())

	var palette_title := Label.new()
	palette_title.text = "SURFACES  (1–7)"
	stack.add_child(palette_title)

	for surface in CourseConstructionGrid.SURFACE_TYPES:
		var button := Button.new()
		var cost: int = int(CourseConstructionGrid.SURFACE_BUILD_COST.get(surface, 0))
		button.text = "%s   $%d" % [str(surface).capitalize(), cost]
		button.toggle_mode = true
		button.pressed.connect(set_selected_surface.bind(str(surface)))
		stack.add_child(button)
		palette_buttons[str(surface)] = button

	stack.add_child(HSeparator.new())

	var save_row := HBoxContainer.new()
	var save_button := Button.new()
	save_button.text = "Save (F5)"
	save_button.pressed.connect(save_to_path)
	save_row.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "Load (F9)"
	load_button.pressed.connect(load_from_path)
	save_row.add_child(load_button)
	var validate_button := Button.new()
	validate_button.text = "Check Hole (H)"
	validate_button.pressed.connect(_show_hole_validation)
	save_row.add_child(validate_button)
	stack.add_child(save_row)

	var marker_help := Label.new()
	marker_help.text = "Left click: build  •  Right click: select\nT: mark selected Tee  •  C: mark selected Cup\nQ/E: rotate  •  Arrows: pan  •  Wheel: zoom"
	marker_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(marker_help)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(status_label)


func _update_hud() -> void:
	if funds_label != null and economy != null:
		funds_label.text = "Funds: $%d" % int(economy.cash_balance)
	if tool_label != null:
		var tool_cost: int = int(CourseConstructionGrid.SURFACE_BUILD_COST.get(selected_surface, 0))
		tool_label.text = "Tool: %s ($%d)" % [selected_surface.capitalize(), tool_cost]
	if hover_label != null:
		if hovered_cell == INVALID_CELL or grid == null:
			hover_label.text = "Hover: —"
		else:
			var quote: Dictionary = quote_build(hovered_cell)
			hover_label.text = "Hover: (%d, %d) %s → %s  $%d" % [
				hovered_cell.x,
				hovered_cell.y,
				grid.surface_at(hovered_cell.x, hovered_cell.y).capitalize(),
				selected_surface.capitalize(),
				int(quote.get("cost", 0))
			]
	if marker_label != null:
		marker_label.text = "Tee: %s   Cup: %s" % [_cell_label(tee_anchor), _cell_label(cup_cell)]
	if status_label != null:
		status_label.text = current_status
	for surface_value in palette_buttons.keys():
		var surface: String = str(surface_value)
		var button: Button = palette_buttons[surface]
		button.button_pressed = surface == selected_surface


func _show_hole_validation() -> void:
	var validation: Dictionary = validate_current_hole(4)
	if bool(validation.get("valid", false)):
		current_status = "Hole valid: %.0f yd, Par %d" % [
			float(validation.get("yardage", 0.0)),
			int(validation.get("par", 4))
		]
	else:
		current_status = str(validation.get("reason", "Hole is not ready"))
	_update_hud()


func _reconcile_hole_markers_after_build(cell: Vector2i) -> void:
	if cell == tee_anchor and grid.surface_at(cell.x, cell.y) != "TEE":
		tee_anchor = INVALID_CELL
		renderer.tee_cell = INVALID_CELL
	if cell == cup_cell and grid.surface_at(cell.x, cell.y) != "GREEN":
		cup_cell = INVALID_CELL
		renderer.flag_cell = INVALID_CELL


func _array_to_cell(value) -> Vector2i:
	if not value is Array or value.size() < 2:
		return INVALID_CELL
	var cell := Vector2i(int(value[0]), int(value[1]))
	if grid != null and grid.is_in_bounds(cell.x, cell.y):
		return cell
	return INVALID_CELL


func _cell_label(cell: Vector2i) -> String:
	if cell == INVALID_CELL:
		return "—"
	return "(%d,%d)" % [cell.x, cell.y]
