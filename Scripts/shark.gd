extends CharacterBody2D

# Debug settings
const DEBUG_PRINT := true  # Set to false to disable all debug prints
const DEBUG_PRINT_RATE := 1  # Seconds between debug prints
var _last_debug_print := 0.0

# Shark movement parameters
var speed := 325.0
var gravity := 900.0

# Shark behavior states
var is_in_patrol_mode := true
var is_in_chase_mode := true
var detection_range := 700.0
var player = null

# Stuck detection variables
var stuck_check_timer := 0.0
var stuck_check_interval := 3.0
var last_checked_position := Vector2.ZERO
var is_stuck := false
var unstuck_timer := 0.0
var unstuck_duration := 2.0
var spawn_point := Vector2.ZERO

# Patrol state
var is_patrolling := false
var patrol_timer := 0.0
var patrol_duration := 3.0  # How long to patrol before checking player again
var patrol_wait_time := 2.0

# Track if player was previously hidden
var player_was_hidden := false
# Track if shark previously saw the player
var player_was_seen := false
# Track last detection range debug state
var last_detection_range_debug := 0

# Eating state variables
var is_eating := false
var eating_timer := 0.0
# Collision settings
var original_collision_layer := 1
var original_collision_mask := 2
# Store player's collision layer to avoid hardcoding
const PLAYER_LAYER := 2

# Random movement variables
var random_direction := Vector2.ZERO
var random_direction_timer := 0.0
var random_direction_duration := 7.0 # Increased from 3.0 for longer movement
var random_movement_speed := 150.0

# Stair climbing variables
var is_on_stairs := false
var stairs = null
var stair_climb_speed := 300.0
# Leaving stairs state
var leaving_stairs_direction := 0

func _ready():
	# Initialize collision settings
	original_collision_layer = 1
	original_collision_mask = 2
	z_index = 1
	collision_layer = original_collision_layer
	collision_mask = original_collision_layer | original_collision_mask  # Combine layers 1 and 2
	
	#collision_layer = 1
	#collision_mask = 1 | 2  # Detect both layer 1 and layer 2
	
	# Add shark to 'shark' group for NPC detection
	add_to_group("shark")
	# Find the player in the scene
	player = get_tree().get_first_node_in_group("player")
	# Save spawn point
	spawn_point = global_position
	# Connect to EatArea's body_entered signal for lose logic
	if has_node("EatArea"):
		$EatArea.connect("body_entered", Callable(self, "_on_eat_area_body_entered"))

	# Initialize random movement
	_generate_new_random_direction()

func _debug_print(message: String, force: bool = false) -> void:
	if not DEBUG_PRINT:
		return
	var now = Time.get_ticks_msec() / 1000.0
	if force or (now - _last_debug_print) > DEBUG_PRINT_RATE:
		print("[SHARK] ", message)
		_last_debug_print = now

