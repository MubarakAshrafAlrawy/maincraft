extends RefCounted

# ---------------------------------------------------------------------------
# DEPRECATED compatibility shim.
#
# Block definitions now live in content/<pack>/blocks.json and are loaded by
# ContentLoader.gd.  This file only keeps the flag/tool constants that older
# scripts may still import; there is no block table here anymore.
# ---------------------------------------------------------------------------

const ToolDefs = preload("res://ToolDefs.gd")

enum Flags {
	TRANSPARENT = 1,
	PASSABLE = 2,
	FLAT = 4,
	LIQUID = 8,
	REPLACEABLE = 16,
}

const FLAG_TRANSPARENT := Flags.TRANSPARENT
const FLAG_NO_COLLISION := Flags.PASSABLE
const FLAG_FLAT := Flags.FLAT
const FLAG_LIQUID := Flags.LIQUID
const FLAG_REPLACEABLE := Flags.REPLACEABLE
const FLAG_PASSABLE := Flags.PASSABLE

const HAND := ToolDefs.Tool.HAND
const PICKAXE := ToolDefs.Tool.PICKAXE
const AXE := ToolDefs.Tool.AXE
const SHOVEL := ToolDefs.Tool.SHOVEL
const SWORD := ToolDefs.Tool.SWORD
const SHEARS := ToolDefs.Tool.SHEARS
const HOE := ToolDefs.Tool.HOE

const ANY := ToolDefs.Tier.ANY
const WOOD := ToolDefs.Tier.WOOD
const STONE := ToolDefs.Tier.STONE
const IRON := ToolDefs.Tier.IRON
const GOLD := ToolDefs.Tier.GOLD
const DIAMOND := ToolDefs.Tier.DIAMOND
const NETHERITE := ToolDefs.Tier.NETHERITE
