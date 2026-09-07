# 怪物名称、血条与阴影核对（2026-09-07）

## 本次布局调整

- 名称字号、颜色和悬浮显示规则不变，相对原位置下移 3px。名称下沿与血条上沿的间距从 4px 改为 1px。
- 怪物血条由 50px 增加 20% 至 60px，位置仍是实体脚点下方 20px，水平中心为实体 x 坐标，左右各延伸 30px。
- 未调整战车的血条/蓝条，也不按当前血量改变整个条框的中心位置。

## 独立阴影核对

| 怪物 | 荣耀目录与当前映射 | 核对结果 |
| --- | --- | --- |
| 奥姆虫 | 三种动作分别有独立阴影 | 节点、贴图和三态八向切换均存在 |
| 奥姆幼虫 | 三态共用 `CHN_2005_06_28_18_39_36_825.ale` | 正常加载，非缺失素材 |
| 感光质 | 共用 `CHN_2005_06_28_18_48_10_910.ale` | 正常加载 |
| 毒胶 | `shadow_actions` 的 idle/move/attack 均为空 | 当前没有独立阴影层，与已逆向的客户端类一致，本次不添加假阴影 |

幼虫阴影使用 `assets/monsters/om_larva/shared/shadow/animation_frames.tres`。其原图集为八向、每向五帧，原始归一化偏移 (-29,-30)。PNG 非透明像素 alpha 为 8..80/255，多数是 72/255（约 28% 不透明度）；因此阴影本身就较淡。身体叠加后还会遮住大部分阴影，不能通过是否显眼判断有没有加载。

本次保留原阴影的透明度、大小和原点，不为了突出阴影而移动/放大它，也不把幼虫的陰影套给毒胶。

证据文件：`data/gameplay/glory/glory_monsters_v1.json`、`assets/equipment_world/combat_visual_manifest.json`、幼虫阴影的 `import_metadata.json` 和 `frames.png`；毒胶客户端类无独立阴影的既有逆向记录见 `stage3_content_evidence.md` 3.2。

## 回归与实图

- `monster_hover_name_test.gd` 校验名称下移、60px 血条及水平居中。
- `monster_shadow_rendering_test.gd` 校验四类怪物的配置与实际节点，遍历 idle/move/attack、八个方向；幼虫贴图必须含有非透明像素。
- 非 headless 运行上述阴影测试并附加 `-- --capture`，生成 `.godot/monster_shadows.png`。上排为真实叠加效果，下排为同一素材拆出的独立阴影，便于对照身体遮盖效果。
