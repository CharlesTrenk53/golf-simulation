extends SceneTree

const PuttingPipeline = preload("res://simulation/putting_pipeline.gd")

const DISTANCES_FEET: Array[float] = [3.0, 5.0, 8.0, 10.0, 15.0, 20.0, 30.0, 40.0]
const ABILITY_LEVELS: Array[float] = [30.0, 50.0, 70.0, 85.0, 95.0]
const TRIALS_PER_CELL: int = 1200
const DIFFICULT_COMEBACK_FEET: float = 5.0

class StressGolfer:
	extends Node
	var putting: float = 70.0
	var coordination: float = 75.0
	var confidence: float = 70.0
	var risk_tolerance: float = 50.0

	func get_shot_ability(shot_type: int) -> float:
		if shot_type == 3:
			return putting
		return 50.0

var failures: int = 0
var pipeline = PuttingPipeline.new()


func _init() -> void:
	print("POC-15F: putting behavioral stress test")
	print("Trials per ability-distance cell: %d" % TRIALS_PER_CELL)
	print("Conditions: level green, speed 10.0; non-putting traits held constant")
	print("")

	var ability_rows: Array = []
	for ability in ABILITY_LEVELS:
		var golfer := StressGolfer.new()
		golfer.putting = ability
		get_root().add_child(golfer)
		for distance in DISTANCES_FEET:
			ability_rows.append(_simulate_cell(golfer, ability, distance, 0.0, 0.0, 10.0, int(ability * 10000.0 + distance * 100.0)))
		golfer.queue_free()

	_print_ability_table(ability_rows)
	_validate_directional_behavior(ability_rows)
	var personality_rows: Array = _print_personality_comparison()
	_validate_personality_behavior(personality_rows)

	if failures == 0:
		print("")
		print("POC-15F PUTTING BEHAVIOR STRESS TEST COMPLETED")
		quit(0)
	else:
		push_error("POC-15F PUTTING BEHAVIOR STRESS TEST FAILED: %d" % failures)
		quit(1)


func _simulate_cell(
	golfer: Node,
	ability: float,
	distance: float,
	cross_slope: float,
	along_slope: float,
	green_speed: float,
	seed_base: int
) -> Dictionary:
	var makes: int = 0
	var miss_leave_total: float = 0.0
	var miss_count: int = 0
	var difficult_comebacks: int = 0
	var short_misses: int = 0
	var long_misses: int = 0
	var attack_count: int = 0
	var neutral_count: int = 0
	var lag_count: int = 0
	var planned_past_feet: float = 0.0
	var assertive_tendency: float = 0.0

	for i in range(TRIALS_PER_CELL):
		var result: Dictionary = pipeline.resolve(
			golfer,
			distance,
			seed_base + i,
			cross_slope,
			along_slope,
			green_speed
		)
		var strategy_data: Dictionary = result["strategy"]
		if i == 0:
			planned_past_feet = float(strategy_data.get("pace_feet_past_hole", 0.0))
			assertive_tendency = float(strategy_data.get("strategy_assertive_tendency", 0.5))
		var strategy: String = str(strategy_data.get("strategy", "NEUTRAL"))
		match strategy:
			"ATTACK": attack_count += 1
			"LAG": lag_count += 1
			_: neutral_count += 1

		if bool(result["holed"]):
			makes += 1
			continue

		miss_count += 1
		var leave: float = float(result["finish_distance_from_hole_feet"])
		miss_leave_total += leave
		if leave > DIFFICULT_COMEBACK_FEET:
			difficult_comebacks += 1
		var rolled: float = float(result["rolled_distance_feet"])
		if rolled < distance:
			short_misses += 1
		else:
			long_misses += 1

	var trials: float = float(TRIALS_PER_CELL)
	return {
		"ability": ability,
		"distance_feet": distance,
		"make_pct": float(makes) / trials * 100.0,
		"avg_miss_leave_feet": miss_leave_total / maxf(float(miss_count), 1.0),
		"difficult_comeback_pct": float(difficult_comebacks) / trials * 100.0,
		"short_miss_pct": float(short_misses) / maxf(float(miss_count), 1.0) * 100.0,
		"long_miss_pct": float(long_misses) / maxf(float(miss_count), 1.0) * 100.0,
		"attack_pct": float(attack_count) / trials * 100.0,
		"neutral_pct": float(neutral_count) / trials * 100.0,
		"lag_pct": float(lag_count) / trials * 100.0,
		"planned_past_feet": planned_past_feet,
		"assertive_tendency": assertive_tendency
	}


