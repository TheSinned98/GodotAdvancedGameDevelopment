extends CanvasLayer

@onready var root: Control = $Root
@onready var map_texture: TextureRect = $Root/MapTexture
@onready var marker: ColorRect = $Root/MapTexture/PlayerMarker
@onready var legend: VBoxContainer = $Root/Legend

var _manager: Node       # der ChunkManager
var _player: Node2D
var _image_size := Vector2.ONE


func setup(manager: Node, player: Node2D) -> void:
	_manager = manager
	_player = player

	var img: Image = manager.world.to_image()
	_image_size = Vector2(img.get_size())
	map_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_texture.texture = ImageTexture.create_from_image(img)
	_build_legend()


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("toggle_map") and event.is_action_pressed("toggle_map"):
		root.visible = not root.visible
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if root.visible and is_instance_valid(_player) and is_instance_valid(_manager):
		_update_marker()


func _update_marker() -> void:
	# Position in Chunk-Einheiten (mit Nachkommastellen, daher Marker läuft flüssig)
	var chunk_pos: Vector2 = _manager.global_to_chunk_position(_player.global_position)

	# Wo liegt das Bild innerhalb des TextureRect? (wegen Keep Aspect)
	var box := map_texture.size
	var px_per_chunk := minf(box.x / _image_size.x, box.y / _image_size.y)
	var offset := (box - _image_size * px_per_chunk) * 0.5

	marker.position = offset + chunk_pos * px_per_chunk - marker.size * 0.5


func _build_legend() -> void:
	for biome_name in WorldData.Biome.keys():
		var biome_id: int = WorldData.Biome[biome_name]

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.color = WorldData.BIOME_COLORS[biome_id]

		var label := Label.new()
		label.text = biome_name.to_lower().capitalize()

		var row := HBoxContainer.new()
		row.add_child(swatch)
		row.add_child(label)
		legend.add_child(row)
