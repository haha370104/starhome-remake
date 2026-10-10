[data/source_evidence/glory/map_recovery/maps/](starhome-remake/starhome-remake/data/source_evidence/glory/map_recovery/maps/) 主要是由 [starhome_lz_ry_full/raw/](starhome-remake/starhome-remake/starhome_lz_ry_full/raw/) 中的地图 FCC 和图片解析而来；生成时还会读取已解析的 `assets/glory/sprites/`。所以它**源于 raw，但不是只读取 raw 就直接得到的目录**。

**原则上可重建，目前不能当作已验证可随时删除的缓存。** 现有按需生成器仍要读取这个目录里的 `map_metadata.json` 和 `transitions.json`；我尚未验证从空目录出发重建全部 497 个地图版本的流程。
