extends Control

# ---------------------------------------------------------------------------
# Main menu: the project now boots here instead of dropping straight into the
# world, so settings can be changed before the first chunk is generated.
# ---------------------------------------------------------------------------

const UiStyle = preload("res://UiStyle.gd")
const SettingsPanelScene = preload("res://SettingsPanel.gd")

var _settings_panel

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	_build()

func _build() -> void:
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.043, 0.075, 0.118))
	gradient.set_color(1, Color(0.075, 0.157, 0.102))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0.1, 0.0)
	gradient_texture.fill_to = Vector2(0.9, 1.0)
	background.texture = gradient_texture
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	var title := UiStyle.label("MAINCRAFT", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	var subtitle := UiStyle.label("Infinite voxel world · threaded chunk streaming", 16, UiStyle.MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	box.add_child(gap)

	var play := Button.new()
	play.text = "Singleplayer"
	UiStyle.apply_button(play, true)
	play.custom_minimum_size = Vector2(340, 50)
	play.pressed.connect(_on_play)
	box.add_child(play)

	var settings := Button.new()
	settings.text = "Settings"
	UiStyle.apply_button(settings)
	settings.custom_minimum_size = Vector2(340, 50)
	settings.pressed.connect(_on_settings)
	box.add_child(settings)

	var quit := Button.new()
	quit.text = "Quit"
	UiStyle.apply_button(quit)
	quit.custom_minimum_size = Vector2(340, 50)
	quit.pressed.connect(_on_quit)
	box.add_child(quit)

	var version := UiStyle.label("v0.4  ·  data-driven content", 13, Color(0.6, 0.65, 0.7, 0.8))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.offset_left = 18
	version.offset_top = -32
	version.offset_bottom = -10
	add_child(version)

	_settings_panel = SettingsPanelScene.new()
	add_child(_settings_panel)

	play.grab_focus()

func _on_play() -> void:
	get_tree().change_scene_to_file("res://Spatial.tscn")

func _on_settings() -> void:
	_settings_panel.open()

func _on_quit() -> void:
	get_tree().quit()
