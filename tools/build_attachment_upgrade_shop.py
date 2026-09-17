"""Register seven Glory materials and price every supported joint upgrade stage."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "starhome_lz_ry_fcc_source"
MATERIALS = {
    "NewJointImpactChip": ("冲击晶体", 300, "ven/stuffclt2_ven.fcc"),
    "NewJointBody": ("接合器升级晶体", 600, "ven/stuffclt2_ven.fcc"),
    "SuperNewJointImpactBody": ("高级冲击晶体", 300, "ven/stuffclt2_ven.fcc"),
    "紫陀金": ("紫陀金", 300, "cltobj/stuffclt2.fcc"),
    "锟晶体": ("锟晶体", 300, "cltobj/stuffclt2.fcc"),
    "质子磁暴甲": ("质子磁暴甲", 300, "cltobj/stuffclt2.fcc"),
    "ProcessStone": ("加工石", 600, "ven/stuffclt2_ven.fcc"),
}
NEW = ("NewGunJoint", "NewFireGunJoint", "NewMilliseJoint", "NewLifeJoint")
OLD = ("HuoLiJieHeQi", "ShengMingJieHeQi", "XunJieJieHeQi", "WaJueJieHeQi", "ZhenCeJieHeQi")


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def write(path, rows, key="definitions"):
    (ROOT / path).write_text('{"schema_version":1,"' + key + '":[\n' + ',\n'.join(
        json.dumps(row, ensure_ascii=False) for row in rows) + '\n]}\n', encoding="utf-8")


def build():
    """Keep source identities, preserve non-premium costs, and rebalance only purchased materials."""
    items = [row for path in ("stage3/starter_loadout_v1", "character_items_v1", "material_items_v1",
             "official_rocket_items_v1", "glory/glory_items_v1", "industrial_materials_v1")
             for row in read(f"data/gameplay/{path}.json")["definitions"]]
    by_class = {row["source_class"]: row for row in items if row.get("source_class")}
    by_name = {row["display_name"]: row for row in sorted(items, key=lambda row: row["id"], reverse=True)}
    for row in items:
        if row["id"] in ("low_grade_gel", "low_grade_energy_catalyst", "low_grade_biosilicon", "low_grade_quadruped_shell"):
            by_name[row["display_name"]] = row
    sprites = {row["logical_id"] for row in read("data/content/glory_sprite_runtime_index_v1.json")["sprites"]}
    recovered = {row['logical_id']: row for row in read('data/content/recovered_sprite_runtime_index_v1.json')['sprites']}
    sprites.update(recovered)
    definitions, ids, prices = [], {}, {}
    for source_class, (name, price, file) in MATERIALS.items():
        source = (SOURCE / file).read_text(encoding="utf-8-sig")
        match = re.search(r"^class " + re.escape(source_class) + r":.*?(?=^class |\Z)", source, re.M | re.S)
        assert match, source_class
        reference = re.search(r'src=\$\+"../([^"\n]+)"', match[0])[1].lower().removesuffix(".ale")
        previous = by_name.get(source_class)
        item_id = previous["id"] if previous else "upgrade_material_" + hashlib.sha256(source_class.encode()).hexdigest()[:12]
        row = {"id": item_id, "kind": "material", "display_name": name, "source_class": source_class,
               "max_stack": 99, "premium_category": "upgrade_material", "description": f"接合器升级材料：{name}。",
               "source_audit": {"source_release": "starhome_lz_ry", "source_file": file,
                   "source_line": source.count("\n", 0, match.start()) + 1, "source_asset": reference + ".ale"}}
        if previous:
            assert previous.get("source_audit", {}).get("status") == "name_only"
            row["replaces_name_only"] = True
        if reference in sprites:
            row["presentation"] = {"ale_reference": reference}
            if reference in recovered:
                row['presentation']['source_release'] = recovered[reference]['source_release']
                row['source_audit']['replacement_source'] = recovered[reference]['source_release']
        else:
            assert source_class == "ProcessStone", reference
            row["source_audit"]["asset_status"] = "local_missing_and_official_exact_path_404"
            row["presentation"] = {"icon": "res://assets/items/materials/processing_stone/icon.png"}
            row["source_audit"]["replacement_source"] = "remake_generated_user_authorized_2026-09-15"
        definitions.append(row)
        ids[source_class] = item_id
        prices[item_id] = price
    write("data/gameplay/commerce/attachment_upgrade_materials_v1.json", definitions)
    shop = read("data/gameplay/commerce/premium_shop_v1.json")
    shop["offers"] = [row for row in shop["offers"] if row["definition_id"] not in prices]
    shop["offers"] += [{"definition_id": item_id, "price": price} for item_id, price in prices.items()]
    (ROOT / "data/gameplay/commerce/premium_shop_v1.json").write_text(json.dumps(shop, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    source = (SOURCE / "ven/SynthesizeNPC.fcc").read_text(encoding="utf-8-sig")
    rules = []
    for source_class in (*NEW, *OLD):
        coefficient = 1800 if source_class in ("NewGunJoint", "HuoLiJieHeQi") else 1200 if source_class == "NewFireGunJoint" else 1500
        for level in range(5 if source_class in NEW else 4):
            normal, premium, currency = [], [], 0
            budget = max(level, 1) * coefficient
            if source_class in NEW:
                if level < 2:
                    normal = [{"definition_id": by_name[f"接合器升级晶片{level + 1}级"]["id"], "quantity": 1}]
                    premium = [{"definition_id": ids["NewJointImpactChip"], "quantity": budget // 300}]
                else:
                    premium = [{"definition_id": ids["NewJointBody"], "quantity": 1},
                               {"definition_id": ids["SuperNewJointImpactBody"], "quantity": (budget - 600) // 300}]
            else:
                lines = [line for line in source.splitlines() if re.search(r'\(\d+,\(\("' + re.escape(source_class) + '",' + str(level) + ',1,', line)]
                assert len(lines) == 1, (source_class, level, len(lines))
                premium_classes = []
                for name, amount in re.findall(r'\("([^"]+)",-1,(\d+),', lines[0]):
                    if name == "money":
                        currency = int(amount)
                    elif name in MATERIALS:
                        premium_classes.append(name)
                    else:
                        normal.append({"definition_id": by_name[name]["id"], "quantity": int(amount)})
                if "ProcessStone" in premium_classes:
                    premium.append({"definition_id": ids["ProcessStone"], "quantity": 1})
                    budget -= 600
                    premium_classes.remove("ProcessStone")
                assert len(premium_classes) == 2
                count = budget // 300
                for index, name in enumerate(premium_classes):
                    premium.append({"definition_id": ids[name], "quantity": count // 2 + (count % 2 if index == 0 else 0)})
            rules.append({"attachment_id": by_class[source_class]["id"], "current_level": level,
                          "target_level": level + 1, "coefficient": coefficient,
                          "premium_materials": premium, "normal_materials": normal, "currency": currency,
                          "source_audit": "remake quantities: max(current level,1)*coefficient; original material roles retained; authoritative single-level upgrade"})
    assert len(rules) == 40
    write("data/gameplay/commerce/attachment_upgrade_costs_v1.json", rules, "rules")
    print(f"Upgrade shop: {len(definitions)} materials, {len(rules)} stage rules")


if __name__ == "__main__":
    build()
