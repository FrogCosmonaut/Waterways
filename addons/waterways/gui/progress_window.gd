# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
class_name _WaterwaysProgressWindow
extends Window

@onready var _progress_bar: ProgressBar = %ProgressBar


func _ready() -> void:
	hide()


func show_progress(message: String, progress: float) -> void:
	title = message
	_progress_bar.value = progress
