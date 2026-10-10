import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
targets = {
    "scripts/server/commerce/authoritative_commerce_service.gd": [("execute", "state, command", "commerce_execute"), ("_build_bundle", "player, operation, merchant_id", "full_response"), ("build_task_bundle", "state, operation", "task_response")],
    "scripts/server/authoritative_server.gd": [("handle_peer_player_panel_command", "peer_id, command", "server_command"), ("_build_entity_combat_loadout", "target, state", "combat_loadout")],
    "scripts/shared/player_panel_projector.gd": [("build_bundle", "player", "full_player_projection"), ("changes", "before, after", "change_projection")],
    "scripts/client/state/current_player.gd": [("apply_bundle", "bundle", "client_full_apply"), ("apply_change", "change", "client_delta_apply")],
    "scripts/client/ui/windows/game_window_manager.gd": [("_apply_player", "player", "full_ui_refresh"), ("_apply_progression_change", "player, change", "delta_ui_refresh")],
}
patch = ["*** Begin Patch"]
for relative, functions in targets.items():
    source = (root / relative).read_text()
    patch.extend(["*** Update File: " + str(root / relative), "@@", " " + re.search(r"^extends .+$", source, re.M)[0], "+", '+const QuestButtonTimingProbe := preload("res://tests/ui/runtime/quest_button_timing.gd")'])
    for name, arguments, label in sorted(functions, key=lambda entry: source.find("func " + entry[0] + "(")):
        signature = re.search(r"^func " + re.escape(name) + r"\(.*?\)(?: -> [^\n:]+)?:\n", source, re.M | re.S)
        if signature is None:
            continue
        header = signature[0].rstrip("\n")
        returning = bool(re.search(r" -> (?!void)[^:]+:", header))
        wrapped = "_quest_timed_" + name
        wrapper = header + "\n\tvar profiling_started := Time.get_ticks_usec()\n"
        wrapper += ("\tvar profiling_result = " if returning else "\t") + wrapped + "(" + arguments + ")\n"
        wrapper += '\tQuestButtonTimingProbe.record("' + label + '", Time.get_ticks_usec() - profiling_started)\n'
        if returning:
            wrapper += "\treturn profiling_result\n"
        wrapper += "\n" + header.replace("func " + name + "(", "func " + wrapped + "(")
        patch.append("@@")
        patch.extend("-" + line for line in header.splitlines())
        patch.extend("+" + line for line in wrapper.splitlines())
patch.append("*** End Patch")
print("\n".join(patch))
