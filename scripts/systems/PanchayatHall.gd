extends StaticBody2D
## PanchayatHall.gd — the crumbling village hall in Viralpadi's square.
##
## Interact to open the offering baskets (bundles). The first visit tells the
## Hall's story. Once every basket is filled the Hall is shown restored.

const COLOR_RUINED:   Color = Color(0.42, 0.40, 0.36)
const COLOR_RESTORED: Color = Color(0.85, 0.72, 0.45)

const INTRO: Array = [
	"The Panchayat Hall. Its walls are cracked and its lamps have been dark for years.",
	"Six empty baskets sit beneath a faded painting of the Vanam Thay, Mother of the Forest.",
	"Paati says: fill them with what the valley gives — and she may come home.",
]


func _ready() -> void:
	refresh()
	if GameManager.instance:
		GameManager.instance.hall_changed.connect(refresh)


func refresh() -> void:
	var gm = GameManager.instance
	var restored: bool = gm != null and gm.hall_state.get("restored", false)
	var body := get_node_or_null("HallSprite") as Polygon2D
	if body:
		body.color = COLOR_RESTORED if restored else COLOR_RUINED


func interact(_player: Node) -> void:
	var gm = GameManager.instance
	if gm == null:
		return
	if not gm.hall_state.get("intro_seen", false):
		gm.hall_state["intro_seen"] = true
		gm.show_dialogue("Panchayat Hall", INTRO, func(): gm.open_hall())
	else:
		gm.open_hall()
