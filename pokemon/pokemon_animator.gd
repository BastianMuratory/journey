class_name PokemonAnimator
extends Node

## Procedural, Pokémon-Quest-style animation for a rigless mesh.
##
## The models in this project are single static [code].obj[/code] meshes with no
## skeleton, so nothing can be keyframed. Instead this node drives one pivot
## [Node3D] every frame with position, rotation and squash-and-stretch scale --
## which is very close to how Pokémon Quest itself animates its voxel creatures.
##
## It never touches the Pokémon's gameplay transform. It owns a dedicated pivot
## node whose rest pose is known, so movement code and this can coexist:
## [codeblock]
## PokemonModel      (Node3D)        <- gameplay moves this
## └── AnimPivot     (Node3D)        <- this animator owns it, exclusively
##     └── Model     (MeshInstance3D)
## [/codeblock]
##
## Usage is deliberately blunt:
## [codeblock]
## animator.moving = true      # swap the looping idle for the run cycle
## animator.attack()           # one-shots play over the loop, then hand back
## animator.take_hit()
## animator.spin(2)
## await animator.animation_finished
## [/codeblock]

## Emitted when a one-shot ([constant Anim.ATTACK], [constant Anim.HIT],
## [constant Anim.SPIN]) ends and the looping animation takes back over.
signal animation_finished(anim: Anim)

enum Anim {
	## Looping. Wobble in place -- style depends on body type.
	IDLE,
	## Looping. Step cycle -- style depends on body type.
	RUN,
	## One-shot. Wind up, lunge, recover.
	ATTACK,
	## One-shot. Knocked back, squashed, shaken, with a white flash.
	HIT,
	## One-shot. Whips around its own axis, leaning out of the turn.
	SPIN,
}

## Base cycle lengths in seconds, before [member speed_scale] is applied.
const ATTACK_TIME := 0.52
const HIT_TIME := 0.42
const SPIN_TIME := 0.55

## Wing beats per second, idling and flying. One phase drives both the wings and
## the body's bob, so a creature never bobs against its own stroke.
const IDLE_BEAT := 1.6
const RUN_BEAT := 2.4

@export_group("Target")
## The pivot this animator owns. Everything is written relative to
## [member rest_position], so the pivot must not be moved by anything else.
## Assigning it starts the animation -- children run [method Node._ready] before
## their parent does, so this is usually set from outside, after our own _ready
## has already been and gone.
@export var target: Node3D:
	set(value):
		target = value
		set_process(target != null)
## Pivot pose with no animation applied. [PokemonModel] sets this so the creature
## rotates around its feet (or its middle, if it flies).
@export var rest_position := Vector3.ZERO
## Mesh that gets the white flash on [method take_hit]. Optional.
@export var flash_target: GeometryInstance3D

@export_group("Tuning")
## Decides which idle and run style plays.
@export var body_type: PokemonData.BodyType = PokemonData.BodyType.QUADRUPED
## The creature's world-space height. Every offset is expressed as a fraction of
## this, so a Caterpie and an Onix wobble by the same *relative* amount.
@export var height := 1.0:
	set(value):
		height = maxf(value, 0.001)
## Multiplies every animation's tempo.
@export_range(0.25, 3.0, 0.05) var speed_scale := 1.0
## Multiplies how far every animation moves.
@export_range(0.0, 3.0, 0.05) var amplitude := 1.0
## Resting altitude for HOVER and FLYER, in multiples of [member height].
@export var hover_height := 0.0
## Set false if the white hit flash fights your art style.
@export var flash_on_hit := true

@export_group("Wings")
## The wing-bending material, handed over by [PokemonModel] for species that
## have wings. While this is set the animator writes the stroke into it every
## frame, and stops faking the beat with whole-body squash. Null means wingless,
## which is the case for everything but the flyers.
@export var wing_material: ShaderMaterial:
	set(value):
		wing_material = value
		if value == null:
			_wing_fold = 0.0
			_wing_twist = 0.0
		else:
			_write_wings()
