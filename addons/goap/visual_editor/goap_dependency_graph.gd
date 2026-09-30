@tool
extends GraphEdit

var routes: Array[PackedVector2Array] = []


func _get_connection_line(from_position: Vector2, to_position: Vector2) -> PackedVector2Array:
	var source := from_position / zoom
	var target := to_position / zoom
	for route in routes:
		if route[0].distance_squared_to(source) < 1.0 and route[-1].distance_squared_to(
			target
		) < 1.0:
			return _rounded_line(route)
	return PackedVector2Array([from_position, to_position])


func _rounded_line(route: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in route:
		if points.is_empty() or not point.is_equal_approx(points[-1]):
			points.append(point)
	var result := PackedVector2Array([points[0] * zoom])
	for index in range(1, points.size() - 1):
		var corner := points[index]
		var before := points[index - 1] - corner
		var after := points[index + 1] - corner
		var radius := minf(12.0, minf(before.length(), after.length()) * 0.5)
		var start := corner + before.normalized() * radius
		var end := corner + after.normalized() * radius
		result.append(start * zoom)
		for step in range(1, 6):
			var t := step / 5.0
			result.append((start.lerp(corner, t).lerp(corner.lerp(end, t), t)) * zoom)
	result.append(points[-1] * zoom)
	return result
