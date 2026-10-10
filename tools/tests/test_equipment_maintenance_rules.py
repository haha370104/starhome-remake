"""Verify collector wear generation using local definitions without asset retrieval or writes."""
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_equipment_maintenance_rules as builder

SPACE_ID = "glory_equipment_space_collector_2_6e0591d35a"


class CollectorMaintenanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = builder.read("data/gameplay/glory/glory_items_v1.json")["definitions"]
        cls.runtime = builder.read("data/gameplay/equipment_maintenance_rules_v1.json")
        cls.generated = cls._generate_rules()

    @staticmethod
    def _generate_rules(legacy_overrides=None):
        local_read = builder.read

        def read_local(path):
            if path == "data/world/manufacturing_facilities_v1.json":
                return {"maps": []}
            if path == "data/maps/map_directory.json":
                return {"definitions": {}}
            data = local_read(path)
            if path == "data/gameplay/glory/glory_items_v1.json" and legacy_overrides:
                for row in data["definitions"]:
                    if row["id"] == SPACE_ID:
                        row["stats"]["legacy_properties"].update(legacy_overrides)
            return data

        workspace = mock.Mock()
        workspace.source.return_value = Path("unused.raw")
        workspace.decode.return_value = (Path("unused.decoded"), {"frame_count": 1, "cell_width": 1, "cell_height": 1})
        with mock.patch.object(builder, "RawFccWorkspace") as fcc, mock.patch.object(builder, "read", side_effect=read_local), mock.patch.object(builder, "write") as write, mock.patch.object(Path, "read_bytes", return_value=b""):
            fcc.return_value.__enter__.return_value.text.return_value = ""
            builder.build(workspace, check=True)
        for call in write.call_args_list:
            if call.args[0] == "data/gameplay/equipment_maintenance_rules_v1.json":
                return call.args[1]
        raise AssertionError("maintenance rules were not emitted")

    def test_all_ground_and_space_collectors_receive_wear(self):
        profiles = {row["definition_id"]: row for row in self.generated["equipment"]}
        collectors = [row for row in self.source if int(((row.get("stats") or {}).get("legacy_properties") or {}).get("m_nEquipKind2", -1)) in [4, 102]]
        self.assertEqual(len(collectors), 22)
        self.assertEqual(self.generated["wear_thresholds"]["mining"], 2)
        for row in collectors:
            with self.subTest(definition_id=row["id"]):
                profile = profiles[row["id"]]
                self.assertTrue(profile["wear_enabled"])
                self.assertFalse(profile["no_wear"])
                self.assertEqual(profile["wear_event"], "mining")

    def test_vehicle_body_and_armor_receive_wear_rules(self):
        profiles = {row["definition_id"]: row for row in self.generated["equipment"]}
        thresholds = self.generated["wear_thresholds"]
        self.assertEqual(thresholds["vehicle_damage"], 1)
        self.assertEqual(thresholds["vehicle_movement"], 120)
        for definition_id in [
            "recruit_tank",
            "glory_equipment_frontarmor1_bedd1471a6",
            "glory_equipment_backarmor1_62474fcdc0",
        ]:
            with self.subTest(definition_id=definition_id):
                self.assertTrue(profiles[definition_id]["wear_enabled"])
                self.assertFalse(profiles[definition_id]["no_wear"])

    def test_generated_space_profiles_match_runtime_rules(self):
        generated = {row["definition_id"]: row for row in self.generated["equipment"]}
        runtime = [row for row in self.runtime["equipment"] if row["definition_id"].startswith("glory_equipment_space_collector_")]
        self.assertEqual(len(runtime), 6)
        for row in runtime:
            with self.subTest(definition_id=row["definition_id"]):
                self.assertEqual(generated[row["definition_id"]], row)

    def test_missing_repair_material_does_not_disable_wear(self):
        unresolved = {row["definition_id"]: row["missing_materials"] for row in self.generated["unresolved"]}
        for row in self.generated["equipment"]:
            if not row["definition_id"].startswith("glory_equipment_space_collector_"):
                continue
            with self.subTest(definition_id=row["definition_id"]):
                self.assertEqual(unresolved[row["definition_id"]], ["太空挖掘臂维护包"])
                self.assertFalse(row["regular_allowed"])
                self.assertTrue(row["quick_allowed"])
                self.assertTrue(row["wear_enabled"])

    def test_explicit_no_durability_and_unit_maximum_remain_nonwearing(self):
        for overrides in [{"m_nNoDurable": "1"}, {"m_nMax_Hardiness": "1"}]:
            with self.subTest(overrides=overrides):
                generated = self._generate_rules(overrides)
                profile = next(row for row in generated["equipment"] if row["definition_id"] == SPACE_ID)
                self.assertTrue(profile["no_wear"])
                self.assertFalse(profile["wear_enabled"])


if __name__ == "__main__":
    unittest.main()
