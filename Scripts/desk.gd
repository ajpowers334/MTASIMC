extends Area2D

# Signal to notify when the player sits or stands
signal player_sat
signal player_stood

# Track if player is overlapping and sitting
var player_in_area := false
var player_sitting := false
var player = null
var original_player_position = Vector2.ZERO

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))
	collision_mask = 2

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
		if not player_sitting:
			# Sit on desk
			original_player_position = player.global_position
			player.global_position = global_position + Vector2(0, -50) # Adjust Y offset as needed
			player_sitting = true
			player.sit_down() # Disable gravity and movement
			emit_signal("player_sat")
		else:
			# Stand up
			player.global_position = original_player_position
			player_sitting = false
			player.stand_up() # Re-enable gravity and movement
			emit_signal("player_stood")
