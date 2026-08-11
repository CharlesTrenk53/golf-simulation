extends Node3D

const HoleDefinition = preload("res://simulation/hole_definition.gd")
const DataDefinedAutonomousHole = preload("res://simulation/data_defined_autonomous_hole.gd")
const GolferScript = preload("res://scenes/golfer.gd")

@export var autoplay: bool = true
@export var seed_value: int = 42
@export var shot_duration: float = 1.1
@export var decision_pause: float = 0.8

var hole_definition = null
var simulation = null
var state = null
var golfer_logic: Node = null
var ball_visual: MeshInstance3D = null
var golfer_visual: MeshInstance3D = null
var status_label: Label = null
var detail_label: Label = null
var shot_log_label: Label = null
var shot_lines: Array[String] = []


func _ready() -> void:
	_build_environment()
	hole_definition = HoleDefinition.load_json("res://data/courses/poc11_test_hole.json")
	if hole_definition == null:
		_set_status("COURSE LOAD FAILED", "Decision Point could not be loaded.")
		return
	_render_hole()
	_build_golfer()
	simulation = DataDefinedAutonomousHole.new(hole_definition, "default")
	state = simulation.create_state(seed_value)
	_sync_player_visuals(state.ball_position)
	_set_status("DECISION POINT — HOLE 1", "%s | Par %d | %.0f yards" % [golfer_logic.golfer_name, hole_definition.par, hole_definition.tee_yardage("default")])
	if autoplay:
		await get_tree().create_timer(0.8).timeout
		await play_visible_hole()


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.48, 0.68, 0.86)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 1.0, 1.0)
	environment.ambient_light_energy = 0.75
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	sun.light_energy = 1.15
	add_child(sun)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 360.0, 245.0)
	camera.rotation_degrees = Vector3(-78.0, 0.0, 0.0)
	camera.fov = 55.0
	add_child(camera)

	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(620.0, 170.0)
	ui.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 22)
	box.add_child(status_label)
	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail_label)
	shot_log_label = Label.new()
	shot_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(shot_log_label)


func _render_hole() -> void:
	var rough := MeshInstance3D.new()
	var rough_mesh := PlaneMesh.new()
	rough_mesh.size = Vector2(180.0, 500.0)
	rough.mesh = rough_mesh
	rough.position = Vector3(0.0, -0.08, 205.0)
	rough.material_override = _material(Color(0.19, 0.46, 0.18))
	rough.name = "RoughBase"
	add_child(rough)

	for region in hole_definition.surface_regions:
		var surface_name := str(region.get("surface", "ROUGH")).to_upper()
		var surface_color := Color(0.25, 0.62, 0.24)
		var height := 0.0
		if surface_name == "TEE":
			surface_color = Color(0.31, 0.70, 0.30)
			height = 0.025
		_add_polygon_mesh(region.get("polygon", PackedVector2Array()), surface_color, height, str(region.get("id", "Surface")))

	_add_polygon_mesh(hole_definition.green_polygon, Color(0.35, 0.76, 0.30), 0.04, "Green")

	for hazard in hole_definition.hazards:
		var hazard_type := str(hazard.get("type", "")).to_upper()
		var hazard_color := Color(0.76, 0.66, 0.39)
		var height := 0.055
		if hazard_type == "WATER":
			hazard_color = Color(0.12, 0.42, 0.75)
			height = 0.06
		_add_polygon_mesh(hazard.get("polygon", PackedVector2Array()), hazard_color, height, str(hazard.get("id", "Hazard")))

	_build_pin()


func _add_polygon_mesh(polygon: PackedVector2Array, color: Color, height: float, node_name: String) -> void:
	if polygon.size() < 3:
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
	add_child(mesh_instance)


func _build_pin() -> void:
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 6.0
	pole.mesh = pole_mesh
	pole.position = hole_definition.pin_position + Vector3(0.0, 3.0, 0.0)
	pole.material_override = _material(Color.WHITE)
	pole.name = "Pin"
	add_child(pole)

	var flag := MeshInstance3D.new()
	var flag_mesh := QuadMesh.new()
	flag_mesh.size = Vector2(3.2, 1.8)
	flag.mesh = flag_mesh
	flag.position = hole_definition.pin_position + Vector3(1.6, 5.2, 0.0)
	flag.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	flag.material_override = _material(Color(0.85, 0.12, 0.10))
	add_child(flag)


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


func play_visible_hole() -> void:
	while state != null and state.can_continue():
		var before_distance: float = state.remaining_distance()
		var result: Dictionary = simulation.play_step(golfer_logic, state)
		if result.is_empty():
			_set_status("PLAY STOPPED", "No valid shot option was available.")
			return
		var option: Dictionary = result.get("selected_option", {})
		var club_name := str(result.get("club_name", "Club"))
		var option_name := str(option.get("name", "SHOT"))
		_set_status(
			"Stroke %d — %s [%s]" % [int(result.get("shot_number", 0)), option_name, club_name],
			"%s lie | %.1f yards remaining | Decision %s" % [str(result.get("surface_before", "")), before_distance, str(result.get("decision_quality", ""))]
		)
		await _animate_ball(result.get("start_position", state.ball_position), result.get("landing_position", state.ball_position))
		ball_visual.position = result.get("relief_position", state.ball_position) + Vector3(0.0, 0.9, 0.0)
		golfer_visual.position = state.ball_position + Vector3(-3.0, 2.8, 2.0)
		shot_lines.append("%d. %s [%s] → %s" % [int(result.get("shot_number", 0)), option_name, club_name, str(result.get("surface_after", ""))])
		shot_log_label.text = "\n".join(shot_lines.slice(max(0, shot_lines.size() - 4), shot_lines.size()))
		await get_tree().create_timer(decision_pause).timeout

	if state != null and state.finished:
		_set_status("HOLED OUT — %s" % golfer_logic.golfer_name, "%d strokes on the par-%d Decision Point." % [state.strokes, state.par])
	else:
		_set_status("ROUND STOPPED", "Stroke limit reached before holing out.")


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
