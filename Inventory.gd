extends RefCounted

# ---------------------------------------------------------------------------
# Player inventory.
#
# Nine hotbar slots, each one either empty, a block stack, or a tool:
#   {"type": "block", "name": "Dirt", "count": 12}
#   {"type": "tool",  "tool": ToolDefs.Tool.PICKAXE, "tier": ToolDefs.Tier.WOOD}
#
# Tools are single items (no count); blocks stack up to MAX_STACK.
# The WorldScript reads held_tool()/held_block() to decide mining speed,
# drops and placement, so this is the single place that owns item state.
# ---------------------------------------------------------------------------

signal changed

const ToolDefs = preload("res://ToolDefs.gd")

const SLOT_COUNT := 9
const MAX_STACK := 64

# Tier order used when cycling a tool with T (debug / testing aid).
const TIER_CYCLE := [
	ToolDefs.Tier.WOOD,
	ToolDefs.Tier.STONE,
	ToolDefs.Tier.IRON,
	ToolDefs.Tier.GOLD,
	ToolDefs.Tier.DIAMOND,
	ToolDefs.Tier.NETHERITE,
]

var slots: Array = []
var selected := 0

func _init() -> void:
	slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		slots[i] = null

# Tools for every job plus a small dirt stack so placement can be tested
# without mining first.  Slots 5-8 stay free for collected blocks.
func setup_default() -> void:
	for i in SLOT_COUNT:
		slots[i] = null

	slots[0] = _make_tool(ToolDefs.Tool.PICKAXE, ToolDefs.Tier.WOOD)
	slots[1] = _make_tool(ToolDefs.Tool.AXE, ToolDefs.Tier.WOOD)
	slots[2] = _make_tool(ToolDefs.Tool.SHOVEL, ToolDefs.Tier.WOOD)
	slots[3] = _make_tool(ToolDefs.Tool.HOE, ToolDefs.Tier.WOOD)
	slots[4] = {"type": "block", "name": "Dirt", "count": 16}
	selected = 0
	changed.emit()

func _make_tool(tool: int, tier: int) -> Dictionary:
	return {"type": "tool", "tool": tool, "tier": tier}

# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func select(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT or index == selected:
		return
	selected = index
	changed.emit()

func cycle(direction: int) -> void:
	selected = wrapi(selected + direction, 0, SLOT_COUNT)
	changed.emit()

func selected_item():
	return slots[selected]

# ---------------------------------------------------------------------------
# Queries used by the world
# ---------------------------------------------------------------------------

func held_tool() -> int:
	var item = selected_item()
	if item != null and String(item.get("type", "")) == "tool":
		return int(item["tool"])
	return ToolDefs.Tool.HAND

func held_tier() -> int:
	var item = selected_item()
	if item != null and String(item.get("type", "")) == "tool":
		return int(item["tier"])
	return ToolDefs.Tier.ANY

# Name of the block in the selected slot, or "" when it is a tool / empty.
func held_block() -> String:
	var item = selected_item()
	if item != null and String(item.get("type", "")) == "block":
		return String(item["name"])
	return ""

func held_display_name() -> String:
	var item = selected_item()
	if item == null:
		return "Hand"
	if String(item.get("type", "")) == "tool":
		return "%s %s" % [ToolDefs.tier_name(int(item["tier"])), ToolDefs.tool_name(int(item["tool"]))]
	return "%s x%d" % [String(item["name"]), int(item["count"])]

# ---------------------------------------------------------------------------
# Mutation
# ---------------------------------------------------------------------------

# Adds block items, merging into existing stacks first and then into empty
# slots.  Anything that does not fit is silently dropped (no world item yet).
func add_block(block_name: String, amount: int) -> void:
	if block_name.is_empty() or block_name == "Air" or amount <= 0:
		return

	var left := amount
	for i in SLOT_COUNT:
		var stack = slots[i]
		if stack == null or String(stack.get("type", "")) != "block":
			continue
		if String(stack["name"]) != block_name or int(stack["count"]) >= MAX_STACK:
			continue
		var put := mini(MAX_STACK - int(stack["count"]), left)
		stack["count"] = int(stack["count"]) + put
		left -= put
		if left <= 0:
			changed.emit()
			return

	for i in SLOT_COUNT:
		if slots[i] != null:
			continue
		var put := mini(MAX_STACK, left)
		slots[i] = {"type": "block", "name": block_name, "count": put}
		left -= put
		if left <= 0:
			break

	changed.emit()

# Removes one item from the selected stack.  Returns false when the selected
# slot is not a block or is empty.
func consume_selected(amount := 1) -> bool:
	var stack = selected_item()
	if stack == null or String(stack.get("type", "")) != "block":
		return false
	if int(stack["count"]) < amount:
		return false

	stack["count"] = int(stack["count"]) - amount
	if int(stack["count"]) <= 0:
		slots[selected] = null
	changed.emit()
	return true

# Cycles the tier of the selected tool (Wood -> Stone -> Iron -> Gold ->
# Diamond -> Netherite).  Returns the new tier, or -1 when no tool is held.
func cycle_tool_tier() -> int:
	var stack = selected_item()
	if stack == null or String(stack.get("type", "")) != "tool":
		return -1

	var current := int(stack["tier"])
	var index := TIER_CYCLE.find(current)
	index = 0 if index < 0 else (index + 1) % TIER_CYCLE.size()
	stack["tier"] = TIER_CYCLE[index]
	changed.emit()
	return int(stack["tier"])
