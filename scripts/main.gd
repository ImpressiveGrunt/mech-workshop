extends Node
## Entry point: hand off to the workshop hub.


func _ready() -> void:
    GameState.go_to.call_deferred("workshop")
