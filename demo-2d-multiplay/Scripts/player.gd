# ============================================================================
# player.gd — 玩家角色脚本
# ============================================================================
# 职责：
#   1. 显示玩家标签（Player 1, Player 2 等）
#   2. 处理键盘输入（仅权限拥有者）
#   3. 控制角色移动
#
# 同步机制（无需在此脚本中编写）：
#   player.tscn 中的 MultiplayerSynchronizer 节点会自动同步 position 属性：
#   - 权限拥有者（authority）修改 position → 自动网络传输 → 其他 peer 的同名节点更新
#   - 这一切由引擎自动完成，player.gd 只需要在本地处理输入和移动
#
# 场景节点结构：
#   player (CharacterBody2D) ← 本脚本
#     ├─ Sprite2D                — Godot 图标贴图
#     ├─ CollisionShape2D        — 碰撞形状
#     ├─ Label                   — 显示 "Player 1 (你)" 等文字
#     └─ MultiplayerSynchronizer — 自动同步 position（配置在 tscn 中）
# ============================================================================

extends CharacterBody2D

# 移动速度（像素/秒）
const SPEED = 300.0

# 玩家名称标签
@onready var label: Label = $Label


# ============================================================================
# 初始化
# ============================================================================

func _ready() -> void:
	# ============================================================
	# 从节点名获取 peer_id
	# ============================================================
	# main.gd 中创建此节点时: player.name = str(peer_id)
	# 所以节点名就是 peer_id 的字符串形式，这里转回整数
	var peer_id = str(name).to_int()

	# 计算玩家编号（Player 1, Player 2, ...）
	var player_index = _get_player_index(peer_id)
	label.text = "Player " + str(player_index)

	# ============================================================
	# 判断是否是"自己"的角色
	# ============================================================
	# ★★★ 重要陷阱 ★★★
	# 这里【不能】使用 is_multiplayer_authority() 来判断！
	#
	# 原因：
	#   main.gd 中的执行顺序是：
	#     1. players_node.add_child(player)       ← 触发此 _ready()
	#     2. player.set_multiplayer_authority(id)  ← _ready() 之后才执行
	#
	#   所以在 _ready() 执行时，authority 还是默认值 1（服务器）
	#   这导致：在服务器上，所有玩家的 is_multiplayer_authority() 都返回 true
	#           在客户端上，所有玩家的 is_multiplayer_authority() 都返回 false
	#
	# 正确做法：直接比较 peer_id 和 multiplayer.get_unique_id()
	# 这不依赖 authority 是否已设置
	if peer_id == multiplayer.get_unique_id():
		label.text += " (你)"
		# 将自己的标签设为黄色，方便在屏幕上区分
		label.add_theme_color_override("font_color", Color.YELLOW)


# ============================================================================
# 物理帧处理（每物理帧调用一次，默认 60 FPS）
# ============================================================================

func _physics_process(_delta: float) -> void:
	# ============================================================
	# 权限检查 — 联机游戏中最核心的一行代码
	# ============================================================
	# is_multiplayer_authority() 判断当前运行此代码的机器是否拥有此节点的权限
	#
	# 示例（假设有服务器和一个客户端）：
	#   Player "1" 节点:
	#     服务器上: is_multiplayer_authority() → true  (authority=1, 自己的id=1)
	#     客户端上: is_multiplayer_authority() → false (authority=1, 自己的id≠1)
	#
	#   Player "客户端id" 节点:
	#     服务器上: is_multiplayer_authority() → false (authority=客户端id, 自己的id=1)
	#     客户端上: is_multiplayer_authority() → true  (authority=客户端id, 自己的id=客户端id)
	#
	# 效果：每台机器只处理自己角色的输入，不会操控别人的角色
	#
	# ★ 注意：这里可以安全使用 is_multiplayer_authority()
	# 因为 _physics_process 是在 _ready() 之后每帧调用的，
	# 到第一帧时 set_multiplayer_authority() 已经执行完了
	if not is_multiplayer_authority():
		return

	# ============================================================
	# 处理输入
	# ============================================================
	# Input.is_action_pressed() 检查指定的输入动作是否正在被按下
	# "up", "down", "left", "right" 是在 project.godot 的 [input] 中定义的
	# 本项目映射了 WASD 和方向键
	var direction = Vector2.ZERO

	if Input.is_action_pressed("up"):
		direction.y -= 1    # 屏幕坐标系：y轴向下为正，所以向上是 -1
	if Input.is_action_pressed("down"):
		direction.y += 1
	if Input.is_action_pressed("left"):
		direction.x -= 1
	if Input.is_action_pressed("right"):
		direction.x += 1

	# ============================================================
	# 移动
	# ============================================================
	# normalized() 将方向向量归一化为单位向量（长度=1）
	# 这确保了斜方向移动时速度不会变成 √2 倍
	# 例如：同时按右+下，direction=(1,1), normalized()→(0.707, 0.707), 长度=1
	velocity = direction.normalized() * SPEED

	# move_and_slide() 是 CharacterBody2D 的内置方法：
	# - 根据 velocity 移动角色
	# - 自动处理碰撞滑动（撞墙时沿墙壁滑动而不是停下）
	# - 会自动乘以 delta（帧间隔时间），所以不需要手动 * delta
	#
	# 移动后，position 属性被自动更新
	# MultiplayerSynchronizer 检测到 position 变化后，自动同步给其他 peer
	move_and_slide()


# ============================================================================
# 辅助函数
# ============================================================================

func _get_player_index(peer_id: int) -> int:
	# 获取所有已连接的 peer ID（包括自己），排序后找到指定 id 的位置
	# 用于生成 "Player 1", "Player 2" 这样的标签

	var all_ids: Array[int] = []
	all_ids.append(multiplayer.get_unique_id())   # 自己
	for id in multiplayer.get_peers():             # 其他所有人
		all_ids.append(id)
	all_ids.sort()

	# 查找 peer_id 在排序后数组中的位置
	for i in all_ids.size():
		if all_ids[i] == peer_id:
			return i + 1  # 从 1 开始编号

	return 0  # 找不到时返回 0（不应该发生）
