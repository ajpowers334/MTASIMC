extends CharacterBody2D

# NPC movement parameters
var speed = 120.0
var gravity = 900.0
var detection_range = 550.0
var shark = null

# Track if NPC is hiding
var is_hiding = false
var original_position = Vector2.ZERO

func _ready():
	add_to_group("npc")
	# Set collision layer to 2 (different from player) and mask to 1 (detect ground)
	collision_layer = 2
	collision_mask = 1
	print("[DEBUG] NPC collision_layer: ", collision_layer, " collision_mask: ", collision_mask)
	# Find the shark in the scene
	shark = get_tree().get_first_node_in_group("shark")

func _physics_process(delta):
	# Apply gravity
	velocity.y += gravity * delta

	# Run away from shark if found and within detection range
	if shark and not is_hiding:
		var distance_to_shark = global_position.distance_to(shark.global_position)
		
		if distance_to_shark < detection_range:
			# Calculate direction away from shark
			var direction = (global_position - shark.global_position).normalized()
			velocity.x = direction.x * speed
		else:
			# Stop moving if shark is too far
			velocity.x = 0

	# Move the NPC
	move_and_slide()

# Called by hiding spot when NPC hides
func hide_in_spot():
	is_hiding = true
	hide()
	add_to_group("hidden")

# Called by hiding spot when NPC unhides
func unhide_from_spot():
	is_hiding = false
	show()
	remove_from_group("hidden")
