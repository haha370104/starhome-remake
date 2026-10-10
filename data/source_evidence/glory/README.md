# Glory Source Evidence

`resource_index.csv` is the recovered Glory download index (18,975 valid files,
638 tombstones). `manifest.json` records its SHA-256, the original file count
and byte total, and the hashes of the small derived evidence files. Run
`python3 tools/audit_glory_archive.py` to compare **actual bytes** in
`../starhome_lz_ry_full/raw/` against every indexed size and MD5. The raw archive
is kept outside the project and is not tracked; Godot does not scan these
original files. This evidence directory also has `.gdignore` so
Godot does not interpret the source index CSV as translations.

The two `*.fcc.cab` files were copied from the FTC expansion of
`NFT_BT/map/RoomSvr1.fcc` (index MD5
`b71362fd4c9cd93192747a5c785aac17`) and `transport.fcc` (index MD5
`67ce142fc06b8a60a9847e7197fa95ed`). The three-row
`equipment_catalog.csv` is the previously materialized Stage-3 equipment
fixture; it is not the missing full catalog. Its SHA-256 is recorded, but
no claim is made that this file alone reconstructs all equipment definitions.
The complete `catalogs_utf8/npc_catalog.csv` and
`catalogs/monsters/glory_monster_map_relations.json` are rebuilt from local raw
NPC data and map FCCs by `python3 tools/build_glory_monster_source_evidence.py`.
The map relations preserve commented editor placements as historical evidence.

The migration compared all 13,895 decoded sprite pairs from the disposable
`starhome_lz_ry_full_parsed/ale_sprites/` cache with
`assets/glory/sprites/`: PNG bytes matched by SHA-256, and frame JSON matched
after parsing while ignoring source-string and formatting differences. Paths
were compared case-insensitively because `assets/` normalizes them to lower
case. No files or path collisions were missing. Needed FTC files are decoded
on demand from workspace-local raw files by `tools/recovery/fcc_workspace.py`;
no persistent FTC cache is required. The ALE decoder is under
`tools/recovery/sprites/`.
