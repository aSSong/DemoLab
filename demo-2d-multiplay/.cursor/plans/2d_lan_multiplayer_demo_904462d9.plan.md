---
name: 2D LAN Multiplayer Demo
overview: 在现有 Godot 4.6 项目中实现一个最小的 2D 局域网联机游戏 Demo，包含 Lobby 大厅（创建/加入）、Main 游戏场景（同步移动），使用 ENetMultiplayerPeer + MultiplayerSynchronizer 架构。
todos:
  - id: create-scripts-dir
    content: 创建 Scripts 目录
    status: completed
  - id: modify-lobby-tscn
    content: 重写 lobby.tscn，添加完整 UI 节点结构（按钮、输入框、玩家列表等）
    status: completed
  - id: create-lobby-gd
    content: 创建 Scripts/lobby.gd - 网络创建/加入、玩家列表管理、开始游戏 RPC
    status: completed
  - id: modify-main-tscn
    content: 修改 main.tscn，添加 Players 节点容器，挂载脚本
    status: completed
  - id: create-main-gd
    content: 创建 Scripts/main.gd - 根据 peer 列表生成玩家实例
    status: completed
  - id: modify-player-tscn
    content: 修改 player.tscn，添加 MultiplayerSynchronizer 同步 position
    status: completed
  - id: create-player-gd
    content: 创建 Scripts/player.gd - 权限检查 + WASD 移动逻辑
    status: completed
  - id: update-project-godot
    content: 修改 project.godot 设置主场景为 lobby，添加方向键输入映射
    status: completed
isProject: false
---

# 2D 局域网联机游戏 Demo 实现计划

## 架构总览

```mermaid
sequenceDiagram
    participant Host as 主机_Server
    participant Client as 客户端_Client
    Host->>Host: 创建 ENet 服务器 port 9999
    Client->>Host: 连接到 IP:9999
    Host-->>Client: peer_connected 信号
    Note over Host,Client: 双方更新玩家列表 UI
    Host->>Host: 点击"开始游戏"
    Host->>Client: start_game RPC
    Note over Host,Client: 切换到 main.tscn
    Note over Host,Client: 各自本地创建所有玩家实例
    Host->>Host: WASD 控制自己的 Player
    Client->>Client: WASD 控制自己的 Player
    Note over Host,Client: MultiplayerSynchronizer 自动同步 position
```



## 需要创建的文件（3 个脚本）

### 1. `Scripts/lobby.gd` - 大厅网络逻辑

核心逻辑：

- **创建服务器**: `ENetMultiplayerPeer.create_server(9999)` 设置为 multiplayer peer
- **加入游戏**: `ENetMultiplayerPeer.create_client(ip, 9999)` 连接到服务器
- 监听 `multiplayer.peer_connected` / `peer_disconnected` 信号更新玩家列表
- **开始游戏**: 通过 `@rpc("authority", "call_local", "reliable")` 调用 `get_tree().change_scene_to_file("res://Scenes/main.tscn")`
- 服务端显示"开始游戏"按钮，至少有1个其他玩家时可点击

### 2. `Scripts/main.gd` - 游戏场景逻辑

核心逻辑：

- `_ready()` 中通过 `multiplayer.get_peers()` 获取所有已连接的 peer ID
- 为每个 peer（包括自己）实例化 `player.tscn`，设置 `name = str(peer_id)`
- 调用 `set_multiplayer_authority(peer_id)` 设置每个玩家的网络权限
- 不同玩家设置不同初始位置，避免重叠

### 3. `Scripts/player.gd` - 玩家移动与同步

核心逻辑：

- `_ready()`: 根据 `name`（即 peer_id）设置 Label 显示 "Player X"
- `_physics_process()`: 仅 `is_multiplayer_authority()` 为 true 时处理输入
- 使用已配置的 `up/down/left/right` 输入映射（WASD），速度 300px/s
- 调用 `move_and_slide()` 移动，位置由 `MultiplayerSynchronizer` 自动同步

## 需要修改的文件（4 个文件）

### 4. `Scenes/lobby.tscn` - 重构为 UI 大厅

将空的 Node2D 重写为包含以下 UI 结构的场景：

```
lobby (Control) [全屏]
  MarginContainer [居中布局]
    VBoxContainer
      TitleLabel "2D 局域网联机 Demo"
      HBoxContainer -> Label "服务器IP:" + LineEdit (默认 127.0.0.1)
      HBoxContainer -> Button "创建服务器" + Button "加入游戏"  
      Label "玩家列表:"
      ItemList (显示已连接玩家)
      StartButton "开始游戏" (默认隐藏)
      StatusLabel (状态提示文字)
```

挂载 `Scripts/lobby.gd` 脚本。

### 5. `Scenes/main.tscn` - 添加 Players 容器

在现有蓝色背景基础上添加：

- `Players` (Node2D) - 作为所有玩家实例的父节点

挂载 `Scripts/main.gd` 脚本。

### 6. `Scenes/player.tscn` - 添加同步器

在现有 CharacterBody2D 基础上添加：

- `MultiplayerSynchronizer` 节点，配置 `SceneReplicationConfig` 同步 `position` 属性（replication_mode = always）

挂载 `Scripts/player.gd` 脚本。

### 7. `project.godot` - 设置主场景

- 将 `run/main_scene` 设为 `"res://Scenes/lobby.tscn"`（游戏启动时进入大厅）

## 关键技术要点

- **无需 Autoload**：`multiplayer.multiplayer_peer` 挂在 SceneTree 上，场景切换后连接仍然保持
- **无需 MultiplayerSpawner**：所有 peer 在 `main.gd` 的 `_ready()` 中本地创建相同的玩家实例，通过 `MultiplayerSynchronizer` 同步位置即可
- **输入映射**：项目已配置 WASD 为 up/down/left/right，同时会增加方向键映射