func _print_ability_table(rows: Array) -> void:
	print("=== ABILITY x DISTANCE SUMMARY ===")
	print("ability,distance_ft,make_pct,avg_miss_leave_ft,difficult_comeback_pct,short_miss_pct,long_miss_pct,attack_pct,neutral_pct,lag_pct,planned_past_ft,assertive_tendency")
	for row in rows:
		print("%.0f,%.0f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.3f" % [
			float(row["ability"]),
			float(row["distance_feet"]),
			float(row["make_pct"]),
			float(row["avg_miss_leave_feet"]),
			float(row["difficult_comeback_pct"]),
			float(row["short_miss_pct"]),
			float(row["long_miss_pct"]),
			float(row["attack_pct"]),
			float(row["neutral_pct"]),
			float(row["lag_pct"]),
			float(row["planned_past_feet"]),
			float(row["assertive_tendency"])
		])
	print("")


func _validate_directional_behavior(rows: Array) -> void:
	for distance in DISTANCES_FEET:
		var low: Dictionary = _find_row(rows, 30.0, distance)
		var high: Dictionary = _find_row(rows, 95.0, distance)
		_expect(float(high["make_pct"]) >= float(low["make_pct"]), "ability 95 make rate is at least ability 30 at %.0f ft" % distance)
		_expect(float(high["difficult_comeback_pct"]) <= float(low["difficult_comeback_pct"]) + 0.50, "ability 95 creates no more difficult comebacks than ability 30 at %.0f ft" % distance)

	var skill_70_3: Dictionary = _find_row(rows, 70.0, 3.0)
	var skill_70_10: Dictionary = _find_row(rows, 70.0, 10.0)
	var skill_70_20: Dictionary = _find_row(rows, 70.0, 20.0)
	var skill_70_40: Dictionary = _find_row(rows, 70.0, 40.0)
	_expect(float(skill_70_3["make_pct"]) > float(skill_70_10["make_pct"]), "make rate falls from 3 ft to 10 ft")
	_expect(float(skill_70_10["make_pct"]) > float(skill_70_40["make_pct"]), "make rate falls from 10 ft to 40 ft")
	_expect(float(skill_70_40["lag_pct"]) > float(skill_70_10["lag_pct"]), "long putts produce more lag strategy than 10-foot putts")
	_expect(float(skill_70_20["short_miss_pct"]) >= 10.0, "20-foot misses include a meaningful short-miss share")
	_expect(float(skill_70_40["short_miss_pct"]) >= 15.0, "40-foot misses include a meaningful short-miss share")
	_expect(float(skill_70_20["long_miss_pct"]) <= 90.0, "20-foot misses are not overwhelmingly long")
	_expect(float(skill_70_40["long_miss_pct"]) <= 85.0, "40-foot misses are not overwhelmingly long")


