# 经验与掉落倍率切面

更新：2026-09-16。此处是已经接入权威运行时的实现；VIP商品、付款和会员发放不在本次范围。

## 结算入口与状态所有权

`RewardPipeline` 是显式调用的领域切面，经验在入账前、掉落在每条随机判定前经过同一套规则。
运行入口不散落 VIP / 食品 if 分支，不依赖客户端节点、RPC 字段或全局可变倍率。

| 对象 | 职责 |
| --- | --- |
| `RewardContext` | 本次账号、通道、技能/物品、来源、物种和权威时间 |
| `RewardModifier` | 倍率规则、筛选匹配、有效期和互斥组 |
| `RewardModifierProvider` | 提供当前有效规则；VIP、活动、药品可继承此端口 |
| `FoodRewardModifierProvider` | 将既有食品1～12类经验效果转换为通用倍率 |
| `RewardPipeline` | 来源合并、冲突判定、独立来源相乘、互斥组最高值选择 |
| `RewardSettlement` | 基础值、最终值及采用规则的解释明细 |
| `AuthoritativeRewardService` | 死亡时读取击杀者当前权威记录，抽取并按堆叠上限拆包 |

`AuthoritativeServer` 组装一个奖励服务，并把同一个 pipeline 注入面板、制造、交易任务和地图战斗。
地图惰性创建时也会绑定奖励服务；切图/休眠不会复制账号状态或重置规则。
只读加载器缓存JSON，每次组装生成独立 pipeline，多个服务器实例不会共享动态提供者。

经验路径：权威事件换算基础经验 → `Player.grant_skill_experience` → 奖励切面 → `SkillBook` → 既有升级规则。
战斗、移动、采矿、生产及训练奖励均经过 Player 聚合；SkillBook 仅负责已经结算好的数值入账。
其食品字段已移除，`FoodStatus.experience_multiplier` 已删除；食品经验倍率只有适配器一个实现。
`PlayerStateMapper` 在还原聚合时注入同一策略，防止制造、交易等路径漏掉增益。

掉落路径：确认怪物死亡 → 根据权威 attacker/killer 实体查账号 → 对每条基础掉率执行切面 → RNG → 地面堆叠。
掉落生成后数量固定；拾取不再次应用倍率，因此拾取者与击杀者不同、VIP后来到期或续费均不会重复结算。
客户端只能请求既有拾取目标，不能提交 account_id、倍率、有效期或规则。

## 配置规则

正式配置为[data/gameplay/reward_modifiers_v1.json](../data/gameplay/reward_modifiers_v1.json)。
当前 `rules` 为空，默认运营倍率为1，保留既有食品经验收益与所有基础掉落数值。
修改此配置后重启服务端；不需要修改任何经验发放点或掉落分支。

示例仅说明结构，尚未启用；`ACCOUNT_ID` 需要替换为服务端存档中的真实 account_id，而不是 peer_id：

```json
{
  "schema_version": 1,
  "content_version": "reward-modifiers-v1",
  "rules": [
    {
      "id": "event.experience",
      "channel": "experience",
      "multiplier": 1.5
    },
    {
      "id": "vip.mining",
      "channel": "experience",
      "account_ids": ["ACCOUNT_ID"],
      "skill_ids": ["mining"],
      "multiplier": 2,
      "stack_group": "vip.experience",
      "starts_at": 1789516800,
      "expires_at": 1792108800
    },
    {
      "id": "vip.gel",
      "channel": "drop",
      "account_ids": ["ACCOUNT_ID"],
      "item_ids": ["low_grade_gel"],
      "multiplier": 2,
      "stack_group": "vip.drop"
    }
  ]
}
```

通道为 `experience` / `drop`。筛选数组省略或为空表示不限，该数组内任一匹配即可；不同字段之间为“且”。
可选筛选字段：`account_ids`、`skill_ids`、`item_ids`、`sources`、`species_ids`、`population_kinds`。
技能用于经验，物品用于掉落；物种和种群事实由怪物掉落入口提供，经验入口不会自动带上受击怪物。
经验来源包括 `effective_damage`、`accepted_driving_movement`、`mined_material`、
`authoritative_action`、`manufacturing`、`training_reward`，聚合直接调用默认为 `direct`。
怪物掉落来源为 `monster_kill`。物品请使用目录的规范ID；不要使用显示名称或旧别名。

