extends RefCounted
## Survival pacing in simulated seconds, shared by actors, resources and actions.

# Start the first cooking demonstration with enough time to gather both ingredients.
const INITIAL_SATIETY := 60.0
const HUNGER_RATE := 1.0
# Hunger and thirst drain at the same rate in simulated seconds.
const HUNGER_THRESHOLD := 50.0
const STARVATION_THRESHOLD := 12.0
const RESPAWN_SECONDS := 5.0
const RAW_NUTRITION := 38.0
const COOKED_NUTRITION := 65.0
const INITIAL_HYDRATION := 100.0
const THIRST_RATE := 1.0
const THIRST_THRESHOLD := 50.0
const DEHYDRATION_THRESHOLD := 15.0
const WATER_RESTORATION := 70.0
const SPRING_RESPAWN_SECONDS := Vector2(25.0, 35.0)
const STONE_RESPAWN_SECONDS := Vector2(45.0, 60.0)
const WEAPON_DURABILITY := 10
const AGENT_HEALTH := 20
const DEPRIVATION_DAMAGE_PER_SECOND := 1.0
const LOW_HEALTH_THRESHOLD := 10
const RECOVERED_HEALTH := 16
const RAW_HEAL := 4
const COOKED_HEAL := 7
const CAMP_SAFE_RADIUS := 4.5
const FLEE_START_RADIUS := 6.0
# A gap beyond melee range gives the actor time to eat before the monster closes in.
const FLEE_END_RADIUS := 8.0
# Leave a little room beyond the observed safety boundary before ending a flee.
const FLEE_CLEAR_RADIUS := 9.0
const FLEE_SPEED_MULTIPLIER := 1.5
const CAMP_RESOURCE_CLEARANCE := 10.0
const MONSTER_HEALTH := 72
const MONSTER_DAMAGE := 2
const MONSTER_SPEED := 2.2
const MONSTER_SIGHT_RADIUS := 18.0
const MONSTER_ATTACK_RANGE := 2.4
const MONSTER_ATTACK_SECONDS := 1.5
const FIRST_MONSTER_SECONDS := Vector2(90.0, 120.0)
# A full supply interval starts AFTER combat, never while a monster is alive.
const MONSTER_SPAWN_SECONDS := Vector2(60.0, 90.0)
const MAX_MONSTERS := 1
const MONSTER_SPAWN_CLEARANCE := 10.0
const UNARMED_DAMAGE := 1
const WEAPON_DAMAGE := 2
const WEAPON_ANIMAL_DAMAGE := 2
const HARVEST_HIT_SECONDS := 0.65

# One tree per actor supports both cooking and tool making after regrowth.
# Food remains available so a timber shortage can be solved by eating raw meat.
# Each harvest samples a fresh delay in simulated seconds.
const TREE_RESPAWN_SECONDS := Vector2(30.0, 45.0)
const ANIMAL_RESPAWN_SECONDS := Vector2(20.0, 30.0)
const FIRE_SECONDS := 30.0
const FIRE_RELIGHT_THRESHOLD := 8.0
