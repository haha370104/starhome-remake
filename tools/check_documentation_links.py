"""只读检查项目 Markdown 的本地链接与 docs 导航覆盖，不执行文档内命令。"""

from pathlib import Path
import re
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    """扫描维护入口和全部 docs 文档，报告失效本地链接及未登记的文档；返回失败数量是否非零。"""
    documents = sorted((ROOT / "docs").rglob("*.md"))
    entries = documents + [ROOT / p for p in (
        "README.md", "PROJECT_CONTEXT.md", "使用说明.md", "assets/README.md", "data/npcs/README.md"
    )]
    failures = []
    links = 0
    for document in entries:
        source = document.read_text(encoding="utf-8-sig")
        # 忽略示例代码围栏，不把示例 Markdown 当实际导航。
        source = re.sub(r"```.*?```", "", source, flags=re.S)
        for match in re.finditer(r"\[[^\]\n]*\]\(([^)\n]+)\)", source):
            target = match[1].strip().strip("<>")
            if re.match(r"^[a-z]+://", target, re.I) or target.startswith("#"):
                continue
            target = unquote(target.split("#", 1)[0])
            if not target:
                continue
            links += 1
            if not (document.parent / target).exists():
                line = source[:match.start()].count("\n") + 1
                failures.append(f"{document.relative_to(ROOT)}:{line}: {target}")
    index = (ROOT / "docs/README.md").read_text(encoding="utf-8-sig")
    for document in documents:
        relative = document.relative_to(ROOT / "docs").as_posix()
        if relative != "README.md" and relative not in index:
            failures.append(f"docs/README.md 未登记: {relative}")
    print(f"文档 {len(entries)} 篇，本地链接 {links} 条，问题 {len(failures)} 项")
    for failure in failures:
        print(failure)
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
