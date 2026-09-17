# 荣耀版怪物弹体速度逆向

## 1. 结论

荣耀版 FCC 中的 `m_nspeed` 是传给老引擎 `line(...)` 控制器的**速度参数**，不能直接当成像素/秒。对当前运行容器的 `nengine.dll` 反汇编后，可以确认默认时间倍率下：

```text
老引擎有效线速度 ≈ m_nspeed / 2.4  地图像素/秒
```

因此当前首批怪物应按以下数值实现：

| 怪物 | 客户端怪物类 | 弹体类 | FCC 参数 | Godot 有效速度 |
|---|---|---|---:|---:|
| 奥姆虫及其同类变种 | `Npc成虫1/2/3` | `npcbulletRoto` | 1000 | 416.666667 px/s |
| 奥姆幼虫及其同类变种 | `Npc幼虫1/2/3` | `npcbullet` | 1000 | 416.666667 px/s |
| 感光质及其同类变种 | `NpcLightBall1/2/3 : NpcBase3` | 无 | 不适用 | 贴身攻击，无弹道 |
| 毒胶及其同类变种 | `NpcSlm1/2/3` | `rotbullet` | 无 | 八方向五帧喷射；复刻到达时序400 px/s，非原版线速度 |

复刻版已经把奥姆虫和奥姆幼虫的共享客户端/服务端速度从错误的 `1000 px/s` 调整为 `416.666667 px/s`。
毒胶此处的早期帧数记录已由专用喷吐原图审计更新为八方向、每方向五帧；当前用服务端到达时序推进喷吐表现。
2026-09-17按用户要求，将该复刻时序速度从1000降为400像素/秒，喷吐结束后3秒渐隐；
这项调参不作为原版弹速证据。最新来源和领域边界见[毒胶喷吐与持续腐蚀](projectile_hit_and_monster_state_reverse_engineering.md#95-毒胶喷吐与持续腐蚀2026-09-16)。

## 2. FCC 层证据

荣耀版 `bullet.fcc` 中：

```text
npcbullet      : m_nspeed = 1000; line(..., m_nspeed, 8, "endfly")
npcbulletRoto  : m_nspeed = 1000; line(..., m_nspeed, 8, "endfly")
paotaibullet   : m_nspeed = 2500; line(..., m_nspeed, 8, "endfly")
VenomBullet    : m_nspeed = 500;  line(..., m_nspeed, 8, "Endfly")
```

`npcclt1.fcc` 则把怪物类映射到弹体类：

- `Npc成虫1/2/3` 使用 `npcbulletRoto`；
- `Npc幼虫1/2/3` 使用 `npcbullet`；
- `NpcSlm1/2/3` 使用 `rotbullet`；
- `NpcLightBall1/2/3` 虽保留历史字段 `m_sbulletclassname="npcbullet"`，但实际继承的 `NpcBase3.OnNpcAttack` 只播放身体攻击与声音，不创建弹体；
- 撒玛机械虎、机械天牛、发条人、悬浮车、飞鹰等常规远程怪物也映射到 `npcbulletRoto`，因此与奥姆虫属于同一速度档。

## 3. `nMFly` 的实际换算

分析对象：

```text
D:/Program Files/FancyBoxII Games/newsystem/nengine.dll
SHA-256: 7DE995127A4860B7EF366D7A37EBDE844E30BC97AEAAD29663448699294EA300
```

RTTI 中的直线飞行控制器名为 `FTGameOS::nMFly`。其初始化代码在默认时间倍率 `100` 下，按下式计算插值总步数：

```text
distance = floor(sqrt((x1-x0)^2 + (y1-y0)^2))
steps = floor(distance * time_scale * 150 / (speed_parameter * 100))
```

更新函数读取毫秒时钟，并用右移 4 位推进进度，即每 **16 ms** 前进一个插值步。默认 `time_scale=100` 时：

```text
duration_seconds ≈ distance * 150 / speed_parameter * 0.016
                 = distance * 2.4 / speed_parameter

effective_speed ≈ speed_parameter / 2.4
```

所以：

| `line` 速度参数 | 默认有效速度 |
|---:|---:|
| 200 | 83.333333 px/s |
| 500 | 208.333333 px/s |
| 600 | 250 px/s |
| 1000 | 416.666667 px/s |
| 1500 | 625 px/s |
| 2000 | 833.333333 px/s |
| 2500 | 1041.666667 px/s |

实际结果还会受整数距离、整数除法和最小步数影响，短距离会有少量量化误差。`line(..., speed, 8, ...)` 中的 `8` 会让视觉对象从路径前八个插值步之后开始显示，相当于跳过靠近发射者的一小段；它不会把 `1000` 变成 `1000 px/s`。复刻版暂时保留从炮口连续飞出的表现，只还原有效线速度，避免在现代高刷新率环境里产生明显的出生跳跃。

## 4. 荣耀版弹体速度档

### 4.1 常规直线怪物弹

`npcbullet`、`npcbulletRoto`、`sama_blt`、`space_npcbullet`、`ApparitionBullet` 和 `BT_ApparitionBullet` 的参数均为 1000 或继承 1000，有效速度约 **416.667 px/s**。

其中 `npcbulletRoto` 与 `npcbullet` 的区别主要是朝向：前者会根据发射矢量旋转 ALE 帧，速度相同。

### 4.2 炮台和高速护卫弹

`paotaibullet` 与 `Guardbullet` 使用参数 2500，有效速度约 **1041.667 px/s**。这是一档有意设计的高速弹，不能把它与奥姆虫共用一个运行时数值。

### 4.3 毒液类慢速弹

`VenomBullet` 与 `YSHN_QZWD` 使用参数 500，有效速度约 **208.333 px/s**。

### 4.4 导弹类

`MissileBullet` 初始参数 600，有效速度约 **250 px/s**；`StartChangeFly` 内保留调用计数超过6次后把参数设为2000的分支，对应约 **833.333 px/s**。
但普通玩家导弹类仅在构造时调用一次，没有定时再次调用；不能据此虚构“飞行一段时间自动加速”。
`GuardMissileBullet` 则从1000起步，并明确每500 ms重新调用，之后可提升到2000，约为 **416.667 → 833.333 px/s**。

导弹会重建朝当前目标位置的 `line` 控制器，不能只用一条固定直线插值代替完整追踪逻辑。

### 4.5 没有空间速度的表现类

以下类不能换算为 px/s：

- `rotbullet`：`PlayAni("fly", 200, "PlayEnd")`，8 帧约 1.6 秒，使用 `forwardto` 定向，但没有 `line`；
- `FireBullet`：播放 8 帧、每帧 100 ms 的动画，没有 `line`；
- `BossBullet`：直接把对象放到目标点播放爆炸；
- `BossBullet2`：目标区域持续碰撞/特效对象；
- `NpcBase3` 感光质：没有弹体，贴近后由攻击结算回调在战车上播放覆盖特效。

这些类型应分别建模为“定向喷射”“定时动画”“目标点爆炸”“区域效果”和“贴身攻击”，不能为了复用代码虚构一个弹道速度。

## 5. 复刻实现约束

1. 配置中保存的是 Godot 世界坐标的有效速度，不再保存未经换算的 FCC 参数。
2. `client_line_speed_parameter` 和 `client_line_initial_step` 仅作为溯源字段保留。
3. 客户端表现与权威服务器必须消费同一个有效速度，确保扣血事件在视觉弹体到达时发生。
4. 新增怪物时先确认其 `m_sbulletclassname`，再按弹体类选择运动模型；不能看到 NPC 表中有历史弹体字段就认定一定发射该弹体。
5. 对 `rotbullet`、Boss 类和贴身类，优先恢复原运动模型，而不是用常规直线弹的数值凑近观感。

## 6. 2026-09-17 玩家导弹速度修正

再次核对荣耀 `bullet.fcc:421,509-510` 及上述同 SHA-256 的运行容器后，普通玩家导弹默认有效速度确认为
`600 / 2.4 = 250 px/s`。此前副武器配置与素材表现清单把600直接用作像素/秒，导致飞行快了2.4倍。
现在 `data/gameplay/stage3/starter_loadout_v1.json` 和素材 `equipment_world/combat_visual_manifest.json` 均为250，
保留原始参数与换算依据；所有实际导弹型号继承该基础速度，权威发射事件/快照同步相同参数。

服务端命中时刻与客户端飞行同时修正，不能只放慢动画而仍提前扣血。视觉专项验证0.25秒前进62.5像素；
权威专项使用真实目录的导弹定义，验证到达前不扣血、按250计算到达刻及事件中的速度值。
本轮只恢复普通导弹基础速度，不增加护卫导弹的500 ms定时加速，也不引入尚未实现的「飞弹速射」技能百分比。
既有复刻版跟随目标表现与服务端命中裁决保持原边界，不宣称完全复制旧客户端信任上报协议。
