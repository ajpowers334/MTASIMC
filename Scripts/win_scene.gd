extends Control

@onready var main_menu_button = $VBoxContainer/MainMenuButton

func _ready():
	print("[WIN SCENE] Win scene ready!")
	if main_menu_button:
		print("[WIN SCENE] Connecting main menu button...")
		main_menu_button.pressed.connect(_on_main_menu_pressed)
	else:
		printerr("[WIN SCENE] Error: Main menu button not found!")

func _on_main_menu_pressed():
	print("[WIN SCENE] Main menu button pressed, changing scene...")
	get_tree().paused = false  # Make sure to unpause when changing scenes
	get_tree().change_scene_to_file("res://Scenes/start_scene.tscn")
