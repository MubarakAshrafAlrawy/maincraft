extends CharacterBody3D

const Registry = preload("res://BlockRegistry.gd")
const Inventory = preload("res://Inventory.gd")

@onready var camera = $CameraBase/Camera3D
@onready var camera_base = $CameraBase
@onready var raycast = $CameraBase/Camera3D/RayCast3D
@onready var cube_outline = $CameraBase/Camera3D/Sprite2D
@onready var info_label = $CameraBase/Camera3D/Label
@onready var hud = $CanvasLayer/Hud

var inventory = Inventory.new()
var camera_x_rotation = 0
var _info_update_timer := 0.0
var _mining := false

const SPEED = 5
const gravity = 9.8
var jump_vel = 5

signal place_block(pos, norm)
signal mine_block(pos, norm)
signal mine_stop()
signal highlight_block(pos, norm)
signal unhighlight_block()

# Called when the node enters the scene tree for the first time.
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Never let the ray hit the player's own capsule; otherwise looking down at
	# a block trapped inside the body reports the player instead of the block.
	raycast.add_exception(self)
	raycast.hit_from_inside = true

	inventory.setup_default()
	hud.setup(inventory)
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	_update_info_label()

func _apply_settings() -> void:
	if camera != null:
		camera.fov = float(Settings.fov)

func _input(event):
	# Mouse movement
	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * Settings.mouse_sensitivity))

		var x_delta = event.relative.y * Settings.mouse_sensitivity
		if camera_x_rotation + x_delta > -90 and camera_x_rotation + x_delta < 90:
			camera.rotate_x(deg_to_rad(-x_delta))
			camera_x_rotation += x_delta
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_hotbar_key(event.keycode)

# 1-9 select a hotbar slot; T cycles the held tool's tier (testing aid until
# crafting exists).
func _handle_hotbar_key(keycode: int) -> void:
	if keycode >= KEY_1 and keycode <= KEY_9:
		inventory.select(keycode - KEY_1)
	elif keycode == KEY_T:
		inventory.cycle_tool_tier()
	_update_info_label()

func _physics_process(delta):
	_info_update_timer -= delta
	if _info_update_timer <= 0.0:
		_info_update_timer = 0.25
		_update_info_label()

	# Check the raycast
	if raycast.is_colliding():
		var pos = raycast.get_collision_point()
		var norm = raycast.get_collision_normal()
		emit_signal("highlight_block", pos, norm)

		# Holding the button keeps mining; WorldScript accumulates progress.
		if Input.is_action_pressed("click"):
			emit_signal("mine_block", pos, norm)
			_mining = true
		elif _mining:
			emit_signal("mine_stop")
			_mining = false

		if Input.is_action_just_pressed("right_click"):
			emit_signal("place_block", pos, norm)
	else:
		emit_signal("unhighlight_block")
		if _mining:
			emit_signal("mine_stop")
			_mining = false

	# Scroll to change the selected hotbar slot
	if Input.is_action_just_released("scroll_up"):
		inventory.cycle(-1)
		_update_info_label()
	elif Input.is_action_just_released("scroll_down"):
		inventory.cycle(1)
		_update_info_label()

	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_vel

	# Get direction and handle movement/deceleration
	var camera_base_basis = get_global_transform().basis
	var direction = Vector3.ZERO

	if Input.is_action_pressed("forward"):
		direction -= camera_base_basis.z # forward is negative in Godot
	if Input.is_action_pressed("backward"):
		direction += camera_base_basis.z

	# Strafe
	if Input.is_action_pressed("left"):
		direction -= camera_base_basis.x
	if Input.is_action_pressed("right"):
		direction += camera_base_basis.x

	direction = direction.normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	# Godot 4 standard movement function
	move_and_slide()

func _update_info_label() -> void:
	if info_label == null:
		return

	var cx = floor(position.x / Registry.DIMENSION.x)
	var cz = floor(position.z / Registry.DIMENSION.z)
	var px = position.x - cx * Registry.DIMENSION.x
	var py = position.y
	var pz = position.z - cz * Registry.DIMENSION.z
	info_label.text = "%s | Chunk (%d, %d) pos (%.0f, %.0f, %.0f)" % [
		inventory.held_display_name(), cx, cz, px, py, pz
	]

# ---------------------------------------------------------------------------
# World-facing queries
# ---------------------------------------------------------------------------

func get_held_tool() -> int:
	return inventory.held_tool()

func get_held_tier() -> int:
	return inventory.held_tier()

func get_held_block() -> String:
	return inventory.held_block()

func set_mining_progress(fraction: float) -> void:
	if hud != null:
		hud.set_mining_progress(fraction)
