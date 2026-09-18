"""Compile audited Sama growth rules and original material/effect artwork."""
import argparse
import hashlib
import io

import audit_monster_asset_sources as indexed
from build_equipment_processing_rules import ROOT, read, write


def build(check=False):
    definitions = read("data/gameplay/glory/glory_items_v1.json")["definitions"]
    profiles, offers, items, frames = [], [], [], []
    decoder = indexed.load_decoder()
    for suffix, location, effect in [("JNQ", 19, "piercing"), ("MCQ", 20, "pulse"),
                                     ("HBQ", 21, "fission"), ("RLQ", 22, "pvp_absorption")]:
        row = next(r for r in definitions if r.get("source_class") == "SaMa" + suffix)
        profiles.append({"definition_id": row["id"], "location": location, "effect": effect})
        for color, price in enumerate([20000, 50000, 100000, 200000]):
            offers.append({"id": row["id"] + "_" + str(color), "definition_id": row["id"], "color": color, "unit_price": price})

    def icon(release, logical, name, all_frames=False):
        source = ROOT.parent / (release + "_full/raw") / logical
        ale = decoder.AleFile(source)
        paths = []
        for index, frame in enumerate(ale.frames if all_frames else ale.frames[:1]):
            bitmap = ale.decode_frame(frame)
            buffer = io.BytesIO()
            bitmap.save(buffer, format="PNG", optimize=True)
            target = ROOT / "assets/items/sama" / (name + ("_%02d" % index if all_frames else "") + ".png")
            if check: assert target.read_bytes() == buffer.getvalue(), target
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(buffer.getvalue())
            frames.append({"file": target.name, "source_release": release, "source_path": logical,
                           "source_frame": index, "native_size": list(bitmap.size), "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
            paths.append("res://" + target.relative_to(ROOT).as_posix())
        return paths

    for classname, name, label, bound, price, use in [
        ("DynamicCore", "dynamic_core", "远征军动力核心", False, 100, "提升撒玛装备成长阶段"),
        ("CapacityCore", "capacity_core", "远征军智能核心", True, 1000, "提升撒玛装备品质；使用后装备绑定"),
        ("MaintainWrap", "maintenance_pack", "远征军装备维护包", False, 500, "维护撒玛装备耐久；每次需要20个"),
    ]:
        path = icon("starhome_lz_fr", f"pic2/Restore/{classname}.ale", name)[0]
        identifier = "sama_" + name
        items.append({"id": identifier, "kind": "material", "display_name": label,
                      "description": use + "。", "max_stack": 999, "bound": bound, "source_class": classname,
                      "presentation": {"icon": path, "native_size": frames[-1]["native_size"]}})
        offers.append({"id": identifier, "definition_id": identifier, "color": 0, "unit_price": price})
    visuals = {}
    for name, logical, animated in [("piercing", "JNCT", False), ("fission", "HBFY", False),
                                     ("pulse_start", "MSAni/JNCT-1", True), ("pulse_end", "MSAni/JNCT-2", True)]:
        visuals[name] = icon("starhome_lz_ry", "pic3/stageskill/" + logical + ".ale", name, animated)
    write("assets/items/sama/manifest.json", {"frames": frames}, check)
    write("data/gameplay/sama_items_v1.json", {"schema_version": 1, "definitions": items}, check)
    write("data/gameplay/sama_rules_v1.json", {
        "schema_version": 1, "profiles": profiles, "offers": offers, "visuals": visuals,
        "color_caps": [1, 3, 6, 10], "color_health": [25, 50, 75, 100], "color_attack": [3, 5, 8, 10],
        "growth_health": 10, "quality_health": 30, "growth_attack": 1, "quality_attack": 3,
        "growth_costs": [5, 10, 20, 40, 60, 80, 110, 140, 170, 200], "quality_cost": 6, "transfer_amethyst": 1000,
        "materials": {"growth": "sama_dynamic_core", "quality": "sama_capacity_core"},
        "chance_percent": [1, 3, 5, 8], "duration_seconds": [1, 3, 5, 8],
        "duration_additions": [0, 0, 1, 2, 4, 6, 8, 11, 14, 17, 20],
        "damage_base": [10, 30, 50, 80], "pulse_additions": [0, 0, 30, 40, 60, 80, 100, 130, 160, 190, 220],
        "fission_additions": [0, 0, 8, 10, 15, 20, 25, 33, 40, 48, 55], "pulse_range": 400,
        "source": "Glory appendequipcltclass 3248-4121; FormClass_ven 24138-25003; stuffclt2 24545-24582; bullet 2371-2437; Mainclient_Char_gwb 2614-2680; npcbasecltmain 138",
        "remake_policy": "Original permanent stats /100 (rounded), skill damage /1000 (rounded), original chances/durations/caps/costs. Workshop sells four original colors and cores for coins until P7 activity supplies. Transfer destroys donor, overwrites recipient growth/quality, requires same or higher recipient color, costs 1000 amethyst. PVP-only absorption deferred. No invented color upgrade.",
    }, check)
    print(f"Sama: 4 bodies / 16 color offers, 2 cores + maintenance pack, {len(frames)} original frames")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
