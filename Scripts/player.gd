extends Node2D

@export var speed := 120.0
@onready var body: CharacterBody2D = $CharacterBody2D

func _ready() -> void:
	body.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	body.velocity = dir * speed
	body.move_and_slide()
