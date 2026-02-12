extends CanvasLayer

@onready var 效果1: ColorRect = $效果1
@onready var 效果2: ColorRect = $效果2
@onready var 效果3: ColorRect = $效果3

func _ready():
	关闭所有效果()


func _input(event):
	if event.is_action_pressed("数字0"):
		关闭所有效果()
	elif event.is_action_pressed("数字1"):
		开启效果1()
	elif event.is_action_pressed("数字2"):
		开启效果2()
	elif event.is_action_pressed("数字3"):
		开启效果3()

func 关闭所有效果():
	效果1.visible = false
	效果2.visible = false
	效果3.visible = false
	print("已关闭所有效果")

func 开启效果1():
	效果1.visible = true
	效果2.visible = false
	效果3.visible = false
	print("已开启效果1")

func 开启效果2():
	效果1.visible = false
	效果2.visible = true
	效果3.visible = false
	print("已开启效果2")

func 开启效果3():
	效果1.visible = false
	效果2.visible = false
	效果3.visible = true
	print("已开启效果3")
