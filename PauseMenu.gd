extends CanvasLayer

# ---------------------------------------------------------------------------
# In-game pause menu.  Owns the paused state of the tree and the mouse mode,
# so the player script no longer has to juggle pause logic.
# ---------------------------------------------------------------------------

const UiStyle = preload("res://UiStyle.gd")
const SettingsPanelScene = preload("res://SettingsPanel.gd")

var _root: Control
var _settings_panel
var _resume_button: Button

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

func _build() -> void:
	_root = Control.new()
	_root.name = "PauseRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.visible = false
	add_child(_root)

	_root.add_child(UiStyle.dim_background(0.6))

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.panel_box())
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(300, 0)
	panel.add_child(box)

	var title := UiStyle.label("Paused", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var hint := UiStyle.label("Esc resumes the game", 13, UiStyle.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	box.add_child(gap)

	_resume_button = Button.new()
	_resume_button.text = "Resume"
	UiStyle.apply_button(_resume_button, true)
	_resume_button.pressed.connect(_resume)
	box.add_child(_resume_button)

	var settings := Button.new()
	settings.text = "Settings"
	UiStyle.apply_button(settings)
	settings.pressed.connect(_open_settings)
	box.add_child(settings)

	var menu := Button.new()
	menu.text = "Main Menu"
	UiStyle.apply_button(menu)
	menu.pressed.connect(_go_to_menu)
	box.add_child(menu)

	var quit := Button.new()
	quit.text = "Quit Game"
	UiStyle.apply_button(quit)
	quit.pressed.connect(_quit_game)
	box.add_child(quit)

	_settings_panel = SettingsPanelScene.new()
	add_child(_settings_panel)

func _unhandled_input(event: InputEvent) -> void:
	if _settings_panel != null and _settings_panel.visible:
		return
	if event.is_action_pressed("pause"):
		set_open(not _root.visible)
		get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	_root.visible = open
	if open:
		_settings_panel.close()
		get_tree().paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_resume_button.grab_focus()
	else:
		Settings.save_settings()
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _resume() -> void:
	set_open(false)

func _open_settings() -> void:
	_settings_panel.open()

func _go_to_menu() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://MainMenu.tscn")

func _quit_game() -> void:
	get_tree().paused = false
	get_tree().quit()