## The same bend for the additive flash pass. Without it the flash would sit on
## the wings' rest pose while the wings themselves are mid-stroke.
@export var wing_flash_material: ShaderMaterial
## Whether the wings beat either side of rest or fold shut and open again.
@export var wing_motion: PokemonData.WingMotion = PokemonData.WingMotion.FLAP
## How far the wings travel, in radians: half the stroke when flapping, the whole
## closed angle when folding. Set from [member PokemonData.flap_degrees].
@export var flap_radians := 0.0
## How far the wing feathers as it moves, in radians.
@export var twist_radians := 0.0

## Which looping animation plays when no one-shot is running.
var loop: Anim = Anim.IDLE:
	set(value):
		if value != Anim.IDLE and value != Anim.RUN:
			push_warning("PokemonAnimator: loop must be IDLE or RUN.")
			return
		loop = value

## Convenience over [member loop] for movement code that only knows "am I
## walking or not".
var moving: bool:
	get: return loop == Anim.RUN
	set(value): loop = Anim.RUN if value else Anim.IDLE

## The one-shot currently playing, or [constant Anim.IDLE] when none is.
var current_one_shot: Anim = Anim.IDLE

## True while an attack, hit or spin is playing.
var is_one_shot_playing: bool:
	get: return _shot_active

# --- loop state ---
var _phase := 0.0
## Wing beat, integrated rather than derived from [member _phase], so that going
## from idle to flying speeds the beat up instead of jumping it.
var _wing_phase := 0.0
var _wing_fold := 0.0
var _wing_twist := 0.0

# --- one-shot state ---
var _shot_active := false
var _shot_elapsed := 0.0
var _shot_duration := 0.0
var _spin_turns := 1.0

# --- pose accumulators, reused every frame so nothing allocates ---
var _off := Vector3.ZERO
var _rot := Vector3.ZERO
var _scl := Vector3.ONE
var _blend := 0.0

var _flash_material: StandardMaterial3D


func _ready() -> void:
	# Desync creatures spawned on the same frame, otherwise a whole field of
	# them wobbles in lockstep and reads as one object.
	_phase = randf() * 100.0
	set_process(target != null)


func _process(delta: float) -> void:
	if target == null:
		set_process(false)
		return

	var dt := delta * speed_scale
	_phase += dt
	# Beats faster in flight, and keeps beating through a one-shot -- a bird
	# lunging at something does not stop flying to do it.
	var beat_rate := RUN_BEAT if (loop == Anim.RUN or _shot_active) else IDLE_BEAT
	_wing_phase = fposmod(_wing_phase + dt * TAU * beat_rate, TAU)

	# 1. One-shot first: it reports how hard it wants to suppress the loop.
	var shot_off := Vector3.ZERO
	var shot_rot := Vector3.ZERO
	var shot_scl := Vector3.ONE
	_blend = 0.0

	if _shot_active:
		_shot_elapsed += dt
		var k := clampf(_shot_elapsed / maxf(_shot_duration, 0.0001), 0.0, 1.0)
		_reset_pose()
		match current_one_shot:
			Anim.ATTACK: _pose_attack(k)
			Anim.HIT: _pose_hit(k)
			Anim.SPIN: _pose_spin(k)
		shot_off = _off
		shot_rot = _rot
		shot_scl = _scl
		if _shot_elapsed >= _shot_duration:
			_end_one_shot()

	# 2. Loop pose, faded out by however much the one-shot took over.
	_reset_pose()
	match loop:
		Anim.RUN: _pose_run(_phase)
		_: _pose_idle(_phase)

	var keep := 1.0 - _blend
	target.position = rest_position + _off * keep + shot_off
	target.rotation = _rot * keep + shot_rot
	target.scale = Vector3.ONE.lerp(_scl, keep) * shot_scl

	# 3. Wings run underneath all of that: they are the mesh deforming, not the
	# pivot moving, so nothing above interferes with them.
	if wing_material != null:
		_pose_wings()


# ---------------------------------------------------------------- public API

## Copies body type and per-species tuning off a [PokemonData]. [param world_height]
## is the mesh's height after [member PokemonData.model_scale], which the caller
## already knows.
func configure(data: PokemonData, world_height: float) -> void:
	if data == null:
		return
	body_type = data.body_type
	speed_scale = data.anim_speed_scale
	amplitude = data.anim_amplitude
	hover_height = data.hover_height
	height = world_height
	wing_motion = data.wing_motion
	flap_radians = deg_to_rad(data.flap_degrees)
	twist_radians = deg_to_rad(data.flap_twist_degrees)


