class_name PokemonInstance
extends Resource

## An actual Pokémon -- one you own, at a level and a move
# [PokemonBaseData] is the species; this is the individual.

## Emitted after [method set_level] moves the level
signal levelled_up(new_level: int)

@export_group("Info")
@export var species: PokemonBaseData
@export var nickname: String = ""
@export_range(1, 100, 1) var level: int = 1
@export var experience: int = 0
@export var shiny: bool = false

@export_group("Moves") # only one for now
@export var move: Move
@export var move_cooldown: float


static func generate(species: PokemonBaseData, level: int = 1) -> PokemonInstance:
	var instance := PokemonInstance.new()
	instance.species = species
	instance.level = level
	instance.move = species.learnable_moves[0]
	return instance

var display_name: String:
	get:
		if not nickname.is_empty():
			return nickname
		return species.display_name if species != null else ""

var dex_number: int:
	get: return species.dex_number if species != null else 0

func icon() -> Texture2D:
	return species.icon if species != null else null

func preview() -> Texture2D:
	return species.get_preview(shiny) if species != null else null

func gain_levels(count: int) -> int:
	return level

## The Pokémon's own HP
func actual_max_hp() -> int:
	return species.base_hp + level

func actual_attack() -> int:
	return species.base_attack + level

func actual_speed() -> int:
	return species.base_speed + level

## Advances every move's cooldown. Call it once per frame from whatever runs the
## battle.
func tick(delta: float) -> void:
	move_cooldown += delta

# --- evolution ---------------------------------------------------------------

func evolve(into: PokemonBaseData = null) -> bool:
	if not species.can_evolve():
		return false

	species = into
	return true

# --- copying -----------------------------------------------------------------

## A genuinely independent copy -- new charm, new stones, new move slots. Plain
## [method Resource.duplicate] would share all three with the original.
func duplicate_instance() -> PokemonInstance:
	var copy := PokemonInstance.new()
	copy.species = species
	copy.nickname = nickname
	copy.level = level
	copy.experience = experience
	copy.shiny = shiny
	return copy
