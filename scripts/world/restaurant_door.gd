extends Area3D

# Script for the exit door inside restaurant interiors.
# Detection is handled via body_entered signal connected in RestaurantManager.

func _ready() -> void:
	collision_layer = 0
	collision_mask = 3
