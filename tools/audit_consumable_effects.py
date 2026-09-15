"""Compare enabled consumable rules with the local Glory FCC archive; never execute FCC."""
import ast
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "starhome_lz_ry_fcc_source/cltobj/stuffclt2.fcc"


def main():
    """Audit each rule including inherited fields against its original class."""
    source = SOURCE.read_text(encoding="utf-8-sig")
    matches = list(re.finditer(r"^class\s+(\w+)\s*:\s*(\w+)", source, re.M))
    classes = {m[1]: (m[2], source[m.end():matches[i + 1].start() if i + 1 < len(matches) else len(source)])
               for i, m in enumerate(matches)}

    def field(name, key):
        parent, body = classes[name]
        found = re.search(r"\b" + key + r"\s*=\s*([^;]+);", body)
        if found:
            return ast.literal_eval(found[1])
        return field(parent, key)

    rules = json.loads((ROOT / "data/gameplay/consumable_effects_v1.json").read_text(encoding="utf-8"))["rules"]
    for definition_id, rule in rules.items():
        name = rule["name"]
        if name not in classes:
            candidates = [key for key, (_, body) in classes.items()
                          if re.search(r'm_sObjName\s*=\s*"' + re.escape(name) + '"', body)]
            assert len(candidates) == 1, (definition_id, name, candidates)
            name = candidates[0]
        if rule["kind"] == "energy":
            assert rule["energy"] == field(name, "m_ncontent"), name
        else:
            assert rule["physical"] == field(name, "m_nAddPhysical"), name
            kinds, values = field(name, "m_szFoodKind"), field(name, "m_szSkillInfo")
            expected = [dict(kind=k, amount=v[0], duration=v[1], cooldown=v[2])
                        for k, v in zip(kinds, values) if k]
            assert rule["effects"] == expected, (name, rule["effects"], expected)
    print(f"CONSUMABLE_SOURCE_AUDIT_OK rules={len(rules)} sha256={hashlib.sha256(SOURCE.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
