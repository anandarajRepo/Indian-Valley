extends StaticBody2D
class_name Bed
## Bed.gd — interact to sleep, ending the day.
##
## Player walks up to the bed and presses Interact. Sleeping triggers the
## overnight sequence (shipping sales, crop growth, save, day summary).

func interact(_player: Node) -> void:
	if GameManager.instance:
		GameManager.instance.show_dialogue(
			"Bed",
			["Go to sleep and end the day?"],
			func(): GameClock._trigger_sleep()
		)
	else:
		GameClock._trigger_sleep()