## Back to the looping idle, cancelling any one-shot.
func play_idle() -> void:
	loop = Anim.IDLE
	_cancel_one_shot()


## Switch the loop to the run cycle. Does not cancel a one-shot -- an attack
## started mid-run finishes, then the run resumes.
func play_run() -> void:
	loop = Anim.RUN


## Wind up and lunge. Returns to the current loop when done.
func attack() -> void:
	_start_one_shot(Anim.ATTACK, ATTACK_TIME)


## Recoil, squash and shake, with a white flash if [member flash_on_hit].
## Interrupts whatever one-shot was playing -- getting hit always wins.
func take_hit() -> void:
	_start_one_shot(Anim.HIT, HIT_TIME)


## Whip around the vertical axis. [param turns] full rotations, and grounded
## species hop while they do it.
func spin(turns := 1.0) -> void:
	_spin_turns = maxf(turns, 0.1)
	_start_one_shot(Anim.SPIN, SPIN_TIME * _spin_turns)


## Drops the creature back to its exact rest pose and stops updating. Use before
## handing the transform to something else, like a cutscene or the evolution VFX.
func stop() -> void:
	_cancel_one_shot()
	set_process(false)
	if target != null:
		target.position = rest_position
		target.rotation = Vector3.ZERO
		target.scale = Vector3.ONE
	_set_flash(0.0)
	# Wings out flat too, so a cutscene or the evolution VFX inherits a pose it
	# can predict rather than whatever half-stroke it interrupted.
	_wing_fold = 0.0
	_wing_twist = 0.0
	_write_wings()


## Resumes after [method stop].
func resume() -> void:
	set_process(target != null)


# ------------------------------------------------------------ looping poses

func _pose_idle(t: float) -> void:
	var a := amplitude
	var h := height
	# Declared up front rather than per branch: match arms are sibling scopes and
	# reusing one name across them is a trap that only shows up at parse time.
	var w := 0.0
	var s := 0.0
	var beat := 0.0

	match body_type:
		PokemonData.BodyType.BIPED:
			# Top-heavy: breathes vertically and sways a little on its feet.
			w = t * TAU * 0.55
			s = sin(w)
			_off.y = s * 0.030 * h * a
			_scl = _squash(s * 0.045 * a)
			_rot.z = sin(w * 0.5) * deg_to_rad(3.0) * a
			_rot.y = sin(w * 0.37) * deg_to_rad(2.5) * a

		PokemonData.BodyType.QUADRUPED:
			# Wider stance, so less sway and a shallower breath.
			w = t * TAU * 0.48
			s = sin(w)
			_off.y = s * 0.022 * h * a
			_scl = _squash(s * 0.040 * a)
			_rot.x = sin(w * 0.5) * deg_to_rad(2.5) * a
			_rot.y = sin(w * 0.29) * deg_to_rad(2.0) * a

		PokemonData.BodyType.HOVER:
			# Never lands, so no squash at all -- it just drifts.
			w = t * TAU * 0.32
			_off.y = hover_height * h + sin(w) * 0.055 * h * a
			_off.x = sin(w * 0.63) * 0.045 * h * a
			_rot.z = sin(w * 0.63) * deg_to_rad(4.0) * a
			_rot.y = sin(w * 0.31) * deg_to_rad(6.0) * a

		PokemonData.BodyType.FLYER:
			# Slow bank riding on a much faster wing beat.
			w = t * TAU * 0.28
			beat = _wing_phase
			_off.y = hover_height * h + sin(w) * 0.035 * h * a + sin(beat) * 0.045 * h * a
			if wing_material == null:
				# No wings to bend, so the beat is faked on the whole body:
				# it pulls in on the downstroke and spreads on the up.
				_scl = Vector3(1.0 - sin(beat) * 0.05 * a, 1.0 + sin(beat) * 0.03 * a, 1.0)
			_rot.z = sin(w * 0.7) * deg_to_rad(5.0) * a
			_rot.y = sin(w * 0.41) * deg_to_rad(4.0) * a

		PokemonData.BodyType.SERPENTINE:
			# A slow S travelling down the body, faked with offset yaw and roll.
			w = t * TAU * 0.40
			_off.y = hover_height * h + sin(w) * 0.025 * h * a
			_rot.y = sin(w) * deg_to_rad(6.0) * a
			_rot.z = sin(w + PI * 0.5) * deg_to_rad(5.0) * a
			_scl = _squash(sin(w * 0.5) * 0.030 * a)


