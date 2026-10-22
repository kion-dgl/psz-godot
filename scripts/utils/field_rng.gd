class_name FieldRng
extends RefCounted
## The field-generation RNG: the Nintendo 64-bit LCG (the Pokemon Gen 4/5
## constants), distinct from the combat RNG in psz_rng.gd.
## Source: data/re_reference/level_generation_algorithm.json (identity
## confirmed by recovering 44/44 per-room seeds across five savestates and
## 17/17 on two out-of-sample fields):
##   state = (state * 0x5D588B656C078965 + 0x269EC3) mod 2^64
##   draw(range) = range == 0 ? state >> 32 : (((state >> 32) * range) >> 32)
## The field is a deterministic function of the state at the instant the
## guild counter confirms the area (the state advances continuously while the
## game runs; nothing is clock-seeded).
##
## State is kept as two 32-bit halves; the 64x64 advance is composed from
## 32x32 limb products so no 64-bit overflow behavior is assumed. Verified
## against the Python mirror by scripts/tools/field_rng_check.py vectors.

const MULTIPLIER_LO := 0x6C078965
const MULTIPLIER_HI := 0x5D588B65
const INCREMENT := 0x269EC3

var _lo := 0
var _hi := 0


func _init(seed_lo: int = 0, seed_hi: int = 0) -> void:
	_lo = seed_lo & 0xFFFFFFFF
	_hi = seed_hi & 0xFFFFFFFF


func get_state_lo() -> int:
	return _lo


func get_state_hi() -> int:
	return _hi


func set_state(lo: int, hi: int) -> void:
	_lo = lo & 0xFFFFFFFF
	_hi = hi & 0xFFFFFFFF


## Bounded draw in [0, range); range 0 returns the raw high word.
func draw(range: int) -> int:
	_advance()
	if range == 0:
		return _hi
	return _mul32_to_64(_hi, range)[0]


## 32x32 -> 64 multiply as [hi32, lo32]; every intermediate stays under 2^34.
static func _mul32_to_64(a: int, b: int) -> Array:
	var al := a & 0xFFFF
	var ah := a >> 16
	var bl := b & 0xFFFF
	var bh := b >> 16
	var ll := al * bl
	var mid := ah * bl + al * bh
	var hh := ah * bh
	var lo_carry := (mid & 0xFFFF) + (ll >> 16)
	var lo := ((lo_carry & 0xFFFF) << 16) | (ll & 0xFFFF)
	var hi := hh + (mid >> 16) + (lo_carry >> 16)
	return [hi, lo]


func _advance() -> void:
	# state * M + C (mod 2^64), limbs:
	# product = s_lo*m_lo + (s_lo*m_hi + s_hi*m_lo) << 32 + (s_hi*m_hi) << 64.
	# The << 64 term drops mod 2^64; of the cross terms only their low 32
	# bits survive the shift (their carry lands at bit 64+ and drops too).
	var ll := _mul32_to_64(_lo, MULTIPLIER_LO)
	var lh := _mul32_to_64(_lo, MULTIPLIER_HI)
	var hl := _mul32_to_64(_hi, MULTIPLIER_LO)
	var lo := ll[1] + INCREMENT
	var carry := lo >> 32
	var hi := ll[0] + carry + ((lh[1] + hl[1]) & 0xFFFFFFFF)
	_lo = lo & 0xFFFFFFFF
	_hi = hi & 0xFFFFFFFF
