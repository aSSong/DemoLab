# ============================================================================
# lobby.gd — 大厅场景脚本
# ============================================================================
# 职责：
#   1. 创建服务器 或 加入已有服务器（网络连接管理）
#   2. 监听 multiplayer 信号，维护已连接的玩家列表
#   3. 服务器通过 RPC 通知所有人切换到游戏场景
#
# 知识点：
#   - ENetMultiplayerPeer: Godot 内置的基于 ENet 协议的网络传输层
#   - multiplayer 信号: peer_connected, peer_disconnected, connected_to_server, connection_failed
#   - RPC (Remote Procedure Call): 远程过程调用，让一台机器调用函数，所有机器都执行
# ============================================================================

extends Control

# 网络端口号。服务器和客户端必须使用相同端口。
# 范围: 1024-65535（1024以下是系统保留端口）
const PORT = 9999

# ============================================================================
# 节点引用
# ============================================================================
# @onready 的含义：等节点树就绪后（_ready 之前）自动赋值
# $ 是 get_node() 的简写，路径相对于当前节点（lobby）
@onready var ip_input: LineEdit = $MarginContainer/VBoxContainer/IPContainer/IPInput
@onready var create_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/CreateButton
@onready var join_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/JoinButton
@onready var player_list: ItemList = $MarginContainer/VBoxContainer/PlayerList
@onready var start_button: Button = $MarginContainer/VBoxContainer/StartButton
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel

# 存储所有已连接的玩家 peer_id
# 使用 Array[int] 类型标注，确保只能存放整数
var players: Array[int] = []


# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	# multiplayer 是 SceneTree 上的全局对象，所有节点共享。
	# 它提供了 4 个关键信号用于监听网络事件：
	#
	# peer_connected(id: int)    — 有新 peer 连入（所有人都会收到）
	# peer_disconnected(id: int) — 有 peer 断开（所有人都会收到）
	# connected_to_server()      — 仅客户端收到：成功连上服务器
	# connection_failed()        — 仅客户端收到：连接服务器失败
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


# ============================================================================
# 创建服务器
# ============================================================================
# 按钮信号连接方式：在 lobby.tscn 中通过 [connection] 配置，
# 当 CreateButton 的 "pressed" 信号触发时，调用此函数。

func _on_create_pressed() -> void:
	# 第一步：创建 ENet 对等体
	# ENetMultiplayerPeer 封装了底层的 ENet 网络库
	# ENet 基于 UDP 协议，但实现了可靠传输、分包、多通道等功能
	var peer = ENetMultiplayerPeer.new()

	# 第二步：在指定端口上创建服务器
	# create_server(port, max_clients) 的第二个参数可选，默认 32 个客户端
	# 返回 Error 枚举，OK 表示成功
	var error = peer.create_server(PORT)
	if error != OK:
		status_label.text = "创建服务器失败! 错误码: " + str(error)
		return

	# 第三步：把 peer 赋值给 SceneTree 的 multiplayer
	# ★ 这是关键的一步！赋值后，网络就"通了"
	# 之后整个场景树中所有节点都可以使用 multiplayer API
	# 即使切换场景，这个 peer 也不会断开（因为它挂在 SceneTree 上，不属于任何场景节点）
	multiplayer.multiplayer_peer = peer
	status_label.text = "服务器已创建，等待玩家加入... 端口: " + str(PORT)

	# 服务器自己也是玩家，peer_id 固定为 1
	players.append(1)
	_update_player_list()

	# UI 状态更新
	create_button.disabled = true
	join_button.disabled = true
	start_button.visible = true
	start_button.disabled = true  # 至少需要 1 个其他玩家才能开始


# ============================================================================
# 加入游戏（客户端）
# ============================================================================

func _on_join_pressed() -> void:
	# 获取用户输入的 IP 地址
	# strip_edges() 去除首尾空格，避免复制粘贴带入空格
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "请输入服务器IP地址!"
		return

	# 创建客户端 peer 并连接到指定 IP:端口
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, PORT)
	if error != OK:
		status_label.text = "连接失败! 错误码: " + str(error)
		return

	# 同样赋值给 multiplayer，启动网络
	# 注意：create_client 是异步的，赋值后连接还没建立
	# 连接成功会触发 connected_to_server 信号
	# 连接失败会触发 connection_failed 信号
	multiplayer.multiplayer_peer = peer
	status_label.text = "正在连接到 " + ip + ":" + str(PORT) + " ..."

	create_button.disabled = true
	join_button.disabled = true


