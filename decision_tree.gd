extends Control
class_name DecisionTree


func _on_button_button_up(source: BaseButton) -> void:
	CountryManager.player_country.daily_pp_gain += 1
	source.disabled = true


func _on_button_2_button_up() -> void:
	hide()
