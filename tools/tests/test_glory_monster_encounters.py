"""Verify source-name joins and evidence-only field encounter semantics."""
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

    def build(self, **overrides):
        arguments = dict(rows=self.rows, relations=self.relations, map_index=self.index,
                         known_maps=self.known, class_names=self.names)
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

    def test_only_recovered_fields_are_configured(self):
        encounters, _ = self.build()
        field_sources = {row["id"] for row in self.known["definitions"] if row["category"] == "field_code"}
        runtime_fields = {row["runtime_id"] for row in self.index["runtime_maps"] if row["source_id"] in field_sources}
        actual = {row["map_id"] for row in encounters}
        self.assertEqual(len(runtime_fields), 460)
        self.assertEqual(len(actual), 27)
        self.assertTrue(actual < runtime_fields)
        self.assertNotIn("glory_nft_bl_b02", actual)
        self.assertTrue(all(row["distribution_evidence"] == "client_editor_placement" for row in encounters))
        valid = {builder.runtime_id(int(row["index"])) for row in self.rows}
        for encounter in encounters:
            self.assertEqual(encounter["population_policy"], builder.POPULATION_POLICY)
            self.assertTrue(all(group["monster_id"] in valid for group in encounter["spawn_groups"]))

    def test_e07_uses_only_its_recovered_species(self):
        encounters = {row["map_id"]: row for row in self.build()[0]}
        expected = {"om_adult", "om_larva", "photosensitive_orb"}
        for map_id in ["glory_nft_bl_e07", "glory_nft_bt_e07"]:
            actual = {row["monster_id"] for row in encounters[map_id]["spawn_groups"]}
            self.assertEqual(actual, expected)
            self.assertNotIn("toxic_gel", actual)

    def test_ambiguous_name_is_not_silently_joined(self):
        duplicate = next(row.copy() for row in self.rows if row["index"] == "4")
        duplicate["index"] = "999"
        _, joins = self.build(rows=self.rows + [duplicate])
        self.assertNotIn("Npc成虫1", [row["monster_class"] for row in joins])


if __name__ == "__main__":
    unittest.main()