func _pose_run(t: float) -> void:
	var a := amplitude
	var h := height
	var w := 0.0
	var bounce := 0.0
	var beat := 0.0

	match body_type:
		PokemonData.BodyType.BIPED:
			# Rolls left and right over each planted foot.
			w = t * TAU * 1.30
			bounce = absf(sin(w))               # two footfalls per roll cycle
			_rot.z = sin(w) * deg_to_rad(13.0) * a
			_rot.y = sin(w) * deg_to_rad(4.0) * a
			_rot.x = _lean(9.0)
			_off.y = bounce * 0.090 * h * a
			# Stretched at the top of the hop, squashed on contact.
			_scl = _squash((bounce - 0.5) * 0.18 * a)

		PokemonData.BodyType.QUADRUPED:
			# Rocks front to back instead, like a bounding animal.
			w = t * TAU * 1.45
			bounce = absf(sin(w))
			_rot.x = sin(w) * deg_to_rad(9.0) * a + _lean(6.0)
			_rot.z = sin(w * 0.5) * deg_to_rad(3.0) * a
			_off.y = bounce * 0.065 * h * a
			_off.z = sin(w) * 0.030 * h * a
			_scl = _squash((bounce - 0.5) * 0.15 * a)

		PokemonData.BodyType.HOVER:
			# No footfalls, so it leans into the drift and banks instead.
			w = t * TAU * 0.85
			_off.y = hover_height * h + sin(w) * 0.045 * h * a
			_off.x = sin(w * 0.5) * 0.030 * h * a
			_rot.x = _lean(10.0)
			_rot.z = sin(w * 0.5) * deg_to_rad(6.0) * a
			_rot.y = sin(w * 0.5) * deg_to_rad(4.0) * a

		PokemonData.BodyType.FLYER:
			# Hard forward lean and a wing beat you can actually count.
			w = t * TAU * 0.60
			beat = _wing_phase
			_off.y = hover_height * h + sin(beat) * 0.085 * h * a
			_rot.x = _lean(15.0)
			_rot.z = sin(w) * deg_to_rad(10.0) * a
			_rot.y = sin(w) * deg_to_rad(5.0) * a
			if wing_material == null:
				_scl = Vector3(1.0 - sin(beat) * 0.09 * a, 1.0 + sin(beat) * 0.05 * a, 1.0)

		PokemonData.BodyType.SERPENTINE:
			# Slithers: the yaw wave leads, the roll follows a beat behind.
			w = t * TAU * 1.05
			_off.y = hover_height * h + absf(sin(w)) * 0.045 * h * a
			_rot.y = sin(w) * deg_to_rad(16.0) * a
			_rot.z = sin(w - 1.0) * deg_to_rad(10.0) * a
			_rot.x = _lean(5.0)


## The wing stroke, written into the shader that bends the mesh.
func _pose_wings() -> void:
	if wing_motion == PokemonData.WingMotion.FOLD:
		_pose_fold()
	else:
		_pose_flap()
	_write_wings()


## Beating: a stroke either side of rest.
##
## A plain sine reads as a metronome, so a second harmonic goes in to make the
## downstroke quicker than the recovery -- the asymmetry is most of what makes a
## wing beat look like a wing beat. The twist runs a quarter cycle behind, so the
## wing is flattest where it moves fastest and feathers as it turns over.
func _pose_flap() -> void:
	var stroke := (sin(_wing_phase) + 0.15 * sin(_wing_phase * 2.0)) / 1.08
	# Negative, so the wings are at the bottom of the stroke exactly when the
	# FLYER poses have the body at the top of its bob. Lift comes from the
	# downstroke; wings rising while the body rises reads as a creature being
	# lifted by something else.
	_wing_fold = -flap_radians * stroke * amplitude
	_wing_twist = twist_radians * cos(_wing_phase) * amplitude


