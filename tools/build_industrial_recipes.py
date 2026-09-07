"""从荣耀原始表恢复工业配方；不依赖可能漏表的历史汇总目录。"""
import csv
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "starhome_lz_ry_full_parsed/ftc_resources"


def read_table(relative):
    """读取已解包的 GB18030 FCTB 表，返回字段字典列表。"""
    path = SOURCE / relative
    text = path.read_bytes().decode("gb18030")
    lines = [line.strip() for line in text.splitlines() if line.strip()][2:]
    rows = list(csv.reader(lines, skipinitialspace=True))
    clean = lambda row: [cell.strip().strip('"') for cell in row]
    return [dict(zip(clean(rows[0]), clean(row))) for row in rows[1:]]


def build():
    """解析来源与物品身份并生成配方、缺失报告；未知材料禁止伪造数量。"""
    definitions = []
    for path in ["stage3/starter_loadout_v1", "character_items_v1", "material_items_v1",
                 "official_rocket_items_v1", "glory/glory_items_v1"]:
        definitions += json.loads((ROOT / f"data/gameplay/{path}.json").read_text(encoding="utf-8"))["definitions"]
    by_class = {row["source_class"]: row for row in definitions if row.get("source_class")}
    by_name = {}
    for row in sorted(definitions, key=lambda row: row["id"], reverse=True):
        by_name[row["display_name"]] = row
    recipes, excluded = [], []
    extras = []
    by_class["FireGun7"] = by_name["劲弩式火箭"]

    def register_material(name, source_file):
        """登记原表明确声明的普通材料产物，复用已有定义，保留来源。"""
        if name in by_name:
            return
        item = {"id": "industrial_material_" + hashlib.sha256(name.encode()).hexdigest()[:12],
                "kind": "material", "display_name": name, "max_stack": 99,
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

    tables = [("refining", "expanded/zyf/maceine/abstractlist/abstractlist.txt.cab"),
              ("alloy", "expanded/zyf/maceine/alloylist/alloylist.txt.cab"),
              ("maintenance", "expanded/zyf/maceine/alloylistb/alloylistb.txt.cab"),
              ("equipment_manufacturing", "expanded/zyf/maceine/MainEquip/mainequip.txt.cab"),
              ("auxiliary_manufacturing", "decoded/zyf/maceine/AssistEquip.txt.decoded")]
    for station, relative in tables:
        for row in read_table(relative):
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
    text = (SOURCE / relative).read_bytes().decode("gb18030")
    section = text.split("class AbstractFace :", 1)[1].split("style lz_showstuff_fun", 1)[0]
    for ore, level, xp, amount, product, count in re.findall(
            r'\("([^"\n]+)",\s*(\d+),\s*(\d+),\s*(\d+),\s*\(\("([^"\n]+)",\s*(\d+)\)\)\)', section):
        register_material(product, relative)
        add("refining", product, level, count, xp, [(ore, int(amount))], relative, ore)
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
    build()
