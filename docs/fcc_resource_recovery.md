# FCC 解密与游戏资源恢复流程

整理日期：2026-08-31。依据本工作区已保存的程序源码、解密产物、下载报告与地图补抓记录。

本文复盘已经验证过的流程，没有在整理时重新连接官网，也没有启动或注入原游戏进程。服务器地址和下载数量均是既有采集记录，不代表官网今日的实时状态。

## 1. 核心结论

`ourgamestart.fcc` 是启动、更新和登录流程的引导脚本，不是全部素材的哈希映射表。它提供更新根地址和本地缓存命名空间，并要求引擎读取 `files_dir.dz`。

恢复过程分为三个不同问题：

1. **解密容器**：借用原版 `fkernel.dll` 的 `FTGameOS::nmemfile::UnCode`，移除 `FTC1` / `FTC!` 层。
2. **找回文件**：解析 `files_dir.dz` 的逻辑路径，直接向更新地址下载，校验原件的大小和 MD5；不需要先破解八位 `.fch` 缓存名生成算法。
3. **解析内容**：CAB 展开、FCC 文本转码、ALE 动画转图。大部分 ALE 本来就没有 FTC 加密，只是专有格式。

完整链路：

```text
启动参数中的 ourgamestart.fcc 地址
  → 下载的 FTC! 文件
  → 原版 DLL 的 UnCode(..., "0003")
  → MSCF/CAB
  → 展开得到引导 FCC 脚本
  → 读取更新根地址、DefLocMaping、CtrlFilesDir
  → 下载 files_dir.dz（FTC1）
  → UnCode 解开资源清单
  → 按字节还原逻辑路径，读取大小/MD5
  → 更新根地址 + 逻辑路径 → 下载原件并校验
  → 按文件头分流
       FTC1 / FTC! → 解密、必要时展开 CAB → 脚本/表/其他数据
       ALE / RLE0 / AEX → 解码动画 → PNG 图集 + frames.json
       PNG / JPG / 音频等 → 保留原件
  → 扫描 FCC/地图中的额外依赖 → 同版本官网准确路径补抓
```

最后一环不能省略：**清单下载完成 ≠ 官网文件全集恢复完成。**

## 2. 如何解密启动 FCC

### 2.1 先看文件头，不按扩展名猜格式

`.fch` 是缓存文件名后缀，并不表示统一的加密格式。`.fcc` 也可能包装了不同载荷。

| 文件头 | 已验证的处理方式 |
|---|---|
| `FTC!` | 调用 `UnCode`，本项目样本得到以 `MSCF` 开头的 Microsoft CAB，再展开 |
| `FTC1` | 调用 `UnCode`，本项目样本直接得到脚本、清单或其他数据 |
| `ALE\0`、`RLE0`、`AEX\0` | 使用动画格式解析器；不能因为来自 `.fch` 就再次解密 |
| `MSCF` | 已经是 CAB，直接展开 |
| PNG、JPEG 等标准头 | 保留并按相应格式读取 |
| 解密后为 `XY20` | 编译载荷，保留二进制，不能声称已经恢复源代码 |

本地荣耀版样本：启动 FCC 为 7,396 字节，头部为 `46 54 43 21`（`FTC!`）；保存的解密结果为 7,381 字节，头部为 `4D 53 43 46`（`MSCF`）。

### 2.2 不是重写密码算法，而是复用原客户端函数

辅助程序源码：[fch_decode.c](../../fch_decrypt_tool/fch_decode.c)。程序：[fch_decode.exe](../../fch_decrypt_tool/fch_decode.exe)。

它完成以下操作：

1. 通过 `LoadLibraryA` 加载指定的原版 `fkernel.dll`。
2. 用 `GetProcAddress` 查找导出符号 `?UnCode@nmemfile@FTGameOS@@QAEHPBD@Z`。
3. 按引擎内存文件布局构造 `NMemFile`，字段为 `data`、`capacity`、`size`、`position`、`grow`。
4. 使用该 DLL 的内存分配器为输入分配缓冲区，读入文件。
5. 以 `__thiscall` 调用 `UnCode(&mem, "0003")`。
6. 将调用后的 `mem.data` 和 `mem.size` 写为解密产物。

