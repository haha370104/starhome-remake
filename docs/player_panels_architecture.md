# 人物、背包与战车面板实现说明

## 1. 已完成范围

三面板按 `combat_and_equipment_ui_reverse_engineering.md` 的荣耀版证据实现，并由底栏现有
`character`、`inventory`、`vehicle_equipment` 三个业务按钮切换。窗口保持原始像素尺寸、
可拖动、点击置顶、关闭后保留单例，并在视口变化后限制在可见区域。

- 人物：`355×450`，独立男/女 dialog 身体图、身份/成长/居所/描述、16 格 buff 区；服装按
  `dialog_anchor + ALE origin + z_layer` 叠加。首个可操作服装为荣耀版无袖衫（男）。
- 背包：`338×469`，主容器为 `276×295` 像素、15 像素吸附、最多 40 个物品实例；支持拖动、
  服务器整理、数量/金币显示和双击穿装。
- 战车：`604×460`，左侧按 dialog 图层合成，右侧显示生命、四向装甲、攻击、推动力、功率、
  重量、维修和两类能量；已装备槽位可双击卸装。

运行时素材全部位于 `assets/ui/windows` 的业务目录，原 ALE 名、版本与 SHA-256 仅保存在
`source_manifest.json`。`tools/import_glory_panel_assets.py` 可从两个荣耀版批准根幂等重建。

## 2. 权威状态链路

```text
底栏 / 面板手势
  -> GameWindowManager（补全本地已知 revision）
  -> ClientMultiplayerSession
  -> reliable panel command RPC
  -> peer 绑定的 ServerSession
  -> AuthoritativePlayerPanelService
  -> InventoryLayout / EquipmentSlotRegistry
  -> AuthoritativeAutosaveService.commit_player_state
  -> PlayerStateRepository
  -> 一次性 player_panels 三快照回包
```

客户端不写入物品位置、所属关系、装备数值或战车统计。正式服务器从 peer 会话取得
`character_id`，忽略客户端可能伪造的身份。查询不提交存档；移动、整理和换装先在隔离聚合上
验证，成功后只执行一次完整玩家聚合提交。

装备事务同时携带 `inventory_revision` 与 `loadout_revision`；人物穿装携带
`inventory_revision` 与玩家聚合 `state_revision`。任一过期即整体拒绝。成功回包总是包含人物、
背包和战车三份来自同一提交版本的快照，避免物品在两个面板同时存在或同时消失。

## 3. 背包几何规则

持久化物品除旧版兼容的 `slot_index` 外，还记录 `container_id`、`position_px`、
`footprint_px`、锁定、绑定和耐久。共享 `InventoryLayout` 负责：

1. 主容器边界；
2. 稳定实例 ID 唯一；
3. 矩形不得重叠；
4. 移动坐标按 15 像素吸附；
5. 整理按实例 ID 稳定排序并从左上扫描首个可用矩形；
6. 穿脱装备前预留被替换装备所需空间。

客户端可用相同规则绘制预览，但释放鼠标后仍等待服务器快照，不会直接确认位置。

## 4. 离线调试边界

编辑器默认离线模式使用 `OfflinePlayerPanelAuthority`。它只保存在内存中，但复用同一个
`AuthoritativePlayerPanelService` 和聚合校验，不在 UI 脚本内维护第二套背包/换装规则。
正式联网模式不会实例化该桥接器。

## 5. 自动验证

- `player_panel_service_test.gd`：像素吸附、过期 revision、战车原子换装和人物服装槽位。
- `authoritative_autosave_test.gd`：真实 `AuthoritativeServer` 面板命令立即提交，并在新服务器
  实例中恢复像素布局。
- `player_panels_runtime_test.gd`：三窗口原始尺寸、显隐、权威物品/槽位投影及视口约束。

完整工程门禁通过 `tools/run_project_checks.ps1` 统一运行上述测试、旧回归、真实 ENet 和素材审计。
