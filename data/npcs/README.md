# NPC configuration

Each map owns an NPC list. `yian_harbor_hall_floor_1.json` currently defines
all nine hall NPCs without hard-coding individuals in the scene script.

An NPC entry contains:

- `id`, `name`, `appearance`, and `kind` (`shop`, `quest`, or `ambient`).
- `spawn`: its initial world-space foot position.
- `patrol.speed`, `patrol.animation_speed_scale`, and `patrol.initial_delay`.
  The current hall NPCs use 203 px/s and animation scale 1.0 (14 FPS), matching
  the player's current presentation through independent NPC configuration.
- Three ordered `patrol.points`; each point has a world-space `position` and a
  random `dwell` range in seconds. The base class loops these points.
- `interaction.body` and `interaction.actions` for the popup.

Runtime behavior is separated from configuration:

- `scripts/npcs/npc_base.gd` owns navigation, waiting, animation direction,
  interaction pausing, and the overridable action interface.
- `shop_npc.gd` and `quest_npc.gd` override the default actions and action
  handler. Add another subclass and register its `kind` in
  `MainHall._create_npc_for_kind()` for future NPC capabilities.

Patrol positions must be walkable in the native map collision grid. Runtime has
a nearest-walkable fallback for robustness, while validation requires checked-in
configuration points to be valid without using that fallback.
