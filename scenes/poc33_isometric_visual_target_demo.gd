extends "res://scenes/poc33_isometric_living_course_demo.gd"

# POC-33E: Visual Target Pass
# ----------------------------
# Keeps the POC-33D technical proof intact and layers a denser, more characterful
# miniature-course presentation over the same authoritative construction grid and
# living-course playback. This scene is intentionally presentation-only.

const IsometricVisualPolishLayer = preload("res://scenes/isometric_visual_polish_layer.gd")
const IsometricGolferArtLayer = preload("res://scenes/isometric_golfer_art_layer.gd")

var visual_polish_layer = null
var golfer_art_layer = null


func _ready() -> void:
	if not initialize_demo():
		push_error("POC-33E visual-target demo failed to initialize base living course")
		return
	_install_visual_target_pass()


func rotate_view(step_quarters: int) -> bool:
	if renderer == null or living_layer == null:
		return false
	renderer.rotate_view(step_quarters)
	living_layer.refresh_projection()
	if visual_polish_layer != null:
		visual_polish_layer.queue_redraw()
	if golfer_art_layer != null:
		golfer_art_layer.refresh_from_source()
	if camera != null:
		camera.position = visual_polish_layer.focus_center() if visual_polish_layer != null else renderer.visual_bounds().get_center()
	_update_hud()
	return true


func visual_snapshot() -> Dictionary:
	return {
		"base": snapshot(),
		"polish": visual_polish_layer.snapshot() if visual_polish_layer != null else {},
		"golfer_art": golfer_art_layer.snapshot() if golfer_art_layer != null else {},
		"placeholder_layer_hidden": living_layer != null and not living_layer.visible,
		"visual_zoom": camera.zoom.x if camera != null else 0.0
	}


func _install_visual_target_pass() -> void:
	if renderer == null or grid == null or living_layer == null:
		return

	# Draw order: authoritative terrain -> environmental polish -> stylized golfers.
	renderer.z_index = 0
	living_layer.visible = false

	visual_polish_layer = IsometricVisualPolishLayer.new()
	visual_polish_layer.name = "IsometricVisualPolishLayer"
	visual_polish_layer.z_index = 1
	add_child(visual_polish_layer)
	if not visual_polish_layer.configure(renderer, grid):
		push_error("POC-33E visual polish layer failed to configure")

	golfer_art_layer = IsometricGolferArtLayer.new()
	golfer_art_layer.name = "IsometricGolferArtLayer"
	golfer_art_layer.z_index = 2
	add_child(golfer_art_layer)
	if not golfer_art_layer.configure(living_layer, grid):
		push_error("POC-33E golfer art layer failed to configure")

	# The technical proof was intentionally framed as a whole-property overview.
	# The visual target uses a closer management-game scale so individual trees,
	# golfers, fairway texture, and landmarks actually read on screen.
	if camera != null:
		var target_zoom := 0.50
		camera.zoom = Vector2(target_zoom, target_zoom)
		camera.position = visual_polish_layer.focus_center()
