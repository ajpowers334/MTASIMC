extends CharacterBody2D

# Debug settings
const DEBUG_PRINT := true
const DEBUG_PRINT_RATE := 1
var _last_debug_print := 0.0

# Shark movement and behavior parameters
var speed := 325.0
var gravity := 900.0
var detection_range := 700.0

# State variables
var player = null
var is_in_patrol_mode := true
var is_in_chase_mode := true
var is_patrolling := false
var player_was_hidden := false
var player_was_seen := false
var last_detection_range_debug := 0
var is_eating := false
var eating_timer := 0.0

# Collision settings
var original_collision_layer := 1
var original_collision_mask := 2
const PLAYER_LAYER := 2

# Patrol and random movement
var patrol_timer := 0.0
var patrol_duration := 3.0
var random_direction := Vector2.ZERO
var random_direction_timer := 0.0
var random_direction_duration := 7.0
var random_movement_speed := 150.0

# Stairs and stuck detection
var is_on_stairs := false
var stairs = null
var stair_climb_speed := 300.0
var leaving_stairs_direction := 0
var stuck_check_timer := 0.0
var stuck_check_interval := 3.0
var last_checked_position := Vector2.ZERO
var is_stuck := false
var unstuck_timer := 0.0
var unstuck_duration := 2.0
var spawn_point := Vector2.ZERO

# Cached groups
var stairs_group := []

func _ready():
	original_collision_layer = 1
	original_collision_mask = 2
	z_index = 1
	collision_layer = original_collision_layer
	collision_mask = original_collision_layer | original_collision_mask
	add_to_group("shark")
	player = get_tree().get_first_node_in_group("player")
	spawn_point = global_position
	if has_node("EatArea"):
		$EatArea.connect("body_entered", Callable(self, "_on_eat_area_body_entered"))
	_generate_new_random_direction()
	stairs_group = get_tree().get_nodes_in_group("stairs")

func _debug_print(message: String, force: bool = false) -> void:
	if not DEBUG_PRINT:
		return
	var now = Time.get_ticks_msec() / 1000.0
	if force or (now - _last_debug_print) > DEBUG_PRINT_RATE:
		print("[SHARK] ", message)
		_last_debug_print = now

func _physics_process(delta):
	var current_time = Time.get_ticks_msec()
	if DEBUG_PRINT and current_time - _last_debug_print > DEBUG_PRINT_RATE * 1000:
		_debug_print("Physics process - is_eating: %s floor: %s pos: %s vel: %s layer: %s mask: %s" % [
			str(is_eating), str(is_on_floor()), str(position), str(velocity), str(collision_layer), str(collision_mask)
		])
		_last_debug_print = current_time

	# Handle eating state as the first logic branch
	if _handle_eating_state(delta):
		move_and_slide()
		return

	_check_stairs()
	if not is_on_stairs:
		velocity.y += gravity * delta
	else:
		velocity.y = 0

	var effective_detection_range = _calculate_detection_range()
	if player:
		var can_see_player = not player.is_in_group("hidden") and global_position.distance_to(player.global_position) < effective_detection_range
		if can_see_player and not player_was_seen:
			_debug_print("Player seen, starting chase")
			player_was_seen = true
			is_in_chase_mode = true
			is_in_patrol_mode = false
			is_patrolling = false
		elif not can_see_player and player_was_seen:
			player_was_seen = false

		var player_hidden = player.is_in_group("hidden")
		if player_hidden and not player_was_hidden:
			_debug_print("Player hidden, switching to patrol mode")
			is_in_patrol_mode = true
			is_in_chase_mode = false
			is_patrolling = false
			player_was_hidden = true
			_patrol(delta)
			move_and_slide()
			return
		elif not player_hidden and player_was_hidden:
			player_was_hidden = false

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
			_chase_player(delta)
		else:
			_patrol(delta)
	else:
		_patrol(delta)

	move_and_slide()

func _handle_eating_state(delta) -> bool:
	if is_eating:
		eating_timer -= delta
		velocity = Vector2.ZERO
		if eating_timer <= 0:
			_debug_print("Eating finished, resetting state")
			is_eating = false
			_restore_collision_after_eating()
			await get_tree().physics_frame
			if is_on_floor():
				velocity.y = 0
				position.y = floor(position.y)
		return true if is_eating or eating_timer > 0 else false
	return false

func _restore_collision_after_eating():
	collision_layer = original_collision_layer if original_collision_layer != 0 else 1
	collision_mask = original_collision_mask if original_collision_mask != 0 else 1
	gravity = 900.0

