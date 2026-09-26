extends StaticBody2D
## FestivalStall.gd — the offering stall set up in the square on festival days.
##
## Hold a crop, forage find or fish and interact to enter the festival's
## Harvest Offering: the village rewards you with gold, a festival treat and
## friendship with everyone. One entry per festival per year.

const OFFERABLE: Array = ["crop", "forage", "fish"]


func interact(_player: Node) -> void:
	var gm = GameManager.instance
	var festival := Calendar.festival_today()
	if gm == null or festival.is_empty():
		return
	var title: String = festival.get("name", "Festival")

	if Calendar.has_entered_festival(festival["id"]):
		gm.show_dialogue(title, ["Thank you for your offering! Enjoy the festival."])
		return

	var lines: Array = festival.get("intro", []).duplicate()
	var held := gm.get_held_item_id()
	var item := ItemDB.get_item(held)
	if held == "" or not item.get("category", "") in OFFERABLE:
		lines.append("(Hold a crop, forage find or fish in your hotbar, then come back to make your offering.)")
		gm.show_dialogue(title, lines)
		return

	gm.show_dialogue(title, lines, func():
		gm.show_choice(title, "Offer your %s?" % item.get("name", held), ["Offer it", "Not yet"],
			func(i: int):
				if i != 0:
					return
				var result: Dictionary = gm.enter_festival_offering(held)
				gm.show_dialogue(title, result["lines"])
		)
	)
