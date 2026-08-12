extends RefCounted

const PuttingReadModel = preload("res://simulation/putting_read_model.gd")
const PuttingStrategyModel = preload("res://simulation/putting_strategy_model.gd")
const PuttingProficiencyModel = preload("res://simulation/putting_proficiency_model.gd")
const PuttingExecutionModel = preload("res://simulation/putting_execution_model.gd")
const PuttingRollModel = preload("res://simulation/putting_roll_model.gd")

var read_model = PuttingReadModel.new()
var strategy_model = PuttingStrategyModel.new()
var proficiency_model = PuttingProficiencyModel.new()
var execution_model = PuttingExecutionModel.new()
var roll_model = PuttingRollModel.new()


func resolve(
	golfer: Node,
	distance_feet: float,
	seed_value: int,
	slope_across_percent: float = 0.0,
	slope_along_percent: float = 0.0,
	green_speed: float = 10.0
) -> Dictionary:
	var read: Dictionary = read_model.plan_putt(
		distance_feet,
		slope_across_percent,
		slope_along_percent,
		green_speed
	)
	var strategy: Dictionary = strategy_model.choose_strategy(golfer, read)
	var proficiency: Dictionary = proficiency_model.assess(golfer, strategy)
	var execution: Dictionary = execution_model.realize(strategy, proficiency, seed_value)
	var roll: Dictionary = roll_model.resolve(strategy, execution)

	return {
		"read": read,
		"strategy": strategy,
		"proficiency": proficiency,
		"execution": execution,
		"roll": roll,
		"holed": bool(roll.get("holed", false)),
		"finish_distance_from_hole_feet": float(roll.get("finish_distance_from_hole_feet", 0.0)),
		"final_lateral_feet": float(roll.get("final_lateral_feet", 0.0)),
		"rolled_distance_feet": float(roll.get("rolled_distance_feet", 0.0))
	}
