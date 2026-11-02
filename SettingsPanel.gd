extends Control

# ---------------------------------------------------------------------------
# Settings overlay shared by the main menu and the pause menu.
#
# Every change is applied live through the Settings autoload and written to
# disk when the panel closes.
# ---------------------------------------------------------------------------

signal closed

const UiStyle = preload("res://UiStyle.gd")

var _sensitivity_slider: HSlider
var _render_slider: HSlider
var _fov_slider: HSlider
var _sensitivity_value: Label
var _render_value: Label
var _fov_value: Label
var _fullscreen_check: CheckButton
var _vsync_check: CheckButton
var _syncing := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()

func _build() -> void:
	add_child(UiStyle.dim_background(0.65))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	var title := UiStyle.label("Settings", 34)
	box.add_child(title)

	var hint := UiStyle.label("Changes apply immediately and are saved when you close this screen.", 14, UiStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(560, 0)
	box.add_child(hint)

	box.add_child(_section("Controls"))
	_sensitivity_slider = _add_slider(box, "Mouse sensitivity", Settings.MIN_SENSITIVITY,
		Settings.MAX_SENSITIVITY, 0.05, Settings.mouse_sensitivity, "%.2f",
		func(value: float) -> void: Settings.set_mouse_sensitivity(value))
	_sensitivity_value = _last_value_label

	box.add_child(_section("Video"))
	_render_slider = _add_slider(box, "Render distance", Settings.MIN_RENDER_DISTANCE,
		Settings.MAX_RENDER_DISTANCE, 1.0, Settings.render_distance, "%d chunks",
		func(value: float) -> void: Settings.set_render_distance(int(value)))
	_render_value = _last_value_label

	_fov_slider = _add_slider(box, "Field of view", Settings.MIN_FOV,
		Settings.MAX_FOV, 1.0, Settings.fov, "%d",
		func(value: float) -> void: Settings.set_fov(int(value)))
	_fov_value = _last_value_label

	_fullscreen_check = _add_check(box, "Fullscreen", Settings.fullscreen,
		func(value: bool) -> void: Settings.set_fullscreen(value))
	_vsync_check = _add_check(box, "V-Sync", Settings.vsync,
		func(value: bool) -> void: Settings.set_vsync(value))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	box.add_child(spacer)

	var back := Button.new()
	back.text = "Back"
	UiStyle.apply_button(back, true)
	back.custom_minimum_size = Vector2(180, 44)
	back.pressed.connect(close)
	box.add_child(back)

# ---------------------------------------------------------------------------
# Row builders
# ---------------------------------------------------------------------------

var _last_value_label: Label

func _section(text: String) -> Control:
	var row := HBoxContainer.new()
	var label := UiStyle.label(text, 14, UiStyle.MUTED)
	row.add_child(label)
	return row

func _add_slider(parent: VBoxContainer, title: String, min_v: float, max_v: float,
		step: float, value: float, fmt: String, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var label := UiStyle.label(title, 17)
	label.custom_minimum_size = Vector2(220, 0)
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(270, 26)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label := UiStyle.label(fmt % value, 16)
	value_label.custom_minimum_size = Vector2(110, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = fmt % new_value
		if not _syncing:
			on_change.call(new_value)
	)

	_last_value_label = value_label
	return slider

func _add_check(parent: VBoxContainer, title: String, value: bool, on_change: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)

	var label := UiStyle.label(title, 17)
	label.custom_minimum_size = Vector2(220, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var check := CheckButton.new()
	check.button_pressed = value
	check.focus_mode = Control.FOCUS_ALL
	row.add_child(check)

	check.toggled.connect(func(pressed: bool) -> void:
		if not _syncing:
			on_change.call(pressed)
	)
	return check

# ---------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------

func open() -> void:
	_syncing = true
	_sensitivity_slider.value = Settings.mouse_sensitivity
	_render_slider.value = Settings.render_distance
	_fov_slider.value = Settings.fov
	_fullscreen_check.button_pressed = Settings.fullscreen
	_vsync_check.button_pressed = Settings.vsync
	_syncing = false

	_sensitivity_value.text = "%.2f" % Settings.mouse_sensitivity
	_render_value.text = "%d chunks" % Settings.render_distance
	_fov_value.text = "%d" % Settings.fov

	visible = true
	move_to_front()

func close() -> void:
	if not visible:
		return
	visible = false
	Settings.save_settings()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
