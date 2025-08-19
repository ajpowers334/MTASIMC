extends Control

@onready var start_button = $Panel/VBoxContainer/StartButton
@onready var title_screen = $TitleScreen
@onready var panel = $Panel

func _ready():
	print("[START] Start scene ready")
	
	
	# Set z-indices
	if panel:
		panel.z_index = -1
	if start_button:
		start_button.z_index = 1
	
	# Connect the StartButton's pressed signal
	if start_button:
		if not start_button.pressed.is_connected(_on_start_button_pressed):
			var connect_result = start_button.pressed.connect(_on_start_button_pressed)
			if connect_result == OK:
				print("[START] Start button connected successfully")
	else:
		printerr("[ERROR] StartButton not found!")

func _on_start_button_pressed():
	print("[START] Start button pressed, loading level scene...")
	# Load and change to the level scene
	var level_scene = load("res://Scenes/level.tscn")
	if level_scene:
		print("[START] Level scene loaded, changing scene...")
		get_tree().change_scene_to_packed(level_scene)
	else:
		printerr("[ERROR] Failed to load level scene!")