这相当于把原客户端已有的解码功能包装成一个可批处理的小工具；不是把原游戏登录起来后抓取内存中的每份脚本，也不是已经独立实现了底层密码算法。

### 2.3 DLL 与位数的约束

辅助程序必须为 **32 位**，因为目标 DLL 是 32 位。解密入口通过导出名定位，但工具还有两个版本绑定的内部地址：

- 内存分配函数：DLL 基址 + `0x12D0`。
- 内存管理器对象：DLL 基址 + `0x73488`。

因此不能把这个 exe 当成适配所有 FancyBoxII 版本的通用工具。更换 DLL 时要核对内部布局、偏移和调用约定。

本次整理时，本机 `newsystem_jz/fkernel.dll` 与 `newsystem_ry/fkernel.dll` 的 SHA-256 相同：

```text
6DDA83202BDF7F671325D12D1741832104852192CF640DCFD3DA27145BF6FCE6
```

### 2.4 `companyid = "0003"` 的首次来源

这个参数不是通过账号口令猜测，也不是暴力枚举得到的。首次先静态定位
`UnCode(const char* key)` 使用的 `companyid` 指针，再在用户启动原客户端后，
用 `OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION)` 和 `ReadProcessMemory`
只读确认对应数据。

已经重新核对早期任务记录（2026-08-25 11:46:42 的采样）：

- `companyid_ptr.bin` 为 4 字节 `B8 05 5B 0A`，按小端解释得到当次进程地址 `0x0A5B05B8`。
- `companyid_value.bin` 为该处读取的 1024 字节，开头 `30 30 30 33 00` 即 ASCII `0003\0`。
- 随后用字符串 `"0003"` 调用 DLL，能得到有效 CAB 或解密数据，验证了该参数。

依据是历史任务轮次 `01a0378f-0bf5-7e63-bf9d-01a3ab7cffce` 中保存的命令输出
`exec-59d7833a-389a-4727-ae16-2a61b74171dd`。这些历史 dump 不作为当前仓库内仍存在的文件引用；
地址只对当时进程有效，不应在新进程中硬编码。
此前本说明的“首次来源未保存”判断现已根据任务记录纠正。

一次性取参用过进程内存读取，但后续批量解密不需要游戏在线，也不是逐份抓取运行脚本。
本次文档整理没有再次读取原游戏内存。

### 2.5 CAB 展开与脚本转码

`FTC!` 解密后不是最终源码，要再运行 Windows `expand.exe -F:*`。CAB 内部文件即使仍叫 `ourgamestart.cab` 或 `xxx.fcc.cab`，实际内容也可能已经是文本，仍应根据内容判断。

原始文本通常使用 GBK/GB18030。阅读副本统一转成 UTF-8，保留原件。批量源码整理脚本会尝试 UTF-8、GB18030，并记录编码及是否发生替换字符；检测到 `XY20` 时进入独立二进制目录。

## 3. 如何从 FCC 找到资源目录

荣耀版引导脚本中的关键代码是：

```cpp
string m_sUpdateUrlPath = "http://update.ftxjjy.com/gameser/ry_www/";
pdesktop.DefLocMaping(m_sUpdateUrlPath, "starhome_lz_ry");
pdesktop.CtrlFilesDir(m_sUpdateUrlPath + "files_dir.dz");
DownLoadFile(m_sUpdateUrlPath + "files_dir.dz");
```

来源：[荣耀版启动 FCC](../../ourgamestart_ry_decrypted/ourgamestart.decoded.utf8.fcc)，关键调用在 357–359 行，地址初始化在 546 行。

含义分别是：更新根地址、本地映射命名空间、资源目录管理、下载目录文件。后续脚本通过逻辑路径加载资源，由引擎映射层处理缓存命中与下载。

不同版本必须分别读取各自引导脚本，不要混用清单和更新根地址：

| 版本 | 记录中的更新根目录 | 本地映射名 |
|---|---|---|
| 荣耀版 | `http://update.ftxjjy.com/gameser/ry_www/` | `starhome_lz_ry` |
| 免费版 | `http://update.ftxjjy.com/gameser/fr_www/` | `starhome_lz_fr` |
| 新激战版 | `http://update.ftxjjy.com/gameser/jznp_www/` | `starhome_jznp` |
| 老激战版 | `http://update.ftxjjy.com/gameser/jz_www/` | `starhome_jz` |

