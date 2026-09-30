@tool
extends RefCounted
## Layered dependency layout. Virtual vertices reserve lanes for long edges;
## they never become GraphNodes or alter the underlying fact connections.

const COLUMN_GAP := 88.0
const ROW_GAP := 36.0
const COMPONENT_GAP := 96.0

var vertices: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var routes: Array[PackedVector2Array] = []


func arrange(nodes: Array[GraphNode], connections: Array[Dictionary]) -> Array[PackedVector2Array]:
	vertices.clear()
	edges.clear()
	routes.clear()
	var ids: Dictionary = {}
	var neighbors: Array = []
	for node in nodes:
		ids[node] = vertices.size()
		vertices.append({ "node": node, "size": node.size, "pos": Vector2.ZERO, "rank": 0 })
		neighbors.append([])
	for connection in connections:
		var source: GoapBaseGraphNode = connection.from
		var target: GoapBaseGraphNode = connection.to
		var output := source.fact_port(connection.fact, true)
		var input := target.fact_port(connection.fact, false)
		if output < 0 or input < 0:
			continue
		var a: int = ids[source]
		var b: int = ids[target]
		edges.append(
			{
				"from": a,
				"to": b,
				"out": source.get_output_port_position(output),
				"in": target.get_input_port_position(input),
				"via": []
			}
		)
		neighbors[a].append(b)
		neighbors[b].append(a)
	var visited: Dictionary = {}
	var top := 0.0
	for id in nodes.size():
		if visited.has(id):
			continue
		var component: Array[int] = [id]
		visited[id] = true
		var cursor := 0
		while cursor < component.size():
			for next: int in neighbors[component[cursor]]:
				if not visited.has(next):
					visited[next] = true
					component.append(next)
			cursor += 1
		component.sort()
		top = _arrange_component(component, top) + COMPONENT_GAP
	return routes


func _arrange_component(component: Array[int], top: float) -> float:
	var members: Dictionary = {}
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	for id in component:
		members[id] = true
		incoming[id] = 0
		outgoing[id] = []
	var local_edges: Array[Dictionary] = []
	for edge in edges:
		if not members.has(edge.from):
			continue
		local_edges.append(edge)
		if not outgoing[edge.from].has(edge.to):
			outgoing[edge.from].append(edge.to)
			incoming[edge.to] += 1
	var queue: Array[int] = []
	for id in component:
		if incoming[id] == 0:
			queue.append(id)
	var placed: Dictionary = {}
	var cursor := 0
	while placed.size() < component.size():
		if cursor == queue.size():
			# Break ordering cycles deterministically, retaining their actual edges.
			for id in component:
				if not placed.has(id):
					queue.append(id)
					break
		var id := queue[cursor]
		cursor += 1
		placed[id] = true
		for next: int in outgoing[id]:
			if placed.has(next):
				continue
			vertices[next].rank = maxi(vertices[next].rank, vertices[id].rank + 1)
			incoming[next] -= 1
			if incoming[next] == 0:
				queue.append(next)
	var columns: Array = []
	for id in component:
		var rank: int = vertices[id].rank
		while columns.size() <= rank:
			columns.append([])
		columns[rank].append(id)
	var segments: Array[Dictionary] = []
	for edge in local_edges:
		var previous: int = edge.from
		var offset: float = edge.out.y
		for rank in range(vertices[previous].rank + 1, vertices[edge.to].rank):
			var dummy := vertices.size()
			vertices.append(
				{ "node": null, "size": Vector2(0, 16), "pos": Vector2.ZERO, "rank": rank }
			)
			columns[rank].append(dummy)
			edge.via.append(dummy)
			segments.append({ "from": previous, "to": dummy, "out": offset, "in": 8.0 })
			previous = dummy
			offset = 8.0
		if vertices[edge.to].rank > vertices[edge.from].rank:
			segments.append({ "from": previous, "to": edge.to, "out": offset, "in": edge.in.y })
	var x := 0.0
	var widths: Array[float] = []
	for column: Array in columns:
		var width := 0.0
		var y := 0.0
		for id: int in column:
			vertices[id].pos = Vector2(x, y)
			y += vertices[id].size.y + ROW_GAP
			width = maxf(width, vertices[id].size.x)
		widths.append(width)
		x += width + COLUMN_GAP
	# Alternate barycenter ordering, then refine alignment without changing order.
	for sweep in 8:
		for direction in [1, -1]:
			var start: int = 1 if direction == 1 else columns.size() - 2
			var end: int = columns.size() if direction == 1 else -1
			for rank in range(start, end, direction):
				_align_column(columns[rank], segments, direction, sweep < 4)
	var minimum := INF
	var maximum := -INF
	for column: Array in columns:
		for id: int in column:
			minimum = minf(minimum, vertices[id].pos.y)
			maximum = maxf(maximum, vertices[id].pos.y + vertices[id].size.y)
	for column: Array in columns:
		for id: int in column:
			vertices[id].pos.y += top - minimum
			var node: GraphNode = vertices[id].node
			if node != null:
				node.position_offset = vertices[id].pos
	var bottom := top + maximum - minimum
	var lane_counts: Dictionary = {}
	var lane_indices: Dictionary = {}
	for edge in local_edges:
		for rank in range(vertices[edge.from].rank, vertices[edge.to].rank):
			lane_counts[rank] = lane_counts.get(rank, 0) + 1
	for edge in local_edges:
		var a: Dictionary = vertices[edge.from]
		var b: Dictionary = vertices[edge.to]
		var source: Vector2 = a.pos + edge.out
		var target: Vector2 = b.pos + edge.in
		var points := PackedVector2Array([source])
		if b.rank <= a.rank:
			# Feedback links run below this component, outside the node columns.
			bottom += 24.0
			var right: float = a.pos.x + widths[a.rank] + COLUMN_GAP * 0.5
			var left: float = b.pos.x - COLUMN_GAP * 0.5
			points.append_array(
				PackedVector2Array(
					[
						Vector2(right, source.y),
						Vector2(right, bottom),
						Vector2(left, bottom),
						Vector2(left, target.y),
						target
					]
				)
			)
		else:
			var previous := source
			var previous_rank: int = a.rank
			for dummy: int in edge.via:
				var vertex: Dictionary = vertices[dummy]
				var entry: Vector2 = vertex.pos + Vector2(0, 8)
				_append_step(
					points,
					previous,
					entry,
					columns,
					widths,
					previous_rank,
					lane_counts,
					lane_indices
				)
				previous = entry + Vector2(widths[vertex.rank], 0)
				points.append(previous)
				previous_rank = vertex.rank
			_append_step(
				points,
				previous,
				target,
				columns,
				widths,
				previous_rank,
				lane_counts,
				lane_indices
			)
		routes.append(points)
	return bottom


