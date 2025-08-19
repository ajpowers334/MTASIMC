extends Node2D

signal game_over()
signal game_won()

func _enter_tree() -> void:
	add_to_group("level")

func _ready() -> void:
	# Connect to bed's win signal if it exists
	var beds = get_tree().get_nodes_in_group("bed")
	for bed in beds:
		if bed.has_signal("player_won"):
			bed.connect("player_won", Callable(self, "_on_player_won"))
			print("[LEVEL] Connected to bed's player_won signal")

func pause_game() -> void:
	print("[LEVEL] game is paused")
	# Only pause the game world, not the UI
	get_tree().call_group("pausable", "set", "process_mode", Node.PROCESS_MODE_DISABLED)

func unpause_game() -> void:
	# Unpause the game world
	get_tree().call_group("pausable", "set", "process_mode", Node.PROCESS_MODE_INHERIT)

func show_game_over() -> void:
	print("[LEVEL] show_game_over() called")
	# Pause the game first to prevent further input/gameplay
	pause_game()
	
	# Load and instantiate the game over scene
	print("[LEVEL] Loading game over scene...")
	var game_over_scene = load("res://Scenes/game_over.tscn")
	if not game_over_scene:
		push_error("Failed to load game over scene")
		return

	print("[LEVEL] Game over scene loaded successfully")
	var game_over_instance = game_over_scene.instantiate()
	print("[LEVEL] Game over instance created:", game_over_instance)
	
	# Create a new CanvasLayer to ensure it's on top
	var canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 100  # High number to ensure it's on top
	
	# Add the CanvasLayer to the scene tree first
	add_child(canvas_layer)
	canvas_layer.add_child(game_over_instance)
	
	print("[LEVEL] Added to CanvasLayer. Parent:", game_over_instance.get_parent())
	
	# Configure the game over instance if it's a Control node
	if game_over_instance is Control:
		print("[LEVEL] Configuring game over UI")
		game_over_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
		
		# Wait one frame for the node to be properly added
		await get_tree().process_frame
		
		# Set size and position
		var viewport_size = get_viewport_rect().size
		game_over_instance.size = viewport_size
		game_over_instance.position = Vector2.ZERO
		game_over_instance.visible = true
		game_over_instance.queue_redraw()
		
		print("[LEVEL] Game over UI configured. Viewport size:", viewport_size, " Visibility:", game_over_instance.visible)

func _on_player_won() -> void:
	print("[LEVEL] Game won! Starting win sequence...")
	emit_signal("game_won")
	
	# Create a CanvasLayer for the win UI
	var win_layer = CanvasLayer.new()
	win_layer.layer = 100  # High number to ensure it's on top
	add_child(win_layer)
	
	# Load and show win scene first
	print("[LEVEL] Loading win scene...")
	var win_scene = load("res://Scenes/win_scene.tscn")
	if win_scene:
		print("[LEVEL] Win scene loaded, instantiating...")
		var win_instance = win_scene.instantiate()
		# Add the win scene to the CanvasLayer
		win_layer.add_child(win_instance)
		print("[LEVEL] Win scene added to CanvasLayer")
		# Make win scene process even when paused
		win_instance.process_mode = Node.PROCESS_MODE_ALWAYS
		# Center the win scene
		win_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
		win_instance.size = get_viewport_rect().size
		# Ensure visible
		win_instance.visible = true
		print("[LEVEL] Win scene positioned, size:", win_instance.size)
	else:
		printerr("[ERROR] Failed to load win scene!")
	
	# Pause the game after setting up the win scene
	print("[LEVEL] Pausing game...")
	pause_game()
	print("[LEVEL] Game paused, win sequence complete")
