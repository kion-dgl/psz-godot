extends RefCounted
## Exact unsigned 32-bit product as [high, low] limbs.

static func multiply(a: int, b: int) -> Array:
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
