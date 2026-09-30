extends RefCounted
## One place to compare urgency. Resource availability belongs to actions.

const ESCAPE := 300.0
const DEHYDRATION := 260.0
const STARVATION := 250.0
const RECOVERY := 230.0
const DEFENSE := 100.0
const THIRST := 55.0
const HUNGER := 40.0
const FIRE := 20.0
const WEAPON := 12.0
const STOW := 10.0
# Collection and its deposit have equal urgency so pickup does not interrupt delivery.
const STOCK := STOW
const REST := 5.0
