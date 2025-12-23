extends Button

@export var decision_tree: DecisionTree


func _on_button_up() -> void:
	decision_tree.show()
	MainClock.time_scale = 0
