# 装备三种表现模式与面板叠图

## 素材契约

荣耀版装备定义已经记录三条独立引用，不能用缩放同一张图片代替。

| 使用场景 | 原客户端字段 | 典型素材路径 | 复刻读取方式 |
| --- | --- | --- | --- |
| 背包、物品栏 | `m_sBaseSrc` | `pic3/equip/bag/*.ale` | `presentation_for("inventory")` |
| 装备面板 | `m_sDlgSrc` | `pic3/equip/dlg/*.ale` | `presentation_for("dialog")` |
| 野外战车 | `m_sMoveSrc` | `pic3/equip/body/*.ale` | 世界组件目录、方向和动画帧 |

并非每件装备都需要在野外额外绘制一层；是否参与整车合成由世界组件配置决定，不能把装备窗大图放进野外。

证据位置：

- `data/gameplay/glory/glory_items_v1.json`：原始装备字段与三个表现模式的对应引用。
- `assets/ui/windows/source_manifest.json`：已导出的荣耀版 PNG 来源、尺寸、ALE 原点。
- `assets/equipment_world/source_manifest.json`、`combat_visual_manifest.json`：野外八向素材来源与组件绑定。

新兵装备的实际图像尺寸如下（单位：像素）：

| 装备 | 背包图 | 装备窗图 | 装备窗原点 |
| --- | --- | --- | --- |
| 新兵战车 `tank1` | 67 × 46 | 199 × 104 | (-77, 8) |
| 新兵能量炮 `gun1` | 40 × 21 | 112 × 43 | (-32, -16) |
| 初级引擎 `engine1` | 36 × 32 | 64 × 57 | (-33, -15) |

## 本次修正

旧初始装备的 `player_equipment_v1.json` 是平铺结构，同时含有 `icon`、背包 `native_size` 和 `dialog_texture`。此前模式读取原样返回整个字典，贴图加载器优先选 `icon`，导致装备窗误用背包图。再把底盘强制放大到 199 × 104，只改变了控件尺寸，没有解决原图模糊；炮仍然只有背包图那么大。

现在由 `GameItem.presentation_for()` 在兼容边界隔离模式：dialog 不返回背包 icon/native_size，inventory 不返回 dialog_texture。新版嵌套配置直接取自己的模式；缺失模式不回退到整个配置，也不拿背包图冒充大图。调用方拿到的仍是防御性副本，不改变物品领域状态。

底盘和炮按 `位置 = 安装锚点 + dialog ALE 原点`、`尺寸 = dialog 原生尺寸` 绘制。新兵两者的安装锚点均为 (170, 200)，因此底盘左上角为 (93, 208)，炮为 (138, 184)。不再强制其他底盘使用新兵战车的矩形大小，避免不同底盘与武器错位。

推进器是槽内独立展示项：在面板局部矩形 `(96, 360, 68, 68)` 内保比居中，较上次下移 31 像素，位于「推进器」标题下方。该槽位调整是本次复刻 UI 决策，不声称是原客户端的像素坐标。

背包继续使用小图，在 5 × 8 等大格子内保比显示并保留 5px 内边距。野外仍使用原来的八向动画组件，不受本次面板修改影响。

## 验证方式

- `tests/domain/item_presentation_modes_test.gd`：旧/新格式隔离、缺失模式、深拷贝。
- `tests/domain/glory_item_runtime_catalog_test.gd`：荣耀新兵战车、撒玛王战车、新兵炮、引擎分别解析 bag/dlg/body。
- `tests/ui/runtime/player_panels_runtime_test.gd`：校验实际源贴图而不只校验控件尺寸；校验推进器位置，以及两种底盘各自的原点与原生尺寸。
- 运行面板测试时附加 `-- --capture-equipment`（非 headless）可保存 `.godot/equipment_panel_regression.png`，供实际渲染核对。
- `tests/integration/d04_player_vehicle_presentation_test.gd`：野外八向移动、瞄准与战车层切换回归。

仅复用现有荣耀版素材；不引入其他版本装备素材。