func _physics_process(delta):
	# Debug print for physics process (rate limited)
	var current_time = Time.get_ticks_msec()
	if DEBUG_PRINT and current_time - _last_debug_print > DEBUG_PRINT_RATE * 1000:
		_debug_print("Physics process - is_eating: " + str(is_eating) + 
			" floor: " + str(is_on_floor()) + 
			" pos: " + str(position) + 
			" vel: " + str(velocity) + 
			" layer: " + str(collision_layer) + 
			" mask: " + str(collision_mask))
		_last_debug_print = current_time

	# Handle eating state
	if is_eating:
		eating_timer -= delta
		# Keep velocity at zero while eating
		velocity = Vector2.ZERO
		
		if eating_timer <= 0:
			_debug_print("Eating finished, resetting state")
			is_eating = false
			# Restore collision before moving
			collision_layer = original_collision_layer if original_collision_layer != 0 else 1
			collision_mask = original_collision_mask if original_collision_mask != 0 else 1
			# Re-enable gravity
			gravity = 900.0
			# Wait for physics frame to ensure collision updates
			await get_tree().physics_frame
			# Ensure we're on the ground after eating
			if is_on_floor():
				velocity.y = 0
				position.y = floor(position.y)
		# Don't process any other movement while eating
		move_and_slide()
		return
	
	# Update collision if eating state changed
	var was_eating = is_eating
	if is_eating:
		eating_timer -= delta
		_debug_print("Eating timer: " + str(eating_timer) + "s remaining")
		if eating_timer <= 0 and is_eating:  # Double check is_eating in case it was changed elsewhere
			_debug_print("Eating finished, resetting state", true)
			is_eating = false
			# Update collision immediately
			_update_collision_for_eating()
			# Force a physics update
			await get_tree().physics_frame
			# Ensure we're on the ground if we should be
			if is_on_floor():
				velocity.y = 0
				position.y = floor(position.y)  # Snap to pixel grid
				_debug_print("On floor, position snapped")
			return  # Skip the rest of physics processing this frame
	
	# Update collision if eating state changed
	if was_eating and not is_eating:
		_debug_print("Eating state changed from true to false", true)
		# We already handled this case above
	elif not was_eating and is_eating:
		_debug_print("Eating state changed from false to true", true)
		_update_collision_for_eating()
	
	# Handle eating pause
	if is_eating:
		_debug_print("Currently eating - freezing movement")
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Check for stairs
	_check_stairs()
	
	# Apply gravity only when not on stairs
	if not is_on_stairs:
		velocity.y += gravity * delta
	else:
		velocity.y = 0  # No gravity on stairs
	
	# Adjust detection range based on player stress
	var effective_detection_range = detection_range
	var detection_debug_state = 0
	if player:
		if player.stress >= 99.0:
			effective_detection_range += 2400.0
			detection_debug_state = 3
		elif player.stress >= 67.0:
			effective_detection_range += 800.0
			detection_debug_state = 2
		elif player.stress >= 34.0:
			effective_detection_range += 400.0
			detection_debug_state = 1
	# Print debug only when the detection range state changes
	if detection_debug_state != last_detection_range_debug:
		if detection_debug_state == 3:
			print("[DEBUG] Shark detection range increased by 2400 from base (stress >= 99)")
		elif detection_debug_state == 2:
			print("[DEBUG] Shark detection range increased by 800 from base (stress >= 67)")
		elif detection_debug_state == 1:
			print("[DEBUG] Shark detection range increased by 400 from base (stress >= 34)")
		last_detection_range_debug = detection_debug_state
	
	# Handle movement based on current state
	if player:
		# Only print when shark first sees or loses sight of the player
		var can_see_player = not player.is_in_group("hidden") and global_position.distance_to(player.global_position) < effective_detection_range
		if can_see_player and not player_was_seen:
			print("[SHARK] Player was seen, starting chase")
			player_was_seen = true
			is_in_chase_mode = true
			is_in_patrol_mode = false
			is_patrolling = false
		elif not can_see_player and player_was_seen:
			player_was_seen = false
		# Update player hidden state
		var player_hidden = player.is_in_group("hidden")
		
		# If player just became hidden, switch to patrol mode
		if player_hidden and not player_was_hidden:
			print("[SHARK] Player hidden, switching to patrol mode")
			is_in_patrol_mode = true
			is_in_chase_mode = false
			is_patrolling = false  # Reset patrolling state to trigger new patrol behavior
			player_was_hidden = true
			_patrol(delta)
			move_and_slide()
			return
		elif not player_hidden and player_was_hidden:
			player_was_hidden = false
			
		# If player is hidden, only patrol
		if player_hidden:
			if not is_in_patrol_mode:
				is_in_patrol_mode = true
				is_in_chase_mode = false
				is_patrolling = false
			_patrol(delta)
			move_and_slide()
			return
		var distance_to_player = global_position.distance_to(player.global_position)
		
		if distance_to_player < effective_detection_range and not player.is_in_group("hidden"):
			# Player detected - chase mode
			_chase_player(delta)
		else:
			# Patrol mode
			_patrol(delta)
	else:
		# No player found - just patrol
		_patrol(delta)
	
	# Move the shark
	move_and_slide()

func _check_stairs():
	# Check if shark is overlapping with stairs using a similar approach to the player
	var stairs_detected = false
	var stairs_group = get_tree().get_nodes_in_group("stairs")
	
	for area in stairs_group:
		if area is Area2D:
			var overlapping_bodies = area.get_overlapping_bodies()
			if overlapping_bodies.has(self):
				stairs = area
				stairs_detected = true
				break
	
	if is_on_stairs != stairs_detected:
		is_on_stairs = stairs_detected
		if is_on_stairs:
			print("[SHARK] Shark entered stairs")
		else:
			print("[SHARK] Shark exited stairs")
			leaving_stairs_direction = 0  # Reset leaving stairs state
			# Don't reset climbing state when exiting stairs - let it complete the climb

