# 荣耀版素材关联关系

本文记录战车、武器、服装、怪物、阴影和攻击/维修特效之间的关联方式，供 `starhome_remake` 的导入器、资源清单和运行时组件使用。

除“免费版 HUD 特例”外，本工程后续素材均以荣耀版资源及荣耀版 `ourgamestart.fcc` 为准。本文没有用其他版本替换荣耀版素材；其他版本只可在荣耀版引用缺失时作为定位线索，并必须另行标记。

## 1. 结论摘要

1. 战车、能量炮、维修臂等装备不是“一张图到处缩放”，而是同一装备类显式绑定三种素材：
   - `m_sBaseSrc`：背包、掉落物、普通物品格使用的小图；
   - `m_sDlgSrc`：装备面板中的展示图；
   - `m_sMoveSrc`：地图场景内使用的八向动画。
2. 服装也采用同样的三视图模型，并额外绑定站立和坐下动画。场景中的人物由裸体基础角色与多个服装层叠加，不应把背包图直接画到人物上。
3. 战车阴影由战车的 `m_ntype` 查硬编码表，不是按战车文件名自动推导。多个战车等级可以共用同一套阴影。
4. 怪物阴影由怪物类分别声明移动、站立、攻击阴影；运行时阴影对象跟随本体，并在状态切换时同步更换动画和帧。
5. 能量炮类直接指定炮身、飞行子弹和发射声音，但命中特效索引由攻击结果消息传给客户端。荣耀客户端保存了全部命中特效表，却不保存一张可靠的“每门炮 -> 命中特效索引”静态表。
6. 地面维修臂的场景 ALE 本身就是维修动作。普通对外维修没有额外创建一张独立维修特效；自维修另有 `MinSpan1/2 + MinSpanShadow`，它与当前装备的维修臂型号解耦。
7. 太空维修臂确实显式绑定 `Repair_effect.ale`，但它属于太空装备系统，不能据此推断地面维修臂也使用同一特效。

## 2. 证据等级

本文使用以下标记：

- **确定**：荣耀版 FCC 中存在字段赋值和实际调用链；
- **高度可能**：素材和全局表均存在，名称与序号一致，但决定索引的一段逻辑位于服务端；
- **候选**：只发现素材或旁支系统引用，不能接入首批复刻的正式映射。

## 3. 装备的三种图像身份

### 3.1 通用字段

荣耀客户端的装备基类保存：

| 字段 | 业务身份 | 常见目录 | 帧方向 |
| --- | --- | --- | --- |
| `m_sBaseSrc` | 背包/物品栏图标 | `pic3/equip/bag/` | 通常单向 |
| `m_sDlgSrc` | 人物或战车装备面板展示 | `pic3/equip/dlg/` | 通常八向或面板专用 |
| `m_sMoveSrc` | 场景内装备 | `pic3/equip/body/` | 八向 |
| `m_sEquipFaceFile` | 快捷栏中的“装备类别按钮” | `pic3/equip/tank_*.ale` | UI 图标 |

`m_sEquipFaceFile` 不是该物品独有的背包图。例如所有地面能量炮默认使用 `tank_gun.ale` 作为快捷栏类别按钮，维修臂使用 `tank_repair.ale`。物品栏必须使用 `m_sBaseSrc`。

运行时容器与素材选择的硬映射为：

| 所在容器 | 使用素材 |
| --- | --- |
| `pbag` | `m_sBaseSrc` |
| `TankEquip`、`OtherEquip` | `m_sDlgSrc` |
| `battle_char`、`me` | `m_sMoveSrc` |
| 其他普通容器 | `m_sBaseSrc` |

