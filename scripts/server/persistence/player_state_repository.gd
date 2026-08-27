class_name PlayerStateRepository
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")


## Initializes storage and applies supported schema migrations.
## Returns success or a stable storage/migration failure.
func initialize() -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository initialize is not implemented")


## Creates one new [param state] aggregate atomically.
## [param state] Validated player aggregate whose character ID must not exist.
## Returns a defensive copy of committed state or a conflict/storage failure.
func create_player(state: PlayerStateRecord) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository create is not implemented")


## Loads the player aggregate identified by [param character_id].
## [param character_id] Stable character identity, never a client-supplied account credential.
## Returns an isolated typed record or a stable not-found/storage failure.
func load_player(character_id: String) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository load is not implemented")


## Saves [param state] only at [param expected_revision].
## [param state] Complete aggregate candidate validated before commit.
## [param expected_revision] Revision observed by the caller for optimistic concurrency.
## Returns committed state with incremented revision or a conflict/storage failure.
func save_player(state: PlayerStateRecord, expected_revision: int) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository save is not implemented")


## Runs [param operation] against one isolated [param character_id] aggregate.
## [param character_id] Existing character loaded within the transaction boundary.
## [param operation] Callable receiving a mutable copy and returning `DomainResult`.
## Returns committed state, or rolls back on callback/validation/storage failure.
## Design: Implementations must not publish an in-memory mutation before durable commit succeeds.
func transact_player(character_id: String, operation: Callable) -> DomainResult:
	return DomainResult.failure(&"persistence.repository_not_implemented", "repository transaction is not implemented")


## Reports the schema version currently materialized by this repository.
## Returns zero before initialization or the latest applied version afterward.
func current_schema_version() -> int:
	return 0
