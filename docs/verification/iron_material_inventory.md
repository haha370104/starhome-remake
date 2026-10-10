# 铁块背包展示修复

- 修复对象是 `iron`（铁），不是 `iron_ore`（铁矿）。原定义只有名称占位，没有图标；描述仍是导入占位文本。
- 在后加载的工业材料目录中替换同一身份的占位定义，不改配方、价格、数量或堆叠上限。旧存档按原物品身份加载即可取得修复后的展示，不需要迁移实例。
- 描述来自本地荣耀版 `cltobj/stuffclt2.fcc:2532` 的 `String7501`，由 `great/code_string.fcc:4161` 解析为“金属块，打造与合成的原材料之一。”。
- 图标由该类引用的原始 ALE 和外部 ACT 调色板恢复，尺寸 45×26；原始文件 SHA256 记录在物品定义中。没有使用默认调色板代替原始 ACT，也没有下载资源。
- `assets/` 按项目现有约定不进入 Git；可运行 `python3 tools/restore_iron_material_icon.py` 从本地 `../starhome_lz_ry_full/raw/` 校验原始文件并重新生成 `assets/items/materials/iron.png`。

## 验证

- Godot 4.7.2 headless editor 扫描通过，无脚本解析错误。
- `godot --headless --path . --script tests/ui/runtime/iron_material_runtime_test.gd`：63 checks，0 failures。
- `godot --display-driver wayland --rendering-driver opengl3 --path . --script tests/ui/runtime/iron_material_runtime_test.gd -- --capture-iron`：65 checks，0 failures；NVIDIA RTX 2060、OpenGL compatibility 实际渲染，截图位于 `.godot/iron-inventory.png`。
- 使用真实主场景、进程内服务器和隔离存档，覆盖已有铁块、真实生产窗口提炼、背包异步图标加载、实际悬停说明、保存及服务器重启恢复；铁矿定义不变。
- 渲染截图手动检查确认铁块图标和正确说明均可见。截图捕获主动绘制，不依赖窗口遮挡时可能不发出的 `frame_post_draw` 信号；之前等待该信号的超时尝试不计为通过。
- 渲染日志有 libdecor 装饰插件回退和一次着色器缓存重编译警告，无脚本错误。未使用或修改日常存档，没有执行修改性 Git 操作。
