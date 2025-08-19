extends Area2D

# Signal to notify when the player hides or unhides
signal player_hid
signal player_unhid

var player_in_area = false
var player_hidden = false
var player = null
var original_player_position = Vector2.ZERO

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))
	# Set collision layer to 4 (hiding spots)
	# Set mask to detect ground (1) and players (2)
	collision_layer = 4
	collision_mask = 1 | 2  # Detect ground and normal players
	# Add to hiding_spot group for easy access
	add_to_group("hiding_spot")

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_area = true
		player = body
		print("[HIDING] Player entered hiding spot area")

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_area = false
		# Don't set player to null here, we need to keep the reference for unhiding
		print("[HIDING] Player exited hiding spot area, but keeping reference")

func unhide_player():
	print("[HIDING] Attempting to unhide player")
	if player_hidden:
		# If we lost the player reference, try to find it again
		if not player:
			var players = get_tree().get_nodes_in_group("player")
			if players.size() > 0:
				player = players[0]
				print("[HIDING] Recovered player reference")
		
		if player:
			print("[HIDING] Unhiding player")
			player_hidden = false
			player.is_hiding = false
			player.global_position = original_player_position
			player.show()
			if player.has_method("unhide_from_spot"):
				player.unhide_from_spot()
			else:
				print("[HIDING] Player does not have unhide_from_spot method")
			emit_signal("player_unhid")
		else:
			print("[HIDING] Cannot find player reference")
	else:
		print("[HIDING] Cannot unhide - player not hidden")

func _process(delta):
	if player_in_area and Input.is_action_just_pressed("interact"):
		if not player_hidden and player:
			# Hide the player
			player_hidden = true
			player.is_hiding = true
			original_player_position = player.global_position
			player.global_position = global_position + Vector2(0, -30) # Adjust as needed
			player.hide() # Makes the player invisible
			if player.has_method("hide_in_spot"):
				player.hide_in_spot()
			print("[HIDING] Player ", player.name, " hidden in ", name)
			emit_signal("player_hid")
		else:
			# Unhide the player
			print("[HIDING] Attempting to unhide from ", name)
			unhide_player()
