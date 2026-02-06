class_name PhotonArtData extends Resource
## Resource definition for photon arts (special attacks/techniques).

@export var id: String = ""
@export var name: String = ""
@export var weapon_type: String = ""
@export var class_type: String = ""  # Hunter, Ranger, Force
@export var attack_mod: float = 0.0
@export var accuracy_mod: float = 0.0
@export var pp_cost: int = 0
@export var targets: int = 1
@export var hit_range: float = 0.0
@export var area: float = 0.0
@export var hits: int = 1
@export var notes: String = ""
