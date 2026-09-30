@tool
extends VBoxContainer
## Editor-only presentation of a remote session's numeric snapshot.

signal reset_requested

var reset_button: Button
var sample_note: Label
var metric_labels: Dictionary = {}


func _ready() -> void:
	name = "Performance"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 14)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	add_child(header)
	var title := Label.new()
	title.text = "Session performance"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	reset_button = Button.new()
	reset_button.text = "Reset samples"
	reset_button.tooltip_text = "Reset this session's performance samples. Running plans and Agent observation continue."
	reset_button.pressed.connect(func() -> void: reset_requested.emit())
	header.add_child(reset_button)
	sample_note = Label.new()
	sample_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(sample_note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 20)
	scroll.add_child(column)
	var sections := GoapPerformanceStatistics.sections()
	for title_text in sections:
		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", 8)
		column.add_child(section)
		var heading := Label.new()
		heading.text = title_text
		section.add_child(heading)
		section.add_child(HSeparator.new())
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		grid.add_theme_constant_override("v_separation", 8)
		section.add_child(grid)
		for key in sections[title_text]:
			var caption := Label.new()
			caption.text = sections[title_text][key]
			caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(caption)
			var value := Label.new()
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(value)
			metric_labels[key] = value
	display_snapshot({}, false)


func display_snapshot(metrics: Dictionary, connected: bool) -> void:
	reset_button.disabled = not connected or metrics.is_empty()
	if not connected:
		sample_note.text = "Run the project from Godot (F5 / F6) to view performance. No game HUD or selected Agent is required."
	elif metrics.is_empty():
		sample_note.text = "Waiting for performance data from the running project."
	else:
		sample_note.text = "All Agents in this session · %.1f s since reset · %d scheduler frames\nTimes use the real clock. Response includes queueing; candidates count completed requests." % [metrics.get("elapsed_sec", 0.0), metrics.get("frames", 0)]
	var values := GoapPerformanceStatistics.display_values(metrics if connected else {})
	for key in values:
		metric_labels[key].text = values[key]
		metric_labels[key].tooltip_text = values[key]
