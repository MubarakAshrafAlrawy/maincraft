extends Node

# ---------------------------------------------------------------------------
# Persisted game settings (autoloaded as "Settings").
#
# Values are applied live and stored in user://settings.cfg, so the main menu,
# the pause menu and the running world all read from the same place.
# ---------------------------------------------------------------------------

signal changed

const FILE_PATH := "user://settings.cfg"

const DEFAULT_SENSITIVITY := 0.3
const DEFAULT_RENDER_DISTANCE := 5
const DEFAULT_FOV := 75

const MIN_SENSITIVITY := 0.05
const MAX_SENSITIVITY := 1.5
const MIN_RENDER_DISTANCE := 2
const MAX_RENDER_DISTANCE := 10
const MIN_FOV := 50
const MAX_FOV := 110

var mouse_sensitivity := DEFAULT_SENSITIVITY
var render_distance := DEFAULT_RENDER_DISTANCE
var fov := DEFAULT_FOV
var fullscreen := false
var vsync := true

func _ready() -> void:
	load_settings()
	apply_display()

# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(FILE_PATH) != OK:
		return

	mouse_sensitivity = clampf(
		float(cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)),
		MIN_SENSITIVITY, MAX_SENSITIVITY
	)
	render_distance = clampi(
		int(cfg.get_value("video", "render_distance", render_distance)),
		MIN_RENDER_DISTANCE, MAX_RENDER_DISTANCE
	)
	fov = clampi(int(cfg.get_value("video", "fov", fov)), MIN_FOV, MAX_FOV)
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("video", "vsync", vsync))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("video", "render_distance", render_distance)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.save(FILE_PATH)

# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

func apply_display() -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)

# ---------------------------------------------------------------------------
# Setters (clamp, apply, notify)
# ---------------------------------------------------------------------------

func set_mouse_sensitivity(value: float) -> void:
	var clamped := clampf(value, MIN_SENSITIVITY, MAX_SENSITIVITY)
	if is_equal_approx(clamped, mouse_sensitivity):
		return
	mouse_sensitivity = clamped
	changed.emit()

func set_render_distance(value: int) -> void:
	var clamped := clampi(value, MIN_RENDER_DISTANCE, MAX_RENDER_DISTANCE)
	if clamped == render_distance:
		return
	render_distance = clamped
	changed.emit()

func set_fov(value: int) -> void:
	var clamped := clampi(value, MIN_FOV, MAX_FOV)
	if clamped == fov:
		return
	fov = clamped
	changed.emit()

func set_fullscreen(value: bool) -> void:
	if value == fullscreen:
		return
	fullscreen = value
	apply_display()
	changed.emit()

func set_vsync(value: bool) -> void:
	if value == vsync:
		return
	vsync = value
	apply_display()
	changed.emit()