func _print_personality_comparison() -> Array:
	print("=== PERSONALITY / STRATEGY COMPARISON ===")
	print("profile,putting,risk_tolerance,confidence,distance_ft,green_speed,along_slope,make_pct,avg_miss_leave_ft,difficult_comeback_pct,attack_pct,neutral_pct,lag_pct,planned_past_ft,assertive_tendency")
	var rows: Array = []
	var profiles: Array = [
		{"name": "CAUTIOUS", "risk": 15.0, "confidence": 70.0},
		{"name": "NEUTRAL", "risk": 50.0, "confidence": 70.0},
		{"name": "BOLD", "risk": 85.0, "confidence": 70.0}
	]
	var scenarios: Array = [
		{"distance": 10.0, "speed": 10.0, "slope": 0.0},
		{"distance": 20.0, "speed": 10.0, "slope": 0.0},
		{"distance": 40.0, "speed": 10.0, "slope": 0.0},
		{"distance": 20.0, "speed": 13.0, "slope": -3.0}
	]

	for profile in profiles:
		var golfer := StressGolfer.new()
		golfer.putting = 70.0
		golfer.risk_tolerance = float(profile["risk"])
		golfer.confidence = float(profile["confidence"])
		get_root().add_child(golfer)
		for scenario in scenarios:
			var distance: float = float(scenario["distance"])
			var speed: float = float(scenario["speed"])
			var slope: float = float(scenario["slope"])
			var row: Dictionary = _simulate_cell(golfer, 70.0, distance, 0.0, slope, speed, int(float(profile["risk"]) * 10000.0 + distance * 100.0 + speed * 10.0))
			row["profile"] = str(profile["name"])
			row["risk_tolerance"] = float(profile["risk"])
			row["confidence"] = float(profile["confidence"])
			row["green_speed"] = speed
			row["along_slope"] = slope
			rows.append(row)
			print("%s,70,%.0f,%.0f,%.0f,%.1f,%.1f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.3f" % [
				str(profile["name"]),
				float(profile["risk"]),
				float(profile["confidence"]),
				distance,
				speed,
				slope,
				float(row["make_pct"]),
				float(row["avg_miss_leave_feet"]),
				float(row["difficult_comeback_pct"]),
				float(row["attack_pct"]),
				float(row["neutral_pct"]),
				float(row["lag_pct"]),
				float(row["planned_past_feet"]),
				float(row["assertive_tendency"])
			])
		golfer.queue_free()
	print("")
	return rows


func _validate_personality_behavior(rows: Array) -> void:
	var cautious_20: Dictionary = _find_profile_row(rows, "CAUTIOUS", 20.0, 10.0, 0.0)
	var neutral_20: Dictionary = _find_profile_row(rows, "NEUTRAL", 20.0, 10.0, 0.0)
	var bold_20: Dictionary = _find_profile_row(rows, "BOLD", 20.0, 10.0, 0.0)
	var cautious_danger: Dictionary = _find_profile_row(rows, "CAUTIOUS", 20.0, 13.0, -3.0)
	_expect(float(cautious_20["planned_past_feet"]) < float(neutral_20["planned_past_feet"]), "cautious golfer plans less pace than neutral golfer from 20 ft")
	_expect(float(neutral_20["planned_past_feet"]) < float(bold_20["planned_past_feet"]), "bold golfer plans more pace than neutral golfer from 20 ft")
	_expect(float(cautious_20["assertive_tendency"]) < float(neutral_20["assertive_tendency"]), "risk tolerance continuously changes assertive tendency")
	_expect(float(neutral_20["assertive_tendency"]) < float(bold_20["assertive_tendency"]), "bold profile has highest assertive tendency")
	_expect(float(cautious_danger["planned_past_feet"]) < float(cautious_20["planned_past_feet"]), "fast downhill context reduces cautious golfer pace intent")


func _find_row(rows: Array, ability: float, distance: float) -> Dictionary:
	for row in rows:
		if absf(float(row["ability"]) - ability) < 0.001 and absf(float(row["distance_feet"]) - distance) < 0.001:
			return row
	return {}


func _find_profile_row(rows: Array, profile: String, distance: float, speed: float, slope: float) -> Dictionary:
	for row in rows:
		if str(row.get("profile", "")) == profile and absf(float(row["distance_feet"]) - distance) < 0.001 and absf(float(row.get("green_speed", 0.0)) - speed) < 0.001 and absf(float(row.get("along_slope", 0.0)) - slope) < 0.001:
			return row
	return {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
