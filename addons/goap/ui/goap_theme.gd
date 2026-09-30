class_name GoapTheme

const COLOR_SUCCESS = Color(0.36, 0.82, 0.38, 0.4)
const COLOR_PENDING = Color(0.5, 0.5, 0.8, 0.4)
const COLOR_ACTIVE = Color(1.0, 0.9, 0.1, 0.4)


static func definition_script(definition: RefCounted) -> Script:
	return definition.get_script()
