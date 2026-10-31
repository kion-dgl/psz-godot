class_name PszRng
extends RefCounted
## Byte-exact port of the PSZ bounded RNG.
## Source: pszm-decomp src/arm9/FUN_0203e874.c (state advance + bounded draw),
## FUN_02045d84.c (percentage roll), FUN_02045d5c.c (range roll).
##
## State is three words [s0, s1, s2]; only s0 evolves:
##   acc = s2 + s1 * s0 (mod 2^64); s0 = acc
##   bounded(n) = high32(high32(acc) * n), or high32(acc) when n == 0
##   percent(pct) = bounded(100) < pct (strict), clamped at 0/100
##   range(lo, hi) = hi > lo ? lo + bounded(hi - lo) : lo
##
## All arithmetic goes through 32/16-bit limbs so nothing depends on 64-bit
## overflow behavior. Seeds must fit 32 bits each (the original seeds its
## state from 32-bit sources). Verified against the Python reference in
## scripts/tools/psz_rng_reference.py by scripts/tools/psz_rng_check.gd.

var _s0_lo := 0
var _s0_hi := 0
var _s1 := 0
var _s2 := 0


func _init(seed0: int = 0, seed1: int = 0, seed2: int = 0) -> void:
	_s0_lo = seed0 & 0xFFFFFFFF
	_s0_hi = 0
	_s1 = seed1 & 0xFFFFFFFF
	_s2 = seed2 & 0xFFFFFFFF


## Bounded draw in [0, n); n must fit 32 bits. n == 0 returns the raw high
## word (original behavior).
func bounded(n: int) -> int:
	assert(n >= 0 and n <= 0xFFFFFFFF)
	return _advance_bounded(n)


## Percentage roll, 0..100; matches the original's strict `roll < pct` form.
func percent(pct: int) -> bool:
	if pct >= 100:
		return true
	if pct <= 0:
		return false
	return _advance_bounded(100) < pct


## Random value in [lo, hi]; returns lo when hi <= lo (original behavior).
func range(lo: int, hi: int) -> int:
	if hi > lo:
		return lo + _advance_bounded(hi - lo)
	return lo


func _advance_bounded(n: int) -> int:
	# acc = s2 + s1 * s0 (mod 2^64), kept as two 32-bit halves.
	var pl := _mul32_to_64(_s1, _s0_lo)
	var ph := _mul32_to_64(_s1, _s0_hi)
	var lo: int = int(pl[1]) + _s2
	var hi: int = int(pl[0]) + (lo >> 32) + (int(ph[1]) & 0xFFFFFFFF)
	_s0_lo = lo & 0xFFFFFFFF
	_s0_hi = hi & 0xFFFFFFFF
	if n == 0:
		return _s0_hi
	return _mul32_to_64(_s0_hi, n)[0]


## 32x32 -> 64 multiply as [hi32, lo32]; limb math keeps every intermediate
## below 2^34 so signed 64-bit ints never overflow.
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
