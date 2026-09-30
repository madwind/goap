@tool
extends EditorExportPlugin


## Keep only cost-model scripts readable when the preset compiles other scripts.
## Runtime inspection remains authoritative, including rejection of unsafe models.
func _get_name() -> String:
	# Godot sorts export hooks by name. Run before its GDScript compiler,
	# whose skip() otherwise prevents later hooks from seeing the source file.
	return "00GoapCostModelSource"


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if not path.ends_with(".gd"):
		return
	var script := load(path) as GDScript
	while script != null:
		if script == GoapCostModel:
			add_file(path, FileAccess.get_file_as_bytes(path), false)
			skip()
			return
		script = script.get_base_script() as GDScript
