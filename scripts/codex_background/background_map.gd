extends ArenaMap
## Existing combat repositions also call Main.map directly; use the same prop bounds.
var kit: CodexBackgroundKit

func is_blocked(p: Vector3) -> bool:
	return super.is_blocked(p) or (kit != null and kit.blocked(p))

func push_out(p: Vector3, r: float) -> Vector3:
	return kit.push_circle(super.push_out(p, r), r) if kit else super.push_out(p, r)

func push_out_feet(p: Vector3, r: float, feet: float, climb := STEP) -> Vector3:
	return kit.push_circle(super.push_out_feet(p, r, feet, climb), r) if kit else super.push_out_feet(p, r, feet, climb)
