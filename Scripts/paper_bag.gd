extends Area2D

# Signal to notify when the bag is picked up
signal picked_up

# Track if the player is overlapping
var player_in_area := false
var stress_reduction_rate := 6.0 # per second
var is_carried = false
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
			self.visible = true
			emit_signal("picked_up")

# Called by the player when using the item
func use_item(player, delta):
	if player.stress > 0.0:
		player.stress -= stress_reduction_rate * delta
		if player.stress < 0.0:
			player.stress = 0.0

func get_overlapping_player():
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			return body
	return null

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