# ============================================================================
# 网络信号处理
# ============================================================================

# --- 有新 peer 连入 ---
# 触发时机：所有人都会收到（服务器、已有客户端、新客户端自己）
# 参数 id：新连入者的 peer_id
func _on_peer_connected(id: int) -> void:
	# ★ 去重检查：避免同一个 peer 被添加两次
	# 为什么需要去重？因为客户端连接时，connected_to_server 和 peer_connected
	# 几乎同时触发，如果两个回调都添加了同一个 id，就会重复
	if not players.has(id):
		players.append(id)
	_update_player_list()
	status_label.text = "玩家 " + str(id) + " 已加入!"

	# 服务器端专属逻辑：有其他玩家加入后，启用"开始游戏"按钮
	if multiplayer.is_server():
		start_button.disabled = false


# --- 有 peer 断开 ---
func _on_peer_disconnected(id: int) -> void:
	# 从玩家列表中移除
	players.erase(id)
	_update_player_list()
	status_label.text = "玩家 " + str(id) + " 已断开!"

	# 服务器端：如果只剩自己了，禁用开始按钮
	if multiplayer.is_server() and players.size() <= 1:
		start_button.disabled = true


# --- 客户端成功连上服务器 ---
# ★ 注意：此信号只在客户端触发，服务器不会收到
# 触发后，紧接着会收到 peer_connected(1) 以及其他已有客户端的 peer_connected
func _on_connected_to_server() -> void:
	status_label.text = "已连接到服务器! 等待房主开始游戏..."

	# 客户端只添加自己的 ID
	# 服务器 (id=1) 和其他已有客户端会通过 _on_peer_connected 信号自动添加
	# ★ 这样设计可以避免重复添加的 bug
	var my_id = multiplayer.get_unique_id()
	if not players.has(my_id):
		players.append(my_id)
	_update_player_list()


# --- 客户端连接失败 ---
func _on_connection_failed() -> void:
	status_label.text = "连接服务器失败!"
	# 恢复按钮状态，允许重新操作
	create_button.disabled = false
	join_button.disabled = false
	# 清除 peer，释放网络资源
	multiplayer.multiplayer_peer = null


# ============================================================================
# 开始游戏（RPC）
# ============================================================================

func _on_start_pressed() -> void:
	# 安全检查：只有服务器才能发起开始游戏
	if multiplayer.is_server():
		# ★ .rpc() 是远程过程调用的核心语法
		# start_game.rpc() 等于：对所有已连接的 peer 调用 start_game 函数
		# 由于函数声明了 "call_local"，发起者（服务器）自己也会执行
		start_game.rpc()


# @rpc 注解声明这是一个可以被远程调用的函数
# 参数解释：
#   "authority"  — 只有节点的 authority 拥有者才能发起调用
#                  lobby 节点的 authority 默认是 1（服务器），所以只有服务器能调用
#   "call_local" — 发起者自己也执行此函数（不加则只有远端执行）
#   "reliable"   — 可靠传输，保证送达且按顺序（适合重要操作如场景切换）
@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	# 所有 peer（服务器 + 所有客户端）都会执行这行代码
	# 切换场景后，lobby 场景的所有节点被销毁
	# 但 multiplayer.multiplayer_peer 挂在 SceneTree 上，不会被销毁
	# 所以网络连接在场景切换后依然保持
	get_tree().change_scene_to_file("res://Scenes/main.tscn")


# ============================================================================
# 更新玩家列表 UI
# ============================================================================

func _update_player_list() -> void:
	player_list.clear()

	# 排序确保所有机器上的显示顺序一致
	# 因为不同 peer 上 players 数组的添加顺序可能不同
	var sorted_players = players.duplicate()
	sorted_players.sort()

	for i in sorted_players.size():
		var id = sorted_players[i]
		var label = "Player " + str(i + 1)

		# id == 1 就是服务器（主机）
		if id == 1:
			label += " (主机)"

		# 判断是否是自己
		if id == multiplayer.get_unique_id():
			label += " (你)"

		player_list.add_item(label)
