extends Node3D

const GolferScript = preload("res://scenes/golfer.gd")
const GolfBag = preload("res://simulation/golf_bag.gd")
const ShotIntent = preload("res://simulation/shot_intent.gd")
const ShotFlightModel = preload("res://simulation/shot_flight_model.gd")
const ShotmakingProficiencyModel = preload("res://simulation/shotmaking_proficiency_model.gd")
const ShotIntentExecutionBridge = preload("res://simulation/shot_intent_execution_bridge.gd")

@export var use_reckless_rick: bool = false
@export var autoplay: bool = true
@export var shot_duration: float = 1.35
@export var pause_between_shots: float = 0.8

var golfer: Node
var ball: MeshInstance3D
var title_label: Label
var detail_label: Label
var bag = GolfBag.new()
var flight_model = ShotFlightModel.new()
var proficiency_model = ShotmakingProficiencyModel.new()
var execution_bridge = ShotIntentExecutionBridge.new()
var active_start := Vector3.ZERO
var active_forward: float = 0.0
var active_lateral: float = 0.0
var active_apex: float = 1.0


func _ready() -> void:
	bag.use_literal_yardages(true)
	_build_world()
	_build_golfer()
	_build_ui()
	if autoplay:
		await get_tree().create_timer(0.6).timeout
		await run_diagnostic()


func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.72, 0.88)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.85
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -20.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(150.0, 270.0)
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, 0.0, -95.0)
	ground.material_override = _material(Color(0.20, 0.52, 0.20))
	add_child(ground)

	for yardage in [50, 100, 150, 200, 250]:
		var line := MeshInstance3D.new()
		var line_mesh := BoxMesh.new()
		line_mesh.size = Vector3(120.0, 0.08, 0.45)
		line.mesh = line_mesh
		line.position = Vector3(0.0, 0.08, -float(yardage))
		line.material_override = _material(Color(0.88, 0.92, 0.88))
		add_child(line)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 92.0, 78.0)
	camera.look_at(Vector3(0.0, 10.0, -110.0), Vector3.UP)
	camera.fov = 54.0
	add_child(camera)

	ball = MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 1.2
	ball_mesh.height = 2.4
	ball.mesh = ball_mesh
	ball.material_override = _material(Color.WHITE)
	ball.position = Vector3(0.0, 1.2, 0.0)
	add_child(ball)


func _build_golfer() -> void:
	golfer = GolferScript.new()
	golfer.profile = golfer.GolferProfile.RECKLESS_RICK if use_reckless_rick else golfer.GolferProfile.CAREFUL_CARL
	add_child(golfer)
	golfer.apply_profile()


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(760.0, 150.0)
	canvas.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 24)
	box.add_child(title_label)
	detail_label = Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 16)
	box.add_child(detail_label)
	title_label.text = "POC-14 SHOTMAKING RANGE"
	detail_label.text = "%s — comparing composable intent, predicted flight, proficiency, and actual execution" % golfer.golfer_name


func run_diagnostic() -> void:
	var club: Dictionary = bag.get_club("DRIVER")
	var baseline_carry: float = float(club.get("carry", club.get("carry_yards", 220.0)))
	if baseline_carry <= 1.0:
		baseline_carry = 220.0
	var baseline_dispersion: float = float(club.get("dispersion", 9.0))
	if baseline_dispersion <= 0.0:
		baseline_dispersion = 9.0

	var intents: Array[Dictionary] = [
		ShotIntent.make(ShotIntent.Trajectory.NORMAL, ShotIntent.Shape.STRAIGHT, ShotIntent.SwingLength.FULL, ShotIntent.Technique.STOCK),
		ShotIntent.make(ShotIntent.Trajectory.NORMAL, ShotIntent.Shape.DRAW, ShotIntent.SwingLength.FULL, ShotIntent.Technique.STOCK),
		ShotIntent.make(ShotIntent.Trajectory.NORMAL, ShotIntent.Shape.FADE, ShotIntent.SwingLength.FULL, ShotIntent.Technique.STOCK),
		ShotIntent.make(ShotIntent.Trajectory.HIGH, ShotIntent.Shape.STRAIGHT, ShotIntent.SwingLength.FULL, ShotIntent.Technique.STOCK),
		ShotIntent.make(ShotIntent.Trajectory.LOW, ShotIntent.Shape.STRAIGHT, ShotIntent.SwingLength.FULL, ShotIntent.Technique.STINGER)
	]

	for index in range(intents.size()):
		var intent: Dictionary = intents[index]
		var predicted: Dictionary = flight_model.predict(club, intent, baseline_carry, baseline_dispersion)
		var proficiency: Dictionary = proficiency_model.assess(golfer, club, intent, predicted)
		var start := Vector3(0.0, 0.0, 0.0)
		var target := Vector3(0.0, 0.0, -baseline_carry)
		var actual: Dictionary = execution_bridge.execute(start, target, predicted, proficiency, 14000 + index * 97)
		_show_shot(intent, predicted, proficiency, actual, index + 1, intents.size())
		await _animate_execution(actual, predicted)
		await get_tree().create_timer(pause_between_shots).timeout

	title_label.text = "POC-14 SHOTMAKING RANGE — COMPLETE"
	detail_label.text = "%s completed stock, draw, fade, high, and stinger executions. Rerun with use_reckless_rick=true to compare golfer-specific reliability." % golfer.golfer_name


func _show_shot(intent: Dictionary, predicted: Dictionary, proficiency: Dictionary, actual: Dictionary, shot_number: int, shot_count: int) -> void:
	var signature := str(intent.get("signature", "UNKNOWN"))
	var predicted_carry := float(predicted.get("carry_yards", 0.0))
	var predicted_curve := float(predicted.get("curve_yards", 0.0))
	var reliability := 100.0 * float(proficiency.get("execution_reliability", 0.0))
	var actual_total := float(actual.get("actual_total_yards", 0.0))
	var actual_lateral := float(actual.get("target_line_lateral_yards", 0.0))
	title_label.text = "SHOT %d/%d — %s" % [shot_number, shot_count, signature]
	detail_label.text = "%s | predicted carry %.1f yd | predicted curve %+0.1f yd | reliability %.0f%% | actual total %.1f yd | actual lateral %+0.1f yd" % [golfer.golfer_name, predicted_carry, predicted_curve, reliability, actual_total, actual_lateral]


func _animate_execution(actual: Dictionary, predicted: Dictionary) -> void:
	active_start = Vector3(0.0, 1.2, 0.0)
	active_forward = float(actual.get("forward_yards", actual.get("actual_total_yards", 0.0)))
	active_lateral = float(actual.get("target_line_lateral_yards", 0.0))
	active_apex = max(0.35, float(actual.get("actual_apex_factor", predicted.get("apex_factor", 1.0))))
	ball.position = active_start
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	tween.tween_method(_set_shot_progress, 0.0, 1.0, shot_duration)
	await tween.finished
	_add_landing_marker(ball.position)


func _set_shot_progress(progress: float) -> void:
	var curve_progress := pow(progress, 1.7)
	var height := sin(progress * PI) * 22.0 * active_apex
	ball.position = active_start + Vector3(active_lateral * curve_progress, height, -active_forward * progress)


func _add_landing_marker(position: Vector3) -> void:
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.8
	mesh.bottom_radius = 1.8
	mesh.height = 0.16
	marker.mesh = mesh
	marker.position = Vector3(position.x, 0.12, position.z)
	marker.material_override = _material(Color(0.95, 0.78, 0.16))
	add_child(marker)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material