最初新激战版还验证过：网络下载的 `files_dir.dz` 与本地 `starhome_jznp/fd694613.fch` 逐字节一致。这证明了网络逻辑资源与本地哈希缓存之间的关系，但并不意味着清单中直接存放了八位缓存名。

`loadfile/DownloadFileList.fcc` 则是另一份预加载清单；当时的新激战样本只有 430 项，不能代替资源目录。

## 4. files_dir.dz 如何还原成可下载清单

荣耀版保存的 `files_dir.dz` 为 `FTC1`，经同一解密器得到 `starhome_lz_ry_resource_index.decoded`。

生产下载器：[download_full_resources.py](../../../work/download_full_resources.py)。

### 4.1 路径是前缀压缩，不是普通 CSV 文本

有效记录按右侧三个逗号切分为四个字段：

```text
压缩路径,版本/时间码,编码后的字节数,MD5
```

只有三个字段、没有 MD5 的记录，是删除指令（tombstone），不加入下载任务。

路径以 `+` 或 `*` 开头时，第二个字节表示沿用上一条有效路径的多少个前缀字节：

```python
path_bytes = previous_path_bytes[:prefix_length] + encoded_path[2:]
logical_path = path_bytes.decode("gbk")
```

关键约束：

- **前缀长度按字节计，不按 Unicode 字符计。** 先解码中文再切片会损坏路径，制造错误 URL 和伪重复项。
- 删除记录**不更新**下一条记录使用的前缀基准。
- 数字使用自定义 64 进制字符表，不是标准 Base64；依次为数字、大写字母、下划线、反引号、小写字母。
- 版本/时间码保留原值，没有充分证据时不强行解释成 Unix 时间。
- CSV 同时保存可读路径与 `path_bytes_hex`，方便审计和重放。

### 4.2 直接按逻辑路径下载，避开缓存名算法

URL 的构造方式：

```text
版本对应的更新根地址 + 原始逻辑路径（反斜杠改斜杠，并做百分号编码）
```

优先对清单保存的 GBK 路径字节编码，不是先默认转 UTF-8。极少数服务器对象只接受 UTF-8 路径；当前下载器会在 GBK 请求返回 404 后尝试 UTF-8，并继续用清单大小和 MD5 验证。

本地输出使用逻辑目录，例如 `raw/map/...`、`raw/pic3/...`。这只是逆向原件归档层；导入复刻工程时仍应转换为业务语义命名，不能把原目录结构当成新的工程组织规范。

### 4.3 校验与异常处理

- 大小和 MD5 校验针对**HTTP 下载原件**，可能仍是加密容器；不是针对解密后脚本，也不是 PNG 图集。
- 已存在文件必须重新匹配大小和 MD5 才跳过。
- 下载使用 `.part` 临时文件和 HTTP Range；完整且通过校验后才替换最终文件。
- 临时 502/超时有限重试；永久缺档和校验漂移单独记录。
- 校验路径穿越、Windows 非法名称、大小写冲突，不允许清单写出目标目录。
- 免费版曾有 20 个服务器当前文件不匹配旧清单，以及 3 个 404。当前文件保留在明确的异常记录中，不能冒充严格校验成功。

MD5 在这里用于匹配历史清单和发现损坏，不构成现代可信签名。尤其 HTTP 来源和无清单记录的补抓文件，都不应视为已通过发布者密码学认证。

## 5. 下载后如何解密与转图

### 5.1 FTC 容器批处理

[batch_decrypt_fcc.py](../../../work/batch_decrypt_fcc.py) 调用前述 32 位解密器：

- `FTC1` → `ftc_resources/decoded/`。
- `FTC!` → `ftc_resources/cab/`，再由 `expand.exe` 展开到 `ftc_resources/expanded/`。
- 使用 `--all-files` 时检查所有文件头，不仅处理 `.fcc` 后缀，因此 `.tab`、`.dz` 等 FTC 容器也能进入流程。
- 每个文件写入 inventory，失败写入独立清单。

[materialize_fcc_source.py](../../../work/materialize_fcc_source.py) 再从这些载荷中选择 FCC，转换为 UTF-8 源码树，保留 include、动态 Run 引用和来源摘要；它做文本物化，不是反编译 `XY20`。

