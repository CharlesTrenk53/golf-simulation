extends Node3D

# POC-22 visual construction proof
# --------------------------------
# Builds a paid tile-based 410-yard par four, renders the authoritative
# construction grid, and lets the existing autonomous golfer play the resulting
# HoleDefinition one visible shot at a time.

const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")
const CourseConstructionEconomy = preload("res://simulation/course_construction_economy.gd")
const ConstructionGridHoleBuilder = preload("res://simulation/construction_grid_hole_builder.gd")
const ConstructionGridRenderer = preload("res://scenes/construction_grid_renderer.gd")
const PlayableHoleRuntime = preload("res://scenes/playable_hole_runtime.gd")
const GolferScript = preload("res://scenes/golfer.gd")

@export var shot_pause_seconds: float = 0.7

var grid = null
var economy = null
var hole = null
var golfer = null
var runtime = null
var grid_renderer = null
var _running: bool = false

@onready var camera: Camera3D = $Camera3D
@onready var status_label: Label = $UI/Margin/Status


func _ready() -> void:
	grid = CourseConstructionGrid.new()
	if not grid.configure(15, 48, 10.0, Vector2(-75.0, -15.0)):
		status_label.text = "Failed to configure construction property"
		return

	economy = CourseConstructionEconomy.new()
	if not economy.configure(grid, 20000):
		status_label.text = "Failed to configure construction economy"
		return
	if not _build_player_hole():
		status_label.text = "Failed to construct starter hole"
		return

	hole = ConstructionGridHoleBuilder.new().build_hole(
		grid,
		"poc22_player_built_course",
		1,
		"First Investment",
		4,
		Vector2i(7, 44),
		Vector2i(7, 3),
		"starter",
		"Starter Tee"
	)
	if hole == null:
		status_label.text = "Failed to convert construction grid into playable hole"
		return

	grid_renderer = ConstructionGridRenderer.new()
	grid_renderer.name = "ConstructionGridRenderer"
	add_child(grid_renderer)
	if not grid_renderer.render_grid(grid):
		status_label.text = "Failed to render construction grid"
		return

	golfer = GolferScript.new()
	golfer.profile = GolferScript.GolferProfile.WILD_BILL
	golfer.apply_profile()
	add_child(golfer)

	runtime = PlayableHoleRuntime.new()
	runtime.name = "PlayableHoleRuntime"
	add_child(runtime)
	if not runtime.configure(hole, golfer, "starter", 22022):
		status_label.text = "Failed to configure autonomous golfer runtime"
		return

	# POC-22's grid renderer is the visible course. The legacy polygon renderer
	# remains part of PlayableHoleRuntime for backward compatibility but is hidden
	# here so there is only one visual terrain projection.
	if runtime.renderer != null:
		runtime.renderer.visible = false

	_frame_hole()
	_update_status("Ready — player-built course")
	_running = true
	_play_visible()


func _play_visible() -> void:
	await get_tree().create_timer(1.0).timeout
	while _running and runtime != null and runtime.state != null and runtime.state.can_continue():
		var shot: Dictionary = runtime.play_next_shot(true)
		if shot.is_empty():
			_running = false
			_update_status("Stopped before hole completion")
			return
		_update_status("Shot %d — %s" % [int(shot.get("shot_number", 0)), str(shot.get("club_name", shot.get("option", "Shot")))])
		_frame_shot(shot)
		await runtime.ball_visual.flight_finished
		runtime.finish_visual_resolution(shot)
		await get_tree().create_timer(shot_pause_seconds).timeout

	var summary: Dictionary = runtime.runtime_snapshot()
	_update_status("Hole complete — %d on Par %d (%+d)" % [
		int(summary.get("strokes", 0)),
		int(summary.get("par", 0)),
		int(summary.get("score_to_par", 0))
	])


func _build_player_hole() -> bool:
	for y in range(44, 46):
		for x in range(6, 8):
			if not _purchase(x, y, "TEE"):
				return false

	for y in range(8, 44):
		var center_x: int = 7
		if y >= 22 and y < 34:
			center_x = 8
		for x in range(center_x - 1, center_x + 2):
			if not _purchase(x, y, "FAIRWAY"):
				return false

	for y in range(2, 5):
		for x in range(6, 9):
			if not _purchase(x, y, "GREEN"):
				return false

	for cell in [Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 6)]:
		if not _purchase(cell.x, cell.y, "BUNKER"):
			return false
	for cell in [Vector2i(10, 25), Vector2i(11, 25), Vector2i(10, 26), Vector2i(11, 26), Vector2i(10, 27), Vector2i(11, 27)]:
		if not _purchase(cell.x, cell.y, "WATER"):
			return false
	return true


func _purchase(x: int, y: int, surface: String) -> bool:
	var result: Dictionary = economy.build_surface(x, y, surface)
	return bool(result.get("built", false))


func _frame_hole() -> void:
	if hole == null:
		return
	var tee: Vector3 = hole.tee_position("starter")
	var pin: Vector3 = hole.pin_position
	var center: Vector3 = (tee + pin) * 0.5
	var length: float = max(160.0, tee.distance_to(pin))
	camera.position = Vector3(center.x + length * 0.50, max(125.0, length * 0.38), center.z + length * 0.10)
	camera.look_at(center, Vector3.UP)


func _frame_shot(shot: Dictionary) -> void:
	var start: Vector3 = shot.get("start_position", Vector3.ZERO)
	var landing: Vector3 = shot.get("relief_position", shot.get("landing_position", Vector3.ZERO))
	var center: Vector3 = (start + landing) * 0.5
	var distance: float = max(45.0, start.distance_to(landing))
	camera.position = Vector3(center.x + distance * 0.48, max(42.0, distance * 0.30), center.z + distance * 0.15)
	camera.look_at(center, Vector3.UP)


func _update_status(message: String) -> void:
	var strokes: int = runtime.state.strokes if runtime != null and runtime.state != null else 0
	status_label.text = "%s\n%s | 410 yd Par 4 | Build cost $%d | Cash $%d | Strokes %d" % [
		message,
		str(golfer.golfer_name) if golfer != null else "Wild Bill",
		economy.lifetime_construction_spend if economy != null else 0,
		economy.cash_balance if economy != null else 0,
		strokes
	]
