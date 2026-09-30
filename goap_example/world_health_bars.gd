extends Control
## Screen-space health bars for resources and monsters.

const Balance = preload("res://goap_example/survival/balance.gd")
const BAR_SIZE := Vector2(88.0, 6.0)

var world: Node3D
var bars: Dictionary = {}
var background_style: StyleBoxFlat
var resource_fill: StyleBoxFlat
var monster_fill: StyleBoxFlat


func _ready() -> void:
	background_style = _style(Color(0.12, 0.16, 0.19, 0.9))
	resource_fill = _style(Color(0.32, 0.72, 0.59))
	monster_fill = _style(Color(0.77, 0.36, 0.37))


func _process(_delta: float) -> void:
	if not is_instance_valid(world):
		return
	var active: Dictionary = {}
	for resource in world.resources:
		if not is_instance_valid(resource) or resource.is_queued_for_deletion():
			continue
		if resource.item != null:
			continue # Ground drops are collectible, not harvestable health targets.
		active[resource] = true
		_update_bar(resource, resource.health, resource.max_health(), resource.available, false)
	for monster in world.monsters:
		if not is_instance_valid(monster) or monster.is_queued_for_deletion():
			continue
		active[monster] = true
		_update_bar(monster, monster.health, Balance.MONSTER_HEALTH, monster.health > 0, true)
	for target in bars.keys():
		if not active.has(target):
			bars[target].queue_free()
			bars.erase(target)


func _update_bar(target: Node3D, health: int, maximum: int, available: bool, monster: bool) -> void:
	var bar: ProgressBar = bars.get(target)
	if bar == null:
		bar = ProgressBar.new()
		bar.custom_minimum_size = BAR_SIZE
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_font_size_override("font_size", 1)
		bar.add_theme_stylebox_override("background", background_style)
		bar.add_theme_stylebox_override("fill", monster_fill if monster else resource_fill)
		add_child(bar)
		bar.size = BAR_SIZE
		bars[target] = bar
	bar.max_value = maximum
	bar.value = health
	var caption := target.get_node("Caption") as Label3D
	var anchor: Vector3 = caption.global_position
	var camera: Camera3D = world.camera
	var screen_position := camera.unproject_position(anchor)
	bar.visible = available and not camera.is_position_behind(anchor) and get_viewport_rect().has_point(screen_position)
	if bar.visible:
		bar.position = screen_position - Vector2(BAR_SIZE.x * 0.5, 24.0)


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	style.set_corner_radius_all(4)
	return style