## Folding: shut and open again, resting open.
##
## A raised cosine rather than a sine, so the cycle starts and ends at exactly
## zero -- fully open -- with the closed pose in the middle. A sine would leave
## the wings half shut at rest and fold them inside out on the way past.
func _pose_fold() -> void:
	var shut := 0.5 - 0.5 * cos(_wing_phase)
	_wing_fold = flap_radians * shut * amplitude
	# Peaks halfway shut and unwinds by the time it is open again, so the wing
	# rolls as it closes instead of arriving twisted.
	_wing_twist = twist_radians * sin(_wing_phase) * amplitude


func _write_wings() -> void:
	if wing_material != null:
		wing_material.set_shader_parameter("fold", _wing_fold)
		wing_material.set_shader_parameter("twist", _wing_twist)
	# The flash pass has to agree with the pass underneath it, always.
	if wing_flash_material != null:
		wing_flash_material.set_shader_parameter("fold", _wing_fold)
		wing_flash_material.set_shader_parameter("twist", _wing_twist)


# ----------------------------------------------------------- one-shot poses

func _pose_attack(k: float) -> void:
	var a := amplitude
	var h := height

	# One scalar drives the whole move: negative while winding up, +1 at the
	# strike, back to 0 on the recovery. Everything else reads off it.
	var reach := 0.0
	if k < 0.30:
		reach = -0.30 * smoothstep(0.0, 1.0, _seg(k, 0.0, 0.30))
	elif k < 0.52:
		reach = lerpf(-0.30, 1.0, smoothstep(0.0, 1.0, _seg(k, 0.30, 0.52)))
	else:
		reach = lerpf(1.0, 0.0, smoothstep(0.0, 1.0, _seg(k, 0.52, 1.0)))

	var strike := maxf(reach, 0.0)

	# -Z is forward in Godot, so a positive reach moves the creature at its target.
	_off.z = -reach * 0.35 * h * a
	_off.y = hover_height * h
	_rot.x = _lean(reach * 22.0 * a)
	_scl = _squash(reach * 0.14 * a)

	match body_type:
		PokemonData.BodyType.FLYER, PokemonData.BodyType.HOVER:
			# Swoops down into the hit rather than hopping into it.
			_off.y -= strike * 0.18 * h * a
			_rot.x = _lean(reach * 30.0 * a)
		PokemonData.BodyType.SERPENTINE:
			# Coils away, then whips through with the head leading.
			_rot.y = -reach * deg_to_rad(28.0) * a
			_rot.z = reach * deg_to_rad(14.0) * a
		_:
			# Grounded species get a small hop out of the lunge.
			_off.y += strike * 0.10 * h * a

	_blend = minf(absf(reach) * 1.4, 1.0)


func _pose_hit(k: float) -> void:
	var a := amplitude
	var h := height

	# Snaps to full impact in the first frames, then decays back out.
	var impact := smoothstep(0.0, 1.0, _seg(k, 0.0, 0.08)) * exp(-k * 6.0)

	# +Z is backward: shoved away from whatever hit it.
	_off.z = impact * 0.28 * h * a
	_off.y = hover_height * h
	_rot.x = impact * deg_to_rad(22.0) * a
	_scl = _squash(-impact * 0.22 * a)

	# High-frequency rattle on top, dying with the impact.
	_off.x = sin(k * 90.0) * impact * 0.055 * h * a
	_rot.z = sin(k * 70.0) * impact * deg_to_rad(8.0) * a

	if body_type == PokemonData.BodyType.FLYER or body_type == PokemonData.BodyType.HOVER:
		# Knocked off its cushion of air, then recovers altitude.
		_off.y -= impact * 0.12 * h * a

	_blend = minf(impact * 1.6, 1.0)
	_set_flash(impact)


