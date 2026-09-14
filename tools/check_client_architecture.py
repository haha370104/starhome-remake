#!/usr/bin/env python3
"""Guard the refactored client boundaries without exempting future dependencies."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FOCUSED_FILES = (
    "scripts/main_hall.gd",
    "scripts/client/gameplay/map_travel_controller.gd",
    "scripts/client/gameplay/combat_interaction_controller.gd",
    "scripts/client/gameplay/world_interaction_controller.gd",
    "scripts/client/presentation/client_world_view.gd",
    "scripts/client/presentation/player_presentation_binding.gd",
    "scripts/client/state/player_panel_session.gd",
)


def inspect_source(path: str, source: str) -> list[str]:
    """Return violations for a source file; comments do not establish dependencies."""
    errors = []
    code = "\n".join(line for line in source.splitlines() if not line.lstrip().startswith("#"))
    client = path.startswith("scripts/client/")
    shared = path.startswith("scripts/shared/")
    component = path.startswith("scripts/client/ui/components/")
    focused = path in FOCUSED_FILES or component
    dependencies = re.findall(r'["\']res://(scripts/[^"\']+)["\']', code)
    if path == "scripts/main_hall.gd":
        if len(source.splitlines()) > 300:
            errors.append("入口超过 300 行，请审查职责")
        if re.search(r"func (_unhandled_input|_on_|_request_|_handle_|_move_to)", code):
            errors.append("入口重新引入输入或业务回调")
    elif focused and len(source.splitlines()) > 500:
        errors.append("重构模块超过 500 行，请审查职责")
    if path != "scripts/main_hall.gd" and "scripts/main_hall.gd" in dependencies:
        errors.append("业务模块反向依赖主场景")
    if client and any(dep.startswith("scripts/server/") for dep in dependencies):
        errors.append("客户端直接依赖服务器实现")
    if shared and any(dep.startswith(("scripts/client/", "scripts/server/")) for dep in dependencies):
        errors.append("共享投影依赖具体客户端或服务器")
    if path.startswith(("scripts/domain/", "scripts/server/")) and any(
        dep.startswith("scripts/client/") for dep in dependencies
    ):
        errors.append("领域或服务器依赖客户端")
    if focused and re.search(r"\bhud\.(hint_label|root_control|popup|state|minimap_player_dot)\b", code):
        errors.append("业务代码访问 HUD 内部控件")
    if focused and re.search(r"get_parent\(|get_node\([\"']/?root", code):
        errors.append("业务依赖通过场景树查找，必须显式注入")
    if component and re.search(r"\b(GameWindowManager|PlayerPanelSession|CurrentPlayer|ClientNetworkAdapter)\b", code):
        errors.append("共享控件依赖窗口会话或传输")
    if component and any(dep.endswith(("character_panel.gd", "inventory_panel.gd", "vehicle_equipment_panel.gd")) for dep in dependencies):
        errors.append("共享控件反向依赖具体面板")
    return [f"{path}: {error}" for error in errors]


def main() -> int:
    """Check all runtime dependencies plus contracts of the new ownership modules."""
    from check_gdscript_doc_comments import inspect_file

    errors = []
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        relative = path.relative_to(ROOT).as_posix()
        source = path.read_text(encoding="utf-8")
        errors.extend(inspect_source(relative, source))
        if relative in FOCUSED_FILES or relative.startswith("scripts/client/ui/components/"):
            errors.extend(inspect_file(path))
            if re.search(r"##.*(对应的模块操作|对应的信号回调|调用方传入的参数；)", source):
                errors.append(f"{relative}: 使用了没有契约含义的模板注释")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("CLIENT_ARCHITECTURE_OK: entry size, dependencies, HUD, components, contracts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