证据见 [`BaseEquip.ChangeEquipStyle`](../../starhome_lz_ry_fcc_source/cltobj/equipclt.fcc#L1401-L1452)。

### 3.2 代表性映射

| 类/名称 | 背包图 | 装备面板图 | 场景图 | 附加关联 |
| --- | --- | --- | --- | --- |
| `tank1` / 新兵战车 | `equip/bag/tank1.ale` | `equip/dlg/tank1.ale` | `equip/body/tank1.ale` | `m_ntype=1`，阴影见第 5 节 |
| `gun1` / 新兵能量炮 | `equip/bag/gun1.ale` | `equip/dlg/gun1.ale` | `equip/body/gun1.ale` | `bullet1.ale`、`gun1.gsm` |
| `repair` / 初级维修臂 | `equip/bag/repair1.ale` | `equip/dlg/repair1.ale` | `equip/body/repair1.ale` | `repair001.gsm` |
| `mancloth01a` / 无袖衫（男） | `clothing/bag/man/mancloth01a.ale` | `clothing/dlg/man/mancloth01a.ale` | `clothing/body/man/mancloth01a.ale` | 另有 `stand/`、`sit/` |

新兵战车定义见 [`tank1`](../../starhome_lz_ry_fcc_source/cltobj/equipcltclass.fcc#L3-L53)，新兵能量炮定义见 [`gun1`](../../starhome_lz_ry_fcc_source/cltobj/equipcltclass.fcc#L1564-L1623)，初级维修臂定义见 [`repair`](../../starhome_lz_ry_fcc_source/cltobj/equipcltclass.fcc#L4205-L4240)。

完整装备关系已经导出到 [`equipment_catalog.json`](../../starhome_lz_ry_full_parsed/catalogs_utf8/equipment_catalog.json)。当前荣耀目录中的统计为：

| 类别 | 类记录数 | 同时解析出三视图 | 三视图路径互不相同 |
| --- | ---: | ---: | ---: |
| 战车/载具 | 40 | 40 | 40 |
| 武器 | 100 | 97 | 96 |
| 服装 | 561 | 489 | 489 |

这里统计的是类记录，不是去重后的素材数量。缺少三视图的记录多为特殊装备、继承类或只在某一界面出现的对象，不能用文件名批量补齐。

### 3.3 外观变体必须整组切换

装备可以同时声明：

- `m_szBaseSrcChange`；
- `m_szDlgSrcChange`；
- `m_szMoveSrcChange`；
- `m_szPaletteChange`；
- `m_szBulletFileChange`。

客户端用同一个 `m_nPlayerUseEquipAleIndex` 选择这些数组。以新兵能量炮为例：

| 外观索引 | 背包 | 面板 | 场景炮身 | 子弹 |
| ---: | --- | --- | --- | --- |
| 0 | `gun1.ale` | `gun1.ale` | `gun1.ale` | `bullet1.ale` |
| 1 | `lasergun1.ale` | `lasergun1.ale` | `lasergun1.ale` | `bullet1b.ale` |

因此复刻时“换皮”不能只换场景炮身，否则背包、装备面板和子弹会互相不一致。

### 3.4 服装比普通装备多两个状态

服装类的核心字段是：

| 状态 | 字段 | 目录 |
| --- | --- | --- |
| 背包 | `m_sBaseSrc` | `clothing/bag/` |
| 装备面板 | `m_sdlgsrc` | `clothing/dlg/` |
| 行走 | `m_smovesrc` | `clothing/body/` |
| 站立 | `m_sstandsrc` | `clothing/stand/` |
| 坐下 | `m_ssitsrc` | `clothing/sit/` |

`Wear()` 会根据人物当前状态在行走、站立、坐下动画之间切换，并使用 `m_nLayer` 控制各服装部位的叠放次序。证据见 [`cloth.Wear`](../../starhome_lz_ry_fcc_source/cltobj/clothclt.fcc#L188-L217) 和 [`mancloth01a`](../../starhome_lz_ry_fcc_source/cltobj/clothcltclass.fcc#L663-L688)。

Godot 中应把服装实现为角色根节点下的多个 `AnimatedSprite2D` 图层，并让所有图层共享：

- 当前动作；
- 八向方向；
- 当前帧；
- 人物锚点；
- 外观调色参数。

不要分别计时播放每个服装层，否则长时间移动后会发生错帧。

## 4. 建议的数据模型

装备资源不应再依赖目录名猜测，建议为每个业务装备保存显式身份：

```json
{
  "id": "gun1",
  "name": "新兵能量炮",
  "visuals": {
    "inventory": ".../equip/bag/gun1",
    "equipment_panel": ".../equip/dlg/gun1",
    "world": ".../equip/body/gun1"
  },
  "weapon": {
    "projectile": ".../bullet/bullet1",
    "muzzle_sound": ".../sound/gun/gun1.gsm",
    "impact_effect": "gun01BZ",
    "impact_mapping_confidence": "inferred_from_name"
  }
}
```

`impact_mapping_confidence` 必须保留，因为命中特效的精确索引缺少服务端原始表，详见第 7 节。

## 5. 战车与阴影

### 5.1 运行时不是同名约定

装备战车时，`bodywork` 创建 `new TankShadow(m_ntype, user)`。`TankShadow` 根据整数类型加载阴影，再同步人物朝向并跟随人物坐标。证据见 [`bodywork` 装备逻辑](../../starhome_lz_ry_fcc_source/cltobj/equipclt.fcc#L1844-L1855) 和 [`TankShadow`](../../starhome_lz_ry_fcc_source/person.fcc#L40-L92)。

荣耀客户端的完整硬编码表如下：

| `m_ntype` | 阴影 ALE | 已识别的主要正文类 | 当前荣耀缓存 |
| ---: | --- | --- | --- |
| 1 | `tank1shadow.ale` | 新兵战车、部分新手/住宅战车 | 有 |
| 2 | `tank2shadow.ale` | 领航者、勇敢者、先驱者、千级战车 | 有 |
| 3 | `tank3shadow.ale` | 冲锋者、突袭者、狙击者、征服者 | 有 |
| 4 | `tank6shadowL.ale` | 炎帝、黄帝、G91、G92 | 有 |
| 5 | `tank6shadowD.ale` | 大禹、尧、蚩尤、帝王战车 | 有 |
| 6 | `tank6shadowZ.ale` | 未在基础战车类中确认 | 缺 |
| 7 | `tank7shadowL.ale` | 未在基础战车类中确认 | 缺 |
| 8 | `tank7shadowD.ale` | 未在基础战车类中确认 | 缺 |
| 9 | `tank7shadowZ.ale` | 未在基础战车类中确认 | 缺 |
| 10 | `tank8shadow.ale` | 未在基础战车类中确认 | 有 |
| 11 | `tank9shadowL.ale` | 未在基础战车类中确认 | 缺 |
| 12 | `tank9shadowD.ale` | 未在基础战车类中确认 | 缺 |
| 13 | `tank9shadowZ.ale` | 未在基础战车类中确认 | 缺 |
| 14 | `tank1000shadow.ale` | 特殊千级/旧系统战车候选 | 缺 |
| 15 | `robotshadow.ale` | 机甲/机器人 | 有 |
| 16 | `tank14shadow.ale` | 该亚级战车 | 有 |
| 17 | `guardshadow.ale` | 护卫形态 | 缺 |
| 18 | `tank15shadow.ale` | 圣诞战车 | 有 |
| 19 | `tankg91shadow.ale` | G91 系特殊影子 | 根目录缺；`equip/body/` 中有同名文件 |

“当前荣耀缓存”只表示目前下载到 `starhome_lz_ry_full/raw/pic3/equip/` 的情况。FCC 已经确定引用但缓存缺失的文件，应进入资源缺口清单，不能静默换成另一辆战车的阴影。

### 5.2 实现约束

- 正文动画与阴影是两个独立节点；
- 阴影节点位于正文节点之下，但跟随同一世界坐标；
- 阴影方向由战车方向同步；
- 隐身时原客户端会单独隐藏/降低阴影可见性，不能只修改正文透明度；
- 不要用 Godot 自动生成椭圆阴影替换已确认存在的专用战车阴影。

## 6. 怪物与阴影

### 6.1 三状态一一对应

经典怪物类同时声明：

| 本体 | 阴影 |
| --- | --- |
| `m_sMoveAle` | `m_sMoveShadow` |
| `m_sStandAle` | `m_sStandShadow` |
| `m_sActionAle` | `m_sActionShadow` |

`NpcShadow` 构造时复制三条阴影路径，跟随怪物对象；怪物切换站立、移动或攻击时，分别调用 `ChangeToStand`、`ChangeToMove`、`ChangeToAction`，并把怪物帧映射到阴影帧。证据见 [`NpcShadow`](../../starhome_lz_ry_fcc_source/npcbaseclt.fcc#L310-L350)。

### 6.2 奥姆成虫示例

`Npc成虫1` 的荣耀定义为：

| 状态 | 本体 | 阴影 |
| --- | --- | --- |
| 移动 | `pic2/npc/chengchong/chc01a.ale` | `pic2/npc/chengchong/chc01ayiny.ale` |
| 站立 | `pic2/npc/chengchong/chc01b.ale` | `pic2/npc/chengchong/chc01byiny.ale` |
| 攻击 | `pic2/npc/chengchong/chc01c.ale` | `pic2/npc/chengchong/chc01cyiny.ale` |

`Npc成虫2` 使用另一套有色正文，但复用 `Npc成虫1` 的三套阴影，并用自己的调色板。这证明：

- 怪物变种与阴影不是一对一；
- 调色板通常只作用于正文；
- 同骨架、同尺寸的变种应复用阴影资源。

原始定义见 [`Npc成虫1/2`](../../starhome_lz_ry_fcc_source/npcclt1.fcc#L380-L469)。首批四类怪物的现有整理仍保存在 [`monster_animations.json`](../data/monster_animations.json)。

### 6.3 例外

- 有些怪物的移动、站立、攻击三种状态共用同一个阴影 ALE；
- 有些怪物有三个独立阴影 ALE；
- 少数类虽然填写了阴影字段，却注释掉 `new NpcShadow(this)`，运行时不显示阴影；
- 补丁型怪物在 `npc_catalog.json` 的 `attr_30` 与 `attr_31` 中分别保存成组的正文和阴影文件，必须按原数组位置配对，不能只按文件名排序。

因此导入器应允许 `shadow_profile` 为“无阴影”“单文件复用”或“三状态文件”三种形态。

## 7. 能量炮、子弹与命中特效

### 7.1 可以静态确定的调用链

```text
能量炮装备类
  ├─ m_sMoveSrc          场景中的炮身八向动画
  ├─ m_sbulletclassname  通常为 laserbullet
  ├─ m_sbulletfile       飞行子弹 ALE
  └─ m_sgunsoundfile     开炮声音
             │
             ▼
laserbullet 从 pic3/bullet/ 加载 m_sbulletfile
             │
             ▼
命中结果回调携带 AviFileIndex / SoundFileIndex / PaletteIndex
             │
             ▼
全局数组 m_szBulletAvi / m_szBulletSound / m_szBulletEffectPalette
             │
             ▼
laserblast 播放最终命中特效
```

炮身到飞行子弹的映射是**确定**的。基础能量炮如下：

| 能量炮 | 场景炮身 | 飞行子弹 | 发射声 |
| --- | --- | --- | --- |
| 新兵能量炮 | `body/gun1.ale` | `bullet1.ale` | `gun1.gsm` |
| 加强能量炮 | `body/gun2a.ale` | `bullet2.ale` | `gun2.gsm` |
| 突袭能量炮 | `body/gun2.ale` | `bullet3.ale` | `gun3.gsm` |
| 鳄式能量炮 | `body/gun3.ale` | `bullet4.ale` | `gun4.gsm` |
| 鳄式加强能量炮 | `body/gun4.ale` | `bullet5.ale` | `gun5.gsm` |
| 鳄式突袭能量炮 | `body/gun5.ale` | `bullet6.ale` | `gun6.gsm` |
| 虎式能量炮 | `body/gun6.ale` | `bullet7.ale` | `gun7.gsm` |
| 虎式加强能量炮 | `body/gun7.ale` | `bullet8.ale` | `gun8.gsm` |
| 虎式突袭能量炮 | `body/gun8.ale` | `bullet9.ale` | `gun9.gsm` |
| 复仇者激光炮 | `body/gun9.ale` | `bullet10.ale` | `gun10.gsm` |
| 拥护者激光炮 | `body/gun10.ale` | `bullet11.ale` | `gun10c.gsm` |
| 聚能激光炮 | `body/gun11.ale` | `bullet12.ale` | `gun11b.gsm` |
| 连击式激光炮 | `body/gun12.ale` | `bullet13.ale` | `gun12a.gsm` |
| 艾莉斯级能量炮 | `body/gun14.ale` | `bullet14a.ale` | `gun12a.gsm` |

发射逻辑见 [`EnergyGunBase.Action`](../../starhome_lz_ry_fcc_source/cltobj/equipclt.fcc#L2771-L2817)，子弹加载逻辑见 [`laserbullet`](../../starhome_lz_ry_fcc_source/bullet.fcc#L121-L155)。

### 7.2 命中特效为什么不能完全静态还原

能量炮类中旧的 `m_sblasteffectfile` 和 `m_sblastsoundfile` 已被注释。命中时，被击中对象收到的回调参数包括：

- `AviFileIndex`；
- `SoundFileIndex`；
- `BulletEffectPalette`。

客户端再用这三个索引访问全局表并创建 `laserblast`。证据见 [`OnUserMyAttack`](../../starhome_lz_ry_fcc_source/mainclient_me.fcc#L1470-L1474) 和 [`laserblast`](../../starhome_lz_ry_fcc_source/effect.fcc#L6-L54)。

也就是说：

- 荣耀客户端明确拥有所有可播放的命中特效；
- 具体一次攻击使用哪个索引，由攻击结果消息决定；
- 当前没有服务端源码，不能从能量炮客户端类中恢复百分之百可靠的索引表。

### 7.3 可用于首版复刻的候选映射

全局表和荣耀素材中都存在 `gun01BZ.ale` 至 `gun14BZ.ale`。按名称建立如下映射是**高度可能**的，但应保留可配置性：

| 炮类 | 候选命中特效 |
| --- | --- |
| `gun1`～`gun5` | `gun01BZ.ale`～`gun05BZ.ale` |
| `gun6`～`gun9` | `gun06BZ.ale`～`gun09BZ.ale` |
| `gun10`～`gun14` | `gun10BZ.ale`～`gun14BZ.ale` |

全局数组还包含 `blasteffect_1/2/3.ale` 等早期通用特效，说明旧服务端可能对部分低级炮使用通用爆炸效果。因此首版可以按 `gunNNBZ` 配置，后续通过原游戏录像或动态抓取命中回调校正，而不要把该推断写死在武器脚本中。

全局命中特效表见 [`golbalstring.fcc`](../../starhome_lz_ry_fcc_source/global/golbalstring.fcc#L5-L65)。

## 8. 维修臂与维修特效

### 8.1 地面维修臂：场景 ALE 自己播放动作

地面维修臂与其他装备一样具有背包、面板、场景三视图。开始维修时，客户端：

1. 令维修臂和玩家朝向维修目标；
2. 对维修臂当前的 `m_sMoveSrc` 循环执行 `PlayAni("move", 60)`；
3. 播放该维修臂类配置的 `sound/Repair/*.gsm`；
4. 停止维修后结束循环并恢复朝向跟随。

证据见 [`Repair.PlayRepair`](../../starhome_lz_ry_fcc_source/cltobj/equipclt.fcc#L4702-L4735) 和 [`OnBeginRepair`](../../starhome_lz_ry_fcc_source/mainclient_char.fcc#L1058-L1088)。

目前没有在地面普通维修调用链中发现“维修臂型号 -> 独立维修光效 ALE”的硬映射。可确认的关系是：

```text
维修臂装备类 -> body/repair*.ale（动作本体） -> repair*.gsm
```

而不是：

```text
维修臂装备类 -> body/repair*.ale -> 某个额外 repair_effect.ale
```

### 8.2 自维修：独立于维修臂型号

战车自维修调用 `OnBeginRepairDIY()`，创建：

- 正文特效：普通战车使用 `other/MinSpan1.ale`，幻影机甲等分支使用 `other/MinSpan2.ale`；
- 特效阴影：`other/MinSpanShadow.ale`；
- 声音：`sound/bool/repair001.gsm`。

这条调用链只检查载具类型/状态，不读取当前维修臂类，所以它是战车自维修效果，不是某一型号维修臂的专属特效。证据见 [`cltplayer/repair.fcc`](../../starhome_lz_ry_fcc_source/cltplayer/repair.fcc#L9-L118)。

### 8.3 两类容易误认的候选素材

| 素材/目录 | 实际系统 | 是否接入地面普通维修 |
| --- | --- | --- |
| `SpacePlayer/pic/effect/Repair_effect.ale` | 太空维修臂，字段名为 `m_sEffectAviFilePath` | 否 |
| `pic3/War_Pic/RecoveryArm/` | 城战炮台/恢复臂建筑，带独立攻击和阴影 | 否 |

太空维修臂引用见 [`space_airship_cltclass.fcc`](../../starhome_lz_ry_fcc_source/cltobj/space_airship_cltclass.fcc#L678-L717)。这两组素材可以留作后续太空和城战模块，但不应因为名称相似而混入首批地面维修臂。

## 9. 对复刻工程的落地要求

### 9.1 导入阶段

- 以 FCC 类名作为稳定业务 ID，不以 ALE 文件名作为业务 ID；
- 每个装备输出 `inventory`、`equipment_panel`、`world` 三个显式引用；
- 服装额外输出 `walk`、`stand`、`sit` 与 `layer`；
- 战车输出 `tank_shadow_type`，再由独立表解析阴影；
- 怪物输出三个动作与三个阴影的显式映射；
- 武器分别输出 `world_sprite`、`projectile`、`muzzle_sound`、`impact_effect`；
- 对推断出的命中特效写入置信度，不得伪装成已确认数据；
- FCC 已引用但本地缺失的素材写入缺口报告，不得自动拿相近图片替换。

### 9.2 运行时

- 战车、炮身、维修臂、阴影作为同一载具组合下的独立节点；
- 所有八向装备跟随载具统一方向，不自行计算方向；
- 阴影跟随本体坐标和方向，但保持独立透明度与显示开关；
- 怪物换动作时同时换正文与阴影状态；
- 飞行子弹和命中特效是两个生命周期对象；
- 普通维修使用维修臂自身动作，自维修才创建 `MinSpan` 特效；
- 所有映射从数据资源读取，不在场景脚本里拼文件名。

## 10. 仍待动态验证的项目

1. `gun1`～`gun14` 与 `gunNNBZ` 命中特效的服务端最终索引；
2. `blasteffect_1/2/3` 在荣耀服务器中具体对应哪些低级炮；
3. `TankShadow` 表中当前荣耀缓存缺失或目录错位的引用，是否能从旧 FCC 下载地址补齐；
4. 个别补丁怪物 `attr_30/attr_31` 的状态顺序和无阴影例外；
5. 地面维修是否存在只由服务器事件触发、当前 FCC 静态搜索未覆盖的目标受修视觉效果。

上述项目不会阻碍首版复刻：现有确定关系已经足够建立正确的数据模型；不确定项全部可以作为配置表后续校正。
