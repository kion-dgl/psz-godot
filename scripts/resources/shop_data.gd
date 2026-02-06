class_name ShopData extends Resource
## Resource definition for shop inventories.

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
## Items: [ { "item": "Monomate", "category": "consumable", "cost": 50, "currency": "Meseta" } ]
@export var items: Array[Dictionary] = []
