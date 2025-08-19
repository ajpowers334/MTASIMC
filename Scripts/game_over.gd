extends Control

func _ready():
	print("[GAME_OVER] Game over screen ready")
	# Make sure we're visible and not paused
	self.visible = true
	self.process_mode = Node.PROCESS_MODE_ALWAYS  # Make sure UI is always processed
	print("[GAME_OVER] Visibility set to:", self.visible)
	
	# Connect the RetryButton's pressed signal with a small delay to ensure it's ready
	call_deferred("_connect_retry_button")

func _connect_retry_button():
	# Get the button using the full path
	var retry_button = $Panel/VBoxContainer/RetryButton
	if retry_button:
		print("[GAME_OVER] Found retry button:", retry_button)
		# Disconnect first to avoid multiple connections
		if retry_button.pressed.is_connected(_on_retry_button_pressed):
			retry_button.pressed.disconnect(_on_retry_button_pressed)
		# Connect the signal
		var connect_result = retry_button.pressed.connect(_on_retry_button_pressed)
		if connect_result == OK:
			print("[GAME_OVER] Successfully connected retry button")
	else:
		print("[ERROR] RetryButton not found!")
		print("Available children:", get_children())
		if has_node("Panel"):
			print("Panel children:", $Panel.get_children())

func _on_retry_button_pressed():
	print("[GAME_OVER] Retry button pressed!")
	# Unpause the game by re-enabling all pausable nodes
	get_tree().call_group("pausable", "set", "process_mode", Node.PROCESS_MODE_INHERIT)
	# Reload the current scene
	get_tree().reload_current_scene()

# Make sure to clean up signals when the node is removed
func _exit_tree():
	if has_node("Panel/VBoxContainer/RetryButton"):
		var retry_button = $Panel/VBoxContainer/RetryButton
		if retry_button.pressed.is_connected(_on_retry_button_pressed):
			retry_button.pressed.disconnect(_on_retry_button_pressed)
