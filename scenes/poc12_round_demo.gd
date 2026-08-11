extends Node3D

# POC-12D: Watchable Three-Hole Mini-Course
# -------------------------------------------
# Reuses the POC-11 visual language while keeping one golfer and one RoundState
# alive across an ordered data-defined course.

const CourseDefinition = preload("res://simulation/course_definition.gd")
const RoundState = preload("res://simulation/round_state.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")
const GolferScript = preload("res://scenes/golfer.gd")

@export var autoplay: bool = true
@export var seed_value: int = 42
@export var shot_duration: float = 0.9
@export var decision_pause: float = 0.55
@export var hole_transition_pause: float = 1.4

var course = null
var round_state = null
var simulation = null
var state = null
var golfer_logic: Node = null
var hole_visuals: Node3D = null
var ball_visual: MeshInstance3D = null
var golfer_visual: MeshInstance3D = null
var status_label: Label = null
var detail_label: Label = null
var score_label: Label = null
var shot_log_label: Label = null
var shot_lines: Array[String] = []


func _ready() -> void:
	_build_environment()
	_build_golfer()
	course = CourseDefinition.load_json("res://data/courses/poc12_proving_course.json")
	if course == null:
		_set_status("COURSE LOAD FAILED", "POC-12 Proving Course could not be loaded.")
		return
	round_state = RoundState.new(course, "default")
	_update_scoreboard()
	if autoplay:
		await get_tree().create_timer(0.7).timeout
		await play_visible_round()


func play_visible_round() -> void:
	while round_state != null and not round_state.complete:
		var hole = round_state.current_hole()
		if hole == null:
			_set_status("ROUND STOPPED", "No current hole was available.")
			return
		await _play_visible_hole(hole)
		if state == null or not state.finished:
			_set_status("ROUND STOPPED", "Hole %d was not completed; score was not advanced." % int(hole.hole_number))
			return
		if not round_state.record_current_hole(state.strokes):
			_set_status("ROUND STOPPED", "Hole %d score could not be recorded." % int(hole.hole_number))
			return
		_update_scoreboard()
		_set_status(
			"HOLE %d COMPLETE — %d" % [int(hole.hole_number), state.strokes],
			"%s | Par %d | Round %s" % [str(hole.hole_name), int(hole.par), _score_to_par_text(round_state.score_to_par())]
		)
		await get_tree().create_timer(hole_transition_pause).timeout

	if round_state != null and round_state.complete:
		_set_status(
			"ROUND COMPLETE — %s" % golfer_logic.golfer_name,
			"%d strokes on par %d | %s" % [round_state.total_strokes(), course.total_par(), _score_to_par_text(round_state.score_to_par())]
		)
		_update_scoreboard()


func _play_visible_hole(hole) -> void:
	_render_hole(hole)
	simulation = DataDefinedAutonomousHole.new(hole, "default")
	state = simulation.create_state(seed_value + int(hole.hole_number) * 101)
	shot_lines.clear()
	shot_log_label.text = ""
	_sync_player_visuals(state.ball_position)
	_set_status(
		"HOLE %d — %s" % [int(hole.hole_number), str(hole.hole_name).to_upper()],
		"%s | Par %d | %.0f yards | Round %s" % [golfer_logic.golfer_name, int(hole.par), float(hole.tee_yardage("default")), _score_to_par_text(round_state.score_to_par())]
	)
	await get_tree().create_timer(0.6).timeout

	while state != null and state.can_continue():
		var before_distance: float = state.remaining_distance()
		var result: Dictionary = simulation.play_step(golfer_logic, state)
		if result.is_empty():
			return
		var option: Dictionary = result.get("selected_option", {})
		var club_name: String = str(result.get("club_name", "Club"))
		var option_name: String = str(option.get("name", "SHOT"))
		_set_status(
			"H%d Stroke %d — %s [%s]" % [int(hole.hole_number), int(result.get("shot_number", 0)), option_name, club_name],
			"%s lie | %.1f yards remaining | Decision %s" % [str(result.get("surface_before", "")), before_distance, str(result.get("decision_quality", ""))]
		)
		await _animate_ball(result.get("start_position", state.ball_position), result.get("landing_position", state.ball_position))
		ball_visual.position = result.get("relief_position", state.ball_position) + Vector3(0.0, 0.9, 0.0)
		golfer_visual.position = state.ball_position + Vector3(-3.0, 2.8, 2.0)
		shot_lines.append("%d. %s [%s] → %s" % [int(result.get("shot_number", 0)), option_name, club_name, str(result.get("surface_after", ""))])
		shot_log_label.text = "\n".join(shot_lines.slice(max(0, shot_lines.size() - 4), shot_lines.size()))
		await get_tree().create_timer(decision_pause).timeout


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.48, 0.68, 0.86)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.75
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	sun.light_energy = 1.15
	add_child(sun)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 400.0, 270.0)
	camera.rotation_degrees = Vector3(-78.0, 0.0, 0.0)
	camera.fov = 58.0
	add_child(camera)

	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(680.0, 220.0)
	ui.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 22)
	box.add_child(status_label)
	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_label)
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 17)
	box.add_child(score_label)
	shot_log_label = Label.new()
	shot_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(shot_log_label)


