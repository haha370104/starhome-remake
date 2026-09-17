# 系统提示交互规范

## 主提示通道

屏幕中央的“停留—上浮—淡出”系统消息是游戏的**主要提示方式**。技能升级、装备规则拒绝、
移动条件不足、地图准入失败以及其他需要玩家立即注意的业务结果，都必须进入
`HallHud.show_system_message()` 的即时消息列表：

- 新消息立即出现在当前视口中央，旧消息依接收顺序排在上方，行间距6像素；
- 每条消息独立停留1.5秒，随后在1秒内上浮56像素并淡出；
- 后来的消息不等待上一条消失，不覆盖旧消息，也不延长旧消息寿命；
- 窗口缩放后重新居中，长文字自动换行并按实际高度留出间距；
- 不设待播队列，瞬时大量消息超出屏幕时仍同时计时，到期立即释放，不留下延迟播报积压。

`tests/ui/central_system_message_feed_test.gd` 已纳入总门禁，验证同帧60条消息立即出现、
独立到期、换行和窗口缩放；加 `-- --capture` 可用实际渲染生成视觉验收截图。

左上角状态文字只保留为路线目标、连接状态和开发诊断的辅助信息，不能作为业务错误的唯一反馈。
客户端本地预检失败与服务端 `command_rejected`/地图准入失败必须走同一个中央提示入口，避免离线
调试和联网模式呈现两套交互。

## 稳定错误码

客户端按稳定错误码映射玩家文案，不直接依赖英文服务端细节。当前装备与移动规则至少包括：

| 错误码 | 玩家提示 |
| --- | --- |
| `movement.no_propulsion` | 未安装可用推进器，战车无法移动 |
| `equipment.chassis_change_forbidden_in_field` | 野外地图中不能更换战车 |
| `equipment.chassis_change_requires_empty_loadout` | 更换战车前请先卸下其他战车装备 |
| `equipment.chassis_required` | 请先装备战车，再安装其他装备 |
| `equipment.chassis_required_for_field` | 未装备战车，无法进入野外地图 |
| `equipment.primary_weapon_required_for_field` | 未装备主武器，无法进入野外地图 |
| `inventory.revision_conflict` / `equipment.revision_conflict` | 装备状态已经更新，请重试 |

新增业务拒绝时，应先定义稳定错误码及中文文案，再接入中央提示；英文 `message` 只作尚未登记错误的
诊断回退，不应成为正式玩家文案。