func _chase_player(delta):
	# Only chase if in chase mode and has seen the player
	if not is_in_chase_mode or not player_was_seen:
		return
		
	if player.is_in_group("hidden") and player.stress_level < 99:
		# Switch to patrol mode
		is_in_patrol_mode = true
		is_in_chase_mode = false
		_patrol(delta)
		return
		
	# Reset patrol mode when chasing player
	is_in_patrol_mode = false
	# Only update last_player_position if player is not hidden
	if not player.is_in_group("hidden"):
		var last_player_position = player.global_position
	# Calculate direction to player
	var direction = (player.global_position - global_position).normalized()
	
	if is_on_stairs and stairs:
		# If we're in the process of leaving stairs, move horizontally only
		if leaving_stairs_direction != 0:
			velocity.x = leaving_stairs_direction * stair_climb_speed
			velocity.y = 0
			# Stuck detection logic
			_check_stuck(delta)
			return
		# Center horizontally on the stairs
		var stairs_x = stairs.global_position.x
		var dx = stairs_x - global_position.x
		if abs(dx) > 5:
			# Move horizontally toward the center of the stairs
			velocity.x = sign(dx) * min(abs(dx), 1) * stair_climb_speed
		else:
			velocity.x = 0  # Already centered
		
		# Move vertically toward the player
		var vertical_dist = abs((player.global_position.y - 115) - global_position.y)
		if vertical_dist < 20:
			# Close enough vertically, pick a direction to leave stairs
			leaving_stairs_direction = sign(player.global_position.x - global_position.x)
			if leaving_stairs_direction == 0:
				leaving_stairs_direction = 1  # Default to right if exactly aligned
			velocity.x = leaving_stairs_direction * stair_climb_speed
			velocity.y = 0
			# Stuck detection logic
			_check_stuck(delta)
			return
		if player.global_position.y - 100 < global_position.y:
			velocity.y = -stair_climb_speed  # Climb up
		else:
			velocity.y = stair_climb_speed  # Climb down
			print("[DEBUG] Shark climbing down stairs towards player")
	else:
		# Normal horizontal movement
		velocity.x = direction.x * speed
		# If player is above and we're not on stairs, try to find stairs
		if direction.y < -0.3 and is_on_floor():
			velocity.x *= 1.5  # Move faster when trying to reach player above
			# Try to find and climb stairs
			_try_to_find_stairs()


func _patrol(delta):
	if not is_in_patrol_mode:
		return
		
	if not is_patrolling:
		is_patrolling = true
		patrol_timer = 0.0
		print("[SHARK] Starting patrol")
	patrol_timer += delta
	
	# Update random direction timer
	random_direction_timer += delta
	
	# Generate new random direction when timer expires
	if random_direction_timer >= random_direction_duration:
		_generate_new_random_direction()
		random_direction_timer = 0.0
	
	# Move in random direction
	velocity.x = random_direction.x * random_movement_speed
	
	# Allow vertical movement on stairs during patrol
	if is_on_stairs and abs(random_direction.y) > 0.3:
		velocity.y = random_direction.y * stair_climb_speed * 0.5

func _try_to_find_stairs():
	# Look for stairs nearby and try to climb them
	var nearest_stairs = null
	var nearest_distance = 1000.0
	
	# Debug: Check what's in the stairs group
	var stairs_group = get_tree().get_nodes_in_group("stairs")
	# for i in range(stairs_group.size()):
	# 	var node = stairs_group[i]
	
	for area in stairs_group:
		if area is Area2D:
			var distance = global_position.distance_to(area.global_position)
			if distance < nearest_distance and distance < 900:  # Within 900 pixels
				nearest_stairs = area
				nearest_distance = distance
	
	if nearest_stairs:
		# Move towards the stairs
		var stairs_direction = (nearest_stairs.global_position - global_position).normalized()
		velocity.x = stairs_direction.x * speed * 1.2  # Move towards stairs
	else:
		pass

func _generate_new_random_direction():
	# Generate a random direction for patrol movement
	random_direction = Vector2(
		randf_range(-1.0, 1.0),  # Random X direction
		randf_range(-0.3, 0.3)   # Slight vertical component for stairs
	).normalized()

func _on_player_lost():
	# Called when player goes out of detection range or hides
	if player and player.is_in_group("hidden"):
		print("[SHARK] Player is lost")


