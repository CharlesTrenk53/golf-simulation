extends "res://scenes/construction_grid_renderer.gd"

# POC-30F: Contoured Surface Overlay
# ----------------------------------
# Bridges the topology-softened POC-30B/C surface renderer to the center-anchored
# POC-30D terrain. The construction grid remains the only source of elevation
# truth. This overlay uses the same center/edge/corner interpolation as the
# contoured base terrain so fairway, green, fringe, tee, bunker, water, and their
# transition bands sit on the same visible landform instead of a second plane.
#
# ROUGH is hidden here because ConstructionGridContouredTerrain supplies the
# common landform/base rough. The original renderer keeps its old behavior for
# backward compatibility with POC-22 and earlier focused tests.

var contoured_base_active: bool = false


func render_grid(grid) -> bool:
	contoured_base_active = false
	var rendered: bool = super.render_grid(grid)
	if not rendered:
		return false
	var rough: Node3D = surface_visual("ROUGH")
	if rough != null:
		rough.visible = false
		rough.set_meta("visual_projection", "hidden_under_contoured_base")
	contoured_base_active = true
	return true


func rough_base_hidden() -> bool:
	var rough: Node3D = surface_visual("ROUGH")
	return contoured_base_active and rough != null and not rough.visible


func surface_height_at_cell_uv(cell_x: int, cell_y: int, u_value: float, v_value: float) -> float:
	if construction_grid == null or not construction_grid.is_in_bounds(cell_x, cell_y):
		return 0.0

	var u: float = clampf(u_value, 0.0, 1.0)
	var v: float = clampf(v_value, 0.0, 1.0)
	var center: float = _tile_elevation(cell_x, cell_y)
	var north: float = _edge_midpoint_height(cell_x, cell_y, "N")
	var east: float = _edge_midpoint_height(cell_x, cell_y, "E")
	var south: float = _edge_midpoint_height(cell_x, cell_y, "S")
	var west: float = _edge_midpoint_height(cell_x, cell_y, "W")
	var nw: float = terrain_height_at_grid_corner(cell_x, cell_y)
	var ne: float = terrain_height_at_grid_corner(cell_x + 1, cell_y)
	var se: float = terrain_height_at_grid_corner(cell_x + 1, cell_y + 1)
	var sw: float = terrain_height_at_grid_corner(cell_x, cell_y + 1)

	if u <= 0.5 and v <= 0.5:
		return _bilinear(nw, north, west, center, u * 2.0, v * 2.0)
	if u > 0.5 and v <= 0.5:
		return _bilinear(north, ne, center, east, (u - 0.5) * 2.0, v * 2.0)
	if u > 0.5 and v > 0.5:
		return _bilinear(center, east, south, se, (u - 0.5) * 2.0, (v - 0.5) * 2.0)
	return _bilinear(west, center, sw, south, u * 2.0, (v - 0.5) * 2.0)


# Override the base renderer's corner-only interpolation with the exact POC-30D
# center-anchored interpolation. All base surface and transition geometry flows
# through this function.
func _terrain_height_inside_cell(cell_x: int, cell_y: int, tx_value: float, tz_value: float) -> float:
	return surface_height_at_cell_uv(cell_x, cell_y, tx_value, tz_value)


func _tile_elevation(x: int, y: int) -> float:
	return float(construction_grid.tile_at(x, y).get("elevation", 0.0))


func _edge_midpoint_height(cell_x: int, cell_y: int, direction: String) -> float:
	var neighbor := Vector2i(cell_x, cell_y)
	match direction:
		"N":
			neighbor.y -= 1
		"E":
			neighbor.x += 1
		"S":
			neighbor.y += 1
		"W":
			neighbor.x -= 1
	var own: float = _tile_elevation(cell_x, cell_y)
	if not construction_grid.is_in_bounds(neighbor.x, neighbor.y):
		return own
	return (own + _tile_elevation(neighbor.x, neighbor.y)) * 0.5


func _bilinear(nw: float, ne: float, sw: float, se: float, u: float, v: float) -> float:
	var north: float = lerpf(nw, ne, u)
	var south: float = lerpf(sw, se, u)
	return lerpf(north, south, v)
