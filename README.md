# starhome_remake

Godot 4 remake prototype of the FancyBoxII client. The default scene is an
interactive reconstruction of 易安港基地大厅一层.

## Run

Open `project.godot` with Godot 4.7.2, or run the project from the command line.
The window is freely resizable: HUD pixels stay fixed while a larger viewport
reveals more of the map.

## Runtime architecture

- `scripts/main_hall.gd`: scene orchestration and player interaction only.
- `scripts/navigation/diamond_navigation.gd`: native 35×280 diamond collision,
  eight-way A*, line-of-sight checks, and path string-pulling.
- `scripts/characters/`: layered body, equipment, shadow, and name rendering.
- `scripts/ui/hall_hud.gd`: viewport-anchored top menu, minimap, shortcut bar,
  weapon slots, and interaction popup.
- `scripts/world/y_sorted_prop.gd`: scene props sorted against actors by their
  floor-contact Y coordinate.

See `assets/README.md` for the business-oriented asset layout and binary asset
version-control policy. See `使用说明.md` for reverse-engineering and gameplay
implementation details.
