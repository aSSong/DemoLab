extends Node2D

const PLAYER_SCENE = preload("res://Scenes/player.tscn")

@onready var players_node: Node2D = $Players


func _ready() -> void:
	# 收集所有已连接的 peer ID（包括自己）
	var peer_ids: Array[int] = []
	peer_ids.append(multiplayer.get_unique_id())
	for id in multiplayer.get_peers():
		peer_ids.append(id)
	peer_ids.sort()

	# 为每个玩家创建实例
	for i in peer_ids.size():
		_add_player(peer_ids[i], i)


func _add_player(id: int, index: int) -> void:
	var player = PLAYER_SCENE.instantiate()
	player.name = str(id)

	# 不同玩家设置不同的初始位置，均匀分布在屏幕中
	var spawn_x = 400 + index * 300
	var spawn_y = 450
	player.position = Vector2(spawn_x, spawn_y)

	players_node.add_child(player)

	# 设置多人游戏权限：每个玩家由对应的 peer 控制
	player.set_multiplayer_authority(id)
