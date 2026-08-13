extends Node3D

# POC-21C: Visible Autonomous Golfer
# ----------------------------------
# Lightweight visual projection of the authoritative golfer + ball state.
# This node never decides a shot and never mutates golfer traits. It only mirrors
# who is playing, where the current ball lies, and what the simulation just chose.

var golfer = null
var course_position: Vector3 = Vector3.ZERO
var last_shot_context: Dictionary = {}


func _ready() -> void:
	if get_child_count() == 0:
		_build_marker()


func configure_golfer(value) -> bool:
	if value == null:
		return false
	golfer = value
	set_meta("golfer_name", str(value.get("golfer_name")))
	set_meta("golfer_profile", int(value.get("profile")))
	return true


func place_at_ball(position_value: Vector3) -> void:
	course_position = position_value
	position = Vector3(position_value.x, 1.0, position_value.z)
	set_meta("course_position", position_value)


func observe_shot_result(result: Dictionary) -> bool:
	if not result.has("start_position") or not result.has("landing_position"):
		return false
	last_shot_context = {
		"shot_number": int(result.get("shot_number", 0)),
		"option": str(result.get("option", "")),
		"club_id": str(result.get("club_id", "")),
		"club_name": str(result.get("club_name", "")),
		"start_position": result.get("start_position", Vector3.ZERO),
		"target_position": result.get("target_position", Vector3.ZERO),
		"landing_position": result.get("landing_position", Vector3.ZERO),
		"relief_position": result.get("relief_position", result.get("landing_position", Vector3.ZERO)),
		"outcome": str(result.get("outcome", "")),
		"intent_signature": str(result.get("intent_signature", ""))
	}
	set_meta("last_shot_context", last_shot_context.duplicate(true))
	return true


func move_to_resolved_ball(result: Dictionary) -> bool:
	if not observe_shot_result(result):
		return false
	var resolved: Vector3 = result.get("landing_position", Vector3.ZERO)
	if str(result.get("outcome", "")).to_upper() == "WATER" and result.has("relief_position"):
		resolved = result.get("relief_position", resolved)
	place_at_ball(resolved)
	return true


func _build_marker() -> void:
	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.45
	body_mesh.height = 1.8
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.92, 0.92, 0.96)
	body_material.roughness = 1.0
	body_mesh.material = body_material
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.9, 0.0)
	add_child(body)

	var facing := MeshInstance3D.new()
	facing.name = "FacingMarker"
	var facing_mesh := BoxMesh.new()
	facing_mesh.size = Vector3(0.12, 0.12, 0.65)
	var facing_material := StandardMaterial3D.new()
	facing_material.albedo_color = Color(0.15, 0.25, 0.85)
	facing_mesh.material = facing_material
	facing.mesh = facing_mesh
	facing.position = Vector3(0.0, 1.25, -0.50)
	add_child(facing)