func _append_step(
	points: PackedVector2Array,
	source: Vector2,
	target: Vector2,
	columns: Array,
	widths: Array[float],
	rank: int,
	counts: Dictionary,
	indices: Dictionary
) -> void:
	# Distinct tracks keep unrelated vertical wires from merging into one trunk.
	var index: int = indices.get(rank, 0)
	indices[rank] = index + 1
	var spacing := minf(14.0, (COLUMN_GAP - 32.0) / maxf(counts[rank] - 1, 1))
	var lane: float = COLUMN_GAP * 0.5 + (index - (counts[rank] - 1) * 0.5) * spacing
	var turn: float = vertices[columns[rank][0]].pos.x + widths[rank] + lane
	points.append_array(
		PackedVector2Array([Vector2(turn, source.y), Vector2(turn, target.y), target])
	)


func _align_column(
	column: Array,
	segments: Array[Dictionary],
	direction: int,
	reorder: bool
) -> void:
	var desired: Dictionary = {}
	var order: Dictionary = {}
	for id: int in column:
		order[id] = order.size()
		var total := 0.0
		var count := 0
		for edge in segments:
			if direction == 1 and edge.to == id:
				total += vertices[edge.from].pos.y + edge.out - edge.in
				count += 1
			elif direction == -1 and edge.from == id:
				total += vertices[edge.to].pos.y + edge.in - edge.out
				count += 1
		desired[id] = total / count if count > 0 else vertices[id].pos.y
	if reorder:
		column.sort_custom(
			func(a: int, b: int) -> bool:
				var ay: float = desired[a] + vertices[a].size.y * 0.5
				var by: float = desired[b] + vertices[b].size.y * 0.5
				return order[a] < order[b] if is_equal_approx(ay, by) else ay < by
		)
	# Isotonic regression finds the closest non-overlapping positions. Unlike
	# pushing everything down, it keeps parents centered on their branches.
	var blocks: Array[Dictionary] = []
	var offsets: Array[float] = []
	var offset := 0.0
	for index in column.size():
		var id: int = column[index]
		offsets.append(offset)
		blocks.append({ "start": index, "end": index, "sum": desired[id] - offset, "count": 1 })
		while blocks.size() > 1:
			var last: Dictionary = blocks[-1]
			var before: Dictionary = blocks[-2]
			if before.sum / before.count <= last.sum / last.count:
				break
			before.end = last.end
			before.sum += last.sum
			before.count += last.count
			blocks.pop_back()
		offset += vertices[id].size.y + ROW_GAP
	for block in blocks:
		for index in range(block.start, block.end + 1):
			vertices[column[index]].pos.y = block.sum / block.count + offsets[index]
