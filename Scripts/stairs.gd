extends Area2D

func _ready():
	collision_layer = 1
	collision_mask = 1 | 2  # Detect both shark (layer 1) and player (layer 2)
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))

func _on_body_entered(body):
	if body.is_in_group("player"):
		body.enter_stairs()

func _on_body_exited(body):
	if body.is_in_group("player"):
		body.exit_stairs()
