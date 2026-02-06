extends Control

const PORT = 9999

@onready var ip_input: LineEdit = $MarginContainer/VBoxContainer/IPContainer/IPInput
@onready var create_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/CreateButton
@onready var join_button: Button = $MarginContainer/VBoxContainer/ButtonContainer/JoinButton
@onready var player_list: ItemList = $MarginContainer/VBoxContainer/PlayerList
@onready var start_button: Button = $MarginContainer/VBoxContainer/StartButton
@onready var status_label: Label = $MarginContainer/VBoxContainer/StatusLabel

# 存储所有已连接的玩家ID
var players: Array[int] = []


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)


func _on_create_pressed() -> void:
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT)
	if error != OK:
		status_label.text = "创建服务器失败! 错误码: " + str(error)
		return

	multiplayer.multiplayer_peer = peer
	status_label.text = "服务器已创建，等待玩家加入... 端口: " + str(PORT)

	# 服务器自己也是玩家
	players.append(1)  # 服务器的 peer_id 固定为 1
	_update_player_list()

	# 禁用按钮，显示开始按钮
	create_button.disabled = true
	join_button.disabled = true
	start_button.visible = true
	start_button.disabled = true  # 至少需要1个其他玩家才能开始


func _on_join_pressed() -> void:
	var ip = ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "请输入服务器IP地址!"
		return

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, PORT)
	if error != OK:
		status_label.text = "连接失败! 错误码: " + str(error)
		return

	multiplayer.multiplayer_peer = peer
	status_label.text = "正在连接到 " + ip + ":" + str(PORT) + " ..."

	create_button.disabled = true
	join_button.disabled = true


func _on_peer_connected(id: int) -> void:
	if not players.has(id):
		players.append(id)
	_update_player_list()
	status_label.text = "玩家 " + str(id) + " 已加入!"

	# 服务器端：有其他玩家加入后可以开始游戏
	if multiplayer.is_server():
		start_button.disabled = false


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	_update_player_list()
	status_label.text = "玩家 " + str(id) + " 已断开!"

	# 服务器端：如果没有其他玩家了，禁用开始按钮
	if multiplayer.is_server() and players.size() <= 1:
		start_button.disabled = true


func _on_connected_to_server() -> void:
	status_label.text = "已连接到服务器! 等待房主开始游戏..."

	# 客户端：只添加自己，其他 peer（包括服务器）会通过 _on_peer_connected 添加
	var my_id = multiplayer.get_unique_id()
	if not players.has(my_id):
		players.append(my_id)
	_update_player_list()


func _on_connection_failed() -> void:
	status_label.text = "连接服务器失败!"
	create_button.disabled = false
	join_button.disabled = false
	multiplayer.multiplayer_peer = null


func _on_start_pressed() -> void:
	# 只有服务器能发起开始游戏
	if multiplayer.is_server():
		start_game.rpc()


@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	get_tree().change_scene_to_file("res://Scenes/main.tscn")


func _update_player_list() -> void:
	player_list.clear()
	# 排序让显示一致
	var sorted_players = players.duplicate()
	sorted_players.sort()
	for i in sorted_players.size():
		var id = sorted_players[i]
		var label = "Player " + str(i + 1)
		if id == 1:
			label += " (主机)"
		if id == multiplayer.get_unique_id():
			label += " (你)"
		player_list.add_item(label)
