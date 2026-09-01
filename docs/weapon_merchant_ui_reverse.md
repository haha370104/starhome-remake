# 武器商人、买卖与任务 UI 逆向记录

## 结论

本次实现没有套用 Godot 的现代化通用对话框，而是分别恢复原客户端的三种交互形态：

- 点击 NPC 后显示贴近 NPC 的 `BasePOPMenu` 纵向菜单；
- “买东西”和“卖东西”打开 530×450 的独立买卖窗；
- “中级任务”打开消息式任务窗口，由接受、材料进度和交付状态驱动。

界面仅发送操作意图。商品范围、价格、背包 revision、任务材料消耗与奖励都由权威服务器验证。

## 原客户端证据

### NPC 动作菜单

`starhome_lz_ry_fcc_source/baseclass/formbaseclass.fcc:3145` 定义了 `BasePOPMenu`：

- 高度按菜单项数量动态计算；
- 每一项是独立的文字按钮；
- 悬浮时切换为按钮发光色，按下时添加 glow；
- 菜单宽度按最长标题计算，并在两侧留白。

`starhome_lz_ry_fcc_source/sellorclt_style_hp.fcc:571` 的 `SellMenu1` 按 NPC 能力依次加入购买、出售、任务等动作。任务动作调用 NPC 的 `HandleWork`，而非打开一个全局任务列表。

### 买卖窗口

`starhome_lz_ry_fcc_source/sellorclt.fcc:638` 和 `:907` 分别定义 `SellDlg1` 与 `BuyDlg1`：

- 窗口尺寸为 530×450；
- 左侧物品滚动区位于 `(16, 84)`，大小约 295×314；
- 每项高度为 22 像素；
- 行内显示物品名、价格、数量和操作按钮；
- 鼠标进入时整行以黄色矩形高亮，并刷新右侧物品图与复杂说明；
- 原文字色为 `#FAF0C8`；
- 窗口可以拖动并被置顶。

原客户端对可合并物品另开数量输入窗。当前雏形按一次一个执行交易，协议已经保留 `quantity` 字段，后续可补数量输入而无需改变服务端模型。

### 循环任务

`starhome_lz_ry_fcc_source/sellorclt.fcc:254` 定义武器商人任务；任务消息由 `ShowTaskMessageWnd` 创建，确认按钮调用 NPC 的 `HandleEve`。原任务要求为：

- 低级类胶 20 个；
- 低级能量催化剂 20 个；
- 低级生物硅 20 个。

基础奖励为 1500 金币，最多完成 30 次；第 5、10、15、20、25、30 次分别给出加强能量炮、改式引擎、领航者战车、突袭能量炮、多能引擎、勇敢者战车。对话原文来自 `starhome_lz_ry_fcc_source/great/code_string.fcc:457-460`。

## 复刻实现

- `HallHud` 只负责 NPC 附近的小型动作菜单；右键点击菜单会关闭且不会触发地图移动。
- `WeaponMerchantWindow` 根据 `buy`、`sell`、`task` 三种模式渲染原版布局。
- `GameWindowManager` 统一管理窗口置顶、拖动、右键关闭与命令分发。
- `AuthoritativeCommerceService` 依据会话绑定的玩家存档执行交易和任务，不接受客户端提交价格、奖励或玩家身份。
- 商店动作复用现有 `player_panel_command` 通道，响应仍是同事务的人物、背包、战车和 commerce 快照。

当前商店出售荣耀版目录中等级不高于 270 的战车、能量炮、引擎、维修臂和挖掘臂；收购背包中一切物品。商品图标仍通过统一物品表现目录按需解析，不复制整套素材库。
