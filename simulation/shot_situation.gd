extends RefCounted

# POC-08 WORLD layer. This object contains facts about the shot that exist
# independently of the golfer: geometry, lie, hazards, weather and target.

var ball_position: Vector3
var target_position: Vector3
var surface: String
var lie_quality: float
var distance_to_target: float
var elevation_change: float = 0.0
var wind_speed: float = 0.0
var wind_direction: Vector3 = Vector3.ZERO
var temperature_f: float = 70.0
var altitude_feet: float = 0.0
var ground_firmness: float = 0.5
var hazards: Array = []
var safe_landing_position: Vector3
var safe_landing_distance: float
var recovery_difficulty: float = 0.0

func _init(start: Vector3, target: Vector3, current_surface: String, current_lie_quality: float, current_hazards: Array = []) -> void:
	ball_position = start
	target_position = target
	surface = current_surface
	lie_quality = current_lie_quality
	distance_to_target = _horizontal_distance(start, target)
	elevation_change = target.y - start.y
	hazards = current_hazards.duplicate(true)
	safe_landing_position = target
	safe_landing_distance = distance_to_target
	recovery_difficulty = _estimate_recovery_difficulty()

func set_weather(p_wind_speed: float, p_wind_direction: Vector3, p_temperature_f: float = 70.0, p_altitude_feet: float = 0.0) -> void:
	wind_speed = max(p_wind_speed, 0.0)
	wind_direction = p_wind_direction.normalized() if p_wind_direction.length() > 0.001 else Vector3.ZERO
	temperature_f = p_temperature_f
	altitude_feet = p_altitude_feet

func set_safe_landing(position: Vector3) -> void:
	safe_landing_position = position
	safe_landing_distance = _horizontal_distance(ball_position, position)

func effective_playing_distance() -> float:
	var distance = distance_to_target
	# Positive elevation means the target is above the golfer.
	distance += elevation_change * 0.35
	var shot_direction = target_position - ball_position
	shot_direction.y = 0.0
	if shot_direction.length() > 0.001 and wind_direction.length() > 0.001:
		shot_direction = shot_direction.normalized()
		# Positive dot = following wind, negative = headwind.
		var wind_alignment = shot_direction.dot(wind_direction)
		distance -= wind_speed * wind_alignment * 0.20
	# Small first-pass temperature/altitude corrections. These are intentionally
	# modest until real-world calibration is introduced.
	distance += max(0.0, 70.0 - temperature_f) * 0.025
	distance -= altitude_feet / 1000.0 * 0.30
	return max(distance, 0.0)

func hazard_on_line_to(position: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var closest = INF
	for hazard in hazards:
		if not hazard.has("position"):
			continue
		var radius: float = float(hazard.get("radius", 6.0))
		var hazard_position: Vector3 = hazard["position"]
		if _distance_to_segment(hazard_position, ball_position, position) <= radius:
			var distance = _horizontal_distance(ball_position, hazard_position)
			if distance < closest:
				closest = distance
				best = hazard
	return best

func _estimate_recovery_difficulty() -> float:
	match surface:
		"GREEN", "TEE", "FAIRWAY": return 5.0
		"ROUGH": return 30.0
		"BUNKER": return 55.0
		"WATER": return 100.0
	return 40.0

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	var delta = b - a
	delta.y = 0.0
	return delta.length()

func _distance_to_segment(point: Vector3, start: Vector3, finish: Vector3) -> float:
	var segment = finish - start
	var length_squared = segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(start)
	var t = clamp((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * t)