func _calculate_detection_range():
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
	if detection_debug_state != last_detection_range_debug:
		_debug_print("Detection range changed: %s" % str(effective_detection_range), True)
		last_detection_range_debug = detection_debug_state
	return effective_detection_range

func _check_stairs():
	var stairs_detected = false
	for area in stairs_group:
		if area is Area2D:
			if area.get_overlapping_bodies().has(self):
				stairs = area
				stairs_detected = true
				break
	if is_on_stairs != stairs_detected:
		is_on_stairs = stairs_detected
		_debug_print("Shark %s stairs" % ("entered" if is_on_stairs else "exited"))

func _chase_player(delta):
	if not is_in_chase_mode or not player_was_seen:
		return
	if player.is_in_group("hidden") and player.stress_level < 99:
		is_in_patrol_mode = true
		is_in_chase_mode = false
		_patrol(delta)
		return
	is_in_patrol_mode = false
	var direction = (player.global_position - global_position).normalized()
	if is_on_stairs and stairs:
		if leaving_stairs_direction != 0:
			velocity.x = leaving_stairs_direction * stair_climb_speed
			velocity.y = 0
			_check_stuck(delta)
			return
		var stairs_x = stairs.global_position.x
		var dx = stairs_x - global_position.x
		velocity.x = sign(dx) * min(abs(dx), 1) * stair_climb_speed if abs(dx) > 5 else 0
		var vertical_dist = abs((player.global_position.y - 115) - global_position.y)
		if vertical_dist < 20:
			leaving_stairs_direction = sign(player.global_position.x - global_position.x) or 1
			velocity.x = leaving_stairs_direction * stair_climb_speed
			velocity.y = 0
			_check_stuck(delta)
			return
		velocity.y = -stair_climb_speed if player.global_position.y - 100 < global_position.y else stair_climb_speed
	else:
		velocity.x = direction.x * speed
		if direction.y < -0.3 and is_on_floor():
			velocity.x *= 1.5
			_try_to_find_stairs()

func _patrol(delta):
	if not is_in_patrol_mode:
		return
	if not is_patrolling:
		is_patrolling = true
		patrol_timer = 0.0
		_debug_print("Starting patrol")
	patrol_timer += delta
	random_direction_timer += delta
	if random_direction_timer >= random_direction_duration:
		_generate_new_random_direction()
		random_direction_timer = 0.0
	velocity.x = random_direction.x * random_movement_speed
	if is_on_stairs and abs(random_direction.y) > 0.3:
		velocity.y = random_direction.y * stair_climb_speed * 0.5

func _try_to_find_stairs():
	var nearest_stairs = null
	var nearest_distance = 1000.0
	for area in stairs_group:
		if area is Area2D:
			var distance = global_position.distance_to(area.global_position)
			if distance < nearest_distance and distance < 900:
				nearest_stairs = area
				nearest_distance = distance
	if nearest_stairs:
		var stairs_direction = (nearest_stairs.global_position - global_position).normalized()
		velocity.x = stairs_direction.x * speed * 1.2

func _generate_new_random_direction():
	random_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-0.3, 0.3)).normalized()

func _on_eat_area_body_entered(body):
	_debug_print("_on_eat_area_body_entered with %s (is_eating=%s)" % [body.name, str(is_eating)], true)
	if is_eating:
		return
	if body.is_in_group("hidden"):
		return
	if body.is_in_group("npc"):
		original_collision_layer = collision_layer
		original_collision_mask = collision_mask
		collision_layer = 0
		collision_mask = 0
		body.queue_free()
		is_eating = true
		eating_timer = 4.0
		velocity = Vector2.ZERO
		gravity = 0
		if is_on_floor():
			velocity.y = 0
			position.y = floor(position.y)
	if body.is_in_group("player") and not is_eating:
		var level_node = get_tree().get_first_node_in_group("level")
		if level_node and level_node.has_method("show_game_over"):
			level_node.show_game_over()

func _check_stuck(delta):
	if is_stuck:
		_unstuck_from_stairs(delta)
		return
	stuck_check_timer += delta
	if stuck_check_timer >= stuck_check_interval:
		if global_position.distance_to(last_checked_position) < 2.0:
			_debug_print("Shark detected as stuck. Initiating unstuck routine.")
			is_stuck = true
			unstuck_timer = 0.0
		else:
			last_checked_position = global_position
		stuck_check_timer = 0.0

func _unstuck_from_stairs(delta):
	unstuck_timer += delta
	var direction = (spawn_point - global_position).normalized()
	velocity.x = direction.x * speed
	velocity.y = direction.y * speed
	if unstuck_timer >= unstuck_duration:
		_debug_print("Shark finished unstuck routine. Returning to patrol.")
		is_stuck = false
		unstuck_timer = 0.0
