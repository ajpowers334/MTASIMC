extends Area2D

# Signal to notify when the player lies down or gets up
signal player_lied_down
signal player_got_up

# Track if player is overlapping and lying down
var player_in_area = false
var player_lying = false
var player = null
var original_player_position = Vector2.ZERO
var stress_reduction_rate = 9.0 # per second

signal player_won()

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))
	collision_mask = 2
	pass  # Win UI handling moved to level.gd

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_area = true
		player = body

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_area = false
		player = null

func _process(delta):
	if player_in_area and Input.is_action_just_pressed("interact"):
		# Emit signal if win condition is met
		if player.knowledge >= player.max_knowledge:
			print("[BED] Win condition met, emitting player_won signal")
			emit_signal("player_won")
			return
		if not player_lying:
			# Lie down on bed
			original_player_position = player.global_position
			player.global_position = global_position + Vector2(0, -30) # Adjust Y offset as needed
			player_lying = true
			player.lie_down() # Disable gravity and movement
			emit_signal("player_lied_down")
		else:
			# Get up
			player.global_position = original_player_position
			player_lying = false
			player.get_up() # Re-enable gravity and movement
			emit_signal("player_got_up")

	# Reduce stress while lying down
	if player_lying and player:
		if player.stress > 0.0:
			player.stress -= stress_reduction_rate * delta
			if player.stress < 0.0:
				player.stress = 0.0

# Win UI handling moved to level.gd
