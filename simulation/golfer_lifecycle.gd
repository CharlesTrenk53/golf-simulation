extends RefCounted

# Golfer Lifecycle
# ----------------
# Aging acts on physical capacity, not directly on learned golf technique.
# Annual changes are deliberately small and continuous so long-run effects emerge
# over seasons rather than appearing as abrupt birthday penalties.
#
# These rates are calibration starting points, not final physiological claims.
# They are intentionally isolated here so future fitness, injury, coaching,
# practice volume, and individual aging profiles can modify them independently.

func advance_year(golfer: Node) -> Dictionary:
	var starting_age: int = int(golfer.age)
	var before := _physical_snapshot(golfer)
	var rates := annual_capacity_rates(starting_age)

	golfer.physical_power = _apply_rate(float(golfer.physical_power), float(rates["power"]))
	golfer.mobility = _apply_rate(float(golfer.mobility), float(rates["mobility"]))
	golfer.coordination = _apply_rate(float(golfer.coordination), float(rates["coordination"]))
	golfer.endurance = _apply_rate(float(golfer.endurance), float(rates["endurance"]))
	golfer.age = starting_age + 1

	return {
		"age_before": starting_age,
		"age_after": int(golfer.age),
		"rates": rates.duplicate(true),
		"before": before,
		"after": _physical_snapshot(golfer)
	}

func annual_capacity_rates(age: int) -> Dictionary:
	# Rates are fractional annual changes. Young adults can still make modest
	# physical gains simply through maturation/training opportunity. Mid-career is
	# close to flat. Later decades introduce gradually stronger physical headwinds.
	if age < 25:
		return {"power": 0.0025, "mobility": 0.0015, "coordination": 0.0015, "endurance": 0.0020}
	if age < 35:
		return {"power": 0.0010, "mobility": 0.0005, "coordination": 0.0010, "endurance": 0.0005}
	if age < 45:
		return {"power": -0.0010, "mobility": -0.0010, "coordination": 0.0003, "endurance": -0.0010}
	if age < 55:
		return {"power": -0.0030, "mobility": -0.0025, "coordination": -0.0005, "endurance": -0.0025}
	if age < 65:
		return {"power": -0.0055, "mobility": -0.0045, "coordination": -0.0015, "endurance": -0.0045}
	if age < 75:
		return {"power": -0.0080, "mobility": -0.0065, "coordination": -0.0030, "endurance": -0.0065}
	return {"power": -0.0100, "mobility": -0.0080, "coordination": -0.0045, "endurance": -0.0080}

func _apply_rate(value: float, rate: float) -> float:
	return clamp(value * (1.0 + rate), 0.0, 100.0)

func _physical_snapshot(golfer: Node) -> Dictionary:
	return {
		"power": float(golfer.physical_power),
		"mobility": float(golfer.mobility),
		"coordination": float(golfer.coordination),
		"endurance": float(golfer.endurance)
	}
