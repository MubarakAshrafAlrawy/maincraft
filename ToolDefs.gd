extends RefCounted

# ---------------------------------------------------------------------------
# Tool / material definitions.
#
# Pure data + static helpers, safe to read from worker threads.  BlockDefs
# references these enums, and BlockRegistry uses break_time() to answer
# "how long does this block take with this tool?".
# ---------------------------------------------------------------------------

enum Tool { HAND, PICKAXE, AXE, SHOVEL, SWORD, SHEARS, HOE }
enum Tier { ANY, WOOD, STONE, IRON, GOLD, DIAMOND, NETHERITE }

const TOOL_NAMES := ["Hand", "Pickaxe", "Axe", "Shovel", "Sword", "Shears", "Hoe"]
const TIER_NAMES := ["Any", "Wood", "Stone", "Iron", "Gold", "Diamond", "Netherite"]

# Harvest level of every tier.  Gold is as weak as wood but mines much faster,
# exactly like the vanilla game.
const TIER_RANK := [0, 1, 2, 3, 2, 4, 5]
# Speed multiplier applied when the tool matches the block's preferred tool.
const TIER_SPEED := [1.0, 2.0, 4.0, 6.0, 12.0, 8.0, 9.0]
# Durability of a tool of that tier (0 = hand, never breaks).
const TIER_DURABILITY := [0, 59, 131, 250, 32, 1561, 2031]

static func tool_name(tool: int) -> String:
	if tool < 0 or tool >= TOOL_NAMES.size():
		return "Hand"
	return TOOL_NAMES[tool]

static func tier_name(tier: int) -> String:
	if tier < 0 or tier >= TIER_NAMES.size():
		return "Any"
	return TIER_NAMES[tier]

static func tier_rank(tier: int) -> int:
	if tier < 0 or tier >= TIER_RANK.size():
		return 0
	return TIER_RANK[tier]

static func tier_speed(tier: int) -> float:
	if tier < 0 or tier >= TIER_SPEED.size():
		return 1.0
	return TIER_SPEED[tier]

static func durability(tier: int) -> int:
	if tier < 0 or tier >= TIER_DURABILITY.size():
		return 0
	return TIER_DURABILITY[tier]

# True when the tool is the right kind for the block.  Blocks with Tool.HAND
# can be harvested by anything (and break at hand speed with a wrong tool).
static func is_correct_tool(block_tool: int, tool: int) -> bool:
	return block_tool == Tool.HAND or block_tool == tool

# True when the tool tier is high enough to actually drop the block.
static func can_harvest(block_tier: int, tool_tier: int) -> bool:
	return tier_rank(block_tier) <= tier_rank(tool_tier)

# Seconds needed to break one block.  Wrong tools fall back to hand speed.
static func break_time(hardness: float, block_tool: int, block_tier: int, tool: int, tool_tier: int) -> float:
	if hardness <= 0.0:
		return 0.0
	if not is_correct_tool(block_tool, tool):
		return hardness
	return hardness / tier_speed(tool_tier)
