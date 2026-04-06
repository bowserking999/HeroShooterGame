class_name HeroesRegistry
## Central list of hero IDs. Add new heroes: create .tres in res://heroes/ and register here.

const HERO_IDS: Array[String] = [
	"tank_explosive", "tank_laser",
	"dps_missile", "dps_sniper", "dps_spring",
	"healer_medic", "healer_orb",
]

const HERO_PATHS: Dictionary = {
	"tank_explosive": "res://heroes/tank_explosive.tres",
	"tank_laser": "res://heroes/tank_laser.tres",
	"dps_missile": "res://heroes/dps_missile.tres",
	"dps_sniper": "res://heroes/dps_sniper.tres",
	"dps_spring": "res://heroes/dps_spring.tres",
	"healer_medic": "res://heroes/healer_medic.tres",
	"healer_orb": "res://heroes/healer_orb.tres",
}

## Columns left→right: Tank, DPS, Healing.
static func get_character_select_columns() -> Array:
	return [
		["tank_explosive", "tank_laser"],
		["dps_missile", "dps_sniper", "dps_spring"],
		["healer_medic", "healer_orb"],
	]

static func get_hero(id: String) -> HeroResource:
	if not HERO_PATHS.has(id):
		return null
	return load(HERO_PATHS[id]) as HeroResource

static func get_all_hero_ids() -> Array:
	return HERO_IDS.duplicate()
