extends RefCounted

# POC-22B / POC-32A: Course Construction Economy
# ------------------------------------------------
# Owns the player's construction cash and applies paid surface and terrain
# changes to the authoritative CourseConstructionGrid. The grid still owns
# spatial truth; this layer decides whether a proposed construction action can
# be afforded and guarantees that paid edits are applied atomically.

const SCHEMA_VERSION: int = 1
const DEFAULT_TERRAIN_COST_PER_YARD: int = 120
const CourseConstructionGrid = preload("res://simulation/course_construction_grid.gd")

var grid = null
var cash_balance: int = 0
var lifetime_construction_spend: int = 0
var transaction_history: Array = []


func configure(construction_grid, starting_cash: int) -> bool:
	if construction_grid == null or starting_cash < 0:
		return false
	grid = construction_grid
	cash_balance = starting_cash
	lifetime_construction_spend = 0
	transaction_history.clear()
	return true


func quote_surface_change(x: int, y: int, surface: String) -> Dictionary:
	if grid == null or not grid.is_in_bounds(x, y):
		return {"valid": false, "reason": "OUT_OF_BOUNDS", "cost": 0}
	var normalized := surface.to_upper()
	if not CourseConstructionGrid.SURFACE_TYPES.has(normalized):
		return {"valid": false, "reason": "UNKNOWN_SURFACE", "cost": 0}
	var existing: String = grid.surface_at(x, y)
	var cost: int = 0 if existing == normalized else int(CourseConstructionGrid.SURFACE_BUILD_COST.get(normalized, 0))
	return {
		"valid": true,
		"reason": "",
		"x": x,
		"y": y,
		"from_surface": existing,
		"to_surface": normalized,
		"cost": cost,
		"affordable": cost <= cash_balance
	}


func build_surface(x: int, y: int, surface: String) -> Dictionary:
	var quote: Dictionary = quote_surface_change(x, y, surface)
	if not bool(quote.get("valid", false)):
		return quote
	var cost: int = int(quote.get("cost", 0))
	if cost > cash_balance:
		quote["built"] = false
		quote["reason"] = "INSUFFICIENT_FUNDS"
		quote["balance_after"] = cash_balance
		return quote
	if not grid.set_surface(x, y, str(quote.get("to_surface", ""))):
		quote["built"] = false
		quote["reason"] = "GRID_REJECTED_CHANGE"
		quote["balance_after"] = cash_balance
		return quote

	cash_balance -= cost
	lifetime_construction_spend += cost
	quote["built"] = true
	quote["balance_after"] = cash_balance
	transaction_history.append(quote.duplicate(true))
	return quote


func quote_elevation_changes(changes: Array, cost_per_yard: int = DEFAULT_TERRAIN_COST_PER_YARD) -> Dictionary:
	if grid == null:
		return {"valid": false, "reason": "NOT_INITIALIZED", "cost": 0}
	if cost_per_yard < 0:
		return {"valid": false, "reason": "INVALID_TERRAIN_COST", "cost": 0}
	if changes.is_empty():
		return {"valid": false, "reason": "NO_TERRAIN_CHANGES", "cost": 0}

	var normalized_changes: Array = []
	var seen_cells := {}
	var total_vertical_yards: float = 0.0
	for raw_change in changes:
		if not raw_change is Dictionary:
			return {"valid": false, "reason": "INVALID_TERRAIN_CHANGE", "cost": 0}
		var x: int = int(raw_change.get("x", -1))
		var y: int = int(raw_change.get("y", -1))
		if not grid.is_in_bounds(x, y):
			return {"valid": false, "reason": "OUT_OF_BOUNDS", "cost": 0}
		var key := Vector2i(x, y)
		if seen_cells.has(key):
			return {"valid": false, "reason": "DUPLICATE_TERRAIN_CELL", "cost": 0}
		seen_cells[key] = true

		var from_elevation: float = float(grid.tile_at(x, y).get("elevation", 0.0))
		var to_elevation: float = float(raw_change.get("to_elevation", from_elevation))
		var delta: float = to_elevation - from_elevation
		total_vertical_yards += absf(delta)
		normalized_changes.append({
			"x": x,
			"y": y,
			"from_elevation": from_elevation,
			"to_elevation": to_elevation,
			"delta_elevation": delta
		})

	var cost: int = int(ceil(total_vertical_yards * float(cost_per_yard)))
	return {
		"valid": true,
		"reason": "",
		"type": "TERRAIN",
		"changes": normalized_changes,
		"total_vertical_yards": total_vertical_yards,
		"cost_per_yard": cost_per_yard,
		"cost": cost,
		"affordable": cost <= cash_balance
	}


func build_elevation_changes(changes: Array, cost_per_yard: int = DEFAULT_TERRAIN_COST_PER_YARD) -> Dictionary:
	var quote: Dictionary = quote_elevation_changes(changes, cost_per_yard)
	if not bool(quote.get("valid", false)):
		quote["built"] = false
		return quote
	var cost: int = int(quote.get("cost", 0))
	if cost > cash_balance:
		quote["built"] = false
		quote["reason"] = "INSUFFICIENT_FUNDS"
		quote["balance_after"] = cash_balance
		return quote

	# The quote validates every cell before any mutation, so this loop is atomic
	# with respect to normal construction-grid failures.
	for normalized_change in quote.get("changes", []):
		if not grid.set_elevation(
			int(normalized_change.get("x", -1)),
			int(normalized_change.get("y", -1)),
			float(normalized_change.get("to_elevation", 0.0))
		):
			quote["built"] = false
			quote["reason"] = "GRID_REJECTED_TERRAIN_CHANGE"
			quote["balance_after"] = cash_balance
			return quote

	cash_balance -= cost
	lifetime_construction_spend += cost
	quote["built"] = true
	quote["balance_after"] = cash_balance
	transaction_history.append(quote.duplicate(true))
	return quote


func add_revenue(amount: int, source: String = "COURSE_REVENUE") -> bool:
	if amount < 0:
		return false
	cash_balance += amount
	transaction_history.append({
		"type": "REVENUE",
		"source": source,
		"amount": amount,
		"balance_after": cash_balance
	})
	return true


func to_dictionary() -> Dictionary:
	if grid == null:
		return {}
	return {
		"schema_version": SCHEMA_VERSION,
		"cash_balance": cash_balance,
		"lifetime_construction_spend": lifetime_construction_spend,
		"transaction_history": transaction_history.duplicate(true),
		"grid": grid.to_dictionary()
	}


static func from_dictionary(data: Dictionary):
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var restored_grid = CourseConstructionGrid.from_dictionary(data.get("grid", {}))
	if restored_grid == null:
		return null
	var result = load("res://simulation/course_construction_economy.gd").new()
	if not result.configure(restored_grid, int(data.get("cash_balance", -1))):
		return null
	result.lifetime_construction_spend = int(data.get("lifetime_construction_spend", 0))
	result.transaction_history = data.get("transaction_history", []).duplicate(true)
	return result
