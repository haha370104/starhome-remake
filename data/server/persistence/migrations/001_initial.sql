PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at_unix INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS accounts (
    account_id TEXT PRIMARY KEY,
    account_name TEXT NOT NULL UNIQUE,
    account_status TEXT NOT NULL,
    created_at_unix INTEGER NOT NULL,
    updated_at_unix INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS characters (
    character_id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK (revision >= 0),
    inventory_revision INTEGER NOT NULL CHECK (inventory_revision >= 0),
    inventory_capacity INTEGER NOT NULL CHECK (inventory_capacity > 0),
    max_health INTEGER NOT NULL CHECK (max_health > 0),
    health INTEGER NOT NULL CHECK (health >= 0 AND health <= max_health),
    experience INTEGER NOT NULL CHECK (experience >= 0),
    UNIQUE(account_id, display_name)
);

CREATE TABLE IF NOT EXISTS inventory_stacks (
    stack_id TEXT PRIMARY KEY,
    character_id TEXT NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
    item_definition_id TEXT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    slot_index INTEGER NOT NULL CHECK (slot_index >= 0),
    UNIQUE(character_id, slot_index)
);

CREATE TABLE IF NOT EXISTS vehicles (
    vehicle_id TEXT PRIMARY KEY,
    character_id TEXT NOT NULL UNIQUE REFERENCES characters(character_id) ON DELETE CASCADE,
    vehicle_definition_id TEXT NOT NULL,
    max_health INTEGER NOT NULL CHECK (max_health > 0),
    health INTEGER NOT NULL CHECK (health >= 0 AND health <= max_health),
    reserve_energy_capacity REAL NOT NULL CHECK (reserve_energy_capacity >= 0),
    reserve_energy REAL NOT NULL CHECK (reserve_energy >= 0 AND reserve_energy <= reserve_energy_capacity),
    working_energy_capacity REAL NOT NULL CHECK (working_energy_capacity >= 0),
    working_energy REAL NOT NULL CHECK (working_energy >= 0 AND working_energy <= working_energy_capacity),
    output_power REAL NOT NULL CHECK (output_power >= 0)
);

CREATE TABLE IF NOT EXISTS equipment_slots (
    character_id TEXT NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
    owner_kind TEXT NOT NULL CHECK (owner_kind IN ('character', 'vehicle')),
    slot_id TEXT NOT NULL,
    item_instance_id TEXT NOT NULL UNIQUE,
    item_definition_id TEXT NOT NULL,
    max_durability INTEGER NOT NULL CHECK (max_durability > 0),
    durability INTEGER NOT NULL CHECK (durability >= 0 AND durability <= max_durability),
    upgrade_level INTEGER NOT NULL CHECK (upgrade_level >= 0),
    PRIMARY KEY(character_id, owner_kind, slot_id)
);

CREATE TABLE IF NOT EXISTS character_locations (
    character_id TEXT PRIMARY KEY REFERENCES characters(character_id) ON DELETE CASCADE,
    map_id TEXT NOT NULL,
    map_instance_id TEXT NOT NULL,
    position_x REAL NOT NULL,
    position_y REAL NOT NULL,
    facing_direction INTEGER NOT NULL CHECK (facing_direction BETWEEN 0 AND 7),
    checkpoint_id TEXT NOT NULL,
    updated_at_unix INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS command_receipts (
    command_id TEXT PRIMARY KEY,
    character_id TEXT NOT NULL REFERENCES characters(character_id) ON DELETE CASCADE,
    command_type TEXT NOT NULL,
    result_code TEXT NOT NULL,
    resulting_revision INTEGER NOT NULL,
    created_at_unix INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_inventory_character ON inventory_stacks(character_id);
CREATE INDEX IF NOT EXISTS idx_equipment_character ON equipment_slots(character_id);
CREATE INDEX IF NOT EXISTS idx_location_map_instance ON character_locations(map_instance_id);
