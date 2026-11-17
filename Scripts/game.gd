# game.gd
extends Node2D

#@onready var world_map := $MapRoot
#@onready var dungeon_map := $DungeonRoot
@onready var player := $PlayerRoot
@onready var chunk_manager := $ChunkManagerNode
@onready var player_body: CharacterBody2D = $PlayerRoot/CharacterBody2D

func _ready() -> void:
	chunk_manager.player = player_body
	player_body.global_position = chunk_manager.get_spawn_position_global()
	chunk_manager.load_around_now()
	$WorldMapUI.setup(chunk_manager, player_body)
	
	
