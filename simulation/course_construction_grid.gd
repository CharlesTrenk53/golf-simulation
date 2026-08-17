extends RefCounted

# POC-22A / POC-30A: Course Construction Grid
# ---------------------------------------------
# Authoritative player-buildable land grid. The grid is intentionally separate
# from rendering and golfer simulation so the same saved construction data can
# drive economics, visuals, navigation, and HoleDefinition generation.
#
# POC-30A keeps that authority intact while formalizing the complete first-pass
# golf-surface vocabulary and exposing neighborhood information for downstream
# organic rendering. Renderers may smooth these boundaries; they may not invent
# a different surface assignment than the cells stored here.

const SCHEMA_VERSION: int = 1
const DEFAULT_TILE_SIZE_YARDS: float = 5.0
const DEFAULT_SURFACE: String = "ROUGH"

const SURFACE_TYPES := [
	"ROUGH",
	"FAIRWAY",
	"GREEN",
	"FRINGE",
	"TEE",
	"BUNKER",
	"WATER"
]

# Placeholder construction prices. Balancing remains outside POC-30; FRINGE uses
# the same placeholder price as FAIRWAY so adding the authoritative surface does
# not introduce a new economic tuning claim.
const SURFACE_BUILD_COST := {
	"ROUGH": 0,
	"FAIRWAY": 80,
	"GREEN": 220,
	"FRINGE": 80,
	"TEE": 140,
	"BUNKER": 180,
	"WATER": 260
}

# Stable eight-neighbor order used by presentation code when deriving rounded
# edges/corners from the authoritative grid. Values outside the property return
# an empty surface string rather than being silently treated as ROUGH.
const NEIGHBOR_OFFSETS := {
	"N": Vector2i(0, -1),
	"NE": Vector2i(1, -1),
	"E": Vector2i(1, 0),
	"SE": Vector2i(1, 1),
	"S": Vector2i(0, 1),
	"SW": Vector2i(-1, 1),
	"W": Vector2i(-1, 0),
	"NW": Vector2i(-1, -1)
}

var width: int = 0
var height: int = 0
var tile_size_yards: float = DEFAULT_TILE_SIZE_YARDS
var origin: Vector2 = Vector2.ZERO
var _tiles: Array = []


func configure(grid_width: int, grid_height: int, size_yards: float = DEFAULT_TILE_SIZE_YARDS, world_origin: Vector2 = Vector2.ZERO) -> bool:
	if grid_width <= 0 or grid_height <= 0 or size_yards <= 0.0:
		return false
	width = grid_width
	height = grid_height
	tile_size_yards = size_yards
	origin = world_origin
	_tiles.clear()
	for y in range(height):
		var row: Array = []
		for x in range(width):
			row.append(_new_tile(x, y, DEFAULT_SURFACE))
		_tiles.append(row)
	return true


func is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func set_surface(x: int, y: int, surface: String) -> bool:
	var normalized := surface.to_upper()
	if not is_in_bounds(x, y) or not SURFACE_TYPES.has(normalized):
		return false
	_tiles[y][x]["surface"] = normalized
	_tiles[y][x]["build_cost"] = int(SURFACE_BUILD_COST.get(normalized, 0))
	return true


func surface_at(x: int, y: int) -> String:
	if not is_in_bounds(x, y):
		return ""
	return str(_tiles[y][x].get("surface", DEFAULT_SURFACE))


func surface_neighbors(x: int, y: int) -> Dictionary:
	if not is_in_bounds(x, y):
		return {}
	var result := {}
	for direction_value in NEIGHBOR_OFFSETS.keys():
		var direction: String = str(direction_value)
		var offset: Vector2i = NEIGHBOR_OFFSETS[direction]
		result[direction] = surface_at(x + offset.x, y + offset.y)
	return result


func same_surface_neighbors(x: int, y: int) -> Dictionary:
	if not is_in_bounds(x, y):
		return {}
	var own_surface: String = surface_at(x, y)
	var neighbors: Dictionary = surface_neighbors(x, y)
	var result := {}
	for direction_value in NEIGHBOR_OFFSETS.keys():
		var direction: String = str(direction_value)
		result[direction] = not own_surface.is_empty() and str(neighbors.get(direction, "")) == own_surface
	return result


func tile_at(x: int, y: int) -> Dictionary:
	if not is_in_bounds(x, y):
		return {}
	return _tiles[y][x].duplicate(true)


func tile_center_world(x: int, y: int) -> Vector3:
	if not is_in_bounds(x, y):
		return Vector3.ZERO
	return Vector3(
		origin.x + (float(x) + 0.5) * tile_size_yards,
		float(_tiles[y][x].get("elevation", 0.0)),
		origin.y + (float(y) + 0.5) * tile_size_yards
	)


func set_elevation(x: int, y: int, elevation_yards: float) -> bool:
	if not is_in_bounds(x, y):
		return false
	_tiles[y][x]["elevation"] = elevation_yards
	return true


func count_surface(surface: String) -> int:
	var normalized := surface.to_upper()
	var count: int = 0
	for row in _tiles:
		for tile in row:
			if str(tile.get("surface", "")) == normalized:
				count += 1
	return count


func total_placed_build_cost() -> int:
	var total: int = 0
	for row in _tiles:
		for tile in row:
			total += int(tile.get("build_cost", 0))
	return total


func to_dictionary() -> Dictionary:
	var serialized_tiles: Array = []
	for row in _tiles:
		var serialized_row: Array = []
		for tile in row:
			serialized_row.append(tile.duplicate(true))
		serialized_tiles.append(serialized_row)
	return {
		"schema_version": SCHEMA_VERSION,
		"width": width,
		"height": height,
		"tile_size_yards": tile_size_yards,
		"origin": [origin.x, origin.y],
		"tiles": serialized_tiles
	}


static func from_dictionary(data: Dictionary):
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return null
	var result = load("res://simulation/course_construction_grid.gd").new()
	var raw_origin: Array = data.get("origin", [0.0, 0.0])
	if raw_origin.size() < 2:
		return null
	if not result.configure(
		int(data.get("width", 0)),
		int(data.get("height", 0)),
		float(data.get("tile_size_yards", DEFAULT_TILE_SIZE_YARDS)),
		Vector2(float(raw_origin[0]), float(raw_origin[1]))
	):
		return null
	var rows: Array = data.get("tiles", [])
	if rows.size() != result.height:
		return null
	for y in range(result.height):
		if not rows[y] is Array or rows[y].size() != result.width:
			return null
		for x in range(result.width):
			var tile: Dictionary = rows[y][x]
			if not result.set_surface(x, y, str(tile.get("surface", DEFAULT_SURFACE))):
				return null
			result.set_elevation(x, y, float(tile.get("elevation", 0.0)))
	return result


func _new_tile(x: int, y: int, surface: String) -> Dictionary:
	return {
		"x": x,
		"y": y,
		"surface": surface,
		"elevation": 0.0,
		"build_cost": int(SURFACE_BUILD_COST.get(surface, 0))
	}
