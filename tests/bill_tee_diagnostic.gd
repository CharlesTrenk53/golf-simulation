extends SceneTree

const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const AutonomousHole = preload("res://simulation/autonomous_hole.gd")
const CourseContext = preload("res://simulation/course_context.gd")

const START_POSITION := Vector3(0, 0.9, 55)
const HOLE_POSITION := Vector3(0, 0.55, -55)
const PAR := 4

var hazards: Array = [{"name": "Water", "position": Vector3(0, 0.25, 5), "radius": 10.0, "risk": 90.0}]

func _init() -> void:
	var golfer = QuietGolfer.new()
	golfer.profile = 0
	golfer.apply_profile()
	golfer.decision_variability = 0.0
	var simulation = AutonomousHole.new()
	var result = simulation.play_hole(golfer, START_POSITION, HOLE_POSITION, hazards, PAR, 1, _build_course_context())
	if result["history"].is_empty():
		push_error("BILL TEE DIAGNOSTIC FAILED: no shot history")
		golfer.free()
		quit(1)
		return
	var shot: Dictionary = result["history"][0]
	print("============================================================")
	print("POC-08 BILL TEE DECISION DIAGNOSTIC")
	print("Chosen: %s (%s) | objective quality %s | score %.2f | objective best %s %.2f | gap %.2f" % [shot["option"], shot["club_name"], shot["decision_quality"], shot["decision_score"], shot["decision_best_option"], shot["decision_best_score"], shot["decision_gap"]])
	print("------------------------------------------------------------")
	for breakdown in shot.get("decision_option_breakdowns", []):
		_print_breakdown(breakdown)
	print("============================================================")
	golfer.free()
	quit(0)

func _build_course_context():
	var context = CourseContext.new()
	context.add_zone("Fairway", CourseContext.Surface.FAIRWAY, Vector3(0, 0, 5), Vector2(11, 45))
	context.add_zone("Tee", CourseContext.Surface.TEE, START_POSITION, Vector2(8, 5))
	context.add_zone("Green", CourseContext.Surface.GREEN, HOLE_POSITION, Vector2(14, 11))
	context.add_zone("Front Bunker", CourseContext.Surface.BUNKER, Vector3(11, 0, -39), Vector2(6, 7))
	context.add_zone("Water", CourseContext.Surface.WATER, Vector3(0, 0, 5), Vector2(16, 6))
	return context

func _print_breakdown(b: Dictionary) -> void:
	print("OPTION %s | club %s | OBJECTIVE %.2f | raw %.2f" % [b.get("option", ""), b.get("club", ""), b.get("final_score", 0.0), b.get("raw_score", 0.0)])
	print("  future: surface %s | remaining %.2f | expected strokes %.3f | hazard penalty %.3f" % [b.get("expected_surface", ""), b.get("expected_remaining_distance", 0.0), b.get("expected_strokes_remaining", 0.0), b.get("hazard_penalty_strokes", 0.0)])
	print("  objective: capability %.2f | success %.2f | miss cost %.2f | base reward %.2f" % [b.get("capability", 0.0), b.get("success_chance", 0.0), b.get("miss_cost", 0.0), b.get("base_reward", 0.0)])
	print("  subjective context only: willingness %.2f | confidence %.2f | believed success %.2f" % [b.get("subjective_willingness", 0.0), b.get("subjective_confidence", 0.0), b.get("subjective_believed_success", 0.0)])
	print("  carry: expected %.2f | required %.2f | margin %.2f" % [b.get("expected_carry", 0.0), b.get("required_carry", 0.0), b.get("carry_margin", 0.0)])
	print("  objective components: capability %.2f | success %.2f | reward %.2f | miss %.2f | future %.2f | carry %.2f | next %.2f" % [b.get("capability_component", 0.0), b.get("success_component", 0.0), b.get("reward_component", 0.0), b.get("miss_component", 0.0), b.get("future_component", 0.0), b.get("carry_component", 0.0), b.get("next_shot_component", 0.0)])
