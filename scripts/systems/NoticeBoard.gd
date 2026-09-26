extends StaticBody2D
## NoticeBoard.gd — the town notice board where villagers pin requests.
##
## Interact to read today's request; if you're carrying everything asked for,
## you can deliver it on the spot (see the Quests autoload).


func interact(_player: Node) -> void:
	var gm = GameManager.instance
	if gm == null:
		return
	if not Quests.has_active():
		var lines: Array = ["The notice board is empty today. Check back tomorrow morning."]
		if not Quests.last_expired.is_empty():
			lines.push_front("A faded note: %s's request went unanswered." %
				Relationships.get_name_of(Quests.last_expired.get("npc_id", "")))
			Quests.last_expired = {}
		gm.show_dialogue("Notice board", lines)
		return

	var inv = gm.get_active_inventory()
	if not Quests.can_deliver(inv):
		gm.show_dialogue("Notice board", [Quests.describe()])
		return
	gm.show_choice("Notice board", Quests.describe(), ["Deliver", "Not now"], func(i: int):
		if i == 0:
			gm.show_dialogue("Notice board", Quests.deliver(inv)["lines"]))
