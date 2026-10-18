# 原版资源离线解码

算法择取自社区提交 `1f46553bd479d3413fdb082444e77cb8831e03dc`，
保留原逻辑路径；不接入游戏启动，不自动下载，不改运行素材目录。
Python 3.10+；精灵另需 Pillow。以下命令从主仓库根目录执行：

```powershell
python -m tools.recovery.maps.pkh_unpack input.pkh output.bin
python -m tools.recovery.sprites.ale_sprite input.ale output-folder --max-sheet-size 2048
python -m tools.recovery.index.parse_starhome_files_dir files_dir.decoded --csv resource_index.csv
python -m unittest discover -s tests/tools -p test_recovery.py
```

PKH 为纯 Python LZW 变体，验证长度前缀并限制输出；已与本地 497 份原始导航解码结果逐字节对照。
ALE/RLE0/AEX 保留帧序、原点、透明度、调色板；像素解码与图集排版分开。
已核对三种封装的 v1/v3 共八份素材、213 帧；修正社区版本的 RGB565 换算、
稀疏行标记消耗行数及 AEX v1 色键，与当前已导入图集逐帧像素一致。
原图尺寸、顺序不可当成战车方向映射；方向映射仍由现有表现配置负责。

`RawSpriteWorkspace`、`RawFccWorkspace` 是临时目录上下文管理器。
路径先验证在调用方指定的原档案根目录内，再读文件；退出时清理本次临时产物。
调用方把需要的最终 PNG、元数据及来源哈希审核后写入 `assets` 子模块。
不要将原版全量档案、DLL、临时输出加入主仓库。

FCC/FTC **仍依赖原版 32 位 fkernel.dll**，不是纯 Python 解密：

- Windows：设置 `STARHOME_FTC_DECODER` 为本地已编译的 `fch_decode.exe`；
  CAB 展开使用系统 `expand.exe`。或设置 `STARHOME_MINGW_CC` 编译 `ftc/fch_decode.c`。
- Linux：原版 DLL 经 Wine 调用；需要 32 位 MinGW、Wine 和 cabextract。
- `RawFccWorkspace(raw_root, fkernel=...)` 显式指定原始目录及 DLL，示例：

```python
from pathlib import Path
from tools.recovery.fcc_workspace import RawFccWorkspace
with RawFccWorkspace(Path('/local/original/raw'), Path('/local/original/fkernel.dll')) as files:
    text = files.text('NFT_BT/map/blackroom/blackroom.fcc')
```

FCC 本轮只验证路径、脚本加载及与现有 native wrapper 的调用约定；
未在缺少 DLL 的环境中声称完成原生解码验收。
`XY20` 为二进制场景数据，不当作 FCC 文本输出。

地图恢复见 `../recover_glory_map_gaps.py`：默认只打印方案，`--apply` 写入独立补充包。
四条新增来源为三套场景表现；缺少入站传送证据的地图未虚构入口。
