@tool
extends RefCounted
## The example's fact vocabulary. Use these keys in providers, actions and goals.
## Runtime resource identities use the factory functions below.

const HUNGRY: StringName = &"hungry"
const STARVING: StringName = &"starving"
const THIRSTY: StringName = &"thirsty"
const DEHYDRATED: StringName = &"dehydrated"
const HAS_WATER: StringName = &"has_water"
const HAS_RAW_MEAT: StringName = &"has_raw_meat"
const HAS_COOKED_MEAT: StringName = &"has_cooked_meat"
const HAS_WOOD: StringName = &"has_wood"
const HAS_STONE: StringName = &"has_stone"
const HAS_WEAPON: StringName = &"has_weapon"
const CAN_TEND_FIRE: StringName = &"can_tend_fire"
const CAMP_HAS_WOOD: StringName = &"camp_has_wood"
const CAMP_HAS_STONE: StringName = &"camp_has_stone"
const HAS_FIRE: StringName = &"has_fire"
const FIRE_STABLE: StringName = &"fire_stable"
const FIRE_LOW: StringName = &"fire_low"
const HAS_MONSTER: StringName = &"has_monster"
const LOW_HEALTH: StringName = &"low_health"
const IN_DANGER: StringName = &"in_danger"
const AT_CAMP: StringName = &"at_camp"
const NEEDS_REST: StringName = &"needs_rest"
const STOCKPILE_FULL: StringName = &"stockpile_full"
const CARRYING_SUPPLIES: StringName = &"carrying_supplies"


static func inventory(key: StringName) -> StringName:
	return StringName("has_%s" % key)


static func available(signature: String) -> StringName:
	return StringName("item_available:" + signature)


static func harvest_available(kind: StringName, method: StringName, signatures: PackedStringArray) -> StringName:
	var sorted := signatures.duplicate()
	sorted.sort()
	return StringName("auto:%s:%s:%s" % [String(kind).uri_encode(), String(method).uri_encode(), "+".join(sorted)])
