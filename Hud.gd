extends Control

# ---------------------------------------------------------------------------
# In-game HUD: the nine-slot hotbar and the mining progress bar.
#
# Everything is built in code so the player scene only needs one empty
# full-rect Control.  Block icons are regions of the shared texture atlas.
# ---------------------------------------------------------------------------

const Registry = preload("res://BlockRegistry.gd")
const ToolDefs = preload("res://ToolDefs.gd")
const Inventory = preload("res://Inventory.gd")

const SLOT_SIZE := 56
const SLOT_GAP := 4
const ICON_MARGIN := 6.0

var inventory = null

var _slots: Array = []
var _icons: Array = []
var _name_labels: Array = []
var _count_labels: Array = []
var _mine_bar: ProgressBar
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_normal = _make_slot_style(false)
	_style_selected = _make_slot_style(true)
	_build_hotbar()
	_build_mining_bar()

func setup(inv) -> void:
	inventory = inv
	if not inventory.changed.is_connected(_refresh):
		inventory.changed.connect(_refresh)
	_refresh()

func set_mining_progress(fraction: float) -> void:
	if _mine_bar == null:
		return
	_mine_bar.value = clampf(fraction, 0.0, 1.0)
	_mine_bar.visible = fraction > 0.0001

# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _build_hotbar() -> void:
	var holder := CenterContainer.new()
	holder.name = "HotbarHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.anchor_left = 0.0
	holder.anchor_right = 1.0
	holder.anchor_top = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_top = -SLOT_SIZE - 18
	holder.offset_bottom = -10
	add_child(holder)

	var bar := HBoxContainer.new()
	bar.name = "Hotbar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_constant_override("separation", SLOT_GAP)
	holder.add_child(bar)

	for i in Inventory.SLOT_COUNT:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(panel)

		var icon := TextureRect.new()
		icon.position = Vector2(ICON_MARGIN, ICON_MARGIN)
		icon.size = Vector2(SLOT_SIZE - ICON_MARGIN * 2.0, SLOT_SIZE - ICON_MARGIN * 2.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		panel.add_child(icon)

		var name_label := Label.new()
		name_label.position = Vector2(2, 10)
		name_label.size = Vector2(SLOT_SIZE - 4, 30)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.add_theme_color_override("font_color", Color(1, 1, 1))
		name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		name_label.add_theme_constant_override("outline_size", 3)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.visible = false
		panel.add_child(name_label)

		var count_label := Label.new()
		count_label.position = Vector2(2, SLOT_SIZE - 18)
		count_label.size = Vector2(SLOT_SIZE - 6, 16)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.add_theme_font_size_override("font_size", 11)
		count_label.add_theme_color_override("font_color", Color(1, 1, 1))
		count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		count_label.add_theme_constant_override("outline_size", 3)
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(count_label)

		_slots.append(panel)
		_icons.append(icon)
		_name_labels.append(name_label)
		_count_labels.append(count_label)

func _build_mining_bar() -> void:
	_mine_bar = ProgressBar.new()
	_mine_bar.name = "MiningBar"
	_mine_bar.show_percentage = false
	_mine_bar.min_value = 0.0
	_mine_bar.max_value = 1.0
	_mine_bar.value = 0.0
	_mine_bar.anchor_left = 0.5
	_mine_bar.anchor_top = 0.5
	_mine_bar.anchor_right = 0.5
	_mine_bar.anchor_bottom = 0.5
	_mine_bar.offset_left = -60
	_mine_bar.offset_top = 34
	_mine_bar.offset_right = 60
	_mine_bar.offset_bottom = 43
	_mine_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mine_bar.visible = false

	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.6)
	background.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.93, 0.95, 0.95)
	fill.set_corner_radius_all(3)
	_mine_bar.add_theme_stylebox_override("background", background)
	_mine_bar.add_theme_stylebox_override("fill", fill)

	add_child(_mine_bar)

func _make_slot_style(is_selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.14, 0.82) if is_selected else Color(0, 0, 0, 0.55)
	style.set_border_width_all(3 if is_selected else 2)
	style.border_color = Color(1, 1, 1, 0.95) if is_selected else Color(0.75, 0.75, 0.75, 0.35)
	style.set_corner_radius_all(4)
	return style

# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if inventory == null:
		return

	for i in Inventory.SLOT_COUNT:
		var item = inventory.slots[i]
		var is_selected: bool = i == inventory.selected

		_slots[i].add_theme_stylebox_override("panel", _style_selected if is_selected else _style_normal)
		_icons[i].texture = null
		_icons[i].visible = false
		_name_labels[i].text = ""
		_name_labels[i].visible = false
		_count_labels[i].text = ""

		if item == null:
			continue

		if String(item.get("type", "")) == "block":
			_icons[i].texture = _block_icon(String(item["name"]))
			_icons[i].visible = true
			var count := int(item["count"])
			if count > 1:
				_count_labels[i].text = str(count)
		else:
			_name_labels[i].text = ToolDefs.tool_name(int(item["tool"]))
			_name_labels[i].visible = true
			_count_labels[i].text = ToolDefs.tier_name(int(item["tier"]))

func _block_icon(block_name: String) -> Texture2D:
	var id: int = Registry.id_of(block_name)
	var side: int = Registry.Side.only if Registry.is_flat(id) else Registry.Side.front
	var tile: Vector2 = Registry.side_uv(id, side)
	var atlas: Texture2D = Registry.get_atlas_texture()
	if atlas == null:
		return null

	var atlas_size := Vector2(Registry.get_atlas_size())
	var tile_pixels := Vector2(Registry.get_atlas_tile()) * atlas_size
	var tex := AtlasTexture.new()
	tex.atlas = atlas
	tex.region = Rect2(Vector2(tile.x * atlas_size.x, tile.y * atlas_size.y), tile_pixels)
	tex.filter_clip = true
	return tex