func _build_golfer() -> void:
	golfer_logic = GolferScript.new()
	golfer_logic.profile = golfer_logic.GolferProfile.CAREFUL_CARL
	add_child(golfer_logic)
	golfer_logic.apply_profile()

	ball_visual = MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.75
	ball_mesh.height = 1.5
	ball_visual.mesh = ball_mesh
	ball_visual.material_override = _material(Color.WHITE)
	ball_visual.name = "GolfBall"
	add_child(ball_visual)

	golfer_visual = MeshInstance3D.new()
	var golfer_mesh := CapsuleMesh.new()
	golfer_mesh.radius = 1.4
	golfer_mesh.height = 5.5
	golfer_visual.mesh = golfer_mesh
	golfer_visual.material_override = _material(Color(0.10, 0.16, 0.25))
	golfer_visual.name = "GolferVisual"
	add_child(golfer_visual)


func _render_hole(hole) -> void:
	if hole_visuals != null:
		hole_visuals.queue_free()
	hole_visuals = Node3D.new()
	hole_visuals.name = "HoleVisuals"
	add_child(hole_visuals)

	var tee_z: float = hole.tee_position("default").z
	var min_z: float = min(-30.0, hole.pin_position.z - 40.0)
	var span: float = max(220.0, tee_z - min_z + 40.0)
	var rough := MeshInstance3D.new()
	var rough_mesh := PlaneMesh.new()
	rough_mesh.size = Vector2(190.0, span)
	rough.mesh = rough_mesh
	rough.position = Vector3(0.0, -0.08, min_z + span * 0.5)
	rough.material_override = _material(Color(0.19, 0.46, 0.18))
	rough.name = "RoughBase"
	hole_visuals.add_child(rough)

	for region in hole.surface_regions:
		var surface_name: String = str(region.get("surface", "ROUGH")).to_upper()
		var surface_color := Color(0.25, 0.62, 0.24)
		var height: float = 0.0
		if surface_name == "TEE":
			surface_color = Color(0.31, 0.70, 0.30)
			height = 0.025
		_add_polygon_mesh(region.get("polygon", PackedVector2Array()), surface_color, height, str(region.get("id", "Surface")))

	_add_polygon_mesh(hole.green_polygon, Color(0.35, 0.76, 0.30), 0.04, "Green")
	for hazard in hole.hazards:
		var hazard_type: String = str(hazard.get("type", "")).to_upper()
		var hazard_color := Color(0.76, 0.66, 0.39)
		var height: float = 0.055
		if hazard_type == "WATER":
			hazard_color = Color(0.12, 0.42, 0.75)
			height = 0.06
		_add_polygon_mesh(hazard.get("polygon", PackedVector2Array()), hazard_color, height, str(hazard.get("id", "Hazard")))
	_build_pin(hole)


func _add_polygon_mesh(polygon: PackedVector2Array, color: Color, height: float, node_name: String) -> void:
	if polygon.size() < 3 or hole_visuals == null:
		return
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty():
		return
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		var point: Vector2 = polygon[int(index)]
		surface_tool.set_normal(Vector3.UP)
		surface_tool.add_vertex(Vector3(point.x, height, point.y))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = surface_tool.commit()
	mesh_instance.material_override = _material(color)
	mesh_instance.name = node_name
	hole_visuals.add_child(mesh_instance)


func _build_pin(hole) -> void:
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 6.0
	pole.mesh = pole_mesh
	pole.position = hole.pin_position + Vector3(0.0, 3.0, 0.0)
	pole.material_override = _material(Color.WHITE)
	hole_visuals.add_child(pole)

	var flag := MeshInstance3D.new()
	var flag_mesh := QuadMesh.new()
	flag_mesh.size = Vector2(3.2, 1.8)
	flag.mesh = flag_mesh
	flag.position = hole.pin_position + Vector3(1.6, 5.2, 0.0)
	flag.material_override = _material(Color(0.85, 0.12, 0.10))
	hole_visuals.add_child(flag)


func _animate_ball(start: Vector3, finish: Vector3) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(_set_ball_progress.bind(start, finish), 0.0, 1.0, shot_duration)
	await tween.finished


func _set_ball_progress(progress: float, start: Vector3, finish: Vector3) -> void:
	var position := start.lerp(finish, progress)
	var flight_distance: float = start.distance_to(finish)
	var arc_height: float = clamp(flight_distance * 0.08, 4.0, 20.0)
	position.y += 0.9 + 4.0 * arc_height * progress * (1.0 - progress)
	ball_visual.position = position


func _sync_player_visuals(position: Vector3) -> void:
	ball_visual.position = position + Vector3(0.0, 0.9, 0.0)
	golfer_visual.position = position + Vector3(-3.0, 2.8, 2.0)


func _update_scoreboard() -> void:
	if score_label == null or round_state == null or course == null:
		return
	var parts: Array[String] = []
	for row in round_state.scorecard():
		if bool(row.get("completed", false)):
			parts.append("H%d %d (%s)" % [int(row.get("hole_number", 0)), int(row.get("strokes", 0)), _score_to_par_text(int(row.get("score_to_par", 0)))])
		else:
			parts.append("H%d —" % int(row.get("hole_number", 0)))
	score_label.text = "Scorecard: %s   |   Total %d / Par %d   |   %s" % ["  ".join(parts), round_state.total_strokes(), round_state.par_played(), _score_to_par_text(round_state.score_to_par())]


func _score_to_par_text(score: int) -> String:
	if score == 0:
		return "E"
	if score > 0:
		return "+%d" % score
	return str(score)


func _set_status(title: String, detail: String) -> void:
	if status_label != null:
		status_label.text = title
	if detail_label != null:
		detail_label.text = detail


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
