# starhome_remake

Godot 4 remake prototype of the FancyBoxII client. The default scene is an
interactive reconstruction of 易安港基地大厅一层.

## Run

Open `project.godot` with Godot 4.7.2, or run the project from the command line.
The window is freely resizable: HUD pixels stay fixed while a larger viewport
reveals more of the map.

When using Godot's embedded game view, select `Stretch to Fit` from its size
menu. This controls the editor preview container only; runtime pixels remain
1:1, the HUD keeps its designed size, and larger windows reveal more map area.

## Multiplayer development run

The editor and the default project launch stay in explicit offline-debug mode.
To run the current server-authoritative two-player slice, start one headless
server and then launch the client command twice:

```powershell
$godot = "C:\path\to\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path . scenes/server/dedicated_server.tscn -- --port=24680
& $godot --path . -- --online --server-host=127.0.0.1 --server-port=24680
& $godot --path . -- --online --server-host=127.0.0.1 --server-port=24680
```

Each client receives its entity ID and map instance from the server handshake;
the exported local IDs are only offline-preview defaults. The production-like
loopback integration uses three independent Godot processes and can be run with:

```powershell
& .\tools\run_enet_integration.ps1 -GodotExecutable $godot
```

That check covers two distinct entities, continuous snapshot replication,
request rejection isolation, reconnect-token recovery, and removal after the
second disconnect grace period.

The Stage-2 world route follows the recovered Glory topology instead of a
synthetic shortcut: `RoomSvr1 -> City1Svr -> D04`. City and D04 are loaded from
business-named Glory assets and swapped only after authoritative `MapJoined`.
The shared player anchor keeps its position ownership across the swap: halls and
the city project a human character, while D04 projects the eight-way starter
combat vehicle and restores the human view when returning to the city.
The independent real-ENet transition check is:

```powershell
& .\tools\run_enet_map_transition_integration.ps1 -GodotExecutable $godot
```

It verifies the reliable transition command, strict join payload, authoritative
spawn, atomic map ownership transfer, and post-transfer snapshot isolation.

## Runtime architecture

- `scripts/main_hall.gd`: the current migration baseline. It still owns scene
  construction, input routing, NPC interaction, HUD wiring, and part of the
  multiplayer/map presentation flow; it is not yet an orchestration-only entry
  point.
- Current client ownership: `LocalPlayerController` is the sole writer of local
  target, route, direction, prediction sequence, and player position.
  `ActiveWorldController` atomically swaps map, navigation, entities, player
  presentation, camera, and HUD map state; `HallHud` exposes semantic methods
  instead of internal Controls.
- `scripts/navigation/diamond_navigation.gd`: map-configured diamond collision,
  eight-way A*, line-of-sight checks, nearest-walkable fallback, and path
  string-pulling. The current Glory hall uses a 41×320 grid.
- `scripts/characters/`: layered body, equipment, shadow, and name rendering.
- `scripts/npcs/`: configurable patrol base plus shop and quest behavior subclasses.
- `scripts/ui/hall_hud.gd`: viewport-anchored top menu, minimap, shortcut bar,
  weapon slots, and interaction popup.
- `scripts/world/y_sorted_prop.gd`: scene props sorted against actors by their
  floor-contact Y coordinate.

Runtime `Dictionary` values are permitted at JSON and RPC boundaries only.
Loaders and adapters must validate them and hand typed definitions, commands,
or presentation bundles to internal modules. NPC shops/quests will be server
interaction services rather than behavior encoded in character-node subclasses.
`AuthoritativeServer` remains a compatibility facade while map transfer,
sessions, simulation scheduling, and RPC routing are extracted incrementally.

The mandatory refactor order is R0 through R8: baseline/commit gate,
composition regression tests, local-player ownership, active-world ownership,
typed data entry, semantic HUD, server-facade decomposition, NPC boundaries,
then resource caching and `.tscn` scene composition. See
`docs/code_review_2026-08-27.md` and `docs/development_roadmap.md`.

Stage 3 currently has versioned Glory-backed content definitions, vehicle and
monster lifecycle rules, an authoritative energy-cannon module, presentation
assets, D04 vehicle projection, and focused tests. It is still in progress: these foundations are not
yet a complete real-session, two-client combat loop with AI, projectiles,
drops, and skill experience.

The persistence boundary now includes typed player aggregates, a repository
contract, schema migrations, and a transactional development file repository.
Production SQLite is intentionally not claimed until a pinned Godot 4
GDExtension driver and its concrete repository adapter are installed and tested.

See `assets/README.md` for the business-oriented asset layout and binary asset
version-control policy. See `使用说明.md` for reverse-engineering and gameplay
implementation details.

The offline FCC/ALE/PKH map reconstruction pipeline, including the exact
navigation record format and Godot coordinate transform, is documented in
`docs/map_resource_pipeline.md`. `tools/map_pipeline/extract_navigation.py`
reproduces the collision extraction with an explicitly selected client DLL.

The selected free-version HUD composition, minimap chrome, individual toolbar
buttons, and the separate reserve/working energy displays are documented in
`docs/free_hud_rendering.md`. This is the project's only cross-version asset
exception: non-HUD assets remain Glory-only.

Hall NPC instances and their triangle patrol routes live in
`data/npcs/yian_harbor_hall_floor_1.json`; see `data/npcs/README.md` for the
extension contract.

## Canonical source version

All non-HUD assets added from now on must come from the 荣耀版
(`starhome_lz_ry`) resource set. The free version (`starhome_lz_fr`) is allowed
only for the top bar, bottom bar/shortcut bar, and minimap chrome listed in
`docs/free_hud_rendering.md`; minimap map images and popup-window contents are
not included. The battle version (`starhome_jznp`) remains research-only.

See `PROJECT_CONTEXT.md` for the persistent project-wide source paths and rules.
Imported files must also be renamed into the remake's business vocabulary;
original `pic`/`pic2`, timestamp, hash, and client class-name paths are not
allowed under `assets/`.

Run `tools/check_asset_conventions.ps1` after importing assets to reject legacy
path segments and runtime references before committing.

The complete local gate is:

```powershell
& .\tools\run_project_checks.ps1 -GodotExecutable $godot
```

Every commit must stay within 20 changed paths and 2000 total text additions
plus deletions. Check `git diff --cached --name-only` and
`git diff --cached --numstat`; do not combine bulk assets, offline extraction
outputs, runtime code, and architecture refactors in one commit.