### 5.2 ALE 是格式解码，不等于解密

使用当前的 [work/ale_sprite.py](../../../work/ale_sprite.py) 和 [batch_ale_sprites.py](../../../work/batch_ale_sprites.py)，不要误用 `fch_decrypt_tool` 内较早的转图副本。

解析器处理帧记录、逐行 RLE、透明度、尺寸及原点偏移。ALE v1 使用 256 色调色板，v3 使用 RGB565；批处理还识别 `RLE0` 和 `AEX` 包装。

输出为 `sheet.png`（大图分页）和 `frames.json`。后者保存帧顺序、图集矩形、尺寸和原点偏移，播放时必须一起使用。单看 `sheet.png` 无法恢复角色锚点和多层动画叠加。

需要 ACT 换色的动画应同时保留原始索引/调色板资料，或导出对应 ACT 变体；已烘焙成 RGBA 的默认 PNG 不能自动替代所有换色逻辑。标准图片和音频原件也应保留。

## 6. 为什么清单取全以后还缺素材

后来城区核查发现，荣耀版 `files_dir.dz` 更像更新/校验目录，不是服务器上的文件全集。

具体证据：[城区资源核查报告](../../city_map_resource_audit/README.md)。当时城区缺少的 19 种场景 ALE，均不依靠清单、直接按地图 FCC 引用路径从荣耀更新目录取得，并成功解码。

因此资源收集至少要做两轮：

1. **目录轮**：取回并校验 `files_dir.dz` 中所有有效记录。
2. **依赖轮**：分析 FCC、地图 `AddImg`、动画/音效等引用；本地没有时，按准确路径向同版本更新根地址补抓，并继续分析新获得的依赖。

当前已实现的专项补抓是地图 ALE，不是能够自动执行所有 FCC 分支、枚举任意动态资源的通用解释器。实现见 [official_asset_recovery.py](../tools/map_pipeline/official_asset_recovery.py)。其规则包括：

- 优先本地命中；只请求来自已识别引用的路径，不枚举猜测官网文件名。
- 只使用同版本来源，不自动模糊匹配或跨版本替换。
- 检查 HTTP 状态、体积上限、ALE 文件头，并实际解码后才标记成功。
- 无清单 MD5 时保存实际大小、MD5、SHA-256、URL 和解析状态；这些哈希用于后续识别同一份内容，不证明它符合一个不存在的历史期望版本。
- 成功和失败均缓存；默认不反复请求同一缺失路径，需要显式重试才能重探失败项。
- 补抓原件放在 `official_lazy_cache`，与经过清单校验的 `raw` 分开，避免把两种完整性混为一谈。

还可能存在运行时字符串拼接、服务器下发路径、不可达脚本分支及已下线文件。因此准确表述是“清单覆盖率”和“已发现依赖覆盖率”，不能保证“服务器历史上存在过的一切资源都已恢复”。

## 7. 荣耀版已经取得的结果

以下是已保存批处理报告，不含后来独立补抓缓存：

| 项目 | 结果 |
|---|---:|
| 清单有效记录 / 校验成功 | 18,975 / 18,975 |
| 删除指令（不下载） | 638 |
| 校验成功原件总字节 | 2,032,740,770（约 1.893 GiB） |
| ALE 转图成功 | 13,888 |
| ALE 总帧数 | 140,513 |
| FTC 容器成功处理 | 2,525 |
| 其中 FTC1 / FTC! | 1,290 / 1,235 |
| FCC 载荷 | 1,228 |
| 可读 UTF-8 FCC / XY20 编译载荷 | 1,220 / 8 |
| 可读源码总行数 | 1,066,012 |

目录与证据：

- [启动脚本和解密清单](../../ourgamestart_ry_decrypted/README.md)。
- [清单下载原件](../../starhome_lz_ry_full/README_全量资源说明.md)、[下载汇总](../../starhome_lz_ry_full/download_summary.json)。
- [FTC 处理汇总](../../starhome_lz_ry_full_parsed/ftc_resources/fcc_summary.json)、[ALE 处理汇总](../../starhome_lz_ry_full_parsed/ale_sprites/ale_summary.json)。
- [源码清单](../../starhome_lz_ry_fcc_source/fcc_source_manifest.json)。
- [额外官网补抓记录](../../starhome_lz_ry_full_parsed/official_lazy_cache/official_recovery_manifest.json)。

