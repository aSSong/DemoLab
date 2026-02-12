extends Node
class_name ButtonEffectsModule

@export var ease_type:Tween.EaseType
@export var trans_type:Tween.TransitionType
@export var anim_duration: float = 0.07
@export var scale_amount: Vector2 = Vector2(1.1,1.1)
@export var rotate_amount: float = 3.0
@export var shake_intensity: float = 0.02 ## 抖动缩放偏移幅度
@export var shake_duration: float = 0.06 ## 单次抖动时长

@onready var button: Button = get_parent()

var tween: Tween
var shake_tween: Tween

func _ready():
	button.mouse_entered.connect(on_mouse_hovered.bind(true))
	button.mouse_exited.connect(on_mouse_hovered.bind(false))
	button.pressed.connect(_on_button_pressed)
	button.pivot_offset_ratio = Vector2(0.5,0.5) # 设置按钮的中心点为按钮的中心点

func _on_button_pressed() -> void:
	reset_tween()
	tween.tween_property(button,"scale",scale_amount,anim_duration).from(Vector2(0.8,0.8))
	tween.tween_property(button,"rotation_degrees",rotate_amount * [-1,1].pick_random(),anim_duration).from(0)

func on_mouse_hovered(hovered: bool) -> void:
	reset_tween()
	if shake_tween:
		shake_tween.kill()
	if hovered:
		tween.tween_property(button,"scale",scale_amount,anim_duration)
		tween.tween_property(button,"rotation_degrees",rotate_amount * [-1,1].pick_random(),anim_duration)
		tween.chain().tween_callback(_start_shake)
	else:
		tween.tween_property(button,"scale",Vector2.ONE,anim_duration)
		tween.tween_property(button,"rotation_degrees",0.0,anim_duration)

func _start_shake() -> void:
	shake_tween = create_tween().set_parallel(true)
	var rand_scale = scale_amount + Vector2(randf_range(-shake_intensity, shake_intensity), randf_range(-shake_intensity, shake_intensity))
	var rand_rot = rotate_amount * [-1,1].pick_random() + randf_range(-1.0, 1.0)
	shake_tween.tween_property(button,"scale",rand_scale,shake_duration)
	shake_tween.tween_property(button,"rotation_degrees",rand_rot,shake_duration)
	shake_tween.chain().tween_callback(_start_shake)

func reset_tween() -> void:
	if tween:
		tween.kill()
	tween = create_tween().set_ease(ease_type).set_trans(trans_type).set_parallel(true)
