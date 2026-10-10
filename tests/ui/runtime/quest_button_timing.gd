extends RefCounted

static var enabled := false
static var samples: Dictionary = {}

static func reset() -> void:
	samples.clear()
	enabled = true

static func record(label: String, elapsed_usec: int) -> void:
	if not enabled: return
	if not samples.has(label): samples[label] = {"calls": 0, "total_usec": 0}
	samples[label].calls += 1
	samples[label].total_usec += elapsed_usec

static func finish() -> Dictionary:
	enabled = false
	return samples.duplicate(true)
