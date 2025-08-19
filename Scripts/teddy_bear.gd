extends Area2D

# Signal to notify when the bear is picked up or dropped
signal picked_up
signal dropped

# Track if the player is overlapping
var player_in_area := false
var stress_reduction_rate := 2.5 # per second
var is_carried := false
var carrier = null

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))
	connect("body_exited", Callable(self, "_on_body_exited"))
	collision_mask = 2

func _on_body_entered(body):
	if body.is_in_group("player"):
		player_in_area = true

func _on_body_exited(body):
	if body.is_in_group("player"):
		player_in_area = false

func _process(delta):
	if is_carried and carrier:
		# Automatically reduce stress
		if carrier.stress > 0.0:
			carrier.stress -= stress_reduction_rate * delta
			if carrier.stress < 0.0:
				carrier.stress = 0.0
		# Drop if player starts running
		if Input.is_action_pressed("run"):
			drop()

	# Pickup logic
	if player_in_area and Input.is_action_just_pressed("interact") and not is_carried:
		var player = get_overlapping_player()
		if player:
			# If player is already holding another item, drop it first
			if player.carried_item and player.carried_item != self:
				if player.carried_item.has_method("drop"):
					player.carried_item.drop()
			# Now pick up this item
			is_carried = true
			carrier = player
			carrier.carried_item = self
			carrier.add_child(self)
			self.position = carrier.carried_item_offset
			self.z_index = 10
			emit_signal("picked_up")

func drop():
	if is_carried and carrier:
		is_carried = false
		# Remove from player
		carrier.carried_item = null
		# Store the drop position before removing from parent
		var drop_position = carrier.global_position
		carrier = null
		var root = get_tree().get_root()
		get_parent().remove_child(self)
		root.add_child(self)
		self.global_position = drop_position
		self.visible = true
		emit_signal("dropped")

func get_overlapping_player():
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			return body
	return null
