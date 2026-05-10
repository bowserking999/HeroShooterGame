class_name HeroesRegistry
## Central list of hero IDs. Add new heroes: create .tres in res://heroes/ and register here.

const HERO_IDS: Array[String] = [
	"tank_explosive", "tank_laser",
	"dps_missile", "dps_sniper", "dps_spring",
	"healer_medic", "healer_orb",
]

const HERO_ID_SPRING := "dps_spring"

const HERO_PATHS: Dictionary = {
	"tank_explosive": "res://heroes/tank_explosive.tres",
	"tank_laser": "res://heroes/tank_laser.tres",
	"dps_missile": "res://heroes/dps_missile.tres",
	"dps_sniper": "res://heroes/dps_sniper.tres",
	"dps_spring": "res://heroes/dps_spring.tres",
	"healer_medic": "res://heroes/healer_medic.tres",
	"healer_orb": "res://heroes/healer_orb.tres",
}

## Columns left→right: Tank, DPS, Healing. Pass `include_spring` false for match / non-debug pickers.
static func get_character_select_columns(include_spring: bool = true) -> Array:
	var dps_col: Array[String] = ["dps_missile", "dps_sniper"]
	if include_spring:
		dps_col.append(HERO_ID_SPRING)
	return [
		["tank_explosive", "tank_laser"],
		dps_col,
		["healer_medic", "healer_orb"],
	]


## Hero IDs for the world `HeroOption` dropdown (same order as [member HERO_IDS] minus Spring when `include_spring` is false).
static func get_world_menu_hero_ids(include_spring: bool) -> Array[String]:
	var out: Array[String] = []
	for hid in HERO_IDS:
		if hid == HERO_ID_SPRING and not include_spring:
			continue
		out.append(hid)
	return out


## 0 = tank, 1 = damage, 2 = healer; -1 if unknown.
static func hero_role_slot(hero_id: String) -> int:
	var h: String = str(hero_id)
	if h.begins_with("tank_"):
		return 0
	if h.begins_with("dps_"):
		return 1
	if h.begins_with("healer_"):
		return 2
	return -1

static func get_hero(id: String) -> HeroResource:
	if not HERO_PATHS.has(id):
		return null
	return load(HERO_PATHS[id]) as HeroResource

static func get_all_hero_ids() -> Array:
	return HERO_IDS.duplicate()