func _pose_spin(k: float) -> void:
	var a := amplitude
	var h := height

	# Every term below is shaped so it is back at zero when k reaches 1. A spin
	# that ends mid-crouch would snap upright on the frame the loop resumes.
	var turn := smoothstep(0.0, 1.0, _seg(k, 0.12, 0.88))       # the rotation itself
	var arc := sin(PI * _seg(k, 0.12, 0.88))                    # peaks mid-spin
	var crouch := sin(PI * _seg(k, 0.0, 0.30))                  # anticipation, resolves
	var land := sin(PI * _seg(k, 0.80, 1.0))                    # landing dip, resolves

	# Winds back the wrong way first, then unwinds through the full turns. A whole
	# number of turns lands exactly where it started, so the yaw hands back clean.
	_rot.y = TAU * _spin_turns * turn - deg_to_rad(35.0) * crouch * a
	# Leans out of the turn, like it's being flung by its own momentum.
	_rot.z = arc * deg_to_rad(12.0) * a
	_off.y = hover_height * h

	if body_type == PokemonData.BodyType.FLYER or body_type == PokemonData.BodyType.HOVER:
		# Already airborne -- it climbs slightly instead of hopping.
		_off.y += arc * 0.06 * h * a
		_scl = _squash(arc * 0.05 * a)
	else:
		_off.y += arc * 0.12 * h * a
		# Crouch, stretch through the spin, then squash on the landing.
		_scl = _squash(-crouch * 0.10 * a + arc * 0.08 * a - land * 0.10 * a)

	_blend = smoothstep(0.0, 1.0, _seg(k, 0.0, 0.10)) \
		* (1.0 - smoothstep(0.0, 1.0, _seg(k, 0.86, 1.0)))


# ------------------------------------------------------------------ helpers

## Volume-preserving squash and stretch. Positive stretches vertically and pulls
## the sides in; negative does the opposite. This is what sells the whole style.
static func _squash(amount: float) -> Vector3:
	# Floored well above zero: a negative Y scale would turn the mesh inside out.
	var y := maxf(1.0 + amount, 0.05)
	var xz := 1.0 / sqrt(y)
	return Vector3(xz, y, xz)


## Forward lean in degrees, converted to the rotation Godot actually wants.
## Forward is -Z, so leaning the top forward is a *negative* pitch.
static func _lean(degrees: float) -> float:
	return -deg_to_rad(degrees)


## Normalised progress through the [param from]..[param to] slice of a one-shot.
static func _seg(k: float, from: float, to: float) -> float:
	return clampf((k - from) / maxf(to - from, 0.0001), 0.0, 1.0)


func _reset_pose() -> void:
	_off = Vector3.ZERO
	_rot = Vector3.ZERO
	_scl = Vector3.ONE


func _start_one_shot(anim: Anim, duration: float) -> void:
	current_one_shot = anim
	_shot_active = true
	_shot_elapsed = 0.0
	_shot_duration = duration
	set_process(target != null)


func _end_one_shot() -> void:
	var finished := current_one_shot
	_shot_active = false
	current_one_shot = Anim.IDLE
	_set_flash(0.0)
	animation_finished.emit(finished)


func _cancel_one_shot() -> void:
	if not _shot_active:
		return
	_shot_active = false
	current_one_shot = Anim.IDLE
	_set_flash(0.0)


## Additive white overlay. Uses [member GeometryInstance3D.material_overlay] so
## the mesh's own imported .mtl material is left completely alone.
##
## Winged species flash through [member wing_flash_material] instead, because an
## overlay is a second draw of the same mesh with its own vertex stage: an
## ordinary white overlay would flash the wings where they are resting, not where
## they actually are.
func _set_flash(strength: float) -> void:
	if not flash_on_hit or flash_target == null:
		return

	if wing_flash_material != null:
		var alpha := clampf(strength, 0.0, 1.0) * 0.75
		wing_flash_material.set_shader_parameter("flash_color", Color(1.0, 1.0, 1.0, alpha))
		flash_target.material_overlay = wing_flash_material if alpha > 0.0 else null
		return

	if strength <= 0.001:
		if _flash_material != null:
			flash_target.material_overlay = null
		return

	if _flash_material == null:
		_flash_material = StandardMaterial3D.new()
		_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_material.albedo_color = Color.WHITE

	_flash_material.albedo_color.a = clampf(strength, 0.0, 1.0) * 0.75
	if flash_target.material_overlay != _flash_material:
		flash_target.material_overlay = _flash_material
