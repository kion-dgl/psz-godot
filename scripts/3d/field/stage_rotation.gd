class_name StageRotation
## Pure stage-rotation helpers, shared by the field controller and the room
## minimap (previously duplicated in both).
##
## Stage rotation is a LABEL SWAP: a cell's rotation only relabels which gate
## is "north/east/south/west". The floor mesh, waypoints, and objectives all
## stay in stage-local space — never apply a rotation matrix to them. These
## helpers only translate gate/portal *directions*.

const DIRECTIONS := ["north", "east", "south", "west"]


## Relabel a direction by a CW rotation (degrees, multiple of 90).
static func rotate_dir(dir: String, rotation: int) -> String:
	if rotation == 0:
		return dir
	var idx: int = DIRECTIONS.find(dir)
	if idx < 0:
		return dir
	var steps: int = (rotation / 90) % 4
	return DIRECTIONS[(idx + steps) % 4]


## Yaw angle (radians) for a player facing the given cardinal direction.
## Model coordinate convention: east=-X, west=+X, north=-Z, south=+Z
## Player movement: Vector3(sin(rot), 0, cos(rot))
static func dir_to_yaw(dir: String) -> float:
	match dir:
		"north": return PI        # sin(PI)=0,  cos(PI)=-1  → -Z
		"south": return 0.0       # sin(0)=0,   cos(0)=1    → +Z
		"east": return -PI / 2.0  # sin(-PI/2)=-1, cos=0    → -X
		"west": return PI / 2.0   # sin(PI/2)=1,  cos=0     → +X
	return 0.0
