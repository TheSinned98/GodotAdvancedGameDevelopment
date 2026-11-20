extends Node2D

@onready var player := $PlayerRoot
@onready var chunk_manager := $ChunkManagerNode
@onready var player_body: CharacterBody2D = $PlayerRoot/CharacterBody2D

func _ready() -> void:
	player.set_physics_process(false)
	chunk_manager.player = player_body
	var spawn_pos: Vector2 = chunk_manager.get_spawn_position_global()
	player_body.global_position = spawn_pos
	$WorldMapUI.setup(chunk_manager, player_body)

	while not chunk_manager.is_chunk_loaded_at(spawn_pos):
		await chunk_manager.chunk_loaded

	# Wasserkoerper und Deko-Kollisionen erst in der Physikwelt wirksam werden lassen.
	await get_tree().physics_frame
	player.set_physics_process(true)
