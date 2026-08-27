class_name MapTransition
extends RefCounted

enum Kind {
	STANDARD,
	MULTI_CHOICE,
	CLIENT_POINT,
	CLIENT_LINE,
}

var transition_id: StringName
var kind: Kind = Kind.STANDARD
var enabled := true
var label := ""
var source_anchor := Vector2.ZERO
var approach_point := Vector2.ZERO
var destination_map_id: StringName
var destination_legacy_code := ""
var destination_entry_number := 0
var destination_landing_point := Vector2.ZERO
var has_destination_landing_point := false
var external_target := false
var presentation: Dictionary = {}
var source_audit: Dictionary = {}


## Performs the `destination_key` operation.
## Returns the resolved string value.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func destination_key() -> String:
	if not destination_map_id.is_empty():
		return String(destination_map_id)
	return destination_legacy_code.to_lower()


## Performs the `kind_name` operation.
## Returns the resolved string value.
## Design: Keeps runtime map semantics separate from legacy source-audit metadata.
func kind_name() -> String:
	match kind:
		Kind.MULTI_CHOICE:
			return "multi_choice"
		Kind.CLIENT_POINT:
			return "client_point"
		Kind.CLIENT_LINE:
			return "client_line"
		_:
			return "standard"