func _update_collision_for_eating():
	_debug_print("_update_collision_for_eating() called with is_eating=" + str(is_eating), true)
	_debug_print("Current collision - layer: " + str(collision_layer) + " mask: " + str(collision_mask) + " gravity: " + str(gravity))
	
	if is_eating:
		_debug_print("Setting up eating collision...")
		# Store original values if not already stored
		if original_collision_layer == 0 or original_collision_mask == 0:
			original_collision_layer = collision_layer
			original_collision_mask = collision_mask
		
		# Set collision layer to 0 to prevent all collisions while eating
		# This is more reliable than trying to modify the mask
		collision_layer = 0
		collision_mask = 0
		
		# Disable gravity while eating
		velocity = Vector2.ZERO
		gravity = 0
		
		# Make sure we're on the ground before stopping
		if is_on_floor():
			velocity.y = 0
			position.y = floor(position.y)
		
		_debug_print("""Eating collision set:
		- Layer: 0 (no collisions)
		- Mask: 0 (no detections)
		- Gravity: 0 (disabled)
		- Position: """ + str(position) + """
		- On floor: """ + str(is_on_floor()))
	else:
		_debug_print("Restoring normal collision...")
		# Make sure we have valid original values
		if original_collision_layer == 0 or original_collision_mask == 0:
			original_collision_layer = 1  # Default layer
			original_collision_mask = 1   # Default mask
		
		# Restore original collision settings
		collision_layer = original_collision_layer
		collision_mask = original_collision_mask
		
		# Always re-enable gravity when done eating
		gravity = 900.0
		velocity = Vector2.ZERO  # Reset velocity to prevent sliding
		
		# Force position to be on ground if we were on floor before
		if is_on_floor():
			velocity.y = 0
			position.y = floor(position.y)  # Snap to pixel grid
		
		_debug_print("""Normal collision restored:
		- Layer: """ + str(collision_layer) + """ (restored)
		- Mask: """ + str(collision_mask) + """ (restored)
		- Gravity: """ + str(gravity) + """ (enabled)
		- On floor: """ + str(is_on_floor()) + """
		- Position: """ + str(position))

# Called when the player enters the EatArea
func _on_eat_area_body_entered(body):
	_debug_print("_on_eat_area_body_entered with " + body.name + " (is_eating=" + str(is_eating) + ")", true)
	_debug_print("Body groups: " + str(body.get_groups()))
	
	if is_eating:
		_debug_print("Already eating, ignoring new body")
		return

	if body.is_in_group("hidden"):
		return

	if body.is_in_group("npc"):
		_debug_print("NPC detected, starting to eat")
		# Store current collision state
		original_collision_layer = collision_layer
		original_collision_mask = collision_mask
		
		# Immediately disable all collisions
		collision_layer = 0
		collision_mask = 0
		
		# Start eating
		body.queue_free()
		is_eating = true
		eating_timer = 4.0  # 4 seconds of eating animation
		velocity = Vector2.ZERO
		gravity = 0
		
		# Make sure we're on the ground
		if is_on_floor():
			velocity.y = 0
			position.y = floor(position.y)

	if body.is_in_group("player") and not is_eating:
		_debug_print("Player detected in eat area!")
		var level_node = get_tree().get_first_node_in_group("level")
		if level_node and level_node.has_method("show_game_over"):
			level_node.show_game_over()


# Stuck detection logic
func _check_stuck(delta):
	if is_stuck:
		_unstuck_from_stairs(delta)
		return
	stuck_check_timer += delta
	if stuck_check_timer >= stuck_check_interval:
		if global_position.distance_to(last_checked_position) < 2.0:
			print("[DEBUG] Shark detected as stuck. Initiating unstuck routine.")
			is_stuck = true
			unstuck_timer = 0.0
		else:
			last_checked_position = global_position
		stuck_check_timer = 0.0

func _unstuck_from_stairs(delta):
	unstuck_timer += delta
	# Move toward spawn point for 2 seconds
	var direction = (spawn_point - global_position).normalized()
	velocity.x = direction.x * speed
	velocity.y = direction.y * speed
	if unstuck_timer >= unstuck_duration:
		print("[DEBUG] Shark finished unstuck routine. Returning to patrol.")
		is_stuck = false
		unstuck_timer = 0.0
		# Resume normal behavior
