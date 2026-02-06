# ============================================================================
# main.gd — 游戏场景脚本
# ============================================================================
# 职责：
#   场景加载时，为每个已连接的 peer 创建对应的 player 节点实例
#
# 核心思路：
#   每台机器（服务器和所有客户端）都独立运行这段代码，
#   各自在本地创建所有玩家的节点。关键是确保：
#   1. 每台机器上创建的节点数量相同
#   2. 每个节点的名称（name）在所有机器上一致（用 peer_id 命名）
#   3. 每个节点的 authority 设置正确（让对应 peer 控制自己的角色）
#
#   这样 MultiplayerSynchronizer 就能通过节点路径匹配，自动同步数据。
#
# 场景树结构（运行时）：
#   main
#     ├─ bg (ColorRect)
#     └─ Players
#          ├─ "1"           ← peer_id=1 (服务器) 的玩家节点
#          └─ "1823974652"  ← peer_id=客户端id 的玩家节点
# ============================================================================

extends Node2D

# preload 在编译时加载场景资源，比 load() 更快
# 返回 PackedScene 类型，后续用 .instantiate() 创建实例
const PLAYER_SCENE = preload("res://Scenes/player.tscn")

# Players 节点是所有玩家实例的父容器
@onready var players_node: Node2D = $Players


func _ready() -> void:
	# ============================================================
	# 收集所有已连接的 peer ID
	# ============================================================
	# multiplayer.get_unique_id() — 返回自己的 peer_id
	# multiplayer.get_peers()     — 返回所有【其他】peer 的 id 数组（不含自己！）
	#
	# 所以要手动把自己加进去，才能得到完整的玩家列表

	var peer_ids: Array[int] = []
	peer_ids.append(multiplayer.get_unique_id())  # 先加自己
	for id in multiplayer.get_peers():             # 再加其他所有人
		peer_ids.append(id)

	# ★ 排序非常重要！
	# 不同 peer 上 get_peers() 返回的顺序可能不同，
	# 但排序后，每台机器得到的 peer_ids 数组内容和顺序完全一致。
	# 这保证了所有机器上的玩家节点创建顺序一致 → 初始位置一致。
	peer_ids.sort()

	# 为每个 peer 创建一个 player 节点
	for i in peer_ids.size():
		_add_player(peer_ids[i], i)


func _add_player(id: int, index: int) -> void:
	# ============================================================
	# 实例化玩家场景
	# ============================================================
	var player = PLAYER_SCENE.instantiate()

	# ★★★ 关键：节点名 = str(peer_id) ★★★
	# 为什么用 peer_id 做节点名？因为 MultiplayerSynchronizer 通过【节点路径】
	# 匹配本机和远端的节点。如果两台机器上同一个玩家的节点路径不同，同步就会失败。
	#
	# 示例：
	#   主机上:   Players/1, Players/1823974652
	#   客户端上: Players/1, Players/1823974652   ← 路径一致，同步成功!
	#
	# 如果用 "Player_0", "Player_1" 这样的名字，不同机器上的顺序可能不同，就会错乱。
	player.name = str(id)

	# 不同玩家设置不同的初始位置，避免重叠
	var spawn_x = 400 + index * 300
	var spawn_y = 450
	player.position = Vector2(spawn_x, spawn_y)

	# ============================================================
	# 添加到场景树
	# ============================================================
	# ★ 注意执行顺序！
	# add_child() 会立即触发 player 节点的 _ready() 函数
	# 但此时 set_multiplayer_authority() 还没调用！
	# 所以在 player.gd 的 _ready() 中不能使用 is_multiplayer_authority()
	# （详见 player.gd 中的注释）
	players_node.add_child(player)

	# ============================================================
	# 设置多人游戏权限（Authority）
	# ============================================================
	# set_multiplayer_authority(peer_id) 的含义：
	#   "这个节点归 peer_id 对应的那台机器管"
	#
	# 设置后的效果：
	#   - 在 peer_id 对应的机器上: player.is_multiplayer_authority() → true
	#   - 在其他机器上:           player.is_multiplayer_authority() → false
	#
	# 同时，MultiplayerSynchronizer 的同步方向是：
	#   authority 拥有者 → 其他所有人
	# 所以只有权限拥有者修改 position 才会同步到其他机器
	player.set_multiplayer_authority(id)
