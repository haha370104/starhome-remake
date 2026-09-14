# 矿物颜色、随机款式与装备组合层级（2026-09-14）

## 渲染错误与修正

矿物及掉落物共用 `ground_loot_hover_glow.gdshader`。旧实现手动采样纹理后再乘 fragment 的 `COLOR`，后者已包含纹理采样，导致 RGB/alpha 被重复相乘。不是原 ALE 全部解码错误，不应该给资源统一提亮或重写调色板。

现在 vertex 阶段保存节点调制颜色，在 fragment 阶段只乘一次。矿物使用 `AtlasTexture`，还需用当前帧的 `source_region` 把全图 UV 换成帧内 UV；外扩晕染与邻域采样只能在这一帧内取色，不能采到隔壁款式。独立掉落 PNG 默认使用完整区域。

真实 OpenGL GPU 测试将七种铁矿及低级生物硅分别与无材质的原图放在相同背景、透明度和调制颜色下逐像素对比：10 项通过，允许每通道最多 2/255 的舍入差。对照图输出到 `.godot/mineral_color_comparison.png`，上排为修正材质，下排为无材质原图。已有素材和调色盘不变，不做主观亮度补偿。

## 随机矿物外观

服务器在生成矿源时已按矿源 ID 种子生成 0..6 的 `visual_variant`，同一矿点生命周期内不变，并随快照发送给各客户端；不是每次刷新随机换样式。铁矿资源确实有七帧静态款式。修复图集采样后它们能正常显示，无需创建第二套客户端随机数。

`authoritative_mining_module_test.gd` 增加款式范围和同批矿源多样性断言，81 项通过。`mineral_world_controller_test.gd` 12 项通过，包含款式选择和采集后款式不变。

## 装备面板

旧底盘 PNG 的配置层级是 10，新导入采掘臂没有显式层级而回退到槽位号 1，造成底盘盖住臂。`PlayerPanelProjector` 现在统一中央组合的层级：底盘 10、主装置 20，沿用已有新兵组合的顺序。主装置槽中的能量炮、采掘臂使用同一规则，不依赖物品名称、导入形式或节点创建顺序。其他槽位仍保留自己的配置。

`player_panels_runtime_test.gd` 使用旧 PNG 新兵底盘与荣耀 ALE 撒玛王底盘分别搭配七档臂，检查实际 TextureRect 层级：整套 87 项通过。

## 执行与验证边界

- GPU 专项：Godot `--rendering-method gl_compatibility --script tests/visual/mineral_color_render_test.gd`。不能用 `--headless`：该模式无实际画面，不能证明像素正确。
- 总检查脚本新增可选 `-IncludeGpuVisualTests`；默认 headless 门禁会明确跳过该项。
- 本轮专项均已执行，正式入口静态检查 0 warning / 0 error；未执行全库总门禁。
- 采掘臂帧率与时序依据见 [采矿动作说明](mining_equipment_and_player_messages.md)。
