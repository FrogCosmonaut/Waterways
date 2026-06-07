@tool
class_name _WaterwaysProgressReporter
extends RefCounted
## Reports progress of bakes so the editor shows a progress bar.
## WaterwaysRiver and WaterwaysSystem each own one as their
## `progress` property instead of declaring the signal and helpers themselves.

signal progress_notified(percentage: float, message: String)

var _owner: Node

# bookkeeping for an active relay (see chain_from / end_chain).
var _chained_source: _WaterwaysProgressReporter = null
var _chained_callback: Callable


func _init(owner: Node) -> void:
	_owner = owner


## Emit a progress update.
func report(percentage: float, message: String) -> void:
	progress_notified.emit(percentage, message)


## Emit a progress update and yield a frame so the progress window shows ok.
func report_and_wait(percentage: float, message: String) -> void:
	progress_notified.emit(percentage, message)
	await _owner.get_tree().process_frame


## Thread-safe progress update, for emitting from the WorkerThreadPool task.
func report_deferred(percentage: float, message: String) -> void:
	call_deferred("report", percentage, message)


## Relays every update from [param source] into this reporter, remapped into the
## [param base]..[param base] + [param span] window and prefixed with [param prefix].
## Call [method end_chain] once the chaine finish.
func chain_from(source: _WaterwaysProgressReporter, base: float, span: float, prefix: String) -> void:
	_chained_source = source
	_chained_callback = func(percentage: float, message: String) -> void:
		report(base + span * percentage / 100.0, prefix + message)
	source.progress_notified.connect(_chained_callback)


## Disconnects the relay started by [method chain_from].
func end_chain() -> void:
	if _chained_source and _chained_source.progress_notified.is_connected(_chained_callback):
		_chained_source.progress_notified.disconnect(_chained_callback)
	_chained_source = null
