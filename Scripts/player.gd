extends CharacterBody2D

# Player movement parameters
var speed := 200.0
var run_speed := 350.0
var gravity := 900.0
var stamina := 100.0
var max_stamina := 100.0
var stamina_deplete_rate := 25.0 # per second
var stamina_recharge_rate := 10.0 # per second
var stamina_recharge_cooldown := 3.0 # seconds to wait before recharging
var stamina_cooldown_timer := 0.0
var stamina_bar
var stress := 0.0
var max_stress := 100.0
var stress_increase_rate := 1.0 # per second
var stress_increase_rate_sitting := 8.0 # per second (higher when sitting)
var stress_bar
var knowledge := 0.0
var max_knowledge := 100.0
var knowledge_increase_rate := 3.0 # per second
var knowledge_bar
var carried_item = null
var carried_item_offset := Vector2(64, 0) # Offset in front of the player (increase x or y for better visibility)
var using_item := false
var is_sitting := false
var is_lying := false
var is_hiding := false
var original_gravity := 900.0
var original_collision_layer := 2
var original_collision_mask := 1
var last_collision_debug = {} # Track which NPCs we've already debugged
var on_stairs := false

func _ready():
	# Set z-index for proper layering
	z_index = 1
	# Add player to 'player' group for item detection
	add_to_group("player")
	# Set collision layer to 2 and mask to 1 (detect ground, ignore NPCs on layer 2)
	collision_layer = 2
	collision_mask = 1
	print("[DEBUG] Player collision_layer: ", collision_layer, " collision_mask: ", collision_mask)
	# Find the UI bars in the scene tree
	stamina_bar = get_node_or_null("Camera2D/StaminaUI/StaminaBar")
	stress_bar = get_node_or_null("Camera2D/StressUI/StressBar")
	knowledge_bar = get_node_or_null("Camera2D/KnowledgeUI/KnowledgeBar")

func _update_hidden_state():
	if is_hiding:
		if not is_in_group("hidden"):
			add_to_group("hidden")
		# Set layer to 0 to avoid all collisions with other objects
		# Set mask to 4 to detect hiding spots (layer 4)
		collision_layer = 0
		collision_mask = 4
		velocity = Vector2.ZERO
		gravity = 0.0
	else:
		if is_in_group("hidden"):
			remove_from_group("hidden")
		collision_layer = original_collision_layer  # Layer 2
		collision_mask = original_collision_mask    # Mask 1
		gravity = original_gravity

