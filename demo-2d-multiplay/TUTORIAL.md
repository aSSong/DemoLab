# Godot 4 局域网联机游戏开发教程

> 基于本项目 `demo-2D-multiplay` 的完整学习指南

---

## 目录

- [前置知识](#前置知识)
- [项目结构总览](#项目结构总览)
- [核心概念](#核心概念)
  - [1. 网络模型：C/S 架构](#1-网络模型cs-架构)
  - [2. Peer ID（对等体标识）](#2-peer-id对等体标识)
  - [3. Authority（节点权限）](#3-authority节点权限)
  - [4. RPC（远程过程调用）](#4-rpc远程过程调用)
  - [5. MultiplayerSynchronizer（状态同步器）](#5-multiplayersynchronizer状态同步器)
- [代码逐文件讲解](#代码逐文件讲解)
  - [lobby.gd — 大厅与网络连接](#lobbygd--大厅与网络连接)
  - [main.gd — 玩家生成](#maingd--玩家生成)
  - [player.gd — 输入与移动](#playergd--输入与移动)
  - [player.tscn — 场景同步配置](#playertscn--场景同步配置)
- [完整流程图](#完整流程图)
- [信号触发时序](#信号触发时序)
- [API 速查表](#api-速查表)
- [常见陷阱](#常见陷阱)
- [进阶学习路线](#进阶学习路线)

---

## 前置知识

在学习本教程之前，你需要掌握以下 Godot 基础知识：

### GDScript 语言基础

| 知识点 | 说明 | 本项目中的体现 |
|--------|------|---------------|
| **变量与类型** | `var`, `const`, 类型标注 (`Array[int]`) | `var players: Array[int] = []` |
| **函数定义** | `func`, 参数类型, 返回类型 | `func _add_player(id: int, index: int) -> void` |
| **@onready** | 节点就绪后自动赋值的语法糖 | `@onready var label: Label = $Label` |
| **信号与连接** | `signal`, `.connect()` 方法 | `multiplayer.peer_connected.connect(...)` |
| **注解** | `@rpc`, `@onready`, `@export` 等 | `@rpc("authority", "call_local", "reliable")` |

### Godot 引擎基础

| 知识点 | 说明 | 为什么需要 |
|--------|------|-----------|
| **场景树 (SceneTree)** | 所有节点组织成树状结构 | `multiplayer` 挂在 SceneTree 上，所有节点共享 |
| **场景实例化** | `preload()` + `instantiate()` | 动态创建玩家节点 |
| **节点生命周期** | `_ready()`, `_process()`, `_physics_process()` | 理解何时初始化、何时处理输入 |
| **场景切换** | `get_tree().change_scene_to_file()` | 从大厅切换到游戏场景 |
| **输入系统** | `Input.is_action_pressed()`, InputMap | WASD 控制玩家移动 |
| **CharacterBody2D** | `velocity`, `move_and_slide()` | 玩家物理移动 |
| **UI 控件** | Control, Button, Label, LineEdit, ItemList | 大厅界面 |

### 网络基础概念

| 知识点 | 说明 |
|--------|------|
| **IP 地址** | 局域网中每台设备的唯一地址（如 `192.168.1.100`） |
| **端口 (Port)** | 同一台设备上区分不同服务的数字（本项目用 `9999`） |
| **客户端/服务器模型** | 一台做服务器（等人来连），其他做客户端（主动去连） |
| **UDP/TCP** | ENet 底层基于 UDP，但实现了可靠传输（兼具 TCP 可靠性和 UDP 低延迟） |

---

## 项目结构总览

```
demo-2d-multiplay/
├── project.godot              # 项目配置（主场景、输入映射等）
├── icon.svg                   # Godot 图标（用作玩家贴图）
├── Scenes/
│   ├── lobby.tscn             # 大厅场景 — UI 界面，创建/加入房间
│   ├── main.tscn              # 游戏场景 — 蓝色背景 + Players 容器节点
│   └── player.tscn            # 玩家场景 — CharacterBody2D + 同步器
└── Scripts/
	├── lobby.gd               # 大厅逻辑 — 网络连接、玩家管理、RPC 开始游戏
	├── main.gd                # 游戏逻辑 — 根据 peer 列表生成玩家实例
	└── player.gd              # 玩家逻辑 — 权限判断、输入处理、移动
```

### 场景节点树

**lobby.tscn:**
```
lobby (Control) ← 挂载 lobby.gd
  └─ MarginContainer
	   └─ VBoxContainer
			├─ TitleLabel          "2D 局域网联机 Demo"
			├─ HSeparator
			├─ IPContainer (HBox)
			│    ├─ IPLabel        "服务器IP:"
			│    └─ IPInput        LineEdit, 默认 "127.0.0.1"
			├─ ButtonContainer (HBox)
			│    ├─ CreateButton   "创建服务器"
			│    └─ JoinButton     "加入游戏"
			├─ HSeparator2
			├─ PlayerListLabel     "玩家列表:"
			├─ PlayerList          ItemList (显示已连接玩家)
			├─ StartButton         "开始游戏" (默认隐藏)
			└─ StatusLabel         状态提示文字
```

**main.tscn:**
```
main (Node2D) ← 挂载 main.gd
  ├─ bg (ColorRect)     蓝色背景 1600x900
  └─ Players (Node2D)   玩家实例的父容器（运行时动态添加子节点）
```

**player.tscn:**
```
player (CharacterBody2D) ← 挂载 player.gd
  ├─ MeshInstance2D       网格（视觉辅助）
  ├─ Sprite2D             Godot 图标贴图
  ├─ CollisionShape2D     碰撞形状 128x126
  ├─ Label                "Player 1" 文字标签
  └─ MultiplayerSynchronizer  ← 自动同步 position 属性
```

---

## 核心概念

### 1. 网络模型：C/S 架构

Godot 4 的多人游戏采用 **客户端/服务器 (Client/Server)** 架构：

```
		┌──────────┐
		│  服务器    │  peer_id = 1 (固定)
		│  (主机)    │  既是服务器，也是一个玩家
		└─────┬────┘
			  │
	┌─────────┼─────────┐
	│         │         │
┌───┴──┐ ┌───┴──┐ ┌───┴──┐
│客户端1│ │客户端2│ │客户端3│
│id=随机│ │id=随机│ │id=随机│
└──────┘ └──────┘ └──────┘
```

- **服务器** 是中心节点，所有数据经由服务器转发
- 服务器的 `peer_id` 固定为 **1**
- 客户端的 `peer_id` 是随机生成的大整数
- 在本项目中，服务器同时也是一个玩家（"Listen Server" 模式）

### 2. Peer ID（对等体标识）

每个连接到网络的 Godot 实例都有一个唯一的整数 ID：

```gdscript
# 获取自己的 ID
var my_id = multiplayer.get_unique_id()
# 服务器: 返回 1
# 客户端: 返回随机大整数，如 1823974652

# 获取所有【其他人】的 ID（不包含自己）
var others = multiplayer.get_peers()
# 服务器: 返回 [客户端1的id, 客户端2的id, ...]
# 客户端: 返回 [1, 其他客户端的id, ...]

# 判断自己是否是服务器
var is_host = multiplayer.is_server()
```

### 3. Authority（节点权限）

Authority 决定了 "这个节点归谁管"。这是联机游戏最核心的概念：

```gdscript
# 设置节点的权限归属（通常在创建节点后调用）
player_node.set_multiplayer_authority(peer_id)

# 判断"我"是否是这个节点的权限拥有者
if player_node.is_multiplayer_authority():
	# 只有权限拥有者才能控制这个节点
	pass
```

**默认 authority 是 1（服务器）**。如果不手动设置，所有节点的权限都归服务器。

在本项目中的应用：
- Player1 节点的 authority 设为服务器的 peer_id (1) → 服务器控制 Player1
- Player2 节点的 authority 设为客户端的 peer_id → 客户端控制 Player2

### 4. RPC（远程过程调用）

RPC 让你在一台机器上调用函数，其他机器也执行同一个函数：

```gdscript
# 第一步：用 @rpc 注解声明函数
@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	get_tree().change_scene_to_file("res://Scenes/main.tscn")

# 第二步：用 .rpc() 调用
start_game.rpc()           # 对所有人调用
start_game.rpc_id(目标id)   # 只对指定 peer 调用
```

**@rpc 注解参数详解：**

| 参数 | 可选值 | 说明 |
|------|--------|------|
| **调用权限** | `"authority"` | 只有节点的 authority 才能发起调用 |
| | `"any_peer"` | 任何 peer 都可以发起调用 |
| **本地执行** | `"call_local"` | 发起者自己也执行函数 |
| | `"call_remote"` | 发起者不执行，只有远端执行 |
| **传输模式** | `"reliable"` | 可靠传输，保证送达且按顺序（如场景切换） |
| | `"unreliable"` | 不可靠传输，可能丢包但延迟低（如位置更新） |
| | `"unreliable_ordered"` | 不可靠但保序 |

### 5. MultiplayerSynchronizer（状态同步器）

MultiplayerSynchronizer 是 Godot 4 提供的自动属性同步节点，**无需手写代码**即可同步属性：

```
节点结构:
player (CharacterBody2D)
  └─ MultiplayerSynchronizer
	   └─ 配置: 同步 position 属性, replication_mode = Always
```

**工作原理：** authority 拥有者修改 position → Synchronizer 自动将新值通过网络发给所有其他 peer → 其他 peer 上的同名节点自动更新 position。

**同步方向：authority → 其他所有人**（单向）

**replication_mode 可选值：**

| 值 | 名称 | 说明 | 适用场景 |
|----|------|------|---------|
| 0 | Never | 不同步 | 只在生成时传递一次 |
| 1 | Always | 每帧同步 | 位置、旋转等高频变化数据 |
| 2 | On Change | 变化时同步 | 血量、分数等低频变化数据 |

---

## 代码逐文件讲解

### lobby.gd — 大厅与网络连接

**职责：** 创建/加入服务器、管理玩家列表、通过 RPC 发起开始游戏

**核心流程：**
1. 用户点击 "创建服务器" → 创建 ENet 服务端 peer
2. 用户点击 "加入游戏" → 创建 ENet 客户端 peer
3. 监听网络信号更新玩家列表
4. 服务器点击 "开始游戏" → RPC 所有人切换场景

详细注释见 `Scripts/lobby.gd` 源码。

### main.gd — 玩家生成

**职责：** 在游戏场景加载时，为每个已连接的 peer 创建对应的 player 节点

**核心流程：**
1. 收集所有 peer ID（包括自己）
2. 遍历每个 ID，实例化 player.tscn
3. 设置节点名 = peer_id（保证所有机器上节点路径一致）
4. 设置 multiplayer_authority = peer_id（让对应的玩家控制自己的角色）

详细注释见 `Scripts/main.gd` 源码。

### player.gd — 输入与移动

**职责：** 处理玩家输入、控制角色移动、由 Synchronizer 自动同步位置

**核心流程：**
1. `_ready()`: 设置标签文字，标记自己的角色
2. `_physics_process()`: 仅权限拥有者处理 WASD 输入并移动

详细注释见 `Scripts/player.gd` 源码。

### player.tscn — 场景同步配置

在 player.tscn 场景中，`MultiplayerSynchronizer` 节点配置了 `SceneReplicationConfig`：

```
SceneReplicationConfig:
  properties/0/path = ".:position"     # 同步的属性路径: 当前节点的 position
  properties/0/spawn = true            # 生成时是否同步初始值
  properties/0/replication_mode = 1    # 1 = Always, 每帧都同步
```

这意味着：
- 拥有 authority 的 peer 修改了 player 的 position 后
- Synchronizer 自动将 position 值通过网络发给所有其他 peer
- 其他 peer 上的同名 player 节点的 position 被自动更新
- 整个过程无需手写任何同步代码

---

## 完整流程图

```
时间轴 ──────────────────────────────────────────────────────────►

【阶段1: 大厅】

  主机                                客户端
  ────                                ──────
  点击"创建服务器"
  ENetMultiplayerPeer.create_server(9999)
  multiplayer.multiplayer_peer = peer
  玩家列表: [1]
									  输入 IP, 点击"加入游戏"
									  ENetMultiplayerPeer.create_client(ip, 9999)
									  multiplayer.multiplayer_peer = peer
										  │
										  ▼
									  connected_to_server 信号触发
									  → 添加自己到列表
										  │
			◄─────── 网络连接建立 ─────────┤
			│                             │
			▼                             ▼
  peer_connected(客户端id) 触发      peer_connected(1) 触发
  → 添加客户端到列表                → 添加服务器到列表
  → 启用"开始游戏"按钮
  玩家列表: [1, 客户端id]           玩家列表: [自己id, 1]

  点击"开始游戏"
  start_game.rpc()
			│                             │
			▼                             ▼
  start_game() 本地执行              start_game() 远程执行
  change_scene_to_file(main)         change_scene_to_file(main)


【阶段2: 游戏】

  主机                                客户端
  ────                                ──────
  main.gd _ready()                    main.gd _ready()
  get_peers() → [客户端id]           get_peers() → [1]
  get_unique_id() → 1                get_unique_id() → 客户端id
  all_ids = [1, 客户端id]            all_ids = [1, 客户端id]  ← 排序后一致!

  创建 Player "1"                     创建 Player "1"
  创建 Player "客户端id"              创建 Player "客户端id"
  设置 authority                      设置 authority

  每帧 _physics_process:             每帧 _physics_process:
  Player "1": 是我的 → 处理输入      Player "1": 不是我的 → 跳过
  Player "客户端id": 不是我的 → 跳过  Player "客户端id": 是我的 → 处理输入

  MultiplayerSynchronizer:
  Player "1" 的 position        ──同步──►  客户端上 Player "1" 的 position
  主机上 Player "客户端id" 的 position  ◄──同步──  Player "客户端id" 的 position
```

---

## 信号触发时序

当一个新客户端连接到已有服务器时，信号的触发顺序如下：

```
事件: 客户端B 连接到已有 服务器A

在客户端B上:
  1. connected_to_server()          ← 最先触发，确认连接成功
  2. peer_connected(1)              ← 发现服务器
  3. peer_connected(其他客户端id)    ← 发现已有的其他客户端（如果有）

在服务器A上:
  4. peer_connected(B的id)          ← 服务器发现新客户端

在其他已有客户端上:
  5. peer_connected(B的id)          ← 其他客户端也发现了新客户端
```

**重要提示：** 客户端的 `connected_to_server` 和 `peer_connected` 几乎同时触发。
在 `_on_connected_to_server` 中只需添加自己，服务器和其他 peer 交给 `_on_peer_connected` 处理，
避免重复添加。

---

## API 速查表

### multiplayer 对象（SceneTree.multiplayer）

| API | 返回值 | 说明 |
|-----|--------|------|
| `multiplayer.get_unique_id()` | `int` | 获取本机 peer_id（服务器=1） |
| `multiplayer.is_server()` | `bool` | 本机是否是服务器 |
| `multiplayer.get_peers()` | `PackedInt32Array` | 所有**其他** peer 的 ID（不含自己） |
| `multiplayer.multiplayer_peer` | `MultiplayerPeer` | 读写网络 peer，赋值启动网络，赋 null 断开 |

### multiplayer 信号

| 信号 | 参数 | 触发者 | 说明 |
|------|------|--------|------|
| `peer_connected` | `id: int` | 所有人 | 有新 peer 连入 |
| `peer_disconnected` | `id: int` | 所有人 | 有 peer 断开 |
| `connected_to_server` | 无 | 仅客户端 | 成功连上服务器 |
| `connection_failed` | 无 | 仅客户端 | 连接失败 |
| `server_disconnected` | 无 | 仅客户端 | 服务器断开 |

### ENetMultiplayerPeer

| API | 说明 |
|-----|------|
| `create_server(port, max_clients)` | 在指定端口创建服务器 |
| `create_client(ip, port)` | 连接到指定 IP:端口 |

### Node 的多人游戏方法

| API | 说明 |
|-----|------|
| `node.set_multiplayer_authority(id)` | 设置节点的 authority |
| `node.get_multiplayer_authority()` | 获取节点的 authority |
| `node.is_multiplayer_authority()` | 当前实例是否是该节点的 authority |

### RPC 调用方式

| 语法 | 说明 |
|------|------|
| `func_name.rpc()` | 对所有 peer 调用（含自己需 `call_local`） |
| `func_name.rpc_id(id)` | 只对指定 peer 调用 |
| `func_name.rpc_id(1)` | 只对服务器调用 |

---

## 常见陷阱

### 1. `_ready()` 中不能依赖 `is_multiplayer_authority()`

```gdscript
# ❌ 错误做法
func _ready():
	if is_multiplayer_authority():  # 此时 authority 还没设置!
		label.text += " (你)"

# ✅ 正确做法
func _ready():
	var peer_id = str(name).to_int()
	if peer_id == multiplayer.get_unique_id():  # 用节点名(=peer_id)比较
		label.text += " (你)"
```

**原因：** `add_child()` 触发 `_ready()`，而 `set_multiplayer_authority()` 在 `add_child()` 之后才调用。默认 authority=1，所以服务器上所有节点的 `is_multiplayer_authority()` 都会返回 `true`。

### 2. `get_peers()` 不包含自己

```gdscript
# ❌ 错误：少了自己
var all_players = multiplayer.get_peers()

# ✅ 正确：手动加上自己
var all_players = [multiplayer.get_unique_id()]
all_players.append_array(multiplayer.get_peers())
```

### 3. 节点名必须所有机器一致

```gdscript
# ✅ 正确：用 peer_id 作为节点名，所有机器上路径一致
player.name = str(peer_id)
# 主机: Players/1, Players/1823974652
# 客户端: Players/1, Players/1823974652  ← 一致!

# ❌ 错误：用递增索引，不同机器可能不一致
player.name = "Player_" + str(index)
```

**MultiplayerSynchronizer 通过节点路径匹配远端节点**，路径不一致同步就会失败。

### 4. 信号中避免重复添加玩家

```gdscript
# ❌ 错误：无去重，可能添加两次
func _on_peer_connected(id):
	players.append(id)

# ✅ 正确：先检查是否已存在
func _on_peer_connected(id):
	if not players.has(id):
		players.append(id)
```

### 5. 场景切换不会断开连接

`multiplayer.multiplayer_peer` 挂在 SceneTree 上而非场景节点上，
`change_scene_to_file()` 会销毁当前场景的所有节点，但不会影响 SceneTree，
因此网络连接在场景切换后依然有效。

---

## 进阶学习路线

掌握本项目后，建议按以下顺序逐步进阶：

### 第一阶段：完善当前项目

| 主题 | 说明 | 关键 API/概念 |
|------|------|-------------|
| **断线重连** | 处理玩家中途断开的情况，在游戏中移除 player | `peer_disconnected` 信号 + `queue_free()` |
| **返回大厅** | 游戏结束后返回大厅，清理状态 | `multiplayer.multiplayer_peer = null` |
| **同步更多属性** | 同步旋转、动画状态、血量等 | SceneReplicationConfig 添加更多属性 |
| **玩家颜色/外观** | 不同玩家不同颜色以区分 | `Sprite2D.modulate` + 同步 |

### 第二阶段：进阶机制

| 主题 | 说明 | 关键 API/概念 |
|------|------|-------------|
| **MultiplayerSpawner** | 自动将服务器上新增的节点复制到所有客户端 | `MultiplayerSpawner` 节点 |
| **自定义 RPC** | 用 RPC 实现聊天、技能释放等交互 | `@rpc("any_peer")`, `rpc_id()` |
| **Spawn/Despawn 同步** | 动态创建/销毁子弹、道具等游戏对象 | `MultiplayerSpawner.spawn()` |
| **插值与预测** | 让远端玩家移动更平滑，减少视觉跳变 | 位置插值 (`lerp`), 客户端预测 |
| **服务器权威验证** | 服务器校验客户端输入，防止作弊 | 服务器端验证 + `rpc_id()` 回传结果 |

### 第三阶段：高级架构

| 主题 | 说明 | 关键 API/概念 |
|------|------|-------------|
| **Autoload 全局管理** | 用 Singleton 管理网络状态、玩家信息 | `ProjectSettings > AutoLoad` |
| **SceneMultiplayer 自定义** | 替换默认的 multiplayer 实现 | `SceneMultiplayer`, `MultiplayerAPI` |
| **WebSocket/WebRTC** | 支持浏览器端联机 | `WebSocketMultiplayerPeer`, `WebRTCMultiplayerPeer` |
| **专用服务器** | 服务器不参与游戏，仅做裁判和转发 | Headless 模式, `--headless` 命令行参数 |
| **NAT 穿透** | 实现互联网联机（非局域网） | STUN/TURN 服务器, WebRTC |
| **状态回滚** | 竞技游戏级别的延迟补偿 | Rollback Netcode, 输入延迟 vs 回滚 |

### 推荐学习资源

- **Godot 官方文档**: [High-level multiplayer](https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html)
- **Godot 官方 Demo**: [Multiplayer Bomber](https://github.com/godotengine/godot-demo-projects/tree/master/networking/multiplayer_bomber)
- **GDQuest 教程**: YouTube 搜索 "GDQuest Godot 4 multiplayer"
- **概念理解**: 搜索 "Gabriel Gambetta Fast-Paced Multiplayer" 了解网络游戏同步原理

---

## 术语对照表

| 英文 | 中文 | 说明 |
|------|------|------|
| Peer | 对等体 | 网络中的一个参与者（服务器或客户端） |
| Authority | 权限/权威 | 决定谁能控制某个节点 |
| RPC | 远程过程调用 | 让远端机器执行本地函数 |
| Replication | 复制/同步 | 将数据从一端复制到另一端 |
| Spawn | 生成 | 在游戏中创建新对象 |
| Listen Server | 监听服务器 | 服务器同时也是一个玩家 |
| Dedicated Server | 专用服务器 | 服务器不参与游戏，仅做转发 |
| Latency | 延迟 | 数据从一端到另一端的时间 |
| Interpolation | 插值 | 在两个已知位置之间平滑过渡 |
| Prediction | 预测 | 客户端提前预估移动结果，减少延迟感 |