这些结果不是原游戏完整服务端工程。客户端脚本中能找到部分装备、怪物、配方和交互逻辑，不等于已经取得服务器专有逻辑、数据库或运行状态。

## 8. 重放命令

在工作区根目录 `C:/Users/tomato/Documents/Codex/2026-08-25/new-chat` 运行。以下使用新的重放目录，避免批量脚本重新展开 CAB 时替换现有解析成果。需要 Python 3、Pillow、Windows `expand.exe` 和匹配版本的引擎 DLL。

### 8.1 解密启动文件及资源清单（使用现有下载原件）

```powershell
$replayRoot = 'work/fcc_recovery_replay'
$decoder = 'outputs/fch_decrypt_tool/fch_decode.exe'
$engineDll = 'D:/Program Files/FancyBoxII Games/newsystem_ry/fkernel.dll'
New-Item -ItemType Directory -Path "$replayRoot/startup" -Force | Out-Null

& $decoder $engineDll `
  'outputs/ourgamestart_ry_decrypted/ourgamestart.encrypted.fcc' `
  "$replayRoot/ourgamestart.cab" '0003'
if ($LASTEXITCODE -ne 0) { throw '启动 FCC 解密失败' }
& expand.exe '-F:*' "$replayRoot/ourgamestart.cab" "$replayRoot/startup"
if ($LASTEXITCODE -ne 0) { throw '启动 CAB 展开失败' }

& $decoder $engineDll `
  'outputs/ourgamestart_ry_decrypted/files_dir.downloaded.dz' `
  "$replayRoot/resource_index.decoded" '0003'
if ($LASTEXITCODE -ne 0) { throw '资源清单解密失败' }
```

重新获取网络原件时，应先读取启动脚本确认更新根地址，再下载该地址下的 `files_dir.dz`；不要仅凭本地缓存文件夹名称猜版本，也不要把登录凭据写入批处理文档。

### 8.2 清单验证与下载

```powershell
python work/download_full_resources.py `
  work/fcc_recovery_replay/resource_index.decoded `
  --output work/fcc_recovery_replay/full `
  --base-url http://update.ftxjjy.com/gameser/ry_www/ `
  --dry-run
```

`--dry-run` 只解析清单并生成规划报告，不发起下载。确认路径、数量和版本后，移除 `--dry-run`，追加 `--workers 4 --retries 8 --timeout 60` 才执行下载。该操作可能下载约 1.9 GiB，不是本篇文档整理时执行的操作。

### 8.3 原件解包、源码物化和动画转图

```powershell
python work/batch_decrypt_fcc.py `
  work/fcc_recovery_replay/full/raw `
  work/fcc_recovery_replay/parsed/ftc_resources `
  --decoder outputs/fch_decrypt_tool/fch_decode.exe `
  --fkernel 'D:/Program Files/FancyBoxII Games/newsystem_ry/fkernel.dll' `
  --key 0003 --workers 4 --all-files

python work/materialize_fcc_source.py `
  work/fcc_recovery_replay/parsed/ftc_resources `
  work/fcc_recovery_replay/fcc_source

python work/batch_ale_sprites.py `
  work/fcc_recovery_replay/full/raw `
  work/fcc_recovery_replay/parsed/ale_sprites `
  --workers 8 --max-sheet-size 8192
```

每一步检查退出码和对应 `summary` / `failures`，再进入下一步；不能只凭生成了目录就认为成功。地图依赖补抓接入现有地图管线，地图结构与叠图细节另见 [地图资源管线](map_resource_pipeline.md)。

## 9. 验收标准

1. 启动 FCC 解密后得到合法 CAB，展开后能读到合理的引导脚本。
2. 资源目录按原始字节解析，无路径越界、伪重复或错误编码。
3. 下载报告逐件区分校验成功、服务器漂移、缺档和临时错误。
4. FTC 解包及 ALE 转图有逐件结果；编译载荷不伪装成源码。
5. 地图/FCC 引用与本地资源再次交叉核查，清单外补抓单独留来源记录。
6. 原始档案、解析成果、业务语义导入层互相分离，后续可以重跑、比对和追溯。