时间为服务器 Unix 秒，生效区间 `[starts_at, expires_at)`；开始默认0，到期默认0表示无限期。
倍率允许0及小数，拒绝负数、非数字、NaN、Infinity、空标识、错误筛选类型、重复ID和未知字段。
动态提供者返回的规则也检查数值和重复ID；使用稳定且不与其他来源重复的ID。
食品规则ID使用 `food.experience.<效果类型>`，该命名空间留给食品适配器。

## 叠加及数量规则

- 无互斥组：独立规则倍率相乘。活动1.5 × VIP2 × 食品1.2 = 3.6。
- 同一 `stack_group`：只取匹配规则中的最高倍率，不累计VIP档位；同倍率按ID稳定选择。
- 不同互斥组彼此仍相乘。0倍率可关闭对应奖励；如果放在互斥组，仍遵循最高值规则。
- 食品同技能仍沿用原有同类替换状态，不重复增加同一效果；切面按结算时间检查到期，即使清理尚未执行也不会续享。
- 经验保留小数，继续遵循一次最多升一级、升级溢出清零及满级规则；返回的 `granted_experience` 为倍率后数值，`base_experience` 为基础数值。
- 掉率 `p × multiplier` 超过1时，整数部分为保证份数，小数部分为追加一份的概率。每份使用原数量范围，合计数量期望严格乘倍率。
  例如50% ×2.5 → 保证1份且25%追加1份；1% ×2.5 → 2.5%出1份。
  实现对一次数量抽样乘以份数，保留均值，不声称与逐份独立抽样具有相同方差。
- 超过物品堆叠上限时生成多个独立loot_id，数量总和保持不变，沿用既有拾取和背包事务。
- 无匹配倍率时不改变基础随机数消费顺序；`reward_settlement` 记录实际采用规则，用于排查收益。

现有精英20倍已在[精英基础策略](../data/gameplay/elite_population_v1.json)编译入基础掉落表，
本切面在该基础上继续乘运营倍率。例如精英基础20倍 × VIP2 = 普通基础的40倍；
不要再额外添加一条精英20倍规则，否则会重复计算。

本次切面覆盖技能经验和怪物随机掉落。商店购买、任务固定物品、采矿产量及生产成品数量不随掉落倍率变化。
食品回血、战车攻击、防御和生命上限属于属性/治疗模型，继续由原领域对象结算；本次迁移的是食品经验增益。

## 接入VIP与药品

静态运营配置可直接使用账号名单、技能/物品筛选和有效期。
需要接入动态会员或药品时，继承 `RewardModifierProvider.modifiers_for(context)`：
用 `context.account_id` 和 `context.now` 查询服务端权益/药品状态，返回类型化 `RewardModifier`，
然后在服务器组装时调用 `reward_service.pipeline.add_provider(provider)`。
同一个实例已被所有经验/掉落消费者共享，新增提供者立即参与后续结算。

提供者只读权益，不直接发经验、创建物品或扣除玩家状态。长期权益保存在服务器仓储；
客户端请求中的VIP标记或倍率不能作为事实来源。规则到期、续费和撤销应由提供者查询最新状态，
不通过反复追加相同规则来模拟续费。新增药品状态及其使用事务仍需对应领域模型，这里提供统一收益结算端口。

## 验证

- `tests/domain/reward_pipeline_test.gd`：账号/目标筛选、有效期、互斥组、食品、重复/非法配置。
- `tests/server/reward_authority_test.gd`：同服双账号、真实经验/生产/掉落/入包、伪造字段拒绝、小数经验、存档往返、超堆叠、默认RNG兼容及2.5倍概率抽样。
- 两项均已纳入 `tools/run_client_checks.py`，食品现有回归也已迁移为验证 Player 统一结算入口。

本轮实际验证：领域专项21项、权威专项138项；完整门禁53/53通过，报告
`.godot/client-checks-20260916-125313-35700/summary.json`。新增及修改函数的中文契约注释检查通过。
