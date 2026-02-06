extends CharacterBody2D

const SPEED = 300.0

@onready var label: Label = $Label


func _ready() -> void:
	# 根据节点名（即 peer_id）设置玩家标签
	var peer_id = str(name).to_int()
	var player_index = _get_player_index(peer_id)
	label.text = "Player " + str(player_index)

	# 用 name（peer_id）与自己的 ID 比较，而非 is_multiplayer_authority()
	# 因为 _ready() 在 add_child 时触发，此时 authority 尚未被 set_multiplayer_authority 设置
	if peer_id == multiplayer.get_unique_id():
		label.text += " (你)"
		label.add_theme_color_override("font_color", Color.YELLOW)


func _physics_process(_delta: float) -> void:
	# 只有拥有权限的 peer 才能控制移动
	if not is_multiplayer_authority():
		return

	var direction = Vector2.ZERO

	if Input.is_action_pressed("up"):
		direction.y -= 1
	if Input.is_action_pressed("down"):
		direction.y += 1
	if Input.is_action_pressed("left"):
		direction.x -= 1
	if Input.is_action_pressed("right"):
		direction.x += 1

	velocity = direction.normalized() * SPEED
	move_and_slide()


func _get_player_index(peer_id: int) -> int:
	# 获取所有 peer 并排序，找到自己的索引
	var all_ids: Array[int] = []
	all_ids.append(multiplayer.get_unique_id())
	for id in multiplayer.get_peers():
		all_ids.append(id)
	all_ids.sort()

	for i in all_ids.size():
		if all_ids[i] == peer_id:
			return i + 1
	return 0