func _physics_process(delta):
	# Check for interact input when hidden
	if is_hiding and Input.is_action_just_pressed("interact"):
		print("[DEBUG] Interact pressed while hidden")
		# Try to find the hiding spot we're currently in
		var areas = get_tree().get_nodes_in_group("hiding_spot")
		print("[DEBUG] Found ", areas.size(), " hiding spots")
		var unhidden = false
		
		for area in areas:
			print("[DEBUG] Checking area: ", area.name)
			# Check if this hiding spot has this player hidden
			if area.get("player_hidden") == true and area.get("player") == self:
				print("[DEBUG] Found hiding spot with this player hidden, calling unhide")
				area.unhide_player()
				unhidden = true
				break
			
		if not unhidden:
			print("[DEBUG] Couldn't find the hiding spot with this player hidden, trying any")
			# Fallback: if we couldn't find the exact hiding spot, try any of them
			for area in areas:
				if area.has_method("unhide_player"):
					print("[DEBUG] Fallback: Calling unhide_player on ", area.name)
					area.unhide_player()
					break
	
	# Update hidden state based on current hiding status
	_update_hidden_state()
	
	# Handle stair climbing
	if on_stairs:
		# Disable gravity and allow vertical movement
		velocity.y = 0
		var climb_speed = run_speed if (Input.is_action_pressed("run") and stamina > 0.0) else speed
		if Input.is_action_pressed("up"):
			velocity.y = -climb_speed
			if climb_speed == run_speed:
				stamina -= stamina_deplete_rate * delta
		elif Input.is_action_pressed("down"):
			velocity.y = climb_speed
			if climb_speed == run_speed:
				stamina -= stamina_deplete_rate * delta
	else:
		# Apply gravity only if not sitting, lying, or hiding
		if not is_sitting and not is_lying and not is_hiding:
			velocity.y += gravity * delta

	# Handle using carried item (only if not sitting, lying, or hiding)
	using_item = false
	if carried_item and Input.is_action_pressed("use") and not is_sitting and not is_lying: # and not is_hidin - i want the player to use items while hiding
		using_item = true
		if carried_item.has_method("use_item"):
			carried_item.use_item(self, delta)

	# Prevent movement if using an item, sitting, lying, or hiding
	if using_item or is_sitting or is_lying or is_hiding:
		velocity.x = 0
	else:
		# Handle left/right movement
		var input_direction = 0
		if Input.is_action_pressed("move_left"):
			input_direction -= 1
		if Input.is_action_pressed("move_right"):
			input_direction += 1

		var can_run = stamina > 0.0
		var running = false
		var current_speed = speed
		if Input.is_action_pressed("run") and can_run and input_direction != 0:
			current_speed = run_speed
			running = true

		velocity.x = input_direction * current_speed

		# Stamina logic
		if running:
			stamina -= stamina_deplete_rate * delta
			if stamina < 0.0:
				stamina = 0.0
				stamina_cooldown_timer = stamina_recharge_cooldown # Start cooldown
		else:
			# Only recharge if cooldown is finished
			if stamina_cooldown_timer <= 0.0:
				stamina += stamina_recharge_rate * delta
				if stamina > max_stamina:
					stamina = max_stamina
			else:
				stamina_cooldown_timer -= delta

	# Update the stamina bar UI if it exists
	if stamina_bar:
		stamina_bar.value = stamina

	# Stress logic - different rates based on sitting state
	if is_sitting:
		stress += stress_increase_rate_sitting * delta
	else:
		stress += stress_increase_rate * delta
	
	if stress > max_stress:
		stress = max_stress

	# Update the stress bar UI if it exists
	if stress_bar:
		stress_bar.value = stress

	# Knowledge logic - only increases while sitting
	if is_sitting:
		knowledge += knowledge_increase_rate * delta
		if knowledge > max_knowledge:
			knowledge = max_knowledge

	# Update the knowledge bar UI if it exists
	if knowledge_bar:
		knowledge_bar.value = knowledge

	# Handle item pickup
	if Input.is_action_just_pressed("interact") and carried_item == null:
		print("[DEBUG] Interact pressed, checking for items to pick up...")
		var overlapping_areas = get_overlapping_areas()
		print("[DEBUG] Overlapping areas found: ", overlapping_areas)
		for area in overlapping_areas:
			if area.has_signal("picked_up") and area.visible:
				print("[DEBUG] Picking up item: ", area)
				# Ensure the item is visible and parented to the player
				carried_item = area
				add_child(carried_item)
				carried_item.visible = true
				carried_item.position = carried_item_offset
				carried_item.z_index = 10 # Draw in front of player
				print("[DEBUG] Carried item after pickup: ", carried_item)
				break

	# If carrying an item, keep it in front of the player
	if carried_item:
		carried_item.position = carried_item_offset
		carried_item.z_index = 10 # Keep in front of player

	# Move the player
	move_and_slide()
	
	# Debug: Check for collisions with NPCs only
	var collision_count = get_slide_collision_count()
	if collision_count > 0:
		for i in range(collision_count):
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			if collider and collider.is_in_group("npc"):
				var npc_id = str(collider.get_instance_id())
				if not last_collision_debug.has(npc_id):
					print("[DEBUG] Player collided with NPC: ", collider, " groups: ", collider.get_groups())
					last_collision_debug[npc_id] = true

# Helper to get all overlapping Area2D nodes
func get_overlapping_areas():
	var result = []
	for area in get_tree().get_nodes_in_group("pickup_item"):
		if area is Area2D and area.visible and area.get_overlapping_bodies().has(self):
			print("[DEBUG] Overlapping with item: ", area)
			result.append(area)
	return result

# Called by desk when player sits
func sit_down():
	is_sitting = true
	gravity = 0.0
	velocity = Vector2.ZERO

# Called by desk when player stands
func stand_up():
	is_sitting = false
	gravity = original_gravity

# Called by bed when player lies down
func lie_down():
	is_lying = true
	gravity = 0.0
	velocity = Vector2.ZERO

# Called by bed when player gets up
func get_up():
	is_lying = false
	gravity = original_gravity

# Called by hiding spot when player hides
func hide_in_spot():
	if not is_hiding:
		is_hiding = true
		_update_hidden_state()

# Called by hiding spot when player unhides
func unhide_from_spot():
	if is_hiding:
		is_hiding = false
		_update_hidden_state()

func enter_stairs():
	on_stairs = true
	gravity = 0.0
	velocity.y = 0

func exit_stairs():
	on_stairs = false
	gravity = original_gravity
