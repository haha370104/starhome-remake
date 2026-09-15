# 底栏导航与窗口（2026-09-07）

## 当前入口

当前入口排列为：人物属性、背包、战车装备、好友列表、当前场景玩家、任务日志、系统设置、成就系统、商城。
2026-09-14 将商城与右邻按钮换位，原商城位置承载[成就系统](achievements.md)，更右侧按钮保持原状。
按钮保持原像素大小；从 1024px 设计面 x=519 开始，每项间距 38px。删除的是入口，不更改顶部工具栏。

人物、背包、战车沿用已有窗口。好友点击中央提示未实现。其他四窗归 `GameWindowManager` 管理，可右键关闭，除小型系统菜单外可拖动，不用系统模态弹窗阻断地图操作。

## 原版证据与实现边界

源码位置相对仓库上一级 `outputs`，只用于离线逆向，不属于运行时资源路径。

| 功能 | 本地原版源码 | 已接入 / 明确保留 |
|---|---|---|
| 底栏顺序与入口 | `starhome_lz_fr_fcc_source/menupart_main_common_dzl.fcc`，`base_ctrlpad`、`ShowPlayerTask`、`OnEnterShopping` | 8 个独立状态按钮；去除天阵、命运、星图、GM 反馈 |
| 用户列表 | `starhome_lz_ry_fcc_source/chatctrl_main.fcc`，`great/code_string.fcc` | 320×450；用户列表/当前区域在线用户列表；用户名、性别、战果、战斗积分四列和列头排序 |
| 任务日志 | `starhome_lz_fr_fcc_source/bool/role/userrolewnd.fcc`、`great/bool_great.fcc` | 250×350；新兵任务、中级任务、高级任务、家园活动四页；名称、状态、材料、完成次数和奖励 |
| 系统菜单 | `starhome_lz_fr_fcc_source/menupart_main_common_dzl.fcc`，`CtrlPad_SystemWnd` | 原 65×178 九行按钮图、逐项点击；仅提示，不实际退出、改设置或打开外链 |
| 商城 | `starhome_lz_fr_fcc_source/hp/adorn/adorn_ui.fcc`，`shopping_ui/InitUi/BtnWnd` | 原 720×502 背景，三大类及各子类、进入确认、搜索、翻页、物品信息区、退出 |

用户列表高级社交操作、战果和战斗积分尚无模型支持：后两项显示“—”，双击用户明确提示未实现。不是伪造 0，也不泄露账号信息。

任务日志只显示真实已接取或有完成记录的任务。2026-09-14 已扩展为四套材料循环任务和五类每日训练，
规则与权威边界见 [任务说明](repeatable_quests.md)，不再只有武器店一项。
详情为同窗下半部分，可滚动；原版另开详情的方式未照搬。未配置分类不生成占位任务，不允许日志远程领取/交付。

2026-09-15 商城新增第四类“接合器”，新式每件1000紫晶、旧式每件2000紫晶，共九件；其他分类保持空态。余额和购买由权威服务器提供，保留进入确认和商品购买确认，不开放充值、兑换或真实货币支付。详见[接合器与紫晶商城](attachments_and_premium_shop.md)。导航窗口文字使用共享微软雅黑常规 12px；任务日志已改为 380×520 的深色圆角面板，正文 16px、标题 20px，并提供分类选中状态。功能控件用项目按钮样式，不宣称全部按钮像素级还原。

2026-09-15 商城单独统一为微软雅黑16px，覆盖分类、列表、空状态、详情、价格、搜索与确认按钮；
其余导航窗口的字号由各自窗口定义。保留720×502原背景，商品列表宽434px、详情侧栏宽206px。
侧栏用纵向容器分配空间：长说明自动换行并在内部滚动，单价、合计、数量与购买按钮固定在底部，
切换商品回到说明顶部。进入商城提示同步加高，避免统一字号后挤压确认按钮。

## 权威边界

- 玩家列表：`query_scene_players` 经过现有 `player_panel_command` 传输；服务器只认发起会话的 `map_instance_id`。排除其他实例和已断线宽限会话，返回实体 ID、显示名、性别及未实现值。客户端请求不得指定任意地图。
- 任务日志：`PlayerPanelProjector` 从同一 `Player.quest_states` 与 `Inventory` 调用 `RepeatableCollectionTask.snapshot`。没有客户端任务规则副本，没有额外持久化表；领取与提交仍由商人权威服务处理。
- 名单/日志仅在窗口可见时每 2 秒查询；普通物品与任务事务仍即时更新日志。查询不写数据库、不增加状态 revision。离线和 ENet 共用同一服务器处理器。
- 窗口投影只负责展示/排序。数据来源是服务器；商城购买复用权威玩家事务，系统菜单的占位功能不变更游戏状态。

## 素材与维护

导入脚本 `tools/import_bottom_menu_windows.py` 使用帧元数据裁切、拼接边框，不拉伸源图。运行时路径为 `assets/ui/windows/navigation` 和 `assets/ui/free_hud/bottom_main/menu_buttons/premium_shop`，来源审计在 `assets/ui/source_audit/bottom_menu_windows.json`。

用户此次指定的免费版任务日志、商城、系统菜单，以及荣耀本地找不到边框时的用户列表回退，是窄范围 UI 豁免；不能推广到地图、装备、怪物或其他窗口。`tools/import_free_hud_assets.py` 同步维护这 8 项，重新导入不会恢复已删除入口。

## 验证

`tests/ui/runtime/navigation_windows_test.gd` 已纳入总门禁：验证名单地图隔离和断线过滤、字段隐私、任务持久化进度、8 项顺序、窗口开关、商城确认/分类/空搜索、按可见性轮询。可选 `--capture-navigation` 使用真实渲染器输出 `.godot/navigation_windows.png` 供视觉检查。

本轮：导航 30 项断言、原有三面板 72 项断言通过；入口脚本扫描 0 warning / 0 error，真实渲染截图已检查。未宣称全库测试通过：全库函数注释门禁还报告其他在改文件中的缺参/返回说明，未并入此次 HUD 改动。
