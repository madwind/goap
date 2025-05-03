extends Node3D

class_name GoapVisionCone3DMarkers

@export var mark_nodes: Array[Node3D]
var markers: Array[Marker3D]


func _ready() -> void:
	markers = []
	for mark_node in mark_nodes:
		var marker := Marker3D.new()
		markers.append(marker)
		mark_node.add_child(marker)
