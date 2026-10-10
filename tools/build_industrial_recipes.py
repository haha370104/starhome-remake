"""从荣耀原始表恢复工业配方；不依赖可能漏表的历史汇总目录。"""
import csv
import hashlib
import io
import json
import re
from pathlib import Path

from audit_monster_asset_sources import load_decoder
from build_upgrade_material_supply import MINING_POLICY
from recovery.fcc_workspace import RawFccWorkspace
from material_id_registry import canonical_material_id

ROOT = Path(__file__).resolve().parents[1]
def read_table(workspace, logical_path):
    """读取已解包的 GB18030 FCTB 表，返回字段字典列表。"""
    text = workspace.payload(logical_path).decode("gb18030")
    lines = [line.strip() for line in text.splitlines() if line.strip()][2:]
    rows = list(csv.reader(lines, skipinitialspace=True))
    clean = lambda row: [cell.strip().strip('"') for cell in row]
    return [dict(zip(clean(rows[0]), clean(row))) for row in rows[1:]]


def build(workspace):
    """解析来源与物品身份并生成配方、缺失报告；未知材料禁止伪造数量。"""
    existing = json.loads((ROOT / "data/gameplay/industrial_materials_v1.json").read_text(encoding="utf-8"))["definitions"]
    definitions = []
    for path in ["stage3/starter_loadout_v1", "character_items_v1", "material_items_v1",
                 "official_rocket_items_v1", "glory/glory_items_v1"]:
        definitions += json.loads((ROOT / f"data/gameplay/{path}.json").read_text(encoding="utf-8"))["definitions"]
    by_class = {row["source_class"]: row for row in definitions if row.get("source_class")}
    by_name = {row["display_name"]: row for row in existing}
    for row in definitions:
        by_name.setdefault(row["display_name"], row)
    recipes, excluded = [], []
    extras = existing[:]
    for row in definitions:
        if row["id"].startswith("official_rocket_firegun_"):
            by_class["FireGun" + row["id"].rsplit("_", 1)[1]] = row

    def register_material(name, source_file):
        """登记原表明确声明的普通材料产物，复用已有定义，保留来源。"""
        if name in by_name:
            return
        item = {"id": canonical_material_id(name),
                "kind": "material", "display_name": name, "max_stack": 999 if name in {"钾", "钡镁合金"} else 99,
                "description": "荣耀版提炼／制造材料。", "source_audit": {
                    "source_release": "starhome_lz_ry", "source_file": source_file,
                    "source_class": name, "asset_status": "not_imported"}}
        extras.append(item)
        by_name[name] = item

    def add(station, product, level, count, experience, materials, source_file, source_key):
        """将单条来源记录转换为稳定身份配方，无法解析时记入排除报告。"""
        target = by_class.get(product) or by_name.get(product)
        ingredients = []
        for name, amount in materials:
            item = by_class.get(name) or by_name.get(name)
            if item is None or amount <= 0:
                excluded.append({"product": product, "reason": f"unresolved material: {name}", "source_file": source_file})
                return
            ingredients.append({"definition_id": item["id"], "quantity": amount})
        if target is None or not ingredients:
            excluded.append({"product": product, "reason": "unresolved product or materials", "source_file": source_file})
            return
        identity = hashlib.sha256(f"{source_file}:{source_key}".encode()).hexdigest()[:12]
        recipes.append({"recipe_id": f"industrial_{station}_{identity}", "station_id": station,
                        "display_name": target["display_name"], "product_definition_id": target["id"],
                        "required_skill_level": int(level), "output_quantity": int(count),
                        "skill_id": "refining" if station == "refining" else "manufacturing",
                        "skill_experience": int(experience), "materials": ingredients,
                        "source_audit": {"source_release": "starhome_lz_ry", "source_file": source_file,
                                         "source_key": source_key, "product_class": product}})

    tables = [("refining", "expanded/zyf/maceine/abstractlist/abstractlist.txt.cab", "zyf/maceine/abstractlist.txt"),
              ("alloy", "expanded/zyf/maceine/alloylist/alloylist.txt.cab", "zyf/maceine/alloylist.txt"),
              ("maintenance", "expanded/zyf/maceine/alloylistb/alloylistb.txt.cab", "zyf/maceine/alloylistb.txt"),
              ("equipment_manufacturing", "expanded/zyf/maceine/MainEquip/mainequip.txt.cab", "zyf/maceine/MainEquip.txt"),
              ("auxiliary_manufacturing", "decoded/zyf/maceine/AssistEquip.txt.decoded", "zyf/maceine/AssistEquip.txt")]
    for station, relative, logical_path in tables:
        for row in read_table(workspace, logical_path):
            product = row.get("ProductClass") or row["ProductCN"]
            if station == "maintenance" and any(token in product for token in ["太空", "飞船", "生物能"]):
                excluded.append({"product": product, "reason": "space content out of scope", "source_file": relative})
                continue
            if station in ["refining", "alloy", "maintenance"]:
                register_material(product, relative)
            materials = []
            if "NeedAmount" in row:
                names, amounts = row["NeedStuff"].split("/"), row["NeedAmount"].split("/")
                if len(names) != len(amounts):
                    raise ValueError(f"Mismatched material counts: {product}")
                materials = [(name.strip(), int(amount)) for name, amount in zip(names, amounts)]
            else:
                for part in row.get("NeedStuff", "").split("/"):
                    match = re.fullmatch(r"\s*(.+?)\s+(\d+)\s*", part)
                    materials.append((match[1], int(match[2])) if match else (part, 0))
            add(station, product, row["NeedSkill"], row["GetAmount"], row["GetPoint"],
                materials, relative, row.get("index", product))

    relative = "expanded/zyf/maceine/maceineface/maceineface.fcc.cab"
    text = workspace.payload("zyf/maceine/maceineface.fcc").decode("gb18030")
    section = text.split("class AbstractFace :", 1)[1].split("style lz_showstuff_fun", 1)[0]
    for ore, level, xp, amount, product, count in re.findall(
            r'\("([^"\n]+)",\s*(\d+),\s*(\d+),\s*(\d+),\s*\(\("([^"\n]+)",\s*(\d+)\)\)\)', section):
        register_material(product, relative)
        add("refining", product, level, count, xp, [(ore, int(amount))], relative, ore)

    # 用户指定的扩展与原表分开标记；重建时保留，不能写回原客户端证据。
    source_file = "cltobj/stuffclt2.fcc"
    source_text = workspace.text(source_file)
    source_texts = {source_file: source_text, "ven/stuffclt2_ven.fcc": workspace.text("ven/stuffclt2_ven.fcc"),
                    "cltobj/stuffclt.fcc": workspace.text("cltobj/stuffclt.fcc")}
    strings = {}
    for logical_path in ["great/code_string.fcc", "great/wk_great.fcc"]:
        strings.update(dict(re.findall(r'^#define\s+(\w+)\s+"((?:\\.|[^"\\])*)"',
                                       workspace.text(logical_path), re.M)))
    sprite_ids = {row["logical_id"] for row in json.loads(
        (ROOT / "data/content/glory_sprite_runtime_index_v1.json").read_text(encoding="utf-8"))["sprites"]}

    processed_materials = {
        "接合器升级晶片1级": ("joint_chip_1", "ven/stuffclt2_ven.fcc"),
        "接合器升级晶片2级": ("joint_chip_2", "ven/stuffclt2_ven.fcc"),
        "紫水晶": ("purple_crystal", source_file), "红水晶": ("red_crystal", source_file),
        "蓝水晶": ("blue_crystal", source_file), "绿水晶": ("green_crystal", source_file),
        "面": ("flour", source_file), "糖": ("sugar", source_file), "油": ("cooking_oil", source_file),
        "硫": ("sulfur", source_file), "磷": ("phosphorus", source_file), "钾": ("potassium", source_file),
        "钛": ("titanium", source_file), "钪": ("scandium", source_file), "镁": ("magnesium", source_file),
        "钡": ("barium", source_file),
        "太空棉": "space_cotton", "生物纤维": "biological_fiber", "棉线": "cotton_thread",
        "低级复合胶板": "low_grade_composite_gel_plate", "中级复合胶板": "mid_grade_composite_gel_plate",
        "高级复合胶板": "high_grade_composite_gel_plate", "低级硬质素": "low_grade_hard_substance",
        "中级硬质素": "mid_grade_hard_substance", "高级硬质素": "high_grade_hard_substance",
        "低级聚熔脂": "low_grade_polymer_fat", "中级聚熔脂": "mid_grade_polymer_fat",
        "高级聚熔脂": "high_grade_polymer_fat", "低级敛核酶": "low_grade_nuclear_enzyme",
        "中级敛核酶": "mid_grade_nuclear_enzyme", "高级敛核酶": "high_grade_nuclear_enzyme",
        "锌钛合金": ("zinc_titanium_alloy", source_file), "钡镁合金": ("barium_magnesium_alloy", source_file),
        "锌钡合金": ("zinc_barium_alloy", source_file), "钛铬合金": ("titanium_chromium_alloy", source_file),
        "钪镁合金": ("scandium_magnesium_alloy", source_file),
        "硬质扣": ("hard_substance_buckle", "cltobj/stuffclt.fcc"),
        "催化之尘": ("catalyst_dust", "cltobj/stuffclt.fcc"),
        "厚脂硅皮": ("thick_polymer_silicon_skin", "cltobj/stuffclt.fcc"),
        "密质胶线": ("dense_gel_thread", "cltobj/stuffclt.fcc"),
        "恒金塑脂": ("constant_gold_plastic", "cltobj/stuffclt.fcc"),
        "普通修复石": ("ordinary_repair_stone", "cltobj/stuffclt.fcc"),
        "普通荣耀修复石": ("ordinary_glory_repair_stone", "cltobj/stuffclt.fcc"),
        "普通战神修复石": ("ordinary_warrior_repair_stone", "cltobj/stuffclt.fcc"),
    }

    def restore_processed_material(name, semantic_spec):
        """Replace a generated name-only material with its original description and icon."""
        if isinstance(semantic_spec, tuple):
            semantic, source_file = semantic_spec
        else:
            semantic, source_file = semantic_spec, "cltobj/stuffclt2.fcc"
        source_text = source_texts[source_file]
        original = by_name[name]
        body = re.search(r"^class " + re.escape(name) + r":.*?(?=^class |\Z)", source_text, re.M | re.S)
        if body is None:
            raise ValueError(f"Missing Glory material class: {name}")
        description_match = re.search(r'\bm_sDesc\s*=\s*(?:"([^"]*)"|(\w+))', body[0])
        description_key = description_match[2] if description_match[2] else ""
        description = description_match[1] if description_match[1] else strings[description_key]
        source_path = re.search(r'src=\$\+"../([^"\n]+)"', body[0])[1]
        source = ROOT / "../starhome_lz_ry_full/raw" / source_path
        sprite = decoder.AleFile(source)
        if len(sprite.frames) != 1:
            raise ValueError(f"Expected one frame for {name}")
        frame = sprite.frames[0].image
        buffer = io.BytesIO()
        frame.save(buffer, format="PNG", optimize=True)
        target = ROOT / "assets/items/materials/industrial" / (semantic + ".png")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(buffer.getvalue())
        item = {
            "id": original["id"], "kind": "material", "display_name": name,
            "description": description, "max_stack": original.get("max_stack", 99),
            "evidence_roles": original.get("evidence_roles", []),
            "presentation": {"inventory": {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(frame.size)},
                            "world": {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(frame.size)}},
            "source_audit": {"source_release": "starhome_lz_ry", "source_file": source_file,
                             "source_class": name, "source_line": source_text.count("\n", 0, body.start()) + 1,
                             "description_source": source_file if not description_key else ("great/code_string.fcc" if description_key.startswith("String") else "great/wk_great.fcc"),
                             "description_string": description_key or description, "source_path": source_path,
                             "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                             "asset_status": "restored_original"},
            "source_class": name, "replaces_name_only": True,
        }
        for index, current in enumerate(extras):
            if current["id"] == item["id"]:
                extras[index] = item
                break
        else:
            extras.append(item)
        by_name[name] = item

    decoder = load_decoder()
    for name, semantic in processed_materials.items():
        restore_processed_material(name, semantic)

    def register_extension(name):
        """复用荣耀已收录的本体图，补齐原客户端明确存在但漏登记的材料。"""
        register_material(name, source_file)
        item = by_name[name]
        if "inventory" in item.get("presentation", {}):
            return
        body = re.search(r"^class " + re.escape(name) + r":.*?(?=^class |\Z)", source_text, re.M | re.S)
        if body is None:
            raise ValueError(f"Missing Glory material class: {name}")
        sprite = re.search(r'src=\$\+"../([^"\n]+)"', body[0])[1].lower().removesuffix(".ale")
        if sprite not in sprite_ids:
            raise ValueError(f"Missing indexed Glory material sprite: {name}: {sprite}")
        item["source_class"] = name
        item["presentation"] = {"ale_reference": sprite}
        item["source_audit"].update({"asset_status": "existing_glory_sprite_index", "source_line": source_text.count("\n", 0, body.start()) + 1})

    policy_source = "remake:industrial-supply-2026-09-15"
    for element in ("硫", "磷", "钾", "钛", "钪", "镁", "钡"):
        register_extension(element)
        level = MINING_POLICY[element + "矿"][0]
        add("refining", element, level, 1, max(1, level // 5 + 10), [(element + "矿", 10)], policy_source, element)
        recipes[-1]["source_audit"].update({"rule_status": "user_requested_remake", "rule": "10 ore to 1 element; refining level equals mining level"})

    refining_levels = {row["display_name"]: row["required_skill_level"] for row in recipes if row["station_id"] == "refining"}
    for name, parts in {"锌钛合金": ("锌", "钛"), "钡镁合金": ("钡", "镁"),
                        "锌钡合金": ("锌", "钡"), "钛铬合金": ("钛", "铬"), "钪镁合金": ("钪", "镁")}.items():
        register_extension(name)
        # 参照镭铬/镍锌的提炼270、制造300：新合金取最高原料提炼等级的下一档50级。
        level = (max(refining_levels[part] for part in parts) // 50 + 1) * 50
        add("alloy", name, level, 1, level // 5 + 20, [(part, 1) for part in parts], policy_source, name)
        recipes[-1]["source_audit"].update({"rule_status": "remake_default", "rule": "one of each constituent; next 50-level band above highest constituent refining level; original recipes unchanged"})
    payload = {"schema_version": 1, "recipes": recipes, "excluded": excluded,
               "execution_policy": "复刻首版：等级达标后单次确定产出；原服务器加工耗时、失败概率与批量倍率尚未恢复。"}
    output = ROOT / "data/gameplay/industrial_recipes_v1.json"
    # 每条记录一行，便于 review 与确定性重生成。
    output.write_text('{"schema_version":1,"execution_policy":' + json.dumps(payload["execution_policy"], ensure_ascii=False)
                      + ',"recipes":[\n' + ',\n'.join(json.dumps(row, ensure_ascii=False) for row in recipes)
                      + '\n],"excluded":' + json.dumps(excluded, ensure_ascii=False) + '}\n', encoding="utf-8")
    (ROOT / "data/gameplay/industrial_materials_v1.json").write_text(
        '{"definitions":[\n' + ',\n'.join(json.dumps(row, ensure_ascii=False) for row in extras) + '\n]}\n', encoding="utf-8")
    print(f"Industrial recipes: {len(recipes)}, excluded: {len(excluded)}")
    for row in excluded:
        print(row)


if __name__ == "__main__":
    with RawFccWorkspace() as workspace:
        build(workspace)
