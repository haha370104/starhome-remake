"""Verify source-name joins and designed field encounter semantics."""
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

    def test_all_fields_receive_bounded_designed_populations(self):
        encounters, _ = self.build()
        field_sources = {row["id"] for row in self.known["definitions"] if row["category"] == "field_code"}
        runtime_fields = {row["runtime_id"] for row in self.index["runtime_maps"] if row["source_id"] in field_sources}
        actual = {row["map_id"] for row in encounters}
        self.assertEqual(len(runtime_fields), 460)
        self.assertEqual(len(actual), 459)
        self.assertEqual(runtime_fields - actual, {"d04_field_zone"})
        self.assertIn("glory_nft_bl_b02", actual)
        self.assertTrue(all(row["distribution_evidence"] == "design_inferred_radial_ecology" for row in encounters))
        valid = {builder.runtime_id(int(row["index"])) for row in self.rows}
        for encounter in encounters:
            self.assertEqual(encounter["population_policy"], builder.POPULATION_POLICY)
            self.assertGreaterEqual(len(encounter["spawn_groups"]), 3)
            self.assertLessEqual(len(encounter["spawn_groups"]), 5)
            self.assertTrue(all(group["monster_id"] in valid for group in encounter["spawn_groups"]))
            allowed = set(encounter["progression"]["allowed_tiers"])
            self.assertTrue(all(group["progression_tier"] in allowed for group in encounter["spawn_groups"]))

    def test_recovered_relations_are_retained_as_supporting_evidence(self):
        encounters = {row["map_id"]: row for row in self.build()[0]}
        for map_id in ["glory_nft_bl_e07", "glory_nft_bt_e07"]:
            evidence = encounters[map_id]["supporting_client_evidence"]
            self.assertEqual(evidence["kind"], "historical_client_editor_placement")
            self.assertEqual(set(evidence["monster_ids"]), {"om_adult", "om_larva", "photosensitive_orb"})

    def test_radial_tiers_and_regional_tiers_are_deterministic(self):
        self.assertEqual(builder.field_progression("map:nft_bl/d04")["danger_tier"], 1)
        self.assertEqual(builder.field_progression("map:nft_bl/c03")["danger_tier"], 2)
        self.assertEqual(builder.field_progression("map:nft_bl/b02")["danger_tier"], 3)
        self.assertEqual(builder.field_progression("map:nft_bl/i09")["danger_tier"], 6)
        self.assertEqual(builder.field_progression("map:nft_bl/ym_c03")["danger_tier"], 8)
        self.assertEqual(builder.field_progression("map:nft_bl/ym_b02")["danger_tier"], 10)

    def test_user_confirmed_progression_tiers(self):
        tiers = {index: tier for tier, members in builder.MONSTER_TIERS.items() for index, _ in members}
        self.assertEqual({index: tiers[index] for index in [1, 2, 3, 4]}, {1: 1, 2: 1, 3: 1, 4: 1})
        self.assertEqual({index: tiers[index] for index in [5, 6, 7, 8]}, {5: 2, 6: 2, 7: 2, 8: 2})
        self.assertEqual({index: tiers[index] for index in [9, 10, 11, 12]}, {9: 3, 10: 3, 11: 3, 12: 3})
        self.assertEqual({index: tiers[index] for index in [13, 14, 15, 16]}, {13: 4, 14: 4, 15: 4, 16: 4})

    def test_new_ordinary_species_and_separate_elite_pools(self):
        encounters, _ = self.build()
        active = {g["monster_id"] for e in encounters for g in e["spawn_groups"]}
        self.assertEqual(len(active), 59)
        self.assertTrue({builder.runtime_id(i) for i in range(48, 60)} <= active)
        elite_ids = {builder.runtime_id(i) for i in [*range(60, 66), *range(97, 111)]}
        elite_maps = [e for e in encounters if e["progression"]["danger_tier"] == 10]
        self.assertEqual(len(elite_maps), 24)
        for encounter in encounters:
            if encounter not in elite_maps:
                self.assertNotIn("elite_spawn_groups", encounter)
                continue
            self.assertEqual({g["monster_id"] for g in encounter["elite_spawn_groups"]}, elite_ids)
            self.assertEqual(encounter["elite_population_policy"],
                             dict(maximum_population=30, replenish_interval_seconds=600))
        self.assertFalse(active & elite_ids)

    def test_ambiguous_name_is_not_silently_joined(self):
        duplicate = next(row.copy() for row in self.rows if row["index"] == "4")
        duplicate["index"] = "999"
        _, joins = self.build(rows=self.rows + [duplicate])
        self.assertNotIn("Npc成虫1", [row["monster_class"] for row in joins])


if __name__ == "__main__":
    unittest.main()
