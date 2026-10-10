# 典型工业材料背包展示修复

## 范围

- 元素材料16种：铜、硅、石墨、银、金、铬、镍、锌、镭、硫、磷、钾、钛、钪、镁、钡。
- 合金14种：铜铁合金、硅铁合金、硅铜合金、银钢合金、银铜合金、金钢合金、金铜合金、镭铬合金、镍锌合金、锌钛合金、钡镁合金、锌钡合金、钛铬合金、钪镁合金。
- 合成材料5种：合成线、合成绒、合成丝、合成棉、合成纤维。
- 不包含原矿、其他未恢复的普通材料、强化石、精炼石、锻造材料或其他扩展检查结果。此前已修复的铁块定义保持不变。

## 实现与来源

- 在后加载的工业材料目录中，按原稳定身份覆盖19个名称占位定义，更新14个现有工业材料定义；银铜合金、金铜合金在其现有拆解材料目录中更新，避免双重覆盖。不修改荣耀占位源目录或新增物品身份。
- 描述逐项解析自本地荣耀版 `cltobj/stuffclt2.fcc` 的 `m_sDesc` 和 `great/code_string.fcc`。保留原文本，包括合成丝描述原有的无句号结尾；不把硅、石墨统一描述为金属块。
- 恢复23个缺失背包PNG图标；12个已可加载的ALE引用保持原样。图标使用该类实际声明的ALE，以及未被注释掉的外部ACT调色板；没有借用其他金属或默认调色板。
- 银的原ACT为771字节，原资源索引登记的MD5为 `0caea474b1f0acd0d3f54103bc99038d`；前768字节为256个RGB条目，末尾为CRCRLF。恢复器验证完整源文件SHA256，调色时不把尾部作为额外颜色。
- 每项记录原类、描述字符串、来源行号、原尺寸和ALE/ACT文件SHA256。保持原堆叠上限：钾和钡镁合金为999，其余本次材料为99；不改变配方、价格、掉落、数量或持久化策略。
- 旧存档通过原物品身份加载修复后的图标与描述，不需要改写物品实例或迁移存档。

## 本地图标重建

`assets/` 按项目约定不进入Git。使用已有本地 `../starhome_lz_ry_full/raw/` 重建缺失图片：

```sh
python3 tools/restore_industrial_material_icons.py
python3 tools/restore_industrial_material_icons.py --check
```

恢复器先验证全部35项来源和图像，再写23个PNG；检查模式不写配置或图像。没有下载资源。

## 历史回归记录

```sh
python3 -m unittest tools/tests/test_industrial_material_icons.py
godot --headless --editor --path . --quit
```

旧的 `industrial_material_runtime_test.gd` 已删除。它依赖已淘汰的 `player_changes_runtime_test.gd` 综合夹具，并硬编码35项历史材料清单；当前材料身份由目录/领域测试覆盖，制造链路由生产权威测试覆盖。上面的 Python 来源检查和 Godot 编辑器扫描仍可作为资源回归入口。

有可用桌面时，可使用 `-- --capture-industrial-materials` 捕获 `.godot/industrial-materials-inventory.png`。无渲染环境的测试不等同于实机画面验收。

## 本轮验证结果

- 原版来源、描述、像素、调色板、堆叠上限和只读检查模式：6项Python测试通过。
- Godot 4.7.2 headless编辑器扫描通过，没有脚本解析错误。
- 真实主场景headless测试：834 checks，0 failures；包含35种材料的两端展示、实际悬停、保存重启及三个真实生产按钮链路。
- Wayland/OpenGL compatibility实际渲染：NVIDIA RTX 2060，836 checks，0 failures；截图已人工检查，35种图标均可见，未保留测试合成悬停带来的批量高亮。
- 原有铁块主场景回归：63 checks，0 failures。
- 修复后再次遍历实际目录，本次35种材料缺失图标、占位描述和空白图像均为0；没有修改其余材料。
- 与修改前配置比较，35项均保留稳定身份、名称、类型、堆叠上限、配方证据及经济字段；没有非目标材料变更，原有Git暂存区保持不变。
- `tests/domain/glory_item_runtime_catalog_test.gd` 仍有12项旧 `logical_id` 的bag/dlg/body路径断言失败。使用修改前两个材料目录重跑，复现完全相同的12项失败；没有顺带修改该旧夹具。
- 新主场景测试退出时仍有4个ObjectDB实例和3项资源未清理的诊断；渲染环境另有libdecor回退及着色器缓存重编译警告。功能断言通过，但不将退出日志描述为完全无告警。
