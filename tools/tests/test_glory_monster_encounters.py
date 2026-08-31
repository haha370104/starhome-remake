"""Verify source-name joins and explicit field-only fallback semantics."""
import copy
import csv
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_glory_monster_runtime_catalog as builder

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT.parent / "starhome_lz_ry_full_parsed"


class EncounterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with (SOURCE / "catalogs_utf8/npc_catalog.csv").open(encoding="utf-8-sig", newline="") as stream:
            cls.rows = list(csv.DictReader(stream))
        cls.relations = builder.read_json(SOURCE / "catalogs/monsters/glory_monster_map_relations.json")
        cls.index = builder.read_json(ROOT / "data/content/glory_map_runtime_index_v1.json")
        cls.known = builder.read_json(ROOT / "data/content/known_maps_v1.json")
        cls.names = builder.recover_class_names(ROOT.parent / "starhome_lz_ry_fcc_source")
        cls.defaults = builder.read_json(ROOT / "data/gameplay/glory/field_population_defaults_v1.json")

    def build(self, **overrides):
        arguments = dict(rows=self.rows, relations=self.relations, map_index=self.index,
                         known_maps=self.known, class_names=self.names, defaults=self.defaults)
        arguments.update(overrides)
        return builder.build_encounters(**arguments)

    def test_all_classes_have_exact_names_not_palette_aliases(self):
        encounters, joins = self.build()
        joined = {row["monster_class"]: row for row in joins}
        self.assertEqual(len(joins), 20)
        for name, expected in [("Npc成虫1", 4), ("NpcLightBall1", 2), ("Npc幼虫1", 3),
                               ("Npc蠕虫1", 13), ("Npc机甲A1", 28), ("NpcFire", 36)]:
            self.assertEqual(joined[name]["npc_index"], expected)
            self.assertGreater(joined[name]["source_name_resolution"]["source_string_line"], 0)
        reversed_result = self.build(rows=list(reversed(self.rows)))
        self.assertEqual((encounters, joins), reversed_result)

    def test_all_fields_and_no_towns(self):
        encounters, _ = self.build()
        field_sources = {row["id"] for row in self.known["definitions"] if row["category"] == "field_code"}
        expected = {row["runtime_id"] for row in self.index["runtime_maps"] if row["source_id"] in field_sources}
        actual = {row["map_id"] for row in encounters} | {"d04_field_zone"}
        self.assertEqual(actual, expected)
        self.assertEqual(len(actual), 460)
        self.assertEqual(len(encounters), len(actual) - 1)
        self.assertEqual(sum(row["distribution_evidence"] == "client_editor_placement" for row in encounters), 27)
        self.assertEqual(sum(row["distribution_evidence"] == "remake_default" for row in encounters), 432)
        valid = {builder.runtime_id(int(row["index"])) for row in self.rows}
        for encounter in encounters:
            self.assertEqual(encounter["population_policy"], builder.POPULATION_POLICY)
            self.assertTrue(all(group["monster_id"] in valid for group in encounter["spawn_groups"]))

    def test_defaults_are_configurable_but_do_not_leak_into_recovered_maps(self):
        defaults = copy.deepcopy(self.defaults)
        defaults["spawn_groups"] = [{"monster_id": "om_larva", "weight": 3.0}]
        encounters, _ = self.build(defaults=defaults)
        baseline = {row["map_id"]: row for row in self.build()[0]}
        for encounter in encounters:
            if encounter["distribution_evidence"] == "client_editor_placement":
                self.assertEqual(encounter, baseline[encounter["map_id"]])
            else:
                self.assertEqual(len(encounter["spawn_groups"]), 1)
                self.assertEqual(encounter["spawn_groups"][0]["weight"], 3.0)
                self.assertFalse(encounter["source_monster_classes"])

    def test_invalid_default_species_weight_or_duplicate_is_rejected(self):
        for groups in [[], [{"monster_id": "missing", "weight": 1}],
                       [{"monster_id": "om_adult", "weight": 0}],
                       [{"monster_id": "om_adult", "weight": 1}] * 2]:
            with self.assertRaises(ValueError):
                self.build(defaults={"spawn_groups": groups})

    def test_ambiguous_name_is_not_silently_joined(self):
        duplicate = next(row.copy() for row in self.rows if row["index"] == "4")
        duplicate["index"] = "999"
        _, joins = self.build(rows=self.rows + [duplicate])
        self.assertNotIn("Npc成虫1", [row["monster_class"] for row in joins])


if __name__ == "__main__":
    unittest.main()
