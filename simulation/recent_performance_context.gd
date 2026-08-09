extends RefCounted

# Tracks what has been happening TODAY without replacing underlying ability.
# Values are centered at 50 and move gradually as shots are recorded.

var ball_striking: float = 50.0
var driver_accuracy_today: float = 50.0
var iron_accuracy_today: float = 50.0
var putting_today: float = 50.0
var directional_bias: float = 0.0 # negative = left, positive = right
var distance_bias: float = 0.0    # negative = short, positive = long
var recent_mishits: int = 0
var recent_good_shots: int = 0

var club_confidence: Dictionary = {}
var shot_type_confidence: Dictionary = {}
var situational_confidence: Dictionary = {}

func initialize_from_golfer(golfer: Node) -> void:
	ball_striking = 50.0
	driver_accuracy_today = 50.0
	iron_accuracy_today = 50.0
	putting_today = 50.0
	club_confidence.clear()
	shot_type_confidence = {
		0: float(golfer.confidence),
		1: float(golfer.confidence),
		2: float(golfer.confidence),
		3: float(golfer.confidence)
	}
	situational_confidence = {
		"ROUGH": float(golfer.confidence),
		"BUNKER": float(golfer.confidence),
		"WATER_CARRY": float(golfer.confidence),
		"PRESSURE": float(golfer.confidence)
	}

func confidence_for(golfer: Node, club: Dictionary, surface: String, pressure: float = 0.0) -> float:
	var base = float(golfer.confidence)
	var club_value = float(club_confidence.get(club.get("id", ""), base))
	var shot_value = float(shot_type_confidence.get(int(club.get("shot_type", 1)), base))
	var lie_value = float(situational_confidence.get(surface, base))
	var pressure_value = float(situational_confidence.get("PRESSURE", base))
	var blended = club_value * 0.30 + shot_value * 0.30 + lie_value * 0.25 + base * 0.15
	blended -= max(0.0, pressure - 50.0) * (100.0 - pressure_value) / 500.0
	return clamp(blended, 0.0, 100.0)

func performance_modifier_for(club: Dictionary) -> Dictionary:
	var shot_type = int(club.get("shot_type", 1))
	var accuracy_today = iron_accuracy_today
	if shot_type == 0:
		accuracy_today = driver_accuracy_today
	elif shot_type == 3:
		accuracy_today = putting_today
	var carry_factor = clamp(1.0 + (ball_striking - 50.0) * 0.002 + distance_bias * 0.002, 0.90, 1.08)
	var dispersion_factor = clamp(1.0 - (accuracy_today - 50.0) * 0.004 + float(recent_mishits - recent_good_shots) * 0.015, 0.75, 1.35)
	return {"carry_factor": carry_factor, "dispersion_factor": dispersion_factor, "directional_bias": directional_bias}

func record_shot(club: Dictionary, outcome: String, execution_quality: String = "ACCEPTABLE", lateral_error: float = 0.0, distance_error: float = 0.0) -> void:
	var good = execution_quality == "GOOD"
	var poor = execution_quality == "POOR" or outcome == "WATER"
	if good:
		recent_good_shots = min(recent_good_shots + 1, 8)
		recent_mishits = max(recent_mishits - 1, 0)
		ball_striking = min(ball_striking + 1.5, 65.0)
	elif poor:
		recent_mishits = min(recent_mishits + 1, 8)
		recent_good_shots = max(recent_good_shots - 1, 0)
		ball_striking = max(ball_striking - 2.0, 35.0)
	else:
		ball_striking = lerp(ball_striking, 50.0, 0.05)

	var shot_type = int(club.get("shot_type", 1))
	var accuracy_delta = 1.0 if good else (-2.0 if poor else 0.0)
	if shot_type == 0:
		driver_accuracy_today = clamp(driver_accuracy_today + accuracy_delta, 30.0, 70.0)
	elif shot_type == 3:
		putting_today = clamp(putting_today + accuracy_delta, 30.0, 70.0)
	else:
		iron_accuracy_today = clamp(iron_accuracy_today + accuracy_delta, 30.0, 70.0)

	directional_bias = clamp(lerp(directional_bias, lateral_error, 0.20), -10.0, 10.0)
	distance_bias = clamp(lerp(distance_bias, distance_error, 0.20), -10.0, 10.0)

	var club_id = String(club.get("id", ""))
	if not club_id.is_empty():
		var current = float(club_confidence.get(club_id, 50.0))
		club_confidence[club_id] = clamp(current + (2.5 if good else (-4.0 if poor else 0.2)), 15.0, 95.0)
	var current_shot = float(shot_type_confidence.get(shot_type, 50.0))
	shot_type_confidence[shot_type] = clamp(current_shot + (1.5 if good else (-2.5 if poor else 0.1)), 15.0, 95.0)
