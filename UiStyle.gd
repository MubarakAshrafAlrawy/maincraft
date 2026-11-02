extends RefCounted

# Shared look for the menus so the main menu, pause menu and settings panel
# stay visually consistent without a .theme resource.

const BG := Color(0.086, 0.090, 0.110, 0.94)
const BORDER := Color(0.85, 0.87, 0.92, 0.22)
const TEXT := Color(0.94, 0.95, 0.97)
const MUTED := Color(0.68, 0.72, 0.78)

static func panel_box() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BG
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(28)
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 18
	return style

static func button_box(accent: bool, hover := false, pressed := false) -> StyleBoxFlat:
	var base := Color(0.21, 0.44, 0.24) if accent else Color(0.19, 0.20, 0.24)
	if hover:
		base = base.lightened(0.12)
	if pressed:
		base = base.darkened(0.14)

	var style := StyleBoxFlat.new()
	style.bg_color = base
	style.border_color = Color(1, 1, 1, 0.16)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

static func apply_button(button: Button, accent := false) -> void:
	button.add_theme_stylebox_override("normal", button_box(accent))
	button.add_theme_stylebox_override("hover", button_box(accent, true))
	button.add_theme_stylebox_override("pressed", button_box(accent, false, true))
	button.add_theme_stylebox_override("focus", button_box(accent, true))
	button.add_theme_stylebox_override("disabled", button_box(false))
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_pressed_color", Color(0.9, 0.9, 0.9))
	button.add_theme_font_size_override("font_size", 18)
	button.custom_minimum_size = Vector2(260, 46)
	button.focus_mode = Control.FOCUS_ALL

static func label(text: String, size := 18, color := TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node

static func dim_background(alpha := 0.6) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0.02, 0.03, 0.04, alpha)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	return rect
